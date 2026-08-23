---
id: TASK-9
title: Add a Settings toggle for automatic update checks
status: Done
assignee: []
created_date: '2026-08-09 18:52'
updated_date: '2026-08-23 02:52'
labels:
  - product
dependencies: []
modified_files:
  - Packages/NevermoreKit/Sources/NevermoreApp/Updater.swift
  - Packages/NevermoreKit/Sources/NevermoreApp/Views/SettingsView.swift
  - Packages/NevermoreKit/Tests/NevermoreTests/main.swift
  - PRIVACY.md
  - docs/privacy.html
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Updater.swift wires up SPUStandardUpdaterController with startingUpdater: true and a Help menu item, and nothing else. Sparkle asks once on first launch and there is no way to change the answer afterwards.

The privacy policy had to be written around this — it says the app asks on first run, because promising a toggle that does not exist would be false. A toggle is a small change that makes the privacy claim simpler and gives the user somewhere to look.

Mac App Store builds compile Sparkle out entirely, so the toggle must not appear there.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Settings exposes an automatic update checks toggle, bound to Sparkle
- [x] #2 Toggle absent in the store build, which has no updater
- [x] #3 PRIVACY.md and docs/privacy.html updated to describe the toggle
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
`AutomaticUpdatesSection` lives in Updater.swift beside `CheckForUpdatesButton`: a "Software updates" Section in Settings ▸ General with a toggle plus a caption, and an `EmptyView` stub in the `#else` arm so the store build shows no header for an updater it lacks. SettingsView calls it unconditionally.

Gated on `canImport(Sparkle)`, not `NEVERMORE_MAS`. The two are not interchangeable: NEVERMORE_MAS asks "is this the sandboxed store build", which is right for the local-server section (that feature is in the sources either way and only the sandbox stops it). Here the question is whether an updater exists to switch on, and that is exactly whether Sparkle was linked — the Tuist target declares no Sparkle package, so the toggle drops out with no flag to remember.

The toggle reads/writes `SPUUpdater.automaticallyChecksForUpdates` rather than the `SUEnableAutomaticChecks` user default. Sparkle owns that key, distinguishes "never answered" from "answered no", and reschedules on change.

Verified: `swift build` and `swift build -Xswiftc -DNEVERMORE_MAS` both succeed; `swiftc -typecheck Sources/NevermoreApp/Updater.swift` standalone (no Sparkle search path, so `canImport(Sparkle)` is false — confirmed with a `#error` probe) type-checks the no-Sparkle arm under Swift 6. Tests: 415 passed, 0 failed (413 before, plus two new source-text tests pinning the gate and the two privacy copies).

Not verified: runtime behaviour. The GUI was not launched (shared machine), so "flipping the toggle changes Sparkle's schedule" rests on the binding type-checking, not on observation.

Separate pre-existing problem, not touched: docs/privacy.html is missing the whole "Connecting an AI agent (MCP)" section that PRIVACY.md has, and still says "Last updated: 1 August 2026". The published policy therefore does not disclose the MCP data flow. PRIVACY.md's date was moved to 22 August 2026; the HTML's was deliberately left alone rather than claim currency it does not have.
<!-- SECTION:NOTES:END -->
