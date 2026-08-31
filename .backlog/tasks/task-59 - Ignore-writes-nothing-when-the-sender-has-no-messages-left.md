---
id: TASK-59
title: Ignore writes nothing when the sender has no messages left
status: Done
assignee: []
created_date: '2026-08-31 23:09'
updated_date: '2026-08-31 23:26'
labels:
  - correctness
dependencies: []
modified_files:
  - Packages/NevermoreKit/Sources/NevermoreApp/Model/AppModel.swift
  - Packages/NevermoreKit/Tests/NevermoreTests/AppModelSuites.swift
  - Packages/NevermoreKit/Package.swift
  - CLAUDE.md
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
- [x] #1 Ignoring a sender writes the record whether or not that sender still has messages
- [x] #2 Trash and Ignore leaves the sender ignored, verified by a test that trashes every message first
- [x] #3 The toast reports what was actually ignored
- [x] #4 A Proposed row retired as ignored has a real ignore behind it
- [x] #5 A deliberate decision is recorded about whether the domain-ignore offer stays keyed on present groups
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
`AppModel.ignore(_:silently:)` now writes from the ids:

    let targets = ids.sorted { $0.storageKey < $1.storageKey }
    try? targets.forEach { try store.ignore($0) }

Sorted rather than left as a `Set` so the log line and the single-row offer below it are stable. The toast count and the undo closure move with it automatically, since both read `targets`.

**Decision on the domain-ignore offer gate: it moves to the ids too.** `DomainIgnoreOffer` reads `groups` to find the *siblings* it would widen to; the sender just ignored is not one of them and does not need a group. Gating on its group would have suppressed the offer exactly after a Trash and Ignore — the moment the user has most clearly said they want less from this company. The offer's own rule already returns nil when nothing is left on the domain, so nothing gets asked that has no answer.

`SelectionAction.ignore` deliberately keeps no `withMessages` guard. Once the write comes from `ids`, ignoring a sender with no mail on file is coherent: it keeps them out of the working list when they next mail, and it is what makes `retireFromProposal(ids, as: .ignore)` truthful.

Also changed `trashAndIgnore`'s undo closure from `targets.forEach { try store.unignore($0.id) }` to `try? store.unignore(id)` — same pattern, one line, and it worked only because `targets` was captured before the trash.

**Testability.** `AppModel` lives in the `NevermoreApp` target, which the test target did not depend on, so no reachable test could have caught this. The test target now depends on `NevermoreApp`, and `AppModel` gains a DEBUG-only `openForTesting(store:backend:)` — the only other routes to a store want a registered account plus a Keychain password, or rebuild the demo database at a fixed path in the user's container. Linking the app target drags in Sparkle.xcframework, which SwiftPM copies beside the products without an rpath that resolves from inside an `.xctest` bundle, so the test target carries `-rpath @loader_path/../../..`; without it the whole bundle fails to `dlopen` and every test "fails".

Six new tests in `Tests/NevermoreTests/AppModelSuites.swift`, suite "Ignoring a sender". Five of the six were confirmed to fail against the pre-fix line and pass after.

**Audited the rest of the codebase for the same pattern.** Every other `groups.filter { ids.contains($0.id) }` needs the group's messages and not merely its id — `trash` and `requestTrash` (uids, message counts), `plan(for:)` (the `List-Unsubscribe` header), `trashAndIgnore` (the message list for undo) — and the `MCPRoutes` / `MCPSnapshot` ones are read-only queries. `ignore` was the only write derived from groups where an id would do; `unignore` already took ids. `AgentActions.setIgnored` reaches `model.ignore` too and was equally affected in principle, but it resolves and rejects unknown senders against `groups` first, so it could not hit it.
<!-- SECTION:NOTES:END -->
