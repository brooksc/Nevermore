---
id: TASK-32
title: Report on whether unsubscribes actually worked
status: Done
assignee: []
created_date: '2026-08-10 01:49'
updated_date: '2026-08-23 02:56'
labels:
  - product
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reappeared reports continuously; it never concludes. A periodic summary would: "You unsubscribed from 8 senders last month. 6 honoured it, 2 did not." That is the app's unique claim stated as a result, and a reason to come back to an app you might otherwise open once and forget.

The data is already there — unsubscribe history with timestamps, and messages received since. It needs a report and a moment to show it, not new plumbing.

Pairs well with the reappearance notification that already exists, which fires per sender and so cannot say anything about the whole.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A summary of unsubscribes and their outcomes over a period
- [ ] #2 Reachable on demand, not only as a notification
- [x] #3 Counts derived from the same rule the Reappeared collection uses, not a second implementation
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented on branch `task-32-fix` (worktree `.worktrees/task-32`), commit 8cb6aaa. Not merged.

**What it is.** `UnsubscribePeriodReport` (NevermoreKit/Domain) is a pure function over stored `UnsubscribeRecord`s plus the mail currently on file, taking `now` from the caller. `AppModel.unsubscribePeriodReport(now:)` supplies a 30-day window from the whole history table (not `unsubscribedRecords`, which hides reappeared senders and applies the search filter). Rendered as a card above the Unsubscribed log.

**The claim it makes, and why it is defensible.** It never says a sender honoured anything. Per record it reports one of: mailed again (with a count — the only conclusive observation); sent nothing since; too recent to say; request failed; no mail on file. `staysWithinTheEvidence` asserts the copy contains none of honoured/respected/complied/worked/succeeded, so the wording cannot drift into a compliance claim without failing a test. A standing caveat sits under the counts saying a silent sender may simply have had nothing to send.

**"Too early to say" — decided yes, it is needed.** Silence is only reported once elapsed time exceeds twice the sender's own median gap between messages, measured only from mail received *before* the attempt, floored at 14 days and capped at 90. Twice, not once, so a newsletter slipping a week does not flip the report week to week; floor so a daily sender's two quiet days is not a conclusion; cap so a quarterly mailer eventually concludes instead of sitting at "too early" forever. A sender with fewer than two prior messages has no measurable rhythm and falls back to the floor.

**Two further honesty cases.** A record whose sender has no mail on file (never synced, or the user trashed it) is reported as "nothing to judge by", not as quiet — the Reappeared collection treats that as not-reappeared, which is right for a queue and would be a lie in a count. A `.failed` outcome with no mail since is reported as unfinished work, since nothing was ever asked; mail arriving after a failed attempt still counts as mailed again, because that fact is certain either way.

**AC#3.** The "mailed again" rule had three copies in `AppModel` (`isReappeared`, `isReappearedRecord`, `messagesSinceUnsubscribe`). All three now call `Reappearance` in NevermoreKit, which is also what the report uses, so the sidebar collection and the report state the same rule rather than two that agree today.

**Name collision.** `UnsubscribeReport` already exists (the per-run results sheet), hence `UnsubscribePeriodReport`.

**AC#2 left unchecked deliberately.** The card is placed unconditionally in `HistoryView` above the log, reachable from the sidebar with no notification involved, and the placement is above the filtered rows so search and the reappeared-hiding filter cannot make it vanish. But it is an on-screen claim and the GUI was not launched (shared machine), so it is not verified.

**Verification.** `swift build` clean; `swift run nevermore-tests` → 432 passed, 0 failed (413 before this work; 19 added: 3 for the shared rule, 16 for the report). No GUI, no real mailbox, no visual check of the card's layout.

**Design concerns.** (1) The 30-day window and the 2x/14d/90d constants are judgement calls, not measured — they are named constants in one place. (2) A user who never syncs recently-unsubscribed senders' mail will see many "nothing to judge by" entries, which is honest but may read as the report knowing nothing; worth watching against real data. (3) The report recomputes on every body evaluation of the Unsubscribed view — cheap at realistic history sizes, but it is O(records x messages).
<!-- SECTION:NOTES:END -->
