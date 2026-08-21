---
id: TASK-43
title: 'Remember what the agent decided about a sender, and why'
status: In Progress
assignee: []
created_date: '2026-08-20 21:18'
updated_date: '2026-08-20 21:19'
labels:
  - mcp
dependencies:
  - TASK-41
priority: high
type: feature
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Part of TASK-41. This is the piece that makes agent triage compound instead of repeat: without it, every session re-derives the same judgements about the same senders and the user re-answers the same questions.

Today the only durable signal about a sender is ignore, which is binary and records no reason. What is needed is a decision record the agent writes and Nevermore stores without interpreting: a classification, a free-text reason, and a context label naming the situation the decision was contingent on (for example job-search-2026).

Nevermore must never match, parse, or reason about these values. They are opaque text. All meaning lives in the agent. This is what keeps an LLM out of the app while still letting the user ask "I am done job hunting, what can go now" — that question becomes a lookup on the context field, not a semantic search.

Store the record per sender ADDRESS, not per GroupID. Grouping is mutable — splitByAddress and keepAsOneGroup change which GroupID a sender belongs to — so keying on GroupID would silently discard agent judgement whenever the user regroups a domain. Records roll up to whatever group is current at read time.

MessageStore already has a generic stringSet(forKey:) / setStringSet(_:forKey:) KV facility, which may or may not be the right substrate for something with this much structure; that is the implementer's call.

Records must survive a normal sync. Whether they survive resetAllState() and account removal needs deciding during implementation, and whichever way it goes should be stated in the task notes rather than left to be discovered.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A sender can carry a classification, a reason, and a context label, all stored verbatim
- [x] #2 Records key on sender address and survive splitByAddress and keepAsOneGroup regrouping
- [x] #3 Records can be queried by context label, so a whole cohort can be re-opened when a situation ends
- [x] #4 Nevermore itself never branches on the content of a classification or context value
- [x] #5 Records survive a normal sync, and the behaviour on resetAllState and account removal is decided and documented
- [x] #6 Tests cover regrouping in both directions without loss, and query-by-context
<!-- AC:END -->

## Implementation Plan
<!-- SECTION:PLAN:BEGIN -->
1. New `senderDecision` table in migration `v5-sender-decisions`, keyed by lowercased sender address. → verify: the migration runs on a fresh and on an existing store, and the pre-migration backup tests still pass.
2. `SenderDecision` value type + store API: `recordDecision`, `decision(forAddress:)`, `allDecisions()`, `decisions(inContext:)`, `decisionContexts()`, `forgetDecision(forAddress:)`, `forgetAllDecisions()`. → verify: round-trip test.
3. Read-time roll-up `decisions(for: SenderGroup)`, resolving the group's member addresses against the address-keyed table. → verify: regrouping tests in both directions.
4. Tests in `Tests/NevermoreTests/main.swift`. → verify: `swift run nevermore-tests` reports 117 + new, 0 failures.

### Substrate: a table, not the KV facility

`stringSet(forKey:)` stores one JSON blob under one key. Query-by-context would
mean decoding every record and filtering in Swift, and every single-sender write
would rewrite the whole blob (last-writer-wins across an app and an MCP server
that TASK-45 will have writing concurrently). A real table gives an indexed
exact-match lookup on `context` and an atomic per-address upsert.

### Shape

```sql
CREATE TABLE senderDecision (
  address        TEXT PRIMARY KEY,   -- lowercased sender address; never a GroupID
  classification TEXT NOT NULL,      -- opaque
  reason         TEXT NOT NULL,      -- opaque
  context        TEXT,               -- opaque, NULL = unconditional
  decidedAt      REAL NOT NULL
)
```

`context` is nullable because not every judgement is contingent on a situation.
Query-by-context is `WHERE context = ?` — an exact match on a stored field, not a
search. Nothing in NevermoreKit reads `classification` or `context` for control
flow; the only string comparison the store makes is on `address`, which is an
identifier, not agent content.
<!-- SECTION:PLAN:END -->

## Implementation Notes
<!-- SECTION:NOTES:BEGIN -->
Implemented in `Packages/NevermoreKit/Sources/NevermoreKit/Store/MessageStore.swift`
(migration `v5-sender-decisions` plus a `// MARK: - Agent decisions` section) and
tested in `Packages/NevermoreKit/Tests/NevermoreTests/main.swift`.

`swift run nevermore-tests`: **128 passed, 0 failed** (117 before, 11 added).
`swift build`: clean, no warnings, `.swiftLanguageMode(.v6)`.

### Decided: records die with the account

`resetAllState()` and account removal both **delete** the decisions, and this is
now deliberate rather than incidental.

The records live in the account's own `<account>.sqlite`, next to its unsubscribe
history and ignore list. `AccountRegistry.resetAllLocalData()` deletes that file
and `remove(_:)` deletes it too, so both already take the decisions with them.
That is the right answer and not merely the convenient one:

- `AppModel.resetDescription` promises the user "the state it was in before it
  was ever launched". Judgements about senders surviving that would be a
  surprise, and the confirmation dialog would be lying.
- A reason is free text an agent wrote about the user's own circumstances
  ("only worth it while I'm job hunting"). Outliving the mailbox it describes
  makes it a small privacy leak, not a feature.
- Decisions are cheap to rebuild — the agent re-derives them — unlike the
  unsubscribe history, which records irreversible actions taken on the server.

`forgetAllDecisions()` exists so the intent is expressed in code rather than
being a side effect of file deletion, and so TASK-44/45 have a way to clear a
cohort without deleting the cache. A test asserts a second store starts empty.

### API

- `recordDecision(address:classification:reason:context:decidedAt:)` — one
  decision per address; re-recording supersedes.
- `decision(forAddress:)`, `allDecisions()` — read one, or all keyed by address.
- `decisions(inContext:)` — exact match on the label. `decisionContexts()` lists
  the distinct labels in use.
- `decisions(for: SenderGroup)` / `decisions(forAddresses:)` — the read-time
  roll-up. This is what makes regrouping lossless.
- `forgetDecision(forAddress:)`, `forgetAllDecisions()`.

`context` is `String?`; nil means the decision isn't contingent on any situation,
and such records belong to no cohort. Addresses are lowercased on write and
lookup — they're identifiers, not agent content — while classification, reason
and context are stored byte-for-byte, whitespace and case included.

### Concerns for whoever picks up TASK-44/45

- **`AccountRegistry.remove(_:)` deletes only the main `.sqlite` file**, not the
  `-wal` and `-shm` siblings, unlike `resetAllLocalData()` which handles all
  three (`AccountRegistry.swift:88` vs `:57-61`). Pre-existing, not touched here,
  and not specific to decisions — but it means a removed account can leave a
  write-ahead log on disk holding recently written rows, which now includes
  free-text reasons. Worth a small separate task.
- Nothing reads these records yet. AC #4 currently holds by construction: no
  file outside `MessageStore.swift` mentions `classification` or `context`. It
  needs to keep holding — the MCP layer should pass these strings through to the
  agent, never filter or rank on them.
- One decision per address, no history. If "what did the agent think last month"
  ever matters, that's a schema change, not an additive one.
<!-- SECTION:NOTES:END -->
