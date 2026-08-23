---
id: TASK-19
title: Convert the test harness to swift-testing
status: Done
assignee: []
created_date: '2026-08-09 18:53'
updated_date: '2026-08-23 03:54'
labels:
  - tests
dependencies: []
modified_files:
  - Packages/NevermoreKit/Package.swift
  - Packages/NevermoreKit/Tests/NevermoreTests/Suites.swift
  - Packages/NevermoreKit/Tests/NevermoreTests/TestSupport.swift
  - Packages/NevermoreKit/Sources/NevermoreKit/TestHarness.swift
  - Packages/NevermoreKit/Sources/NevermoreKit/Server/NevermoreServer.swift
  - Packages/NevermoreKit/Sources/NevermoreKit/Backend/IMAPBackend.swift
  - .github/workflows/tests.yml
  - CLAUDE.md
  - README.md
  - RELEASE.md
  - PLAN.md
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Tests run as an executable with a hand-rolled harness because SwiftPM builds test targets as .xctest bundles, which needs a full Xcode rather than Command Line Tools. That constraint is gone: the Mac App Store build already requires Xcode, and CI has it.

Raised as an open question in both PLAN.md and RELEASE.md. 110 tests to move, so worth doing before the suite grows further.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Suite runs under swift-testing
- [x] #2 CI runs the tests as part of the Release MAS workflow or a separate one
- [x] #3 All 110 assertions still present, none quietly dropped
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Done on branch `task-19-fix` (commit c12c4b2). The suite runs under swift-testing in a real `.testTarget`: `swift test`, 434 tests in 77 suites, 12.5s.

**The stated constraint no longer holds, and had already lapsed.** The harness existed because `.xctest` bundles need XCTest/`_TestingInterop` from a full Xcode, and `swift run nevermore-tests` was meant to work anywhere `swift build` did. But `NevermoreApp` needs the macOS SDK, so the package never built on Command Line Tools alone regardless. Checked rather than assumed: a throwaway package with a `.testTarget` builds and runs on this toolchain, with `@testable` reaching internals and tests running in parallel.

**Count reconciles exactly.** 434 before, 434 after, and the same 434 — the test-name and suite-name multisets from both runs are identical (no missing, no new). The baseline breaks down as 393 direct `Harness.test` call sites plus 41 `asyncTest` ones, which is the total exactly.

**Assertions are unchanged, not just re-counted.** `expect`/`eq` were kept and now forward to `Issue.record` instead of the harness, rather than rewriting ~1900 assertions into bare `#expect`. A multiset diff of every non-scaffolding line across old and new shows no assertion line added or removed — every difference is scaffolding, imports, comments, or the three structural fixes below. The cost is losing `#expect`'s expression capture, which `eq` never had.

**Structural edits, all forced by Swift rules, none semantic:** chained `let`s inside a suite closure are legal but chained property initialisers are not, so `Demo unsubscribe history` gained an `init()`, and `Selection cursor` / `Selection across collections` spell out the list their `ids()` helper used to build.

**API surface recovered (the actual point).** `NevermoreServer.listenerParameters()` and `IMAPBackend.matched(_:)` are internal again — the latter was the only public signature in the kit naming a SwiftMail type. `Harness` was public API in the shipping library and is deleted.

**Ports, and a worse problem underneath.** The 11 socket/port suites are nested under one `@Suite(.serialized)`. That was meant to stop contention on 8775-8779, but it turns out to be load-bearing for a different reason: `runAsync` blocks a cooperative-pool thread, so two concurrent calls starve the pool and **hang** the run with nothing reported. Removing the trait hung the suite; a `sample` of the stuck process showed two `Local server lifecycle` tests parked in the semaphore, no port error involved. All 26 `runAsync` callers are inside `NetworkBound`, so serialisation contains it — but that is a comment and a backlog task, not a type-system guarantee. Raised as TASK-54, and flagged loudly in both `TestSupport.swift` and `CLAUDE.md`. Pre-existing behaviour is otherwise unchanged: these suites still fail if the app itself holds a port.

**AC#2:** added `.github/workflows/tests.yml` running `swift test` on push to main, PRs, and dispatch. Nothing ran the tests in CI before. Assumption worth confirming: this spends macOS-runner minutes, which `release-mas.yml` is explicitly manual to conserve; the workflow comment says to drop the `push` trigger first if minutes get tight. **Not verified** — it has not run on GitHub, only locally.

Verified: `swift build` clean across all targets; `swift test` green on four consecutive runs (12.4-12.6s), no flakiness observed.

## Rebased onto main (34fa453), TASK-30 converted

Rebased; branch is now a single commit `0e532de` on top of `34fa453`. TASK-30 merged 45 tests in 6 suites while this was in flight, so the target moved 434 -> 479.

Git followed the rename and tried to reconcile the 524-line append against the rewrite, exactly as feared. Resolved deterministically rather than by hand-merging: the conflict was one hunk containing precisely TASK-30's block, so the converted file was taken whole and the block converted separately with the same transform.

**479 before, 479 after, name-for-name.** Reconciled against a real harness run at the branch point (434 names) plus the 45 names extracted from TASK-30's block — all 45 call sites are canonical one-line forms, verified, none multi-line. Zero missing, zero unexpected, on both test names and suite names. 83 suites reported = 82 real + the `NetworkBound` parent.

**TASK-30's tests needed no edits at all.** A multiset diff of every non-scaffolding line between the original block and the converted version is empty in both directions — every assertion, helper, and comment is byte-identical. Only the `Harness.suite`/`Harness.test` scaffolding changed. The four suite-level `let`s were self-contained, so unlike three suites in the first pass, none needed an `init()`.

`SenderTrust`, `AuthenticationResults` and `SenderTrust.recommendation(given:)` are covered exactly as merged.

## Port-binding suites: what was actually done

The 11 socket/port suites are nested under one `@Suite(.serialized)`, which is recursive over descendants (verified in a spike: interleaved children never overlapped).

**Contention between the port suites within one run: fixed.** They cannot race each other now.

**Contention with an outside holder (the app, or another agent): unchanged, and verified.** Holding 127.0.0.1:8775 from a separate process and running the suite fails 3 named tests in ~21s with legible messages ("could not occupy 8775 to set up the test", "could not occupy all 5 ports") — no hang, no cascade. Same failure mode as the harness.

**One thing that got mildly worse.** `NetworkBound` now spans essentially the whole run (12.53s of a 12.53s run), where the harness confined the port block to a contiguous stretch of a longer sequential run. The absolute port-holding window is about the same — it is dominated by real socket timeouts, not scheduling — but it now overlaps the entire run rather than one slice. Two concurrent runs are therefore no more likely to collide than before, but the window in which a second run *could* collide is a larger fraction of a shorter run. Net: better within a run, unchanged across processes, slightly worse in overlap fraction.

**Diagnostics check.** An earlier read of the port-failure output suggested messages were being lost (headline reads a generic "Issue recorded"). They are not: the text lands on the `↳` detail line, confirmed both in a spike and in the real port-held run. `eq`'s expected/got is preserved the same way. The only genuine loss remains `#expect`'s decomposed expression, which neither helper ever had.
<!-- SECTION:FINAL_SUMMARY:END -->
