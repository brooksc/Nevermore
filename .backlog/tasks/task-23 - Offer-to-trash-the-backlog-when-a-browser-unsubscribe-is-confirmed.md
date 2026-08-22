---
id: TASK-23
title: Offer to trash the backlog when a browser unsubscribe is confirmed
status: In Progress
assignee: []
created_date: '2026-08-10 01:46'
updated_date: '2026-08-22 22:23'
labels:
  - product
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finishing an unsubscribe in the browser can leave every message behind with only a 12-second toast as the way to clear them — and the better the app works, the more likely you miss it.

There are three exits from the browser sheet and they do not agree:

1. Close the sheet (WebUnsubscribeSheet.swift:41-56) — a dialog with "Yes, and Delete Their Messages". Explicit, hard to miss.
2. The auto-detected confirmation banner (:118-140) — "Mark Confirmed" calls recordManual(confirmed: true) and dismisses immediately. No delete option in the interaction at all.
3. Automated (non-browser) unsubscribes — a result sheet with "Delete Messages from N Unsubscribed Senders".

Path 2 is the happy path: the page looked like a confirmation, so the app offered the banner, and the user took it. The delete offer then degrades to showToast(actionLabel: "Delete N Messages") (AppModel.swift:1315-1321), which sits in the status bar while attention is on the sheet closing. The code already made this judgement once — the outcome question used to be a toast and was moved into a dialog because it "was too weak" and "sat at the bottom of the window for twelve seconds" (:62-66). The delete offer deserves the same treatment.

It is worse when escalating from Reappeared, which is where this was hit. recordManual updates attemptedAt, which clears the reappeared state (:1307-1309), so the sender leaves the Reappeared collection the moment it is recorded — taking its "Trash and Ignore" button with it. The user is left with a backlog of mail from a sender that already ignored them once, and a toast that is about to expire.

Suggested shape:

- Banner gains the delete option: "Mark Confirmed" plus "Confirmed, and Delete N Messages", matching the close dialog. Smallest fix, closes the gap.
- Better: after confirmation, do not dismiss straight away — show a short in-sheet result step naming the count, with Delete and Keep. The user is already looking there.
- For escalations (target.isEscalation), word it as "Trash and Ignore" to match the Reappeared row, since a sender that came back is the one you most want gone.
- Keep the toast as a fallback, never as the only route.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every browser-sheet exit that records a confirmed unsubscribe offers deletion within that same interaction
- [ ] #2 The auto-detected confirmation banner offers delete, not just Mark Confirmed
- [x] #3 The offer names the message count
- [x] #4 Escalations from Reappeared offer trash and ignore, matching that view's wording
- [ ] #5 Nothing is deleted without being asked; the toast remains only as a fallback
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch `task-23-fix`, commit a0b40cc. 375 tests pass (367 before, 8 added).

Most of the shape had already landed with TASK-47 (f3d4df2): the sheet's result step, the banner routing into it, and the escalation wording. What was missing was that none of it was testable, and one exit walked past the question.

What this commit adds:
- `NevermoreKit/Domain/BacklogOffer.swift` — the offer as a value: count, escalation, question, accept/decline labels, `accept` (.trash vs .trashAndIgnore), and the toast fallback strings. `init?` returns nil when there is no mail left, so "nothing to offer" is one decision rather than a scattered `> 0`.
- The sheet reads all copy off it; `WebUnsubscribeSheet.backlogQuestion`/`deleteLabel` are gone.
- `AppModel.offerBacklogDelete(_:isEscalation:)`, the toast fallback, and `recordManual`'s toast now share that wording.
- Closing the sheet while the offer is on screen now falls back to the toast. Answering "Keep Messages" does not — declining is answered, and re-offering would be the nag.

On the trash threshold: the accepted offer trashes directly rather than going through `requestTrash`. `pendingTrash`'s dialog is attached to `MainWindowView`, which also presents this sheet, so during a queue sitting (sheet stays open) the alert would never appear and the trash would silently not happen. The offer itself is the confirmation instead, which is only defensible while it says what that dialog says — `BacklogOffer.namesWhatItWillDo` is that invariant and every offer in the tests is held to it (count + destination).

AC verification:
- #1 not ticked — three confirmed exits (banner, footer, close dialog) all funnel through `confirm()` into the result step, verified by reading `WebUnsubscribeSheet.swift`, not by running the UI.
- #2 not ticked — same reason; the banner's "Mark Confirmed" calls `confirm()`, which shows the result step rather than dismissing. On-screen, unverified.
- #3 ticked — tested (`BacklogOffer` suite, "the offer names the message count", "every offer states the count and where the mail goes").
- #4 ticked — tested: escalation yields "Trash and Ignore" and `.trashAndIgnore`; the string matches `CollectionViews.swift:150` (Reappeared row), checked by grep.
- #5 not ticked — nothing in the kit deletes, and the sheet only trashes from a button press, but proving "nothing is deleted without being asked" needs the app running. The toast fallback exists and is now reachable from exactly one exit.

Noted, not changed: `AppModel.recordManualAndDelete` (:1965) has no callers — it was the old close-dialog's "Yes, and Delete Their Messages". Left in place rather than deleted as unrelated cleanup.
<!-- SECTION:NOTES:END -->
