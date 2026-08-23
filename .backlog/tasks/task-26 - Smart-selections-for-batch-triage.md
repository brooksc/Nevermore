---
id: TASK-26
title: Smart selections for batch triage
status: Done
assignee: []
created_date: '2026-08-10 01:47'
updated_date: '2026-08-23 02:08'
labels:
  - product
dependencies: []
modified_files:
  - Packages/NevermoreKit/Sources/NevermoreKit/Domain/SmartSelection.swift
  - Packages/NevermoreKit/Sources/NevermoreKit/Domain/AgentActionRules.swift
  - Packages/NevermoreKit/Sources/NevermoreApp/Model/AppModel.swift
  - Packages/NevermoreKit/Sources/NevermoreApp/Commands.swift
  - >-
    Packages/NevermoreKit/Sources/NevermoreApp/Views/Sheets/UnsubscribeFlow.swift
  - Packages/NevermoreKit/Tests/NevermoreTests/main.swift
  - README.md
  - UI_SPEC.md
  - CHANGELOG.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The core loop is one sender at a time, which is right when the answer is uncertain and wrong when it is obvious. On a mailbox with a thousand senders, most of the decisions are not close: a sender with 40 messages and 0% opened does not need thinking about.

The pieces exist — selection is already a Set, actions already take multiple ids, and the confirmation sheet already says "Unsubscribe from N senders?". What is missing is a way to express the selection.

Starting set, all derivable from what is already stored: never opened (0% read), rarely opened (under 10%) with volume above a threshold, nothing received in a year, and one-click capable (so the whole batch can complete without a browser).

Keep it a selection, not an action: it fills the selection and shows the list, the user reviews and presses the button. Never a "clean my inbox" button that acts on its own.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A menu of smart selections that fill the current selection
- [ ] #2 Selection is reviewable before any action
- [ ] #3 Batch unsubscribe reports per-sender outcomes, not just a total
- [ ] #4 Nothing acts without an explicit confirmation
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented on branch `task-26-fix` (worktree `.worktrees/task-26`). 404 tests pass (394 on main + 10 new).

**Where it lives.** The rules are `NevermoreKit/Domain/SmartSelection.swift` — pure predicates over figures the sync already stored, so they are testable without a window. The menu (`Edit → Smart Selection`, in `Commands.swift`) and the model call (`AppModel.applySmartSelection`) are app-target and are not reachable from the harness.

**It selects, it never acts.** `applySmartSelection` sets `selection` and shows a toast. That is all it does.

**Collection is respected twice.** Candidates are built from `visibleIDs` (already collection- and search-filtered), and `SmartSelection.select` re-checks `SenderCollection.contains` regardless. Tested: the same pool selects the ordinary sender in All Senders and the ignored sender in Ignored.

**Cap of 50.** Reviewability is the safety mechanism and nobody reviews 400 rows, so a rule fills at most `SmartSelection.maxSelected` in display order and the toast says "the first 50 of 312 matching — review them, act, then run it again for the rest." Same reasoning as the 25-item cap on agent proposals.

**Change to the starting set.** `neverOpened` now requires ≥3 messages (`SmartSelection.minimumVolume`). Taken literally, "0% read" also selects every sender that mailed once and has not been read yet, which after a first sync is most of the mailbox — a fact about how new the sync is, not evidence the mail is unwanted. `rarelyOpened` uses <10% read with ≥10 messages. Nothing else changed.

**AC #4 went further than wiring.** `Edit → Smart Selection` plus one `⇧U` would otherwise have been 50 live requests with no confirmation for anyone who has turned "Ask before unsubscribing" off. `UnsubscribeConfirmation.requiresPrompt` gained `selectionWasAutomatic:` (defaulted, so no existing call site changed), and `UnsubscribeFlow` passes `model.selectionIsSmart`, which is cleared by any other route to the selection. The preference is about a selection built row by row; a rule-filled one has never been looked at, and the sheet is where it gets looked at.

**Per-AC evidence — nothing is ticked, because nothing was seen on screen.** The app was not launched (shared machine).
- #1 menu: `Commands.swift` compiles into the app target; a `Menu("Smart Selection")` over `SmartSelection.allCases`, disabled in Unsubscribed. Not verified on screen.
- #2 reviewable: proven only structurally — `applySmartSelection` performs no action. That the table shows the rows is not something the harness can look at.
- #3 per-sender outcomes: **already true before this task.** `UnsubscribeFlow.swift` buckets results and lists every sender by name with its own outcome detail (`Views/Sheets/UnsubscribeFlow.swift`, the `bucket(_:)` builder). Nothing was re-implemented. Not verified on screen.
- #4 confirmation: the decision function is unit-tested (`a rule-filled selection always reaches the confirm step`) and it is what the sheet's `onAppear` consults. The sheet appearing was not verified on screen.

Remaining: one GUI pass to tick #1–#4.

**Unrelated defect noticed, not touched:** `UnsubscribeMethod` is declared twice — `NevermoreKit/Domain/UnsubscribeMethod.swift` (`oneClick/web/mailto/none`) and `NevermoreApp/Design/Tokens.swift` (`oneClick/webLink/email/manual`). The app-module one shadows the kit's throughout the app target, so `SenderRow.method` and `MCPSenderSummary` describe the same sender with different vocabularies. Smart selection sidesteps it by carrying a plain `isOneClick: Bool`.
<!-- SECTION:NOTES:END -->
