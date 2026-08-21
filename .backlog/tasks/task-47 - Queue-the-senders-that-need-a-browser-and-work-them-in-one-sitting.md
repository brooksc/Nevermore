---
id: TASK-47
title: 'Queue the senders that need a browser, and work them in one sitting'
status: In Progress
assignee: []
created_date: '2026-08-20 21:20'
updated_date: '2026-08-20 21:20'
labels:
  - mcp
  - ui
dependencies:
  - TASK-41
  - TASK-46
priority: medium
type: feature
ordinal: 13000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of TASK-41. Some senders publish only a web target, or return needsManual, and someone has to click through their page. Today that is one sender at a time, interleaved with everything else. When an agent has just triaged four hundred senders and thirty of them need a browser, doing them one at a time across the rest of the workflow is the part that does not scale.

Collect them into a queue the user works through in one sitting: open, complete, next. The existing WebUnsubscribeSheet already renders the page in a WKWebView with a non-persistent data store and watches for a likely confirmation, so the per-sender mechanics exist; what is missing is the sequence around them.

The agent can identify this set before attempting anything, from supportsOneClick and the target types on the parsed header, so the queue can be built up front rather than discovered through failures.

An agent must not be able to drive the browser sheet itself. It can queue senders and read what the human confirmed. The sheet is a human-in-the-loop step by construction, and that is not an implementation limit to be worked around.

TASK-23 is adjacent — offering to trash the backlog once a browser unsubscribe is confirmed — and the confirmation signal it needs is the same one this queue advances on. Worth building them together rather than twice.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Senders needing a browser can be queued from an agent proposal without attempting an unsubscribe first
- [ ] #2 The user can work the queue in sequence without returning to the sender list between each
- [ ] #3 Each completion records an outcome distinguishing a confirmed unsubscribe from an abandoned one
- [x] #4 An agent can read queue progress but cannot advance or drive the sheet
- [x] #5 Leaving the queue part-way keeps the remaining entries for later
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
The sequence lives in a value type in NevermoreKit, so everything except the
WKWebView itself is provable in the harness.

1. `Domain/BrowserQueue.swift` — an ordered, Codable list of entries
   (group key, sender name/email, the reason a browser is needed, and a
   terminal outcome once worked). `BrowserReason` is derived from
   `UnsubscribeMethod` + reappearance + the send-as problem, so membership is
   decided from stored headers before anything is attempted. Verify: harness
   suite over queueing, dedupe, `next`, recording, progress, Codable round trip.
2. Persist it in `MessageStore` under a `syncState` key, exactly as the
   proposal is (TASK-45). Verify: harness writes a queue, reopens the store,
   reads back the remaining entries.
3. `MCPActions` gains `queueForBrowser(senderIds:)` and
   `browserQueueStatus()`; `AgentActionOutcome` gains a `.browserQueue` case.
   Routes `/mcp/browser-queue/add` and `/mcp/browser-queue/status`, two tools in
   the catalog, both listed as unattended in the policy. Verify: harness drives
   the routes against `StubActions`, and asserts no route advances the queue.
4. `AppModel` holds the queue, builds entries (skipping senders that do not
   need a browser), hands out the next target, and records each outcome.
   `ManualUnsubscribe` gains the queue position and the message count.
5. `WebUnsubscribeSheet` becomes the sitting: one confirmation step with the
   delete offer (folding in TASK-23), then Next / Stop for Now. Stopping leaves
   the remaining entries pending.

Not verifiable headlessly: anything past the AppModel boundary — the sheet, the
menu command, the WKWebView. Stated as such rather than ticked.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built as planned. 309 tests pass (285 on main, plus 24 new); one existing test
was updated because it counts the tool surface — twenty tools became twenty-two.

**Per acceptance criterion, and what was actually run.**

- **#1 ticked.** `swift run nevermore-tests`, suite *Browser queue over MCP*:
  `/mcp/browser-queue/add` queues a set of sender ids and the stub records only
  `queue_for_browser` — no unsubscribe verb is reached — and suite *Who needs a
  browser* proves the set is decided from stored headers, the unsubscribe record
  and send-as knowledge rather than from a failure. `list_senders(needs_browser:
  true)` and `BrowserQueue.reason` are asserted to agree on every sender in a
  fixture mailbox, so an agent cannot select a set the queue then declines.
  Caveat recorded rather than hidden: queueing takes sender ids, which is what a
  proposal's rows are; there is no `queue_proposal` shorthand. And the app-side
  implementation (`AgentActions.queueForBrowser`, which is where the
  "doesn't need a browser, skipped" answer is produced) is in the app target and
  is not reachable from the harness — the route tests drive a stub.
- **#2 not verified.** The sequence lives in `WebUnsubscribeSheet` and
  `AppModel.nextBrowserTarget`. The sheet holds the current sender in state and
  swaps it rather than dismissing, so the user never returns to the list; that
  is a claim about a `WKWebView` sheet, and this task was done without launching
  the GUI on a shared machine. Nothing was run that proves it.
- **#3 not verified.** The *recording* is proven — `BrowserQueue` keeps
  confirmed, couldn't-unsubscribe and abandoned as three terminal outcomes, will
  not let a second answer overwrite the first, and the distinction survives both
  the store round trip and the MCP wire (`state`, `confirmed` counted separately
  from `worked`). What is not proven is that the sheet calls
  `recordBrowserOutcome` on each exit, which is UI code no headless test reaches.
- **#4 ticked.** Suite *Browser queue over MCP*: after the stub's queue is filled
  and one entry answered, every write route on the surface is driven with
  `outcome`, `state`, `confirmed`, `sender_id` and the rest, and the queue's
  pending count is unchanged by all of them. Reinforced structurally — the only
  two `/mcp/browser-queue` paths are add and status, no tool pointing at them is
  named for a verb that would work the queue, and both descriptions say so, since
  a client may show only one of them.
- **#5 ticked.** Suite *Browser queue* proves the value keeps the rest pending
  after a partial sitting; suite *The browser queue survives a relaunch* writes a
  half-worked queue through a real `MessageStore`, closes it, opens a second one
  on the same file and reads the remaining entries back — the same technique
  TASK-45 used for proposals, and the only way to show "survives quitting"
  without a UI.

**TASK-23 folded in.** Its confirmation signal is this queue's advance signal, so
doing it twice would have meant two answers to the same question. Every exit that
records a confirmed unsubscribe now ends in one in-sheet result step naming the
message count, with `Delete N Messages` / `Keep Messages`, and `Trash and Ignore`
when the sender is an escalation — including the auto-detected banner, which was
the path where the offer degraded to a twelve-second toast. The toast in
`recordManual` is untouched and remains the fallback. Its acceptance criteria are
UI-side and were not run either; TASK-23 is left open for whoever verifies the
sheet.

**Incidental fix, needed for the queue to work at all.** `manualTarget(for:)`
returned nil for senders with no `List-Unsubscribe` header — which is the largest
cohort in the queue. It now falls back to the newest message for the address and
delivered-to, so the webmail-search fallback is reachable for them.

**Design concern.** `NevermoreApp` has its own `UnsubscribeMethod` in
`Design/Tokens.swift` that shadows `NevermoreKit.UnsubscribeMethod` inside the
app module — `AgentActions` has to write `NevermoreKit.UnsubscribeMethod.of(...)`
to reach the real one. Pre-existing and not touched here, but it is a trap.
<!-- SECTION:NOTES:END -->
