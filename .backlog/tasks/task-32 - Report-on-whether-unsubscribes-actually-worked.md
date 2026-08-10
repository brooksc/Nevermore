---
id: TASK-32
title: Report on whether unsubscribes actually worked
status: To Do
assignee: []
created_date: '2026-08-10 01:49'
labels:
  - product
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reappeared reports continuously; it never concludes. A periodic summary would: "You unsubscribed from 8 senders last month. 6 honoured it, 2 did not." That is the app's unique claim stated as a result, and a reason to come back to an app you might otherwise open once and forget.

The data is already there — unsubscribe history with timestamps, and messages received since. It needs a report and a moment to show it, not new plumbing.

Pairs well with the reappearance notification that already exists, which fires per sender and so cannot say anything about the whole.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A summary of unsubscribes and their outcomes over a period
- [ ] #2 Reachable on demand, not only as a notification
- [ ] #3 Counts derived from the same rule the Reappeared collection uses, not a second implementation
<!-- AC:END -->
