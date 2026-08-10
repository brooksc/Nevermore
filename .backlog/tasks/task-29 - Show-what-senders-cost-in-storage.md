---
id: TASK-29
title: Show what senders cost in storage
status: To Do
assignee: []
created_date: '2026-08-10 01:49'
labels:
  - product
dependencies:
  - TASK-28
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Tidiness is a weak motivator; a full mailbox is a strong one. Gmail's free tier is 15 GB shared with Drive and Photos, and image-heavy newsletters are a real part of what fills it. "These 12 senders are using 3.1 GB" is a better reason to open the app than "you have 40 newsletters".

It fits the premise exactly: RFC822.SIZE is message metadata, not content. Reading it says nothing about what a message contains, so headers-only still holds.

Work: fetch size alongside the existing header fields, store it, aggregate per sender, offer sort-by-size. The obvious follow-through — trashing the biggest senders — is then one keystroke away.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Message size fetched and stored
- [ ] #2 Per-sender totals shown and sortable
- [ ] #3 Existing caches backfill without forcing a full re-sync, or the cost is stated plainly
- [ ] #4 Sizes never presented as more precise than the server reports
<!-- AC:END -->
