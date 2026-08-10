---
id: TASK-28
title: >-
  Unsubscribe results sheet hides most of its content, and all of its actions,
  below a silent scroll
status: To Do
assignee: []
created_date: '2026-08-09 18:58'
labels:
  - ui
  - unsubscribe
priority: high
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Unsubscribing from 10 senders produces a sheet headed "Unsubscribed from 10 senders" that shows **two** of them. Nothing indicates there is more. The reporter nearly dismissed it, wondering why a run of 10 had listed 2.

`resultsView` (`Views/Sheets/UnsubscribeFlow.swift:212`) wraps the buckets in a `ScrollView` capped at `.frame(maxHeight: 280)`, inside a sheet fixed at `.frame(width: 460)`. macOS uses overlay scroll indicators, which stay hidden until you actually scroll — so a 10-row report in a 280pt box looks like a complete 2-row report. The second screenshot shows the failure mode plainly: the content is sliced mid-line, with a sentence cut horizontally through its glyphs and no fade, shadow or indicator at the boundary.

**The worse half is that the only actionable content is what gets hidden.** The buckets render in fixed order — CONFIRMED, REQUESTED, FAILED, NOT ATTEMPTED — and FAILED is where the "Open in Browser" buttons live. So the successful senders, which need nothing from the user, occupy the visible region, and the one sender that needs a decision ("Jodi Visconti — endpoint returned HTTP 404") sits below the fold. A summary sheet whose only call to action is off-screen is worse than one that shows nothing at all, because it reads as complete.

Worth fixing together:

1. **No affordance.** Either size the sheet to its content up to a sensible maximum, or make the clipped state visible — a fade at the boundary, persistent indicators, or an explicit "10 senders · scroll for the rest" line. Slicing a line of text in half is the current signal and it reads as a rendering bug.
2. **Ordering buries the actionable.** FAILED (and arguably NOT ATTEMPTED) should come first, or the sheet should open scrolled to the first bucket that needs the user. Nothing needing a decision should require scrolling to discover.
3. **Fixed 460pt width** wastes the sheet's other axis: "one-click accepted (HTTP 204), unverifiable" nearly fills the row, so a wider sheet would fit more per line and fewer rows would be clipped.

**Secondary observation, may be its own task.** The headline counts `confirmed + requested`, deliberately excluding failures (there's a comment at line 200 explaining why — a run where everything failed used to claim success). But the result is a sheet titled "Unsubscribed from 10 senders" that also contains "FAILED · 1", so the reader has to reconcile 10 against 11 outcomes. The count isn't wrong; it just isn't self-explanatory next to a failure. Something like "10 of 11 senders" would say both things at once.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 When the report is taller than the sheet, that is visible without interacting — no line is ever sliced mid-glyph at the boundary
- [ ] #2 Buckets requiring user action (FAILED, NOT ATTEMPTED) are reachable without discovering that the sheet scrolls
- [ ] #3 A run of ~10 senders shows materially more than two rows before clipping
- [ ] #4 The sheet still fits on a small display, with a maximum height rather than unbounded growth
- [ ] #5 The headline count and the buckets below it cannot be read as contradicting each other when a run has failures
- [ ] #6 Covered by a test or preview at 1, 10 and 50 senders, including an all-failed run
<!-- AC:END -->
