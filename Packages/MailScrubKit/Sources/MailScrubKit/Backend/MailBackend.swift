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
            // Workspace admins can disable app passwords org-wide, which
            // surfaces here as a plain auth failure.
            return """
                Sign-in failed: \(detail)
                Check that 2-Step Verification is on and the app password is current. \
                Workspace administrators can disable app passwords for the whole organisation.
                """
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

/// The mail operations MailScrub needs. Deliberately narrow so a second
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

    func trash(_ uids: [MessageUID]) async throws
    /// Restore trashed messages by Message-ID; returns how many were recovered.
    func untrash(messageIDs: [String]) async throws -> Int
    /// Throws if the credentials don't authenticate.
    func verifyConnection() async throws
    func sendMail(to: String, subject: String, body: String, from: String?) async throws

    /// Addresses this account can legitimately send as.
    func sendAsAddresses() async throws -> [String]
    var primaryAddress: String { get }
}
