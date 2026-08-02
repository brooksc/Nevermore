# Privacy Policy

**Nevermore for macOS**
_Last updated: 1 August 2026_

## The short version

Nevermore has no servers. It collects nothing, transmits nothing to its
developer, and contains no analytics, telemetry, crash reporting, or
advertising of any kind. Your mail, your credentials, and everything the app
derives from them stay on your Mac.

There is no account to create, because there is nothing to create it with.

## What the app accesses

Nevermore connects directly from your Mac to **your mail provider** over IMAP,
using an app-specific password you supply.

It reads **message headers only** — never message bodies. Specifically:

| Field | Why |
|---|---|
| `From` | To identify and group senders |
| `Subject` | To show you what a sender sends |
| `Date` | To sort and show recency |
| `List-Unsubscribe`, `List-Unsubscribe-Post` | The unsubscribe method itself |
| `List-ID`, `Auto-Submitted`, `Precedence` | Bulk-mail signals |
| `Delivered-To` / `To` | So a `mailto:` unsubscribe is sent from the address the mail was delivered to |
| `Message-ID` | To find a message again in Trash if you undo, and to open it in webmail |

Headers are fetched with IMAP `BODY.PEEK`, which means **reading them does not
mark your mail as read**.

## What is stored, and where

Everything is on your Mac:

- **Header cache** — a SQLite database in
  `~/Library/Application Support/Nevermore/` (inside the app's sandbox
  container for Mac App Store builds), one per account. It holds the fields
  above, plus your unsubscribe history, ignored senders, and grouping
  corrections.
- **App password** — in the **macOS Keychain**, stored
  `WhenUnlockedThisDeviceOnly`, so it cannot ride a backup or Migration
  Assistant transfer to another machine. Nevermore never writes it to disk in
  the clear and never logs it.
- **Preferences** — ordinary macOS user defaults (appearance, sync interval,
  and similar).

Deleting the app's Application Support folder erases the cache. Removing an
account from Settings deletes both its database and its Keychain item.

## What leaves your Mac

Three things, all of them direct and all of them initiated by you:

1. **Your mail provider.** IMAP connections to fetch headers and to move
   messages to Trash, and SMTP to send a `mailto:` unsubscribe. STARTTLS is
   required for sending, so the session cannot be downgraded to cleartext.
2. **The sender's unsubscribe endpoint.** When you unsubscribe, Nevermore
   contacts the address that sender published in their own `List-Unsubscribe`
   header — an HTTP request, or an email sent from your account. Nothing beyond
   what the unsubscribe requires is included.
3. **A web page you choose to open.** The in-app browser and the "view this
   message" and "manage preferences" links open pages at your request. The
   in-app browser uses a non-persistent data store, so it never reads or writes
   your normal browser's cookies.

Nevermore never contacts the developer. There is no licence check and no
"phone home".

## Software updates

The version downloaded directly from GitHub checks for updates using
[Sparkle](https://sparkle-project.org), which fetches a static file —
`appcast.xml` — from the project's GitHub Pages site. That request carries
nothing identifying beyond what any web request carries: your IP address and the
app's user agent, logged by GitHub under [their privacy
statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement),
not by the developer. No account, licence, install ID, or usage data is sent,
and the developer has no access to those logs.

The Mac App Store version contains no updater at all — Apple's rules forbid it,
and Sparkle is compiled out of that build. It updates through the App Store like
any other app.

The first time you run it, the app asks whether to check for updates
automatically. Decline and it makes no outbound request of its own at all, until
you pick **Check for Updates…** from the Help menu yourself.

## Third parties

The developer shares your information with nobody, because the developer never
receives it.

Unsubscribe endpoints belong to the senders who published them and are governed
by those senders' own privacy policies — Nevermore has no relationship with
them and no control over what they log when you unsubscribe. Contacting them is
the point of the app, and it happens only when you ask.

If you obtained Nevermore from the Mac App Store, Apple's own policies cover
your purchase and download; the developer receives only Apple's standard
aggregate sales reporting, which contains no personal information.

## Logging and diagnostics

Nevermore writes to the standard macOS unified log. Those entries stay on your
Mac. Sender addresses and domains appear in them, because diagnosing an
unsubscribe failure requires knowing which sender failed. **Message contents
and your password are never logged.**

Settings ▸ Advanced ▸ Export Diagnostics writes a copy of the app's own recent
log entries to a file, so that you can inspect it and choose whether to share
it when reporting a problem. Nothing is sent anywhere automatically.

## Children

Nevermore is not directed at children and collects no information from anyone.

## Your rights

Because nothing is collected, there is no data held about you to access,
correct, export, or delete — and no account to close. Everything the app knows
is in the files described above, on your own machine, under your control.

## Changes

Material changes to this policy will be noted in the app's release notes and
reflected in the "last updated" date above. Previous versions remain in the
project's Git history.

## Contact

Questions about this policy, or about the app's handling of your data: open an
issue on the project's GitHub repository.
