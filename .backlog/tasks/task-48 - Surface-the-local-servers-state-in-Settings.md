---
id: TASK-48
title: Surface the local server's state in Settings
status: In Progress
assignee: []
created_date: '2026-08-20 21:20'
updated_date: '2026-08-20 22:55'
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
- [x] #5 Turning the server off releases the port and removes the token file
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
TASK-42 built `NevermoreServer` and `MCPTokenManager` but nothing constructed either, so this is
lifecycle wiring first and a Settings pane second.

1. `Sources/NevermoreKit/Server/LocalServerController.swift` — an actor pairing the token with the
   listener: `start(isDemo:)` writes a fresh 0600 token and builds a server around it (the server
   takes its token at init and never mutates it), `stop()` cancels the listener and deletes the
   token. Returns a `LocalServerStatus` the UI can render. → verify: harness tests for bind, stop,
   and the all-ports-taken failure.
2. `AppModel` — owns the controller, mirrors its status for SwiftUI, starts it at launch when the
   setting is on (not awaited: a full failing bind can take seconds), restarts it across demo-mode
   changes so `/api/ping` stops lying about `is_demo`, and deletes the token on
   `willTerminateNotification`. → verify: `swift build`.
3. `AppSettings.localServerEnabled` + `@AppStorage("localServerEnabled")` in SettingsView, default
   false. → verify: build.
4. Settings → Advanced → "Local server": toggle, address, token path, and the failure message with
   a Retry. → verify: build only; launching the GUI is not available here.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
The server now actually runs: `LocalServerController` is the only thing that constructs a
`NevermoreServer`, and it cannot construct one without also writing the token that authenticates
against it, which is what stops the two halves drifting apart again.

Off by default, so a first launch binds nothing.

What the tests cover (5 new cases in `Local server lifecycle`; 162 pass in total):
- start binds a port from the contract range, and the token *file on disk* is accepted by the
  server that is actually listening — proven over the wire, 404 with the file's token vs 401
  without, rather than by comparing two in-memory strings;
- stop deletes the token and releases the port, proven by re-binding the port afterwards;
- with all five ports held, the reported failure names 8775 and 8779 and leaves no token behind,
  and a retry after the holders release succeeds — the Retry path, minus the button;
- the token path is available before the server has ever run.

Not verified: nothing in Settings was seen rendered. The GUI must not be launched on this machine,
so ACs #1, #2 (the "visible in the UI" half), #3 (persistence across an actual relaunch) and #4 are
implemented and compile but are left unchecked above.

Known gap: the launch-time start rides on `AppModel.start()`, which the keychain explainer sheet
defers — so on the one launch that shows that sheet, the server comes up only after it is dismissed.
<!-- SECTION:NOTES:END -->
