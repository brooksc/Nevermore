---
id: TASK-55
title: The DMG build ships App Intents that Shortcuts cannot see
status: To Do
assignee: []
created_date: '2026-08-23 21:00'
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
