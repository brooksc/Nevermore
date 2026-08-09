---
id: TASK-22
title: Let me re-read the latest message before deciding in Reappeared
status: To Do
assignee: []
created_date: '2026-08-09 19:11'
labels:
  - product
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reappeared is where the decision is hardest — escalate to a manual unsubscribe, or trash and ignore for good — and it is the one view that gives you nothing to decide with. The row shows the latest subject and three buttons: Unsubscribe in Browser, Trash and Ignore, Forget Record. There is no way to open the message and see what the sender is actually still sending.

Everywhere else this exists: v opens the newest message, viewLatestMessage() prefers Gmail's own conversation link via gmailThreadID and falls back to a provider web search, and it is in the Actions menu as View Latest Message.

Neither works here, and not just because the key is unbound: ReappearedCollectionView rows (CollectionViews.swift:104) never set model.selection, and viewLatestMessage() reads selection.first. So the existing menu item and shortcut silently do nothing from this view — a keyboard-first app with a dead end in it.

Demo mode already explains itself with a toast rather than opening anything, so that path is handled.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A View action on each Reappeared row, alongside the existing three buttons
- [ ] #2 Reappeared rows participate in selection, so Actions > View Latest Message and the v shortcut work there
- [ ] #3 Uses viewLatestMessage(), so Gmail opens the conversation and other providers fall back to search
- [ ] #4 Reachable by keyboard alone, matching the rest of the app
- [ ] #5 Demo mode still shows its explanatory toast rather than opening a browser
<!-- AC:END -->
