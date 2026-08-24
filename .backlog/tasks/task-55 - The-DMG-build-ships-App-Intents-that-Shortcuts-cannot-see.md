---
id: TASK-55
title: The DMG build ships App Intents that Shortcuts cannot see
status: Won't Do
assignee: []
created_date: '2026-08-23 21:00'
updated_date: '2026-08-24 03:16'
labels:
  - product
dependencies:
  - TASK-35
priority: medium
type: bug
ordinal: 21000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-35 added four App Intents. They are registered in the Mac App Store build and invisible in the direct-download one.

Xcode runs an `ExtractAppIntentsMetadata` build phase for app targets, which writes `Contents/Resources/Metadata.appintents`. Shortcuts, Spotlight and Siri read that bundle; without it the intents are compiled and linked but nothing lists them. The Tuist store target gets the phase for free — verified: the built `Nevermore.app` contains a `Metadata.appintents` naming all four intents and `SenderEntity`.

SwiftPM has no such phase, and `make-app.sh` copies only `AppIcon.icns` into `Contents/Resources`. So the DMG channel — which is the primary channel today — ships the feature dead. Nothing is broken at runtime; the intents simply never appear.

The fix is to invoke `appintentsmetadataprocessor` from `make-app.sh` after the SwiftPM build, out of the active Xcode toolchain, with the module name, SDK root, Swift version and the `Sources/NevermoreApp` inputs. It is undocumented and version-sensitive, which is why TASK-35 reported it rather than guessing at the invocation: a subtly wrong bundle is worse than a missing one, because it looks like it worked.

Worth checking as part of this whether an intent that arrives while the app is closed should launch it. TASK-35 set `openAppWhenRun = false` on all four so a scheduled sync cannot steal the screen, and the trade is that a shortcut run against a closed app refuses with a message. That is the right default for Sync; it may be the wrong one for the ignore verbs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A DMG-channel Nevermore.app contains Contents/Resources/Metadata.appintents naming all four intents
- [ ] #2 The four intents appear in the Shortcuts app from a DMG install
- [ ] #3 make-app.sh fails loudly if the metadata step does not produce a bundle, rather than shipping an app without one
- [ ] #4 A test or script check asserts the built bundle carries the metadata, so this cannot regress silently
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-08-24 03:16
---
Won't Do. The bug is real — the DMG build genuinely ships intents Shortcuts cannot see — but it is not worth fixing, because the feature it would complete has no established value.

The maintainer's view, and I agree: "I struggle to find any value in intents, I don't see anyone using Siri to trigger Nevermore. If you hadn't implemented it I'd say don't."

The deeper problem is that the three verbs safe enough to automate are the three with the least automation value. Sync duplicates the scheduled background sync already in Settings. Ignoring by name requires knowing the sender in advance, which means you are already in the app looking at it. Get Reappeared is a query, and Reappeared already notifies. The one verb worth automating — unsubscribe — is the one that must never be automated, which is not a gap to fill but a sign the app is a poor fit for Shortcuts.

What has been done instead is to stop overpromising: the README section is removed and the CHANGELOG entry now says Mac App Store build. The intents stay because they are isolated, cost nothing at runtime, and give the store listing something Apple favours — which is a marketing benefit, named as one.

Re-open this if someone actually asks for a shortcut, or if the intents start constraining a refactor of AppModel. In the second case deleting TASK-35 outright is the better answer than finishing it.
---
<!-- COMMENTS:END -->
