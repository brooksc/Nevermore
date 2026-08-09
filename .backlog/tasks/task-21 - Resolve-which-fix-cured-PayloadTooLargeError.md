---
id: TASK-21
title: Resolve which fix cured PayloadTooLargeError
status: On Hold
assignee: []
created_date: '2026-08-09 18:53'
updated_date: '2026-08-09 19:00'
labels:
  - product
dependencies: []
priority: low
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
An incremental sync once failed with PayloadTooLargeError. Two changes landed together — raising responseBufferLimit to 32 MB and switching to date-based search — and it has not recurred, so which one was responsible is unknown.

Nothing to do while it stays quiet. If it returns, resolve the ambiguity before attempting another fix, or the same guessing repeats.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 If it recurs: isolate which change matters and record it in PLAN.md
<!-- AC:END -->
