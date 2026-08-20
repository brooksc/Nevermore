---
id: TASK-42
title: 'Give Nevermore a loopback HTTP server, ported from jobhunt'
status: To Do
assignee: []
created_date: '2026-08-20 21:18'
updated_date: '2026-08-20 21:20'
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
- [ ] #1 The app binds a loopback-only listener on the first free port in 8775-8779 and reports which one
- [ ] #2 With all five ports occupied the server fails closed and the failure is observable, rather than binding an ephemeral port
- [ ] #3 A request from a non-loopback peer never reaches route handling
- [ ] #4 MCP routes reject a missing, wrong, or over-permissive token with 401
- [ ] #5 The token file is created 0600 at launch, removed on clean shutdown, and refused on read if its permissions are broader
- [ ] #6 Tests cover port fallback, the all-ports-taken failure, and token permission rejection
<!-- AC:END -->
