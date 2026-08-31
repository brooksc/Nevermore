import Foundation

/// The sidebar collections.
///
/// "Unsubscribable" and "Manual only" were removed: every sender we discover is
/// found *by* its List-Unsubscribe header, so "Unsubscribable" always equalled
/// "All Senders" and "Manual only" was always empty. The remaining destinations
/// are genuinely distinct sender *states*, not filters of one list.
///
/// Lives here, not in the app, so what belongs in a collection and what may be
/// done to a selection in one are answerable without a store, a backend, or a
/// UI — the app was carrying four hand-written variants of both. How a
/// collection is *presented* (title, icon, sidebar section) stays in the app.
///
/// Named `SenderCollection` rather than `Collection`: the short name shadowed
/// `Swift.Collection` throughout this module, which surfaced as a compile error
/// in any file that had forgotten to import NevermoreKit — a confusing symptom
/// for an unrelated cause.
/// (continued) `proposed` is appended last rather than slotted next to
/// `allSenders` because the ⌘-number for a collection is its position in
/// `allCases` — inserting it anywhere else would renumber shortcuts that are
/// documented, muscle-memorised, and nothing to do with this feature.
public enum SenderCollection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case allSenders
    case reappeared
    case unsubscribed, ignored
    case proposed

    public var id: String { rawValue }
}

/// What Nevermore knows about one sender, independent of which list is on screen.
public struct SenderState: Hashable, Sendable {
    /// Hidden on this Mac. Local-only; nothing is touched on the server.
    public var isIgnored: Bool
    /// This sender was actually unsubscribed from — a record whose outcome is
    /// `requested` or `confirmed`.
    ///
    /// Not "there is a record": an attempt the user said did not go through
    /// (`.failed`) leaves a record too, and reading that as an unsubscribe is
    /// what moved a sender the user wanted to block into the archive (TASK-57).
    public var isUnsubscribed: Bool
    /// They mailed again *after* that attempt — the request didn't stick.
    public var hasReappeared: Bool
    /// False once the sender's messages are gone from the mailbox and only the
    /// unsubscribe record survives. Unsubscribed keeps listing them, so a row
    /// there can have nothing left to unsubscribe from, open, or trash.
    public var hasMessages: Bool
    /// An external agent has put this sender forward for review.
    ///
    /// An overlay on whatever the sender already is, not a state of its own: a
    /// proposed sender stays listed wherever it was listed before. A proposal
    /// is a suggestion, and nothing has happened to the sender until the human
    /// says so — moving it out of All Senders would be the app acting on the
    /// agent's say-so, which is exactly what this feature refuses to do.
    public var isProposed: Bool

    public init(
        isIgnored: Bool = false,
        isUnsubscribed: Bool = false,
        hasReappeared: Bool = false,
        hasMessages: Bool = true,
        isProposed: Bool = false
    ) {
        self.isIgnored = isIgnored
        self.isUnsubscribed = isUnsubscribed
        self.hasReappeared = hasReappeared
        self.hasMessages = hasMessages
        self.isProposed = isProposed
    }
}

extension SenderCollection {
    /// Whether a sender in this state belongs in this collection.
    public func contains(_ state: SenderState) -> Bool {
        switch self {
        // Once a sender has been unsubscribed it leaves the working list — it
        // lives in Unsubscribed, or in Reappeared if it starts mailing again.
        case .allSenders: !state.isIgnored && !state.isUnsubscribed
        case .ignored: state.isIgnored
        case .unsubscribed: state.isUnsubscribed && !state.hasReappeared
        case .reappeared: !state.isIgnored && state.isUnsubscribed && state.hasReappeared
        // The one collection that overlaps the others: a proposed sender is
        // still listed wherever it already lived. `allCases` puts this last, so
        // anything asking "which collection is this sender in" still gets the
        // sender's actual state rather than "under review".
        case .proposed: state.isProposed
        }
    }
}

/// Every verb the app performs on a selection.
///
/// One list, answered in one place, so the toolbar, the Actions menu, the
/// context menus and the single-key shortcuts cannot drift apart — they did,
/// which is how ⌘U stayed enabled in Ignored and acted on a stale sender.
public enum SelectionAction: String, CaseIterable, Sendable {
    case unsubscribe
    case unsubscribeAndDelete
    case viewLatestMessage
    case ignore
    case unignore
    case trash
    case forget
}

/// The selection, as the availability rules see it.
public struct SelectionContext: Hashable, Sendable {
    public var collection: SenderCollection
    /// Rows selected *in the collection on screen*. A selection is never
    /// carried across a switch, so this is simply the selection's size.
    public var count: Int
    /// How many of those still have messages in the mailbox to act on.
    public var withMessages: Int
    /// How many already carry a recorded unsubscribe.
    ///
    /// Only Proposed needs this, and only because it is the one collection that
    /// can list a sender who has *already* been dealt with: the proposal is a
    /// durable record of what the agent put forward, so acting on a row doesn't
    /// remove it. Everywhere else the collection itself answers the question —
    /// an unsubscribed sender has left All Senders by definition.
    public var alreadyUnsubscribed: Int

    public init(
        collection: SenderCollection, count: Int, withMessages: Int, alreadyUnsubscribed: Int = 0
    ) {
        self.collection = collection
        self.count = count
        self.withMessages = withMessages
        self.alreadyUnsubscribed = alreadyUnsubscribed
    }
}

extension SelectionAction {
    /// Why this action can't run on the current selection, or nil when it can.
    ///
    /// A sentence rather than a Bool because it becomes the disabled control's
    /// tooltip: a control that is greyed out for no stated reason is
    /// indistinguishable from one that is broken.
    public func unavailability(in context: SelectionContext) -> String? {
        guard context.count > 0 else { return "Select a sender first." }

        func needsMessages(_ why: String) -> String? {
            context.withMessages == context.count ? nil : why
        }

        switch self {
        case .unsubscribe, .unsubscribeAndDelete:
            switch context.collection {
            case .ignored:
                return "Ignored senders are hidden, not unsubscribed. Unignore them first."
            case .unsubscribed:
                // Reappeared is the one place re-unsubscribing makes sense, and
                // it escalates to the browser rather than retrying what failed.
                return "Already unsubscribed. Forget the record to unsubscribe again."
            case .proposed:
                // Proposed reviews senders that are otherwise ordinary, so it
                // can do everything All Senders can — reviewing a proposal you
                // can't act on would leave the human bouncing between two lists
                // to finish it. With one difference: acting on a row does not
                // remove it from the proposal, so unlike All Senders this list
                // can still be showing a sender who is already done. Firing a
                // second round of live requests at them is the mistake this
                // collection exists to prevent.
                if context.alreadyUnsubscribed == context.count {
                    return "Already unsubscribed. Forget the record to unsubscribe again."
                }
                if context.alreadyUnsubscribed > 0 {
                    return "Some of these are already unsubscribed. Deselect them first."
                }
                return needsMessages("Their messages are no longer in this mailbox.")
            case .allSenders, .reappeared:
                return needsMessages("Their messages are no longer in this mailbox.")
            }
        case .viewLatestMessage:
            guard context.count == 1 else { return "Select a single sender." }
            return needsMessages("There's no message left to open.")
        case .ignore:
            return context.collection == .ignored ? "Already ignored." : nil
        case .unignore:
            return context.collection == .ignored ? nil : "These senders aren't ignored."
        case .trash:
            return needsMessages("There are no messages left to trash.")
        case .forget:
            switch context.collection {
            case .unsubscribed, .reappeared: return nil
            // The escape hatch the refusal above points at has to exist here,
            // or "forget the record to unsubscribe again" names an action the
            // user can't reach from the list they're standing in.
            case .proposed:
                return context.alreadyUnsubscribed == context.count
                    ? nil : "There's no unsubscribe record to forget."
            case .allSenders, .ignored:
                return "There's no unsubscribe record to forget."
            }
        }
    }
}
