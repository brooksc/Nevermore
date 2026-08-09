---
id: TASK-16
title: Stop embedding Sparkle in sandboxed local builds
status: To Do
assignee: []
created_date: '2026-08-09 18:52'
labels:
  - tech-debt
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
make-app.sh copies and signs Sparkle.framework whenever it is present, including under NEVERMORE_SANDBOX=1. The Sparkle feed keys are correctly omitted, so the updater is inert, but the framework and its XPC services are still in the bundle.

Harmless for the real store artifact, which Tuist builds without Sparkle at all. It is misleading though: the sandbox build exists to approximate the store build, and it differs in exactly the way the store cares about.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Sandboxed builds omit Sparkle.framework entirely
- [ ] #2 DMG builds unchanged
<!-- AC:END -->
