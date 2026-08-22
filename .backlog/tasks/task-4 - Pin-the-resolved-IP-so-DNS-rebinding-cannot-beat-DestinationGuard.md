---
id: TASK-4
title: Pin the resolved IP so DNS rebinding cannot beat DestinationGuard
status: In Progress
assignee: []
created_date: '2026-08-09 18:50'
updated_date: '2026-08-22 03:35'
labels:
  - security
dependencies: []
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
- [ ] #1 The validated address is the one connected to
- [ ] #2 Host header preserved so TLS and vhosts still work
- [ ] #3 Redirect hops get the same treatment
- [ ] #4 Test covers a resolver that changes its answer between lookups
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
