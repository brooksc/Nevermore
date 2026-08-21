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
public enum SenderCollection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case allSenders
    case reappeared
    case unsubscribed, ignored

    public var id: String { rawValue }
}

/// What Nevermore knows about one sender, independent of which list is on screen.
public struct SenderState: Hashable, Sendable {
    /// Hidden on this Mac. Local-only; nothing is touched on the server.
    public var isIgnored: Bool
    /// There is a recorded unsubscribe attempt for this sender.
    public var isUnsubscribed: Bool
    /// They mailed again *after* that attempt — the request didn't stick.
    public var hasReappeared: Bool
    /// False once the sender's messages are gone from the mailbox and only the
    /// unsubscribe record survives. Unsubscribed keeps listing them, so a row
    /// there can have nothing left to unsubscribe from, open, or trash.
    public var hasMessages: Bool

    public init(
        isIgnored: Bool = false,
        isUnsubscribed: Bool = false,
        hasReappeared: Bool = false,
        hasMessages: Bool = true
    ) {
        self.isIgnored = isIgnored
        self.isUnsubscribed = isUnsubscribed
        self.hasReappeared = hasReappeared
        self.hasMessages = hasMessages
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

    public init(collection: SenderCollection, count: Int, withMessages: Int) {
        self.collection = collection
        self.count = count
        self.withMessages = withMessages
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
            case .allSenders, .ignored: return "There's no unsubscribe record to forget."
            }
        }
    }
}
