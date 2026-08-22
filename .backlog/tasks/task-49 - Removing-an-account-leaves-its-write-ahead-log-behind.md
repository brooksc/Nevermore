---
id: TASK-49
title: Removing an account leaves its write-ahead log behind
status: Done
assignee: []
created_date: '2026-08-21 01:13'
updated_date: '2026-08-22 03:37'
labels:
  - store
  - privacy
dependencies: []
references:
  - Packages/NevermoreKit/Sources/NevermoreKit/Credentials/AccountRegistry.swift
modified_files:
  - Packages/NevermoreKit/Sources/NevermoreKit/Credentials/AccountRegistry.swift
  - Packages/NevermoreKit/Tests/NevermoreTests/main.swift
priority: medium
type: bug
ordinal: 15000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`AccountRegistry.remove(_:)` deletes `<account>.sqlite` but not its `-wal` and `-shm` siblings. `resetAllLocalData()`, a few lines above it, correctly removes all three — so the two paths disagree about what "remove this account's data" means, and the narrower one is the one a user reaches by removing an account in Settings.

SQLite in WAL mode holds recently written rows in the `-wal` file until a checkpoint, so removing an account can leave the most recent writes on disk after the app has said the account is gone. That now includes agent decision records (TASK-43), whose `reason` field is free text an external agent wrote about the user's own circumstances — "only worth it while I'm job hunting". Those outliving the mailbox they describe is a small privacy leak rather than a feature.

Found twice independently while reviewing TASK-43: once by the implementing agent, once during integration review. Deliberately not fixed there, because it is pre-existing and touches shared code.

The fix is small. The value is in also deciding whether anything else in the app deletes a database by path and makes the same assumption.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Removing an account deletes its -wal and -shm files along with the database
- [x] #2 A test asserts no files matching the account's database prefix remain after removal
- [x] #3 Any other path that deletes a database by name is checked for the same omission
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Survey every path that deletes a database by name (AC#3) — grep for `removeItem`, `-wal`/`-shm`, `.sqlite`, `databasePath` across all Swift sources.
2. Replace the three hand-written suffix lists in `AccountRegistry` with one helper that sweeps the database's directory for every file whose name starts with `<database>.sqlite`, so the paths cannot drift apart again and so files with suffixes nobody listed are also caught.
3. Add a test suite (appended at the very end of `Tests/NevermoreTests/main.swift`) asserting that after `remove(_:)` no file matching the account's database prefix survives, and that a sibling account's files are untouched. Temp directory only — never the real Application Support.
4. Verify: `swift build`, then `swift run nevermore-tests` — 309 existing tests still pass plus the new ones.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Survey for AC#3 found a second, larger instance of the same assumption, in addition to the `-wal`/`-shm` omission the task describes.

`MessageStore.backUpIfMigrationPending` (Store/MessageStore.swift:31) copies the database aside as `<account>.sqlite.pre-<migration>.bak` before running a new migration. Nothing ever deletes that copy — not `remove(_:)`, not `resetAllLocalData()`, not `resetDemoDatabase()`. It is a whole prior copy of the account's database, agent decision `reason` text included, and it outlives account removal completely. Strictly worse than the WAL leak this task was filed for, and invisible to a fix that only adds two more suffixes to a list.

Checked and cleared: `MCPTokenManager` (Server/MCPTokenManager.swift) deletes `~/.nevermore-mcp-token`, not a database — no siblings exist. `Sources/Probe/main.swift` builds its own database path but never deletes one.

That is the argument for sweeping by prefix rather than by a list of known suffixes: the list was already incomplete, and would have stayed incomplete.

Fixed by replacing all three hand-written suffix lists in `AccountRegistry` with one private `removeDatabase(atPath:)` that lists the database's directory and deletes every entry whose filename starts with `<account>.sqlite`. `remove(_:)`, `resetAllLocalData()`, and `resetDemoDatabase()` all go through it, so they can no longer disagree, and the `.pre-<migration>.bak` copy is now cleaned up by all three.

Prefix matching is safe against neighbouring accounts because the prefix includes the `.sqlite` extension: removing `tester@example.com` cannot match `tester@example.com.au.sqlite`. There is a test for exactly that.

Verification: `swift build` clean under `.swiftLanguageMode(.v6)`; `swift run nevermore-tests` reports **312 passed, 0 failed** (309 before, 3 new). The three new tests were also run against the un-fixed `AccountRegistry` and all three failed there, naming the leftover `-wal`, `-shm`, and `.pre-v9.bak` files — so they test the defect rather than passing vacuously.

The tests write siblings by hand into a fresh temp directory rather than relying on a live store leaving a `-wal` behind; whether SQLite has checkpointed at a given instant is exactly the timing this must not depend on. They never touch Application Support. `remove(_:)` does call `Keychain.delete`, which issues a `SecItemDelete` for `tester@example.com` / `tester@example.com.au` under the app's service — no such item exists, it is silent, and neither address is a real mailbox.
<!-- SECTION:NOTES:END -->
