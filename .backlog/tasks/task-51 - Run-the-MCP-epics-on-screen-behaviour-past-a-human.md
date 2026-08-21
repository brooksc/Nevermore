---
id: TASK-51
title: Run the MCP epic's on-screen behaviour past a human
status: To Do
assignee: []
created_date: '2026-08-21 02:16'
updated_date: '2026-08-21 02:17'
labels:
  - mcp
  - ui
dependencies: []
priority: high
type: task
ordinal: 17000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The MCP epic (TASK-41 through TASK-48) is implemented, merged and covered by 309 passing tests, but every part of it that asserts something on screen is unverified. The implementing agents were forbidden from launching the GUI — the machine is shared with the user — so they correctly left those criteria unchecked rather than ticking them on a clean build.

What was verified against a running app: the local server binds a contract port, the token file is created 0600 and removed when the app quits, an unauthenticated MCP request is refused and an authenticated one reaches routing. That was done over the wire with curl during integration, on the user's real mailbox.

What nobody has looked at:

- TASK-48: the Settings pane. Toggle, running state, bound port, token path, and the Retry that appears after a bind failure. Whether the failure message renders and the Retry works from the button rather than the model.
- TASK-45: the Proposed collection. That the REVIEW section appears when a proposal arrives and vanishes when cleared, that the agent's reason is legible in the row, that selection and keyboard triage behave as they do in All Senders, and that a proposal survives a relaunch.
- TASK-27: selection, click, shift-click, command-click and j/k across Reappeared, Unsubscribed and Ignored. Also whether disabled actions actually grey out and whether their tooltips appear — macOS may not surface tooltips on menu items at all.
- TASK-47: the browser queue as a sequence — open, complete, next — and that leaving part-way keeps the rest.
- TASK-44: the full path, an MCP client through the bridge to a running app. Every leg has been proven separately; the whole has not been run end to end.

The unchecked criteria on each of those tasks are the checklist. This is not a rewrite of them, it is the session where someone opens the app and looks.

Worth doing before 1.0.1 ships, because it is the first release carrying any of this.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The unchecked criteria on TASK-27, TASK-44, TASK-45, TASK-47 and TASK-48 are each either ticked after being seen working, or turned into a defect
- [ ] #2 An MCP client is connected through the bridge to a running app and completes a read call
- [ ] #3 A proposal is created, reviewed, edited and confirmed end to end, and the per-sender outcomes are what the app reports
- [ ] #4 Anything found is filed rather than fixed in passing, unless the fix is smaller than the report
<!-- AC:END -->
