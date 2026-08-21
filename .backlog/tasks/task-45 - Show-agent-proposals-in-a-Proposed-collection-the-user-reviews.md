---
id: TASK-45
title: Show agent proposals in a Proposed collection the user reviews
status: In Progress
assignee: []
created_date: '2026-08-20 21:19'
updated_date: '2026-08-20 22:40'
labels:
  - mcp
  - ui
dependencies:
  - TASK-41
  - TASK-27
  - TASK-44
priority: high
type: feature
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of TASK-41. This is where an agent's proposal becomes something a human can actually check, and it is the safety mechanism for the whole feature — everything else assumes this review is real.

A fifth sidebar collection, Proposed, holding the senders an agent has put forward. It reuses the existing sender table, inspector, multi-select and keyboard model, so Command-A, shift-click and per-row keys work as they already do. Not a sheet: a sheet is modal, blocks the app, cannot use keyboard triage, and the existing results sheet already has the hidden-scroll defect in TASK-28.

The row must show the agent's one-line reason. Reviewing twenty-five rows without seeing why each was picked is not review, it is rubber-stamping, and the reason is the only thing that makes an agent's judgement checkable. It belongs in the table, not buried in the inspector.

The collection appears only when it holds something, and disappears when cleared. Most users will never connect an MCP client, and a permanently visible empty collection is an advertisement for a feature they cannot use.

Proposals should survive an app restart: the agent session and the review session are naturally hours apart.

Note the ordering constraint against TASK-27 — Reappeared, Unsubscribed and Ignored do not currently share the selection model that All Senders has. Adding a sixth variant of selection handling before that is resolved would make the problem worse.

Sidebar shortcuts are positional, so inserting a collection renumbers the ones after it. UI_SPEC.md documents four collections and must be updated with whatever this becomes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Proposed appears in the sidebar only while it holds senders, and disappears when cleared
- [ ] #2 Rows show the agent's reason in the table itself
- [ ] #3 Selection, keyboard triage and multi-select behave exactly as in All Senders
- [x] #4 A proposal survives quitting and reopening the app
- [ ] #5 Dismissing a proposal clears it without acting on any sender
- [x] #6 UI_SPEC.md is updated for the new collection and any shortcut renumbering
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
`swift build` clean; `swift run nevermore-tests` → **250 passed, 0 failed**
(230 on main, 20 added).

### Which criteria I ticked, and what proved them

Only #4 and #6 are ticked. The tests link `NevermoreKit` only — not
`NevermoreApp` — so nothing in `AppModel` or a `View` can be run here, and
anything asserting on-screen behaviour is left unchecked on purpose. The GUI was
not launched (shared machine).

- **#1 unchecked.** The rule is implemented and readable —
  `AppModel.shows(.proposed)` is `proposal != nil`, `SidebarView` draws only
  `section.members.filter(model.shows)` and omits a section with no visible
  members, and ⌘5 disables itself the same way. What I cannot prove is that the
  row actually appears and disappears on screen, because `AppModel` isn't
  reachable from the harness. Needs a look in the running app.
- **#2 unchecked.** `ProposedCollectionView` puts `row.reason` in the row, in
  the widest column, two lines with the full text as its tooltip. That it
  *renders* legibly at the real column widths is unverified.
- **#3 unchecked.** The collection uses the same `List(selection:)`, the same
  `.selectionKeyboard(…)` and the same `AppModel.selection` as Ignored and
  Reappeared, and its action availability is tested to match All Senders
  exactly (`Proposed collection` suite). But "behaves exactly as in All Senders"
  is a claim about ⌘A, shift-click and j/k under a real first responder, which
  I did not run.
- **#4 ticked.** `Proposals survive a relaunch` writes a proposal through one
  `MessageStore`, closes it, opens a second store on the same file, and reads
  the proposal back with its summary, reason, sender address and timestamp
  intact. A second `MessageStore` on the same path is what a relaunch is, below
  the app. What is *not* proved by that test is the app-side reload — I did
  verify by reading that `reloadFromStore()` assigns `proposal = store.proposal()`
  on every load path, but that is inspection, not a run.
- **#5 unchecked as a UI claim, though the substance is tested.**
  `dismissing clears the proposal and acts on nothing` sets up an ignored
  sender, an unsubscribe record and a message, clears the proposal, and asserts
  all three are untouched. `AppModel.dismissProposal()` calls
  `store.clearProposal()` and nothing else. The unverified part is only that
  the button is wired to it.
- **#6 ticked.** UI_SPEC.md now carries the REVIEW section (§4), Proposed in
  the one-selection-model paragraph and the new `RowSource` note (§5), a §9.10
  on why it is a collection and not a sheet, the empty-state row (§10), and
  `⌘5` plus the corrected explanation of why appending rather than inserting
  keeps ⌘1–⌘4 fixed (§8). `KeyboardShortcutsView` and CLAUDE.md's docs map were
  corrected for the same reason.

### Decisions worth knowing about

- **Appended, not inserted.** `.proposed` is the last case in
  `SenderCollection.allCases`, so it takes ⌘5 and renumbers nothing. Its
  *sidebar* position is independent — a REVIEW section above ATTENTION — so it
  reads where it belongs while numbering last. Pinned by a test.
- **Membership is an overlay, not a state change.** A proposed sender is still
  in All Senders. Moving it out would be the app acting on the agent's say-so,
  which is the one thing this feature refuses to do. `.proposed` sorting last
  also means `MCPSnapshot.collection(of:)` keeps its old answer.
- **The `visibleIDs` special case is gone.** `AppModel.RowSource` is an
  exhaustive switch: a new collection now has to state where its rows come from
  or it won't compile.
- **One live proposal per account**, stored as JSON in `syncState` beside the
  grouping rules — read and written whole, never queried by field, so no table
  and no migration. It dies with the account, which is right: it names that
  mailbox's senders and carries an agent's free text about them.
- **Items are self-contained** (name and address, not just a group key), like
  `UnsubscribeRecord`, so a sender trashed between the proposal and the review
  still gets a reviewable row rather than silently vanishing from the set the
  agent sent.
- **Acting on a row does not remove it from the proposal.** The proposal is the
  durable record of what was proposed, which is what TASK-46's
  `get_proposal_status` will need to report against. The consequence is that
  Proposed is the one collection that can list a sender who is already done, so
  `SelectionContext` gained `alreadyUnsubscribed` and Proposed refuses a second
  unsubscribe — with Forget offered as the escape hatch its refusal names.
  Tested.
- **`list_senders(collection: "proposed")` is a 400**, not an empty list. A
  proposal lives in the running app, not in the database a snapshot is built
  from, and an empty list would read to an agent as "the human cleared it".
- **`SenderProposal.capped` caps at 25 and reports the drop count.** TASK-46
  owns the criterion; putting the constant and the truncation on the model is
  what gives that task something to call. It also dedupes before capping, so
  the cap counts senders rather than mentions.

### For TASK-46

- The seam is `AppModel.receiveProposal(_:)` — no HTTP route was added. It
  refuses in demo mode and when no store is open.
- `get_proposal_status` has no outcome record to read yet. The proposal knows
  what was proposed and `AppModel` knows what is left after edits, but nothing
  records *what happened* to a sender the user acted on. That is the piece
  TASK-46 has to add, and it is the reason I deliberately did not shrink the
  proposal as rows are worked.
- The review token has to bind to "the exact confirmed set". The set the user
  confirms is `model.selection` within `.proposed`, which is
  `Set<GroupID>`; the proposal is keyed by `GroupID.storageKey`. Same identity,
  two spellings — worth picking one before minting tokens against it.
- Grouping is mutable. If the user splits or merges a domain between the
  proposal and the confirmation, a stored `groupKey` no longer matches any
  group and its row shows with `sender == nil`. TASK-43 solved the same problem
  for decisions by keying on address; a review token bound to group keys will
  inherit this. Worth deciding deliberately rather than discovering.
<!-- SECTION:NOTES:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Recorded before coding. The test executable links `NevermoreKit` only — not
`NevermoreApp` — so anything in `AppModel` or a `View` is unprovable here. That
decides the split: put every rule in NevermoreKit and leave the app target as
wiring.

1. **`Domain/SenderProposal.swift`** (NevermoreKit). A `Codable` value: id,
   createdAt, optional one-line summary, and items of
   `(groupKey, senderName, senderEmail, reason)`. Self-contained like
   `UnsubscribeRecord`, so a row still renders after the sender's mail is gone.
   `capped(_:)` truncates at 25 and reports how many were dropped — the seam
   TASK-46's cap criterion sits on. `removing(_:)` returns nil when the last
   item goes, which is what makes the sidebar row disappear.
   → verify: harness suite on cap, truncation count, removal-to-empty.
2. **`senders(in:matching:)`** on the proposal: joins items to the current
   `[SenderGroup]`, preserving the agent's order, filtering on name/email/reason.
   A missing group yields a row with `group == nil` rather than dropping it.
   → verify: harness suite on order, search, missing sender.
3. **`SenderCollection.proposed`**, appended last so ⌘1–⌘4 do not renumber.
   `SenderState.isProposed`. Membership is an overlay, not a state transition:
   a proposed sender is still in All Senders, and `MCPSnapshot.collection(of:)`
   keeps its old answer because `.proposed` sorts last in `allCases`.
   Availability rules identical to `.allSenders`.
   → verify: extend the two existing suites.
4. **`MessageStore.proposal()` / `setProposal(_:)` / `clearProposal()`** — one
   live proposal per account, JSON in `syncState`, like `groupingRules`. No
   migration: nothing queries it by field.
   → verify: round-trip, and reopen the same file to prove it survives a quit.
5. **`AppModel`**: `proposal`, `receiveProposal(_:)` (the in-process seam
   TASK-46 drives; no HTTP route here), `dismissProposal()`, and
   `removeFromProposal(_:)`. Replace the `if collection == .unsubscribed`
   branch in `visibleIDs` with an exhaustive `rowSource` — a new collection
   cannot compile without stating where its rows come from.
6. **`ProposedCollectionView`** + `Tokens.swift` presentation + a REVIEW
   sidebar section shown only while a proposal exists, and `SidebarView`
   asking the model whether a collection shows rather than hard-coding
   Reappeared's rule.
7. **UI_SPEC.md** §4, §5, §8 for the fifth collection and ⌘5.
<!-- SECTION:PLAN:END -->
