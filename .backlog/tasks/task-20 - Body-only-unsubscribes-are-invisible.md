---
id: TASK-20
title: Body-only unsubscribes are invisible
status: On Hold
assignee: []
created_date: '2026-08-09 18:53'
labels:
  - product
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The app finds newsletters by the List-Unsubscribe header, so a sender who only puts an unsubscribe link in the message body is never seen. Trash this sender therefore means the subset carrying the header, which is not what the words say.

On hold rather than open: closing it means either reading message bodies, which the app's whole premise forbids, or a sender-wide SEARCH FROM delete that removes mail the app never showed the user. Both are worse than the gap. Recorded here so the decision is findable, and so the FAQ keeps saying it plainly.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Revisit only if a way exists that reads no bodies and deletes nothing unshown
<!-- AC:END -->
