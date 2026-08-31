---
id: TASK-57
title: Saying you did not unsubscribe files the sender as unsubscribed
status: To Do
assignee: []
created_date: '2026-08-31 18:28'
updated_date: '2026-08-31 18:29'
labels:
  - ui
  - correctness
dependencies: []
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
- [ ] #1 Answering that you did not unsubscribe leaves the sender in the working list, where it can still be ignored or trashed
- [ ] #2 No record claims requested for an attempt the user said did not happen
- [ ] #3 A sender that was attempted and not finished is distinguishable from one never tried
- [ ] #4 The automated path's behaviour is unchanged: a failed or needs-manual result still records nothing
- [ ] #5 Existing history is not rewritten, and the task notes say why it cannot be repaired retroactively
<!-- AC:END -->
