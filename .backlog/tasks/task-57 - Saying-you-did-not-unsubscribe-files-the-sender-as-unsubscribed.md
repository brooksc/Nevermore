---
id: TASK-57
title: Saying you did not unsubscribe files the sender as unsubscribed
status: Done
assignee: []
created_date: '2026-08-31 18:28'
updated_date: '2026-08-31 18:41'
labels:
  - ui
  - correctness
dependencies: []
modified_files:
  - Packages/NevermoreKit/Sources/NevermoreKit/Store/MessageStore.swift
  - Packages/NevermoreKit/Sources/NevermoreKit/Domain/SenderCollection.swift
  - Packages/NevermoreKit/Sources/NevermoreKit/Domain/BacklogOffer.swift
  - Packages/NevermoreKit/Sources/NevermoreKit/Server/MCPSnapshot.swift
  - Packages/NevermoreKit/Sources/NevermoreApp/Model/AppModel.swift
  - >-
    Packages/NevermoreKit/Sources/NevermoreApp/Views/Sheets/WebUnsubscribeSheet.swift
  - Packages/NevermoreKit/Sources/NevermoreApp/Views/SenderTableView.swift
  - Packages/NevermoreKit/Tests/NevermoreTests/Suites.swift
  - UI_SPEC.md
priority: high
type: bug
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reported from use. The user opened a sender's unsubscribe page in the built-in browser, found it demanded a login, answered honestly that they had **not** unsubscribed — and the sender vanished. They then wanted to block it instead and could not find it anywhere.

Two defects that compound.

**The record is untrue.** `AppModel.recordManual(_:confirmed:)` takes a Bool, so it can only say `confirmed` or `requested`:

    outcome: confirmed ? .confirmed : .requested

Answering "I did not unsubscribe" therefore writes `requested`, which in this app means *the request was sent and accepted, but nothing confirms it worked*. That is the opposite of what happened. The four-outcome vocabulary exists precisely so the app never overstates, and this path collapses it to a Bool and rounds up.

**Any record hides the sender, whatever it says.** `isUnsubscribed: history[g.id.storageKey] != nil` — no outcome check. So the moment that record exists the sender leaves All Senders (`!isIgnored && !isUnsubscribed`) and lands in the Unsubscribed archive, where the user will never look, because they did not unsubscribe.

**The automated path already gets this right**, which is what makes it clearly a bug rather than a design choice: `if outcome.isSuccess` guards the write, so a failed or needs-manual result records nothing and the sender stays in the working list. Only the manual path records unconditionally.

Measured on the maintainer's mailbox: 138 `requested`, 11 `confirmed`, and **zero `failed` records ever written**. An unknown number of those 138 are attempts the user explicitly said had not happened, and they cannot be told apart after the fact — nothing distinguishes a real request from a declined one.

Beyond restoring correctness, the interface has no way to say **attempted and unresolved**. Everything is either done or never started, so a half-finished attempt gets rounded into the archive. Worth fixing as part of this: a sender the user tried and could not finish should stay where they can act on it, carrying enough of a mark that they know they have already been there — and the moment they hit a login wall is exactly when *ignore* and *trash* are the useful next actions, which the browser sheet does not currently offer.</description>
<parameter name="acceptanceCriteriaSet">["Answering that you did not unsubscribe leaves the sender in the working list, where it can still be ignored or trashed", "No record claims requested for an attempt the user said did not happen", "A sender that was attempted and not finished is distinguishable from one never tried", "The automated path's behaviour is unchanged: a failed or needs-manual result still records nothing", "Existing history is not rewritten, and the task notes say why it cannot be repaired retroactively"]</parameter>
</invoke>
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Answering that you did not unsubscribe leaves the sender in the working list, where it can still be ignored or trashed
- [x] #2 No record claims requested for an attempt the user said did not happen
- [x] #3 A sender that was attempted and not finished is distinguishable from one never tried
- [x] #4 The automated path's behaviour is unchanged: a failed or needs-manual result still records nothing
- [x] #5 Existing history is not rewritten, and the task notes say why it cannot be repaired retroactively
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## What was done

Recorded the declined attempt honestly rather than recording nothing, and made "is this sender unsubscribed" read the outcome instead of the mere existence of a record.

**The shape chosen, and why not the other one.** Recording nothing on a declined attempt would have matched the automated path exactly and been simpler, but it loses something the app already depends on. `hasPriorAttempt` is `history[key] != nil`, and it drives `manualTarget`'s `isEscalation` and the browser queue's `ignoredAnUnsubscribe` reason — the sheet's own comment said as much ("the record is what stops the app offering the same automated path again"). Recording nothing would have regressed that, and it fails AC#3 outright: a sender never tried and a sender tried-and-blocked would be byte-identical. `MessageStore.Outcome.failed` already existed and `UnsubscribePeriodReport` already classified it as `.requestFailed` — the vocabulary was there and only the write site was rounding up.

**The predicate.** `MessageStore.Outcome.isUnsubscribed` (`!= .failed`) is the single place the question is now answered, named to match `BrowserQueue.Outcome.isUnsubscribed`, which asks the same thing about the same moment. `SenderState.isUnsubscribed` now means *a real unsubscribe is on record*, and both builders of it — `AppModel.state(of:)` and `MCPSnapshot.state(of:)` — were changed together.

`SenderCollection.contains` itself was **not** touched, and did not need to be: all four collections read `isUnsubscribed`, so narrowing that one fact moves a failed attempt correctly in every one of them at once.
- **All Senders** (`!isIgnored && !isUnsubscribed`) — now keeps the sender, which is the whole complaint.
- **Unsubscribed** — excludes it via the predicate, and `AppModel.unsubscribedRecords` (which feeds the log view and the sidebar count, and is read from history rather than from state) now filters on the outcome too.
- **Reappeared** (`isUnsubscribed && hasReappeared`) — excludes it, which is the correct reading: Reappeared means a sender ignored an unsubscribe, and a failed attempt never was one. Covered by a test that back-dates the attempt behind the mail and asserts the sender is still in All Senders.
- **Proposed** — an overlay, unaffected; but `selectionContext.alreadyUnsubscribed` also counted bare records, which would have blocked ⌘U in Proposed with "Already unsubscribed" for a sender that never was. Fixed alongside.

**The write site.** `recordManual(_:confirmed:)` became `recordManual(_:outcome:)`, taking the store's own vocabulary. The Bool was the defect: it had no way to spell the third answer, so "I did not unsubscribe" became `requested`. The automated path is untouched — its `if outcome.isSuccess` guard still records nothing for a failed or needs-manual result.

**Ignore/trash at the login wall.** `BacklogOffer` gained a `Context` (`unsubscribed` / `escalated` / `couldNotUnsubscribe`) in place of its `isEscalation` Bool; the old initialiser stays as a wrapper so existing callers and tests are unchanged. The new case accepts into `trashAndIgnore` — trashing alone would leave the sender in the working list to be met again next sync — and its copy opens "Nothing was unsubscribed", with the decline button reading "Leave in My List" rather than "Keep Messages". `WebUnsubscribeSheet` now shows its result step for a declined attempt too (orange, "Still subscribed to X"), carrying that offer, instead of closing silently.

**Distinguishability in the list.** `SenderRow.priorOutcome` already existed and was displayed nowhere. The Sender column now shows a small **Tried** capsule when it is `.failed`, with a tooltip saying the sender is still subscribed.

## Existing history is not repaired, and cannot be

Nothing was migrated. The store holds 138 `requested` records and no `failed` ones ever written, and a declined attempt was written with exactly the same row as a real one — same outcome, same URL, same timestamp shape. There is no field, no correlation with the browser queue's own outcomes (which only began being recorded later), and no mail-behaviour signal that separates them: a sender who genuinely was sent a request and a sender the user gave up on both look like `requested`, and both may or may not have kept mailing. Any migration would be assigning a fabricated outcome to real user history, which is a worse error than the one being fixed. The fix is forward-only; senders wrongly filed before this change are recovered the way they always could be, by forgetting the record from Unsubscribed.

## Verification

`swift build` clean, `swift test` **579 tests in 98 suites, all passing** (570 in 97 on main; 9 tests and 1 suite added, none removed or changed). New suite `Declined manual unsubscribe` covers the outcome predicate, the four collections through `MCPSnapshot`, the failed-attempt-is-not-a-reappearance rule, and the store round-trip proving tried-vs-never-tried is distinguishable; `BacklogOffer` gained two tests for the login-wall offer.

**Not verified:** anything on screen. The sheet, the result step and the Tried badge are in the app target and were not run — the GUI was not launched (shared machine). What was proved is that they compile and that every rule underneath them holds in `NevermoreKit`.

## Open concern

A sender carrying a `.failed` record sits in All Senders, where `SelectionAction.forget` is unavailable ("There's no unsubscribe record to forget") — so that record cannot be cleared from the UI. It is harmless and arguably right (the sender genuinely has been tried, and escalating straight to the browser next time is the useful behaviour), but it is a record with no user-facing off switch. Left alone deliberately rather than widening `forget`'s availability rule, which four collections read. Worth a follow-up if it bites.
<!-- SECTION:NOTES:END -->
