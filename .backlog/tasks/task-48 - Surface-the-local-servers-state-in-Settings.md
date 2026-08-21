---
id: TASK-48
title: Surface the local server's state in Settings
status: To Do
assignee: []
created_date: '2026-08-20 21:20'
updated_date: '2026-08-21 00:13'
labels:
  - mcp
  - ui
dependencies:
  - TASK-41
  - TASK-42
priority: medium
type: feature
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of TASK-41. The server in TASK-42 fails closed by design: if all five ports in 8775-8779 are taken it does not bind at all, because an ephemeral port would be undiscoverable by the bridge. Failing closed is only a good decision if the failure is visible somewhere — otherwise the symptom is an MCP client that reports nothing wrong except that Nevermore "isn't running", when it is.

A Settings section for the local server, following what jobhunt has: on/off, current state, the port it bound, the token file path, and a Retry for the case where whatever held the port has since released it. Off by default is the right posture for a feature most users will never use.

Deferred out of the first pass deliberately, so it is worth being explicit about the interim: until this exists, a bind failure is only visible in the log, and anyone debugging a connection problem has to know to look there. That is acceptable while the only user is the developer and not much longer.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Settings shows whether the server is running and which port it bound
- [ ] #2 A bind failure is visible in the UI with a Retry that can succeed once the port frees up
- [ ] #3 The server is off by default and the toggle persists across launches
- [ ] #4 The token file path is shown, so an MCP client can be configured without hunting for it
- [ ] #5 Turning the server off releases the port and removes the token file
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-08-21 00:13
---
Scope clarification after TASK-42 merged (main 2c5e085): NOTHING CONSTRUCTS NevermoreServer. There is no app-lifecycle wiring, no MCPTokenManager.generateAndWrite() at launch, no delete() at shutdown, and start() is never called in the shipping app. TASK-42 added the machinery and deliberately no runtime behaviour.

So this task owns more than a Settings pane: deciding when the server starts and stops, generating and removing the token around that lifecycle, and surfacing the result are one decision and belong together here. Until this is done the server does not listen at all, which means TASK-44's bridge has nothing to connect to — worth confirming the sequencing before starting TASK-44, or at least doing the lifecycle wiring early enough that TASK-44 can be tested end to end.
---
<!-- COMMENTS:END -->
