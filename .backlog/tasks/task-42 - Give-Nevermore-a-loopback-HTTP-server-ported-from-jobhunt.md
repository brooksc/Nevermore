---
id: TASK-42
title: 'Give Nevermore a loopback HTTP server, ported from jobhunt'
status: Done
assignee: []
created_date: '2026-08-20 21:18'
updated_date: '2026-08-20 22:40'
labels:
  - mcp
dependencies:
  - TASK-41
priority: high
type: feature
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nevermore has no HTTP server today; jobhunt's exists for its Chrome extension and is the thing every later MCP task forwards to. Port it rather than writing a new one — it carries a security model that was reasoned through once and would be re-earned the hard way.

Source files to port from ~/code/jobhunt: server/swift/HTTPRequest.swift, HTTPResponse.swift, JobhuntServer.swift, ServerErrors.swift, plus core/App/ServerPortContract.swift and core/Settings/MCPTokenManager.swift. Keep the explanatory comments; they are the reason the code is shaped as it is.

Two decisions carried over verbatim, both of which look like defects if the reasoning is lost:

- The listener binds loopback only via requiredInterfaceType = .loopback, and THAT is the security boundary. An Origin header check is not authentication — any local process can forge it. Do not add CORS and call it access control.
- The server binds only ports from a fixed shared list, with no ephemeral fallback. An ephemeral port is undiscoverable by the bridge, so the server must fail closed and surface the failure rather than run somewhere nothing can find it.

Nevermore's port range is 8775-8779. jobhunt owns 8765-8769; 8770-8774 is deliberately left as a growth gap for it. The bridge probes this list in order to find the running app.

The token follows jobhunt's MCPTokenManager lifecycle: a fresh UUID written 0600 at launch, deleted on clean shutdown, and refused on read if the file permissions are broader than 0600. The path should be ~/.nevermore-mcp-token.

Bearer-token auth applies to the MCP routes specifically, because third-party AI clients drive them and the token scopes which may act on the user's mail.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The app binds a loopback-only listener on the first free port in 8775-8779 and reports which one
- [x] #2 With all five ports occupied the server fails closed and the failure is observable, rather than binding an ephemeral port
- [x] #3 A request from a non-loopback peer never reaches route handling
- [x] #4 MCP routes reject a missing, wrong, or over-permissive token with 401
- [x] #5 The token file is created 0600 at launch, removed on clean shutdown, and refused on read if its permissions are broader
- [x] #6 Tests cover port fallback, the all-ports-taken failure, and token permission rejection
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
New directory `Sources/NevermoreKit/Server/`, five files ported from jobhunt:

1. `ServerPortContract.swift` — 8775…8779, with the "no ephemeral fallback"
   rationale and the note that 8770–8774 is jobhunt's growth gap.
2. `HTTPRequest.swift` — `parseHTTPRequest` + `inspectRequestFraming` verbatim
   (header cap, Content-Length strictness, byte-sliced bodies).
3. `HTTPResponse.swift` — verbatim minus `withCORS`. Nevermore has no browser
   extension, so there is no origin to reflect and no CORS surface to get wrong.
4. `ServerErrors.swift` — `ServerError` cases + `safeServerError`, logging via
   `Log.app` rather than jobhunt's `print`/`DiagnosticsRedactor`.
5. `NevermoreServer.swift` — the actor: loopback-only `NWListener`, the
   fixed-port loop, framing/size guards, bearer auth for `/mcp/*`, and
   `/health` + `/api/ping`.
6. `MCPTokenManager.swift` — jobhunt's lifecycle against `~/.nevermore-mcp-token`,
   keeping the URL seam so tests never touch the real home directory.

Deviations from the source, deliberate:

- **Everything the tests touch must be `public`.** Jobhunt's tests are in-module
  so these types are internal there. Nevermore's harness is a separate
  executable target, so `routeRequest`, `parseHTTPRequest`, `HTTPResponse`,
  `MCPTokenManager` and the port contract are public here. Not an API-design
  choice — a consequence of the harness.
- **Bearer token, not `X-MCP-Token`.** The task says bearer, so
  `Authorization: Bearer <token>`, still with jobhunt's constant-time compare.
- **`/mcp/*` has no routes yet.** Auth runs and then 404s. The routes are
  TASK-44; the auth gate is what this task owes.
- **No CORS, no `Origin` check at all.** Jobhunt's origin allowlist exists to
  keep *other Chrome extensions* out. Nevermore has no extension, so the check
  would be pure ceremony that a later reader could mistake for authentication.

Out of scope: the bridge binary and MCP tools (TASK-44), Settings UI (TASK-48).
Nothing calls `NevermoreServer` from the app yet — wiring it to the app
lifecycle belongs with the UI that reports its state.

Verification: `swift run nevermore-tests`; port fallback and exhaustion tested
by holding real listeners on the contract ports; token permissions tested
through the URL seam in a temp directory.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Done as planned. 146 tests pass (117 before, 29 added), five consecutive clean
runs. Files added under `Packages/NevermoreKit/Sources/NevermoreKit/Server/`:
`ServerPortContract.swift`, `HTTPRequest.swift`, `HTTPResponse.swift`,
`ServerErrors.swift`, `MCPTokenManager.swift`, `NevermoreServer.swift`.

**How each criterion was verified**

- #1 A test occupies 8775 with a real listener and asserts the server lands on
  8776. The bound port is on `NevermoreServer.port` and logged via `Log.app`.
- #2 All five ports occupied: `start()` throws `.noPortAvailable`, `port` stays
  0 and `isListening` is false, and `errorDescription` names the range so the
  Settings surface (TASK-48) has something to show.
- #3 Verified out-of-band, because a unit test can't originate a non-loopback
  connection. A standalone binary using the same `NWParameters` bound 8775;
  `nc 127.0.0.1 8775` connected, `nc 192.168.7.230 8775` was refused. A test
  asserts `requiredInterfaceType == .loopback` so the setting can't be dropped
  silently.
- #4 401 for: no Authorization header, wrong token, empty token, the raw token
  without the `Bearer` scheme, the wrong scheme, a prefix of the token, and the
  token plus a suffix. 503 when no token is configured at all — never open. A
  further test composes the over-permissive case end to end: a widened file
  reads as nil, so the client presents nothing and gets 401.
- #5 0600 asserted on the written file; refused on read at 0644/0640/0604/0666
  and accepted at 0400 (narrower, not broader); `delete` removes it; a failed
  write leaves no file behind; each call yields a different UUID.
- #6 Covered above, plus framing tests and one end-to-end request over a real
  socket — the only test that proves the listener, parser and serialiser work
  together as HTTP rather than as function calls.

**Worth knowing**

`lsof -iTCP:8775` reports the socket as `*:8775`, not `127.0.0.1:8775`.
Network.framework enforces the loopback restriction by evaluating each incoming
connection's path, not by narrowing the bind address, so anything that audits
bind addresses will report this port as LAN-exposed. It isn't — but expect the
question, and answer it with `nc` from the LAN address rather than with lsof.
Recorded in the code comment too.

**Left undone, deliberately**

Nothing constructs `NevermoreServer` yet: no app-lifecycle wiring, no call to
`MCPTokenManager.generateAndWrite()` at launch or `delete()` at shutdown. The
mechanism is here and tested; deciding when it starts, and showing the user that
it did, is TASK-48. As it stands, `start()` is never called in the shipping app,
so this task adds no runtime behaviour — only the machinery TASK-44 forwards to.
<!-- SECTION:NOTES:END -->
