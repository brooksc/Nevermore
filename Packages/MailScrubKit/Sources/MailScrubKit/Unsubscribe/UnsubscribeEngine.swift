import Foundation

/// Performs a single sender's unsubscribe, following the RFC 2369/8058 chain:
/// one-click POST → GET → mailto:. Returns an honest outcome — the design and
/// spec both insist the UI must not claim success it cannot prove.
public struct UnsubscribeEngine: Sendable {
    public enum Outcome: Sendable, Equatable {
        /// The endpoint positively acknowledged (2xx on a one-click POST, or a
        /// mailto: successfully sent). The closest thing to proof available.
        case confirmed(detail: String)
        /// Accepted but unverifiable — a plain GET link, or a POST that returned
        /// a non-committal status. May still have worked.
        case requested(detail: String)
        case failed(detail: String)
        /// No usable target; the caller should fall back to opening Gmail.
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

    public init(sendMail: @escaping MailSender, session: URLSession = .shared) {
        self.sendMail = sendMail
        self.session = session
    }

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
            if unsubscribe.supportsOneClick {
                Log.unsubscribe.detail("one-click POST -> \(host)")
                return await oneClickPost(url)
            }
            Log.unsubscribe.detail("GET -> \(host)")
            return await get(url)
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

    private func oneClickPost(_ url: URL) async -> Outcome {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("MailScrub/1.0", forHTTPHeaderField: "User-Agent")
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
        var request = URLRequest(url: url)
        request.setValue("MailScrub/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        do {
            let (_, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
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
