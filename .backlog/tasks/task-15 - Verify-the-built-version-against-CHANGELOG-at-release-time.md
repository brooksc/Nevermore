---
id: TASK-15
title: Verify the built version against CHANGELOG at release time
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
RELEASE.md raises this against itself: the tag guard in notarize.sh and make-dmg.sh catches a VERSION that disagrees with the tag, but nothing catches a release whose version has no CHANGELOG entry. The changelog is the source for App Store release notes, so a missed entry means shipping with nothing to say.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Release scripts fail when CHANGELOG has no entry for the version being built
- [ ] #2 Guard covers both make-dmg.sh and the Release MAS workflow
<!-- AC:END -->
