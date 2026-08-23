---
id: TASK-54
title: Replace runAsync's blocking semaphore with async tests
status: To Do
assignee: []
created_date: '2026-08-23 03:43'
labels:
  - tests
  - concurrency
dependencies: []
priority: medium
type: chore
ordinal: 20000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`runAsync` (Tests/NevermoreTests/TestSupport.swift) bridges a sync test body into async work by blocking on a `DispatchSemaphore`. That was harmless when the harness ran every test sequentially. Under swift-testing it is a thread-starvation deadlock: each blocked call holds a cooperative-pool thread while waiting on a Task that needs that same pool, so two or more concurrent calls can wedge the whole run.

This is not theoretical. Removing `.serialized` from `NetworkBound` during TASK-19 hung the suite indefinitely; a `sample` of the stuck process showed two `Local server lifecycle` tests both parked in `runAsync` -> `_dispatch_semaphore_wait_slow`, with no port error involved.

TASK-19 contained it rather than fixed it: all 26 `runAsync` call sites are inside the `NetworkBound` parent suite, and `.serialized` means only one can block at a time, so progress is guaranteed. The suite has run green repeatedly on that basis.

The containment is load-bearing and undocumented in the type system. Anyone adding a `runAsync` call to a suite outside `NetworkBound`, or removing the trait, reintroduces the deadlock — and it presents as a hang with no failing test, which is the worst possible signal.

The fix is to make the affected tests `@Test ... async` and `await` directly, deleting `runAsync` and `ResultBox`. swift-testing supports async tests natively; the semaphore bridge exists only because the old harness could not. Once nothing blocks a pool thread, `.serialized` on `NetworkBound` is needed only for the real port contention it was nominally added for.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 runAsync and ResultBox are gone from the test target
- [ ] #2 Every test that used them is an async @Test awaiting directly, asserting what it asserted before
- [ ] #3 The suite passes with .serialized removed from NetworkBound, proving the deadlock is gone rather than still contained
- [ ] #4 Whether .serialized is then still needed for port contention is decided and recorded, not left implicit
- [ ] #5 Test count is still 434 (or any change is accounted for case by case)
<!-- AC:END -->
