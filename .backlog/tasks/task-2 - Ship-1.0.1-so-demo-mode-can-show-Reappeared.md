---
id: TASK-2
title: Ship 1.0.1 so demo mode can show Reappeared
status: On Hold
assignee: []
created_date: '2026-08-09 18:50'
labels:
  - release
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Twelve commits sit unreleased since v1.0.0, and one of them matters to users: 47c6cb4 seeds the demo mailbox with unsubscribe history. Without it, Reappeared is always empty in demo mode, so anyone meeting the app through the demo — including an App Review reviewer following our own review notes — never sees the feature the app is named after.

On hold deliberately: 1.0.0 is in review, and a second version in flight would confuse that. Release once Apple approves or asks for changes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 VERSION bumped to 1.0.1 and CHANGELOG updated
- [ ] #2 Signed tag v1.0.1 pushed
- [ ] #3 DMG released and the appcast updated, verified live
- [ ] #4 Store build produced by the Release MAS workflow and uploaded
<!-- AC:END -->
