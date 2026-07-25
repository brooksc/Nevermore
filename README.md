# Nevermore

A native macOS app for finding and bulk-unsubscribing from newsletters.

Nevermore syncs the *headers* of every message carrying a `List-Unsubscribe`
header into a local database, groups them by sender, and lets you unsubscribe
from or trash whole senders in a few keystrokes. It never downloads message
bodies, and it never sends your data anywhere except directly to the
unsubscribe endpoint the sender published.

The name is the point: senders that keep mailing after you unsubscribe get
flagged and shut down for good.

> **Status:** working, but pre-release. Not yet on the Mac App Store. Built and
> used against a real ~132,000-message mailbox.

## Why another one of these

Most unsubscribe tools are web services that ask for OAuth access to your
mailbox and then read it on their servers. Unroll.me famously sold the results.
Nevermore is the opposite shape:

- **Local-first.** Everything runs on your Mac. There is no server, no account
  to create, and no telemetry. Your header cache is a SQLite file in
  Application Support; your password lives in the macOS Keychain.
- **Headers only.** It reads `From`, `Subject`, `Date`, `List-Unsubscribe`, and
  a few others. It never fetches a message body.
- **Honest about outcomes.** Unsubscribing is not verifiable in the general
  case. Nevermore distinguishes *requested* from *confirmed* rather than
  claiming success it can't prove — and it tells you when a sender ignores you.
- **No OAuth.** It signs in over plain IMAP with an app-specific password, so
  there's no Google Cloud project to create and no consent screen to click
  through.

## Features

- **Any IMAP provider.** Gmail, iCloud, Yahoo, Fastmail, and AOL are detected
  from your address; custom domains pick their provider. Folders are discovered
  at connect via the IMAP SPECIAL-USE extension rather than hard-coded.
- **Fast sync.** Header-only fetch runs at roughly 1,000 messages/second.
- **Smart grouping.** Senders are grouped by registrable domain (eTLD+1), with
  shared platforms split per newsletter so every Substack doesn't collapse into
  one row. You can override with *Split by Address* / *Keep as One Group*.
- **Full RFC 2369 / 8058 chain.** One-click `POST` where offered, then `GET`,
  then `mailto:`, then a built-in browser for senders that publish nothing
  usable.
- **Reappearance detection.** If a sender mails you again after a recorded
  unsubscribe, it surfaces in a dedicated collection with a notification.
- **Keyboard triage.** `j`/`k` to move, `u` unsubscribe, `i` ignore, `d` trash,
  `?` for the full list. Ignore and trash advance to the next sender.
- **Trash with undo.** Messages move to your provider's Trash and `⌘Z` puts
  them back.
- **Alias-aware.** Send-as addresses are inferred from your Sent folder, so
  `mailto:` unsubscribes go out from the address the mail was delivered to.
- **Multi-account**, with per-account databases.

## Requirements

- macOS 14 or later
- Xcode 26 (or matching Swift 6 toolchain) to build
- An app-specific password for your mail account

## Build

```bash
cd Packages/NevermoreKit
swift build                       # build everything
swift run nevermore-tests         # run the test suite (70 tests)
./make-app.sh release             # produce a signed Nevermore.app
```

`make-app.sh` wraps the SwiftPM executable into a proper `.app` bundle. It
signs with the first Developer ID Application certificate it finds; set
`NEVERMORE_SIGN_IDENTITY` to choose one explicitly. Signing with a stable
identity matters — an ad-hoc signature changes every build, which invalidates
the Keychain ACL on the saved password.

To build with the App Sandbox enabled (as the Mac App Store requires):

```bash
NEVERMORE_SANDBOX=1 ./make-app.sh release
```

Note the sandbox relocates Application Support into the app container, so a
sandboxed build starts with no accounts. See [MAS-RELEASE.md](MAS-RELEASE.md).

## Setup

1. Turn on two-factor authentication for your mail account.
2. Create an app-specific password (Nevermore links you to the right page for
   your provider).
3. Enter your address and that password. It goes straight to the Keychain.

macOS will ask permission the first time Nevermore reads its own Keychain item.
Choose **Always Allow** so it stops asking.

## Architecture

```
Packages/NevermoreKit/
├── Sources/
│   ├── NevermoreKit/          # no SwiftUI — domain logic, testable headless
│   │   ├── Domain/            # value types + pure logic, zero I/O
│   │   ├── Backend/           # MailBackend protocol, IMAP implementation
│   │   ├── Unsubscribe/       # RFC 2369/8058 engine, SSRF destination guard
│   │   ├── Store/             # GRDB/SQLite header cache
│   │   └── Credentials/       # Keychain, account registry
│   ├── NevermoreApp/          # SwiftUI app: views, sheets, AppModel
│   └── Probe/                 # CLI harness for live-mailbox testing
└── Tests/NevermoreTests/
```

`NevermoreKit` must not import SwiftUI — the domain logic stays testable
without launching a UI.

Design documents: [PLAN.md](PLAN.md) for architecture decisions and
[UI_SPEC.md](UI_SPEC.md) for the interface brief. Both are design-time
snapshots and have drifted from the code in places; this README and the source
are authoritative.

## Security

The app acts on data written by strangers — a `List-Unsubscribe` header is
attacker-authored input that drives outbound network requests and email. It's
built accordingly:

- **SSRF guard.** Unsubscribe URLs are resolved and rejected unless they point
  at a public, global-unicast address, so a sender can't aim a request at
  `localhost`, your LAN, or a cloud metadata endpoint. Redirects are
  re-validated at every hop.
- **Header-injection defense.** `mailto:` values are percent-decoded, so
  control characters are stripped and the subject is RFC 2047-encoded
  unconditionally; recipients must be a single well-formed address.
- **STARTTLS required** when sending, so a stripped capability can't downgrade
  the session and leak your password in cleartext.
- **Device-bound credential.** The app password is stored
  `WhenUnlockedThisDeviceOnly`, so it can't ride a backup to another machine.

Found something? Open an issue — or email if it's sensitive.

## License

Not yet chosen.
