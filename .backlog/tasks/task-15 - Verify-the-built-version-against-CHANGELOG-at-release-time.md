---
id: TASK-15
title: Verify the built version against CHANGELOG at release time
status: Done
assignee: []
created_date: '2026-08-09 18:52'
updated_date: '2026-08-10 02:05'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Guard added in two places: make-dmg.sh for the DMG channel, and the Release MAS workflow before the archive, so neither channel can ship a version with nothing to say. Both look for '## [VERSION]' in CHANGELOG.md and fail with the version named. Verified passing on 1.0.0 and blocking on a fabricated version.
<!-- SECTION:NOTES:END -->
