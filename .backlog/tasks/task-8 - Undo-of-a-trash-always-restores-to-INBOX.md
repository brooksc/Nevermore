---
id: TASK-8
title: Undo of a trash always restores to INBOX
status: Done
assignee: []
created_date: '2026-08-09 18:51'
updated_date: '2026-08-23 02:11'
labels:
  - product
dependencies: []
modified_files:
  - Packages/NevermoreKit/Sources/NevermoreKit/Backend/MailBackend.swift
  - Packages/NevermoreKit/Sources/NevermoreKit/Backend/IMAPBackend.swift
  - Packages/NevermoreKit/Sources/NevermoreKit/Demo/DemoBackend.swift
  - Packages/NevermoreKit/Sources/NevermoreApp/Model/AppModel.swift
  - Packages/NevermoreKit/Tests/NevermoreTests/main.swift
  - CHANGELOG.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
IMAP has no put-it-back-where-it-was, so undoing a trash returns the message to the inbox even if it was archived. A user who archives aggressively gets mail dumped back into the inbox by an action described as undo.

Either record the source mailbox per message and restore there, or say plainly in the undo copy that it returns to the inbox. The second is cheap and honest; the first is correct.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Decision recorded: restore-to-source or clearer copy
- [x] #2 Implemented, with the undo wording matching the behaviour
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Decision: restore-to-source, not clearer copy.

What made the correct option feasible: SwiftMail's pinned revision already
exposes `fetchGmailAttributes`, which returns `X-GM-LABELS` including the
`\Inbox` system label. Inbox membership is therefore one bulk FETCH on the
mailbox `trash` has already selected — not a per-message search. It must be
taken *before* the MOVE, because Gmail strips every label from a message that
lands in Trash; nothing is recoverable at undo time.

Scope of the bug, established rather than assumed: `resolvedFolders` sets the
discovery/trash scope to an all-mail folder only when one exists, i.e. Gmail.
Every other provider searches and trashes INBOX, so the app never sees an
archived message there and restoring to INBOX was already correct. The fix is
Gmail-only by construction and non-Gmail behaviour is byte-for-byte unchanged.

Implementation: `trash` now returns `TrashOutcome(moved:archived:)`, and takes
`recordOrigin` so the probe is skipped for batches too large for undo to be
offered. `untrash(messageIDs:to:)` takes a `RestoreTarget` (.inbox/.archive);
.archive resolves to the all-mail folder, falling back to INBOX where there
isn't one. AppModel splits the restorable set with `TrashOutcome.restorePlan`
and issues one untrash per bucket.

Failure directions are deliberately asymmetric: a failed or unavailable label
probe returns an empty archived set, which is exactly the old behaviour, and a
failed MOVE to All Mail falls back to moving to INBOX. Guessing "inbox" wrongly
puts mail where the user can see it; guessing "archived" wrongly hides it.

Known limit, unfixable here: Gmail *labels* are not restored. The move to Trash
drops them and SwiftMail's `store` handles flags only, not `X-GM-LABELS`, so
restoring a user label would need a fork of the IMAP library — the same fork the
codebase already declined for X-GM-RAW. A labelled, archived message returns
archived and unlabelled. Recorded in CHANGELOG and in the `untrash` doc comment
so nobody reads "restores where it was" as stronger than it is.

Undo copy: left as "Trashed N messages" / "Undo", which now matches what the
code does. README's "⌘Z puts them back" became true rather than needing editing.

Verification: 403/403 tests pass (394 before, 9 added) covering the label→origin
rule, the Gmail host gate, and the restore split. The IMAP round trip itself is
untested — it needs a live Gmail mailbox, which this machine has no credentials
for. Specifically unverified: that Gmail accepts All Mail as a MOVE destination
from Trash, and that the `\Inbox` label reads back as the literal string
`\Inbox` through SwiftMail's `makeDisplayString()`.
<!-- SECTION:NOTES:END -->
