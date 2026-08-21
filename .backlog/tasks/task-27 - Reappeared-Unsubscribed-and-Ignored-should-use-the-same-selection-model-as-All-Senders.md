---
id: TASK-27
title: >-
  Reappeared, Unsubscribed and Ignored should use the same selection model as
  All Senders
status: Done
assignee: []
created_date: '2026-08-09 18:45'
updated_date: '2026-08-20 00:00'
labels:
  - ui
  - consistency
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
All Senders and the other collections behave like two different apps.

**All Senders** is a `Table(rows, selection: $model.selection, …)` (`SenderTableView.swift:17`). You click a row, it highlights, and the inspector shows that sender.

**Reappeared, Unsubscribed and Ignored** are a plain `List { ForEach(…) }` with **no selection binding** — `ReappearedCollectionView` and `IgnoredCollectionView` in `Collections/CollectionViews.swift`, and `HistoryView` for Unsubscribed. Rows can't be selected at all; every action is a per-row button.

The visible symptom is worse than the inconsistency. `model.selection` is never cleared when the collection changes, and the inspector is driven by it (`MainWindowView.swift:64` opens the inspector whenever selection is non-empty). So switching to Reappeared leaves the inspector rendering **whatever sender you last clicked in All Senders** — a sender that isn't in the list you're looking at. The attached screenshot shows Reappeared listing Social Security Administration and Walmart Canada while the right pane describes "Joe at PostHog", and the status bar reads "1 selected · 1 messages" for a row that isn't on screen.

Two things are wrong and they need separating:

1. **Stale inspector.** The detail pane describes a sender the current list doesn't contain. That's a correctness bug, and it's worth fixing even if the selection model stays as-is: an inspector should never describe something you can't see.
2. **Inconsistent interaction.** Three of the four collections can't be selected, so keyboard navigation, multi-select and the shared inspector don't work in them, and the toolbar actions that operate on `model.selection` have nothing to act on.

Making the three collections use the same selectable model as All Senders fixes both, and removes a second interaction pattern from the app. Their per-row buttons (Unsubscribe in Browser / Trash and Ignore / Forget Record / Unignore) should stay — they're good affordances — but they should sit alongside selection rather than instead of it, exactly as All Senders does.

Worth deciding while implementing: whether selection carries *across* collections when the same sender appears in two of them, or resets on every collection change. Resetting is the simpler, less surprising default and is what fixes the stale-inspector symptom outright.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Rows in Reappeared, Unsubscribed and Ignored can be selected, with the same click, keyboard and multi-select behaviour as All Senders
- [x] #2 Switching collections never leaves the inspector describing a sender absent from the visible list
- [x] #3 The status bar's "N selected" count always refers to rows in the current collection
- [x] #4 Existing per-row actions still work and still act on their own row, not on the selection
- [x] #5 Toolbar and menu actions that operate on the selection either work in these collections or are disabled with a reason, rather than silently acting on a stale sender
- [x] #6 A decision is recorded on whether selection persists across collection switches, and the chosen behaviour is covered by a test
- [x] #7 Reappeared offers a way to open the latest message before deciding, using viewLatestMessage() so Gmail opens the conversation and other providers fall back to search
- [x] #8 The v shortcut and Actions > View Latest Message work in every collection that has a selection, not just All Senders
- [x] #9 Demo mode keeps its explanatory toast rather than opening a browser
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Plan (2026-08-20, before coding)

The four collections differ because each one re-invents "what is on screen" and
"what can act on it". So move both into `NevermoreKit`, where they can be tested
without a UI, and have every collection read from them.

1. `Domain/Collections.swift` (new, NevermoreKit): move the `Collection` enum out
   of `Design/Tokens.swift` and give it the membership rule as a pure function of
   a new `SenderState` (ignored / unsubscribed / reappeared / still has mail).
   Add `SelectionAction` + `SelectionContext` and one availability rule per
   action, returning *why* it's unavailable rather than a bare Bool — AC #5 wants
   a reason, and a disabled control with no tooltip reads as broken.
   `Tokens.swift` keeps `title` / `systemImage` / `Section` as an extension:
   presentation stays in the app.
2. `Domain/SelectionCursor.swift`: add `surviving(_:in:collectionChanged:)` — the
   one place that decides what a selection survives.
3. `AppModel`: one `visibleIDs` (records for Unsubscribed, sorted rows
   elsewhere); `collection` didSet resets the selection through `surviving`;
   every reload prunes through it; `moveSelection` / `advance` / status counts
   read it. `can(_:)` / `reason(_:)` expose the availability rules.
   `viewLatestMessage(_:)` gains a per-row overload for AC #7.
4. Views: a single `.selectionKeyboard(…)` modifier carries j/k/u/⇧U/v/i/d/?, and
   all four lists apply it. Reappeared / Ignored / Unsubscribed become
   `List(selection: $model.selection)` with the same focus binding the table has.
   Per-row buttons stay and keep acting on their own row.
   Toolbar and Actions menu disable with `reason(_:)` as the tooltip.
   The inspector gains a record-only branch for an unsubscribed sender whose
   mail is gone, so a selected row is never described as "no sender selected".

**Decision for AC #6:** selection does *not* persist across a collection switch.
A sender means a different thing in each list, and carrying it over is exactly
what left the inspector describing an off-screen row. Covered by tests on
`SelectionCursor.surviving`.

## Outcome (2026-08-20)

Built as planned. `swift build` clean; `swift run nevermore-tests` reports
**175 passed, 0 failed** (157 before, 18 added across three new suites:
Collection membership, Selection across collections, Selection action
availability).

What is verified by test, and what isn't:

- Verified in the harness: membership per collection, the reset-on-switch rule
  (AC #6), pruning to the visible list, and every action's availability and
  refusal wording per collection — including the Unsubscribed row whose messages
  are gone.
- **Not verified**: everything that needs the running app. Nobody clicked a row
  in Reappeared, ⇧-clicked a range, watched the inspector during a collection
  switch, or read a disabled control's tooltip. The GUI was deliberately not
  launched (shared machine). ACs #1–#5, #7 and #9 are implemented and reasoned
  through, but their on-screen behaviour is unconfirmed.

Two things found and left alone, both pre-existing:

- A sender that is both ignored and unsubscribed is listed in *both* archives —
  `Collection.unsubscribed` never excluded ignored senders. Pinned by a test that
  names it as inherited, not endorsed. Worth its own task.
- `Collection` now lives in NevermoreKit and shadows `Swift.Collection` inside
  that module. It bites as a compile error in any app file that forgets
  `import NevermoreKit` (SidebarView did). Loud, not silent, but a rename to
  `SenderCollection` would remove the trap.

For TASK-45: a fifth collection needs a case in `Collection`, a line in
`contains(_:)`, its rules in `SelectionAction.unavailability(in:)`, presentation
in `Tokens.swift`, and a list that applies `.selectionKeyboard(…)`. The one part
that does not generalise is `visibleIDs`: it special-cases Unsubscribed because
that collection lists records rather than groups. A Proposed collection backed by
agent proposals rather than `groups` will need the same special case, and at that
point the branch should become a per-collection row source instead of an `if`.

Merged TASK-22 into this on 2026-08-09. TASK-22 reported the symptom from the Reappeared side: deciding whether to escalate or trash is the hardest call in the app, and it is the one view with nothing to decide with. The cause is the same missing selection model — viewLatestMessage() reads selection.first (AppModel.swift:440), so both the v shortcut and the Actions menu item silently no-op there. Fixing selection fixes the shortcut; the View affordance on the row is the remaining piece.
<!-- SECTION:NOTES:END -->
