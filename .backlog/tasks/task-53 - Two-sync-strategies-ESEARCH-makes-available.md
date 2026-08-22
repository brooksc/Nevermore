---
id: TASK-53
title: Two sync strategies ESEARCH makes available
status: To Do
assignee: []
created_date: '2026-08-22 22:32'
updated_date: '2026-08-22 22:33'
labels:
  - sync
dependencies:
  - TASK-5
priority: medium
type: spike
ordinal: 19000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Raised by TASK-5's implementer while migrating to `extendedSearch`, and deliberately not acted on there: both are changes to the query strategy, which PLAN.md §4 documents as measured rather than incidental. They belong in their own decision.

**`result.max` could retire the two-day overlap.** Incremental sync searches `.since(lastSync - 2 days)` because `SearchCriteria.uid(N)` encodes a single UID and not an open range, so "newer than N" is not expressible — the overlap absorbs IMAP's day-granularity `SINCE`, and duplicate UIDs collapse on the primary key. `ExtendedSearchResult` carries `max`, which is the UID ceiling that could not be asked for before. If that removes the overlap, every incremental sync stops re-fetching two days of headers it already has.

**`partialRange` (PARTIAL, RFC 5267) is an alternative to date-window halving.** Discovery runs 23 one-year windows with adaptive halving because a single unbounded `SEARCH` exceeds the 60s command timeout and can breach swift-nio-imap's 8 KB frame limit. PARTIAL asks for a slice of the result set directly, which is a different shape of answer to the same problem.

Both are gated on the same question: neither is available on a server that does not advertise the capability, and SwiftMail falls back to plain `SEARCH` there. So either would be a second path to maintain, not a replacement — and the existing windowing has to keep working regardless. That is the cost side, and it is why this is a spike rather than a change.

Worth measuring against the real mailbox before deciding: current full discovery is ~95s for ~14,600 UIDs across 23 windows, and incremental sync is 40-50 new messages in ~3s. If the overlap removal is worth seconds and the PARTIAL work is worth a second code path, the numbers will say so.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 It is established whether result.max can replace the two-day incremental overlap, with the correctness argument written down rather than assumed
- [ ] #2 The cost of a second discovery path using PARTIAL is measured against the existing windowing on a real mailbox
- [ ] #3 A decision is recorded for each, including deciding not to do them
- [ ] #4 Whatever is adopted keeps working on a server that advertises neither capability
<!-- AC:END -->
