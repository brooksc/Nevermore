---
id: TASK-36
title: Work out the cost of fetching more header fields
status: To Do
assignee: []
created_date: '2026-08-10 01:48'
updated_date: '2026-08-23 03:33'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: task-30-spammer
created: 2026-08-23 03:33
---
TASK-30 is built around this measurement rather than ahead of it. Everything downstream of the fetch for `Authentication-Results` now exists and is tested — RFC 8601 parser, the `authResults` column (migration `v6-authentication-results`), the per-sender roll-up, the recommendation change and the copy. What is missing is only the fetch.

**Turning it on is one line:** `SyncHeaderFields.fetchesAuthenticationResults = true` in `Packages/NevermoreKit/Sources/NevermoreKit/Backend/SyncHeaderFields.swift`. `IMAPBackend.fetch` already appends `SyncHeaderFields.optional` to its header-field list, and a harness test asserts the switch is off so nobody mistakes a green suite for a shipped fetch.

Three things this task should measure or decide that TASK-30 could not:

1. **Cost.** `Authentication-Results` is by far the largest header in this set — Gmail writes 200–400 bytes per message, several times `Message-ID` or `List-ID`. On ~14,700 stored messages that is roughly 3–6 MB of extra header traffic, but the fetch cost that matters is per-message parse and round-trip, not total bytes, and nobody has measured it.

2. **Backfill.** TASK-30 chose the incremental answer already, and it needs confirming rather than deciding: the upsert writes `authResults = COALESCE(excluded.authResults, message.authResults)` rather than last-write-wins, precisely so a sync with the switch off cannot erase verdicts a sync with it on had collected. That makes a partial backfill safe and a full re-sync unnecessary — but it also means messages synced before the flip stay blank until they are re-fetched, so TASK-30's verdict will be silent on a sender's older mail. Whether that matters is a product call for this task.

3. **The column already landed**, empty and nullable, in the same migration series. AC #3's migration sketch is done for this field; anything TASK-36 adds for `RFC822.SIZE` or `List-Post` is separate.

No other TASK-30 behaviour waits on this: the checks that need no new fetch (unsubscribe link behind a shortener, at a bare IP, or addressed to a consumer mailbox; and the sender-versus-target domain mismatch) are live now.
---
<!-- COMMENTS:END -->
