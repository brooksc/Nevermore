---
id: TASK-19
title: Convert the test harness to swift-testing
status: To Do
assignee: []
created_date: '2026-08-09 18:53'
labels:
  - tests
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Tests run as an executable with a hand-rolled harness because SwiftPM builds test targets as .xctest bundles, which needs a full Xcode rather than Command Line Tools. That constraint is gone: the Mac App Store build already requires Xcode, and CI has it.

Raised as an open question in both PLAN.md and RELEASE.md. 110 tests to move, so worth doing before the suite grows further.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Suite runs under swift-testing
- [ ] #2 CI runs the tests as part of the Release MAS workflow or a separate one
- [ ] #3 All 110 assertions still present, none quietly dropped
<!-- AC:END -->
