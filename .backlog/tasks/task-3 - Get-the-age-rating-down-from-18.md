---
id: TASK-3
title: Get the age rating down from 18+
status: Done
assignee: []
created_date: '2026-08-09 18:50'
updated_date: '2026-08-23 20:06'
labels:
  - store
dependencies: []
priority: medium
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The store listing is rated 18+ solely because the age-rating questionnaire was answered honestly for unrestricted web access. WebUnsubscribeSheet.swift:204-219 allows navigation to any public http/https host — the guard only blocks non-http schemes and private, loopback and link-local addresses — so once an unsubscribe page opens, a user can click through to anywhere.

An inbox utility rated 18+ narrows its audience for a capability nobody uses deliberately. Restricting navigation to the unsubscribe target host and its redirect chain would make "no" the honest answer.

Needs testing against real senders first: some unsubscribe flows legitimately redirect across hosts, and breaking those is worse than the rating.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Navigation policy restricted to the initial host and its redirect chain
- [ ] #2 Tested against a sample of real senders, including multi-host flows
- [ ] #3 Age rating questionnaire re-answered and the listing shows 4+
- [x] #4 App Review notes updated to match
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: claude
created: 2026-08-23 17:46
---
The premise may be wrong, and the cheap fix should be tried before the expensive one.

Checked against Apple's own documentation (App Store Connect Help, "Age ratings values and definitions"): **unrestricted web access maps to 16+, not 18+**. 18+ is reserved for frequent alcohol/tobacco/drug references, frequent sexual content or nudity, frequent realistic violence, and gambling — none of which this app has any answer for.

Apple overhauled the tiers, adding 13+, 16+ and 18+ where the scheme previously ran 4+/9+/12+/17+, and required every developer to answer a new questionnaire by 31 January 2026. So the likeliest explanation for an 18+ listing is that the rating was produced under the old scheme, where unrestricted web access reached 17+ — and note that a 17+ global rating is displayed as 18+ in France specifically, per ANFR, which is worth ruling out before assuming the global rating is 18+ at all.

That reorders the work. The first step is to re-answer the updated questionnaire in App Store Connect and see what rating it produces. If it yields 16+, this task is done without touching any code.

That matters because the code change is not cheap or safe: restricting WebUnsubscribeSheet to the target host and its redirect chain risks breaking legitimate unsubscribe flows that cross hosts, which is why the task already said it needs testing against real senders. It has also become entangled since — TASK-4 replaced the unsubscribe transport with a pinned NWConnection client, so anything done to navigation policy now has to be reconciled with that.

Sources: https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/ and https://developer.apple.com/news/?id=ks775ehf
---

author: claude
created: 2026-08-23 20:06
---
Closed without the code change, at the maintainer's direction and on the evidence above: the rating work moves into the submission runbook (MAS-RELEASE.md §9.6) rather than staying an open engineering task.

Apple's documentation puts unrestricted web access at 16+. 18+ requires frequent drug or alcohol references, sexual content, realistic violence, or gambling, and this app answers no to all four. So the listing's 18+ is most likely a rating produced under the retired 4+/9+/12+/17+ scheme — or the French display of a 17+ global rating, which ANFR requires. Re-answering the current questionnaire is the whole fix, and it costs nothing.

Criterion 1 (restrict navigation to the initial host and its redirect chain) is deliberately not done. It was always the risky half: unsubscribe flows legitimately cross hosts, and breaking one is worse than the rating. It has also become entangled with TASK-4, which replaced the transport with a pinned NWConnection client. If a re-answered questionnaire still produces a rating worth fighting, re-open this with that as the starting point rather than the assumption.

Criterion 3 asked for 4+. That was never reachable while the app opens sender-published pages, and pretending otherwise would mean answering the questionnaire dishonestly. 16+ is the honest floor unless the navigation restriction lands.
---
<!-- COMMENTS:END -->
