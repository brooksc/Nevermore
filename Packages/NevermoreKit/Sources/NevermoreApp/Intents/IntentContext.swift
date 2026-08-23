import AppIntents
import Foundation
import NevermoreKit

/// Why an intent could not run. Each case is a distinct thing a person building
/// a shortcut can fix, so none of them is flattened into "something went wrong".
enum NevermoreIntentError: Error, CustomLocalizedStringResourceConvertible {
    /// The app is not running, or is running with no mailbox open.
    case noMailbox
    /// The demo mailbox is open. Its senders are fabricated.
    case demoMailbox
    /// The action layer answered something a Shortcut must never receive. See
    /// `IntentContext.detail(of:)`.
    case notAutomatable(String)
    /// The app declined, in its own words.
    case refused(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noMailbox:
            "Nevermore has no mailbox open. Open Nevermore and sign in, then run this shortcut again."
        case .demoMailbox:
            "Nevermore is in demo mode. Its senders are fabricated, so shortcuts refuse to act on them — leave demo mode first."
        case .notAutomatable(let detail):
            "\(detail)"
        case .refused(let detail):
            "\(detail)"
        }
    }
}

/// The only door an App Intent has into the running app (TASK-35).
///
/// Every verb goes through `AgentActions` — the single internal action layer
/// TASK-41 asked for and TASK-46 built — so a shortcut and an MCP client get the
/// same behaviour, the same wording and the same refusals rather than two
/// implementations that agree today.
///
/// The intents do not hold an `any MCPActions` themselves, and that is
/// deliberate: the protocol carries `requestUnsubscribe` and `requestTrash`, and
/// an intent holding it could call them. What an intent can reach is the four
/// methods below, which is `ShortcutVerb` and nothing else.
@MainActor
enum IntentContext {
    private static func model() throws -> AppModel {
        guard let model = AppModel.current else { throw NevermoreIntentError.noMailbox }
        // Demo mode is refused for the same reason the MCP surface refuses it:
        // acting on a fabricated mailbox and reporting it as a result would be
        // reporting something that never happened.
        guard !model.isDemoMode else { throw NevermoreIntentError.demoMailbox }
        guard model.currentAccount != nil else { throw NevermoreIntentError.noMailbox }
        return model
    }

    // MARK: - The verbs

    static func sync() async throws -> String {
        let model = try model()
        // Guarded here rather than trusted downstream: `AppModel.startSync()` is
        // a silent no-op with no backend open, and the action layer reports
        // "Sync started." either way. That answer is fine for MCP, whose write
        // surface only exists while a mailbox is open; an intent has no such
        // gate, so it does its own.
        return try detail(of: await model.agentActions.startSync())
    }

    static func setIgnored(_ ignored: Bool, _ senders: [SenderEntity]) async throws -> String {
        let model = try model()
        guard !senders.isEmpty else {
            throw NevermoreIntentError.refused("No senders were given to this shortcut.")
        }
        let outcome = await model.agentActions.setIgnored(ignored, senderIds: senders.map(\.id))
        return try detail(of: outcome)
    }

    static func reappeared() throws -> [SenderEntity] {
        let model = try model()
        return model.groups(in: .reappeared)
            .map { entity(for: $0, in: model) }
            // Worst first: the sender who has sent eleven more is the one the
            // shortcut is being run to find.
            .sorted { $0.messagesSinceUnsubscribe > $1.messagesSinceUnsubscribe }
    }

    /// Every sender in the open mailbox, for the entity picker. Across all
    /// collections — a shortcut that unignores a sender has to be able to name
    /// one that is currently ignored.
    static func allSenders() throws -> [SenderEntity] {
        let model = try model()
        return model.groups.map { entity(for: $0, in: model) }
    }

    // MARK: - Helpers

    private static func entity(for group: SenderGroup, in model: AppModel) -> SenderEntity {
        SenderEntity(
            id: group.id.storageKey,
            name: group.displayName,
            email: group.latest?.sender.address ?? group.id.key,
            messageCount: group.total,
            messagesSince: model.messagesSinceUnsubscribe(group.id))
    }

    /// Turn the action layer's answer into something a shortcut can show, or
    /// throw.
    ///
    /// `awaiting_confirmation` is the interesting case. It is the honest answer
    /// for MCP — a human is being asked, right now, at a keyboard they are
    /// sitting at. It is never the right answer for a Shortcut, which may be
    /// running on a schedule with nobody there, so reaching it means a verb that
    /// needs a human has been wired to an intent. Failing loudly is the point:
    /// this is the second lock on the same door as `ShortcutVerb`, and it does
    /// not depend on anyone having kept that list up to date.
    private static func detail(of outcome: AgentActionOutcome) throws -> String {
        switch outcome {
        case .result(let result):
            switch result.status {
            case AgentActionResult.done:
                let perSender = result.results
                    .filter(\.applied)
                    .map(\.senderName)
                    .compactMap { $0 }
                return perSender.isEmpty
                    ? result.detail
                    : "\(result.detail) (\(perSender.joined(separator: ", ")))"
            case AgentActionResult.awaitingConfirmation:
                throw NevermoreIntentError.notAutomatable(
                    "This needs a person to confirm it in Nevermore, so it cannot run from a "
                    + "shortcut. Nothing happened.")
            default:
                throw NevermoreIntentError.refused(result.detail)
            }
        case .refusal(let message, _):
            throw NevermoreIntentError.refused(message)
        case .proposal, .status, .browserQueue:
            // None of these are reachable from the four verbs above; if one
            // arrives, something was rewired and the shortcut should not invent
            // a summary of it.
            throw NevermoreIntentError.notAutomatable(
                "Nevermore answered with something a shortcut has no way to report. Nothing was "
                + "changed.")
        }
    }
}
