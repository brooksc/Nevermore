---
id: TASK-49
title: Removing an account leaves its write-ahead log behind
status: To Do
assignee: []
created_date: '2026-08-21 01:13'
updated_date: '2026-08-21 01:14'
labels:
  - store
  - privacy
dependencies: []
references:
  - Packages/NevermoreKit/Sources/NevermoreKit/Credentials/AccountRegistry.swift
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
- [ ] #1 Removing an account deletes its -wal and -shm files along with the database
- [ ] #2 A test asserts no files matching the account's database prefix remain after removal
- [ ] #3 Any other path that deletes a database by name is checked for the same omission
<!-- AC:END -->
