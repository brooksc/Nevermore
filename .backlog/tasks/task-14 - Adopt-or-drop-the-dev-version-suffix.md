---
id: TASK-14
title: Adopt or drop the -dev version suffix
status: Done
assignee: []
created_date: '2026-08-09 18:52'
updated_date: '2026-08-23 20:05'
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
- [x] #1 Decision recorded in RELEASE.md
- [ ] #2 If adopted: VERSION carries the suffix and make-app.sh handles it
- [x] #3 If dropped: step 18 removed
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-08-23 20:05
---
Dropped. Step 18 is gone from RELEASE.md, with the reasoning left in its place so the idea is not reinvented.

The suffix guarded against mistaking a local build for the shipped one. That is already guarded, three ways: build numbers are commit counts so a local build reads 1.0.0 (93) against the release's 1.0.0 (49) and scripts/run prints it on launch; notarize.sh refuses a VERSION that disagrees with the git tag; and both release paths refuse a version the changelog does not mention.

Adopting it would have meant teaching make-app.sh, the tag guard and the changelog guard to strip the suffix, to make a distinction the build number already makes. Criterion 2 does not apply.
---
<!-- COMMENTS:END -->
