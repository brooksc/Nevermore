# Changelog

All notable changes to Nevermore are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows
[RELEASE.md](RELEASE.md).

## [Unreleased]

### Added

- **Guided app-password setup, for the provider you actually use.** The sign-in
  screen now asks for the credential by your provider's own name — an
  app-specific password on iCloud, an app password on Gmail — mentions
  two-factor authentication only where the provider requires it first, and links
  to a step-by-step page for that provider. There is a page for Gmail, iCloud,
  Yahoo, Fastmail, AOL, and one for custom domains, on the support site so they
  can be corrected when a provider moves the setting.
- **A failed sign-in says what usually causes it.** Providers reject your
  ordinary account password with exactly the same error as a mistyped app
  password, so "authentication failed" sent people back to retype the one thing
  that cannot work. The message now names the app-password policy as the likely
  cause and links the guide for that provider.
- **Demo mode seeds an unsubscribe history**, so Reappeared is no longer always
  empty for someone meeting the app through the demo.
- **An MCP server, so an AI assistant can help you triage senders.** Off by
  default, direct-download builds only. Nevermore listens on 127.0.0.1 and a
  `nevermore-mcp` bridge connects your assistant to it. The assistant can read
  your senders — names, addresses, subject lines, counts and read rates — and
  record what it decided about each one and why, under a label like
  `job-search-2026` that Nevermore stores but never interprets. Ask it later
  what can go now that a situation has ended.
- **A Proposed collection** where an assistant's suggestions wait for you. It
  appears only when something is in it, shows the assistant's reason on every
  row, and acts on nothing until you say so. Every row leads with the action the
  assistant recommends — unsubscribe, ignore or trash — and its button does that
  thing, so an assistant telling you *not* to unsubscribe from a cold sender is
  no longer a sentence competing with a button that says otherwise.
  Unsubscribing anyway is still yours to do; you are asked first, with the
  assistant's reason in front of you.
- **A browser queue**, so the senders that publish only a web form can be worked
  through in one sitting instead of one at a time.

### Changed

- **The Help menu now points at help.** It links the FAQ, the app-password
  guides, the privacy policy and support — all pages on the site rather than
  files in a source repository, so they read properly without a GitHub account
  and can be corrected without shipping a new build. Reporting a problem now
  goes to the support page and its email address instead of an issue tracker
  that asked you to sign up first.

### Notes

- **There is no bulk unsubscribe over MCP, and there will not be one.**
  Unsubscribing is irreversible and goes to a third party, so a set of senders
  is unsubscribed only after you have reviewed that exact set in Nevermore and
  confirmed it, and that confirmation is bound to those senders, good once, and
  expires. An assistant proposes; you decide.
- Trashing a sender's messages on an assistant's behalf always asks you first,
  even below the threshold that lets your own trash go through silently.
- Connecting an assistant sends sender names and subject lines to that
  assistant's AI model, which may be cloud-hosted. Nothing else about the app
  changes: still no server, no account, no telemetry. See [PRIVACY.md](PRIVACY.md).
- The Mac App Store build does not include any of this. The sandbox there
  permits outgoing connections only, so the local server cannot run.

### Fixed

- **An unsubscribe link can no longer be aimed at your own network.** Nevermore
  already refused to send to a private or local address, but it checked the
  address and then let the system look the name up a second time to open the
  connection — so a sender who controls their own DNS could answer with a public
  address for the check and your router for the connection. The address that
  passes the check is now the address the connection goes to, on every redirect
  hop as well. Certificate checking is untouched: HTTPS connections are still
  verified against the real hostname, and a wrong, expired or self-signed
  certificate is still refused.
- **Undo of a trash puts archived mail back in the archive.** On Gmail,
  Nevermore finds newsletters wherever they are, including ones you had already
  archived — but undo moved everything to the inbox, so an action labelled Undo
  dumped read-and-filed mail back into the inbox. Nevermore now records whether
  each message was in the inbox at the moment it was trashed, and restores it
  where it was. Gmail *labels* are not restored: the move to Trash removes them
  and IMAP offers no way to put them back, so a labelled, archived message comes
  back archived and unlabelled. Other providers are unaffected — Nevermore only
  ever sees their inbox, so the inbox was always the right answer there.


## [1.0.0] — 2026-08-01

First Mac App Store release, and the version number catching up to what the app
is. Per [RELEASE.md](RELEASE.md), 1.0 means no known data-loss bugs and a
verified sandboxed build — both now true. The app is unchanged from 0.1.1
beyond what's below.

### Added

- A Mac App Store build, generated by Tuist from `Project.swift`: sandboxed,
  signed with Apple Distribution, and containing no updater — Sparkle ships in
  the direct-download build only, as Apple requires.
- A support page at <https://brooksc.github.io/Nevermore/support.html> with an
  email address, so getting help never requires a GitHub account.

### Changed

- The App Store listing is "Nevermore Mail Cleanup"; "Nevermore" was already
  taken. The app itself is still Nevermore.

## [0.1.1] — 2026-08-01

Packaging and documentation. No change to how the app behaves.

### Fixed

- The app inside the DMG carried no stapled notarization ticket — only the
  image did. An update installed by Sparkle on a machine that was offline or
  behind a filter could stall at launch while Gatekeeper tried to reach Apple.
  `make-dmg.sh` now notarizes and staples the app before packaging it.

### Changed

- The privacy policy is published at
  <https://brooksc.github.io/Nevermore/privacy.html> and the site links there
  rather than to a file on GitHub.
- The privacy policy said the app had "no update server". The direct-download
  build carries Sparkle, which fetches an appcast from GitHub Pages, so the
  policy now describes that request and what it does and doesn't reveal.

### Added

- `./run` builds the app from source and launches it, for development.

## [0.1.0] — 2026-07-26

First public release. Universal binary for Apple Silicon and Intel, macOS 14+.

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
- Mailing-list detection via RFC 2919 `List-ID`, so a discussion list or
  notification stream is distinguishable from a marketing blast before you
  unsubscribe.
- Gmail conversations open directly from the app, and webmail links route to the
  right account rather than whichever Google account signed in first.
- In-app updates via Sparkle (direct download build only; the Mac App Store
  build has no updater, as Apple requires).

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

[Unreleased]: https://github.com/brooksc/Nevermore/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/brooksc/Nevermore/releases/tag/v1.0.0
[0.1.1]: https://github.com/brooksc/Nevermore/releases/tag/v0.1.1
[0.1.0]: https://github.com/brooksc/Nevermore/releases/tag/v0.1.0
