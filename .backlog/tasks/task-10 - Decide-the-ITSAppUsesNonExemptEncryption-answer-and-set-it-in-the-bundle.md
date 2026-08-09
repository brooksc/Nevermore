---
id: TASK-10
title: Decide the ITSAppUsesNonExemptEncryption answer and set it in the bundle
status: To Do
assignee: []
created_date: '2026-08-09 18:52'
labels:
  - store
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every submission re-asks the export compliance questions. Setting ITSAppUsesNonExemptEncryption in Info.plist ends that, but the easy value is not the honest one: the app statically links BoringSSL via swift-nio-ssl for IMAP and SMTP TLS, so it does more than call the OS.

The declaration made for 1.0.0 was standard algorithms in addition to Apple's, plus not distributed in France. Whatever key is set must say the same thing, and it interacts with TASK-11.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Correct value determined for an app bundling BoringSSL
- [ ] #2 Key set in Project.swift infoPlist, and in make-app.sh if it applies to the DMG
- [ ] #3 Next submission does not ask the encryption questions
<!-- AC:END -->
