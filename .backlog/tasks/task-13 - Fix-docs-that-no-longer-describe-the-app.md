---
id: TASK-13
title: Fix docs that no longer describe the app
status: Done
assignee: []
created_date: '2026-08-09 18:52'
updated_date: '2026-08-10 02:07'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Fixed more than the task listed. UI_SPEC's View menu and shortcut summary now match the four collections that exist (Command-1 to Command-4), with a note that the numbers are positional so inserting a collection renumbers the rest, and that Unsubscribable and Manual Only were specified but never built. RELEASE.md: four done items checked off, the status paragraph rewritten (it still described the appcast and submission as future work), and the 'single source of truth' section rewritten from a proposal into a description of what exists. PLAN.md 97 tests to 117; README 95 to 117. MAS-RELEASE.md status, and the provisioning profile row that still said missing.

Also recorded the finding from TASK-16 where it matters: a NEVERMORE_SANDBOX=1 build still embeds Sparkle, because the SwiftPM target links it unconditionally. Only the Tuist store build genuinely has no updater.
<!-- SECTION:NOTES:END -->
