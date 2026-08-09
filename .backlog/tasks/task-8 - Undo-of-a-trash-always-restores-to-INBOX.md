---
id: TASK-8
title: Undo of a trash always restores to INBOX
status: To Do
assignee: []
created_date: '2026-08-09 18:51'
labels:
  - product
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
IMAP has no put-it-back-where-it-was, so undoing a trash returns the message to the inbox even if it was archived. A user who archives aggressively gets mail dumped back into the inbox by an action described as undo.

Either record the source mailbox per message and restore there, or say plainly in the undo copy that it returns to the inbox. The second is cheap and honest; the first is correct.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Decision recorded: restore-to-source or clearer copy
- [ ] #2 Implemented, with the undo wording matching the behaviour
<!-- AC:END -->
