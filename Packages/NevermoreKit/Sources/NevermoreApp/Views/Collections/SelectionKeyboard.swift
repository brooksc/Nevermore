import SwiftUI
import NevermoreKit

/// Single-key triage while a list is focused, for every collection.
///
/// One modifier rather than a copy per view: the shortcuts were only ever wired
/// to the All Senders table, so j/k/u/v/i/d did nothing in the other three
/// lists. A collection gets the whole keyboard model by applying this.
///
/// Keys whose action isn't available here are swallowed rather than passed on —
/// u in Ignored would otherwise beep. The Actions menu says why, with the same
/// rule (`AppModel.reason`) behind the tooltip.
struct SelectionKeyboard: ViewModifier {
    @Bindable var model: AppModel
    var onUnsubscribe: (Set<GroupID>) -> Void
    var onUnsubscribeAndDelete: (Set<GroupID>) -> Void

    func body(content: Content) -> some View {
        content
            // j/k move; u/i/d act on the selection; ? opens the shortcut list.
            // (⌘-shortcuts also work via menus.)
            .onKeyPress("j") { model.moveSelection(by: 1); return .handled }
            .onKeyPress("k") { model.moveSelection(by: -1); return .handled }
            // u unsubscribes; ⇧U unsubscribes *and* trashes with no confirmation —
            // the full-speed triage stroke. Recoverable via the provider's Trash
            // and ⌘Z, which is what makes skipping the confirm defensible.
            //
            // One handler taking both cases: the plain `onKeyPress(KeyEquivalent)`
            // overload doesn't match a shifted key at all, so ⇧U silently did
            // nothing. This form gets the modifiers. Both cases are listed because
            // the reported key is "U" or "u" depending on the shift state.
            .onKeyPress(keys: ["u", "U"]) { press in
                let alsoDelete = press.modifiers.contains(.shift)
                guard model.can(alsoDelete ? .unsubscribeAndDelete : .unsubscribe) else {
                    return .handled
                }
                if alsoDelete {
                    onUnsubscribeAndDelete(model.selection)
                } else {
                    onUnsubscribe(model.selection)
                }
                return .handled
            }
            // v opens the newest message in the browser — read it, then decide.
            // It reports why when it can't, so the key is never simply dead.
            .onKeyPress("v") { model.viewLatestMessage(); return .handled }
            // Ignore/trash advance to the next row so triage keeps flowing.
            .onKeyPress("i") {
                if model.can(.ignore) { model.ignoreAndAdvance() }
                return .handled
            }
            .onKeyPress("d") {
                if model.can(.trash) { model.trashAndAdvance() }
                return .handled
            }
            .onKeyPress(.init("?")) { model.showShortcuts = true; return .handled }
    }
}

extension View {
    func selectionKeyboard(
        model: AppModel,
        onUnsubscribe: @escaping (Set<GroupID>) -> Void,
        onUnsubscribeAndDelete: @escaping (Set<GroupID>) -> Void
    ) -> some View {
        modifier(
            SelectionKeyboard(
                model: model,
                onUnsubscribe: onUnsubscribe,
                onUnsubscribeAndDelete: onUnsubscribeAndDelete))
    }
}
