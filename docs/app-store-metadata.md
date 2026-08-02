# App Store listing copy

_Draft, 1 August 2026. Not yet submitted._

Everything App Store Connect asks for, kept here so a submission is a paste job
rather than a writing job, and so the next version can be diffed against the
last one. Character limits are Apple's and are counted, not estimated.

---

## Name (≤30)

```
Nevermore
```

`Nevermore` is 9 characters. App Store names are unique — if it's taken, the
fallback is `Nevermore: Unsubscribe` (22), which keeps the searchable word.

## Subtitle (≤30)

```
Bulk-unsubscribe, privately
```

27 characters. The subtitle is indexed for search, so it carries "unsubscribe"
rather than repeating the app name.

## Promotional text (≤170)

Editable at any time without a new review — use it for anything time-sensitive.

```
Sort your inbox by who keeps mailing you, then unsubscribe from dozens of
senders in a few keystrokes. Nothing leaves your Mac but the unsubscribe
itself.
```

154 characters.

## Keywords (≤100, comma-separated, no spaces after commas)

Apple already indexes the name and subtitle, so nothing in them is repeated
here. Singular forms match plurals.

```
newsletter,email,inbox,cleanup,imap,gmail,icloud,fastmail,spam,junk,mailbox,privacy,local,declutter
```

99 characters. Count again after any edit — this one is at the limit.

## Description (≤4000)

```
Nevermore finds every newsletter in your mailbox and lets you unsubscribe from
them in bulk, without handing your mail to anyone.

It reads the headers of your messages over IMAP, groups them by sender, and
shows you who mails you most. Unsubscribing from a sender takes one keystroke.
So does trashing everything they have ever sent you.

EVERYTHING STAYS ON YOUR MAC

There is no server, no account, and no telemetry. Your header cache is an
ordinary database file on your disk and your app password lives in the macOS
Keychain. The developer has no way to see your mail, because there is nowhere
for it to go.

IT NEVER READS YOUR MAIL

Nevermore fetches message headers only — sender, subject, date, and the
unsubscribe headers — and never downloads a message body. It uses IMAP
BODY.PEEK, so reading them does not even mark your mail as read.

BUILT FOR THE KEYBOARD

Move with j and k. Unsubscribe with u. Trash with d. Open the newest message
with v. Every action moves you to the next sender, so a hundred newsletters is
a few minutes of triage rather than an afternoon.

IT CATCHES THE ONES THAT COME BACK

Senders who keep mailing after you unsubscribe show up in Reappeared, with a
count of what has arrived since. From there you can finish the job by hand in
the built-in browser, or trash and ignore them for good. That is what the name
is about.

HONEST ABOUT WHAT IT CANNOT DO

Unsubscribing cannot be verified in general. An endpoint can return success and
keep mailing you. Nevermore says "requested" when it sent the request and
"confirmed" only when you saw a confirmation page yourself — it will not claim
a result it cannot prove.

Deleting moves messages to your provider's Trash, where they stay under that
provider's retention and you can restore them. The app never issues an IMAP
EXPUNGE, so it has no way to destroy mail permanently. Small batches undo in
the app with Command-Z.

It finds newsletters by the standard List-Unsubscribe header, which nearly all
legitimate bulk mail carries. A sender who only puts an unsubscribe link in the
body of the message is invisible to it. Finding those would mean reading your
mail, which is the thing this app does not do.

WORKS WITH ANY IMAP PROVIDER

Gmail, iCloud, Yahoo, Fastmail, and AOL are detected from your address, and
custom domains pick their provider. Folders are discovered from the server
rather than assumed, so unusual setups work too.

TRY IT BEFORE YOU TRUST IT

The first screen offers a demo: a complete sample mailbox with every button
live and no credentials required. It runs on a backend containing no network
code at all, so nothing in demo mode can reach a server.

Requires macOS 14 or later. Universal, for Apple Silicon and Intel.
```

2,730 characters — comfortably inside the limit, with room to grow.

The em dashes here are fine; the `<`/`>` rule below is specific to the What's
New field. If a Description paste is ever rejected for invalid characters,
strip them anyway and re-paste rather than hunting for the culprit.

## What's New (per version, plain text)

Rewritten every submission. Two rules that are easy to get wrong:

1. **Never use `<` or `>`.** App Store Connect reads them as HTML and rejects
   the whole field with only "This field contains one or more invalid
   characters" — it names neither the character nor the position. This cost the
   jobhunt project three rejections on a single submission.
2. Cover **every** version since the last one that shipped to the store, not
   just the newest. The store skips releases the DMG channel shipped.

Check before pasting:

```bash
python3 - <<'EOF'
text = open('/tmp/whats-new.txt').read()
bad = [(i, c) for i, c in enumerate(text) if c in '<>' or ord(c) > 127]
print(f"{len(text)} chars")
print("offenders:", bad if bad else "none")
EOF
```

Draft for the first submission:

```
First release on the Mac App Store.

Nevermore finds the newsletters in your mailbox, groups them by sender, and
lets you unsubscribe from or delete whole senders in a few keystrokes. It
reads message headers only, keeps everything on your Mac, and flags the
senders that keep mailing you after you unsubscribe.
```

## URLs

| Field | Value |
|---|---|
| Marketing URL | `https://brooksc.github.io/Nevermore/` |
| Support URL | `https://github.com/brooksc/Nevermore/issues` |
| Privacy Policy URL | `https://brooksc.github.io/Nevermore/privacy.html` |

## Categorization

| Field | Value |
|---|---|
| Primary category | Productivity |
| Secondary category | Utilities |
| Age rating | 4+ |
| Copyright | `© 2026 Brooks Cutter` |

The primary category must match `LSApplicationCategoryType` in `Project.swift`
(`public.app-category.productivity`).

**Age rating questionnaire:** the app has a built-in browser that opens pages
chosen by mail senders. Answer the unrestricted-web-access question honestly —
it does not force a higher rating on its own, but a wrong answer here is the
kind of thing that gets caught later.

## Privacy nutrition label

**Data collected: none.** Not "collected but not linked" — none.

There is no server, no account, no analytics, and no crash reporting. The app
talks to exactly two kinds of destination, both chosen by the user: their own
mail provider, and the unsubscribe endpoint a sender published in their own
message. Neither is the developer, and neither receives anything beyond what
the operation itself requires.

Nothing is tracked, so there is no tracking disclosure.

Expect a reviewer to push back on this — a mail app that collects nothing reads
as too good to be true. The answer is in [PRIVACY.md](../PRIVACY.md) and the
architecture backs it: there is no code that can send anything anywhere else.

## Screenshots

`docs/screenshots/` holds four at 2880×1800, which is a size the store accepts
as-is. They use the built-in demo mailbox, so no real address appears in any of
them — worth keeping true for every future screenshot.

## App Review notes

See [MAS-RELEASE.md](../MAS-RELEASE.md) §10 for the text. Lead with demo mode:
it is how a reviewer evaluates the app without owning a mail account, which
removes the most common reason a tool like this gets rejected.

---

## Before each submission

- [ ] Version in App Store Connect matches `Packages/NevermoreKit/VERSION`.
- [ ] Build number is higher than the last upload (`git rev-list --count HEAD`).
- [ ] "What's New" passes the checker above and mentions no DMG-only or Sparkle
      features — they do not exist in the store build.
- [ ] `CHANGELOG.md` updated.
- [ ] Screenshots still show the current UI.
