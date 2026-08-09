---
id: TASK-9
title: Add a Settings toggle for automatic update checks
status: To Do
assignee: []
created_date: '2026-08-09 18:52'
labels:
  - product
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Updater.swift wires up SPUStandardUpdaterController with startingUpdater: true and a Help menu item, and nothing else. Sparkle asks once on first launch and there is no way to change the answer afterwards.

The privacy policy had to be written around this — it says the app asks on first run, because promising a toggle that does not exist would be false. A toggle is a small change that makes the privacy claim simpler and gives the user somewhere to look.

Mac App Store builds compile Sparkle out entirely, so the toggle must not appear there.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Settings exposes an automatic update checks toggle, bound to Sparkle
- [ ] #2 Toggle absent in the store build, which has no updater
- [ ] #3 PRIVACY.md and docs/privacy.html updated to describe the toggle
<!-- AC:END -->
