# Nevermore for macOS — Build Plan

Native Swift rewrite of the Python TUI (originally `py/`, since removed — the
original lives in its own repo). Target: parity plus the things a TUI can't do.

> **Kept for the rationale, not as a status report.** Sections 1–9 explain
> *why* the app is shaped the way it is and remain accurate. Section 9a
> (status) and section 10 (open questions) are updated as of **26 July 2026**.
> The app was since built, gained multi-provider support, and was renamed from
> MailScrub to Nevermore. Where this document and the code disagree about
> current behaviour, see [README.md](README.md) — the source is authoritative.

Status at time of writing: planning. All numbers below come from the original
Python IMAP spike (`spike/imap_probe.py`, since removed — superseded by the
Swift `Probe` target) run against a real 132,883-message mailbox on 2026-07-22.

---

## 1. Decisions already made

| Decision | Rationale |
|---|---|
| **IMAP + app-specific password**, not the Gmail API | An app password is a *user credential*, not an OAuth grant — no Cloud project, no consent screen, no verification, no CASA assessment, no 100-user cap, no 7-day token expiry. It is the only path where an arbitrary downloader can use the app on day one. |
| **SwiftMail** for IMAP/SMTP | Actively maintained actor-based wrapper over Apple's `swift-nio-imap`. MailCore2 is a 2020 binary blob pinned to macOS 10.10 — not viable. |
| **Pure RFC 3501 for v1**, Gmail extensions later | Avoids forking two dependencies before shipping anything. See §4. |
| **Keep the existing sync query semantics** | `{category:promotions unsubscribe}` is an OR, not an AND — already broad. Measured: "broadening" it added 0 messages and lost 2,672. |
| **SQLite via GRDB**, not SwiftData | The sync engine is built on set-difference over ID lists. That's raw SQL work. SwiftData fights it. |

### Not doing

- No Gmail API backend in v1. The `MailBackend` protocol leaves room; adding it
  later means an iOS-type OAuth client (no secret is issued for that client
  type), `gmail.modify` scope, and a verification project. Out of scope now.
- ~~No multi-provider support. Gmail-only, like the original.~~ *Superseded:
  the app now supports any IMAP provider, with folders discovered via
  SPECIAL-USE rather than hard-coded Gmail names.*
- No message bodies. Headers only, same privacy posture as the Python app.

---

## 2. What the spike proved

Measured on a real test account, 132,883 messages in All Mail:

| Capability | Result |
|---|---|
| Post-login capabilities | `CONDSTORE MOVE UIDPLUS ESEARCH COMPRESS=DEFLATE IDLE X-GM-EXT-1 LIST-STATUS` |
| Header fetch throughput | **1,084 msg/s** (500 headers in 0.46s) — ~40× the REST API's 25/batch-with-1s-sleep |
| Full sync of 4,479 messages | **~4 seconds** (vs ~3 minutes today) |
| `Delivered-To` present | **500/500** — alias detection works with no backfill |
| `List-Unsubscribe` present | 406/500 sampled |
| `List-Unsubscribe-Post` (RFC 8058 one-click) | **393/500 — 79%** can use the good POST path |
| Send-as aliases | **5 inferred from Sent Mail** — replaces `users.settings.sendAs.list` |
| SMTP submission | Authenticates — `mailto:` unsubscribes work without the Gmail API |
| `X-GM-RAW` search | Works, 0.3s for the production query |
| `HEADER List-Unsubscribe ""` | Works, 14,682 hits, **94s** |

**Gmail categories are NOT exposed as IMAP labels.** Observed labels on this
account: `\Important`, `\Inbox`, `\Starred`, `Sent`, plus user labels. No
`\Promotions`. Category filtering therefore requires `X-GM-RAW` — it cannot be
done via labels. This is why v1 uses header-based discovery instead (§4).

---

## 3. Module layout

Swift package with a thin app target. Keeps the domain logic testable without
launching a UI, mirroring what the Python version got right.

```
Nevermore.mac/
├── Nevermore.xcodeproj
├── App/                          # @main, windows, menu bar, Sparkle
│   └── NevermoreApp.swift
├── Packages/
│   └── NevermoreKit/             # everything below is plain Swift, no UI
│       ├── Sources/
│       │   ├── Domain/           # value types + pure logic, zero I/O
│       │   │   ├── EmailMessage.swift
│       │   │   ├── EmailSender.swift
│       │   │   ├── SenderGroup.swift
│       │   │   └── Grouping.swift
│       │   ├── Backend/
│       │   │   ├── MailBackend.swift        # the protocol (§5)
│       │   │   └── IMAPBackend.swift        # SwiftMail impl
│       │   ├── Store/
│       │   │   ├── Database.swift           # GRDB, migrations
│       │   │   └── MessageStore.swift
│       │   ├── Sync/
│       │   │   └── SyncEngine.swift         # actor
│       │   ├── Unsubscribe/
│       │   │   ├── UnsubscribeEngine.swift
│       │   │   └── ListUnsubscribeHeader.swift   # RFC 2369/8058 parsing
│       │   └── Credentials/
│       │       └── Keychain.swift
│       └── Tests/
└── Sources/Probe/main.swift      # live-mailbox harness; replaced the Python spike
```

`NevermoreKit` must not import SwiftUI. Enforced by a build-phase grep in CI.

---

## 4. The query strategy

This is the one genuinely subtle part, and the spike changed the answer twice.

**v1 — pure RFC 3501, no Gmail extensions, no forks:**

```
SELECT "[Gmail]/All Mail"          -- excludes Trash and Spam automatically
UID SEARCH HEADER "List-Unsubscribe" "" NOT FLAGGED
```

Then drop client-side any message whose `From` matches a known send-as address
(that's the `-in:sent` exclusion). Everything here is expressible in SwiftMail's
`SearchCriteria` today: it has `.header`, `.not`, `.flagged`.

Costs 94s on first run. Acceptable *once*, in the background, with a progress
bar — and it is strictly more complete than the Python query, because it finds
every message carrying the header regardless of category or body text.

**Incremental sync** then uses `CONDSTORE`:

```
SELECT "[Gmail]/All Mail" (CONDSTORE)
UID SEARCH MODSEQ <lastHighestModSeq>
```

`SearchCriteria.modSeq` exists in SwiftMail. This replaces the Python app's
`after:<epoch>` timestamp hack, which can both miss and re-fetch messages around
clock skew. Persist `UIDVALIDITY` alongside; if it changes, full resync.

**v2 — optional X-GM-RAW optimization.** Drops first-run discovery from 94s to
0.3s. Requires adding `case gmailRaw(String)` to *two* enums:
`SwiftMail.SearchCriteria` and `NIOIMAPCore.SearchKey`. Both are encoder-only
changes (~10 lines each; SEARCH responses are just UID lists, so no parser work).
Fork both, PR upstream, and gate behind a capability check for `X-GM-EXT-1`.
**Not on the critical path.** Do it only if the 94s first run tests badly.

---

## 5. The MailBackend protocol

Deliberately narrow — only what the app actually needs, so a Gmail API
implementation stays cheap to add later.

```swift
public protocol MailBackend: Sendable {
    /// Every message carrying List-Unsubscribe. Slow; first run only.
    func discoverAll(progress: @Sendable (Int, Int) -> Void) async throws -> [MessageHeader]

    /// Messages changed since the given sync token. Fast.
    func changes(since token: SyncToken?) async throws -> (headers: [MessageHeader], token: SyncToken)

    func trash(_ ids: [MessageID]) async throws
    func sendMail(to: String, subject: String, body: String, from: String?) async throws
    func sendAsAddresses() async throws -> [String]
    var primaryAddress: String { get async throws }
}
```

`SyncToken` wraps `(uidValidity, highestModSeq)` for IMAP; it would wrap
`historyId` for a Gmail API backend. That's the whole reason it's opaque.

---

## 6. Schema

Port of the Python schema with the defects fixed. GRDB migrations from day one.

```sql
CREATE TABLE messages (
    uid              INTEGER PRIMARY KEY,   -- IMAP UID, not Gmail msg id
    gm_msgid         TEXT,                  -- X-GM-MSGID when available, else NULL
    sender_email     TEXT NOT NULL,
    sender_domain    TEXT NOT NULL,
    sender_name      TEXT NOT NULL DEFAULT '',
    subject          TEXT NOT NULL DEFAULT '',
    received_at      REAL NOT NULL,
    is_unread        INTEGER NOT NULL DEFAULT 1,
    unsubscribe_raw  TEXT,                  -- verbatim List-Unsubscribe header
    unsubscribe_post INTEGER NOT NULL DEFAULT 0,
    delivered_to     TEXT NOT NULL DEFAULT '',
    synced_at        REAL NOT NULL
);
CREATE INDEX idx_messages_sender ON messages(sender_email);
CREATE INDEX idx_messages_received ON messages(received_at);

-- Fixed: the Python version's PK is named `domain` but stores an email address.
CREATE TABLE unsubscribe_history (
    sender_key    TEXT PRIMARY KEY,         -- honestly named; holds whatever GroupID.key holds
    unsubscribe_url TEXT,
    attempted_at  REAL NOT NULL,
    outcome       TEXT NOT NULL             -- 'requested' | 'confirmed' | 'failed'
);

CREATE TABLE ignored_senders (
    sender_key  TEXT PRIMARY KEY,
    ignored_at  REAL NOT NULL
);

CREATE TABLE sync_state (key TEXT PRIMARY KEY, value TEXT NOT NULL);
```

Changes from Python, each deliberate:

- **`outcome` replaces the always-`True` success flag.** `UnsubscribeClient.verify_unsubscribe()`
  returns `True` unconditionally today, so every attempt is recorded as a
  success. Track `requested` vs `confirmed` honestly and say so in the UI.
- **`ignored_senders` replaces `excluded_message_ids`.** Ignoring is a
  sender-level concept; storing it per-message means every new message from an
  ignored sender reappears until the next ignore.
- **No `message_cache` table.** The Python version has two overlapping caches;
  the TTL one is only used by the legacy non-store path. Dropped.
- **WAL + `synchronous=NORMAL`.** The Python app uses `FULL` + `journal_mode=DELETE`
  for a cache that can be rebuilt from Gmail in 4 seconds.

---

## 7. Grouping — replacing the hardcoded alias table

`DomainService._aliases` is a hand-maintained dict of ~40 specific companies
("Additional domains from screenshot"). It doesn't generalize, and it's the
exact anti-pattern to avoid in a repo that's going public.

Replacement, in order:

1. **Registrable domain** via the Public Suffix List (`swift-domain-parser` or a
   bundled PSL snapshot). `email.harborfreight.com` → `harborfreight.com`. This
   alone subsumes most of the hardcoded table.
2. **Strip common bulk-sender subdomains** before step 1 where the registrable
   domain is a known ESP (`sendgrid.net`, `mailgun.org`, `sparkpostmail.com`) —
   fall back to the `From` display name in that case.
3. **Split shared platforms by display name**, which is the Python heuristic and
   is sound: >1 distinct display name within a domain ⇒ split per sender address
   (Substack); 1 display name across many addresses ⇒ keep merged (Amazon).
4. **User overrides** in a local table, editable via merge/split in the UI.

Verify: golden-file test over an anonymized export of the 4,479-message set,
asserting group counts stay stable across refactors.

---

## 8. Build sequence

Each milestone ends in something runnable and verifiable.

**M0 — Skeleton (0.5 d)**
Xcode project, `NevermoreKit` package, CI running `swift test`.
*Verify:* `swift test` green on an empty suite; CI badge.

**M1 — Connect and store (3 d)**
SwiftMail dependency, Keychain credential storage, app-password onboarding
sheet, `IMAPBackend.discoverAll`, GRDB schema + migrations.
*Verify:* CLI harness in the package prints "N messages stored" matching the
spike's 14,682 within the sender-filter delta. Re-run is idempotent.

**M2 — Sync engine (3 d)**
`SyncEngine` actor, CONDSTORE incremental, `UIDVALIDITY` invalidation, progress
via `AsyncStream`, cancellation.
*Verify:* full sync then immediate re-sync fetches 0 messages. Kill mid-sync;
restart resumes without duplicates or gaps. Unit tests with a mock backend.

**M3 — Domain logic (3 d)**
Header parsing (RFC 2047 encoded words, RFC 2369/8058), grouping per §7,
statistics.
*Verify:* golden-file grouping test; RFC 2047 fixtures ported from
`py/tests/test_domain.py` and `test_sender_edge_cases.py`.

**M4 — Unsubscribe engine (3 d)**
POST → GET → `mailto:` chain, send-as alias resolution from `Delivered-To`,
`UID MOVE` to Trash, history recording with honest `outcome`.
*Verify:* `URLProtocol` stub tests for each branch. One real end-to-end
unsubscribe against a live newsletter, manually confirmed.

**M5 — UI at parity (6 d)**
`NavigationSplitView`, `Table` with native sort, multi-select, confirm sheets,
ignored-senders view, reappeared-sender alert, progress overlay.
*Verify:* every keybinding in the Python README's table has an equivalent
command with a menu item and shortcut. Manual pass through each.

**M6 — Beyond parity (5 d)**
Sender detail pane with per-message actions; live search field; `WKWebView`
sheet for unsubscribe pages needing a confirm click (this is what upgrades
`outcome` from `requested` to `confirmed`); `UndoManager` for trash; IDLE-driven
background refresh + notification.
*Verify:* each feature demoed against the live account.

**M7 — Ship (3 d)**
Hardened runtime, notarization, Sparkle, first-run docs, `.dmg`.
*Verify:* clean-VM install, launch, onboard, sync, unsubscribe.

**~26 working days.** M0–M5 is parity at ~18 days; M6 is where it gets better
than the TUI.

---

## 9. Defects in the Python version — do not port

Carried forward from the code review so they don't get faithfully reproduced:

1. `verify_unsubscribe()` returns `True` unconditionally — every unsubscribe is
   reported as a success. → §6 `outcome`.
2. `unsubscribe_history.domain` stores an email address; `_history_match()`
   exists only to paper over it. → §6 rename.
3. `StatusRepository.__del__` closes a `Database` shared with `MessageStore` and
   `MessageCache`; whichever is deallocated first closes the connection out from
   under the others. → GRDB `DatabasePool`, no manual lifecycle.
4. Two overlapping caches (`message_cache` TTL + `messages`). → dropped.
5. `g.domain` is simultaneously group label, selection key, and table row key,
   and holds an email address for split groups. → explicit `GroupID`.
6. Hardcoded company alias table. → §7.
7. `synchronous=FULL` + `journal_mode=DELETE` on a rebuildable cache. → WAL.
8. Ignore is stored per-message, so new mail from an ignored sender reappears. → §6.

---

## 9a. Build status

**All milestones through the SwiftUI app are done** (updated 26 July 2026).
`Packages/NevermoreKit` builds under Swift 6 strict concurrency; **230 tests
pass**. The app is used daily against a live ~132,000-message mailbox.

Measured on that mailbox:

| Measured | Result |
|---|---|
| Full discovery (23 date windows) | ~14,600 UIDs located in ~95s |
| Header fetch | ~40s → ~12,300 stored after filtering own mail |
| Incremental sync | 40–50 new messages in ~3s |
| Grouping | ~12,300 messages → ~1,015 senders |
| Send-as aliases inferred | 5, matching the Python probe exactly |

Shipped since this plan was written, and not described above:

- **Demo mode** — a fabricated mailbox on a `MailBackend` implementation with
  no network code, reachable before onboarding. Also what an App Store reviewer
  uses to evaluate the app without an email account.
- **Reappearance detection** with notifications, the Unsubscribed history log,
  and the in-app browser escalation.
- **Keyboard triage** beyond the plan: `⇧U` (unsubscribe and delete, no
  confirm), `v` (open the newest message via Gmail's `rfc822msgid:`).
- **Release tooling** — `VERSION`, commit-count build numbers, a pre-migration
  database backup, and a version/tag guard in `notarize.sh`.

**Testing note:** tests run as an executable (`swift run nevermore-tests`) with
a small harness, not a `.testTarget`. SwiftPM builds test targets as `.xctest`
bundles on macOS, which needs XCTest and `_TestingInterop` from a full Xcode
install; neither is in Command Line Tools. Worth converting to swift-testing
alongside the Xcode app target that the Mac App Store requires — see
[MAS-RELEASE.md](MAS-RELEASE.md).

**Xcode is required** for the SwiftUI app; Command Line Tools alone cannot
build it. `swift build` fails without `DEVELOPER_DIR` pointing at Xcode.

## 10. Open questions

**Resolved:**

- ~~First-run discovery time~~ — a single unbounded `SEARCH` exceeds SwiftMail's
  60s command timeout and fails outright. Discovery runs in 23 one-year date
  windows, newest first, with adaptive halving. ~95s with real progress, and it
  removed the X-GM-RAW fork from the critical path entirely.
- ~~Incremental sync strategy~~ — `SearchCriteria.uid(N)` encodes a *single*
  UID, not an open range, so "newer than N" isn't expressible. Incremental sync
  searches `.since(lastSync - 2 days)`; the overlap absorbs IMAP's
  day-granularity `SINCE`, and duplicate UIDs collapse on the primary key.
- ~~Workspace accounts~~ — an auth failure now prompts re-authentication with
  copy that names app-password policy as a likely cause.
- ~~Alias detection source~~ — `Delivered-To` was kept, falling back to `To`.
  Filter labels were not used; they only exist for users who happen to have set
  them up.

**Still open:**

- **Messages located but not stored.** Discovery finds more UIDs than the store
  keeps. Expected causes are the user's own sent mail and headers whose only
  target uses an unsupported scheme, but the split has never been measured.
  Worth instrumenting so the UI's counts can be explained.
- **`PayloadTooLargeError` root cause.** An incremental run once failed with
  this before two changes landed together — raising `responseBufferLimit` to
  32 MB and switching to date-based search. It hasn't recurred, but **which fix
  was responsible is unknown.** If it returns, resolve that ambiguity first.
- **Body-only unsubscribes are invisible.** Discovery matches on the
  `List-Unsubscribe` header, so a sender who only puts a link in the message
  body is never seen — and "delete this sender's mail" therefore means "the
  subset carrying the header". Closing the gap means either reading bodies
  (which the app's whole premise forbids) or a sender-wide `SEARCH FROM` delete
  that removes mail the app never displayed. Deliberately not done.
- **DNS rebinding beats `DestinationGuard`.** It resolves the host, then
  URLSession resolves independently, so a hostile resolver can answer public
  then private. A real fix pins the validated IP and sets the `Host` header.
- **Undo-trash always restores to INBOX.** IMAP has no "put it back where it
  was", so a message that was archived returns to the inbox.
- **Concurrent IMAP connections.** Gmail throttles (commonly cited as ~15,
  unverified). Sync is single-connection, so this only matters if a parallel
  fetch path is ever added. Measure before parallelizing.
