import Foundation

/// Performs a single sender's unsubscribe, following the RFC 2369/8058 chain:
/// one-click POST → GET → mailto:. Returns an honest outcome — the design and
/// spec both insist the UI must not claim success it cannot prove.
public struct UnsubscribeEngine: Sendable {
    public enum Outcome: Sendable, Equatable {
        /// A human saw the sender's own confirmation page. Never produced by
        /// this engine — an HTTP status can't prove an unsubscribe took effect,
        /// so the automated paths all report `requested`. Only the browser flow
        /// (`AppModel.recordManual`) can promote an outcome to confirmed.
        case confirmed(detail: String)
        /// Accepted but unverifiable — a plain GET link, or a POST that returned
        /// a non-committal status. May still have worked.
        case requested(detail: String)
        case failed(detail: String)
        /// Nothing was sent, and the caller should hand this to the manual
        /// flow. Carries why, because "no unsubscribe link" and "we can't send
        /// as the address this was delivered to" need different responses.
        case needsManual(reason: String)

        public var isSuccess: Bool {
            if case .failed = self { return false }
            if case .needsManual = self { return false }
            return true
        }
    }

    /// Sends the mailto: variant. Injected so the caller supplies the SMTP-backed
    /// implementation (the backend) without this type depending on it.
    public typealias MailSender = @Sendable (
        _ to: String, _ subject: String, _ body: String, _ from: String?
    ) async throws -> Void

    /// Not `URLSession`: it resolves hostnames itself, which is the whole defect
    /// (see `PinnedHTTPClient`). Injectable so tests can pin at a local server.
    private let client: PinnedHTTPClient
    private let sendMail: MailSender

    public init(sendMail: @escaping MailSender, client: PinnedHTTPClient = PinnedHTTPClient()) {
        self.sendMail = sendMail
        self.client = client
    }

    /// The one message for every way a destination can be refused — private,
    /// loopback, link-local, unresolvable, or not http(s). They are one thing to
    /// the user, and spelling out which would tell a hostile sender which of
    /// their probes landed.
    private static let blockedDetail =
        "unsubscribe URL resolves to a private or local address; blocked"

    /// Unsubscribe from one message's target.
    /// `fromAddress` is the send-as alias for mailto:, when the mail was
    /// delivered to a non-primary address.
    public func run(
        _ unsubscribe: ListUnsubscribe,
        fromAddress: String? = nil
    ) async -> Outcome {
        // Prefer HTTP: it's silent and needs no From address.
        if let url = unsubscribe.webTargets.first {
            let host = url.host ?? "?"
            let outcome: Outcome
            if unsubscribe.supportsOneClick {
                Log.unsubscribe.detail("one-click POST -> \(host)")
                outcome = await oneClickPost(url)
            } else {
                Log.unsubscribe.detail("GET -> \(host)")
                outcome = await get(url)
            }
            // Only fall through to mailto: when the web attempt actually failed.
            // RFC 2369 lists targets in the sender's order of preference, so a
            // dead link shouldn't end the attempt when they also published an
            // address — which is the chain the README documents.
            guard case .failed = outcome, !unsubscribe.mailtoTargets.isEmpty else {
                return outcome
            }
            Log.unsubscribe.detail("web target failed; falling back to mailto")
        }
        if let mail = unsubscribe.mailtoTargets.first {
            Log.unsubscribe.detail("mailto -> \(mail.address)\(fromAddress.map { " (from \($0))" } ?? "")")
            do {
                try await sendMail(mail.address, mail.subject, mail.body, fromAddress)
                // Sending the email is not proof the sender honoured it.
                return .requested(detail: "unsubscribe email sent, unverifiable")
            } catch {
                return .failed(detail: error.localizedDescription)
            }
        }
        return .needsManual(reason: "no unsubscribe link")
    }

    // MARK: - HTTP

    /// A 3xx surviving to the final response means `PinnedHTTPClient` refused to
    /// follow it — it follows every redirect it is willing to, so the only way a
    /// 3xx reaches us is that the next hop failed the guard. Without this it
    /// fell under `code < 400` and an SSRF attempt was recorded as a successful
    /// unsubscribe, moving the sender out of the working list.
    private static func blockedRedirect(_ code: Int) -> Outcome? {
        guard (300..<400).contains(code) else { return nil }
        return .failed(
            detail: "redirected to a private or local address; blocked (HTTP \(code))")
    }

    private func oneClickPost(_ url: URL) async -> Outcome {
        // The guard runs inside the client, on the single lookup whose answer is
        // also the address dialled. Checking here as well would be a second
        // resolution — which is the bug this fix exists to remove.
        let result = await client.send(
            method: "POST",
            url: url,
            headers: [
                "Content-Type": "application/x-www-form-urlencoded",
                "User-Agent": AppVersion.userAgent,
            ],
            body: Data("List-Unsubscribe=One-Click".utf8))

        switch result {
        case .success(let response):
            // A 2xx on a one-click POST means the request was *accepted*, not
            // that the unsubscribe took effect — we don't read the body, and
            // endpoints routinely 200 without acting. "Confirmed" is reserved
            // for a human verifying the sender's page (the browser flow). The
            // real safety net is reappearance detection, which fires regardless.
            if let blocked = Self.blockedRedirect(response.statusCode) { return blocked }
            if response.statusCode < 400 {
                return .requested(
                    detail: "one-click accepted (HTTP \(response.statusCode)), unverifiable")
            }
            return .failed(detail: "endpoint returned HTTP \(response.statusCode)")
        case .failure(let failure):
            return Self.outcome(for: failure, url: url, verb: "one-click POST")
        }
    }

    /// Map a transport-level failure onto the engine's vocabulary. A refused
    /// destination and a broken connection are different things and must not
    /// read the same, since only one of them means someone tried something.
    private static func outcome(
        for failure: PinnedHTTPClient.Failure, url: URL, verb: String
    ) -> Outcome {
        switch failure {
        case .blocked(let host):
            Log.unsubscribe.problem("blocked \(verb) to non-public host: \(host)")
            return .failed(detail: blockedDetail)
        case .tooManyRedirects:
            return .failed(detail: "too many redirects")
        case .malformedResponse:
            return .failed(detail: "unreadable response from \(url.host ?? "the endpoint")")
        case .transport(let message):
            return .failed(detail: message)
        }
    }

    /// Heuristic: does this page text (plus URL) read like a *completed*
    /// unsubscribe confirmation? Used by the browser sheet to offer marking it
    /// confirmed. Matches specific past-tense confirmation phrases rather than a
    /// loose keyword combination, to avoid firing on pages that merely mention
    /// unsubscribing or ask you to confirm. Conservative — the user still decides.
    public static func looksLikeConfirmation(_ rawText: String) -> Bool {
        let text = rawText.lowercased()
        let phrases = [
            "you have been unsubscribed", "you've been unsubscribed",
            "you're unsubscribed", "you are unsubscribed",
            "successfully unsubscribed", "unsubscribed successfully", "unsubscribe successful",
            "will no longer receive", "no longer receive these",
            "has been removed", "have been removed", "successfully removed",
            "removed from the list", "removed from this list",
            "opted out", "your email preferences have been updated",
        ]
        return phrases.contains { text.contains($0) }
    }

    private func get(_ url: URL) async -> Outcome {
        let result = await client.send(
            method: "GET", url: url, headers: ["User-Agent": AppVersion.userAgent])

        switch result {
        case .success(let response):
            if let blocked = Self.blockedRedirect(response.statusCode) { return blocked }
            if response.statusCode < 400 {
                // A GET only proves the page loaded, never that it unsubscribed —
                // hence "requested", not "confirmed".
                return .requested(
                    detail: "page loaded (HTTP \(response.statusCode)), unverifiable")
            }
            return .failed(detail: "page returned HTTP \(response.statusCode)")
        case .failure(let failure):
            return Self.outcome(for: failure, url: url, verb: "GET")
        }
    }
}
