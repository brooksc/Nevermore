---
id: TASK-40
title: Work out whether the MCP server can ship in the App Store build
status: On Hold
assignee: []
created_date: '2026-08-20 20:53'
updated_date: '2026-08-20 20:53'
labels:
  - mcp
  - store
dependencies: []
references:
  - 'https://unclutr.app/blog/unclutr-files-mcp-support-local-ai-duplicate-scan'
  - >-
    https://medium.com/@charidimos/building-an-mcp-server-for-a-swift-native-macos-app-84197137d378
  - 'https://modelcontextprotocol.io/specification/2025-03-26/basic/transports'
  - 'https://apps.apple.com/us/app/mcp-one-mcp-server-manager/id6748261474?mt=12'
priority: low
type: spike
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The MCP server is planned as direct-download only, on the assumption that the App Sandbox rules it out. That assumption is worth testing before it hardens into a permanent split, because shipping one build is cheaper to support than two and the store audience is the larger one.

The assumption comes from the stdio transport, where an MCP client spawns a helper binary shipped inside the app bundle. That path is well documented as painful under the sandbox: helper binaries that pass validation on disk still fail to execute with "Operation not permitted", plus hardened-runtime and archive-validation friction. At least one shipping macOS app (unclutr) hit exactly this and split its distribution the same way.

The streamable HTTP transport may avoid the whole problem, because the app itself is the server and nothing is spawned. A sandboxed app can hold a loopback listener with com.apple.security.network.server. What is not established is Apple's review stance on a store app opening a localhost listening socket for agent control, and no source found so far documents it either way. Two App Store apps (MCP One, MCP Server Pro) appear to do something adjacent, but whether they expose a server or only act as clients was not determined.

Not an immediate goal. Direct-download remains the shipping decision for the first release either way; this exists so the store question is answered on evidence rather than inherited from a previous project's conclusion.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 It is established whether a sandboxed build can hold a loopback MCP listener and be accepted by App Review, with the evidence recorded
- [ ] #2 The stdio-helper path is confirmed unworkable under the sandbox, or shown to work
- [ ] #3 If the store build cannot carry MCP, the reason is written down where a future reader will find it rather than left as folklore
- [ ] #4 MAS-RELEASE.md records the outcome alongside the other store constraints
<!-- AC:END -->
