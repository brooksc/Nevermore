---
id: TASK-33
title: 'Suggest burning an alias instead of unsubscribing, where one applies'
status: To Do
assignee: []
created_date: '2026-08-10 01:49'
labels:
  - product
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The app already infers send-as aliases from Delivered-To. For anyone using iCloud+ Hide My Email, Fastmail aliases or a catch-all domain, the strongest move is often not unsubscribing at all: kill the alias and every sender using it stops at once, with no cooperation required from any of them.

The app can see which alias each sender uses and how many senders share it. "17 senders mail shop@yourdomain — disabling that alias stops all of them" is advice no unsubscribe tool gives, and it costs no new data.

It cannot disable the alias itself; that lives in the provider. Deep link and explain.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Per-alias grouping shown, with sender counts
- [ ] #2 Suggestion appears only where an alias plausibly exists
- [ ] #3 Links to the provider where the alias is managed
<!-- AC:END -->
