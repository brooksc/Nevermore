---
id: TASK-14
title: Adopt or drop the -dev version suffix
status: To Do
assignee: []
created_date: '2026-08-09 18:52'
labels:
  - release
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
RELEASE.md step 18 says to bump VERSION to the next patch with a -dev suffix after each release, so a stray local build cannot be mistaken for the shipped one. It has never been done: VERSION reads 1.0.0, which is exactly what the released build reads.

Either do it as part of the release checklist, or delete the step. A rule nobody follows is worse than no rule, because it makes the rest of the checklist look optional.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Decision recorded in RELEASE.md
- [ ] #2 If adopted: VERSION carries the suffix and make-app.sh handles it
- [ ] #3 If dropped: step 18 removed
<!-- AC:END -->
