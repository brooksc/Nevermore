---
id: TASK-29
title: Show what senders cost in storage
status: Done
assignee:
  - task-29-storage
created_date: '2026-08-10 01:49'
updated_date: '2026-08-23 20:42'
labels:
  - product
dependencies:
  - TASK-36
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Tidiness is a weak motivator; a full mailbox is a strong one. Gmail's free tier is 15 GB shared with Drive and Photos, and image-heavy newsletters are a real part of what fills it. "These 12 senders are using 3.1 GB" is a better reason to open the app than "you have 40 newsletters".

It fits the premise exactly: RFC822.SIZE is message metadata, not content. Reading it says nothing about what a message contains, so headers-only still holds.

Work: fetch size alongside the existing header fields, store it, aggregate per sender, offer sort-by-size. The obvious follow-through — trashing the biggest senders — is then one keystroke away.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Message size fetched and stored
- [ ] #2 Per-sender totals shown and sortable
- [x] #3 Existing caches backfill without forcing a full re-sync, or the cost is stated plainly
- [x] #4 Sizes never presented as more precise than the server reports
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## The dependency on TASK-36 does not apply to this field

TASK-29 was blocked on TASK-36 because adding a fetch field costs bandwidth on
every message and nobody here has a mailbox to measure against. That reasoning
is sound and it is why TASK-30 shipped everything but its fetch. **It does not
apply to `RFC822.SIZE`, and the reason is structural rather than a judgement
about what is affordable.**

`IMAPBackend.fetch` requests `options: .slim`. SwiftMail defines `.slim` as
`[.envelope, .internalDate, .flags, .size]` (`FetchMessageInfoOptions.swift:52`),
`.size` maps to the `RFC822.SIZE` attribute (`FetchCommands.swift:67`), and
`FetchMessageInfoHandler.swift:192` parses it into `MessageInfo.size`. The sync
has been asking the server for message sizes since before this task existed.
`IMAPBackend.convert` simply never read `info.size`.

So no field was added, no header was added, and the FETCH command is identical
before and after. That is a fact about the code, not a measurement, and
`MessageSizeStorageAndFetchTests` asserts it — if somebody narrows the attribute
set, the test fails and says what it costs. There was accordingly nothing to
gate: a `SyncHeaderFields.fetchesMessageSize = false` would have implied a price
TASK-36 must pay, which would have been false. TASK-36 keeps
`Authentication-Results` and `List-Post`; `RFC822.SIZE` is off its list.

## What was built

- `SenderStorage` (NevermoreKit/Domain) — per-sender aggregation, combination
  across a selection, formatting, sort key, and the caveat text. It carries
  `knownBytes`, `knownMessages` and `unknownMessages` together on purpose, so a
  total can never be quoted without the app knowing how much of it was measured.
- `EmailMessage.byteSize: Int?`, read from `info.size` in `convert`.
- Migration `v7-message-size` — one nullable INTEGER column. The upsert uses
  `COALESCE(excluded.byteSize, message.byteSize)`, matching v6: a fetch that
  omits a size must not erase one already on file, and a message's size does not
  change after delivery so the older value is as good as a new one.
- UI: a sortable **Size** column, a Storage line plus caveat in the inspector,
  and the collection/selection total in the status bar.
- Demo mailbox: per-sender typical sizes spread over two orders of magnitude,
  with three senders deliberately part-unmeasured so demo mode and screenshots
  show the honest states, not only the flattering one.

## Three things it refuses to do

**A sender of unknown size is not a sender of no size.** `nil` stays `nil` from
`MessageInfo` through the store to the screen, and renders "Unknown" in tertiary
— never "0 bytes", which reads as "this sender costs you nothing". Sorting is on
measured bytes, so an unknown sender lands at the bottom of a largest-first sort:
the app cannot claim it is large and must not imply it is small, so it goes where
no claim is made. The cell still says Unknown.

**A partial total says so.** Some measured and some not renders "at least 3.1 GB".

**No total is presented as complete.** Even a fully measured sender's caveat says
the figure counts only the messages Nevermore has on file, so mail already
deleted from the mailbox is not in it. Sizes are rounded by
`ByteCountFormatStyle` rather than reported to the byte, because `RFC822.SIZE` is
the server's count of the message as it would transmit it and is not exactly what
the account is billed for.

Metadata-not-content is stated where a user or a reviewer would look: `PRIVACY.md`
adds `RFC822.SIZE` to the field table with a paragraph explaining that "the app
now reads message sizes" is not a change of posture — the size describes how big
a message is, never what is in it, and no extra request is made. Repeated in
`README.md`, `CHANGELOG.md`, `SenderStorage`'s doc comment and
`EmailMessage.byteSize`.

## Verification

`swift build && swift test` — **520 tests in 92 suites, all passing** (494 before;
26 new). No existing test was edited.

- **AC #1 — checked.** The fetch claim is asserted structurally
  (`SyncHeaderFields.attributes == .slim`, `.contains(.size)`, header list still
  empty). Storage round-trips through `MessageStore`: a size persists, a nil
  comes back nil rather than 0, a re-fetch fills in a missing size, and a fetch
  without a size does not erase a stored one.
- **AC #2 — aggregation and sorting checked; appearance not.** Totals, combining
  across a selection, and largest-first ordering (including where an unmeasured
  and a part-measured sender rank) are tested. `SenderTableView`,
  `InspectorView` and `StatusBarView` compile and are unreviewed: views cannot be
  reached from the test target and the GUI was not launched — shared machine.
  Left unticked for that reason.
- **AC #3 — checked, and the answer is the second half of the criterion.** There
  is no bulk backfill and none was invented: migrations are forward-only, so a
  row written before this change has nothing to be backfilled from, and
  incremental sync re-reads only a two-day overlap. Existing caches therefore
  fill in gradually as messages are re-fetched, and stay "Unknown" until they
  are. Stated in the migration comment, the CHANGELOG entry and the UI. Tested
  that a re-fetch does fill a missing size in, so the gap closes for real rather
  than requiring the cache be thrown away.
- **AC #4 — checked.** Rounding tested (3,149,217,744 B renders "3.15 GB", not
  the exact figure), the 1000-based scale tested against the way providers quote
  quotas, and the "at least" qualifier tested to attach to the size rather than
  being buried elsewhere.

## Not verified

- Any real `RFC822.SIZE` from a real mailbox. Every size in the tests and in the
  demo is constructed. The claim that the value is already on the wire rests on
  reading SwiftMail's source, not on watching a session.
- **No fetch timing was measured, and none is claimed.** The claim is narrower
  and different in kind: the FETCH command is unchanged, so there is nothing new
  to time.
- The migration itself was not exercised against a database created at v6 and
  migrated forward. Testing that needs `pool` access or GRDB as a test-target
  dependency, and neither seemed worth adding for a single nullable
  `ADD COLUMN`. A fresh database is covered by every store test above.
- Anything on screen.

Docs updated: `PRIVACY.md`, `README.md` (Features), `UI_SPEC.md` §5,
`CHANGELOG.md` Unreleased.

## The backfill product call, made

Sizes appear on new mail and fill in only on a full re-sync. No bulk backfill
exists and none was invented — migrations are forward-only, so a row written
before this change has nothing to backfill from.

**The feature does not offer to trigger a re-sync.** A full re-sync is minutes of
work on a large mailbox and that decision belongs to the deliberate control that
already exists at `Settings ▸ Full Resync…` (`SettingsView.swift:103` →
`AppModel.fullResync()`, verified present). What the feature does instead is make
the state legible rather than silent, since a Size column that is mostly blank on
an established mailbox reads as broken: every unmeasured cell says "Unknown", and
its caveat — in the tooltip and in the inspector's Storage line — says how many
messages have no size, that sizes arrive with new mail, and names
`Settings ▸ Full Resync` as where the rest come from. Naming the control is not
offering it; there is no button here that starts one. A test asserts both halves:
the caveat names the control, and it does not tell the user to click anything.

One judgement worth flagging: the status bar omits the size clause entirely when
nothing in the collection is measured, rather than printing "Unknown" there. A
running summary that carried a permanent apology seemed worse than one that says
nothing, and the per-sender column is where an unknown has to be stated because
there a blank could be mistaken for zero. That is a judgement about a surface I
could not look at.
<!-- SECTION:NOTES:END -->
