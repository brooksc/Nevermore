---
id: TASK-4
title: Pin the resolved IP so DNS rebinding cannot beat DestinationGuard
status: To Do
assignee: []
created_date: '2026-08-09 18:50'
labels:
  - security
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DestinationGuard resolves the host and decides, then URLSession resolves independently when the request is made. A hostile resolver can answer public for the first lookup and private for the second, which defeats the check entirely.

This matters more here than in most apps: every URL comes from an attacker-authored List-Unsubscribe header, which is the app's central threat. Recorded as open in PLAN.md section 10.

A real fix pins the validated IP and sets the Host header, rather than trusting a second resolution.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The validated address is the one connected to
- [ ] #2 Host header preserved so TLS and vhosts still work
- [ ] #3 Redirect hops get the same treatment
- [ ] #4 Test covers a resolver that changes its answer between lookups
<!-- AC:END -->
