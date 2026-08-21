import CryptoKit
import Foundation

/// Proof that a human looked at one exact set of senders and said yes.
///
/// This is the whole safety argument of the MCP feature (TASK-39, TASK-41,
/// TASK-46) expressed as a type. An agent's value is classification and
/// selection; actuating a reviewed selection is one keystroke for the user, and
/// an agent able to fire hundreds of irreversible third-party requests buys a
/// category of risk with nothing on the other side of the trade. So the batch
/// unsubscribe path takes one of these, and there is no way to get one except by
/// a human confirming a selection in the app.
///
/// **The initializer is deliberately not public.** `ReviewTokenVault` is the only
/// thing that can mint a token, and nothing on the MCP surface mints, accepts or
/// returns one — an agent has no wire representation of a token at all, so it
/// cannot present, forge or replay something it can never hold. If you find
/// yourself widening this initializer, or adding a `review_token` argument to a
/// tool schema, stop: that is the convenience path this type exists to prevent.
public struct ReviewToken: Sendable, Hashable {
    public let id: UUID
    /// Binds the token to the exact set of senders that was on screen. A token
    /// minted for one selection is worthless against another, so it cannot be
    /// carried over to a set the user never saw.
    public let fingerprint: String
    public let issuedAt: Date
    public let expiresAt: Date

    init(id: UUID, fingerprint: String, issuedAt: Date, expiresAt: Date) {
        self.id = id
        self.fingerprint = fingerprint
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
    }

    /// A stable digest of a set of `GroupID.storageKey`s.
    ///
    /// Set semantics, sorted before hashing: the user confirmed *these senders*,
    /// and neither the order the UI happened to list them in nor a duplicate in
    /// the caller's array changes what they agreed to.
    /// Each key is length-prefixed, so no key can impersonate two by containing
    /// the separator: `["a\nb"]` and `["a", "b"]` are different sets and must
    /// have different fingerprints.
    public static func fingerprint(of keys: some Sequence<String>) -> String {
        let joined = Set(keys).sorted()
            .map { "\($0.utf8.count):\($0)" }
            .joined(separator: "\n")
        return SHA256.hash(data: Data(joined.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    public func isExpired(at now: Date) -> Bool { now >= expiresAt }

    public func covers(_ keys: Set<String>) -> Bool {
        fingerprint == Self.fingerprint(of: keys)
    }
}

/// Why a token was refused. Each case is a distinct thing that went wrong, and
/// the batch path must not treat any of them as "close enough".
public enum ReviewTokenError: Error, Equatable, CustomStringConvertible {
    /// Never minted here, or already spent. A token is single-use, so this is
    /// what a replay looks like.
    case notOutstanding
    case expired
    /// The token was minted for a different set of senders than the one being
    /// acted on.
    case setMismatch

    public var description: String {
        switch self {
        case .notOutstanding:
            "This selection has no live confirmation — the token was never issued here, or it has already been used."
        case .expired:
            "The confirmation has expired. Review the selection again."
        case .setMismatch:
            "The confirmation was for a different set of senders than the one being acted on."
        }
    }
}

/// Mints and redeems review tokens. The single source of a valid token.
///
/// An actor because the mint happens on the main actor (a click) and the redeem
/// happens wherever the batch runs, and outstanding tokens are mutable state
/// shared between them.
public actor ReviewTokenVault {
    /// How long a confirmation stays good for.
    ///
    /// Long enough that a twenty-five-sender batch — each one an HTTP request
    /// with a thirty-second timeout — cannot outlive its own authorisation, and
    /// short enough that a token left over from a review the user has wandered
    /// away from is dead by the time anything could reach it.
    public static let lifetime: TimeInterval = 600

    private var outstanding: [UUID: ReviewToken] = [:]

    public init() {}

    /// Record a human confirmation of exactly these senders.
    ///
    /// Call this only from a path a person drove. There is no MCP route that
    /// reaches it, and adding one would end the guarantee.
    public func mint(confirming keys: Set<String>, now: Date = Date()) -> ReviewToken {
        // Expired tokens can never be redeemed again, so they are only memory.
        outstanding = outstanding.filter { !$0.value.isExpired(at: now) }
        let token = ReviewToken(
            id: UUID(),
            fingerprint: ReviewToken.fingerprint(of: keys),
            issuedAt: now,
            expiresAt: now.addingTimeInterval(Self.lifetime))
        outstanding[token.id] = token
        return token
    }

    /// Spend a token against the set about to be acted on, or throw.
    ///
    /// Validated against the *stored* token rather than the one handed in, so a
    /// caller that fabricated a struct with an agreeable fingerprint gets
    /// nowhere: the only thing its copy is used for is finding the real one.
    ///
    /// A mismatched set does not spend the token. The user's confirmation of
    /// their actual selection is still good, and burning it here would turn a
    /// caller's mistake into the user having to review everything again.
    @discardableResult
    public func redeem(_ token: ReviewToken, for keys: Set<String>, now: Date = Date()) throws
        -> ReviewToken
    {
        guard let issued = outstanding[token.id] else { throw ReviewTokenError.notOutstanding }
        if issued.isExpired(at: now) {
            outstanding[issued.id] = nil
            throw ReviewTokenError.expired
        }
        guard issued.covers(keys) else { throw ReviewTokenError.setMismatch }
        // Single use: what makes a captured token worthless the second time.
        outstanding[issued.id] = nil
        return issued
    }

    /// How many confirmations are live. For tests and diagnostics only.
    public var outstandingCount: Int { outstanding.count }
}
