---
id: TASK-50
title: A sender that is ignored and unsubscribed appears in both archives
status: To Do
assignee: []
created_date: '2026-08-21 01:13'
updated_date: '2026-08-21 01:14'
labels:
  - ui
dependencies: []
priority: low
type: bug
ordinal: 16000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A sender that has been both ignored and unsubscribed is listed in the Unsubscribed archive *and* the Ignored archive, because `.unsubscribed` never excluded ignored senders.

Pre-existing behaviour, not introduced by TASK-27 — that task pinned it with a test naming it as inherited rather than endorsed, so the current behaviour is now locked in until someone decides otherwise. This task is that decision.

It is a product question rather than a defect to fix blind. The two archives answer different questions ("who did I unsubscribe from" and "who did I mute"), and a sender can honestly belong to both. The argument for changing it is that every other collection is mutually exclusive, so a row appearing twice reads as a bug to a user who has not thought about it. The argument for leaving it is that hiding an unsubscribe record because the sender was later ignored loses information the Reappeared feature depends on.

Whichever way it goes, the test that currently pins the behaviour must be updated to say the outcome is intended, rather than describing it as inherited.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A decision is recorded on whether the two archives may overlap
- [ ] #2 The chosen behaviour is covered by a test that states it is intended
- [ ] #3 If overlap is removed, no unsubscribe record is lost — only its presentation changes
- [ ] #4 UI_SPEC.md matches whatever is decided
<!-- AC:END -->
