import Foundation

/// How much mailbox storage a sender's messages occupy, and how much of that
/// the app can actually vouch for.
///
/// The number comes from IMAP `RFC822.SIZE`, which is the server's own octet
/// count for a message. **It is metadata, not content**: it says how big a
/// message is and nothing whatever about what is in it. Reading it does not
/// weaken the headers-only promise, and the sync did not have to ask for
/// anything extra to get it — see `SyncHeaderFields.messageSize`.
///
/// The type carries the unknowns alongside the total on purpose. A sender whose
/// size is unknown must never render as `0 B`: zero reads as "this sender costs
/// you nothing", which is the exact opposite of what an unmeasured sender might
/// turn out to be. Every total here is therefore a floor, never a ceiling.
public struct SenderStorage: Hashable, Sendable {
    /// Octets summed over the messages whose size is on file.
    public let knownBytes: Int
    /// How many messages contributed to `knownBytes`.
    public let knownMessages: Int
    /// Messages in the group with no size on file — synced before the app read
    /// sizes, or served by something that did not report one.
    public let unknownMessages: Int

    public init(knownBytes: Int, knownMessages: Int, unknownMessages: Int) {
        self.knownBytes = knownBytes
        self.knownMessages = knownMessages
        self.unknownMessages = unknownMessages
    }

    public static let none = SenderStorage(
        knownBytes: 0, knownMessages: 0, unknownMessages: 0)

    public var totalMessages: Int { knownMessages + unknownMessages }

    /// Nothing is known. Distinct from "known to be nothing", which cannot
    /// happen: a stored message always has some size.
    public var isUnknown: Bool { knownMessages == 0 }

    /// Some sizes are on file and some are not, so the total is a floor.
    public var isPartial: Bool { knownMessages > 0 && unknownMessages > 0 }

    /// Sum two sender's worth of storage — for a selection, or a whole
    /// collection. Unknowns add up too, which is what keeps a combined total
    /// honest about how much of it was measured.
    public static func + (a: Self, b: Self) -> Self {
        SenderStorage(
            knownBytes: a.knownBytes + b.knownBytes,
            knownMessages: a.knownMessages + b.knownMessages,
            unknownMessages: a.unknownMessages + b.unknownMessages)
    }

    public static func combining(_ parts: some Sequence<SenderStorage>) -> SenderStorage {
        parts.reduce(.none, +)
    }

    /// The key a size-sorted table orders by.
    ///
    /// The measured bytes and nothing else, which puts a sender of unknown size
    /// at the bottom of a largest-first sort. That is the only defensible place
    /// for it: the app cannot claim such a sender is large and must not imply it
    /// is small, so it goes where no claim is being made. What the cell *shows*
    /// is still "Unknown" — this orders rows, it does not describe them.
    public var sortKey: Int { knownBytes }

    // MARK: - Presentation

    /// The size for a table cell or a one-line summary.
    ///
    /// Three shapes, and the distinction between them is the point:
    /// - `"Unknown"` — no size on file for any message.
    /// - `"at least 3.1 GB"` — some messages measured, some not.
    /// - `"3.1 GB"` — every message in the group measured.
    ///
    /// Rounded by `ByteCountFormatStyle`, which is what keeps the app from
    /// claiming more precision than the server offered: `RFC822.SIZE` is the
    /// size of the message as the server would transmit it, which is not
    /// exactly what the account is billed for, so showing raw octets would
    /// dress an approximation up as an audit.
    public func summary(locale: Locale = .autoupdatingCurrent) -> String {
        guard !isUnknown else { return "Unknown" }
        let size = Self.format(bytes: knownBytes, locale: locale)
        return isPartial ? "at least \(size)" : size
    }

    /// The bare formatted size, with no qualifier. For places that state the
    /// partialness separately rather than inline.
    public static func format(bytes: Int, locale: Locale = .autoupdatingCurrent) -> String {
        // `.file` is the 1000-based scale Finder uses, and the one mail
        // providers quote quotas in — a "15 GB" free tier is 15 × 10⁹.
        bytes.formatted(.byteCount(style: .file).locale(locale))
    }

    /// Why this total may be lower than what the mailbox is actually holding,
    /// or nil when there is nothing to qualify.
    ///
    /// Two separate reasons, and neither is a rounding error:
    /// - messages this app has never measured, and
    /// - the fact that the app only ever knew about messages carrying a
    ///   `List-Unsubscribe` header that were still on the server when it
    ///   looked. Anything already trashed or deleted is gone from the count.
    public var caveat: String? {
        guard !isUnknown else {
            // Names the existing control rather than offering to run it. A full
            // re-sync is minutes of work on a large mailbox, and that decision
            // belongs to the deliberate button in Settings, not to a tooltip on
            // a column that has noticed it is missing data.
            return
                "Nevermore has no size on file for \(Self.messages(unknownMessages)) from this "
                + "sender. Sizes arrive with new mail; Settings ▸ Full Resync fills in the rest."
        }
        var reasons = [
            "counts only the messages Nevermore has on file, so anything already deleted "
                + "from the mailbox is not in it"
        ]
        if isPartial {
            reasons.insert(
                "leaves out \(Self.messages(unknownMessages)) with no size on file", at: 0)
        }
        return "This total \(reasons.joined(separator: ", and "))."
    }

    private static func messages(_ n: Int) -> String {
        n == 1 ? "1 message" : "\(n.formatted()) messages"
    }
}

extension SenderGroup {
    /// What this sender's stored messages occupy on the server.
    public var storage: SenderStorage {
        var bytes = 0
        var known = 0
        var unknown = 0
        for message in messages {
            if let size = message.byteSize {
                bytes += size
                known += 1
            } else {
                unknown += 1
            }
        }
        return SenderStorage(
            knownBytes: bytes, knownMessages: known, unknownMessages: unknown)
    }
}
