---
id: TASK-7
title: Measure the gap between messages located and messages stored
status: To Do
assignee: []
created_date: '2026-08-09 18:51'
labels:
  - product
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Discovery consistently finds more UIDs than the store keeps, and the split has never been measured. The expected causes are the user's own sent mail and headers whose only unsubscribe target uses an unsupported scheme, but that is a guess.

It matters because the UI shows both numbers, and today nobody can explain the difference to a user who notices. Recorded as open in PLAN.md section 10.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Sync logs a breakdown of why located messages were not stored
- [ ] #2 Measured once against the real mailbox and the split written into PLAN.md
- [ ] #3 If a category is unexpectedly large, a follow-up task is filed
<!-- AC:END -->
