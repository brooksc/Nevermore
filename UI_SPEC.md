# MailScrub for macOS — UI Specification

A brief for designing the interface. Written against Apple's macOS Human
Interface Guidelines and the Tahoe (macOS 26) design system.

Companion document: [PLAN.md](PLAN.md) for architecture. The Python TUI
predecessor whose functionality this must match or beat lived in `py/` (since
removed; the original is its own repo).

---

## 1. Product in one paragraph

Gmail accumulates hundreds of newsletters. MailScrub syncs the *headers* of
every message carrying a `List-Unsubscribe` header into a local database,
groups them by sender, and lets you unsubscribe from or delete whole senders in
bulk. It never downloads message bodies and never sends data anywhere except
directly to the unsubscribe endpoint the sender published.

**The core loop:** sync → scan a ranked list of senders → select several →
unsubscribe and/or delete → confirm it worked.

**Real data from the target account** (use for sizing and realistic mockups):
~132,000 messages in the mailbox, ~14,700 carrying `List-Unsubscribe`, grouped
into roughly 130–800 senders depending on filter. The top sender has ~290
messages; the long tail is senders with 1–3. **79% of messages support RFC 8058
one-click unsubscribe**; the rest need a web page visit or a `mailto:`.

---

## 2. Archetype and window model

**Archetype: library + detail.** Sidebar of collections, a table of senders,
an inspector for the selected sender. This is the Mail/Photos/Music shape, and
users already know it.

**Window model:**

- **One main window**, resizable, remembers frame and column widths.
- Supports **multiple windows** (`⌘N` opens another window on the same account —
  useful for comparing two filters side by side) and **window tabbing**.
- **Settings** is a separate window opened with `⌘,` from the App menu.
- **Onboarding** is a sheet on the main window, not a separate window.
- Minimum window size **900 × 560**. Below ~1000pt wide the inspector
  auto-collapses; below ~760pt the sidebar auto-collapses to an overlay.

**No menu-bar-extra in v1.** Background sync with a Notification Center alert
covers the same need without asking the user to manage a second surface. Revisit
only if users ask.

---

## 3. Layout

```
┌──────────────────────────────────────────────────────────────────────────┐
│ ●●●  MailScrub          [search field]        ⟳  ⊘  🗑  ⋯   [inspector] │  toolbar
├────────────────┬──────────────────────────────────┬──────────────────────┤
│ INBOX          │ Sender          Latest Subject   │  ┌────┐              │
│  All Senders   │ ─────────────────────────────────│  │ 🅐 │ Acme News    │
│  Unsubscri… ⁴¹²│ Acme News       Spring sale…  128│  └────┘ news@acme.com│
│  Manual only ⁸⁸│ Substack: Bob   Weekly digest  47│                      │
│                │ GitHub          [security]     31│  128 messages        │
│ ATTENTION      │ …                                │  92% unread          │
│  Reappeared  ³ │                                  │  Newest 2h ago       │
│                │                                  │  ──────────────────  │
│ ARCHIVE        │                                  │  One-click available │
│  Unsubscribed⁶⁷│                                  │  ──────────────────  │
│  Ignored     ¹²│                                  │  Recent messages     │
│                │                                  │   • Spring sale  2h  │
│                │                                  │   • New arrivals 1d  │
├────────────────┴──────────────────────────────────┴──────────────────────┤
│ 412 senders · 8,204 messages · Last synced 4 minutes ago                  │  status
└──────────────────────────────────────────────────────────────────────────┘
```

**Three columns**, `NavigationSplitView`:

| Region | Width | Notes |
|---|---|---|
| Sidebar | 200 default, 180–280 | Collapsible (`⌥⌘S`) |
| Sender table | flexible, ≥ 420 | The content layer |
| Inspector | 280 default, 260–400 | Collapsible (`⌥⌘I`), hidden by default on first launch |

**Liquid Glass:** toolbar and sidebar are system-provided glass — do not add
custom backgrounds. **The table is the content layer: no glass, no translucency,
no decorative borders.** Do not stack glass on glass. Express hierarchy in the
table through typography and spacing only.

---

## 4. Sidebar

A `List` with `Section`s. Items are stable and scannable; counts are trailing
secondary-styled numbers. No action buttons live here.

**INBOX**
- **All Senders** — everything not ignored (`house`)
- **Unsubscribable** — senders with a `List-Unsubscribe` target (`envelope.open`)
- **Manual only** — senders lacking a target; these need a browser visit (`hand.raised`)

**ATTENTION** — section hidden entirely when empty
- **Reappeared** — senders that kept mailing after a successful unsubscribe
  (`exclamationmark.triangle`). Badge uses the accent color, not red: this is
  notable, not an error.

**ARCHIVE**
- **Unsubscribed** — history, with outcome state (`checkmark.circle`)
- **Ignored** — hidden locally, never touched in Gmail (`eye.slash`)

**Multiple accounts:** when more than one is configured, add a top-level
account section above INBOX with each address as a row; the collections below
reflect the selected account. With a single account, show no account chrome at
all.

---

## 5. Sender table

The heart of the app. Use SwiftUI `Table` so sorting, column resizing, column
reordering, and the header context menu all come for free.

### Selection: native, not checkboxes

**Use standard macOS multi-selection** — click, `⇧`-click for ranges,
`⌘`-click to toggle, `⌘A` for all. **Do not add a checkbox column.** The Python
TUI needed one because terminals have no selection model; on Mac a checkbox
column is non-native and steals horizontal space. Bulk actions operate on the
current selection.

The selection count drives the toolbar and status bar: *"3 senders selected ·
214 messages"*.

### Columns

| Column | Default | Content | Sortable |
|---|---|---|---|
| **Sender** | 240 | Display name, bold if any unread. Second line: email address in secondary, `.caption`. | ✓ name |
| **Latest Subject** | flexible | Most recent subject, truncated with tail ellipsis. Secondary color. | ✗ |
| **Messages** | 90 | Count, right-aligned, monospaced digits. | ✓ (default, descending) |
| **Unread** | 80 | Percentage with a thin horizontal bar. Never color alone — show the number too. | ✓ |
| **Last Received** | 120 | Relative ("2h ago", "3d ago", "Mar 4"). Full date in tooltip. | ✓ |
| **Unsubscribe** | 44 | Icon only, see below. | ✓ by method |

**Unsubscribe method icons** (with VoiceOver labels and tooltips):

- `bolt.circle.fill` — **One-click** (RFC 8058 POST). "One-click unsubscribe available."
- `link.circle` — **Web link** (HTTP GET). "Unsubscribe by visiting a web page."
- `envelope.circle` — **Email** (`mailto:`). "Unsubscribe by sending an email."
- `hand.raised.circle` — **Manual** (no header). "No unsubscribe link — opens Gmail search."

Default sort: Messages descending. Row height ~44pt to fit the two-line sender
cell. Alternating row backgrounds on.

### Row interactions

| Interaction | Result |
|---|---|
| Single click | Select; inspector updates |
| Double click | Open sender detail (expands inspector if collapsed) |
| `↑` `↓` | Move selection |
| `⌥` double-click | Open this sender's mail in Gmail in the browser |
| Right click | Context menu (below) |
| Drag | Not supported in v1 |

### Row context menu

Mirrors the Actions menu, scoped to the clicked row (or the whole selection if
the clicked row is part of it):

```
Unsubscribe                    ⌘U
Unsubscribe and Delete…        ⇧⌘U
─────────────────────────────────
Ignore Sender                  ⌘I
Move Messages to Trash…        ⌘⌫
─────────────────────────────────
View in Gmail                  ⌘G
Copy Sender Address            ⌘C
─────────────────────────────────
Merge with…
Split by Address
```

**Merge / Split** expose the grouping override described in PLAN.md §7 — when
the automatic grouping gets a sender wrong, the user corrects it here instead of
filing a bug.

---

## 6. Inspector

Selected-sender detail. When multiple senders are selected, show an aggregate
summary instead ("3 senders · 214 messages · all support one-click") and the
same action buttons.

Sections, top to bottom:

1. **Identity** — sender avatar (monogram fallback on a tinted circle), display
   name in `.title3`, address in `.caption` secondary, with a copy affordance.
2. **Statistics** — message count, unread percentage, first-seen and
   last-received dates.
3. **Unsubscribe method** — icon + plain-language explanation of what pressing
   Unsubscribe will actually do. This is where the app is honest: *"Sends a
   one-click request directly to Acme. No page will open."* vs *"Opens Acme's
   unsubscribe page — you may need to confirm there."*
4. **History** — if previously unsubscribed: date and outcome
   (Requested / Confirmed / Failed), plus a **Forget** button to clear the record.
5. **Recent messages** — last 10 subjects with dates. Each row has a context
   menu with *View in Gmail* and *Move to Trash*. This is a capability the TUI
   never had: acting on individual messages rather than whole senders.
6. **Actions** — `Unsubscribe` (prominent, tinted), `Ignore`, `Trash Messages`.

---

## 7. Toolbar

Deliberately sparse — a crowded toolbar is a signal to demote. Grouped by
function, secondary actions in an overflow menu. No custom backgrounds.

| Position | Item | Symbol | Notes |
|---|---|---|---|
| Leading | Sidebar toggle | `sidebar.leading` | System-provided |
| Center | **Search** | `magnifyingglass` | `.searchable`, filters by name/address/subject |
| Trailing | **Sync** | `arrow.clockwise` | Becomes a determinate progress ring during sync |
| Trailing | **Unsubscribe** | `envelope.open` | Primary, tinted. Disabled with no selection. |
| Trailing | **Ignore** | `eye.slash` | Disabled with no selection |
| Trailing | **Trash** | `trash` | Disabled with no selection |
| Trailing | Overflow `⋯` | `ellipsis.circle` | Unsubscribe and Delete, View in Gmail, Merge/Split, Export CSV |
| Trailing | Inspector toggle | `sidebar.trailing` | System-provided |

Do not place a text button adjacent to an icon button — under the current design
system they read as a single control.

---

## 8. Menu bar

Every feature must be reachable here. Items enable/disable based on selection.

**MailScrub**
`About MailScrub` · `Check for Updates…` · `Settings… ⌘,` · Services · Hide/Quit

**File**
`New Window ⌘N` · `Add Account…` · `Sync Now ⌘R` · `Full Resync…` ·
`Export Sender List… ⇧⌘E` · `Close Window ⌘W`

**Edit**
Standard `Undo ⌘Z` / `Redo ⇧⌘Z` / Cut / Copy / Paste · `Select All ⌘A` ·
`Deselect All ⇧⌘A` · `Find ⌘F`

**Actions** *(custom menu — the app's verbs)*
`Unsubscribe ⌘U` · `Unsubscribe and Delete… ⇧⌘U` ·
`Ignore Sender ⌘I` · `Unignore ⇧⌘I` ·
`Move Messages to Trash… ⌘⌫` ·
`Forget Unsubscribe Record` ·
`Merge with…` · `Split by Address` ·
`View in Gmail ⌘G`

**View**
`All Senders ⌘1` · `Unsubscribable ⌘2` · `Manual Only ⌘3` · `Reappeared ⌘4` ·
`Unsubscribed ⌘5` · `Ignored ⌘6` ·
`Sort By ▸` (Messages / Sender / Unread / Last Received) ·
`Show Only Unread` · `Toggle Sidebar ⌥⌘S` · `Toggle Inspector ⌥⌘I` ·
Enter Full Screen

**Window** — standard, with tabbing.

**Help** — `MailScrub Help`, `Privacy and Data Handling`, `Report an Issue…`.

### Shortcut summary

`⌘R` sync · `⌘U` unsubscribe · `⇧⌘U` unsubscribe + delete · `⌘I` ignore ·
`⌘⌫` trash · `⌘G` view in Gmail · `⌘F` search · `⌘1`–`⌘6` collections ·
`⌘Z` undo · `⌥⌘S` sidebar · `⌥⌘I` inspector · `⌘,` settings

Never override standard shortcuts. `⌘⌫` for trash matches Finder.

---

## 9. Sheets, alerts, and dialogs

### 9.1 Onboarding — Add Account

A sheet, shown automatically on first launch. Three steps, one sheet, no wizard
chrome — the whole thing should fit in one view without scrolling.

1. **Explain** — one short paragraph: MailScrub reads message headers only,
   stores them on this Mac, and needs a Gmail app password.
2. **Get the password** — numbered steps with a `Link` to
   `myaccount.google.com/apppasswords`, noting 2-Step Verification is required.
3. **Enter** — email `TextField` + app password `SecureField`. Accept the
   space-separated 16-character form Google displays and strip spaces silently.

**States:** idle → validating (spinner, fields disabled) → success (sheet
dismisses, sync begins) → failure (inline error below the field, fields stay
populated).

**Failure text must distinguish the real causes**, because the generic Google
error is useless: wrong password; 2-Step Verification not enabled; *app
passwords disabled by a Workspace administrator*; network unreachable.

### 9.2 Unsubscribe confirmation

`confirmationDialog` for 1–3 senders; a sheet with a scrollable list beyond that.

- **Title:** "Unsubscribe from 3 senders?"
- **Body:** the sender list, plus a per-method breakdown: *"2 use one-click. 1
  will open a web page."*
- **Alias warning** where the mail was delivered to a non-primary address:
  *"Will send as you@example.com"*, or, if that address has no verified
  send-as alias, a caution that the request may be rejected.
- **Buttons:** `Unsubscribe` (default) · `Unsubscribe and Delete Messages` ·
  `Cancel`. Verbs, never Yes/No.

### 9.3 Unsubscribe progress

Sheet with a determinate `ProgressView`, current sender name, and `Cancel`.
Cancel must stop before the *next* sender, never mid-request. Completed senders
stay done — this is not transactional and the UI shouldn't imply it is.

### 9.4 Unsubscribe results

Replaces the progress sheet when finished. This screen is where MailScrub is
honest about a hard truth: **an HTTP 200 does not prove an unsubscribe worked.**

Group results into three lists:

- **Confirmed** — the endpoint positively acknowledged. `checkmark.circle.fill`.
- **Requested** — accepted, unverifiable. `clock.badge.questionmark`. Copy:
  *"Sent. If mail continues, they'll show up under Reappeared."*
- **Failed** — with the reason and a `Retry` button.

Footer: `Delete messages from confirmed senders` and `Done`.

### 9.5 Web unsubscribe sheet

For senders whose target is a plain link needing human confirmation. A `WKWebView`
in a sheet, 900 × 700, with the sender name in the title and a `Done` button.

This is the single biggest upgrade over the TUI, which could only shell out to a
browser tab and hope. Watch for navigation to a success URL or confirmation text
and offer to mark the result **Confirmed**.

Privacy: use a non-persistent data store so unsubscribe pages can't read or
write cookies belonging to the user's real browser session.

### 9.6 Trash confirmation

Trashing is **recoverable** (messages go to Gmail's Trash, and `⌘Z` untrashes),
so do not nag. Confirm only when the selection exceeds ~500 messages; otherwise
act immediately and show an undo affordance in the status bar for ~10 seconds.

### 9.7 Ignore

No confirmation. Act immediately, show *"Ignored Acme News. Undo"* in the status
bar. Ignoring is local-only and trivially reversible.

### 9.8 Reappeared senders

Shown as a **collection in the sidebar**, not a modal on launch. The Python
version interrupted startup with a dialog; that is hostile. Badge the sidebar
item and let the user come to it.

The collection view leads with an explanatory banner: *"These senders kept
emailing after you unsubscribed. They may have ignored the request."* Row
actions: `Unsubscribe Again`, `Trash and Ignore`, `Forget Record`.

### 9.9 Errors

Inline where recoverable — a banner above the table with a `Retry` button, not
an alert. Reserve alerts for genuinely modal problems (credentials invalidated
mid-session). Never surface a raw IMAP or SMTP error string; map to plain
language and put the technical detail behind a disclosure triangle.

---

## 10. Empty and transitional states

Every one needs an SF Symbol, a headline, one line of explanation, and — where
useful — a button.

| State | Symbol | Headline | Action |
|---|---|---|---|
| No account | `envelope.badge.person.crop` | "Connect your Gmail account" | `Add Account…` |
| First sync running | — | Determinate progress, "Reading message headers… 4,200 of 14,682" + a note that only headers are downloaded | `Cancel` |
| No messages found | `tray` | "No newsletters found" | `Sync Now` |
| All processed | `checkmark.seal` | "You're all caught up" | `Show Ignored` |
| Search: no results | `magnifyingglass` | "No senders match '\(query)'" | `Clear Search` |
| Ignored: empty | `eye.slash` | "No ignored senders" | — |
| Reappeared: empty | `checkmark.shield` | "Everyone honored your unsubscribes" | — |
| Offline | `wifi.slash` | "No internet connection" | `Retry` |

**First sync deserves care.** It takes ~90 seconds on a large mailbox and is the
user's first impression. Show real progress, state plainly that only headers are
read, and — importantly — let the table populate progressively as results arrive
rather than blocking on the whole run.

---

## 11. Settings (`⌘,`)

Standard `TabView` settings window, four tabs, sized to content.

**General** — appearance (System/Light/Dark) · confirm-before-unsubscribe
toggle · confirm-before-trash threshold · show `Unsubscribe and Delete` as the
default action.

**Accounts** — account list with add/remove · per-account sync status · re-enter
app password · `Open Google App Passwords` link.

**Sync** — sync on launch · background sync interval (Off / 15m / 1h / Daily) ·
notify on new senders · `Full Resync…` (destructive, confirm) · database size
with `Reveal in Finder`.

**Advanced** — grouping overrides table (add/edit/remove host → group) · export
diagnostics · verbose logging toggle · `Reset All Grouping Overrides`.

---

## 12. Status bar

A single row at the bottom of the window. Three zones:

- **Leading:** counts — "412 senders · 8,204 messages", or the selection summary
  when something is selected.
- **Center:** transient messages with an `Undo` button, auto-dismissing after
  ~10 seconds.
- **Trailing:** "Last synced 4 minutes ago", or live sync progress.

---

## 13. Undo

`⌘Z` must work for: **Ignore**, **Unignore**, **Trash** (untrashes in Gmail),
and **Forget unsubscribe record**.

`Unsubscribe` is **not undoable** — the request has left the building. Say so in
the confirmation dialog rather than offering a false affordance.

---

## 14. Motion

Restrained. Table row insertion/removal animates; collection switches
cross-fade; the sync button's progress ring animates continuously. The
unsubscribe results sheet may stagger its row reveals slightly — this is the one
moment worth a small flourish.

All of it must respect **Reduce Motion**: cross-fades become instant, the
progress ring becomes a static indeterminate bar.

---

## 15. Accessibility

Non-negotiable, designed in rather than retrofitted.

- **VoiceOver:** every table row reads as a sentence — *"Acme News, 128
  messages, 92 percent unread, last received 2 hours ago, one-click unsubscribe
  available."* Method icons carry labels, never meaning by shape alone.
- **Keyboard-only:** the entire core loop — sync, navigate, select, unsubscribe,
  confirm — must be completable without a pointer. Focus rings on every custom
  control; logical tab order in every sheet.
- **Color:** unread percentage shows a number as well as a bar. Outcome states
  pair an icon with text. Nothing is conveyed by hue alone.
- **Contrast / Reduce Transparency:** the app must stay fully usable; the system
  handles Liquid Glass adaptation, but verify custom content.
- **Dynamic Type:** the two-line sender cell must not clip at larger sizes —
  allow the row to grow.

---

## 16. Screens to design

In priority order:

1. Main window — populated, nothing selected
2. Main window — multi-selection with toolbar active
3. Main window — inspector open on a selected sender
4. Onboarding sheet — all three states (entry, validating, error)
5. First-run sync progress
6. Unsubscribe confirmation (small and large variants)
7. Unsubscribe progress
8. Unsubscribe results — mixed confirmed/requested/failed
9. Web unsubscribe sheet
10. Reappeared collection with banner
11. Ignored collection
12. Empty states (the table in §10)
13. Settings — all four tabs
14. Search active with results
15. Error banner
16. App icon — layered, tested across Default/Dark/Clear/Tinted

**Icon direction:** the name suggests scrubbing, but a literal brush is a
cliché. Consider an envelope with something being lifted or peeled away — the
idea is *removal*, not cleaning. Must stay legible in monochrome at 16pt, so
keep to two or three shapes and set one key element to white.

---

## 17. Explicit non-goals for v1

Naming them so the design doesn't drift:

- No reading of message bodies, and therefore no message preview pane.
- No composing or replying.
- No rules or filter automation.
- No analytics dashboard or charts.
- No iOS companion.
- No provider other than Gmail.
