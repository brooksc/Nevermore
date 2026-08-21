import Foundation

/// Arguments for the write tools, in the same tolerant shape the read routes
/// use: every field optional, an absent body an empty request, and whatever this
/// route doesn't use ignored.
public struct MCPWriteRequest: Decodable, Sendable {
    /// One proposed sender and the agent's reason for proposing it.
    public struct ProposedItem: Decodable, Sendable {
        public var senderId: String?
        public var reason: String?
    }

    public var senderId: String?
    public var senderIds: [String]?
    public var summary: String?
    public var senders: [ProposedItem]?
    public var classification: String?
    public var reason: String?
    public var context: String?
    public var mode: String?

    public init() {}
}

/// What an agent may do unattended, so it can plan a session instead of finding
/// out mid-batch.
public struct MCPPolicy: Sendable, Encodable, Equatable {
    /// Tools that complete on their own. All of them are local to this Mac and
    /// reversible.
    public let unattended: [String]
    /// Tools that hand the decision to the person at the keyboard and return
    /// `awaiting_confirmation` having done nothing.
    public let requiresHumanConfirmation: [String]
    /// Always false, and not a setting. See `noBatchUnsubscribe`.
    public let batchUnsubscribeAvailable: Bool
    public let noBatchUnsubscribe: String
    public let proposalCap: Int
    public let note: String
}

/// The write surface: eleven tools, every one of them narrow on purpose.
///
/// **Read this before adding a route here.** The safety argument of the whole
/// MCP feature is that an agent classifies and a human actuates. Concretely:
///
/// - There is no batch unsubscribe. Not a gated one, not a policy-controlled
///   one, not one behind a flag — the verb does not exist on `MCPActions`, so
///   there is nothing for a route to call. Bulk goes through a proposal the
///   human reviews in the app, and the app's own batch path takes a
///   `ReviewToken` that only a human confirmation mints.
/// - `unsubscribe` is one sender and stages the app's existing confirmation.
/// - `trash_sender_messages` always stages a confirmation, whatever the user's
///   trash threshold says (`TrashConfirmation`).
/// - Nothing here accepts or returns a review token. An agent has no wire
///   representation of one, so replay is not a thing it can attempt.
///
/// Handlers are `(MCPWriteRequest, any MCPActions) -> AgentActionOutcome`, so
/// the whole surface is exercisable in the harness against a stub action layer —
/// which is the only way it can be proven, since TASK-41 refuses these routes in
/// demo mode and there is no other mailbox a test may drive.
public enum MCPWriteRoutes {
    public static let paths: Set<String> = [
        "/mcp/proposal/create",
        "/mcp/proposal/status",
        "/mcp/senders/unsubscribe",
        "/mcp/browser-queue/add",
        "/mcp/browser-queue/status",
        "/mcp/senders/trash",
        "/mcp/senders/ignore",
        "/mcp/senders/unignore",
        "/mcp/senders/classify",
        "/mcp/senders/grouping",
        "/mcp/unsubscribe/forget",
        "/mcp/sync/start",
        "/mcp/policy",
    ]

    /// The one route that answers without a mailbox: an agent asks what it may
    /// do *before* it has anything to do, and failing here would send it into a
    /// session with no idea where the walls are.
    public static let policyPath = "/mcp/policy"

    public static let unattendedTools = [
        "propose_selection", "get_proposal_status", "queue_for_browser", "get_browser_queue",
        "ignore", "unignore", "set_classification", "start_sync", "set_grouping",
        "forget_unsubscribe_record", "get_policy",
    ]

    public static let confirmedTools = ["unsubscribe", "trash_sender_messages"]

    public static let policy = MCPPolicy(
        unattended: unattendedTools,
        requiresHumanConfirmation: confirmedTools,
        batchUnsubscribeAvailable: false,
        noBatchUnsubscribe:
            "There is no bulk unsubscribe over MCP and there will not be one. Unsubscribing is "
            + "irreversible and goes to a third party, so a set of senders is unsubscribed only "
            + "after a human has reviewed that exact set in Nevermore and confirmed it. Propose "
            + "with propose_selection and check back with get_proposal_status; do not look for a "
            + "batch tool, a policy setting or a token that would skip this.",
        proposalCap: SenderProposal.maxItems,
        note:
            "The unattended tools are local to this Mac and reversible: they change what Nevermore "
            + "shows and remembers, never the mailbox and never anything a sender can see. "
            + "unsubscribe and trash_sender_messages return awaiting_confirmation having done "
            + "nothing at all — read `status` before reporting that anything happened.")

    /// Serve one already-authenticated write request.
    ///
    /// Returns nil when the path isn't a write route, so the caller can go on to
    /// the read routes and answer 404 about the route rather than the credential.
    public static func handle(
        path: String, request: HTTPRequest, actions: (any MCPActions)?
    ) async -> HTTPResponse? {
        guard paths.contains(path) else { return nil }
        if path == policyPath { return MCPRoutes.json(policy) }

        // Nil actions means the app is not accepting agent actions — no mailbox
        // is open. Refusing beats a write that silently lands nowhere.
        guard let actions else {
            return .error(
                "No mailbox is open in Nevermore. Open an account in the app and try again.",
                code: 503)
        }

        let args: MCPWriteRequest
        do {
            args = try decodeArguments(request)
        } catch {
            return .error("Could not read the tool arguments as JSON: \(error)", code: 400)
        }

        switch path {
        case "/mcp/proposal/create": return respond(await propose(args, actions))
        case "/mcp/proposal/status": return respond(await actions.proposalStatus())
        case "/mcp/senders/unsubscribe": return respond(await unsubscribe(args, actions))
        case "/mcp/browser-queue/add": return respond(await queueForBrowser(args, actions))
        case "/mcp/browser-queue/status": return respond(await actions.browserQueueStatus())
        case "/mcp/senders/trash": return respond(await trash(args, actions))
        case "/mcp/senders/ignore": return respond(await setIgnored(true, args, actions))
        case "/mcp/senders/unignore": return respond(await setIgnored(false, args, actions))
        case "/mcp/senders/classify": return respond(await classify(args, actions))
        case "/mcp/senders/grouping": return respond(await grouping(args, actions))
        case "/mcp/unsubscribe/forget": return respond(await forget(args, actions))
        case "/mcp/sync/start": return respond(await actions.startSync())
        default: return nil
        }
    }

    static func decodeArguments(_ request: HTTPRequest) throws -> MCPWriteRequest {
        guard let body = request.body, !body.isEmpty else { return MCPWriteRequest() }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(MCPWriteRequest.self, from: body)
    }

    static func respond(_ outcome: AgentActionOutcome) -> HTTPResponse {
        switch outcome {
        case let .result(result): MCPRoutes.json(result)
        case let .proposal(result): MCPRoutes.json(result)
        case let .status(status): MCPRoutes.json(status)
        case let .browserQueue(status): MCPRoutes.json(status)
        case let .refusal(message, code): .error(message, code: code)
        }
    }

    // MARK: - Handlers

    static func propose(_ args: MCPWriteRequest, _ actions: any MCPActions) async
        -> AgentActionOutcome
    {
        guard let raw = args.senders, !raw.isEmpty else {
            return .refusal(
                message:
                    "propose_selection needs `senders`: a list of {sender_id, reason} objects. The "
                    + "reason is what makes the proposal reviewable, so it is required for every "
                    + "sender.",
                code: 400)
        }
        var requests: [AgentProposalRequest] = []
        for item in raw {
            guard let senderId = item.senderId?.trimmingCharacters(in: .whitespacesAndNewlines),
                !senderId.isEmpty
            else {
                return .refusal(
                    message: "Every entry in `senders` needs a sender_id, as returned by list_senders.",
                    code: 400)
            }
            guard let reason = item.reason?.trimmingCharacters(in: .whitespacesAndNewlines),
                !reason.isEmpty
            else {
                return .refusal(
                    message:
                        "'\(senderId)' has no reason. A row the human cannot see a reason for is a "
                        + "row they can only rubber-stamp, which is the one thing this review is "
                        + "for.",
                    code: 400)
            }
            requests.append(AgentProposalRequest(senderId: senderId, reason: reason))
        }
        let summary = args.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        return await actions.propose(
            summary: (summary?.isEmpty ?? true) ? nil : summary, requests: requests)
    }

    static func unsubscribe(_ args: MCPWriteRequest, _ actions: any MCPActions) async
        -> AgentActionOutcome
    {
        // A list here is an agent reaching for the batch path. Say why it isn't
        // there rather than quietly acting on the first one.
        if let ids = args.senderIds, ids.count > 1 {
            return .refusal(message: policy.noBatchUnsubscribe, code: 400)
        }
        guard let id = singleSender(args) else {
            return .refusal(
                message: "unsubscribe needs one sender_id, as returned by list_senders.", code: 400)
        }
        return await actions.requestUnsubscribe(senderId: id)
    }

    /// A list is allowed here, and that is not an inconsistency with
    /// `unsubscribe` refusing one. Queueing sends nothing, tells no sender
    /// anything, and is undone by the human ignoring the list — the thing bulk
    /// unsubscribe would buy an agent is exactly what this does not do.
    static func queueForBrowser(_ args: MCPWriteRequest, _ actions: any MCPActions) async
        -> AgentActionOutcome
    {
        let ids = senderList(args)
        guard !ids.isEmpty else {
            return .refusal(
                message:
                    "queue_for_browser needs sender_ids (or a single sender_id), as returned by "
                    + "list_senders. list_senders(needs_browser: true) is the set this is for.",
                code: 400)
        }
        return await actions.queueForBrowser(senderIds: ids)
    }

    static func trash(_ args: MCPWriteRequest, _ actions: any MCPActions) async
        -> AgentActionOutcome
    {
        guard let id = singleSender(args) else {
            return .refusal(
                message: "trash_sender_messages needs one sender_id, as returned by list_senders.",
                code: 400)
        }
        return await actions.requestTrash(senderId: id)
    }

    static func setIgnored(_ ignored: Bool, _ args: MCPWriteRequest, _ actions: any MCPActions)
        async -> AgentActionOutcome
    {
        let ids = senderList(args)
        guard !ids.isEmpty else {
            return .refusal(
                message:
                    "\(ignored ? "ignore" : "unignore") needs sender_ids (or a single sender_id), "
                    + "as returned by list_senders.",
                code: 400)
        }
        return await actions.setIgnored(ignored, senderIds: ids)
    }

    static func classify(_ args: MCPWriteRequest, _ actions: any MCPActions) async
        -> AgentActionOutcome
    {
        guard let id = singleSender(args) else {
            return .refusal(
                message: "set_classification needs a sender_id, as returned by list_senders.",
                code: 400)
        }
        guard let classification = nonEmpty(args.classification) else {
            return .refusal(
                message:
                    "set_classification needs a classification — your own label, stored verbatim "
                    + "and never interpreted.",
                code: 400)
        }
        guard let reason = nonEmpty(args.reason) else {
            return .refusal(
                message:
                    "set_classification needs a reason. The record exists so a later session can "
                    + "read why, and a classification with no reason cannot answer that.",
                code: 400)
        }
        return await actions.setClassification(
            senderId: id, classification: classification, reason: reason,
            context: nonEmpty(args.context))
    }

    static func grouping(_ args: MCPWriteRequest, _ actions: any MCPActions) async
        -> AgentActionOutcome
    {
        guard let id = singleSender(args) else {
            return .refusal(
                message: "set_grouping needs a sender_id, as returned by list_senders.", code: 400)
        }
        guard let raw = nonEmpty(args.mode), let mode = AgentGroupingMode(rawValue: raw) else {
            return .refusal(
                message: "set_grouping needs a mode: "
                    + AgentGroupingMode.allCases.map(\.rawValue).joined(separator: " or ") + ".",
                code: 400)
        }
        return await actions.setGrouping(senderId: id, mode: mode)
    }

    static func forget(_ args: MCPWriteRequest, _ actions: any MCPActions) async
        -> AgentActionOutcome
    {
        guard let id = singleSender(args) else {
            return .refusal(
                message: "forget_unsubscribe_record needs a sender_id.", code: 400)
        }
        return await actions.forgetUnsubscribeRecord(senderId: id)
    }

    // MARK: - Helpers

    /// One sender from either spelling, so `sender_id` and a one-element
    /// `sender_ids` mean the same thing.
    static func singleSender(_ args: MCPWriteRequest) -> String? {
        nonEmpty(args.senderId) ?? args.senderIds.flatMap { $0.count == 1 ? nonEmpty($0[0]) : nil }
    }

    static func senderList(_ args: MCPWriteRequest) -> [String] {
        var seen = Set<String>()
        return ((args.senderIds ?? []) + [args.senderId].compactMap { $0 })
            .compactMap(nonEmpty)
            .filter { seen.insert($0).inserted }
    }

    static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
