---
id: TASK-36
title: Work out the cost of fetching more header fields
status: To Do
assignee: []
created_date: '2026-08-10 01:48'
labels:
  - product
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Several proposed features need fields the app does not fetch: RFC822.SIZE for storage totals (TASK-27 equivalent), Authentication-Results for spam-aware advice, and List-Post or similar for better mailing-list handling.

None of them are free. The fetch currently asks for newsletterHeaderFields plus Delivered-To, To and Message-ID (IMAPBackend.swift:317-318) in bulk chunks, and discovery on a real mailbox already takes about 95 seconds with a 40-second header fetch. Every added field costs bandwidth on every message, and the store needs new columns plus a migration — and migrations here are forward-only by policy.

The question to answer before committing to any of those features: what does each extra field cost in fetch time on a 12,000-message mailbox, and can existing caches be backfilled incrementally rather than forcing a full re-sync.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Measured fetch-time cost per added field against the real mailbox
- [ ] #2 Decision on whether backfill can be incremental or needs a full re-sync
- [ ] #3 Migration sketch for the new columns, respecting the forward-only rule
- [ ] #4 Findings written into PLAN.md so the dependent tasks can be sized
<!-- AC:END -->
