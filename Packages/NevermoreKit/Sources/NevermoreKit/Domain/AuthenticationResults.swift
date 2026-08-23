import Foundation

/// One method's verdict inside an `Authentication-Results` header (RFC 8601 §2.7).
///
/// Deliberately keeps `temperror`/`permerror` and `neutral` apart from `fail`.
/// They are the receiver saying "I could not tell", and treating "could not
/// tell" as "failed" is how a warning starts firing on ordinary mail.
public enum AuthMethodResult: String, Sendable, Hashable, CaseIterable {
    case pass
    case fail
    case softfail
    case neutral
    case none
    case policy
    case permerror
    case temperror

    /// A verdict the receiving provider is actually asserting against the
    /// sender, as opposed to declining to assert anything.
    public var isFailure: Bool { self == .fail }
}

/// The receiving provider's own SPF / DKIM / DMARC verdicts for one message.
///
/// This is evidence Nevermore can only have because it reads headers, and it is
/// second-hand by construction: the verdict belongs to whichever server put the
/// header there, and it covers one hop — the delivery into this mailbox. Every
/// piece of copy built on it has to say so, because a user who thinks the app
/// examined the sender will trust it far past what it can support.
///
/// Not `Codable`: like `ListUnsubscribe`, the raw header is what the store keeps
/// and re-parsing on read means a parser fix reaches rows already written.
public struct AuthenticationResults: Sendable, Hashable {
    /// The `authserv-id` — the server that made these findings, e.g.
    /// `mx.google.com`. Named in the UI so the claim is attributed rather than
    /// presented as the app's own.
    public let authority: String
    public let spf: AuthMethodResult?
    public let dkim: AuthMethodResult?
    public let dmarc: AuthMethodResult?
    /// `header.from=` as the evaluating server saw it, lowercased.
    ///
    /// Kept so a verdict can be checked against the `From:` the app is showing.
    /// If they disagree, the header is describing a different identity than the
    /// row is, and nothing should be concluded from it.
    public let headerFrom: String?
    /// The header exactly as received.
    public let raw: String

    /// True when the header carried no usable verdict at all — an
    /// `Authentication-Results: example.com; none`, or only methods this type
    /// does not model. Such a header is not evidence of anything.
    public var isSilent: Bool { spf == nil && dkim == nil && dmarc == nil }

    public init(
        authority: String,
        spf: AuthMethodResult? = nil,
        dkim: AuthMethodResult? = nil,
        dmarc: AuthMethodResult? = nil,
        headerFrom: String? = nil,
        raw: String = ""
    ) {
        self.authority = authority
        self.spf = spf
        self.dkim = dkim
        self.dmarc = dmarc
        self.headerFrom = headerFrom
        self.raw = raw
    }

    /// Parse an `Authentication-Results` header value. Nil when there is nothing
    /// there to parse.
    ///
    /// Accepts either a bare value or a whole `Authentication-Results: …` line,
    /// and tolerates several of them run together: a message can carry one per
    /// hop, and only the **first** is worth reading. The receiving server
    /// prepends its own, so the first is the one added by the provider that
    /// delivered into this mailbox — the only one whose findings were not
    /// written by somebody upstream who may be the sender.
    public init?(header: String?) {
        guard let header else { return nil }
        let topmost = Self.topmostHeaderValue(header)
        guard !topmost.isEmpty else { return nil }

        // Comments carry semicolons and equals signs of their own — Google's SPF
        // comment alone contains both — so they have to go before any splitting.
        let unfolded = Self.stripComments(topmost)
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let segments = unfolded.split(separator: ";").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard let first = segments.first, !first.isEmpty else { return nil }

        // `authserv-id [version]`. The optional version is a bare number.
        let idTokens = first.split(whereSeparator: \.isWhitespace).map(String.init)
        let id = idTokens.first ?? ""

        var spf: AuthMethodResult?
        var dkim: AuthMethodResult?
        var dmarc: AuthMethodResult?
        var headerFrom: String?
        var dmarcHeaderFrom: String?

        for segment in segments.dropFirst() where !segment.isEmpty {
            let tokens = segment.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let head = tokens.first, let (method, result) = Self.methodResult(head)
            else { continue }

            // `header.from` belongs to whichever method quoted it; DMARC's is
            // the authoritative one, so it wins if both appear.
            let from = tokens.dropFirst().compactMap { token -> String? in
                let lower = token.lowercased()
                guard lower.hasPrefix("header.from=") else { return nil }
                return Self.domainPart(String(token.dropFirst("header.from=".count)))
            }.first

            switch method {
            case "spf": spf = spf ?? result
            // DKIM legitimately appears several times, one per signature, and a
            // message is DKIM-signed if *any* signature verifies. Taking the
            // first would report a failure for a message that also carried a
            // signature that passed.
            case "dkim": dkim = (dkim == .pass || result == .pass) ? .pass : (dkim ?? result)
            case "dmarc":
                dmarc = dmarc ?? result
                dmarcHeaderFrom = dmarcHeaderFrom ?? from
            default: continue
            }
            if headerFrom == nil { headerFrom = from }
        }

        self.authority = id
        self.spf = spf
        self.dkim = dkim
        self.dmarc = dmarc
        self.headerFrom = dmarcHeaderFrom ?? headerFrom
        self.raw = topmost
    }

    /// The first `Authentication-Results` value in `header`, with any field name
    /// removed.
    static func topmostHeaderValue(_ header: String) -> String {
        let name = "authentication-results:"
        var value = header
        // Split on the field name so several concatenated headers reduce to the
        // first; a value with no field name at all falls through unchanged.
        let lowered = header.lowercased()
        if let start = lowered.range(of: name) {
            let rest = String(header[start.upperBound...])
            let restLower = rest.lowercased()
            if let next = restLower.range(of: name) {
                // Trim back to the start of the folded line the next header began
                // on, rather than mid-token.
                let cut = rest[rest.startIndex..<next.lowerBound]
                value = String(cut)
            } else {
                value = rest
            }
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Remove RFC 5322 comments, honouring nesting, quoted strings and escapes.
    static func stripComments(_ s: String) -> String {
        var out = ""
        var depth = 0
        var inQuote = false
        var escaped = false
        for ch in s {
            if escaped {
                if depth == 0 { out.append(ch) }
                escaped = false
                continue
            }
            if ch == "\\" {
                escaped = true
                if depth == 0 { out.append(ch) }
                continue
            }
            if inQuote {
                if depth == 0 { out.append(ch) }
                if ch == "\"" { inQuote = false }
                continue
            }
            switch ch {
            case "\"":
                inQuote = true
                if depth == 0 { out.append(ch) }
            case "(":
                depth += 1
                // A comment sits between tokens; without this the tokens either
                // side would fuse into one.
                if depth == 1 { out.append(" ") }
            case ")":
                if depth > 0 { depth -= 1 }
            default:
                if depth == 0 { out.append(ch) }
            }
        }
        return out
    }

    /// `dkim=pass` → `("dkim", .pass)`. Tolerates the `method/version` form and
    /// trailing punctuation.
    public static func methodResult(_ token: String) -> (method: String, result: AuthMethodResult)? {
        guard let eq = token.firstIndex(of: "=") else { return nil }
        let method = token[token.startIndex..<eq]
            .split(separator: "/").first.map(String.init)?.lowercased() ?? ""
        let value = String(token[token.index(after: eq)...])
            .lowercased()
            .prefix { $0.isLetter }
        guard !method.isEmpty, let result = AuthMethodResult(rawValue: String(value))
        else { return nil }
        return (method, result)
    }

    /// The domain out of `header.from=` — servers write it as a bare domain, but
    /// a full address turns up too.
    public static func domainPart(_ value: String) -> String? {
        let cleaned = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"<> ,;"))
            .lowercased()
        guard !cleaned.isEmpty else { return nil }
        if let at = cleaned.lastIndex(of: "@") {
            let host = String(cleaned[cleaned.index(after: at)...])
            return host.isEmpty ? nil : host
        }
        return cleaned
    }
}
