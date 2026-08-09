---
id: TASK-3
title: Get the age rating down from 18+
status: On Hold
assignee: []
created_date: '2026-08-09 18:50'
updated_date: '2026-08-09 19:00'
labels:
  - store
dependencies: []
priority: high
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The store listing is rated 18+ solely because the age-rating questionnaire was answered honestly for unrestricted web access. WebUnsubscribeSheet.swift:204-219 allows navigation to any public http/https host — the guard only blocks non-http schemes and private, loopback and link-local addresses — so once an unsubscribe page opens, a user can click through to anywhere.

An inbox utility rated 18+ narrows its audience for a capability nobody uses deliberately. Restricting navigation to the unsubscribe target host and its redirect chain would make "no" the honest answer.

Needs testing against real senders first: some unsubscribe flows legitimately redirect across hosts, and breaking those is worse than the rating.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Navigation policy restricted to the initial host and its redirect chain
- [ ] #2 Tested against a sample of real senders, including multi-host flows
- [ ] #3 Age rating questionnaire re-answered and the listing shows 4+
- [ ] #4 App Review notes updated to match
<!-- AC:END -->
