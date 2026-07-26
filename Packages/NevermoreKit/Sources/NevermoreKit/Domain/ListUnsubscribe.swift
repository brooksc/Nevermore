import Foundation

/// A parsed RFC 2369 `List-Unsubscribe` header, plus the RFC 8058 one-click flag.
///
/// The header is a comma-separated list of angle-bracketed URIs, in the sender's
/// order of preference:
///
///     List-Unsubscribe: <https://ex.com/u?id=1>, <mailto:unsub@ex.com?subject=stop>
public struct ListUnsubscribe: Hashable, Sendable {
    public struct MailtoTarget: Hashable, Sendable {
        public let address: String
        public let subject: String
        public let body: String
    }

    /// `https`/`http` targets, in header order.
    public let webTargets: [URL]
    /// `mailto:` targets, in header order.
    public let mailtoTargets: [MailtoTarget]
    /// True when `List-Unsubscribe-Post: List-Unsubscribe=One-Click` was present.
    public let supportsOneClick: Bool
    /// The header exactly as the sender wrote it.
    ///
    /// Kept so the store can persist the whole thing and re-parse it later.
    /// Storing only the parsed parts loses the alternate targets *and* the
    /// mailto query string — and senders routinely put a per-recipient token in
    /// `?subject=`, without which the unsubscribe silently does nothing.
    public let raw: String

    public var isEmpty: Bool { webTargets.isEmpty && mailtoTargets.isEmpty }

    /// Parse the header pair. Returns nil when no usable target is found.
    public init?(header: String?, postHeader: String? = nil) {
        guard let header, !header.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        var web: [URL] = []
        var mailto: [MailtoTarget] = []

        for uri in Self.bracketedURIs(header) {
            let scheme = uri.prefix(while: { $0 != ":" }).lowercased()
            switch scheme {
            case "http", "https":
                if let url = URL(string: uri) { web.append(url) }
            case "mailto":
                if let t = Self.parseMailto(uri) { mailto.append(t) }
            default:
                continue
            }
        }

        guard !(web.isEmpty && mailto.isEmpty) else { return nil }

        self.webTargets = web
        self.mailtoTargets = mailto
        self.raw = header
        // RFC 8058 requires the exact token; anything else is not one-click.
        self.supportsOneClick = (postHeader ?? "")
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .contains("list-unsubscribe=one-click")
    }

    /// Extract the contents of each `<...>` group.
    ///
    /// Hand-rolled rather than regex because URIs legitimately contain commas
    /// and the brackets are the only reliable delimiter.
    static func bracketedURIs(_ header: String) -> [String] {
        var result: [String] = []
        var current: String?
        for ch in header {
            switch ch {
            case "<":
                current = ""
            case ">":
                if let c = current?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
                    result.append(c)
                }
                current = nil
            default:
                // Fold whitespace inside a URI — headers wrap across lines.
                if current != nil, !ch.isNewline {
                    current?.append(ch)
                }
            }
        }
        return result
    }

    private static func parseMailto(_ uri: String) -> MailtoTarget? {
        guard let comps = URLComponents(string: uri) else { return nil }
        let address = comps.path.trimmingCharacters(in: .whitespaces)
        // The recipient is attacker-authored (it's the sender's List-Unsubscribe
        // header) and drives an email sent from the user's own account. Require
        // a single, syntactically well-formed address: this rejects control
        // characters (CRLF header injection) and comma/whitespace-separated lists
        // (smuggling extra recipients) before either reaches SMTP.
        guard Self.isSingleWellFormedAddress(address) else { return nil }
        let items = comps.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name.lowercased() == name }?.value
        }
        return MailtoTarget(
            address: address,
            subject: value("subject") ?? "unsubscribe",
            body: value("body") ?? "Please unsubscribe me from this mailing list."
        )
    }

    /// A conservative check that `address` is one ordinary email address:
    /// exactly one `@`, non-empty local and domain parts, a dot in the domain,
    /// and no control characters, whitespace, commas, or angle brackets that
    /// could split it into several recipients or inject a header.
    public static func isSingleWellFormedAddress(_ address: String) -> Bool {
        guard !address.isEmpty, address.count <= 254 else { return false }
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, let local = parts.first, let domain = parts.last,
            !local.isEmpty, !domain.isEmpty, domain.contains(".")
        else { return false }
        let forbidden = CharacterSet(charactersIn: " ,;<>\"\\").union(.controlCharacters)
            .union(.whitespacesAndNewlines)
        return address.rangeOfCharacter(from: forbidden) == nil
    }
}
