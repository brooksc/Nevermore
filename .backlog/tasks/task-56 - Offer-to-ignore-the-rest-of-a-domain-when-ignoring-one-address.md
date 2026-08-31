---
id: TASK-56
title: Offer to ignore the rest of a domain when ignoring one address
status: Done
assignee: []
created_date: '2026-08-31 18:04'
updated_date: '2026-08-31 18:17'
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
- [x] #2 The offer never appears for a shared sending platform, so ignoring one newsletter cannot silence the rest
- [x] #3 The offer never appears when there is nothing else to ignore on that domain
- [ ] #4 Accepting is undoable by the same route as any other ignore
- [ ] #5 Declining is respected rather than re-asked on every subsequent sender from that domain
- [x] #6 The rule for which senders the offer would cover is in NevermoreKit and tested, including the shared-platform exclusion
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented on branch `task-56-fix` (worktree `.worktrees/task-56`), not merged.

**The rule lives in NevermoreKit.** `Domain/DomainIgnoreOffer.swift` decides which senders the offer covers and what it says. It is nil unless the ignored row is an address group, the registrable domain is offerable, the domain has not already been declined, and at least one un-ignored sibling remains. `GroupID.registrableDomain` (new, in `EmailMessage.swift`) is what makes `citicards@info11.citi.com` and `clientexperience@citi.com` agree on `citi.com`; `AppModel.domain(of:)` now delegates to it instead of keeping its own copy.

**Shared platforms are excluded by asking `Grouping`, not by keeping a second list.** `Grouping.isSharedSendingPlatform(_:)` is a new public accessor over the existing `sharedSendingPlatforms` set, so the offer and the grouping can never disagree about what a platform is. Note this exclusion is *only* the platform list: a domain that split into rows because its display names differ — `costco.com`, `chase.com` — is not a platform and is exactly the case this exists for.

**Presentation** is the existing ignore toast, which now carries both Undo and the offer button. `StatusBarView` previously rendered `undo` *or* `action`; that `else if` became an `if`, because an ignore that also asks about the domain must not lose its Undo to the question. Accepting calls `AppModel.ignore` again, so it produces an ordinary ignore with an ordinary undo (AC #4) rather than a widening that could only be taken back row by row. Offered only off a single-row ignore — a multi-row sweep has no single "the other senders".

### The two decisions

**A declined offer is remembered, per mailbox, on disk.** `MessageStore.declinedDomainIgnores()` / `declineDomainIgnore(_:)` store the set as JSON in `syncState`, beside the grouping rules — the same mechanism, and per-account for the same reason: a domain worth widening in one mailbox need not be in another. It survives relaunch (tested by reopening the file). A decline is taken when the offer's toast goes away unaccepted — dismissed, replaced, or expired — and *not* when the ignore itself is undone, since undoing takes back the premise of the question.

**One remaining sender is still worth asking about.** A threshold of two was considered and rejected: most of the leaks measured in the real mailbox (chase, citi, apple, meta, lhh) were a single sibling host, so a threshold of two would have suppressed the clearest cases there were. The copy handles the singular.

### Verification

`swift build` clean; `swift test` → **570 tests in 97 suites passed** (560/96 on main). New: `@Suite("DomainIgnoreOffer")` (8 tests) plus two `MessageStore` persistence tests.

- AC #2 checked — `never offers to widen an ignore across a shared sending platform` names Substack explicitly, with three Substack publications across two hosts, and then sweeps beehiiv/mcsv/sendgrid/ghost.
- AC #3 checked — `makes no offer when there is nothing else on the domain`, covering both a lone sender and a domain whose siblings are all already ignored; plus `never offers off a domain group`.
- AC #6 checked — the rule is `DomainIgnoreOffer` in NevermoreKit and is what the suite exercises.
- AC #1 **left unchecked**: the rule and the copy are tested (the question and the button both name the domain and the count), but that the toast actually appears on screen is app-target and has no test. Compile-verified only.
- AC #4 **left unchecked** for the same reason: accepting routes through `ignore`, which is the undoable path, but nothing exercises the button.
- AC #5 **left unchecked**: that a declined domain is suppressed, and that the decline survives a relaunch, are both tested; that the decline is *recorded* when the toast expires or is dismissed is app-target and untested.

The app was not launched (shared machine), so nothing here is confirmed by eye.

### Concern

Taking a decline on toast *expiry* is the one debatable call. It means a user who simply looked away never sees the question for that company again. The alternative — re-offering until answered — is the nag the task explicitly rejects, and the offer is a convenience rather than the only route (the sibling rows can still be selected and ignored by hand). Worth a second opinion, and easy to change: it is one `retirePendingOffer()` call in the expiry path.
<!-- SECTION:NOTES:END -->
