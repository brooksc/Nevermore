import Foundation

// MARK: - Outcome honesty

extension UnsubscribeEngine.Outcome {
    /// The outcome as an agent sees it.
    ///
    /// The four cases reach the wire intact, and that is the point. An endpoint
    /// answering "success" proves nothing: the app itself only ever says
    /// `confirmed` when a human watched the sender's own confirmation page, and
    /// an agent that reported "unsubscribed" for what Nevermore calls
    /// `requested` would be inventing evidence the app deliberately refuses to
    /// invent. Anything that flattens these into a boolean is a bug.
    public var agentOutcomeName: String {
        switch self {
        case .confirmed: "confirmed"
        case .requested: "requested"
        case .failed: "failed"
        case .needsManual: "needs_manual"
        }
    }

    /// The engine's own words about what happened, unrewritten.
    public var agentDetail: String {
        switch self {
        case let .confirmed(detail), let .requested(detail), let .failed(detail): detail
        case let .needsManual(reason): reason
        }
    }
}

/// One thing that actually happened to one sender.
///
/// Per sender, never a total (TASK-26 acceptance criterion 3): "23 unsubscribed"
/// is exactly the summary that hides the two that failed and the one that needs
/// a browser.
public struct AgentOutcome: Sendable, Encodable, Equatable {
    public let senderId: String
    public let senderName: String
    /// What was attempted: `unsubscribe` today, and whatever TASK-47 adds next.
    public let action: String
    /// `confirmed`, `requested`, `failed` or `needs_manual`.
    public let outcome: String
    public let detail: String
    public let at: String

    public init(
        senderId: String, senderName: String, action: String, outcome: String, detail: String,
        at: String
    ) {
        self.senderId = senderId
        self.senderName = senderName
        self.action = action
        self.outcome = outcome
        self.detail = detail
        self.at = at
    }

    public init(
        senderId: String, senderName: String, action: String = "unsubscribe",
        outcome: UnsubscribeEngine.Outcome, at: Date = Date()
    ) {
        self.init(
            senderId: senderId, senderName: senderName, action: action,
            outcome: outcome.agentOutcomeName, detail: outcome.agentDetail,
            at: MCPRoutes.iso(at))
    }
}

/// What the app has actually done, so an agent that proposed something can find
/// out how it went.
///
/// In memory and bounded, deliberately. These are transient facts about one
/// review session — the durable record of an unsubscribe is
/// `MessageStore.UnsubscribeRecord`, which the read surface already serves, and
/// duplicating it into the database would create a second history to keep in
/// agreement with the first. The cost is that a relaunch empties it, which
/// `get_proposal_status` says out loud rather than reporting an empty list as
/// "nothing happened".
public actor AgentOutcomeLedger {
    /// Eight times the proposal cap: enough for several review sessions, small
    /// enough that a long-running app cannot grow it without bound.
    public static let capacity = SenderProposal.maxItems * 8

    private var entries: [AgentOutcome] = []

    public init() {}

    public func record(_ outcome: AgentOutcome) {
        entries.append(outcome)
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
    }

    public func record(_ outcomes: [AgentOutcome]) {
        for outcome in outcomes { record(outcome) }
    }

    /// Newest last, in the order things happened.
    public func recent(limit: Int = capacity) -> [AgentOutcome] {
        Array(entries.suffix(max(limit, 0)))
    }

    /// Everything recorded about these senders, newest last.
    public func outcomes(for senderIds: Set<String>) -> [AgentOutcome] {
        entries.filter { senderIds.contains($0.senderId) }
    }
}

// MARK: - Results

/// What one sender in a multi-sender write did.
public struct AgentSenderResult: Sendable, Encodable, Equatable {
    public let senderId: String
    public let senderName: String?
    public let applied: Bool
    public let detail: String

    public init(senderId: String, senderName: String?, applied: Bool, detail: String) {
        self.senderId = senderId
        self.senderName = senderName
        self.applied = applied
        self.detail = detail
    }
}

/// The answer to a write that either happened, or is now sitting in front of a
/// human.
///
/// `status` is the field an agent must read before saying anything happened:
///
/// - `done` — the app did it. Local, reversible things only.
/// - `awaiting_confirmation` — Nevermore is asking the user, and nothing has
///   happened yet. Every path that touches a sender's mailbox or reaches a third
///   party ends here.
/// - `refused` — the app declined, and `detail` says why.
public struct AgentActionResult: Sendable, Encodable, Equatable {
    public static let done = "done"
    public static let awaitingConfirmation = "awaiting_confirmation"
    public static let refused = "refused"

    public let status: String
    public let senderId: String?
    public let senderName: String?
    public let detail: String
    /// Per-sender results for a write that names several senders. Never
    /// summarised into a count.
    public let results: [AgentSenderResult]
    /// What has actually happened to these senders so far, when anything has.
    public let outcomes: [AgentOutcome]
    /// Everything the app would warn the user about for this sender, in the same
    /// words — an agent-driven unsubscribe must not be the quiet path where the
    /// caveats the UI shows go missing (TASK-30).
    public let warnings: [String]
    public let note: String?

    public init(
        status: String,
        senderId: String? = nil,
        senderName: String? = nil,
        detail: String,
        results: [AgentSenderResult] = [],
        outcomes: [AgentOutcome] = [],
        warnings: [String] = [],
        note: String? = nil
    ) {
        self.status = status
        self.senderId = senderId
        self.senderName = senderName
        self.detail = detail
        self.results = results
        self.outcomes = outcomes
        self.warnings = warnings
        self.note = note
    }
}

/// What became of a proposal after it was handed over.
public struct AgentProposalResult: Sendable, Encodable, Equatable {
    public let proposalId: String
    /// How many senders are actually under review.
    public let proposed: Int
    /// How many the agent sent.
    public let candidatesReceived: Int
    /// How many were cut by the cap.
    public let dropped: Int
    public let truncated: Bool
    public let cap: Int
    /// Senders the agent named that this mailbox has never heard of.
    public let skipped: [AgentSenderResult]
    public let note: String

    public init(
        proposalId: String, proposed: Int, candidatesReceived: Int, dropped: Int, truncated: Bool,
        cap: Int, skipped: [AgentSenderResult], note: String
    ) {
        self.proposalId = proposalId
        self.proposed = proposed
        self.candidatesReceived = candidatesReceived
        self.dropped = dropped
        self.truncated = truncated
        self.cap = cap
        self.skipped = skipped
        self.note = note
    }
}

/// Applies the cap to a proposal and says what that cost, in the words the agent
/// reads.
///
/// Separate from the app-side action layer so it can be held to its promise:
/// truncation must be *reported*, not merely performed. An agent that believes
/// three hundred senders are under review while the human sees twenty-five will
/// go on to report on senders nobody ever looked at, and a proposal is only a
/// safety mechanism for as long as it is reviewable (TASK-41).
public enum AgentProposalBuilder {
    public static func build(
        summary: String?,
        resolved: [SenderProposal.Item],
        skipped: [AgentSenderResult] = [],
        candidatesReceived: Int
    ) -> (proposal: SenderProposal, result: AgentProposalResult) {
        let (proposal, dropped) = SenderProposal.capped(summary: summary, items: resolved)
        var note =
            "Nothing has happened to these senders. The human reviews them in Nevermore and "
            + "decides; check back with get_proposal_status."
        if dropped > 0 {
            note =
                "Only the first \(proposal.items.count) of \(resolved.count) senders were put up "
                + "for review — \(dropped) were dropped by the cap of \(SenderProposal.maxItems), "
                + "and the human will never see them. Do not report them as proposed. " + note
        }
        return (
            proposal,
            AgentProposalResult(
                proposalId: proposal.id.uuidString,
                proposed: proposal.items.count,
                candidatesReceived: candidatesReceived,
                dropped: dropped,
                truncated: dropped > 0,
                cap: SenderProposal.maxItems,
                skipped: skipped,
                note: note)
        )
    }
}

/// Where the human got to with the proposal.
public struct AgentProposalStatus: Sendable, Encodable, Equatable {
    /// `none` — nothing was ever proposed in this session.
    /// `awaiting_review` — it is on screen, untouched.
    /// `edited` — the human took senders out of it and is still reviewing.
    /// `dismissed` — the human cleared it. Nothing was done to any sender.
    public static let none = "none"
    public static let awaitingReview = "awaiting_review"
    public static let edited = "edited"
    public static let dismissed = "dismissed"

    public let state: String
    public let proposalId: String?
    public let createdAt: String?
    public let summary: String?
    /// As sent, after the cap.
    public let proposedCount: Int
    /// Still under review now.
    public let remainingCount: Int
    /// The senders the human took out — the clearest signal an agent gets that
    /// its judgement was wrong about those rows.
    public let removedByHuman: [String]
    /// Per sender, for everything that has happened to any of them.
    public let outcomes: [AgentOutcome]
    public let note: String

    public init(
        state: String, proposalId: String?, createdAt: String?, summary: String?,
        proposedCount: Int, remainingCount: Int, removedByHuman: [String],
        outcomes: [AgentOutcome], note: String
    ) {
        self.state = state
        self.proposalId = proposalId
        self.createdAt = createdAt
        self.summary = summary
        self.proposedCount = proposedCount
        self.remainingCount = remainingCount
        self.removedByHuman = removedByHuman
        self.outcomes = outcomes
        self.note = note
    }
}

/// One sender in the browser queue, as an agent sees it (TASK-47).
public struct AgentBrowserQueueEntry: Sendable, Encodable, Equatable {
    public let senderId: String
    public let senderName: String
    public let senderEmail: String
    /// Why nothing automated can finish this sender.
    public let reason: String
    public let reasonDetail: String
    /// `pending`, or the outcome the human recorded.
    public let state: String
    public let queuedAt: String
    public let completedAt: String?

    public init(entry: BrowserQueue.Entry) {
        self.senderId = entry.groupKey
        self.senderName = entry.senderName
        self.senderEmail = entry.senderEmail
        self.reason = entry.reason.rawValue
        self.reasonDetail = entry.reason.explanation
        self.state = entry.outcome?.rawValue ?? AgentBrowserQueueStatus.pending
        self.queuedAt = MCPRoutes.iso(entry.queuedAt)
        self.completedAt = entry.completedAt.map(MCPRoutes.iso)
    }
}

/// The browser queue and how far through it the human is.
///
/// The answer to both queueing and asking, so an agent reads one shape either
/// way. It is also the *only* thing an agent gets: there is no route that
/// advances the queue, opens the sheet, or answers on the human's behalf, and
/// that is the point of the feature rather than a gap in it (TASK-41). The web
/// page belongs to a third party, the click is a person's, and an agent that
/// could drive it would be unsubscribing on its own say-so through a different
/// door than the one `ReviewToken` locks.
public struct AgentBrowserQueueStatus: Sendable, Encodable, Equatable {
    public static let pending = "pending"

    public let total: Int
    public let pending: Int
    /// How many the human worked and confirmed. Never the same as `total -
    /// pending`: an entry can be worked and still not be unsubscribed.
    public let confirmed: Int
    public let entries: [AgentBrowserQueueEntry]
    /// What this call did, when it was a queueing call. Per sender, including
    /// the ones that were skipped and why.
    public let results: [AgentSenderResult]
    public let note: String

    public init(
        total: Int, pending: Int, confirmed: Int, entries: [AgentBrowserQueueEntry],
        results: [AgentSenderResult] = [], note: String
    ) {
        self.total = total
        self.pending = pending
        self.confirmed = confirmed
        self.entries = entries
        self.results = results
        self.note = note
    }

    /// Every response says the same two things, because an agent may only ever
    /// see one of them: nothing has been sent, and you cannot work this queue.
    public static let humanOnlyNote =
        "Queueing sends nothing and tells the sender nothing — these entries are a to-do list for "
        + "the person at the keyboard, who opens each sender's page in Nevermore and says what "
        + "happened. There is no tool that advances this queue, opens the browser or records an "
        + "outcome, and there will not be one: the click is a human's. Poll this tool to see how "
        + "far they have got. `confirmed` is the only state that means unsubscribed; "
        + "`could_not_unsubscribe` and `abandoned` mean the sender is still mailing."

    public init(queue: BrowserQueue, results: [AgentSenderResult] = [], note: String? = nil) {
        self.init(
            total: queue.count,
            pending: queue.pendingCount,
            confirmed: queue.confirmedCount,
            entries: queue.entries.map(AgentBrowserQueueEntry.init),
            results: results,
            note: note.map { "\($0) \(Self.humanOnlyNote)" } ?? Self.humanOnlyNote)
    }
}

/// A write's answer: a result to serialise, or a refusal with an HTTP status.
///
/// The two are distinct because an agent reads them differently. A refusal is
/// the call failing — an unknown sender, a bad argument — and the bridge turns a
/// non-2xx into an MCP `isError`. A result is the call succeeding, whatever it
/// says happened, including "the user is being asked".
public enum AgentActionOutcome: Sendable {
    case result(AgentActionResult)
    case proposal(AgentProposalResult)
    case status(AgentProposalStatus)
    case browserQueue(AgentBrowserQueueStatus)
    case refusal(message: String, code: Int)
}

// MARK: - The action layer

/// One sender an agent wants reviewed, and why.
public struct AgentProposalRequest: Sendable, Equatable {
    public let senderId: String
    public let reason: String

    public init(senderId: String, reason: String) {
        self.senderId = senderId
        self.reason = reason
    }
}

/// How an agent wants a sender's mail regrouped.
public enum AgentGroupingMode: String, Sendable, Equatable, CaseIterable {
    case splitByAddress = "split_by_address"
    case keepAsOne = "keep_as_one"
}

/// Everything an agent can ask the running app to do.
///
/// The single internal action layer TASK-41 asks for: the MCP routes are one
/// caller and TASK-35's App Intents should be the second, rather than a second
/// implementation of the same verbs with its own idea of what needs confirming.
///
/// Async throughout, and `Sendable`, because the implementation lives on the
/// main actor with the app's state while the server is an actor of its own.
/// Nothing here returns a `ReviewToken`, and nothing here takes one — the batch
/// unsubscribe an agent might want does not exist on this protocol, which is
/// where that guarantee is made rather than in a policy document.
public protocol MCPActions: Sendable {
    /// Put a set of senders in front of the human, capped and with reasons.
    func propose(summary: String?, requests: [AgentProposalRequest]) async -> AgentActionOutcome
    func proposalStatus() async -> AgentActionOutcome
    /// One sender, handed to the app's existing confirmation. Never a batch.
    func requestUnsubscribe(senderId: String) async -> AgentActionOutcome
    /// Destructive, and so always confirmed by a human first.
    func requestTrash(senderId: String) async -> AgentActionOutcome
    /// Put senders that need a browser on the human's list, without attempting
    /// anything (TASK-47). A batch, unlike unsubscribing: queueing is inert.
    func queueForBrowser(senderIds: [String]) async -> AgentActionOutcome
    /// Read the queue and how far through it the human is. There is deliberately
    /// no counterpart that advances it.
    func browserQueueStatus() async -> AgentActionOutcome
    func setIgnored(_ ignored: Bool, senderIds: [String]) async -> AgentActionOutcome
    func setClassification(
        senderId: String, classification: String, reason: String, context: String?
    ) async -> AgentActionOutcome
    func startSync() async -> AgentActionOutcome
    func setGrouping(senderId: String, mode: AgentGroupingMode) async -> AgentActionOutcome
    func forgetUnsubscribeRecord(senderId: String) async -> AgentActionOutcome
}
