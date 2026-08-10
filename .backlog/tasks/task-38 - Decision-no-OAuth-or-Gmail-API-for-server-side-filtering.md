---
id: TASK-38
title: 'Decision: no OAuth or Gmail API for server-side filtering'
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
Recurring idea: use the Gmail API to create filters, apply labels or block senders outright — which would do what unsubscribing cannot, since it needs no cooperation from the sender.

Rejected for now, and it is a genuine trade rather than an obvious call. It needs a cloud project, a client secret shipped inside a downloadable app, and a broad consent screen. Then the app is Gmail-first rather than any-IMAP, and the app-password story that makes it provider-agnostic is gone.

The app already has an answer for senders that will not stop: trash and ignore. Weaker, but it works everywhere and asks nothing of anyone.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Revisit only if provider-agnostic design and the app-password path both survive
<!-- AC:END -->
