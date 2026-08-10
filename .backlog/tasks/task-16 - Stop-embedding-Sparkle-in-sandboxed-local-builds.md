---
id: TASK-16
title: >-
  Verify sandbox behaviour against the Tuist store build, not a Sparkle-stripped
  one
status: Wont Do
assignee: []
created_date: '2026-08-09 18:52'
updated_date: '2026-08-10 02:04'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Tried and reverted. The SwiftPM NevermoreApp target depends on Sparkle unconditionally, so the binary links @rpath/Sparkle.framework whether or not the feed keys are written. Removing the framework from a sandboxed build makes it fail at launch: 'Library not loaded: @rpath/Sparkle.framework'. The embed is not decoration, it is what makes the SwiftPM-built app runnable at all.

So the premise was wrong. The build that genuinely contains no updater already exists — the Tuist store target, which never declares the Sparkle package, which is why its preflight asserts otool shows nothing. Sandbox verification should use that artifact (make-mas.sh, or the Release MAS workflow's .pkg) rather than a stripped approximation.

Doing it 'properly' in SwiftPM would mean package traits or a second executable product without Sparkle — real work to reproduce something Tuist already produces correctly.
<!-- SECTION:NOTES:END -->
