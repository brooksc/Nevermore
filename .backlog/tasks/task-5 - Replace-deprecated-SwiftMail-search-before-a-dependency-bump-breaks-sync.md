---
id: TASK-5
title: Replace deprecated SwiftMail search before a dependency bump breaks sync
status: In Progress
assignee: []
created_date: '2026-08-09 18:51'
updated_date: '2026-08-22 22:30'
labels:
  - tech-debt
dependencies: []
modified_files:
  - Packages/NevermoreKit/Sources/NevermoreKit/Backend/IMAPBackend.swift
  - Packages/NevermoreKit/Tests/NevermoreTests/main.swift
  - Packages/NevermoreKit/Package.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A clean build emits four warnings for search(identifierSet:criteria:calendar:), deprecated in favour of extendedSearch(...) for structured results or search(..., sortCriteria:) for ordered ones.

This is on the sync path, and SwiftMail is pinned to an exact revision precisely because it moves fast. The next time that pin is raised, a deprecation can become a removal and sync stops working.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Calls migrated to the replacement API
- [x] #2 No deprecation warnings from SwiftMail in a clean build
- [ ] #3 Full sync and incremental sync verified against a real mailbox
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Branch `task-5-fix`, commit f049ab7 (single commit, not merged). Branch base is
2446c1a, before main reached 375 tests.

Both deprecated `server.search(criteria:)` calls in IMAPBackend.swift migrated to
`server.extendedSearch(criteria:)`:
- `searchWindow(_:on:depth:)` — the discovery/incremental sync path
- `untrash(messageIDs:)` — Message-ID lookup in Trash

No `server.search(` remains anywhere in the repo.

The one semantic difference between the APIs: `ExtendedSearchResult.all` is `nil`
when nothing matched (ESEARCH omits the ALL datum; the plain-SEARCH fallback nils
out an empty set), where the deprecated call returned an empty set.
`IMAPBackend.matched(_:)` collapses nil to empty in one place. It is `public`
following the `NevermoreServer.listenerParameters()` precedent, so a test can pin
it — it is the only public signature in NevermoreKit naming a SwiftMail type, and
the doc comment says why.

Query strategy deliberately unchanged: 23 one-year windows, newest first, adaptive
halving, `.since(lastSync - 2 days)` for incremental. ESEARCH returns matches as
compacted ranges, which makes swift-nio-imap's 8 KB frame limit much harder to hit,
but SwiftMail still falls back to plain SEARCH on servers without ESEARCH and the
60s timeout is identical, so nothing was relaxed.

AC #1 — done. Verified by diff and a clean build.

AC #2 — done. Forced recompile of NevermoreKit before the change: 2 SwiftMail
deprecation warnings, at IMAPBackend.swift:228 and :434. After: `grep -c deprecated`
over the full build log returns 0. (Task description says "four"; this toolchain
emits two, one per call site.) Remaining build warnings are pre-existing and all in
Tests/NevermoreTests/main.swift.

AC #3 — NOT verified, and nothing here moves it. No live mailbox and no credentials
on this branch; `nevermore-probe` was not run. Unverified specifically:
`extendedSearch` against any real IMAP server, the ESEARCH-capable path, the
non-ESEARCH plain-SEARCH fallback path, and whether the 8 KB frame-limit behaviour
is actually any different in practice. The new tests pin result *interpretation*
only — they do not touch a socket. Nobody has run this code against an IMAP server.

Tests: 369 passed, 0 failed on this branch (367 at the branch base, plus 2 new).
New suite `IMAPBackend.matched`, appended at the end of the harness:
- a result with no ALL datum is no matches, not a failure
- a populated result round-trips its UIDs unchanged
Mutation-checked: rebuilding with `result.all!` in place of `result.all ?? UIDSet()`
kills the suite on the first case, so the pin is real and not vacuous.

Package.swift: NevermoreTests now declares SwiftMail explicitly rather than relying
on it being importable transitively through NevermoreKit.

Design note for a separate decision: `extendedSearch` also exposes `count`, `min`,
`max` and a `partialRange`. PARTIAL (RFC 5267) would be a real alternative to
date-window halving on ESEARCH servers, and `max` could give incremental sync the
UID ceiling `SearchCriteria.uid(N)` cannot express — which is the reason the
two-day date overlap exists. Both are strategy changes, not part of this migration.
<!-- SECTION:NOTES:END -->
