import Foundation

/// Where a sync left off.
///
/// Opaque on purpose: for IMAP it is `(uidValidity, highestUID)`; a future
/// Gmail API backend would put a `historyId` here instead.
public struct SyncToken: Hashable, Sendable, Codable {
    public let uidValidity: UInt32
    public let highestUID: UInt32
    /// When the sync that produced this token ran.
    ///
    /// Incremental sync searches by date rather than UID: SwiftMail's
    /// `SearchCriteria.uid` encodes a single UID, not an open-ended range, so
    /// "everything newer than N" isn't expressible. Optional so tokens written
    /// before this field existed still decode.
    public let lastSyncedAt: Date?

    public init(uidValidity: UInt32, highestUID: UInt32, lastSyncedAt: Date? = nil) {
        self.uidValidity = uidValidity
        self.highestUID = highestUID
        self.lastSyncedAt = lastSyncedAt
    }
}

public enum MailBackendError: Error, LocalizedError {
    case notConnected
    case authenticationFailed(String)
    case mailboxUnavailable(String)
    case sendFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to the mail server."
        case .authenticationFailed(let detail):
            // Just the server's answer. What to do about it depends entirely on
            // the provider — 2-Step Verification and org-wide policy are Google's
            // words, not Fastmail's — so the advice lives in `AppPasswordGuide`
            // and is added by whoever knows which provider this account uses.
            return "Sign-in failed: \(detail)"
        case .mailboxUnavailable(let name):
            return "Could not open the mailbox '\(name)'."
        case .sendFailed(let detail):
            return "Could not send mail: \(detail)"
        }
    }
}

/// What a sync is currently doing, for progress reporting.
///
/// Discovery and fetching have genuinely different shapes — discovery walks
/// date windows without knowing the total up front, fetching has a real
/// denominator — so collapsing both into one (done, total) pair would lie.
public enum SyncPhase: Sendable {
    /// Searching the server. `found` grows as windows complete.
    case discovering(window: Int, of: Int, found: Int)
    /// Downloading headers for messages already located.
    case fetching(done: Int, of: Int)
}

/// Where a message sat before it was trashed, so undo can put it back there.
///
/// Two cases, because two is all IMAP can express. On Gmail the difference is
/// the `\Inbox` label rather than a folder — but Gmail's IMAP surface presents
/// All Mail as a mailbox you can MOVE into, so "archived" is reachable exactly
/// the way "inbox" is. Providers without an all-mail folder never show
/// Nevermore anything but the inbox, so `.archive` does not arise there.
public enum RestoreTarget: String, Sendable, Hashable {
    case inbox
    case archive
}

/// What a trash actually did, which is not always what was asked for.
public struct TrashOutcome: Sendable {
    /// The UIDs the server confirmed it moved. May be a prefix of the request.
    public let moved: [MessageUID]
    /// Of those, the ones that were archived rather than in the inbox.
    ///
    /// Empty when nothing was archived, when the account has no notion of
    /// archiving, and when the origin could not be established — in all three
    /// cases undo restores to the inbox, which is what it has always done.
    public let archived: Set<MessageUID>

    public init(moved: [MessageUID], archived: Set<MessageUID> = []) {
        self.moved = moved
        self.archived = archived
    }

    /// Split messages by where each one has to be restored to, as Message-IDs
    /// — the only identifier that survives the move into Trash, since IMAP UIDs
    /// are per-mailbox.
    public static func restorePlan(
        for messages: [EmailMessage], archived: Set<MessageUID>
    ) -> (inbox: [String], archive: [String]) {
        var inbox: [String] = []
        var archive: [String] = []
        for message in messages where !message.messageId.isEmpty {
            if archived.contains(message.uid) {
                archive.append(message.messageId)
            } else {
                inbox.append(message.messageId)
            }
        }
        return (inbox, archive)
    }
}

/// The mail operations Nevermore needs. Deliberately narrow so a second
/// implementation stays cheap to add.
public protocol MailBackend: Sendable {
    /// Every message carrying `List-Unsubscribe`. Slow; first run only.
    func discoverAll(
        progress: @Sendable @escaping (SyncPhase) -> Void
    ) async throws -> (messages: [EmailMessage], token: SyncToken)

    /// Messages that arrived since `token`. Fast.
    func changes(
        since token: SyncToken?,
        progress: @Sendable @escaping (SyncPhase) -> Void
    ) async throws -> (messages: [EmailMessage], token: SyncToken)

    /// Move messages to Trash. Reports the UIDs actually moved, which may be a
    /// prefix of the request if the server gave up partway, and which of those
    /// were archived rather than in the inbox.
    ///
    /// `recordOrigin` is false when the batch is too large for undo to be
    /// offered: establishing origin costs a round trip per chunk, and nothing
    /// would ever read the answer.
    func trash(_ uids: [MessageUID], recordOrigin: Bool) async throws -> TrashOutcome
    /// Restore trashed messages by Message-ID into `target`; returns how many
    /// were recovered.
    func untrash(messageIDs: [String], to target: RestoreTarget) async throws -> Int
    /// Throws if the credentials don't authenticate.
    func verifyConnection() async throws
    func sendMail(to: String, subject: String, body: String, from: String?) async throws

    /// Gmail's internal conversation id for a message, if the server offers the
    /// `X-GM-EXT-1` extension. Used to open the conversation in Gmail's web UI
    /// directly rather than a search that the user then has to click through.
    /// Nil for every non-Gmail server, and on any failure — this is a
    /// convenience, never a requirement.
    func gmailThreadID(for uid: MessageUID) async -> UInt64?

    /// Addresses this account can legitimately send as.
    func sendAsAddresses() async throws -> [String]
    var primaryAddress: String { get }

    /// Drop the connection. Called between sync retries, because a cached
    /// connection that has errored stays poisoned.
    func disconnect() async
}
