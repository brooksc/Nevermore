---
id: TASK-23
title: Offer to trash the backlog when a browser unsubscribe is confirmed
status: To Do
assignee: []
created_date: '2026-08-10 01:46'
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
- [ ] #3 The offer names the message count
- [ ] #4 Escalations from Reappeared offer trash and ignore, matching that view's wording
- [ ] #5 Nothing is deleted without being asked; the toast remains only as a fallback
<!-- AC:END -->
