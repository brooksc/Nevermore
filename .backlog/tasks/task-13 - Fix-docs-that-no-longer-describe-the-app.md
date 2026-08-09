---
id: TASK-13
title: Fix docs that no longer describe the app
status: To Do
assignee: []
created_date: '2026-08-09 18:52'
labels:
  - docs
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Several documents drifted while shipping 1.0.0:

- UI_SPEC.md section 8 documents Command-1 to Command-6 with Unsubscribable and Manual Only collections. The app has four collections and Command-2 is Reappeared. This was found the hard way while scripting the demo.
- RELEASE.md lines 326-331 still list the Xcode target, the App Store Connect record, the privacy label and the first upload as not done. All four are done.
- PLAN.md section 9a says 97 tests pass; it is 110.
- Docs last reviewed dates say 26 July across several files.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 UI_SPEC shortcuts match the shipping collections
- [ ] #2 RELEASE.md checkboxes reflect reality
- [ ] #3 Test count and review dates corrected
<!-- AC:END -->
