import Foundation

/// Picking the sender a person *named*.
///
/// The MCP surface never needs this: it hands out ids and takes them back.
/// Shortcuts does — someone building a shortcut types or dictates "Patagonia"
/// and the entity picker has to turn that into one sender.
///
/// Deliberately narrower than `search_senders`, which also reads subject lines.
/// A subject match is a good way to *find* a sender to read about and a bad way
/// to decide which one an automation acts on: a newsletter that once mentioned
/// Patagonia is not Patagonia, and the difference is invisible in a shortcut
/// that runs unattended.
public enum SenderMatch {
    /// How well `query` names this sender, or nil when it does not name it at
    /// all. Lower is a better match, so results sort ascending.
    ///
    /// An empty query matches everything at one rank: that is the picker being
    /// opened rather than a search finding nothing.
    public static func rank(_ query: String, name: String, address: String) -> Int? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return 0 }
        let name = name.lowercased()
        let address = address.lowercased()
        // Exact first, and both fields at the same rank: someone who typed a
        // whole address means that address, and someone who typed a whole
        // display name means that sender.
        if name == needle || address == needle { return 0 }
        if name.hasPrefix(needle) { return 1 }
        if address.hasPrefix(needle) { return 2 }
        if name.contains(needle) { return 3 }
        if address.contains(needle) { return 4 }
        return nil
    }
}
