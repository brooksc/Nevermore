---
id: TASK-60
title: Sender-controlled URL reaches the real browser and the request line unchecked
status: Done
assignee: []
created_date: '2026-08-31 23:09'
updated_date: '2026-08-31 23:10'
labels:
  - security
dependencies: []
priority: high
type: bug
ordinal: 26000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Two defects on the same surface, both found by audit and both verified independently. The sender chooses this URL — it comes from their own `List-Unsubscribe` header — so everything derived from it is attacker-controlled input.

**1. The History context menu opens it in the real browser with no guard.**

`Views/Collections/HistoryView.swift` — the row's visible *Manage* button correctly gates on `DestinationGuard.isAllowed(url)`, with a comment saying "handing an unvetted attacker-chosen link to the default browser was the one remaining unguarded path." The context menu on the same row, about 26 lines below, rebuilds the same URL and calls `NSWorkspace.shared.open(url)` with no check at all.

A sender publishes `List-Unsubscribe: <http://192.168.1.1/admin/...>`. Any attempt that reports success stores the URL. The row appears in History with *Manage* correctly hidden because the guard fails — and right-click, "Open Preferences Page", loads it in the user's default browser with their real cookies and their position on the LAN. That is worse than the in-app sheet: authenticated CSRF against a router, printer, or a localhost dev service.

**2. Percent-decoded CRLF in the path reaches the request line.**

`Unsubscribe/PinnedHTTPClient.swift` builds the request target as `url.path`, and Foundation returns `path` **percent-decoded**. Verified directly:

    URL(string: "https://x.example/unsub%0D%0AX-Injected:%20yes")!.path
    == "/unsub\r\nX-Injected: yes"

That string is joined into the request with `\r\n` separators, so a sender injects arbitrary headers — or a second request — into the message Nevermore sends. `url.query` stays encoded, so the path is the hole.

The request goes to the sender's own host, which limits direct gain, but it breaks HTTP framing and is the standard precondition for request smuggling through any intermediary. It is also cheap to close and there is no reason to emit a malformed request.</description>
<parameter name="acceptanceCriteriaSet">["Every path that opens a sender-supplied URL externally passes DestinationGuard, with no route around it", "A URL whose path or query decodes to contain CR or LF is refused rather than sent", "The request target is built from the encoded path, not the decoded one", "Tests cover a percent-encoded CRLF and a private-address URL reaching each exit"]
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every path that opens a sender-supplied URL externally passes DestinationGuard, with no route around it
- [x] #2 A URL whose path or query decodes to contain CR or LF is refused rather than sent
- [x] #3 The request target is built from the encoded path, not the decoded one
- [x] #4 Tests cover a percent-encoded CRLF and a private-address URL reaching each exit
<!-- AC:END -->
