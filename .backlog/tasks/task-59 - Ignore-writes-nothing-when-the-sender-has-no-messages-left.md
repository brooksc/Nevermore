---
id: TASK-59
title: Ignore writes nothing when the sender has no messages left
status: To Do
assignee: []
created_date: '2026-08-31 23:09'
updated_date: '2026-08-31 23:09'
labels:
  - correctness
dependencies: []
priority: high
type: bug
ordinal: 25000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by audit, verified independently by reading the chain.

`AppModel.ignore(_:silently:)` derives what to write from the current groups:

    let targets = groups.filter { ids.contains($0.id) }
    try? targets.forEach { try store.ignore($0.id) }

`store.ignore` takes the `GroupID` directly, so that round-trip through `groups` is the only reason it can fail — and `unignore` does not do it.

**Trash and Ignore therefore trashes and does not ignore.** `trashAndIgnore` calls `trash` first, which deletes the rows and then `reloadFromStore()`, rebuilding `groups`. The sender's last message is gone, so it has no group, so `targets` is empty and nothing reaches `ignoredSender`. The toast still says "Trashed N messages and ignored the sender".

It fails precisely when it appears to have worked: a failed or partial trash leaves the group in place and the ignore lands.

Three reachable paths, all of them the ones where the feature is the point:
- the Reappeared row's **Trash and Ignore** button
- `WebUnsubscribeSheet`'s result-step accept for `escalated` and `couldNotUnsubscribe` — the flow a user is in after a browser unsubscribe fails
- the same offer as a toast action

The consequence is the exact outcome `BacklogOffer` documents itself as preventing: "trashing alone would leave the sender in the working list to be met again next sync". Its copy promises "Trashing them also ignores the sender, so they stay out of your lists."

**Second manifestation, same root cause.** Ignoring a Proposed row whose sender has lost its mail writes nothing, toasts "Ignored 0 senders", and still retires the row recording `proposalActions[key] = .ignore` — so an agent is told the sender was ignored when no ignore exists.

The fix is to write from `ids` rather than from present groups. Two other reads of `targets` in that function must move with it or they will keep reporting zero: the toast count, and the domain-ignore offer gate. Whether that gate stays keyed on present groups is a deliberate choice to make, not a side effect to inherit.

Note rather than file: `SelectionAction.ignore` has no `withMessages` guard, which is correct once the write comes from `ids` — ignoring a sender with no mail on file is a coherent local decision that keeps them out of the working list when they next mail.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Ignoring a sender writes the record whether or not that sender still has messages
- [ ] #2 Trash and Ignore leaves the sender ignored, verified by a test that trashes every message first
- [ ] #3 The toast reports what was actually ignored
- [ ] #4 A Proposed row retired as ignored has a real ignore behind it
- [ ] #5 A deliberate decision is recorded about whether the domain-ignore offer stays keyed on present groups
<!-- AC:END -->
