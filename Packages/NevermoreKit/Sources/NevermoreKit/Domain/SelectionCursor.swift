import Foundation

/// Where the selection should land as rows come and go.
///
/// Pure index arithmetic over an ordered list, deliberately kept out of the
/// view model so it can be tested without a store, a backend, or a UI.
///
/// The rules exist because `Set` has no order: reading `selection.first` to
/// decide "the next row" picks an arbitrary member, which is invisible with one
/// row selected and wrong with several.
public enum SelectionCursor {
    /// The row to select once `selected` is removed from `ordered`.
    ///
    /// Lands on the first surviving row *below* the selection, falling back to
    /// the nearest surviving row above it, and nil when nothing survives.
    /// Skips other selected rows, which are about to vanish too — landing on
    /// one leaves the table pointing at a row that no longer exists.
    public static func rowAfterRemoving(
        _ selected: Set<GroupID>, from ordered: [GroupID]
    ) -> GroupID? {
        guard !selected.isEmpty, !ordered.isEmpty else { return nil }
        let selectedIndices = ordered.indices.filter { selected.contains(ordered[$0]) }
        guard let highest = selectedIndices.last else { return nil }

        if let below = ordered[(highest + 1)...].first(where: { !selected.contains($0) }) {
            return below
        }
        // Nothing below survives — walk back up from the *last* acted row, not
        // from the top of the selection. With a scattered selection those are
        // different rows, and searching from the top skips survivors that sit
        // between the selected ones.
        if let above = ordered[..<highest].last(where: { !selected.contains($0) }) {
            return above
        }
        return nil
    }

    /// What is left of a selection once the list under it changes.
    ///
    /// `collectionChanged` drops everything. A sender that appears in two
    /// collections is a different decision in each, and carrying the selection
    /// over is what left the inspector describing a row that wasn't on screen —
    /// and the status bar counting it. Within one collection the selection is
    /// kept, minus whatever has since left the list (unsubscribed, ignored,
    /// trashed, or filtered out by a search).
    public static func surviving(
        _ selected: Set<GroupID>, in visible: [GroupID], collectionChanged: Bool
    ) -> Set<GroupID> {
        guard !collectionChanged else { return [] }
        return selected.intersection(visible)
    }

    /// The row j/k should move to.
    ///
    /// Anchors on the edge of the selection you're moving away from — down from
    /// the bottom-most row, up from the top-most — so a multi-row selection
    /// collapses in the direction of travel instead of jumping somewhere
    /// arbitrary inside itself.
    public static func move(
        from selected: Set<GroupID>, by delta: Int, in ordered: [GroupID]
    ) -> GroupID? {
        guard !ordered.isEmpty else { return nil }
        let selectedIndices = ordered.indices.filter { selected.contains(ordered[$0]) }
        guard let lowest = selectedIndices.first, let highest = selectedIndices.last else {
            // Nothing selected: enter the list from whichever end you're heading.
            return delta > 0 ? ordered.first : ordered.last
        }
        let anchor = delta > 0 ? highest : lowest
        let target = max(0, min(ordered.count - 1, anchor + delta))
        return ordered[target]
    }
}
