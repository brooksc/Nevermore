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
            if unsubscribe.supportsOneClick {
                return await oneClickPost(url)
            }
            return await get(url)
        }
        if let mail = unsubscribe.mailtoTargets.first {
            do {
                try await sendMail(mail.address, mail.subject, mail.body, fromAddress)
                return .confirmed(detail: "unsubscribe email sent")
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
            if (200..<300).contains(code) {
                // A one-click POST returning 2xx is the strongest signal short of
                // reading the body, so treat it as confirmed.
                return .confirmed(detail: "endpoint acknowledged (HTTP \(code))")
            }
            if code < 400 {
                return .requested(detail: "accepted (HTTP \(code)), unverifiable")
            }
            return .failed(detail: "endpoint returned HTTP \(code)")
        } catch {
            return .failed(detail: error.localizedDescription)
        }
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
