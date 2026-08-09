---
id: TASK-6
title: Replace deprecated SecKeychainSetUserInteractionAllowed
status: To Do
assignee: []
created_date: '2026-08-09 18:51'
labels:
  - tech-debt
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Keychain.swift:80-81 uses SecKeychainSetUserInteractionAllowed, deprecated since macOS 10.10 along with the whole SecKeychain API. Four warnings per clean build.

It is used to stop a Keychain prompt appearing during a headless read. The modern equivalent is per-item access control on the SecItem call rather than a process-wide toggle. Worth doing while the surrounding code is small enough to reason about — credential handling is the last place to want a surprise API removal.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Process-wide interaction toggle replaced with per-item behaviour
- [ ] #2 No prompt appears during a normal read, including after a rebuild
- [ ] #3 Password still survives app relaunch, sandboxed and not
<!-- AC:END -->
