---
id: TASK-56
title: Offer to ignore the rest of a domain when ignoring one address
status: To Do
assignee: []
created_date: '2026-08-31 18:04'
updated_date: '2026-08-31 18:05'
labels:
  - ui
  - product
dependencies: []
priority: high
type: feature
ordinal: 22000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reported from use: senders that were ignored keep arriving under a different address at the same company.

Ignoring keys on whatever the row is. A domain group stores `domain:costco.com`; an address group stores `address:order-refund@costco.com`. Both already work — the maintainer's own store holds 38 address ignores and 29 domain ignores — so the capability exists and the gap is that nothing offers the wider one at the moment it is obviously wanted.

Measured against the real mailbox, these are all still arriving on sibling hosts of something already ignored:

- chase@mcmap.chase.com, against an ignore on chase.com
- retailresearch@insideapple.apple.com, against apple.com
- careerservices2@email.lhh.com, against lhh.com
- noreply@meta-ai.meta.com, against meta.com
- citicards@info11.citi.com, against citi.com — the clearest case, since clientexperience.citi.com was unsubscribed the same week
- three separate costco.com addresses

Not every sibling is a leak. Shared platforms are deliberately split per newsletter, so each Substack is its own row and ignoring one must not silence the rest. Any rule here has to leave that alone; several apparent leaks in the data were Substack behaving exactly as intended.

**The shape: an offer, not a second menu item.** "Ignore this domain" sitting permanently next to "Ignore" is one mis-click from silencing gmail.com or substack.com, and the damage is invisible — mail simply stops appearing. Instead, when an address group is ignored and the app can see other senders sharing its registrable domain, ask once, with the count and the domain named: *"Also ignore the other 3 senders at costco.com?"* A real question at the moment it is obviously right, answered from evidence the app already has.

That is the same posture as the Proposed collection and the smart selections: propose, never assume. The user pressed `i` on one sender; widening that to a whole company without asking would be the app acting on its own inference.

Worth deciding as part of this: whether the offer should appear at all for a domain the app knows is a shared platform, and whether declining it should be remembered so the same question is not asked every time another address from that company appears.</description>
<parameter name="acceptanceCriteriaSet">["Ignoring an address group offers to ignore the other senders on the same registrable domain, naming the domain and the count", "The offer never appears for a shared sending platform, so ignoring one newsletter cannot silence the rest", "The offer never appears when there is nothing else to ignore on that domain", "Accepting is undoable by the same route as any other ignore", "Declining is respected rather than re-asked on every subsequent sender from that domain", "The rule for which senders the offer would cover is in NevermoreKit and tested, including the shared-platform exclusion"]
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Ignoring an address group offers to ignore the other senders on the same registrable domain, naming the domain and the count
- [ ] #2 The offer never appears for a shared sending platform, so ignoring one newsletter cannot silence the rest
- [ ] #3 The offer never appears when there is nothing else to ignore on that domain
- [ ] #4 Accepting is undoable by the same route as any other ignore
- [ ] #5 Declining is respected rather than re-asked on every subsequent sender from that domain
- [ ] #6 The rule for which senders the offer would cover is in NevermoreKit and tested, including the shared-platform exclusion
<!-- AC:END -->
