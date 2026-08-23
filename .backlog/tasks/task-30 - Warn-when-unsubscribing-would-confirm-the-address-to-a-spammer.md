---
id: TASK-30
title: Warn when unsubscribing would confirm the address to a spammer
status: Done
assignee:
  - task-30-spammer
created_date: '2026-08-10 01:49'
updated_date: '2026-08-23 03:33'
labels:
  - security
dependencies:
  - TASK-36
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
- [x] #3 Advice is trash and ignore rather than unsubscribe, and never acts on its own
- [x] #4 Sending domain versus unsubscribe target mismatch flagged too
- [x] #5 Copy makes clear the verdict came from the mail provider
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## The local-verdict-versus-agent decision (TASK-52 left this open)

**The local verdict may veto an unsubscribe, and may never mint one.**
Implemented as `SenderTrustVerdict.recommendation(given:)`, tested five ways.

The rule is asymmetric because the evidence is. A provider verdict that a sender
cannot be verified, or an unsubscribe link that resolves to a shortener, is
evidence *against* that sender. The same checks coming back clean are evidence
of nothing at all — a spammer who publishes SPF and DKIM for their own throwaway
domain passes DMARC on the first try, routinely. So a clean read must never talk
over an agent that read the content and said "cold outreach, ignore it": the
agent knows something the headers cannot show.

In the other direction the app wins, because it knows something the agent does
not — no MCP tool exposes `Authentication-Results` or the unsubscribe target's
host. Where they disagree *about unsubscribing*, the side holding evidence the
other could not have is the side to follow, and it is also the side arguing for
the reversible action. The agent's reason is never replaced: the badge says what
to do, a second line under it says the app overrode the agent and why, and the
agent's own sentence stays verbatim above it.

## What was built

Two sources of evidence, kept apart because their costs differ:

**Needs no new fetch, live now** — where the unsubscribe would actually go,
read from `List-Unsubscribe`, which the app already stores whole.
- *strong*: link behind a URL shortener; link at a bare IPv4/IPv6 literal;
  `mailto:` addressed to a free consumer mailbox rather than a list manager.
- *advisory*: target on a registrable domain unrelated to the sender's (AC #4).
  Advisory and nothing more — handing unsubscribes to a bulk-mail platform is
  how most legitimate mail works, and the platform list will never be complete.

**Needs the fetch TASK-36 has to price** — `Authentication-Results` (RFC 8601).
Parser, storage column, roll-up and copy are all built and tested; the field is
not in the sync's header list. `SyncHeaderFields.fetchesAuthenticationResults`
is `false`, and a test asserts it is, so a green suite cannot be read as a claim
that the app is fetching it.

Only *strong* findings change a recommendation. That split is the whole design:
a warning that fires on ordinary mail teaches people to click through the one
that matters.

False-positive work, each with a test:
- A DMARC failure is strong only when *every* checked message failed. Some
  failing among passes is the shape of forwarded mail, and is advisory.
- A mailing list that fails throughout is advisory: lists break DMARC by
  rewriting what they forward.
- SPF and DKIM are read only together, and only where no DMARC verdict exists.
- A verdict whose `header.from` is a different registrable domain is discarded
  rather than attributed to this sender.
- The mismatch check excuses the sender's own domain and subdomains, the same
  brand on another public suffix, the mailing list's own domain, and the known
  platform lists.

UI: findings appear in the inspector above the actions (AC #2), each naming who
found it and what it does not cover (AC #5), and closing with a suggestion to
Ignore — or Trash if the mail is not wanted either — plus "nothing here stops
you: the button still works" (AC #3). Nothing is disabled and nothing acts.

Per TASK-52's binding decision this adds **no second warning surface**: the
verdict renders through TASK-52's recommendation slot, and its objections go
into TASK-52's existing override dialog. `mayUnsubscribeFromProposal` became
`mayUnsubscribe` and now carries both parties' objections in one list, one line
per sender. `ProposalOverrideWarning`'s closing paragraph was extracted so both
callers share it rather than keeping two copies.

## Verification

`swift build && swift run nevermore-tests` — **479 passed, 0 failed**
(434 before; 45 new). No existing test was edited.

- **AC #1 — parsed and stored: checked. Fetched: NOT done, deliberately.**
  Parser tested against real-shaped Gmail headers (pass and fail), comment
  stripping with nested parens and embedded `;`/`=`, folded headers, multiple
  DKIM signatures, `method/version`, `none`, several concatenated headers.
  Storage round-trips through `MessageStore` (migration `v6-authentication-results`),
  including that a re-sync with the switch off does not erase a stored verdict.
  The fetch is one Boolean in `SyncHeaderFields`, off until TASK-36 measures it.
- **AC #2 — logic checked, appearance not.** Every finding's weight, wording
  and roll-up is tested. `InspectorView` compiles and is unreviewed: views
  cannot be reached from the harness and the GUI was not launched (shared
  machine).
- **AC #3 — checked.** Tested that a strong verdict yields `.ignore` and never
  `.unsubscribe`, that it never upgrades an agent's ignore/trash, that advisory
  findings change nothing, and that the copy says ignore-or-trash. Nothing in
  this change calls an action; the strongest thing it does is raise a
  confirmation that can be answered yes.
- **AC #4 — checked.** Flagged, advisory, with both domains named; and eight
  legitimate shapes tested to *not* flag.
- **AC #5 — checked.** The strong authentication finding names the `authserv-id`
  verbatim and says "not Nevermore's"; the dialog line attributes the objection
  to "Nevermore, from the message headers".

## Not verified

- Any real `Authentication-Results` header from a real mailbox. Every sample is
  hand-written from the RFC and from the shape Gmail emits.
- Whether the strong unsubscribe-target rules fire on real mail at the rate
  expected. The riskiest is the consumer-mailbox rule: a one-person newsletter
  whose homemade tooling points `List-Unsubscribe` at its author's Gmail would
  be flagged. Judged acceptable because the advice is reversible and the button
  still works — but it is a judgement, not a measurement.
- Anything on screen.

Docs updated: `README.md` (Features), `UI_SPEC.md` §6, `CHANGELOG.md`
Unreleased. The changelog entry claims only what ships — it does not mention
DMARC, because the fetch is off.
<!-- SECTION:NOTES:END -->
