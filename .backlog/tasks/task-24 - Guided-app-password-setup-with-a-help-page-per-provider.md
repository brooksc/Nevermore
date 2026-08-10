---
id: TASK-24
title: 'Guided app-password setup, with a help page per provider'
status: To Do
assignee: []
created_date: '2026-08-10 01:47'
labels:
  - docs
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The app password is the barrier. Nobody generates an app-specific password for a tool they have only read about, and the failure mode is silent — people try their account password, get an auth error, and leave.

Agreed approach: a page per provider in docs/ on the site, walking the setup through with screenshots, linked directly from the add-account dialog. No in-app wizard to maintain, and the pages are fixable without shipping a build — which matters because providers move these settings.

Providers to cover, in order of likely use: Gmail (needs 2FA enabled first, which is the step people miss), iCloud, Yahoo, Fastmail, AOL, and a generic IMAP page for custom domains.

The dialog should link to the page for the provider it has already detected from the address, not a menu of all six. The app knows the provider before the password is entered.

Worth pairing with better auth-failure copy: when a login fails, say that providers commonly reject the account password and link the same page, rather than reporting a generic failure.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A help page per provider under docs/, each with the real steps and screenshots
- [ ] #2 Add-account dialog links to the page for the detected provider
- [ ] #3 Auth failure names app-password policy as the likely cause and links the page
- [ ] #4 Pages linked from the site index and the FAQ
<!-- AC:END -->
