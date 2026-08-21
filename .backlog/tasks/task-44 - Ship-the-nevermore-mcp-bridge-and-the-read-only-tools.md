---
id: TASK-44
title: Ship the nevermore-mcp bridge and the read-only tools
status: Done
assignee: []
created_date: '2026-08-20 21:19'
updated_date: '2026-08-21 09:00'
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
- [x] #2 The bridge recovers from an app relaunch that rotates the token and moves the port, without being restarted
- [x] #3 list_senders pages and defaults to a limit that does not swamp an agent on a thousand-sender mailbox
- [x] #4 Every tool description states that message bodies are unavailable
- [x] #5 Senders are partitioned by unsubscribe method without attempting an unsubscribe
- [x] #6 Tools refuse in demo mode, and every response names the account it refers to
- [x] #7 The bridge target is absent from the Tuist store build
- [x] #8 PRIVACY.md discloses the data sent to a connected AI model
- [x] #9 README documents connecting an MCP client, including that the app must be running
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-08-21 09:00
---
Plan, recorded before coding.

1. `UnsubscribeMethod` (Domain) — one_click / web / mailto / none derived from
   the group's newest unsubscribable message, plus `needsBrowser`. This is the
   partition AC #5 asks for and it is knowable from stored headers alone.
2. `MCPSnapshot` (Server) — rebuilds the app's grouped read model from the
   MessageStore alone: messages, grouping rules, ignored keys, unsubscribe
   history, decisions, sync token. No UI, so the harness can drive it.
3. `MCPRoutes` — pure `(snapshot, HTTPRequest) -> HTTPResponse` handlers for the
   nine read tools. Paging with limit 50 / max 200.
4. `MCPToolCatalog` — the tool definitions live in NevermoreKit, not in the
   bridge, so the harness can assert every description names the body limit and
   every schema parses.
5. `MCPBridgeProtocol` — the JSON-RPC framing and `shouldRefreshMCP` as pure
   functions, for the same reason.
6. `Sources/NevermoreMCP` — a new executable target: token read, /health port
   probe, Bearer forward, refresh-and-retry. Product is an executable, and
   Project.swift depends only on the NevermoreKit *library* product, so the
   store build cannot pick it up.
7. Wire MessageStore into NevermoreServer via a settable MCPContext (account +
   store), set from AppModel when an account opens and cleared on close.
8. PRIVACY.md disclosure, README connection instructions.

Verification: routes driven directly in the harness; the bridge's JSON-RPC and
refresh logic tested as pure functions. The full bridge -> running app leg
cannot be exercised here (launching the GUI is not permitted on this machine),
and will be reported as unverified rather than ticked.
---
author: claude
created: 2026-08-21 00:13
---
Integration constraints from TASK-42, which is now merged (main 2c5e085). Read these before porting jobhunt's MCP helper.

1. HEADER NAME DIVERGES FROM JOBHUNT. The server authenticates `Authorization: Bearer <token>`, parsing the scheme case-insensitively. Jobhunt's bridge sends `X-MCP-Token` and will NOT authenticate against Nevermore unless changed. Match the server; do not change the server to match the ported bridge.

2. Token path is ~/.nevermore-mcp-token (not ~/.jobhunt-mcp-token). Port range is 8775-8779 (not 8765-8769). Probe endpoint is /health, which returns 200 and exactly {"ok":true}.

3. /mcp/* currently authenticates and then returns 404 "MCP route not found". The 404 is deliberately about the route, not the credential, so a bridge can distinguish "bad token" from "tool not implemented". Preserve that distinction when adding real routes.

4. NevermoreServer has no reference to MessageStore or any service — its entire dependency surface is three init parameters (appVersion, isDemo, mcpToken). Wiring the store in is this task's work.

5. The token protects against other accounts on the Mac, not against a process running as this user, which can read the 0600 file and drive every route. That is an accepted tradeoff for a localhost companion. It does mean the token is NOT what bounds the damage once these routes can act on mail — TASK-46's confirmed-selection requirement is. Do not let TASK-46 slip past this task on the assumption that the token is holding the line.
---
author: claude
created: 2026-08-21 12:00
---
Done, with one acceptance criterion deliberately left unchecked.

WHAT WAS BUILT

- `UnsubscribeMethod` (Domain) — one_click / web / mailto / none, derived from
  the newest message that carries a header, matching what `UnsubscribeEngine`
  would actually attempt. `needsBrowser` is true only for `none`; a sender who
  already ignored an unsubscribe is combined with it at the row level.
- `MCPSnapshot` — the app's grouped read model rebuilt from the store alone,
  reusing `Grouping`, `Collection` and `SenderState` rather than restating them.
  Built per request, because the app writes to that database continuously.
- `MCPRoutes` — nine read routes, each a pure function of (snapshot, arguments).
- `MCPToolCatalog` — the tool definitions, in NevermoreKit so the harness can
  hold them to their promises rather than in an unreachable `main.swift`.
- `MCPBridgeProtocol` — JSON-RPC framing and the refresh-and-retry rule, pure.
- `Sources/NevermoreMCP` — the bridge executable, a new product.
- `NevermoreServer.setMCPContext` and the matching passthrough on
  `LocalServerController`; `AppModel` publishes it on every path that opens,
  switches or closes a mailbox.

TESTS: 230 pass, 0 fail (`swift run nevermore-tests`). Baseline on this branch
was 180, so 50 are new. Two pre-existing tests were updated rather than left
passing on a false premise: they used `/mcp/senders/list` as a stand-in for "a
route that doesn't exist yet", which it no longer is. They now use
`/mcp/not-a-tool` for the 404, and the lifecycle test expects 503 (no mailbox
open) where it expected 404.

PER-AC VERIFICATION

#1 NOT VERIFIED, left unchecked. Two of its three legs are proven and the third
is not. Proven: the real `nevermore-mcp` binary driven over stdin against a
stand-in that speaks the server's wire contract — all nine tools reach nine
distinct routes with `Authorization: Bearer`, arguments forwarded verbatim, the
answer returned as text. Proven separately: a real `NevermoreServer`, started
through `LocalServerController` and reached over an actual socket, answers
`/mcp/mailbox/summary` 200 and names the account. NOT proven: an MCP client
talking to Nevermore.app itself, because launching the GUI needs the user's
permission on this shared Mac and was not sought. What is unexercised is
specifically `AppModel` publishing the context and starting the server on a real
launch — the wiring, not the surface.

#2 Verified with the real bridge binary: a 401 plus a rewritten token file made
it retry with the new credential; killing the stand-in on 8775 and restarting it
on 8777 made it re-probe and follow, both without the bridge being restarted.
The relaunch was simulated, but simulated by doing what a relaunch does.

#3 Verified: 400-sender snapshot, default limit 50, `has_more`/`next_offset`
present, and a paging loop that walks 120 senders exactly once with no repeats.
A limit above 200 is clamped and the reduction is reported in `note`.

#4 Verified twice: every catalogued description, and every description as it
arrives at a client through `tools/list`. Also on every response body, in `note`
— an agent may see a response without the description that came with it.

#5 Verified from stored headers only, with no network anywhere in the path:
one-click, web, mailto and none each filter to exactly their sender.

#6 Verified: all nine routes answer 403 in demo mode, all nine name the account,
and the four refusals stay distinguishable (401 credential, 404 route, 403 demo,
503 no mailbox) — including that 401 still wins over 403, so a bad token in demo
mode reads as a bad token.

#7 Verified for real, not by argument: `tuist generate` was run and the produced
`Nevermore.xcodeproj` contains zero references to `NevermoreMCP` or
`nevermore-mcp`. The generated project was deleted afterwards. A test also pins
`Project.swift` against ever naming them.

#8 and #9 Verified by reading the result; both are prose.

NOT VERIFIED, beyond #1: nothing on screen. The Settings ▸ Local Server copy was
corrected — it said an assistant could "read your senders and act on them",
which overstates a read-only surface — and the running-state line now points at
the bridge rather than at the address. Neither was seen rendered.

DESIGN NOTES FOR TASK-46

- The context seam (`MCPContext` = account + store) is what a write path will
  also need, and it deliberately carries no way to act. A confirmed-selection
  route will need something else from the app — the selection, and the review
  token — which `MCPContext` cannot supply as it stands. Widening it into "the
  app's capabilities" is the tempting move and the wrong one; a second, separate
  handle for the write path keeps "read" incapable of writing by construction.
- Routes are keyed by `GroupID.storageKey`, which is stable only until the user
  merges or splits. For reads that is harmless. For a confirmed write it is not:
  an agent could propose ids that regrouping has since invalidated, and the
  confirmation the user gave would be about different rows. TASK-46 should
  resolve a proposal against grouping as it stands at confirmation time, and
  refuse rather than silently re-resolve.
- `MCPRoutes.paths` is the single list of what exists; the tests assert the
  catalog and the server agree in both directions, so an added write route
  without a tool (or the reverse) fails the suite.
---
<!-- COMMENTS:END -->
