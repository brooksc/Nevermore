---
id: TASK-30
title: Warn when unsubscribing would confirm the address to a spammer
status: To Do
assignee: []
created_date: '2026-08-10 01:49'
labels:
  - security
dependencies:
  - TASK-28
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Unsubscribing from real spam is worse than doing nothing: it proves a human read the message and the address is live. Every unsubscribe tool encourages the click anyway, because the click is the product.

Nevermore can do the opposite, and only because it reads headers. Authentication-Results carries the SPF, DKIM and DMARC verdicts the provider already computed. A sender failing DMARC, or whose unsubscribe target has nothing to do with the sending domain, is one to trash and ignore rather than ask politely.

No web service will copy this, and it is honest in the way the rest of the app tries to be: the app telling you not to use its main feature.

Care needed: the verdict is the provider's and only covers the hop into your mailbox, and legitimate senders fail DMARC through misconfiguration all the time. So it advises, never blocks.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Authentication-Results fetched, parsed and stored per sender
- [ ] #2 Failing senders flagged in the inspector with an explanation
- [ ] #3 Advice is trash and ignore rather than unsubscribe, and never acts on its own
- [ ] #4 Sending domain versus unsubscribe target mismatch flagged too
- [ ] #5 Copy makes clear the verdict came from the mail provider
<!-- AC:END -->
