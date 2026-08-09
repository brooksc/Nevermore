---
id: TASK-5
title: Replace deprecated SwiftMail search before a dependency bump breaks sync
status: To Do
assignee: []
created_date: '2026-08-09 18:51'
labels:
  - tech-debt
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A clean build emits four warnings for search(identifierSet:criteria:calendar:), deprecated in favour of extendedSearch(...) for structured results or search(..., sortCriteria:) for ordered ones.

This is on the sync path, and SwiftMail is pinned to an exact revision precisely because it moves fast. The next time that pin is raised, a deprecation can become a removal and sync stops working.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Calls migrated to the replacement API
- [ ] #2 No deprecation warnings from SwiftMail in a clean build
- [ ] #3 Full sync and incremental sync verified against a real mailbox
<!-- AC:END -->
