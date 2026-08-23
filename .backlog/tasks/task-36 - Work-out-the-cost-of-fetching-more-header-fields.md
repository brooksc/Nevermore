---
id: TASK-36
title: Work out the cost of fetching more header fields
status: To Do
assignee: []
created_date: '2026-08-10 01:48'
updated_date: '2026-08-23 20:40'
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

author: claude
created: 2026-08-23 20:28
---
Narrower than written. Message size is not part of this question.

Found while implementing TASK-29 and verified independently: `IMAPBackend.fetch` passes `options: .slim`, and SwiftMail defines `.slim` as `[.envelope, .internalDate, .flags, .size]`. So `RFC822.SIZE` already crosses the wire on every sync and is already parsed into `MessageInfo.size` — `convert` simply never read it. Surfacing per-sender storage adds no field and does not change the FETCH command at all.

So this task prices `Authentication-Results` (which TASK-30 left behind a switch for exactly this reason) and `List-Post`, and nothing else. Both are genuine header-section additions; size never was.

Worth carrying into the measurement design: the interesting comparison is not "headers versus more headers" but the marginal cost of each named field against the ~95s / ~14,600-UID baseline, since one of the three candidates has turned out to be free.
---

author: task-29-storage
created: 2026-08-23 20:40
---
**`RFC822.SIZE` is off this task's list — there is nothing to measure.**

TASK-29 is Done and did not wait for this measurement, because unlike `Authentication-Results` the field was never absent from the fetch.

`IMAPBackend.fetch` requests `options: .slim`. SwiftMail defines `.slim` as `[.envelope, .internalDate, .flags, .size]` (`FetchMessageInfoOptions.swift:52-54`), `.size` maps to the `RFC822.SIZE` attribute (`FetchCommands.swift:67-68`), and `FetchMessageInfoHandler.swift:192-193` parses it into `MessageInfo.size`. The sync has been asking every server for message sizes all along; `IMAPBackend.convert` just discarded the value. TASK-29 stopped discarding it, and the FETCH command is byte-identical before and after.

So AC #1's per-field cost applies to `Authentication-Results` and `List-Post` only. TASK-29 added no field, and `MessageSizeStorageAndFetchTests` asserts `SyncHeaderFields.attributes == .slim` and `.contains(.size)` so a future narrowing of the attribute set fails loudly rather than silently emptying the Size column.

**AC #2, backfill, for sizes:** decided the same way TASK-30 decided it, and for the same reason. Migrations are forward-only, so a row stored before TASK-29 has nothing to backfill from, and incremental sync re-reads only a two-day overlap — old messages stay sizeless until re-fetched. No full re-sync is forced; the gap closes gradually and is visible in the UI as "Unknown" (never "0 bytes") with a per-sender "at least" on any partial total. Tested that a re-fetch does fill a missing size in. Whether to offer an explicit full re-sync is a product call, not a measurement, and nothing here blocks on it.

**AC #3, migration sketch, for sizes:** already landed as `v7-message-size` — one nullable INTEGER `byteSize` on `message`, upserted with `COALESCE(excluded.byteSize, message.byteSize)` so a fetch that omits a size cannot erase one on file. Nothing left for this task to sketch for this field.

What remains for TASK-36 is unchanged in substance: price `Authentication-Results` (TASK-30's switch is still `false`) and `List-Post`.
---
<!-- COMMENTS:END -->
