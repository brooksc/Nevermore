---
id: TASK-58
title: Opening the browser from a results sheet loses every other failure
status: To Do
assignee: []
created_date: '2026-08-31 19:43'
updated_date: '2026-08-31 19:44'
labels:
  - ui
dependencies: []
priority: high
type: bug
ordinal: 24000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reported from use, immediately after TASK-28 and TASK-57 made the results sheet readable and the browser answer honest. Unsubscribing from 11 senders left 2 failures. The user pressed **Open in Browser** on the first, handled it, and the results sheet was gone — taking the second failure with it, with no way back to it.

The cause is one line in `UnsubscribeFlow.resultsView`:

    Button("Open in Browser") {
        dismiss()
        onManualFallback(t.id)
    }

`dismiss()` destroys the report, and `onManualFallback` hands over exactly one sender. Everything else in that run is lost — not archived, not queued, just no longer on screen. The user is left knowing a second sender failed and having no route to it except finding it by name in a list of hundreds.

**The machinery to do this properly already exists and is not being used.** TASK-47 built `BrowserQueue` for precisely this — working through the senders that need a person in a browser, one sitting, in order. It has `next`, `pending`, `worked` and `position(of:)`, it persists across a relaunch, and `AppModel` already loads and saves it. The results sheet simply never fills it.

So the fix is to route the sheet's browser hand-off through the queue rather than around it: every sender in the run that needs a browser goes in, the browser opens on the first, and finishing one advances to the next until the run is done. Position is worth showing — "1 of 2" — because a person who has just watched eleven unsubscribes wants to know how much is left, and because a queue that silently ends is how this bug felt in the first place.

Two things to get right rather than assume:

- **`failed` is not the only bucket that needs a browser.** `needsManual` means nothing was sent and a person has to finish it; those senders belong in the same queue. Check what the sheet currently offers for that bucket.
- **Leaving part-way must keep the rest.** TASK-47 already requires this of the queue; the point here is that the sheet must not be the thing that drops them.</description>
<parameter name="acceptanceCriteriaSet">["Every sender in a run that needs a browser is reachable after the first one is handled", "Finishing one advances to the next, and the position in the run is visible", "Abandoning the browser part-way leaves the remaining senders reachable rather than discarding them", "needsManual senders are queued on the same footing as failed ones, or the reason they are not is recorded", "The queue used is BrowserQueue, not a second list built for this sheet"]
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every sender in a run that needs a browser is reachable after the first one is handled
- [ ] #2 Finishing one advances to the next, and the position in the run is visible
- [ ] #3 Abandoning the browser part-way leaves the remaining senders reachable rather than discarding them
- [ ] #4 needsManual senders are queued on the same footing as failed ones, or the reason they are not is recorded
- [ ] #5 The queue used is BrowserQueue, not a second list built for this sheet
<!-- AC:END -->
