---
id: TASK-1
title: Unblock the 1.0.0 App Store submission
status: Done
assignee: []
created_date: '2026-08-09 18:50'
updated_date: '2026-08-22 03:27'
labels:
  - store
dependencies: []
priority: high
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
1.0.0 (build 49) has sat in review for a week. Before chasing Apple, confirm nothing on our side is holding it.

The EU trader status banner in App Store Connect says trader status is required to submit new apps for EU distribution; it is set under Business by the Account Holder only, and it was never confirmed done. A submission missing it can sit rather than fail loudly.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 EU trader status is confirmed provided, or confirmed not required
- [ ] #2 The version shows build 49 attached and a state of Waiting for Review or later
- [ ] #3 Review notes contain the test account credentials and the demo-mode pointer
- [ ] #4 If everything on our side is clean and it is still queued, contact App Review
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-08-22 03:27
---
Closed: 1.0.0 was approved by App Review. Whatever was holding it — EU trader status or simply queue time — resolved without further action on our side, so the acceptance criteria are moot rather than met. Recording that distinction so nobody later reads this as evidence that the trader-status theory was confirmed.
---
<!-- COMMENTS:END -->
