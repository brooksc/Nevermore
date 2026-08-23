---
id: TASK-54
title: Replace runAsync's blocking semaphore with async tests
status: Done
assignee: []
created_date: '2026-08-23 03:43'
updated_date: '2026-08-23 20:20'
labels:
  - tests
  - concurrency
dependencies: []
modified_files:
  - Packages/NevermoreKit/Tests/NevermoreTests/TestSupport.swift
  - Packages/NevermoreKit/Tests/NevermoreTests/Suites.swift
  - CLAUDE.md
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
- [x] #1 runAsync and ResultBox are gone from the test target
- [x] #2 Every test that used them is an async @Test awaiting directly, asserting what it asserted before
- [ ] #3 The suite passes with .serialized removed from NetworkBound, proving the deadlock is gone rather than still contained
- [x] #4 Whether .serialized is then still needed for port contention is decided and recorded, not left implicit
- [x] #5 Test count is still 479 (or any change is accounted for case by case)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
`runAsync` and `ResultBox` are gone. The 26 call sites became `async @Test`s
awaiting directly; the helpers they went through (`send`, `route`, `serve`,
`withScratchToken`, `withScratchTokenPath`) are `async` too. Two `defer { runAsync
{ await controller.stop() } }` blocks became explicit `await controller.stop()`
on every path, since `defer` cannot await. `ResultBox` had two non-`runAsync`
uses: one was dead (a `box.value` written and never read) and one captured the
mailto fallback's recipient, now a small `MailtoRecorder` actor — an actor rather
than a locked box because `MailSender` is already `async`.

Removing `.serialized` then exposed a second instance of the same bug that the
first one had been masking. `StubHTTPServer.init`, `holdPort` and
`HeldPort.release` each waited on a `DispatchSemaphore` for an `NWListener` to
change state. Called from an `async` test body that is a cooperative-pool thread,
and with 14 network tests suddenly running at once, enough threads were parked
that the listeners could not reach `.ready` inside their own 3s timeout: 13 tests
failed with "could not start stub origin". Not a hang this time, but the same
mechanism. Those three are now `async` and wait through a new `AsyncGate`
(continuation + `asyncAfter` timeout, resumed once) instead of a semaphore. No
`DispatchSemaphore` remains anywhere in the test target.

AC #4 — `.serialized` stays, and now buys only what it always claimed to. The
port contention is real: `fails closed when every contract port is taken` and `a
bind failure is reported with the port range` each occupy all five of 8775-8779
for their duration, while `starting binds a contract port`, `stopping releases
the port` and `the local server hands the context on` each bind one of those same
five. In parallel they take each other's ports. Reasoned from the code rather
than measured, because this machine's running Nevermore holds 8775, which makes
the two "occupy all five" tests bail at their setup guard before they can
contend — so an unserialized run here cannot exhibit the clash either way. The
trait is restored with a comment saying this, so the next person does not have to
rediscover which of the two reasons it exists for.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-08-23 17:05
---
Criterion 5 said 434 when filed. That was the count at TASK-19's branch point; the rebase brought TASK-30's 45 tests across and main is at 479. Corrected so nobody reconciles against the wrong baseline.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Test count unchanged: 479 tests in 83 suites, before and after.

AC #3 is left unchecked, deliberately. The deadlock it was written to catch is
gone: with `.serialized` removed the suite ran to completion three consecutive
times in ~4.3s (against ~21.7s serialized) with no hang, which is how TASK-19
found the hang in the first place. But the criterion says *passes*, and the run
is not clean — three tests fail with "could not occupy" because the maintainer's
Nevermore is listening on 8775 (`lsof -nP -iTCP:8775-8779`, pid 69627). Those
same three fail identically with `.serialized` on, so they are the environment
and not this change; they are the only tests in the suite not verified green
here. Ticking #3 needs one unserialized run with 8775 free, and per the AC #4
reasoning that run is expected to surface genuine port contention instead —
at which point the honest resolution is to reword #3, not to tick it.
<!-- SECTION:FINAL_SUMMARY:END -->
