import AppKit
import Foundation
import NevermoreKit

/// The running app, as the MCP write routes see it (TASK-46).
///
/// The whole app-side half of the write surface, in one place, so the rule that
/// matters can be read off it: **nothing here unsubscribes from anything.** The
/// two verbs that reach a sender's mailbox or a third party — `unsubscribe` and
/// `trash_sender_messages` — put the app's own confirmation in front of the
/// user and answer `awaiting_confirmation` having done nothing. The rest are
/// local to this Mac and reversible.
///
/// There is no batch unsubscribe here because there is none on `MCPActions`, and
/// none on `MCPActions` because `AppModel.performUnsubscribe` takes a
/// `ReviewToken` that only a human confirmation mints. That is three layers
/// saying the same thing, which is deliberate: this is the one place in
/// Nevermore where a plausible-looking convenience method would be a serious
/// mistake.
///
/// `@MainActor` because it drives `AppModel`. The protocol's requirements are
/// all `async`, so the server's actor awaits its way here.
@MainActor
final class AgentActions: MCPActions {
    private weak var model: AppModel?

    /// What was last handed over, so `get_proposal_status` can tell "the human
    /// took rows out" from "this proposal was always this size". In memory: it
    /// describes one review session, and it is honest about not surviving a
    /// relaunch rather than pretending a fresh app means nothing happened.
    private var lastProposalSent: SenderProposal?

    init(model: AppModel) {
        self.model = model
    }

    // MARK: - Proposals

    func propose(summary: String?, requests: [AgentProposalRequest]) async -> AgentActionOutcome {
        guard let model else { return Self.gone }
        var items: [SenderProposal.Item] = []
        var skipped: [AgentSenderResult] = []
        for request in requests {
            guard let id = GroupID(storageKey: request.senderId),
                let group = model.group(for: id)
            else {
                skipped.append(
                    AgentSenderResult(
                        senderId: request.senderId, senderName: nil, applied: false,
                        detail:
                            "No sender with this id in the open mailbox. Ids come from "
                            + "list_senders and change when grouping changes."))
                continue
            }
            items.append(
                SenderProposal.Item(
                    groupKey: id.storageKey,
                    senderName: group.displayName,
                    senderEmail: group.latest?.sender.address ?? id.key,
                    reason: request.reason))
        }
        guard !items.isEmpty else {
            return .refusal(
                message:
                    "None of those senders are in the open mailbox, so there is nothing to review. "
                    + "Re-read list_senders for current ids.",
                code: 404)
        }

        // The cap is the product decision (TASK-41): reviewability is the safety
        // mechanism, so an unreviewable proposal is a broken one rather than a
        // large one. `AgentProposalBuilder` both applies it and says so — the
        // reporting is the half that matters, and it lives in NevermoreKit where
        // the harness can hold it to it.
        let (proposal, result) = AgentProposalBuilder.build(
            summary: summary, resolved: items, skipped: skipped,
            candidatesReceived: requests.count)
        guard model.receiveProposal(proposal) else { return Self.gone }
        lastProposalSent = proposal
        return .proposal(result)
    }

    func proposalStatus() async -> AgentActionOutcome {
        guard let model else { return Self.gone }
        let live = model.proposal
        let sent = lastProposalSent

        // Only reason about the proposal this session sent. A live proposal with
        // a different id came from somewhere else, and describing it as though
        // it were ours would invent a review that never happened.
        let ours = live.flatMap { $0.id == sent?.id ? $0 : nil }
        let sentKeys = sent?.items.map(\.groupKey) ?? []
        let remaining = Set(ours?.items.map(\.groupKey) ?? [])
        let outcomes = await model.agentOutcomes.outcomes(for: Set(sentKeys))

        // A row leaves the proposal for two opposite reasons, and telling them
        // apart matters more than it looks: acted on is the agent being right,
        // taken out is the agent being wrong. Reporting the first as the second
        // would teach it the reverse of what happened. The outcome ledger is the
        // discriminator — a sender that was acted on has one, a sender the human
        // declined does not.
        let actedKeys = model.proposalActedKeys
        let gone = sent == nil ? [] : sentKeys.filter { !remaining.contains($0) }
        let removed = gone.filter { !actedKeys.contains($0) }
        let acted = gone.filter { actedKeys.contains($0) }

        let state: String
        if sent == nil {
            state = AgentProposalStatus.none
        } else if ours == nil {
            // Everything is gone. Whether that was a decline or a finished
            // review is, again, the ledger's answer rather than a guess.
            state = acted.isEmpty ? AgentProposalStatus.dismissed : AgentProposalStatus.worked
        } else if !acted.isEmpty {
            state = AgentProposalStatus.inProgress
        } else if removed.isEmpty {
            state = AgentProposalStatus.awaitingReview
        } else {
            state = AgentProposalStatus.edited
        }
        return .status(
            AgentProposalStatus(
                state: state,
                proposalId: sent?.id.uuidString,
                createdAt: sent.map { Self.iso($0.createdAt) },
                summary: sent?.summary,
                proposedCount: sentKeys.count,
                remainingCount: remaining.count,
                removedByHuman: removed,
                outcomes: outcomes,
                note: Self.statusNote(state: state)))
    }

    private static func statusNote(state: String) -> String {
        let outcomes =
            "Each outcome is per sender and keeps Nevermore's own distinction: 'confirmed' means a "
            + "human saw the sender's confirmation page, 'requested' means the request was accepted "
            + "and nothing more — never report it as unsubscribed — 'failed' means it did not go, "
            + "and 'needs_manual' means nothing was sent and a person has to finish it in a "
            + "browser. This ledger covers the current run of the app only; unsubscribe_history is "
            + "the durable record."
        switch state {
        case AgentProposalStatus.dismissed:
            return "The human cleared the proposal. No sender was unsubscribed, ignored or "
                + "trashed by it. Treat that as a considered no rather than an invitation to "
                + "propose the same senders again. " + outcomes
        case AgentProposalStatus.edited:
            return "The human took senders out of the proposal — the clearest signal available "
                + "that the judgement was wrong about those rows. " + outcomes
        case AgentProposalStatus.awaitingReview:
            return "Still waiting on the human. Nothing has happened yet. " + outcomes
        case AgentProposalStatus.inProgress:
            return "The human is working through the proposal. Senders that have been acted on "
                + "have left the queue and appear in `outcomes`; `remaining_count` is what is "
                + "still waiting on a decision. Do not read a sender's absence as a rejection "
                + "here — check `outcomes` first. " + outcomes
        case AgentProposalStatus.worked:
            return "The human worked through the whole proposal; every sender was decided rather "
                + "than the queue being cleared. What was actually done to each one is in "
                + "`outcomes`, and `removed_by_human` names any the human declined. " + outcomes
        default:
            return "Nothing has been proposed in this run of Nevermore. " + outcomes
        }
    }

    // MARK: - Confirmed writes

    func requestUnsubscribe(senderId: String) async -> AgentActionOutcome {
        guard let model else { return Self.gone }
        guard let id = GroupID(storageKey: senderId), let group = model.group(for: id) else {
            return Self.noSuchSender(senderId)
        }
        guard model.requestAgentUnsubscribe(id) else { return Self.noSuchSender(senderId) }
        return .result(
            AgentActionResult(
                status: AgentActionResult.awaitingConfirmation,
                senderId: id.storageKey,
                senderName: group.displayName,
                detail:
                    "Nevermore is asking the user to confirm. No request has been sent, and the "
                    + "answer may be no.",
                warnings: warnings(for: group, model: model),
                note:
                    "Poll get_proposal_status for the outcome, or unsubscribe_history once it "
                    + "lands. Do not report this sender as unsubscribed on the strength of this "
                    + "call."))
    }

    func requestTrash(senderId: String) async -> AgentActionOutcome {
        guard let model else { return Self.gone }
        guard let id = GroupID(storageKey: senderId), let group = model.group(for: id) else {
            return Self.noSuchSender(senderId)
        }
        // Always `.agent`, and there is no argument that changes it: an
        // agent-initiated trash prompts however low the user set their own
        // threshold (TASK-46 acceptance criterion 6).
        model.requestTrash([id], origin: .agent)
        model.bringWindowForward()
        return .result(
            AgentActionResult(
                status: AgentActionResult.awaitingConfirmation,
                senderId: id.storageKey,
                senderName: group.displayName,
                detail:
                    "Nevermore is asking the user to confirm moving \(group.total) message"
                    + "\(group.total == 1 ? "" : "s") to Trash. Nothing has moved.",
                warnings: [
                    "Trashing does not unsubscribe. This sender keeps mailing, and the new mail "
                    + "keeps arriving."
                ],
                note: "This confirmation is unconditional — the user's trash-confirmation "
                    + "threshold applies to their own keystrokes, not to yours."))
    }

    // MARK: - The browser queue (TASK-47)

    /// Collect the senders nothing automated can finish, for the human to work
    /// through in one sitting.
    ///
    /// Unattended, and a batch, because it attempts nothing: no request goes
    /// anywhere, no sender is told anything, and the queue is a list the person
    /// at the keyboard can ignore entirely. What an agent cannot do is work it —
    /// there is no verb here that opens the sheet, advances it or records an
    /// outcome, and the sheet is the only thing that can. That is the same rule
    /// `ReviewToken` makes for the batch path, made structurally for this one:
    /// the click on a third party's page belongs to a human.
    ///
    /// It does not bring the window forward. A proposal does, because a review
    /// nobody sees is not a safety mechanism; a to-do list interrupting whatever
    /// the user was doing is just an interruption.
    func queueForBrowser(senderIds: [String]) async -> AgentActionOutcome {
        guard let model else { return Self.gone }
        var results: [AgentSenderResult] = []
        var found = 0
        for senderId in senderIds {
            guard let id = GroupID(storageKey: senderId), let group = model.group(for: id) else {
                results.append(
                    AgentSenderResult(
                        senderId: senderId, senderName: nil, applied: false,
                        detail: "No sender with this id in the open mailbox."))
                continue
            }
            found += 1
            guard let reason = model.browserReason(for: id) else {
                results.append(
                    AgentSenderResult(
                        senderId: id.storageKey, senderName: group.displayName, applied: false,
                        detail:
                            "Skipped: this sender can still be unsubscribed from without a browser "
                            + "(\(NevermoreKit.UnsubscribeMethod.of(group).rawValue)). Queueing "
                            + "them would send a person to a page for no reason."))
                continue
            }
            let queued = model.queueForBrowser(id)
            results.append(
                AgentSenderResult(
                    senderId: id.storageKey, senderName: group.displayName, applied: queued,
                    detail: queued
                        ? reason.explanation
                        : "Already waiting in the queue; left where it is."))
        }
        guard found > 0 else {
            return .refusal(
                message: "None of those senders are in the open mailbox.", code: 404)
        }
        let added = results.filter(\.applied).count
        return .browserQueue(
            AgentBrowserQueueStatus(
                queue: model.browserQueue,
                results: results,
                note: "Queued \(added) sender\(added == 1 ? "" : "s")."))
    }

    func browserQueueStatus() async -> AgentActionOutcome {
        guard let model else { return Self.gone }
        return .browserQueue(AgentBrowserQueueStatus(queue: model.browserQueue))
    }

    // MARK: - Unattended writes

    func setIgnored(_ ignored: Bool, senderIds: [String]) async -> AgentActionOutcome {
        guard let model else { return Self.gone }
        var results: [AgentSenderResult] = []
        var applied: Set<GroupID> = []
        for senderId in senderIds {
            guard let id = GroupID(storageKey: senderId), let group = model.group(for: id) else {
                results.append(
                    AgentSenderResult(
                        senderId: senderId, senderName: nil, applied: false,
                        detail: "No sender with this id in the open mailbox."))
                continue
            }
            applied.insert(id)
            results.append(
                AgentSenderResult(
                    senderId: id.storageKey, senderName: group.displayName, applied: true,
                    detail: ignored ? "hidden from the working list" : "back in the working list"))
        }
        guard !applied.isEmpty else {
            return .refusal(
                message: "None of those senders are in the open mailbox.", code: 404)
        }
        if ignored {
            // Silently: the toast is an undo affordance for something the user
            // just did, and one that appears for an action they did not take is
            // an offer to undo a thing they never saw happen.
            model.ignore(applied, silently: true)
        } else {
            model.unignore(applied)
        }
        return .result(
            AgentActionResult(
                status: AgentActionResult.done,
                detail: ignored
                    ? "Hidden on this Mac only. The sender keeps mailing and is not unsubscribed."
                    : "Back in the working list.",
                results: results,
                note: "Reversible with \(ignored ? "unignore" : "ignore"), and invisible to the "
                    + "sender either way."))
    }

    func setClassification(
        senderId: String, classification: String, reason: String, context: String?
    ) async -> AgentActionOutcome {
        guard let model else { return Self.gone }
        guard let id = GroupID(storageKey: senderId), let group = model.group(for: id) else {
            return Self.noSuchSender(senderId)
        }
        let addresses = model.recordAgentDecision(
            id, classification: classification, reason: reason, context: context)
        guard addresses > 0 else { return Self.noSuchSender(senderId) }
        return .result(
            AgentActionResult(
                status: AgentActionResult.done,
                senderId: id.storageKey,
                senderName: group.displayName,
                detail:
                    "Recorded '\(classification)' against \(addresses) address"
                    + "\(addresses == 1 ? "" : "es") in this group.",
                note:
                    "Stored verbatim and never interpreted. Kept per address, so it survives the "
                    + "group being split or merged, and it outlives the sender's mail."))
    }

    func startSync() async -> AgentActionOutcome {
        guard let model else { return Self.gone }
        let alreadyRunning = model.isSyncing
        model.startSync()
        return .result(
            AgentActionResult(
                status: AgentActionResult.done,
                detail: alreadyRunning
                    ? "A sync was already running; it was left to finish rather than restarted."
                    : "Sync started.",
                note: "Returns as soon as the sync starts. Poll sync_status for progress."))
    }

    func setGrouping(senderId: String, mode: AgentGroupingMode) async -> AgentActionOutcome {
        guard let model else { return Self.gone }
        guard let id = GroupID(storageKey: senderId), model.group(for: id) != nil else {
            return Self.noSuchSender(senderId)
        }
        switch mode {
        case .splitByAddress: model.splitByAddress(id)
        case .keepAsOne: model.keepAsOneGroup(id)
        }
        return .result(
            AgentActionResult(
                status: AgentActionResult.done,
                senderId: id.storageKey,
                detail: mode == .splitByAddress
                    ? "This domain's addresses are now separate senders."
                    : "This domain's addresses are now one sender.",
                note:
                    "Sender ids are derived from grouping, so the ids you hold for this domain are "
                    + "now stale. Re-read list_senders before acting on them."))
    }

    func forgetUnsubscribeRecord(senderId: String) async -> AgentActionOutcome {
        guard let model else { return Self.gone }
        guard let id = GroupID(storageKey: senderId) else { return Self.noSuchSender(senderId) }
        guard model.unsubscribeRecord(for: id) != nil else {
            return .refusal(
                message: "Nevermore has no unsubscribe record for '\(senderId)' to forget.",
                code: 404)
        }
        model.forget([id])
        return .result(
            AgentActionResult(
                status: AgentActionResult.done,
                senderId: id.storageKey,
                detail: "The record is gone and the sender is back in the working list.",
                warnings: [
                    "Forgetting the record does not undo anything with the sender. They were still "
                    + "sent an unsubscribe request, and unsubscribing again is a real second "
                    + "request."
                ]))
    }

    // MARK: - Helpers

    /// The caveats the app would put in front of the user for this sender, so
    /// the agent-driven path is not the quiet one where they go missing
    /// (TASK-30, still unresolved: Nevermore has no spammer-specific warning to
    /// pass on yet, and inventing one here would be inventing a product
    /// decision).
    private func warnings(for group: SenderGroup, model: AppModel) -> [String] {
        var out = [
            "Unsubscribing tells this sender the address is live and read. That is worth nothing "
            + "against a legitimate mailing list and worth something to a spammer."
        ]
        if let listID = group.mailingListID {
            out.append(
                "This is a mailing list (\(listID)), not a marketing blast — unsubscribing leaves "
                + "the conversation.")
        }
        if let source = group.unsubscribeSource, !source.deliveredTo.isEmpty,
            source.deliveredTo != model.currentAccount,
            model.sendAsFrom(for: source.deliveredTo) == nil
        {
            out.append(
                "This mail was delivered to \(source.deliveredTo), which this account cannot send "
                + "as. A mailto:-only unsubscribe will be handed to the manual flow rather than "
                + "sent from the wrong identity.")
        }
        if model.hasPriorAttempt(group.id) {
            out.append(
                "An unsubscribe was already recorded for this sender. If they are still mailing, "
                + "the automated path did not work and a person has to finish it in a browser.")
        }
        return out
    }

    private static var gone: AgentActionOutcome {
        .refusal(
            message: "Nevermore is no longer holding a mailbox open. Try again once it is running "
                + "with an account open.",
            code: 503)
    }

    private static func noSuchSender(_ senderId: String) -> AgentActionOutcome {
        .refusal(
            message:
                "No sender with id '\(senderId)' in the open mailbox. Ids come from list_senders "
                + "and change when grouping changes.",
            code: 404)
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
