# Nevermore

Native macOS app (Swift 6 / SwiftUI) that syncs the *headers* of every message
carrying a `List-Unsubscribe` header over IMAP, groups them by sender, and
bulk-unsubscribes or trashes whole senders. No message bodies are ever
downloaded, and nothing leaves the Mac except the unsubscribe request itself.
Two distribution channels: a notarized DMG with Sparkle updates, and the Mac
App Store.

## Build, test, run

Everything runs from `Packages/NevermoreKit` — the repo root holds only the
Tuist manifest for the App Store target.

```bash
./run                             # build (debug, host arch) and launch the app
cd Packages/NevermoreKit
swift build                       # build everything
swift run nevermore-tests         # the test suite — 117 tests as of 1.0.0
swift run nevermore-probe         # CLI harness against a real mailbox, no UI
./make-app.sh release             # signed Nevermore.app
./make-dmg.sh --notarize          # notarized, stapled DMG
```

`./run` launches a GUI app on a machine shared with the user — ask before
running it.

**Tests are an executable, not a `.testTarget`.** `swift test` is useless here.
SwiftPM builds test targets as `.xctest` bundles needing XCTest from a full
Xcode; the harness in `Tests/NevermoreTests/main.swift` runs anywhere
`swift build` does. Add cases with `Harness.suite("…") { Harness.test("…") { … } }`
and the `expect` / `eq` helpers at the top of that file. Converting to
swift-testing is TASK-19.

**Xcode is required** for `NevermoreApp` — Command Line Tools alone cannot
build it. `swift build` fails unless `DEVELOPER_DIR` points at Xcode.

All targets compile under `.swiftLanguageMode(.v6)`; strict concurrency is not
optional.

## Layout

- `Packages/NevermoreKit/Sources/NevermoreKit` — the engine, no UI:
  `Backend` (IMAP + the `MailBackend` protocol), `Store` (GRDB),
  `Domain` (grouping, `List-Unsubscribe` parsing, MIME headers),
  `Unsubscribe` (engine + `DestinationGuard`), `Credentials` (Keychain),
  `Demo` (a fabricated mailbox on `MailBackend` with no network code —
  it is also what an App Review reviewer uses)
- `…/Sources/NevermoreApp` — SwiftUI app: `Views`, `Model/AppModel.swift`,
  `Commands.swift`, `Updater.swift`
- `…/Sources/Probe` — CLI used to verify sync behaviour against a real mailbox
- `Project.swift` + `.mise.toml` — Tuist (pinned 4.203.1) generates the Mac App
  Store target
- `.github/workflows/release-mas.yml` — the only way to produce a
  store-acceptable build (see below)

## Release rules

- `Packages/NevermoreKit/VERSION` is the single source of the marketing
  version. `Project.swift` reads it and `fatalError`s if it is missing.
- The build number is the **commit count**, so a shallow clone breaks it — CI
  checks out with `fetch-depth: 0`.
- Releasing requires a `## [VERSION]` section in `CHANGELOG.md`; both
  `make-dmg.sh` and the CI workflow refuse otherwise, because that text becomes
  the GitHub release notes and the App Store "What's New".
- `notarize.sh` refuses when `HEAD`'s tag disagrees with `VERSION`.
- **Sparkle must not link into the App Store build.** It hangs off
  `NevermoreApp` rather than `NevermoreKit`, and every use sits behind
  `#if canImport(Sparkle)`, so the Tuist store target omits it with no flags to
  remember. Note that `NEVERMORE_SANDBOX=1 ./make-app.sh` still embeds Sparkle
  — the SwiftPM target links it unconditionally — so a sandboxed local build
  does *not* approximate the store build in that respect.
- **Store builds must run on CI.** Apple rejects binaries built on a beta macOS
  (ITMS-90301) and this Mac runs one; `BuildMachineOSBuild` is stamped into the
  bundle, so a released Xcode locally is not enough.

## Gotchas

- SwiftMail is pinned to an exact **revision**, not a version: 1.8.0 depends on
  a branch-pinned `swift-nio-imap`, which SPM rejects under `from:`. The pinned
  commit is past 1.8.0 for `fetchGmailAttributes`. Bumping it is deliberate
  work — see TASK-5, which also covers the deprecated search API.
- Sign with a stable identity. An ad-hoc signature changes every build and
  invalidates the Keychain ACL on the saved password.
- IMAP discovery cannot use one unbounded `SEARCH` — it exceeds SwiftMail's 60s
  timeout. It runs 23 one-year date windows, newest first, with adaptive
  halving. Incremental sync uses `.since(lastSync - 2 days)` because
  `SearchCriteria.uid(N)` encodes a single UID, not an open range.

## Docs map

`README.md` is authoritative for current behaviour. `PLAN.md` is kept for
rationale, not status. `RELEASE.md` (DMG/Sparkle) and `MAS-RELEASE.md` (App
Store) are the release runbooks. `UI_SPEC.md` describes the sidebar collections
and the keyboard model. `PRIVACY.md` backs the App Store privacy label.

<!-- BACKLOG.MD MCP GUIDELINES START -->

<CRITICAL_INSTRUCTION>

## BACKLOG WORKFLOW INSTRUCTIONS

This project uses Backlog.md MCP for all task and project management activities.

**CRITICAL GUIDANCE**

- If your client supports MCP resources, read `backlog://workflow/overview` to understand when and how to use Backlog for this project.
- If your client only supports tools or the above request fails, call `backlog.get_backlog_instructions()` to load the tool-oriented overview. Use the `instruction` selector when you need `task-creation`, `task-execution`, or `task-finalization`.

- **First time working here?** Read the overview resource IMMEDIATELY to learn the workflow
- **Already familiar?** You should have the overview cached ("## Backlog.md Overview (MCP)")
- **When to read it**: BEFORE creating tasks, or when you're unsure whether to track work

These guides cover:
- Decision framework for when to create tasks
- Search-first workflow to avoid duplicates
- Links to detailed guides for task creation, execution, and finalization
- MCP tools reference

You MUST read the overview resource to understand the complete workflow. The information is NOT summarized here.

</CRITICAL_INSTRUCTION>

<!-- BACKLOG.MD MCP GUIDELINES END -->
