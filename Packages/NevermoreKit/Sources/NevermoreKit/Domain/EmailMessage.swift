import Foundation

/// IMAP UID of a message within a mailbox. Only unique alongside a `UIDVALIDITY`.
public struct MessageUID: Hashable, Sendable, Comparable, Codable {
    public let value: UInt32
    public init(_ value: UInt32) { self.value = value }
    public static func < (a: Self, b: Self) -> Bool { a.value < b.value }
}

/// One message's headers. Bodies are never fetched or stored.
public struct EmailMessage: Hashable, Sendable, Identifiable {
    public let uid: MessageUID
    public let sender: EmailSender
    public let subject: String
    public let receivedAt: Date
    public let isUnread: Bool
    public let unsubscribe: ListUnsubscribe?
    /// `Delivered-To`, falling back to `To`. Used for send-as alias detection.
    public let deliveredTo: String
    /// RFC 5322 `Message-ID` (e.g. `<abc@host>`). The stable identifier used to
    /// find a message again in Trash for undo, since IMAP UIDs differ per folder.
    public let messageId: String
    /// RFC 2919 `List-ID`, when the sender is a mailing list. Nil for ordinary
    /// bulk mail, which is most marketing.
    public let listID: String?
    /// RFC 8601 `Authentication-Results` — the receiving provider's SPF, DKIM
    /// and DMARC verdicts for this message (TASK-30).
    ///
    /// Nil on every message today: the field is not in the sync's header list
    /// until TASK-36 has measured what asking for it costs on a real mailbox.
    /// See `SyncHeaderFields`.
    public let authentication: AuthenticationResults?
    /// IMAP `RFC822.SIZE` — the server's octet count for this message (TASK-29).
    ///
    /// Metadata, not content: how big the message is, never what is in it. The
    /// sync gets it without asking for anything extra, because it is part of the
    /// attribute set the fetch already requests — see `SyncHeaderFields.messageSize`.
    ///
    /// Nil where no size is on file: a message stored before the app read sizes,
    /// or a server that did not report one. Nil is not zero, and must never be
    /// shown as zero — `SenderStorage` is what enforces that.
    public let byteSize: Int?

    public var id: MessageUID { uid }
    public var canUnsubscribe: Bool { unsubscribe != nil }

    public init(
        uid: MessageUID,
        sender: EmailSender,
        subject: String,
        receivedAt: Date,
        isUnread: Bool,
        unsubscribe: ListUnsubscribe?,
        deliveredTo: String = "",
        messageId: String = "",
        listID: String? = nil,
        authentication: AuthenticationResults? = nil,
        byteSize: Int? = nil
    ) {
        self.uid = uid
        self.sender = sender
        self.subject = subject
        self.receivedAt = receivedAt
        self.isUnread = isUnread
        self.unsubscribe = unsubscribe
        self.deliveredTo = deliveredTo
        self.messageId = messageId
        self.listID = listID
        self.authentication = authentication
        self.byteSize = byteSize
    }
}

/// Identity of a sender group — a table row, a selection key, and a history key.
///
/// The Python version overloaded a bare `domain` string for all three, and stored
/// an email address in it for split groups. Making the kind explicit removes a
/// whole class of "is this a domain or an address?" bugs.
public struct GroupID: Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable {
        /// Every sender on a registrable domain, merged (e.g. `amazon.com`).
        case domain
        /// One sender address on a shared platform (e.g. a single Substack).
        case address
    }
    public let kind: Kind
    public let key: String

    public init(kind: Kind, key: String) {
        self.kind = kind
        self.key = key
    }

    /// Stable string form for persistence.
    public var storageKey: String { "\(kind.rawValue):\(key)" }

    public init?(storageKey: String) {
        guard let sep = storageKey.firstIndex(of: ":"),
              let kind = Kind(rawValue: String(storageKey[storageKey.startIndex..<sep]))
        else { return nil }
        self.init(kind: kind, key: String(storageKey[storageKey.index(after: sep)...]))
    }
}

/// A group of messages from one sender, as shown in one table row.
public struct SenderGroup: Identifiable, Sendable {
    public let id: GroupID
    public let messages: [EmailMessage]

    public init(id: GroupID, messages: [EmailMessage]) {
        self.id = id
        self.messages = messages.sorted { $0.receivedAt > $1.receivedAt }
    }

    public var total: Int { messages.count }
    public var unreadCount: Int { messages.lazy.filter(\.isUnread).count }
    public var unreadPercent: Double {
        total == 0 ? 0 : Double(unreadCount) / Double(total) * 100
    }
    public var latest: EmailMessage? { messages.first }
    public var newest: Date { messages.first?.receivedAt ?? .distantPast }

    /// The list identifier if this sender is a mailing list.
    ///
    /// Taken from any message in the group: a list's id is stable, and older
    /// messages carry it even when a recent one is missing the header.
    public var mailingListID: String? {
        messages.lazy.compactMap(\.listID).first
    }
    public var isMailingList: Bool { mailingListID != nil }

    /// The message to drive an unsubscribe from — newest one that has a target.
    public var unsubscribeSource: EmailMessage? {
        messages.first(where: \.canUnsubscribe)
    }
    public var canUnsubscribe: Bool { unsubscribeSource != nil }

    /// Human label for the row.
    ///
    /// Falls back to the group key when the messages disagree about the display
    /// name. `notifications@github.com` carries a different human's name on every
    /// message, so taking the newest one would label 2,000 messages after
    /// whoever happened to comment last.
    public var displayName: String {
        let names = messages.map(\.sender.displayName).filter { !$0.isEmpty }
        guard !names.isEmpty else { return latest?.sender.label ?? id.key }

        var tally: [String: Int] = [:]
        for name in names { tally[name, default: 0] += 1 }

        // A dominant name is the brand ("Mint" across slightly varying senders).
        // No dominant name means the field carries per-message data rather than
        // an identity, so the key is the only honest label.
        // Tie-break by name, not by dictionary order: `max(by: value)` picks
        // arbitrarily among equal counts, and Dictionary iteration order varies
        // between launches — so a domain with two equally-common display names
        // would relabel itself every time the app started.
        if let (name, count) = tally.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }),
            count * 2 >= names.count
        {
            return name
        }
        return id.key
    }
}
