---
id: TASK-39
title: 'Decision: never unsubscribe from everything automatically'
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
Recurring idea: a one-button clean-my-inbox that unsubscribes from everything, or everything not on an allowlist.

Rejected. It is irreversible in aggregate — requests go straight to senders and cannot be recalled — and, more seriously, unsubscribing from real spam confirms the address is live. A bulk run over an unfiltered mailbox actively makes things worse for exactly the senders the user most wants gone. See TASK-30, which is the opposite instinct.

Smart selections (TASK-26) are the acceptable version: the app proposes, the user reviews and confirms.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Any bulk feature keeps a review step; nothing acts on its own
<!-- AC:END -->
