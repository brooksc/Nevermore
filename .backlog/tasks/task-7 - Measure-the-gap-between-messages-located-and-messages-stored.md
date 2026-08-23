---
id: TASK-7
title: Measure the gap between messages located and messages stored
status: Done
assignee: []
created_date: '2026-08-09 18:51'
updated_date: '2026-08-23 20:19'
labels:
  - product
dependencies: []
modified_files:
  - Packages/NevermoreKit/Sources/NevermoreKit/Backend/SyncAttribution.swift
  - Packages/NevermoreKit/Sources/NevermoreKit/Backend/IMAPBackend.swift
  - Packages/NevermoreKit/Sources/NevermoreKit/Backend/MailBackend.swift
  - Packages/NevermoreKit/Sources/NevermoreKit/Store/MessageStore.swift
  - Packages/NevermoreKit/Sources/NevermoreKit/Demo/DemoBackend.swift
  - Packages/NevermoreKit/Sources/NevermoreApp/Model/AppModel.swift
  - Packages/NevermoreKit/Sources/NevermoreApp/Views/StatusBarView.swift
  - Packages/NevermoreKit/Sources/Probe/main.swift
  - Packages/NevermoreKit/Tests/NevermoreTests/Suites.swift
  - PLAN.md
  - README.md
  - UI_SPEC.md
  - CHANGELOG.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Discovery consistently finds more UIDs than the store keeps, and the split has never been measured. The expected causes are the user's own sent mail and headers whose only unsubscribe target uses an unsupported scheme, but that is a guess.

It matters because the UI shows both numbers, and today nobody can explain the difference to a user who notices. Recorded as open in PLAN.md section 10.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Sync logs a breakdown of why located messages were not stored
- [ ] #2 Measured once against the real mailbox and the split written into PLAN.md
- [ ] #3 If a category is unexpectedly large, a follow-up task is filed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Instrumentation built and tested on branch `task-7-fix`; the measurement itself is NOT done.

**Categories.** Found by reading every point on the path `discoverAll` → `searchWindow` → `fetch` → `convert` → `filterOutOwnMail` → `upsert` where a located UID can stop, rather than from the suspected list. `SyncDropReason` (Backend/SyncAttribution.swift):
- `notFetched` — SEARCH matched, FETCH returned nothing for the UID (or a response with no UID). Derived as `located - fetched`, so no per-UID set.
- `noUnsubscribeHeader` — fetched, header absent or blank despite the search matching on it.
- `unsupportedScheme` — every target uses a scheme that is not http/https/mailto. One of the two suspected causes.
- `unusableTarget` — a supported scheme that still yielded nothing: no angle brackets, an unparseable URL, or a mailto address the injection guard rejected. Split from the above deliberately — one is the sender's choice, the other is our parser, and they want opposite responses.
- `ownMail` — sender matches a send-as address. The other suspected cause.
- `duplicateUID` — same UID twice in one fetch. Previously collapsed silently inside SQLite and read as a message that vanished; now deduped in the backend and counted.

Plus the store half: `inserted` vs `updated`. `updated` is the answer to most of an incremental sync's apparent gap — the two-day search overlap re-reads messages on purpose, and a re-read message is not a lost one.

**Arithmetic is checked.** `SyncAttribution.unaccounted = located - (inserted + updated + dropped)`; `balances` is false if a drop exists that no case names, and the log line says `UNACCOUNTED n`. That is the guard against this type drifting out of date with the code it describes.

**Cost.** One `Set<UInt32>` insert per fetched message (~58 KB at 14,600 UIDs) and one dictionary bump per *dropped* message. Header re-classification runs only on the drop path, never on messages that parse. Two `COUNT(*)`s per upsert.

**Where it surfaces.** `Log.sync` one-liner on every sync; `nevermore-probe` prints the full breakdown (this is where the measurement gets taken); status bar — "Last synced…" becomes a button opening a popover with a line and a count per reason.

**Found on the way (not fixed):** on a *first* full sync `filterOutOwnMail` has only the primary address to match, because `AppModel` calls `sendAsAddresses()` after the sync returns. A first run's `ownMail` count is therefore a floor, and an incremental run's is the honest one. Noted in PLAN.md §10.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: task-7 agent
created: 2026-08-23 20:19
---
AC #1 is done and verified — the breakdown is logged on every sync and rendered in the app.

AC #2 and #3 are **not** done and cannot be done from here: the measurement needs a real mailbox, which this session deliberately did not go looking for. `nevermore-probe` prints the full split; whoever runs it against a real account should paste the numbers into PLAN.md §10 (the entry is already rewritten to say the instrumentation exists and the split is still unmeasured) and file the follow-up if a category is unexpectedly large. TASK-33, TASK-36 and TASK-51 are all waiting on that run, not on more code.

Tests: 494 in 86 suites (was 479 in 83); 15 new. The only failures are the three port-binding tests, which fail because the maintainer's app is running and holding 8775-8779 — unrelated to this change.
---
<!-- COMMENTS:END -->
