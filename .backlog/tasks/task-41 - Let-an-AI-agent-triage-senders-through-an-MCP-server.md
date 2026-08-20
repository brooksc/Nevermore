---
id: TASK-41
title: Let an AI agent triage senders through an MCP server
status: To Do
assignee: []
created_date: '2026-08-20 21:17'
updated_date: '2026-08-20 21:18'
labels:
  - mcp
  - product
dependencies: []
references:
  - /Users/brooksc/code/jobhunt/mcp/swift/MCPHelpers.swift
  - /Users/brooksc/code/jobhunt/server/swift/JobhuntServer.swift
  - /Users/brooksc/code/jobhunt/core/App/ServerPortContract.swift
  - /Users/brooksc/code/jobhunt/core/Settings/MCPTokenManager.swift
priority: high
type: feature
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nevermore decides one sender at a time, which is right when the answer is uncertain and useless when the question is "which of these 400 senders belong to a life situation that is now over". That judgement is semantic, contextual, and changes over time — a keyword rule cannot express it, and building an LLM into Nevermore is not wanted.

The shape that works: an external coding agent is the classifier, Nevermore is the actuator and the memory of what was decided. The agent reads sender metadata over MCP, classifies in its own context, and writes back a decision with a reason and a context label that Nevermore never interprets. Nevermore stores it verbatim, so a later session can ask "what did we keep for job-search-2026" without re-deriving anything.

Confirmed product decisions, which a future implementer must not quietly reverse:

- The agent proposes; the human actuates. There is no unattended bulk unsubscribe over MCP. Bulk goes through a selection the human reviews in the app, and the batch path requires a review token the app mints only on human confirmation. This is TASK-39 restated.
- Proposals are capped in size, because "reviewable" is the entire safety mechanism and a 300-row proposal is not reviewable.
- The app must be running. It is the single writer; nothing else opens the database.
- Direct-download build only. The bridge target is excluded from the Tuist store build. Whether the store build could ever carry it is TASK-40.
- Current open account only. No agent-initiated account switching.
- Refused in demo mode. Consequence: the MCP surface cannot be exercised against the demo mailbox, so its tests drive the routes directly in the harness rather than through a demo session.
- Using an MCP client sends sender names and subject lines to a third-party model that may be cloud-hosted. This is a deliberate, accepted change to the app's posture and is disclosed in PRIVACY.md rather than prompted for.

Message bodies are never available. The agent classifies on sender, domain, subject lines, dates and read rate, which is a real ceiling on classification quality and must be stated in the tool descriptions or an agent will assume otherwise.

The architecture is proven in the sibling jobhunt project (~/code/jobhunt): a thin stdio-to-HTTP bridge binary forwarding to a loopback HTTP server inside the running app, with a fixed discoverable port range, a rotating file token, and refresh-and-retry on relaunch. Reuse it rather than re-deriving it.

TASK-35 (App Intents for Shortcuts) wants the same verbs with the same confirmation rules. Both should sit on one internal action layer; whoever builds this first should shape it so the other is a second caller, not a second implementation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An MCP client can list, filter and inspect senders from the running app, on the currently open account
- [ ] #2 Agent classifications persist with a reason and a context label, and survive regrouping
- [ ] #3 Bulk unsubscribe is impossible without a human-reviewed, human-confirmed selection in the app
- [ ] #4 Senders needing a browser can be identified before any unsubscribe is attempted, and queued for the human
- [ ] #5 The store build does not contain the bridge target
- [ ] #6 PRIVACY.md discloses that MCP use sends sender names and subject lines to a third-party model
<!-- AC:END -->
