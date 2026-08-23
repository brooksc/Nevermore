---
id: TASK-35
title: Expose actions to Shortcuts
status: Done
assignee: []
created_date: '2026-08-10 01:49'
updated_date: '2026-08-23 20:59'
labels:
  - product
dependencies: []
modified_files:
  - Packages/NevermoreKit/Sources/NevermoreKit/Domain/ShortcutsSurface.swift
  - Packages/NevermoreKit/Sources/NevermoreKit/Domain/SenderMatch.swift
  - Packages/NevermoreKit/Sources/NevermoreApp/Intents/NevermoreIntents.swift
  - Packages/NevermoreKit/Sources/NevermoreApp/Intents/IntentContext.swift
  - Packages/NevermoreKit/Sources/NevermoreApp/Intents/SenderEntity.swift
  - Packages/NevermoreKit/Sources/NevermoreApp/Model/AppModel.swift
  - Packages/NevermoreKit/Tests/NevermoreTests/Suites.swift
  - README.md
  - CHANGELOG.md
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Cheap to add and it fits the audience: someone who runs a local-first, keyboard-driven mail tool is the same person who automates things. App Intents for the obvious verbs — sync, unsubscribe from a named sender, list reappeared senders — make the app scriptable without an API or a server.

Also useful for the store listing, since Shortcuts support is a feature Apple likes to see.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 App Intents for sync, unsubscribe, ignore, and querying reappeared senders
- [x] #2 Intents refuse to act without the same confirmations the UI requires
- [x] #3 Works in the sandboxed store build
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-08-20 21:20
---
TASK-41 (MCP server for agent triage) needs the same verbs with the same confirmation rules — sync, unsubscribe, ignore, query reappeared, all refusing to act without the confirmations the UI requires. Whichever is built first should put those verbs in one internal action layer so the other becomes a second caller rather than a second implementation. Note the divergence: App Intents must work in the sandboxed store build (this task's AC #3), while the MCP bridge is excluded from it, so the action layer has to sit below that split.
---

author: claude
created: 2026-08-23 20:59
---
Three intents shipped, not four. **AC #1 is left unchecked deliberately** — there is no unsubscribe intent, and this is the reason rather than an omission.

AC #2 is the binding one, and for Shortcuts it cannot be satisfied by "the intent raises the app's confirmation". A Shortcut can be *scheduled*, which an MCP client cannot: an unsubscribe intent would either act at 3am with nobody looking, or put a dialog on screen with nobody there to read it. A confirmation that fires on a schedule is answered by reflex, which is a worse hole than the MCP one `ReviewToken` was written to close. So the admission test became `ShortcutVerb.isLocalAndReversible` — the verb changes nothing outside this Mac and can be undone here — and `unsubscribe`, `unsubscribe_and_delete` and `trash_sender_messages` are recorded in `ShortcutsSurface.refused` with their reasons, so the absence reads as a decision.

Shipped: **Sync Mailbox**, **Ignore Senders**, **Unignore Senders**, **Get Reappeared Senders** (returns `SenderEntity` values with messages-since-unsubscribe, worst first). Sync and Reappeared are in `AppShortcutsProvider` for Spotlight/Siri; the ignore pair is not, because a one-tap action with no sender attached invites a mistake.

**The action layer was reusable as TASK-52 predicted, with no entanglement.** Only `LocalServerController` and its Settings section are behind `#if NEVERMORE_MAS`; `MCPActions` (NevermoreKit) and `AgentActions` (NevermoreApp) compile unconditionally, so they already sat below the split. Every intent goes through `AgentActions` via `IntentContext` — `startSync()` and `setIgnored(_:senderIds:)` — so the two channels share wording and refusals rather than being two implementations. The intents deliberately do *not* hold an `any MCPActions`, since that protocol carries `requestUnsubscribe`/`requestTrash`; `IntentContext` exposes four methods and nothing else. Second lock: `IntentContext.detail(of:)` **throws** on `awaiting_confirmation`, so wiring a confirmation-requiring verb to an intent fails loudly instead of quietly popping a dialog — that guard does not depend on anyone keeping the verb list current.

AC #3 verified further than a compile: `tuist generate` + `xcodebuild -scheme Nevermore` (the store target, `NEVERMORE_MAS` defined) succeeds, and `Nevermore.app/Contents/Resources/Metadata.appintents` contains SyncMailboxIntent, IgnoreSendersIntent, UnignoreSendersIntent, ReappearedSendersIntent and SenderEntity. `swift build -Xswiftc -DNEVERMORE_MAS` also clean. Not verified: running a shortcut against a live sandboxed app — the GUI was not launched (shared machine).

**Known gap, DMG channel only.** SwiftPM does not run Xcode's ExtractAppIntentsMetadata phase and `make-app.sh` copies only AppIcon.icns, so the direct-download build links the intents but ships no `Metadata.appintents` and Shortcuts will not list them. The store target gets the phase for free. Filed separately.

Tests: 560 in 96 suites (was 549 in 94), all passing. New suites cover the surface policy (every shipped verb local and reversible, unsubscribe/trash refused with stated reasons, no verb on both lists) and `SenderMatch` ranking for the entity picker. The intent shells themselves are untestable — NevermoreTests depends on NevermoreKit only, and `AppModel` lives in NevermoreApp.
---
<!-- COMMENTS:END -->
