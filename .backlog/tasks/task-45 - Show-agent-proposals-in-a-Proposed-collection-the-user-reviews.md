---
id: TASK-45
title: Show agent proposals in a Proposed collection the user reviews
status: To Do
assignee: []
created_date: '2026-08-20 21:19'
updated_date: '2026-08-20 21:19'
labels:
  - mcp
  - ui
dependencies:
  - TASK-41
  - TASK-27
  - TASK-44
priority: high
type: feature
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of TASK-41. This is where an agent's proposal becomes something a human can actually check, and it is the safety mechanism for the whole feature — everything else assumes this review is real.

A fifth sidebar collection, Proposed, holding the senders an agent has put forward. It reuses the existing sender table, inspector, multi-select and keyboard model, so Command-A, shift-click and per-row keys work as they already do. Not a sheet: a sheet is modal, blocks the app, cannot use keyboard triage, and the existing results sheet already has the hidden-scroll defect in TASK-28.

The row must show the agent's one-line reason. Reviewing twenty-five rows without seeing why each was picked is not review, it is rubber-stamping, and the reason is the only thing that makes an agent's judgement checkable. It belongs in the table, not buried in the inspector.

The collection appears only when it holds something, and disappears when cleared. Most users will never connect an MCP client, and a permanently visible empty collection is an advertisement for a feature they cannot use.

Proposals should survive an app restart: the agent session and the review session are naturally hours apart.

Note the ordering constraint against TASK-27 — Reappeared, Unsubscribed and Ignored do not currently share the selection model that All Senders has. Adding a sixth variant of selection handling before that is resolved would make the problem worse.

Sidebar shortcuts are positional, so inserting a collection renumbers the ones after it. UI_SPEC.md documents four collections and must be updated with whatever this becomes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Proposed appears in the sidebar only while it holds senders, and disappears when cleared
- [ ] #2 Rows show the agent's reason in the table itself
- [ ] #3 Selection, keyboard triage and multi-select behave exactly as in All Senders
- [ ] #4 A proposal survives quitting and reopening the app
- [ ] #5 Dismissing a proposal clears it without acting on any sender
- [ ] #6 UI_SPEC.md is updated for the new collection and any shortcut renumbering
<!-- AC:END -->
