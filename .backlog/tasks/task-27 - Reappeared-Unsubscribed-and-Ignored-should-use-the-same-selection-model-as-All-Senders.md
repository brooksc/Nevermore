---
id: TASK-27
title: >-
  Reappeared, Unsubscribed and Ignored should use the same selection model as
  All Senders
status: To Do
assignee: []
created_date: '2026-08-09 18:45'
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
- [ ] #1 Rows in Reappeared, Unsubscribed and Ignored can be selected, with the same click, keyboard and multi-select behaviour as All Senders
- [ ] #2 Switching collections never leaves the inspector describing a sender absent from the visible list
- [ ] #3 The status bar's "N selected" count always refers to rows in the current collection
- [ ] #4 Existing per-row actions still work and still act on their own row, not on the selection
- [ ] #5 Toolbar and menu actions that operate on the selection either work in these collections or are disabled with a reason, rather than silently acting on a stale sender
- [ ] #6 A decision is recorded on whether selection persists across collection switches, and the chosen behaviour is covered by a test
<!-- AC:END -->
