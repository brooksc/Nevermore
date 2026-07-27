import Foundation

/// RFC 2919 `List-ID`: the definitive marker that a message came from a
/// *mailing list* rather than a marketing blast.
///
/// This matters because `List-Unsubscribe` only means "bulk mail with a
/// machine-readable opt-out" — it says nothing about whether the sender is a
/// promotion, a notification stream, or a discussion list you're a member of.
/// Unsubscribing from a PTA list or from GitHub issue notifications is a
/// different decision from dropping a retailer's promo, and the app shouldn't
/// present them identically.
public enum MailingList {
    /// The list identifier from a `List-ID` header, or nil.
    ///
    /// The header is an optional human phrase followed by the identifier in
    /// angle brackets:
    ///
    ///     List-ID: Ruby Talk <ruby-talk.ruby-lang.org>
    ///     List-ID: <ptamemberconnection.wastatepta.org>
    ///
    /// Returns just the identifier, lowercased. A header with no brackets is
    /// accepted whole, since some senders emit a bare identifier.
    public static func id(fromHeader raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let open = trimmed.lastIndex(of: "<"),
            let close = trimmed[open...].firstIndex(of: ">")
        {
            let inner = trimmed[trimmed.index(after: open)..<close]
                .trimmingCharacters(in: .whitespaces)
            return inner.isEmpty ? nil : inner.lowercased()
        }
        // No brackets: take the whole value, but refuse anything with spaces —
        // that's a description with the identifier missing, not an id.
        return trimmed.contains(" ") ? nil : trimmed.lowercased()
    }
}
