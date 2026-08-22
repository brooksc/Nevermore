---
id: TASK-28
title: >-
  Unsubscribe results sheet hides most of its content, and all of its actions,
  below a silent scroll
status: In Progress
assignee: []
created_date: '2026-08-09 18:58'
updated_date: '2026-08-22 03:39'
labels:
  - ui
  - unsubscribe
dependencies: []
priority: high
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
- [x] #2 Buckets requiring user action (FAILED, NOT ATTEMPTED) are reachable without discovering that the sheet scrolls
- [ ] #3 A run of ~10 senders shows materially more than two rows before clipping
- [ ] #4 The sheet still fits on a small display, with a maximum height rather than unbounded growth
- [x] #5 The headline count and the buckets below it cannot be read as contradicting each other when a run has failures
- [x] #6 Covered by a test or preview at 1, 10 and 50 senders, including an all-failed run
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Move the report's *decisions* out of the view into `NevermoreKit`: a new
   `UnsubscribeReport` over `[UnsubscribeEngine.Outcome?]` that owns which
   bucket an outcome falls in, the order the buckets render in (actionable
   first: FAILED, NOT ATTEMPTED, REQUESTED, CONFIRMED), the headline, and a
   contents line naming the full size of the report.
   → verify: harness suite at 1 / 10 / 50 senders and an all-failed run.
2. Headline stops contradicting the buckets: "Unsubscribed from 10 of 11
   senders" whenever some senders did not succeed; unchanged when all did.
   → verify: tests on the string.
3. Affordance in `resultsView`: taller scroll box (280 → 420), persistent
   scroll indicators, a bottom fade mask so the boundary never slices a line of
   text, and the contents line above the list so the reader knows the report is
   larger than what shows.
   → verify: builds; on-screen appearance is human-only, recorded as such.
4. Widen the results stage to 560pt (confirm/progress stay 460) so an outcome
   like "one-click accepted (HTTP 204), unverifiable" fits its row.
5. Update UI_SPEC 9.4 to specify ordering, the headline, and the affordance.
   → verify: read back.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Fixed on branch `task-28-fix` (worktree `.worktrees/task-28`).

**What changed**
- New `Sources/NevermoreKit/Unsubscribe/UnsubscribeReport.swift`: the bucket an outcome falls in, the render order (FAILED, NOT ATTEMPTED, REQUESTED, CONFIRMED — whatever needs the user first), the headline and a contents line. Out of the view so it can be tested without a screen.
- `Views/Sheets/UnsubscribeFlow.swift`: `resultsView` renders `report.buckets` in that order; headline is `report.headline`; a new contents line ("11 senders in this report · 1 still needs you, listed first") sits under the honesty caption; the list grew 280 → 420pt with `.scrollIndicators(.visible)` and a bottom fade mask; the results stage is 560pt wide, confirm and progress stay 460.
- `UI_SPEC.md` 9.4 rewritten to specify the order, the headline rule and the affordance.
- 12 new tests appended to the harness. 321 pass, 0 fail (309 on main + 12).

**Verification**
- AC#2, #3 (ordering half), #5, #6: covered by the `UnsubscribeReport` suite — `swift run nevermore-tests`.
- AC#1, AC#4, and the *pixel* half of AC#3: not verified. The fade, the forced indicators, the 420pt box and the 560pt width are layout, and the GUI was deliberately not launched (shared machine). A human needs to open the sheet on a ~10-sender run with one failure and confirm the boundary fades instead of slicing a line, and that the sheet still fits a small display.

**Concerns**
- `.mask` does not disable hit testing, so a button in the faded bottom band stays clickable while half-transparent. With FAILED first, the `Open in Browser` buttons are at the top, so this should not bite in practice.
- The width now changes between stages (460 → 560) when the sheet moves to results. Whether that resize looks deliberate or twitchy is a human call.
- `needsManual` shares the FAILED bucket but gets no `Open in Browser` button (unchanged behaviour — the reason is usually "no unsubscribe link", which a browser cannot fix). Left alone.

Correction to the tick list: AC#3 is unchecked. Raising the box 280 → 420pt and widening to 560 should show roughly half again as many rows, but "materially more than two rows" is a count of pixels on a screen I did not look at. AC#2 stays checked because it is now a property of the data, not the layout: FAILED and NOT ATTEMPTED are the first buckets rendered whenever they are non-empty, which the suite asserts at every size.
<!-- SECTION:NOTES:END -->
