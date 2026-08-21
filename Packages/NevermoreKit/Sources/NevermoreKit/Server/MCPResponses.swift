import Foundation

// The shapes the read tools return.
//
// Every one of them carries `account`, because an agent holding a conversation
// about someone's mail has no other way to know which mailbox it is looking at —
// and Nevermore serves only the account that is currently open, so a response
// that arrived before the user switched accounts is about a different mailbox
// than the next one. Naming it on every response makes that visible instead of
// silent.
//
// Encoded with `.convertToSnakeCase` (see `MCPRoutes.json`), so the property
// names here are the wire names in camelCase form.

/// One sender, as a list row. Deliberately compact: a real mailbox has around a
/// thousand of these and an agent has to be able to hold a page of them.
public struct MCPSenderSummary: Encodable, Sendable {
    /// `domain:acme.com` or `address:news@acme.com` — the id every other tool
    /// takes, and the same key the app uses for history and ignore records.
    public let id: String
    public let kind: String
    public let key: String
    public let name: String
    public let messages: Int
    public let unread: Int
    public let unreadPercent: Int
    public let newest: String?
    public let oldest: String?
    public let collection: String
    public let unsubscribeMethod: String
    /// True when finishing this sender needs a human in a browser: either they
    /// published no machine-readable target, or they already ignored one
    /// unsubscribe and retrying the same automated path is what failed before.
    public let needsBrowser: Bool
    public let isMailingList: Bool
    public let mailingListId: String?
    /// The agent's own last judgement about this sender, echoed back so a later
    /// session can see what an earlier one decided. Opaque text; Nevermore never
    /// interprets it.
    public let classification: String?
    public let context: String?
    public let latestSubject: String?
}

/// One sender in full. Everything the summary carries, plus the parsed
/// unsubscribe targets and what has already been tried.
public struct MCPSenderDetail: Encodable, Sendable {
    public let account: String
    public let sender: MCPSenderSummary
    public let addresses: [String]
    public let hosts: [String]
    public let supportsOneClick: Bool
    public let webTargets: [String]
    public let mailtoTargets: [MCPMailtoTarget]
    public let unsubscribeHeader: String?
    public let unsubscribeRecord: MCPUnsubscribeRecord?
    public let messagesSinceUnsubscribe: Int
    public let decision: MCPDecision?
    public let recentSubjects: [MCPMessageRow]
    public let note: String
}

public struct MCPMailtoTarget: Encodable, Sendable {
    public let address: String
    public let subject: String
    /// True when the sender put a token in the mailto's subject or body, which
    /// is what lets them identify the subscription without relying on the From
    /// address.
    public let identifiesRecipient: Bool
}

public struct MCPMessageRow: Encodable, Sendable {
    public let uid: UInt32
    public let from: String
    public let subject: String
    public let receivedAt: String
    public let isUnread: Bool
}

public struct MCPUnsubscribeRecord: Encodable, Sendable {
    public let senderId: String
    public let senderName: String
    public let senderEmail: String
    public let senderDomain: String
    public let url: String?
    public let attemptedAt: String
    public let outcome: String
    /// Whether the sender has mailed since. The whole reason the outcome above
    /// is not to be trusted: `requested` means the request was accepted, never
    /// that it worked.
    public let reappeared: Bool
}

public struct MCPDecision: Encodable, Sendable {
    public let address: String
    public let classification: String
    public let reason: String
    public let context: String?
    public let decidedAt: String
}

/// A page of senders. `hasMore` and `nextOffset` exist so an agent never has to
/// infer whether it saw everything from the row count.
public struct MCPSenderPage: Encodable, Sendable {
    public let account: String
    public let collection: String?
    public let total: Int
    public let offset: Int
    public let limit: Int
    public let hasMore: Bool
    public let nextOffset: Int?
    public let senders: [MCPSenderSummary]
    public let note: String
}

public struct MCPMessagePage: Encodable, Sendable {
    public let account: String
    public let senderId: String
    public let senderName: String
    public let total: Int
    public let offset: Int
    public let limit: Int
    public let hasMore: Bool
    public let nextOffset: Int?
    public let messages: [MCPMessageRow]
    public let note: String
}

public struct MCPHistoryPage: Encodable, Sendable {
    public let account: String
    public let total: Int
    public let offset: Int
    public let limit: Int
    public let hasMore: Bool
    public let nextOffset: Int?
    public let records: [MCPUnsubscribeRecord]
    public let note: String
}

public struct MCPContextCohort: Encodable, Sendable {
    public let account: String
    public let context: String
    public let total: Int
    public let decisions: [MCPCohortRow]
    public let availableContexts: [String]
    public let note: String
}

/// One decided sender, joined back to the group it currently sits in.
///
/// `sender` is nil when the decision's address has no messages left locally —
/// the decision outlives the mail, which is the point of keying it by address.
public struct MCPCohortRow: Encodable, Sendable {
    public let decision: MCPDecision
    public let sender: MCPSenderSummary?
}

public struct MCPMailboxSummary: Encodable, Sendable {
    public let account: String
    public let senders: Int
    public let messages: Int
    public let unread: Int
    public let byCollection: [String: Int]
    public let byUnsubscribeMethod: [String: Int]
    public let needBrowser: Int
    public let mailingLists: Int
    public let decided: Int
    public let contexts: [String]
    public let oldestMessage: String?
    public let newestMessage: String?
    public let lastSyncedAt: String?
    public let note: String
}

public struct MCPSyncStatus: Encodable, Sendable {
    public let account: String
    public let hasSynced: Bool
    public let lastSyncedAt: String?
    public let messages: Int
    public let senders: Int
    public let uidValidity: UInt32?
    public let highestUid: UInt32?
    public let note: String
}
