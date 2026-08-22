---
id: TASK-52
title: >-
  A proposal row should carry the action the agent means, not just prose about
  it
status: In Progress
assignee:
  - task-52-recommendation
created_date: '2026-08-22 02:32'
updated_date: '2026-08-22 03:31'
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

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## Plan

1. **NevermoreKit — the recommendation becomes data.**
   `RecommendedAction` (`unsubscribe` / `ignore` / `trash`) on
   `SenderProposal.Item`. Custom `init(from:)` so a proposal stored before this
   change decodes as `.unsubscribe` — that is what those rows already meant —
   rather than failing to decode and vanishing.
   → verify: harness round-trips an item with each action, and decodes legacy
   JSON with no `recommendation` key.

2. **`propose_selection` requires it.** `MCPWriteRequest.ProposedItem`
   gains `recommendation`; the route refuses a sender without a valid one, in
   the same voice as the missing-reason refusal. Required rather than defaulted:
   defaulting to unsubscribe is precisely the bug — the agent said "ignore" and
   the app heard "unsubscribe".
   → verify: route tests for accepted values, missing value, bogus value.

3. **Catalog.** Schema `enum` + `required`, and the description says when each
   is appropriate, including the standing rule: cold outreach and one-off
   senders are trashed and ignored, never unsubscribed, because an unsubscribe
   confirms a live address and the exposure only pays for a recurring
   subscription.
   → verify: schema parses, enum present, description carries the rule.

4. **Override is a decision, not a keystroke.** Pure helper in Kit:
   `SenderProposal.items(contradicting:in:)` plus the warning copy. `AppModel`
   asks it before any unsubscribe started from Proposed (`u`, `⇧U`, the button,
   the menu) and puts a confirmation up naming the senders and the agent's
   reason. Only unsubscribe is guarded: it is irreversible and visible to a
   third party, while ignore and trash are local and undoable.
   → verify: harness tests on the pure helper and the copy; the dialog itself
   is app-target UI and cannot be tested here.

5. **The reason becomes legible.** Row leads with the recommended action
   (badge + the primary button doing that action); the reason moves to primary
   foreground, three lines.
   → verify: on-screen only. Left unchecked unless a human looks.

6. **`get_proposal_status` reports followed vs overrode.** `AppModel` records
   *which* action retired each row (`proposalActions`), and a pure builder in
   Kit turns sent-proposal + human actions + removals into per-sender
   `decisions` with `followed_recommendation`.
   → verify: harness tests on the builder and the JSON encoding.

7. **TASK-30 decision** recorded in notes (AC #6).

Build: `swift build`, `swift run nevermore-tests` in `Packages/NevermoreKit`.
<!-- SECTION:PLAN:END -->
