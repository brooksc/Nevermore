---
id: TASK-47
title: 'Queue the senders that need a browser, and work them in one sitting'
status: To Do
assignee: []
created_date: '2026-08-20 21:20'
updated_date: '2026-08-20 21:20'
labels:
  - mcp
  - ui
dependencies:
  - TASK-41
  - TASK-46
priority: medium
type: feature
ordinal: 13000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of TASK-41. Some senders publish only a web target, or return needsManual, and someone has to click through their page. Today that is one sender at a time, interleaved with everything else. When an agent has just triaged four hundred senders and thirty of them need a browser, doing them one at a time across the rest of the workflow is the part that does not scale.

Collect them into a queue the user works through in one sitting: open, complete, next. The existing WebUnsubscribeSheet already renders the page in a WKWebView with a non-persistent data store and watches for a likely confirmation, so the per-sender mechanics exist; what is missing is the sequence around them.

The agent can identify this set before attempting anything, from supportsOneClick and the target types on the parsed header, so the queue can be built up front rather than discovered through failures.

An agent must not be able to drive the browser sheet itself. It can queue senders and read what the human confirmed. The sheet is a human-in-the-loop step by construction, and that is not an implementation limit to be worked around.

TASK-23 is adjacent — offering to trash the backlog once a browser unsubscribe is confirmed — and the confirmation signal it needs is the same one this queue advances on. Worth building them together rather than twice.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Senders needing a browser can be queued from an agent proposal without attempting an unsubscribe first
- [ ] #2 The user can work the queue in sequence without returning to the sender list between each
- [ ] #3 Each completion records an outcome distinguishing a confirmed unsubscribe from an abandoned one
- [ ] #4 An agent can read queue progress but cannot advance or drive the sheet
- [ ] #5 Leaving the queue part-way keeps the remaining entries for later
<!-- AC:END -->
