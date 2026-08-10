---
id: TASK-37
title: 'Decision: no cloud sync of unsubscribe history'
status: Wont Do
assignee: []
created_date: '2026-08-10 01:56'
labels:
  - product
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Recurring idea: sync unsubscribe history, ignored senders and grouping corrections across machines.

Rejected. The moment there is a server, "no server, no account, no telemetry" stops being true, and that claim is the product — it is the first thing the site says, the reason the privacy policy is short, and the answer to "why not just use Unroll.me".

If multi-machine becomes pressing, the honest routes are a manual export/import file the user moves themselves, or CloudKit private database, which keeps the data under the user's own account rather than the developer's.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Revisit only with a design where the developer can never see the data
<!-- AC:END -->
