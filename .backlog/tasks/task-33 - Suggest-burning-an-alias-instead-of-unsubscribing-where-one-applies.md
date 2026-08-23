---
id: TASK-33
title: 'Suggest burning an alias instead of unsubscribing, where one applies'
status: On Hold
assignee: []
created_date: '2026-08-10 01:49'
updated_date: '2026-08-23 03:15'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-08-23 03:15
---
Parked. The idea is sound and costs no new data — Delivered-To is already stored per message, so grouping senders by the alias they arrived on is presentation over what is on disk. It is also the one instrument in the app that needs no cooperation from the sender: burning an alias cannot be ignored the way an unsubscribe can.

Held because its value is unknown until built. It only pays off if several senders cluster on one burnable alias, and PLAN.md records five send-as addresses inferred from the maintainer's mailbox without saying how the senders distribute across them. It could be a feature that fires twice and then stays quiet. Worth revisiting once TASK-7's instrumentation makes that distribution visible, which would answer the question without building the feature to find out.
---
<!-- COMMENTS:END -->
