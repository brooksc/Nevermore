---
id: TASK-25
title: Point the app's Help menu at the website
status: Done
assignee: []
created_date: '2026-08-10 01:47'
updated_date: '2026-08-22 22:57'
labels:
  - docs
dependencies: []
modified_files:
  - Packages/NevermoreKit/Sources/NevermoreKit/Backend/SupportSite.swift
  - Packages/NevermoreKit/Sources/NevermoreKit/Backend/AppPasswordGuide.swift
  - Packages/NevermoreKit/Sources/NevermoreApp/Commands.swift
  - Packages/NevermoreKit/Tests/NevermoreTests/main.swift
  - UI_SPEC.md
  - CHANGELOG.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Help menu is Nevermore Help, Privacy and Data Handling, and Report an Issue. Meanwhile the site has grown a FAQ, a privacy page, a support page and (with TASK-24) provider setup guides — and the app links to almost none of it.

Help that lives on the website can be fixed without shipping a build, which is the point.

Audit every place the app could send someone for help — Help menu, the add-account dialog, auth failures, the empty states, the unsubscribe result sheets — and link the relevant page.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Help menu links the FAQ, the provider setup guides, privacy and support pages
- [x] #2 Links point at the website, not GitHub blob URLs, so they work without an account
- [x] #3 One place in the code holds the URLs, so a moved page is one edit
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
`SupportSite` (NevermoreKit) is now the one list of pages the app links: home, faq.html, app-passwords.html, privacy.html, support.html. `AppPasswordGuide.siteBase` was a second copy of the base URL and is gone; the per-provider guides now hang off `SupportSite.home`.

Help menu is Check for Updates… / How Nevermore Works / Keyboard Shortcuts ⌘? — divider — Frequently Asked Questions / Setting Up an App Password / Privacy Policy / Nevermore Support. Privacy Policy left a GitHub blob URL and Report an Issue… left the issue tracker; both now go to site pages that need no account. The site home page was dropped as a menu item (every page links back to it), and the six per-provider app-password pages are reached through their index rather than listed individually — a menu has no address in hand to pick the right provider with, and the add-account sheet already links the specific page.

4 tests appended to the harness (391 passing, was 387): every linked page is a real file in docs/, no link is a GitHub blob URL, the guides share the one base, and the app-passwords index links every provider page.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Help menu now links the FAQ, the app-password guides index, the privacy policy and the support page, all on the published site. URLs live in one place (`SupportSite` in NevermoreKit), verified by tests that check each page exists in `docs/` and that none is a GitHub blob URL. Menu items were not clicked — the app was not launched (shared machine).
<!-- SECTION:FINAL_SUMMARY:END -->
