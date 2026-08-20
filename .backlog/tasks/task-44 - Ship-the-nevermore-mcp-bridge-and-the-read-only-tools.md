---
id: TASK-44
title: Ship the nevermore-mcp bridge and the read-only tools
status: To Do
assignee: []
created_date: '2026-08-20 21:19'
updated_date: '2026-08-20 21:19'
labels:
  - mcp
dependencies:
  - TASK-41
  - TASK-42
  - TASK-43
priority: high
type: feature
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of TASK-41. The bridge is a thin stdio-to-HTTP forwarder modelled directly on ~/code/jobhunt/mcp/swift/. It reads JSON-RPC 2.0 from stdin, forwards to 127.0.0.1 on the discovered port with the token header, and writes responses back. It holds no state beyond token and port, opens no database, and needs no entitlements — which is precisely why it survives being spawned by an arbitrary MCP client.

Copy jobhunt's reconnection behaviour, which exists because of a real failure: the bridge outlives the app it talks to, so an app relaunch rotates the token and may move the port, and every subsequent call fails until the client restarts the bridge. A 401 refreshes the token; a bodyless 5xx re-probes the port; retry once, then surface the error.

The bridge is a separate executable target, excluded from the Tuist store build. Direct-download only.

Read tools in scope:

- list_senders — filters on collection, message count, unread percentage, last-received window, unsubscribe method, mailing-list status, and classification or context label; paged, with a sane default limit, because a real mailbox has around a thousand senders and returning them all with subjects would swamp any agent's context
- get_sender — one group in full, including parsed List-Unsubscribe targets and whether it supports one-click
- list_messages — subjects and dates for one sender
- search_senders — text across display name, address, domain, subject
- unsubscribe_history, list_reappeared — what was done and who ignored it
- mailbox_summary, sync_status — orientation without pulling rows
- list_by_context — the cohort query from TASK-43

Every tool description must state that message bodies do not exist locally and never will, or an agent will assume it can read content and reason as though it had.

Partitioning by unsubscribe method matters and is knowable before acting: ListUnsubscribe already exposes supportsOneClick, webTargets and mailtoTargets, so the agent can tell the user which senders will need a browser without attempting anything.

Every response identifies the account it refers to. Requests are served for the currently open account only; there is no account switching over MCP.

In demo mode the tools refuse. A consequence to plan for rather than discover: the surface cannot be exercised end-to-end against the demo mailbox, so tests drive the routes directly through the harness.

PRIVACY.md gains its disclosure here, since this is the task that first sends sender names and subject lines off the machine: using an MCP client means that data goes to whatever AI model is connected, which may be cloud-hosted. Stated plainly, not prompted for.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An MCP client can connect through the bridge and call every read tool against the running app
- [ ] #2 The bridge recovers from an app relaunch that rotates the token and moves the port, without being restarted
- [ ] #3 list_senders pages and defaults to a limit that does not swamp an agent on a thousand-sender mailbox
- [ ] #4 Every tool description states that message bodies are unavailable
- [ ] #5 Senders are partitioned by unsubscribe method without attempting an unsubscribe
- [ ] #6 Tools refuse in demo mode, and every response names the account it refers to
- [ ] #7 The bridge target is absent from the Tuist store build
- [ ] #8 PRIVACY.md discloses the data sent to a connected AI model
- [ ] #9 README documents connecting an MCP client, including that the app must be running
<!-- AC:END -->
