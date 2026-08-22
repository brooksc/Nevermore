---
id: TASK-52
title: >-
  A proposal row should carry the action the agent means, not just prose about
  it
status: To Do
assignee: []
created_date: '2026-08-22 02:32'
updated_date: '2026-08-22 02:33'
labels:
  - mcp
  - ui
dependencies:
  - TASK-45
priority: high
type: feature
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in use, the first time an agent recommended something other than unsubscribe.

Two senders were proposed as cold outreach, with reasons beginning "IGNORE, do not unsubscribe" and explaining that an unsubscribe request confirms to a cold sender that the address is live and read. Both were unsubscribed anyway. The user read the reason afterwards and said the preview text was hard to read and unclear.

The cause is structural, not a wording problem. A proposal row carries prose, but its affordances are fixed: Unsubscribe is the primary button in the inspector and `u` is the key already in the fingers. An agent's recommendation that contradicts the default has nowhere to live except a caption that is truncated, set small, and competing with a button that says otherwise. Prose cannot override a button, and rewriting the sentence will not change that.

What is missing is a per-sender recommended action on the proposal itself — unsubscribe, ignore, or trash — so the recommendation is data the UI can act on rather than text the user has to read and obey. The row can then lead with the recommended action, and acting against it can be made deliberate rather than accidental.

This is closely related to TASK-30, which wants a warning when unsubscribing would confirm an address to a spammer. That warning and this recommendation are the same moment in the interface, and building them separately would produce two things competing for the same row. Whoever takes this should read TASK-30 first and decide whether they merge.

Second, smaller finding from the same session: the reason is the only thing that makes an agent's judgement checkable, and at present it is a truncated caption. It should be legible at a glance without selecting the row.

Recorded user preference driving this: cold outreach and one-off senders should be trashed and ignored, never unsubscribed. The exposure is only worth it for a genuine recurring subscription.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 propose_selection accepts a recommended action per sender, and the tool description explains when each is appropriate
- [ ] #2 The row leads with the recommended action rather than defaulting to unsubscribe regardless
- [ ] #3 Acting against a recommendation is possible but deliberate, not something a single habitual keystroke does silently
- [ ] #4 The agent's reason is legible in the row without selecting it
- [ ] #5 get_proposal_status reports whether the human followed the recommendation or overrode it
- [ ] #6 A decision is recorded on whether this merges with TASK-30's spammer warning
<!-- AC:END -->
