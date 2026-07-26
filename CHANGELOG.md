# Changelog

All notable changes to Nevermore are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows
[RELEASE.md](RELEASE.md).

## [Unreleased]

Everything below is pre-release work leading to 0.1.0, which has not shipped.

### Added

- Any IMAP provider — Gmail, iCloud, Yahoo, Fastmail, AOL detected from the
  address; custom domains pick a provider. Folders discovered via SPECIAL-USE.
- Sender grouping by registrable domain, with shared sending platforms split
  per newsletter, and per-domain *Split by Address* / *Keep as One Group*.
- Full RFC 2369 / 8058 unsubscribe chain: one-click `POST`, `GET`, `mailto:`,
  then a built-in browser.
- Reappearance detection, with a notification when a sender mails again after
  a recorded unsubscribe.
- Trash with undo, alias-aware `mailto:` sending, and multi-account support.
- **Demo mode** — a fabricated sample mailbox reachable before entering any
  credentials and from Settings, running on a backend containing no network
  code, so nothing in it can reach a server.
- **Help ▸ How Nevermore Works**, also shown during the first sync, including
  an honest list of what the app cannot find.
- Keyboard triage: `j`/`k` move, `u` unsubscribe, `⇧U` unsubscribe and delete
  with no confirmation, `v` open the newest message in the browser, `i` ignore,
  `d` trash, `?` for the full list. Every action advances to the next sender.
- Hidden debug tools (double-click the version in Settings) to reset app state
  for repeated onboarding tests.
- Pre-migration database backup before any new schema migration runs.
- `VERSION` file and commit-count build numbers written into the bundle.

### Fixed

- The onboarding sheet awaited the entire first sync, leaving a large mailbox
  on "Verifying…" for minutes with the progress display hidden behind it.
- Trash sent one IMAP `MOVE` for every UID; over a thousand messages timed out
  and moved nothing. Now batched, with partial success reported.
- "Full Resync" ran an incremental sync, which can add rows but never retire
  them, so it could not reconcile a deletion made elsewhere.
- Only the first unsubscribe target was stored, and `mailto:` targets lost
  their query string — discarding the per-recipient token many senders rely on.
- A blocked SSRF redirect was recorded as a successful unsubscribe.
- The in-app browser had no navigation policy, so a sender-authored URL could
  walk it to any host or scheme.
- The unsubscribe chain stopped at the first web target instead of falling back
  to `mailto:`.
- Multi-row actions left the selection on a row that had just been removed.
- Toasts and their undo never expired, leaving ⌘Z armed indefinitely.
- Sender labels could change between launches.
- An authenticated SMTP connection leaked on every failed send.
- Layout: the first-run screen's ideal height was miscalculated, pushing the
  sidebar and status bar thousands of points off-screen.

### Removed

- The "new senders to review" notification and its setting. It fired on
  ordinary incoming mail, which is noise for a tool opened deliberately.
  Reappearance notifications remain.

### Security

- SSRF guard on every sender-supplied URL: the silent request, each redirect
  hop, the in-app browser, and the unsubscribe-history "Manage" link.
- Header-injection defence on `mailto:` unsubscribes; STARTTLS required when
  sending; app password stored `WhenUnlockedThisDeviceOnly`.

[Unreleased]: https://github.com/brooksc/nevermore
