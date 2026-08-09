---
id: TASK-1
title: Unblock the 1.0.0 App Store submission
status: To Do
assignee: []
created_date: '2026-08-09 18:50'
labels:
  - store
dependencies: []
priority: high
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
