import Foundation

/// Why a message the server located never became a row in the store.
///
/// Discovery reliably finds more UIDs than the store keeps, and until this
/// existed nobody could say where the difference went — the UI showed both
/// numbers and could explain neither (PLAN.md §10, TASK-7). The cases here are
/// not a guess at the causes: each one is a specific `return nil` / `filter` on
/// the path from `IMAPBackend.discoverAll` through `MessageStore.upsert`, and
/// between them they cover every way a located UID can be dropped.
///
/// Being dropped is not the same as being wrong. Every case below is the app
/// behaving as designed; the point is to be able to say *which* design decision
/// accounts for how many messages, so a large number in an unexpected place is
/// visible instead of merely suspected.
public enum SyncDropReason: String, Sendable, Hashable, CaseIterable, Codable {
    /// `SEARCH` matched the UID but the following `FETCH` returned nothing for
    /// it, or returned a response carrying no UID at all. Normal in small
    /// numbers — a message can be deleted or moved between the two commands.
    case notFetched
    /// The headers came back without a `List-Unsubscribe` (or with a blank
    /// one), even though the search matched on that header. A stale server-side
    /// index, or a header the fetch could not return.
    case noUnsubscribeHeader
    /// The header held targets, but every one used a scheme the app cannot act
    /// on — anything that is not `http`, `https` or `mailto`. This is one of
    /// the two causes PLAN.md suspected.
    case unsupportedScheme
    /// The header named a supported scheme but nothing survived parsing: no
    /// `<…>` brackets at all, a URL that would not parse, or a `mailto:`
    /// address rejected by the header-injection guard in `ListUnsubscribe`.
    case unusableTarget
    /// The sender is one of the account's own send-as addresses, so this is the
    /// user's own sent mail. The other cause PLAN.md suspected.
    case ownMail
    /// The same UID arrived twice in one fetch. Would have collapsed silently
    /// on the store's primary key; counted and dropped here instead so the
    /// arithmetic below stays exact.
    case duplicateUID

    /// Short label for the UI.
    public var label: String {
        switch self {
        case .notFetched: return "Gone before we read them"
        case .noUnsubscribeHeader: return "No unsubscribe header"
        case .unsupportedScheme: return "Unsupported unsubscribe link"
        case .unusableTarget: return "Unusable unsubscribe link"
        case .ownMail: return "Your own sent mail"
        case .duplicateUID: return "Listed twice by the server"
        }
    }

    /// One sentence a user can act on, or at least understand.
    public var detail: String {
        switch self {
        case .notFetched:
            return "The server matched these but had nothing to send when we asked for the headers."
        case .noUnsubscribeHeader:
            return "The headers came back without the unsubscribe header the search matched on."
        case .unsupportedScheme:
            return "The only unsubscribe links use a scheme Nevermore cannot open."
        case .unusableTarget:
            return "The unsubscribe header was there but no usable link could be read from it."
        case .ownMail:
            return "Mail you sent from this account or one of its aliases."
        case .duplicateUID:
            return "The same message came back more than once in one batch."
        }
    }
}

extension SyncDropReason {
    /// Why a `List-Unsubscribe` header produced no usable target.
    ///
    /// Only meaningful once `ListUnsubscribe(header:)` has already returned
    /// nil; this says *which* of its three refusals happened, which is the
    /// difference between "senders are using schemes we don't support" and
    /// "our parser is rejecting headers it should accept". Those want opposite
    /// responses, and the old code could not tell them apart.
    ///
    /// Runs only on the drop path — never on the ~14,600 messages that parse
    /// fine — so re-walking the header here costs nothing on a normal sync.
    public static func forUnusableHeader(_ header: String?) -> SyncDropReason {
        guard let header, !header.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .noUnsubscribeHeader
        }
        let uris = ListUnsubscribe.bracketedURIs(header)
        // No brackets at all is a malformed header rather than a scheme we
        // decline to speak, so it is a target we cannot use, not an unsupported
        // one — the fix for it would be in our parser.
        guard !uris.isEmpty else { return .unusableTarget }
        let supported = uris.contains { uri in
            let scheme = uri.prefix(while: { $0 != ":" }).lowercased()
            return scheme == "http" || scheme == "https" || scheme == "mailto"
        }
        return supported ? .unusableTarget : .unsupportedScheme
    }
}

/// The ledger for one sync: how many messages the server located, and what
/// became of every one of them.
///
/// Filled in two halves, because the answer lives in two places. The backend
/// knows what it located, fetched and dropped; only the store knows whether a
/// message it was handed was new or one it already had. `record(_:)` joins them.
///
/// The invariant worth watching is `unaccounted`: located messages minus
/// everything the ledger can explain. It should be zero. If it is not, this
/// type is out of date with the code it describes, which is exactly the state
/// the sync was in before it existed.
public struct SyncAttribution: Sendable, Equatable, Codable {
    /// Distinct UIDs the server's `SEARCH` matched.
    public var located = 0
    /// Of those, how many came back from `FETCH` with a UID attached.
    public var fetched = 0
    /// How many messages the backend handed to the store.
    public var handedToStore = 0
    /// New rows written. Filled in by `record(_:)` after the upsert.
    public var inserted = 0
    /// Rows the store already had, refreshed rather than added. Incremental
    /// sync deliberately re-reads a two-day overlap, so this is normally
    /// non-zero and is not a loss.
    public var updated = 0

    public private(set) var drops: [SyncDropReason: Int] = [:]

    public init() {}

    public mutating func drop(_ reason: SyncDropReason, count: Int = 1) {
        guard count > 0 else { return }
        drops[reason, default: 0] += count
    }

    public func count(_ reason: SyncDropReason) -> Int { drops[reason] ?? 0 }

    /// Every located message the app decided not to store.
    public var dropped: Int { drops.values.reduce(0, +) }

    /// Merge in what the store did with the messages it was handed.
    public mutating func record(_ outcome: MessageStore.UpsertOutcome) {
        inserted = outcome.inserted
        updated = outcome.updated
    }

    /// Located messages this ledger cannot explain. Zero unless a drop exists
    /// in the code that has no case here.
    public var unaccounted: Int { located - (inserted + updated + dropped) }

    public var balances: Bool { unaccounted == 0 }

    /// One reason and how many messages it accounts for.
    public struct DropCount: Sendable, Equatable, Identifiable {
        public let reason: SyncDropReason
        public let count: Int
        public var id: SyncDropReason { reason }
    }

    /// The drops that actually happened, largest first — what a human wants to
    /// read, without six rows of zero.
    public var significantDrops: [DropCount] {
        drops.filter { $0.value > 0 }
            .sorted { ($0.value, $0.key.rawValue) > ($1.value, $1.key.rawValue) }
            .map { DropCount(reason: $0.key, count: $0.value) }
    }

    /// One line for the log: the whole ledger, in the order the messages moved
    /// through it.
    public var summary: String {
        var parts = [
            "located \(located)", "fetched \(fetched)", "stored \(inserted) new",
            "\(updated) already known",
        ]
        parts += significantDrops.map { "\($0.reason.rawValue) \($0.count)" }
        if !balances { parts.append("UNACCOUNTED \(unaccounted)") }
        return "sync accounting — " + parts.joined(separator: ", ")
    }
}
