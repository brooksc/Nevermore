---
id: TASK-26
title: Smart selections for batch triage
status: To Do
assignee: []
created_date: '2026-08-10 01:47'
labels:
  - product
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The core loop is one sender at a time, which is right when the answer is uncertain and wrong when it is obvious. On a mailbox with a thousand senders, most of the decisions are not close: a sender with 40 messages and 0% opened does not need thinking about.

The pieces exist — selection is already a Set, actions already take multiple ids, and the confirmation sheet already says "Unsubscribe from N senders?". What is missing is a way to express the selection.

Starting set, all derivable from what is already stored: never opened (0% read), rarely opened (under 10%) with volume above a threshold, nothing received in a year, and one-click capable (so the whole batch can complete without a browser).

Keep it a selection, not an action: it fills the selection and shows the list, the user reviews and presses the button. Never a "clean my inbox" button that acts on its own.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A menu of smart selections that fill the current selection
- [ ] #2 Selection is reviewable before any action
- [ ] #3 Batch unsubscribe reports per-sender outcomes, not just a total
- [ ] #4 Nothing acts without an explicit confirmation
<!-- AC:END -->
