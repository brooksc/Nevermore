---
id: TASK-10
title: Decide the ITSAppUsesNonExemptEncryption answer and set it in the bundle
status: On Hold
assignee: []
created_date: '2026-08-09 18:52'
updated_date: '2026-08-23 17:47'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-08-23 17:47
---
Parked at the maintainer's direction: answer the questions at submission time rather than setting the plist key.

The answers are now written down in MAS-RELEASE.md §9.5 so they are consistent every upload and nobody re-derives them under time pressure. Recorded there: encryption yes; exemption no, because the app statically links BoringSSL through swift-nio-ssl rather than relying on Apple's crypto; declared as standard algorithms in addition to the OS; not distributed in France.

That removes the recurring cost without taking on the risk this task was really about — the honest value of ITSAppUsesNonExemptEncryption depends on the France answer (TASK-11), and a wrong plist key is harder to notice than a wrong questionnaire answer, because nothing asks you to confirm it again.
---
<!-- COMMENTS:END -->
