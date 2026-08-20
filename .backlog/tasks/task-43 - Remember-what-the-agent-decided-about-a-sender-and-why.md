---
id: TASK-43
title: 'Remember what the agent decided about a sender, and why'
status: To Do
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
- [ ] #1 A sender can carry a classification, a reason, and a context label, all stored verbatim
- [ ] #2 Records key on sender address and survive splitByAddress and keepAsOneGroup regrouping
- [ ] #3 Records can be queried by context label, so a whole cohort can be re-opened when a situation ends
- [ ] #4 Nevermore itself never branches on the content of a classification or context value
- [ ] #5 Records survive a normal sync, and the behaviour on resetAllState and account removal is decided and documented
- [ ] #6 Tests cover regrouping in both directions without loss, and query-by-context
<!-- AC:END -->
