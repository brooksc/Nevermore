---
id: TASK-31
title: Tell people what a sender will cost them next year
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
The app knows first seen, last received and message count, so it can say what a subscription costs going forward: "about 156 more a year at this rate". A forecast argues for the unsubscribe better than a backlog count does, because the backlog is sunk and the forecast is not.

Same data supports a trend — a sender that has gone from monthly to twice weekly is worth surfacing, and is exactly the kind of drift nobody notices from the inbox.

No new fetching: this is arithmetic over what is already stored.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Per-sender forecast shown in the inspector
- [ ] #2 Cadence changes surfaced where they are material
- [ ] #3 Wording stays honest about it being an estimate from past rate
<!-- AC:END -->
