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
        /// No usable target; the caller should fall back to opening webmail.
        case needsManual

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

    private let session: URLSession
    private let sendMail: MailSender

    public init(sendMail: @escaping MailSender, session: URLSession? = nil) {
        self.sendMail = sendMail
        self.session = session ?? Self.guardedSession
    }

    /// A session whose redirects are re-validated by `DestinationGuard`, so a
    /// public URL can't 30x-bounce into an internal host. Ephemeral: no cookies
    /// or cache persisted from these one-off unsubscribe requests.
    private static let guardedSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        return URLSession(configuration: config, delegate: RedirectGuard(), delegateQueue: nil)
    }()

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
        return .needsManual
    }

    // MARK: - HTTP

    /// A 3xx surviving to the final response means `RedirectGuard` refused to
    /// follow it — the only way a redirect reaches us unfollowed. Without this
    /// it fell under `code < 400` and an SSRF attempt was recorded as a
    /// successful unsubscribe, moving the sender out of the working list.
    private static func blockedRedirect(_ code: Int) -> Outcome? {
        guard (300..<400).contains(code) else { return nil }
        return .failed(
            detail: "redirected to a private or local address; blocked (HTTP \(code))")
    }

    private func oneClickPost(_ url: URL) async -> Outcome {
        guard DestinationGuard.isAllowed(url) else {
            Log.unsubscribe.problem("blocked one-click POST to non-public host: \(url.host ?? "?")")
            return .failed(detail: "unsubscribe URL resolves to a private or local address; blocked")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(AppVersion.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Data("List-Unsubscribe=One-Click".utf8)
        request.timeoutInterval = 30

        do {
            let (_, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            // A 2xx on a one-click POST means the request was *accepted*, not
            // that the unsubscribe took effect — we don't read the body, and
            // endpoints routinely 200 without acting. "Confirmed" is reserved
            // for a human verifying the sender's page (the browser flow). The
            // real safety net is reappearance detection, which fires regardless.
            if let blocked = Self.blockedRedirect(code) { return blocked }
            if code < 400 {
                return .requested(detail: "one-click accepted (HTTP \(code)), unverifiable")
            }
            return .failed(detail: "endpoint returned HTTP \(code)")
        } catch {
            return .failed(detail: error.localizedDescription)
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
        guard DestinationGuard.isAllowed(url) else {
            Log.unsubscribe.problem("blocked GET to non-public host: \(url.host ?? "?")")
            return .failed(detail: "unsubscribe URL resolves to a private or local address; blocked")
        }
        var request = URLRequest(url: url)
        request.setValue(AppVersion.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        do {
            let (_, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let blocked = Self.blockedRedirect(code) { return blocked }
            if code < 400 {
                // A GET only proves the page loaded, never that it unsubscribed —
                // hence "requested", not "confirmed".
                return .requested(detail: "page loaded (HTTP \(code)), unverifiable")
            }
            return .failed(detail: "page returned HTTP \(code)")
        } catch {
            return .failed(detail: error.localizedDescription)
        }
    }
}

/// Re-checks every HTTP redirect target against `DestinationGuard`, so a public
/// unsubscribe URL cannot 30x-redirect the request into a loopback/LAN host.
/// Returning nil stops the redirect and surfaces the 3xx as the final response.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let url = request.url, DestinationGuard.isAllowed(url) else {
            Log.unsubscribe.problem(
                "blocked unsubscribe redirect to non-public host: \(request.url?.host ?? "?")")
            return nil
        }
        return request
    }
}
