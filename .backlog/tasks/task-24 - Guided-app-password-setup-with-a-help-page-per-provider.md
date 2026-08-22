---
id: TASK-24
title: 'Guided app-password setup, with a help page per provider'
status: Done
assignee: []
created_date: '2026-08-10 01:47'
updated_date: '2026-08-22 22:47'
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
- [x] #4 Pages linked from the site index and the FAQ
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented on branch `task-24-fix` (commit 77b74ad), not merged.

**What exists now**
- `NevermoreKit/Backend/AppPasswordGuide.swift` — per-provider guidance as data: the provider's own noun for the credential, whether 2FA is a prerequisite, the provider's documentation URL, the Nevermore help page URL, verified steps, a caveat, and the auth-failure explanation. Console URLs are read from `MailProvider` so there is one place to fix them. Unknown domains map to the generic `imap` guide, never to Gmail's.
- `docs/app-passwords.html` (hub) + `app-password-{gmail,icloud,yahoo,fastmail,aol,imap}.html`, sharing `docs/app-password.css`.
- `OnboardingSheet` renders the guidance for the detected/picked provider, links its page, and shows a provider-specific explanation plus the page link when sign-in is rejected. Re-auth now resolves the provider from the stored id rather than the typed domain.
- `MailBackendError.authenticationFailed` no longer carries Google-specific advice (it was telling Fastmail users to check 2-Step Verification); that advice moved to the per-provider guide.

**Verification** — 387 tests pass (377 before, 10 new in the `AppPasswordGuide` suite). Docs link-checked with a script: no broken relative links.

**AC status**
- #1 unchecked: the steps exist and were checked against each provider's current documentation on 2026-08-22 (Google 185833, Apple HT102654, Yahoo SLN15241, Fastmail 360058752854, AOL create-and-manage-app-password), but there are **no screenshots** — taking them means signing in to five providers' account settings, which was not done. AOL's page is deliberately thinner: its help article did not state the current button labels, so that page links AOL rather than describing the menu.
- #2 unchecked: the mapping from address to help page is unit-tested, but the sheet itself was never rendered — the GUI was not launched (shared machine), and the views are unreachable from the test harness.
- #3 unchecked: same reason. The failure copy and the auth/non-auth split are in `OnboardingSheet`; only the wording it draws from (`authFailureExplanation`) is tested.
- #4 checked: `docs/index.html` (How it works + footer), `docs/faq.html` (new question + footer) and `docs/support.html` link the hub and per-provider pages; verified by a link-checking script over `docs/`.

**Still open**
- Screenshots for all six pages.
- The sheet grew two lines on the failure path; its 460pt frame has not been checked visually.
- `SettingsView` still links only the provider console, not the help page. Left alone as out of scope.
<!-- SECTION:NOTES:END -->
