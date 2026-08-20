---
id: TASK-35
title: Expose actions to Shortcuts
status: To Do
assignee: []
created_date: '2026-08-10 01:49'
updated_date: '2026-08-20 21:20'
labels:
  - product
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Cheap to add and it fits the audience: someone who runs a local-first, keyboard-driven mail tool is the same person who automates things. App Intents for the obvious verbs — sync, unsubscribe from a named sender, list reappeared senders — make the app scriptable without an API or a server.

Also useful for the store listing, since Shortcuts support is a feature Apple likes to see.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 App Intents for sync, unsubscribe, ignore, and querying reappeared senders
- [ ] #2 Intents refuse to act without the same confirmations the UI requires
- [ ] #3 Works in the sandboxed store build
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-08-20 21:20
---
TASK-41 (MCP server for agent triage) needs the same verbs with the same confirmation rules — sync, unsubscribe, ignore, query reappeared, all refusing to act without the confirmations the UI requires. Whichever is built first should put those verbs in one internal action layer so the other becomes a second caller rather than a second implementation. Note the divergence: App Intents must work in the sandboxed store build (this task's AC #3), while the MCP bridge is excluded from it, so the action layer has to sit below that split.
---
<!-- COMMENTS:END -->
