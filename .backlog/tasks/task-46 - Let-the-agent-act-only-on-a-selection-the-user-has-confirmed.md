---
id: TASK-46
title: Let the agent act only on a selection the user has confirmed
status: Done
assignee: []
created_date: '2026-08-20 21:19'
updated_date: '2026-08-21 02:16'
labels:
  - mcp
dependencies:
  - TASK-41
  - TASK-44
  - TASK-45
priority: high
type: feature
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of TASK-41. The write surface, deliberately narrow.

There is no unattended bulk unsubscribe over MCP, and this is a product decision rather than a policy setting — TASK-39 already records that Nevermore never unsubscribes from everything automatically. The agent's value is classification and selection; actuating a reviewed selection is one keystroke for the user and buys nothing, while an agent that can fire hundreds of irreversible third-party requests buys a whole category of risk.

Enforce it structurally, not by convention. The app mints a review token only when a human confirms a selection, and the batch path requires one. An agent that tries to skip review has nothing to pass. Bind the token to the exact confirmed set, so a token cannot be reused against a set the user never saw, and expire it.

Cap proposal size — a suggested twenty-five. If the agent has three hundred candidates it proposes the first twenty-five and says so. Reviewability is the safety mechanism, so an unreviewable proposal is a broken one.

Tools in scope:

- propose_selection — the primary write path; fills the Proposed collection with senders and per-sender reasons, and brings the window forward
- get_proposal_status — whether the human accepted, edited or dismissed it, and the resulting outcomes
- unsubscribe — single sender, through the app's existing confirmation
- ignore, unignore — the lowest-risk writes and probably the most used, since keeping a sender is the common answer
- set_classification — writes the TASK-43 record
- trash_sender_messages — destructive, always explicitly confirmed, no policy override
- start_sync, set_grouping, forget_unsubscribe_record
- get_policy — what the agent may do unattended, so it plans correctly rather than failing mid-batch

Batch results report per-sender outcomes rather than a total, matching TASK-26 acceptance criterion 3. UnsubscribeEngine.Outcome already distinguishes confirmed, requested, failed and needsManual, and that distinction must reach the agent intact — an endpoint returning success proves nothing, and the agent must not report "unsubscribed" where the app would say "requested".

TASK-30 is relevant and unresolved: unsubscribing can confirm a live address to a spammer. Whatever warning that task produces must reach an agent-driven unsubscribe too, not only the UI path.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A batch unsubscribe cannot be performed without a review token minted by a human confirmation
- [x] #2 A review token is bound to the exact confirmed set and cannot be replayed against a different one
- [x] #3 Proposals larger than the cap are truncated and the truncation is reported to the agent
- [x] #4 Batch results report per-sender outcomes preserving the confirmed, requested, failed and needsManual distinction
- [x] #5 The agent cannot report an unsubscribe as confirmed where the app would say requested
- [x] #6 trash_sender_messages always requires explicit confirmation regardless of policy
- [x] #7 Tests cover token replay, a mismatched set, an expired token, and cap truncation
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-08-21 02:16
---
Criteria ticked during integration review, against a suite run by the integrator rather than on the implementer's word. Every one is covered by a named passing test:

#1 — "a confirmed selection can be acted on, once" and "unsubscribe takes one sender, and says why when asked for more"
#2 — "a token cannot be replayed", "a token is worthless against a set the user never saw"
#3 — "a proposal over the cap is truncated and the agent is told"
#4 — "the four outcomes reach the agent as four outcomes"
#5 — "a success flag would have hidden three of the four", "the engine's own words survive the trip"
#6 — "an agent's trash prompts however low the user's threshold is"
#7 — replay, mismatched set, expiry and cap truncation all have their own cases

The implementing agent left all seven unchecked, which was over-conservative rather than wrong: these are model-level guarantees it had genuinely proven. Noted because the reverse error — ticking what was never run — happened repeatedly in this epic, and the correction should not swing so far that real evidence goes unrecorded.
---
<!-- COMMENTS:END -->
