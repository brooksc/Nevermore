---
id: TASK-25
title: Point the app's Help menu at the website
status: To Do
assignee: []
created_date: '2026-08-10 01:47'
labels:
  - docs
dependencies: []
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
- [ ] #1 Help menu links the FAQ, the provider setup guides, privacy and support pages
- [ ] #2 Links point at the website, not GitHub blob URLs, so they work without an account
- [ ] #3 One place in the code holds the URLs, so a moved page is one edit
<!-- AC:END -->
