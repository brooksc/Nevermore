#!/usr/bin/env python3
"""Throwaway spike: verify Gmail IMAP can replace the Gmail REST API for MailScrub.

Read-only. Nothing is deleted, moved, or sent. stdlib only.

Usage:
    python3 spike/imap_probe.py
    MAILSCRUB_EMAIL=you@gmail.com MAILSCRUB_APP_PASSWORD=xxxx python3 spike/imap_probe.py

Generate an app password at https://myaccount.google.com/apppasswords (needs 2SV).
"""

import email
import imaplib
import os
import smtplib
import ssl
import sys
import time
from getpass import getpass

ALL_MAIL = '"[Gmail]/All Mail"'

# The query the Python app uses today, minus the parts IMAP handles separately.
SYNC_QUERY = "{category:promotions unsubscribe} -in:trash -in:sent -in:spam -is:starred"

HEADER_FIELDS = "From Subject Date List-Unsubscribe List-Unsubscribe-Post Delivered-To To"

imaplib._MAXLINE = 10_000_000  # Gmail sends long SEARCH responses


def hr(title):
    print(f"\n{'=' * 70}\n{title}\n{'=' * 70}")


def ok(msg):
    print(f"  \033[32mPASS\033[0m  {msg}")


def bad(msg):
    print(f"  \033[31mFAIL\033[0m  {msg}")


def info(msg):
    print(f"        {msg}")


def uid_search(imap, raw_query):
    """Run a Gmail search via X-GM-RAW. Returns (uids, elapsed) or (None, err).

    imaplib has no literal support in uid(), so the query goes as a quoted
    string. Gmail search syntax contains no double quotes in our queries.
    """
    t0 = time.time()
    try:
        typ, data = imap.uid("SEARCH", "X-GM-RAW", '"%s"' % raw_query.replace('"', r'\"'))
    except imaplib.IMAP4.error as e:
        return None, str(e)
    if typ != "OK":
        return None, str(data)
    return data[0].split(), time.time() - t0


def main():
    user = os.environ.get("MAILSCRUB_EMAIL") or input("Gmail address: ").strip()
    pw = os.environ.get("MAILSCRUB_APP_PASSWORD") or getpass("App password (16 chars, spaces ok): ")
    pw = pw.replace(" ", "")

    hr("1. Connect + authenticate")
    t0 = time.time()
    imap = imaplib.IMAP4_SSL("imap.gmail.com", 993, ssl_context=ssl.create_default_context())
    try:
        imap.login(user, pw)
    except imaplib.IMAP4.error as e:
        bad(f"login failed: {e}")
        info("App passwords require 2-Step Verification, and a Workspace admin can disable them.")
        return 1
    ok(f"authenticated in {time.time() - t0:.2f}s")

    hr("2. Capabilities (re-queried AFTER login — the set changes on auth)")
    typ, capdata = imap.capability()
    caps = capdata[0].decode().split() if typ == "OK" else []
    for want, why in [
        ("X-GM-EXT-1", "Gmail search syntax, labels, thread/msg IDs"),
        ("CONDSTORE", "incremental sync via MODSEQ"),
        ("QRESYNC", "resync after disconnect without refetching"),
        ("MOVE", "atomic move to Trash"),
        ("ID", "client identification"),
    ]:
        (ok if want in caps else bad)(f"{want:<12} — {why}")
    info(f"all: {' '.join(sorted(caps))}")

    hr("3. Select All Mail (read-only)")
    typ, data = imap.select(ALL_MAIL, readonly=True)
    if typ != "OK":
        bad(f"could not select {ALL_MAIL}: {data}")
        return 1
    ok(f"{int(data[0])} messages in All Mail")
    typ, hms = imap.status(ALL_MAIL, "(HIGHESTMODSEQ UIDVALIDITY UIDNEXT)")
    info(f"STATUS: {hms[0].decode() if typ == 'OK' else 'unavailable'}")

    hr("4. X-GM-RAW search — does Gmail query syntax work over IMAP?")
    queries = [
        ("bare category", "category:promotions"),
        ("bare unsubscribe", "unsubscribe"),
        ("grouped (as app uses)", "{category:promotions unsubscribe}"),
        ("full app query", SYNC_QUERY),
        ("full app query, 1y", f"{SYNC_QUERY} newer_than:1y"),
        ("has List-Unsubscribe", "has:list-unsubscribe"),
    ]
    results = {}
    for label, q in queries:
        uids, meta = uid_search(imap, q)
        if uids is None:
            bad(f"{label:<24} {q!r}\n              error: {meta}")
        else:
            results[label] = uids
            ok(f"{label:<24} {len(uids):>6} msgs in {meta:.2f}s   {q!r}")

    hr("4b. Plain RFC 3501 search — the fallback if X-GM-RAW is unusable")
    # Apple's swift-nio-imap has no X-GM-RAW search key, so this path matters:
    # an empty HEADER value matches any message that *has* that header at all.
    t0 = time.time()
    typ, d = imap.uid("SEARCH", "HEADER", "List-Unsubscribe", '""')
    if typ == "OK":
        plain = d[0].split()
        results["plain HEADER search"] = plain
        ok(f"{'HEADER List-Unsubscribe':<24} {len(plain):>6} msgs in {time.time() - t0:.2f}s")
        info("Expressible in swift-nio-imap today, and catches newsletters outside Promotions.")
        gm = results.get("full app query") or results.get("grouped (as app uses)")
        if gm:
            info(f"vs X-GM-RAW query: {len(plain)} vs {len(gm)} "
                 f"({len(set(plain) - set(gm))} found only by plain search)")
    else:
        bad(f"plain HEADER search failed: {d}")

    target = (results.get("full app query") or results.get("grouped (as app uses)")
              or results.get("plain HEADER search"))
    if not target:
        bad("no usable query returned results — IMAP backend is not viable as designed")
        return 1

    hr("5. Header-only fetch throughput")
    sample = target[-500:] if len(target) > 500 else target
    uid_set = b",".join(sample).decode()
    t0 = time.time()
    typ, data = imap.uid(
        "FETCH", uid_set,
        f"(UID X-GM-MSGID X-GM-LABELS INTERNALDATE FLAGS BODY.PEEK[HEADER.FIELDS ({HEADER_FIELDS})])",
    )
    elapsed = time.time() - t0
    if typ != "OK":
        bad(f"fetch failed: {data}")
        return 1

    parsed = with_unsub = with_post = with_delivered = 0
    for item in data:
        if not isinstance(item, tuple) or len(item) < 2:
            continue
        msg = email.message_from_bytes(item[1])
        if not msg.get("From"):
            continue
        parsed += 1
        if msg.get("List-Unsubscribe"):
            with_unsub += 1
        if msg.get("List-Unsubscribe-Post"):
            with_post += 1
        if msg.get("Delivered-To"):
            with_delivered += 1

    ok(f"fetched {len(sample)} messages in {elapsed:.2f}s ({len(sample) / max(elapsed, .01):.0f} msg/s)")
    info(f"parsed {parsed} headers")
    info(f"List-Unsubscribe present:      {with_unsub}/{parsed}")
    info(f"List-Unsubscribe-Post (RFC8058): {with_post}/{parsed}")
    info(f"Delivered-To (alias detection):  {with_delivered}/{parsed}")
    if with_delivered == 0:
        bad("no Delivered-To headers — alias detection would need the To: header only")

    est = len(target) / max(len(sample) / max(elapsed, .01), 1)
    info(f"extrapolated full sync of {len(target)} msgs: ~{est / 60:.1f} min")

    hr("6. Gmail-specific data (labels, msgids)")
    raw = b" ".join(x for item in data if isinstance(item, tuple) for x in [item[0]])
    (ok if b"X-GM-MSGID" in raw else bad)("X-GM-MSGID returned — gives a stable ID across sessions")
    (ok if b"X-GM-LABELS" in raw else bad)("X-GM-LABELS returned — lets us see Trash/Spam/Starred state")

    # Can we recognise the Promotions category from labels alone? If so, the
    # X-GM-RAW dependency disappears entirely.
    import re
    labels = set()
    for m in re.finditer(rb'X-GM-LABELS \(([^)]*)\)', raw):
        labels.update(t.strip(b'"') .decode(errors="replace") for t in m.group(1).split())
    info(f"distinct labels seen: {', '.join(sorted(labels)) or 'none'}")
    if any("CATEGORY_PROMOTIONS" in x.upper() or "Promotions" in x for x in labels):
        ok("Promotions category IS visible as a label — X-GM-RAW not needed for it")
    else:
        bad("Promotions category NOT exposed as a label — would need X-GM-RAW or plain search")

    hr("7. Trash capability (checked, NOT executed)")
    typ, boxes = imap.list()
    names = [b.decode() for b in boxes] if typ == "OK" else []
    trash = [n for n in names if "Trash" in n]
    (ok if trash else bad)(f"Trash mailbox: {trash[0] if trash else 'not found'}")
    info("Deletion would be: UID MOVE <uids> \"[Gmail]/Trash\" (atomic, needs MOVE capability)")

    hr("8. Send-as aliases — the known Gmail-API-only feature")
    typ, data = imap.select('"[Gmail]/Sent Mail"', readonly=True)
    if typ == "OK":
        uids, _ = uid_search(imap, "newer_than:1y")
        froms = set()
        if uids:
            typ, d = imap.uid("FETCH", b",".join(uids[-300:]).decode(),
                              "(BODY.PEEK[HEADER.FIELDS (From)])")
            for item in d:
                if isinstance(item, tuple) and len(item) > 1:
                    f = email.message_from_bytes(item[1]).get("From", "")
                    if "@" in f:
                        froms.add(f.split("<")[-1].strip("<> ").lower())
        if len(froms) > 1:
            ok(f"inferred {len(froms)} send-as addresses from Sent Mail: {', '.join(sorted(froms))}")
            info("Viable substitute for users.settings.sendAs.list — no API needed.")
        else:
            info(f"only found: {froms or 'none'} — would have to ask the user for aliases")
    imap.logout()

    hr("9. SMTP submission (auth only, nothing sent)")
    try:
        with smtplib.SMTP("smtp.gmail.com", 587, timeout=20) as s:
            s.starttls(context=ssl.create_default_context())
            s.login(user, pw)
            ok("SMTP authenticated — mailto: unsubscribes can be sent without the Gmail API")
    except Exception as e:
        bad(f"SMTP failed: {e}")

    hr("Verdict")
    print("""  The IMAP path is viable if 4, 5 and 9 passed. Key numbers to weigh:
    - full app query result count vs. what the Python app reports
    - header fetch throughput (Gmail REST batch does ~25/req with 1s sleeps)
    - whether Delivered-To survives, for alias detection
""")
    return 0


if __name__ == "__main__":
    sys.exit(main())
