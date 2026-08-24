---
id: TASK-34
title: Menu-bar mode for triaging new senders
status: On Hold
assignee: []
created_date: '2026-08-10 01:49'
updated_date: '2026-08-24 03:02'
labels:
  - product
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The app is opened deliberately, which means new senders accumulate silently between sessions. A menu-bar item — "3 new senders this week" — turns it into something ambient, and triaging three senders does not warrant a window.

Keep it small: what is new, unsubscribe or ignore, open the app for anything else.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Menu bar item showing senders new since last visit
- [ ] #2 Unsubscribe and ignore available without opening the main window
- [ ] #3 Optional, and off by default
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-08-24 03:02
---
Parked, and the reason is now on the record from the maintainer rather than inferred: "I see this app as something I periodically run when I'm annoyed by too much irrelevant email."

That is the whole answer. A menu-bar extra is for a tool you want ambient awareness from continuously; this is a tool you open on purpose when a problem has become annoying enough to act on. Making it ambient would be arguing with how it is actually used.

It also matches the decision already in UI_SPEC §2 — no menu-bar-extra in v1, revisit only if users ask — which nobody has. And the app has since gained several surfaces it did not have then (Proposed, the browser queue, the Settings local-server section, Shortcuts), which is an argument for fewer new ones.

If the specific gap ever bites — new senders piling up unnoticed between sessions — extending the reappearance notification that already exists is the cheaper answer and does not reverse a recorded decision.
---
<!-- COMMENTS:END -->
