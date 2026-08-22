---
id: TASK-4
title: Pin the resolved IP so DNS rebinding cannot beat DestinationGuard
status: Done
assignee: []
created_date: '2026-08-09 18:50'
updated_date: '2026-08-22 04:21'
labels:
  - security
dependencies: []
modified_files:
  - >-
    Packages/NevermoreKit/Sources/NevermoreKit/Unsubscribe/PinnedHTTPClient.swift
  - >-
    Packages/NevermoreKit/Sources/NevermoreKit/Unsubscribe/DestinationGuard.swift
  - >-
    Packages/NevermoreKit/Sources/NevermoreKit/Unsubscribe/UnsubscribeEngine.swift
  - Packages/NevermoreKit/Sources/NevermoreKit/Server/NevermoreServer.swift
  - Packages/NevermoreKit/Tests/NevermoreTests/main.swift
  - PLAN.md
  - CHANGELOG.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DestinationGuard resolves the host and decides, then URLSession resolves independently when the request is made. A hostile resolver can answer public for the first lookup and private for the second, which defeats the check entirely.

This matters more here than in most apps: every URL comes from an attacker-authored List-Unsubscribe header, which is the app's central threat. Recorded as open in PLAN.md section 10.

A real fix pins the validated IP and sets the Host header, rather than trusting a second resolution.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The validated address is the one connected to
- [x] #2 Host header preserved so TLS and vhosts still work
- [x] #3 Redirect hops get the same treatment
- [x] #4 Test covers a resolver that changes its answer between lookups
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Measured first, because the obvious fix is wrong.

Probe (scratchpad, macOS 27 / CFNetwork 3896): URLSession *does* honour a custom `Host`
header, but when the URL host is an IP literal it sends **no SNI at all** (TLS forbids IP
literals in SNI). So the brief's literal fix — rewrite the URL to the validated IP, set
`Host` — silently drops SNI on every HTTPS request. Shared-hosting and CDN unsubscribe
endpoints (i.e. most of them) would get the wrong certificate or a refused handshake, and
the only way to make that "work" would be to weaken trust evaluation. That is the trade
the brief explicitly forbids.

Second probe: point `URLSessionConfiguration.connectionProxyDictionary` at a loopback
CONNECT proxy. URLSession then sends `CONNECT host:port` and **does not resolve the host
itself** — the proxy owns the only resolution. Observed on the far side: SNI arrives as the
real hostname, and default trust evaluation still runs against that hostname (it correctly
rejected a self-signed cert, naming the host in the error). Pin achieved, TLS untouched.

Plan:
1. `DestinationGuard` gains a resolve-and-validate entry point that returns the chosen
   address, so "what was checked" and "what is dialled" are one value, not two lookups.
2. New `PinnedProxy`: NWListener on 127.0.0.1, OS-assigned port (never 8775-8779).
   Resolves once, validates every answer as public, dials the pinned address, then splices
   bytes. CONNECT for https (end-to-end TLS), origin-form rewrite for http.
3. `UnsubscribeEngine`'s session routes through it. Every redirect hop is a fresh
   CONNECT/request through the proxy, so hop two is pinned exactly like hop one.
   `RedirectGuard` stays as the belt to the proxy's braces.
4. Tests: injectable resolver + connector, so a resolver that answers public-then-private
   can be run deterministically and the dialled address asserted; plus an end-to-end
   splice test against a local listener.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Verified, each against something that was actually run (`swift run nevermore-tests`, 322 passed / 0 failed; 309 was the baseline, so 13 new).

**AC #1 — the validated address is the one connected to.** `PinnedProxy` resolves via `DestinationGuard.pin(for:)` exactly once per hop and dials an explicitly-constructed `.ipv4`/`.ipv6` endpoint, so Network.framework has no name to look up. Test: *a resolver that changes its answer cannot move the connection* — the injected resolver answers reachable on lookup 1 and unreachable (TEST-NET-2) on every lookup after; the request arrives at answer 1, and the host is looked up exactly once.

**AC #2 — Host preserved, TLS and vhosts still work.** For http, test *the origin still sees the real Host* asserts the origin receives `Host: vhost.invalid` and an origin-form request line. For https there is no header rewriting at all, because the tunnel is never parsed. Proven with a real TLS server and the real `PinnedProxy` (scratchpad probe): the server logged `SNI: 'vhost.example'`, and with **no URLSession delegate at all** the self-signed certificate was rejected as "pretending to be vhost.example" — stock validation, running against the hostname. Accepting the cert, the request completed 200 through the tunnel.

**AC #3 — redirect hops.** Tests *a redirect to another host is pinned again, not inherited* (both hostnames appear in the resolver's log; the body comes from hop two) and *a redirect into a refused host is stopped at the second hop* (403, and the second origin records no request). Plain HTTP is forwarded with `Connection: close` specifically so CFNetwork cannot reuse one proxy connection for a different origin host, which would have let hop two ride hop one's pin.

**AC #4 — resolver that changes its answer.** See AC #1. Honest limitation: this asserts the invariant (one lookup; the validated answer is dialled) rather than reproducing the old code failing. It cannot demonstrate the before/after, because after the fix the app no longer resolves names outside the proxy at all. The companion test *URLSession never resolves the host itself* covers that from the other side: a request to a `.invalid` hostname with no DNS record anywhere succeeds, which is only possible if nothing but the proxy resolved it.

Rejected approach, recorded so it is not retried: rewriting the URL to the pinned IP and setting `Host:`. Measured on macOS 27 / CFNetwork 3896 — the `Host` header *is* honoured, but with an IP literal in the URL, CFNetwork sends **no SNI** (`SNI: None` observed, versus `SNI: 'localhost'` for the same server reached by name). Every CDN- or shared-hosting-backed unsubscribe endpoint would then be served a default certificate that correct validation must reject, and the only way to ship it would be to loosen trust evaluation. That trades a real TLS guarantee for an SSRF one.

Residual risk, left deliberately:
- While the app is running, the proxy is an open forward proxy for anything on the machine that finds its loopback port. It only ever forwards to public addresses, so it is not a pivot into the LAN, and any local process already has internet access — no privilege is gained. Not authenticated, because making URLSession present proxy credentials costs a 407 round trip per request for no security gain.
- If the listener will not bind, `UnsubscribeEngine` refuses to send rather than falling back to a direct session. Fail closed. That path is reasoned, not tested — I could not make the bind fail on demand.
- The proxy is never stopped; it lives for the life of the process, like the session it serves.

**Superseded: the proxy was wrong, and the reason is worth keeping.**

The loopback `CONNECT` proxy worked and kept TLS end-to-end, but a listener requires `com.apple.security.network.server` and `Packages/NevermoreKit/Resources/Nevermore.entitlements` grants only `app-sandbox` + `network.client` (verified directly; its own comment reads "No server."). `UnsubscribeEngine` ships in the Mac App Store build, so the proxy would have failed to bind there and broken unsubscribing outright — a far worse regression than the bug. Same constraint that made the MCP server direct-download only; relaxing it is TASK-40's call, not this task's.

**What shipped instead.** `PinnedHTTPClient` makes the connection itself, outbound only. `NWConnection` dials a literal `.ipv4`/`.ipv6` endpoint from the validated address, `sec_protocol_options_set_tls_server_name` carries the real hostname, and `Host:` carries it too. Requests no longer go through `URLSession` anywhere in the unsubscribe path, so nothing re-resolves a name. Only response headers are parsed — no bodies, hence no chunked or gzip handling to get wrong.

**TLS, verified not asserted.** No verify block exists in the file. Against badssl.com through the shipped code: `badssl.com` 200; `wrong.host.badssl.com` rejected (-9808) — validly chained, wrong hostname, which is the case that proves hostname checking specifically; `expired.badssl.com` rejected (-9814); `self-signed.badssl.com` rejected. Plus `example.com` over both http and https. Two of my earlier controls were junk and were discarded: `wrong-name.example.com` matches a `*.example.com` wildcard, and a bogus SNI at Cloudflare is refused server-side (-9824), which says nothing about the client.

**Two defects found by measuring the real thing, both invisible to the unit tests.**

1. *Single-address pinning lost failover.* `example.com` publishes two A records; pinning `.first` meant one dead address read as an unsubscribe endpoint that doesn't work. `DestinationGuard.pinnedAddresses(for:)` now returns every validated address and the client tries them in order — same single lookup, same check applied to all of them, so nothing is given up. Each address gets a slice of the caller's budget rather than the whole of it, floored at 4s, so trying several cannot take several times as long.

2. *The timeout reported itself but did not end anything.* Measured against a blackholed address: a 3s budget produced the correct `timed out after 4s` error after **30.54s**. Network.framework does not observe Swift task cancellation, so the sibling task sat in a continuation until the OS gave up. The timeout path now cancels the connection. Re-measured: 4.22s for a 4s budget, 6.27s for 6s. Covered by *a timeout ends the request, not just the waiting for it*, which asserts elapsed time rather than the error text — the old bug produced exactly the right error.

Honest gap: the TLS path has **no coverage in the test suite**. A local TLS server would need a certificate the system trusts, and correctly rejecting a self-signed one is the behaviour we want. It is verified by the badssl.com matrix above, which is a live-network probe run by hand, not something `swift run nevermore-tests` re-checks. If the SNI line or the trust default is ever changed, the suite will stay green. That is the weakest point in this work.

**The redirect floor did not exist.** The brief pointed at "the existing `blockedRedirect` tests" as a floor. There are none: `git show main:Packages/NevermoreKit/Tests/NevermoreTests/main.swift | grep -i redirect` returns nothing. The 0.1.0 fix for "A blocked SSRF redirect was recorded as a successful unsubscribe" shipped with no regression guard at all, and stayed that way.

There is one now: *a blocked redirect is never recorded as a success* runs 301/302/303/307/308 and asserts `!outcome.isSuccess` — the exact property that regressed, since the unfollowed 3xx used to fall under `code < 400` — plus that the internal host records no request.

That guard was mutation-tested rather than trusted. Reintroducing the defect (forcing `blockedRedirect` to return nil) turned it red: 6 failures across the status codes. Restored, 340 pass.

**Deadline coverage.** Two failure modes, both asserted on elapsed time rather than error text, because the original bug produced exactly the right text while honouring nothing: a blackholed address (connect never completes) and an endpoint that accepts the connection and then answers nothing (the response-head read — the cheaper and more likely hostile move). Both return inside the budget.

**No body reading is deliberate, not an omission.** `UnsubscribeEngine` already discarded every response body on both paths, and `looksLikeConfirmation` has exactly one caller, `WebUnsubscribeSheet` (the WKWebView flow), which this does not touch — verified by grep over `Sources/`. So dropping body handling changes no behaviour. It also removes chunked decoding and gzip from the hand-rolled path, which is most of what makes such a client risky. Nobody should re-add it believing it was overlooked.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Landed on `task-4-fix` as a single commit, d33086c. Not merged.

Unsubscribe requests no longer go through `URLSession`, which is what resolved the hostname a second time. `PinnedHTTPClient` connects with `NWConnection` to a literal IP endpoint taken from `DestinationGuard.pinnedAddresses(for:)`, sets the real hostname as SNI via `sec_protocol_options_set_tls_server_name` and in `Host:`, and leaves trust evaluation at the default — there is no verify block, confirmed by grep over `Sources/`. Every redirect hop is resolved, checked and pinned on its own account. Outbound-only, so it works under the App Store sandbox, which a loopback proxy would not have.

340 tests pass, 0 failed (309 baseline, 31 new), stable across three consecutive runs, suite ~8s. Working tree clean.

Beyond the suite, verified against live endpoints through the shipped code: `badssl.com` connects, while `wrong.host.badssl.com` (valid chain, wrong hostname), `expired.badssl.com` and `self-signed.badssl.com` are all rejected.

Two known gaps, both stated rather than papered over:
- The TLS path has no automated coverage. A local TLS server would need a system-trusted certificate, and correctly rejecting a self-signed one is the behaviour we want. If the SNI line or the trust default is changed, the suite stays green — the badssl matrix is a hand-run live probe.
- The branch sits on its original branch point (f835795); `main` has since advanced to 8015737. It needs a rebase or merge by whoever integrates it. `git reset --soft main` would have staged reversions of other agents' merged work, so the squash was done against the branch point instead.
<!-- SECTION:FINAL_SUMMARY:END -->
