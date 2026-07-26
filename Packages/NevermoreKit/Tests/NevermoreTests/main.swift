import Foundation
import NevermoreKit

// Thin forwarders: binding these as `let` loses both the generic parameter and
// the `line: Int = #line` default, so they have to be functions.
func expect(
    _ condition: Bool,
    _ message: @autoclosure () -> String = "expectation failed",
    line: Int = #line
) {
    Harness.expect(condition, message(), line: line)
}

func eq<T: Equatable>(
    _ actual: T?,
    _ expected: T?,
    _ label: @autoclosure () -> String = "",
    line: Int = #line
) {
    Harness.expectEqual(actual, expected, label(), line: line)
}

// MARK: - MIME header decoding

Harness.suite("MIMEHeader") {
    Harness.test("passes plain text through untouched") {
        eq(MIMEHeader.decode("Acme Newsletter"), "Acme Newsletter")
    }
    Harness.test("decodes base64 encoded-words") {
        eq(MIMEHeader.decode("=?UTF-8?B?Q2Fmw6k=?="), "Café")
    }
    Harness.test("decodes Q-encoded words, with _ as space") {
        eq(MIMEHeader.decode("=?UTF-8?Q?Caf=C3=A9_News?="), "Café News")
    }
    // RFC 2047: whitespace *between* adjacent encoded-words is not significant.
    Harness.test("joins adjacent encoded-words without inserting whitespace") {
        eq(MIMEHeader.decode("=?UTF-8?B?Q2Fm?= =?UTF-8?B?w6k=?="), "Café")
    }
    Harness.test("keeps literal text around encoded-words") {
        eq(MIMEHeader.decode("The =?UTF-8?B?Q2Fmw6k=?= Times"), "The Café Times")
    }
    Harness.test("leaves malformed encoded-words alone rather than dropping text") {
        eq(MIMEHeader.decode("=?UTF-8?B?not-valid"), "=?UTF-8?B?not-valid")
        eq(MIMEHeader.decode("=?"), "=?")
    }
    Harness.test("falls back to UTF-8 for an unknown charset") {
        eq(MIMEHeader.decode("=?NOPE-9?B?Q2Fmw6k=?="), "Café")
    }
}

// MARK: - Sender parsing

Harness.suite("EmailSender") {
    Harness.test("splits display name from address") {
        let s = EmailSender(header: "Acme News <news@mail.acme.com>")
        eq(s.displayName, "Acme News")
        eq(s.address, "news@mail.acme.com")
        eq(s.host, "mail.acme.com")
    }
    Harness.test("handles a bare address") {
        let s = EmailSender(header: "news@acme.com")
        eq(s.displayName, "")
        eq(s.address, "news@acme.com")
        eq(s.host, "acme.com")
    }
    Harness.test("lowercases the address but preserves display-name case") {
        let s = EmailSender(header: "Acme NEWS <News@ACME.com>")
        eq(s.displayName, "Acme NEWS")
        eq(s.address, "news@acme.com")
    }
    Harness.test("decodes an encoded display name") {
        eq(EmailSender(header: "=?UTF-8?B?Q2Fmw6k=?= <hi@acme.com>").displayName, "Café")
    }
    Harness.test("strips quotes from the display name") {
        eq(EmailSender(header: "\"Acme, Inc.\" <hi@acme.com>").displayName, "Acme, Inc.")
    }
    // `"Foo <bar>" <real@acme.com>` — the last bracket pair is the real address.
    Harness.test("uses the last angle-bracket pair when the name contains one") {
        eq(EmailSender(header: "\"Foo <bar>\" <real@acme.com>").address, "real@acme.com")
    }
    Harness.test("degrades gracefully on empty input") {
        let s = EmailSender(header: "")
        expect(s.address.isEmpty, "address should be empty")
        expect(s.host.isEmpty, "host should be empty")
        expect(s.label.isEmpty, "label should be empty")
    }
    Harness.test("label prefers name, then address") {
        eq(EmailSender(header: "N <a@b.com>").label, "N")
        eq(EmailSender(header: "<a@b.com>").label, "a@b.com")
    }
}

// MARK: - List-Unsubscribe

Harness.suite("ListUnsubscribe") {
    Harness.test("returns nil when the header is absent or blank") {
        expect(ListUnsubscribe(header: nil) == nil, "nil header")
        expect(ListUnsubscribe(header: "   ") == nil, "blank header")
    }
    Harness.test("parses an https target") {
        let u = ListUnsubscribe(header: "<https://ex.com/u?id=1>")
        eq(u?.webTargets.map(\.absoluteString), ["https://ex.com/u?id=1"])
        eq(u?.mailtoTargets.isEmpty, true)
    }
    Harness.test("parses a mailto target with subject and body") {
        let u = ListUnsubscribe(header: "<mailto:unsub@ex.com?subject=stop&body=please%20stop>")
        eq(u?.mailtoTargets.first?.address, "unsub@ex.com")
        eq(u?.mailtoTargets.first?.subject, "stop")
        eq(u?.mailtoTargets.first?.body, "please stop")
    }
    Harness.test("supplies defaults for a bare mailto") {
        let u = ListUnsubscribe(header: "<mailto:unsub@ex.com>")
        eq(u?.mailtoTargets.first?.subject, "unsubscribe")
        eq(u?.mailtoTargets.first?.body.isEmpty, false)
    }
    Harness.test("preserves sender-preferred order across both target kinds") {
        let u = ListUnsubscribe(header: "<https://a.com/1>, <mailto:b@ex.com>, <https://c.com/2>")
        eq(u?.webTargets.count, 2)
        eq(u?.webTargets.first?.host, "a.com")
        eq(u?.mailtoTargets.count, 1)
    }
    // Commas are legal inside a URI, so brackets are the only safe delimiter.
    Harness.test("tolerates commas inside a URI") {
        let u = ListUnsubscribe(header: "<https://ex.com/u?a=1,2,3>")
        eq(u?.webTargets.count, 1)
        eq(u?.webTargets.first?.absoluteString, "https://ex.com/u?a=1,2,3")
    }
    Harness.test("folds a header wrapped across lines") {
        eq(ListUnsubscribe(header: "<https://ex.com/\n  unsub?id=1>")?.webTargets.count, 1)
    }
    Harness.test("detects the RFC 8058 one-click token") {
        let u = ListUnsubscribe(
            header: "<https://ex.com/u>", postHeader: "List-Unsubscribe=One-Click")
        eq(u?.supportsOneClick, true)
    }
    Harness.test("does not treat an arbitrary post header as one-click") {
        eq(ListUnsubscribe(header: "<https://ex.com/u>", postHeader: "x")?.supportsOneClick, false)
        eq(ListUnsubscribe(header: "<https://ex.com/u>")?.supportsOneClick, false)
    }
    Harness.test("ignores unsupported schemes") {
        expect(ListUnsubscribe(header: "<ftp://ex.com/u>") == nil, "ftp should be rejected")
    }
}

// MARK: - Registrable domain

Harness.suite("RegistrableDomain") {
    Harness.test("collapses sending subdomains to the brand domain") {
        for (host, want) in [
            ("email.harborfreight.com", "harborfreight.com"),
            ("e.paypal.com", "paypal.com"),
            ("news.bloomberg.com", "bloomberg.com"),
            ("em1.turbotax.intuit.com", "intuit.com"),
            ("notifications.t-mobile.com", "t-mobile.com"),
            ("acme.com", "acme.com"),
        ] {
            eq(RegistrableDomain.of(host), want, host)
        }
    }
    Harness.test("respects multi-label public suffixes") {
        for (host, want) in [
            ("mail.bbc.co.uk", "bbc.co.uk"),
            ("bbc.co.uk", "bbc.co.uk"),
            ("shop.example.com.au", "example.com.au"),
        ] {
            eq(RegistrableDomain.of(host), want, host)
        }
    }
    Harness.test("normalises case and stray dots") {
        eq(RegistrableDomain.of("Mail.ACME.com."), "acme.com")
    }
    Harness.test("returns empty for an empty host") {
        eq(RegistrableDomain.of(""), "")
    }
}

// MARK: - Grouping

func msg(
    _ uid: UInt32,
    from: String,
    subject: String = "s",
    daysAgo: Double = 0,
    unread: Bool = false,
    unsub: String? = "<https://ex.com/u>"
) -> EmailMessage {
    EmailMessage(
        uid: MessageUID(uid),
        sender: EmailSender(header: from),
        subject: subject,
        receivedAt: Date(timeIntervalSince1970: 1_700_000_000 - daysAgo * 86400),
        isUnread: unread,
        unsubscribe: ListUnsubscribe(header: unsub)
    )
}

Harness.suite("Grouping") {
    // The Amazon case: one display name, several sending hosts → one row.
    Harness.test("merges one brand sending from many subdomains into a single row") {
        let groups = Grouping().group([
            msg(1, from: "Amazon <store-news@amazon.com>"),
            msg(2, from: "Amazon <ship@emailinfo.amazon.com>"),
            msg(3, from: "Amazon <pay@payments.amazon.com>"),
        ])
        eq(groups.count, 1)
        eq(groups.first?.id, GroupID(kind: .domain, key: "amazon.com"))
        eq(groups.first?.total, 3)
    }
    // The Substack case: same domain, different display names → one row each.
    Harness.test("splits distinct newsletters that share a platform") {
        let groups = Grouping().group([
            msg(1, from: "Alice Writes <alice@substack.com>"),
            msg(2, from: "Bob Reports <bob@substack.com>"),
            msg(3, from: "Alice Writes <alice@substack.com>"),
        ])
        eq(groups.count, 2)
        expect(groups.allSatisfy { $0.id.kind == .address }, "all groups keyed by address")
        eq(groups.first { $0.id.key == "alice@substack.com" }?.total, 2)
    }
    Harness.test("splits when one domain carries several distinct display names") {
        eq(
            Grouping().group([
                msg(1, from: "Deals <a@shop.com>"),
                msg(2, from: "Receipts <b@shop.com>"),
            ]).count, 2)
    }
    Harness.test("a split rule forces a single-brand domain into per-address rows") {
        // Amazon-style: one display name, several addresses — normally merged.
        let merged = Grouping().group([
            msg(1, from: "Amazon <a@amazon.com>"),
            msg(2, from: "Amazon <b@amazon.com>"),
        ])
        eq(merged.count, 1)
        let split = Grouping(rules: ["amazon.com": .split]).group([
            msg(1, from: "Amazon <a@amazon.com>"),
            msg(2, from: "Amazon <b@amazon.com>"),
        ])
        eq(split.count, 2)
    }
    Harness.test("a merge rule keeps an auto-split domain as one group") {
        // Distinct display names normally split; a merge rule overrides that.
        let split = Grouping().group([
            msg(1, from: "Deals <a@shop.com>"),
            msg(2, from: "Receipts <b@shop.com>"),
        ])
        eq(split.count, 2)
        let merged = Grouping(rules: ["shop.com": .merge]).group([
            msg(1, from: "Deals <a@shop.com>"),
            msg(2, from: "Receipts <b@shop.com>"),
        ])
        eq(merged.count, 1)
    }
    Harness.test("sorts by message count descending") {
        let groups = Grouping().group([
            msg(1, from: "One <a@one.com>"),
            msg(2, from: "Two <b@two.com>"),
            msg(3, from: "Two <b@two.com>"),
        ])
        eq(groups.first?.id.key, "two.com")
    }
    Harness.test("computes per-group statistics") {
        let groups = Grouping().group([
            msg(1, from: "N <a@x.com>", unread: true),
            msg(2, from: "N <a@x.com>", unread: false),
        ])
        eq(groups.first?.total, 2)
        eq(groups.first?.unreadCount, 1)
        eq(groups.first?.unreadPercent, 50)
    }
    Harness.test("orders messages newest-first") {
        let groups = Grouping().group([
            msg(1, from: "N <a@x.com>", subject: "old", daysAgo: 10),
            msg(2, from: "N <a@x.com>", subject: "new", daysAgo: 1),
        ])
        eq(groups.first?.latest?.subject, "new")
    }
    Harness.test("reports a group unsubscribable only when some message carries a target") {
        expect(Grouping().group([msg(1, from: "N <a@x.com>")])[0].canUnsubscribe, "has target")
        expect(
            !Grouping().group([msg(2, from: "N <a@y.com>", unsub: nil)])[0].canUnsubscribe,
            "no target")
    }
    // Skips newer messages lacking a target rather than giving up on the group.
    Harness.test("picks the newest message carrying an unsubscribe target") {
        let groups = Grouping().group([
            msg(1, from: "N <a@x.com>", subject: "old", daysAgo: 10),
            msg(2, from: "N <a@x.com>", subject: "newer-no-unsub", daysAgo: 2, unsub: nil),
            msg(3, from: "N <a@x.com>", subject: "newer-with-unsub", daysAgo: 5),
        ])
        eq(groups.first?.unsubscribeSource?.subject, "newer-with-unsub")
    }
    Harness.test("handles an empty input") {
        expect(Grouping().group([]).isEmpty, "empty in, empty out")
    }
    // Regression: notifications@github.com carries a different human's name on
    // every message. Labelling the group after the newest one named 2,286
    // messages "Liang Hu".
    Harness.test("falls back to the key when senders disagree on display name") {
        let groups = Grouping().group([
            msg(1, from: "Liang Hu <notifications@github.com>", daysAgo: 1),
            msg(2, from: "Ana Ruiz <notifications@github.com>", daysAgo: 5),
            msg(3, from: "Sam Poe <notifications@github.com>", daysAgo: 9),
        ])
        eq(groups.count, 1)
        eq(groups.first?.displayName, groups.first?.id.key)
    }
    Harness.test("uses a dominant display name even when a few messages differ") {
        // "Mint" across mostly-consistent senders should still read as Mint.
        let groups = Grouping().group([
            msg(1, from: "Mint <team@mint.com>"),
            msg(2, from: "Mint <team@mint.com>"),
            msg(3, from: "Mint Alerts <team@mint.com>"),
        ])
        eq(groups.first?.displayName, "Mint")
    }
    Harness.test("uses the shared display name when all senders agree") {
        let groups = Grouping().group([
            msg(1, from: "Netflix <info@netflix.com>"),
            msg(2, from: "Netflix <news@netflix.com>"),
        ])
        eq(groups.first?.displayName, "Netflix")
    }
}

// MARK: - Round-tripping through storage

// Regression: the store wrote "One-Click" but ListUnsubscribe looks for the
// canonical "List-Unsubscribe=One-Click" token, so every message came back
// reporting no one-click support — 0% instead of the true 79%.
Harness.suite("Storage round-trip") {
    Harness.test("preserves the one-click flag through the stored token") {
        let stored = "List-Unsubscribe=One-Click"
        let decoded = ListUnsubscribe(header: "<https://ex.com/u>", postHeader: stored)
        eq(decoded?.supportsOneClick, true)
    }
    Harness.test("re-wrapping a bare stored URL parses back to the same target") {
        let original = ListUnsubscribe(header: "<https://ex.com/u?id=1>")
        let bare = original?.webTargets.first?.absoluteString
        let decoded = ListUnsubscribe(header: bare.map { "<\($0)>" })
        eq(decoded?.webTargets.first?.absoluteString, "https://ex.com/u?id=1")
    }
}

// MARK: - GroupID

Harness.suite("GroupID") {
    Harness.test("round-trips through its storage key") {
        for id in [
            GroupID(kind: .domain, key: "acme.com"),
            GroupID(kind: .address, key: "alice@substack.com"),
        ] {
            eq(GroupID(storageKey: id.storageKey), id)
        }
    }
    Harness.test("distinguishes a domain key from an address key with the same text") {
        expect(
            GroupID(kind: .domain, key: "x") != GroupID(kind: .address, key: "x"),
            "kind must participate in equality")
    }
    Harness.test("rejects a malformed storage key") {
        expect(GroupID(storageKey: "nonsense") == nil, "no separator")
        expect(GroupID(storageKey: "bogus:x") == nil, "unknown kind")
    }
}

// MARK: - Browser confirmation heuristic

Harness.suite("UnsubscribeEngine.looksLikeConfirmation") {
    Harness.test("matches common success confirmations") {
        for page in [
            "You have been unsubscribed from our newsletter.",
            "Success! You will no longer receive these emails.",
            "Your subscription has been removed.",
            "You're unsubscribed. Sorry to see you go.",
            "Email preferences updated — you opted out of marketing.",
        ] {
            expect(UnsubscribeEngine.looksLikeConfirmation(page), "should match: \(page)")
        }
    }
    Harness.test("does not match a page still asking for action") {
        for page in [
            "Enter your email to unsubscribe.",
            "Click the button below to confirm your unsubscribe request.",
            "Manage your subscription preferences.",
            "Welcome! Confirm your account to get started.",
        ] {
            expect(!UnsubscribeEngine.looksLikeConfirmation(page), "should NOT match: \(page)")
        }
    }
    Harness.test("is case-insensitive") {
        expect(UnsubscribeEngine.looksLikeConfirmation("UNSUBSCRIBED SUCCESSFULLY"), "upper")
    }
}

// MARK: - MessageStore (in-memory integration)

func makeMessage(
    _ uid: UInt32, from: String, unsub: String? = "<https://ex.com/u>",
    messageId: String = "", deliveredTo: String = ""
) -> EmailMessage {
    EmailMessage(
        uid: MessageUID(uid),
        sender: EmailSender(header: from),
        subject: "s\(uid)",
        receivedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(uid)),
        isUnread: true,
        unsubscribe: ListUnsubscribe(header: unsub),
        deliveredTo: deliveredTo,
        messageId: messageId)
}

Harness.suite("MessageStore") {
    Harness.test("upserts and reads back messages, preserving messageId") {
        do {
            let store = try MessageStore.inMemory()
            try store.upsert([
                makeMessage(1, from: "A <a@x.com>", messageId: "<m1@x.com>", deliveredTo: "me@x.com"),
                makeMessage(2, from: "B <b@y.com>"),
            ])
            eq(try store.count(), 2)
            let all = try store.allMessages()
            eq(all.count, 2)
            let m1 = all.first { $0.uid == MessageUID(1) }
            eq(m1?.messageId, "<m1@x.com>")
            eq(m1?.deliveredTo, "me@x.com")
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("does not filter ignored senders out of allMessages") {
        // Regression: ignored senders must remain in the model so the Ignored
        // collection can show them.
        do {
            let store = try MessageStore.inMemory()
            try store.upsert([makeMessage(1, from: "A <a@x.com>")])
            try store.ignore(GroupID(kind: .domain, key: "x.com"))
            eq(try store.allMessages().count, 1)
            expect(try store.ignoredGroupKeys().contains("domain:x.com"), "key stored")
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("delete removes messages") {
        do {
            let store = try MessageStore.inMemory()
            try store.upsert([makeMessage(1, from: "A <a@x.com>"), makeMessage(2, from: "B <b@y.com>")])
            try store.delete(uids: [MessageUID(1)])
            eq(try store.count(), 1)
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("records and reads unsubscribe history with metadata") {
        do {
            let store = try MessageStore.inMemory()
            let id = GroupID(kind: .domain, key: "acme.com")
            try store.recordUnsubscribe(
                id, senderName: "Acme", senderEmail: "n@acme.com", senderDomain: "acme.com",
                url: "https://acme.com/prefs", outcome: .confirmed)
            let history = try store.unsubscribeHistory()
            let record = history["domain:acme.com"]
            eq(record?.senderName, "Acme")
            eq(record?.url, "https://acme.com/prefs")
            eq(record?.outcome, .confirmed)
            try store.forgetUnsubscribe(id)
            expect(try store.unsubscribeHistory().isEmpty, "forgotten")
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("persists grouping rules") {
        do {
            let store = try MessageStore.inMemory()
            store.setGroupingRules(["github.com": .split, "shop.com": .merge])
            let rules = store.groupingRules()
            eq(rules["github.com"], .split)
            eq(rules["shop.com"], .merge)
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("persists sync token round-trip") {
        do {
            let store = try MessageStore.inMemory()
            expect(try store.syncToken() == nil, "no token initially")
            let token = SyncToken(uidValidity: 42, highestUID: 100, lastSyncedAt: Date())
            try store.setSyncToken(token)
            eq(try store.syncToken()?.uidValidity, 42)
            eq(try store.syncToken()?.highestUID, 100)
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("string-set persistence round-trips") {
        do {
            let store = try MessageStore.inMemory()
            eq(store.stringSet(forKey: "k").count, 0)
            store.setStringSet(["a", "b"], forKey: "k")
            eq(store.stringSet(forKey: "k"), Set(["a", "b"]))
        } catch { expect(false, "threw: \(error)") }
    }
}

// MARK: - Provider detection

Harness.suite("MailProvider") {
    Harness.test("detects known providers by domain, case-insensitively") {
        expect(MailProvider.detect(forEmail: "a@gmail.com")?.id == "gmail", "gmail")
        expect(MailProvider.detect(forEmail: "A@GoogleMail.com")?.id == "gmail", "googlemail alias")
        expect(MailProvider.detect(forEmail: "a@icloud.com")?.id == "icloud", "icloud")
        expect(MailProvider.detect(forEmail: "a@me.com")?.id == "icloud", "me.com alias")
        expect(MailProvider.detect(forEmail: "a@yahoo.com")?.id == "yahoo", "yahoo")
        expect(MailProvider.detect(forEmail: "a@fastmail.com")?.id == "fastmail", "fastmail")
    }
    Harness.test("returns nil for an unknown (custom) domain") {
        expect(MailProvider.detect(forEmail: "a@example.com") == nil, "custom domain")
        expect(MailProvider.detect(forEmail: "not-an-email") == nil, "no @")
    }
    Harness.test("resolved prefers a stored id, then detection, then Gmail") {
        expect(
            MailProvider.resolved(forEmail: "a@example.com", storedID: "fastmail").id == "fastmail",
            "stored id wins")
        expect(
            MailProvider.resolved(forEmail: "a@yahoo.com", storedID: nil).id == "yahoo",
            "detects when no stored id")
        expect(
            MailProvider.resolved(forEmail: "a@example.com", storedID: nil).id == "gmail",
            "falls back to gmail")
        expect(
            MailProvider.resolved(forEmail: "a@example.com", storedID: "bogus").id == "gmail",
            "ignores unknown stored id, falls back")
    }
    Harness.test("webSearchURL is provided for Gmail and nil is possible") {
        expect(
            MailProvider.gmail.webSearchURL(fromSender: "x@y.com") != nil,
            "gmail has a search URL")
    }
}

// MARK: - Security hardening

Harness.suite("Header injection defense") {
    Harness.test("strips CR/LF and control chars from header values") {
        let dirty = "stop\r\nBcc: evil@x.com\r\n\r\nforged body"
        let clean = IMAPBackend.stripControlCharacters(dirty)
        expect(!clean.contains("\r"), "no CR")
        expect(!clean.contains("\n"), "no LF")
        expect(clean.contains("stop"), "keeps printable content")
    }
    Harness.test("rejects a mailto whose subject smuggles CRLF headers, via a valid address") {
        // The address is fine; the subject carries percent-encoded CRLF. The
        // target still parses (address valid) but the composed subject must be
        // neutralized by stripControlCharacters at the rfc822 sink.
        let u = ListUnsubscribe(header: "<mailto:unsub@example.com?subject=stop%0D%0ABcc:evil@x.com>")
        expect(u != nil, "parses")
        if let subject = u?.mailtoTargets.first?.subject {
            let safe = IMAPBackend.stripControlCharacters(subject)
            expect(!safe.contains("\n") && !safe.contains("\r"), "sanitized subject has no CRLF")
        }
    }
}

Harness.suite("Mailto recipient validation") {
    Harness.test("accepts a single well-formed address") {
        expect(ListUnsubscribe.isSingleWellFormedAddress("unsub@example.com"), "plain")
        expect(ListUnsubscribe.isSingleWellFormedAddress("a.b+tag@mail.example.co.uk"), "tagged")
    }
    Harness.test("rejects lists, injection, and malformed addresses") {
        expect(!ListUnsubscribe.isSingleWellFormedAddress("a@b.com,c@d.com"), "comma list")
        expect(!ListUnsubscribe.isSingleWellFormedAddress("a@b.com c@d.com"), "space list")
        expect(!ListUnsubscribe.isSingleWellFormedAddress("a@b.com\r\nBcc:x@y.com"), "CRLF")
        expect(!ListUnsubscribe.isSingleWellFormedAddress("nodomain"), "no @")
        expect(!ListUnsubscribe.isSingleWellFormedAddress("a@localhost"), "no dot in domain")
        expect(!ListUnsubscribe.isSingleWellFormedAddress("<a@b.com>"), "angle brackets")
    }
    Harness.test("drops a mailto target with a multi-recipient address") {
        // Comma is inside the brackets, so it's one URI whose path is a list.
        let u = ListUnsubscribe(header: "<mailto:a@b.com,victim@evil.com?subject=x>")
        expect(u == nil, "no usable target -> nil")
    }
}

Harness.suite("DestinationGuard (SSRF)") {
    func allowed(_ s: String) -> Bool { DestinationGuard.isAllowed(URL(string: s)!) }
    Harness.test("blocks loopback, private, and link-local IP literals") {
        expect(!allowed("http://127.0.0.1/admin"), "loopback v4")
        expect(!allowed("http://10.0.0.5/"), "10/8")
        expect(!allowed("http://192.168.1.1/reboot"), "192.168/16")
        expect(!allowed("http://172.16.4.4/"), "172.16/12")
        expect(!allowed("http://169.254.169.254/latest/meta-data/"), "link-local metadata")
        expect(!allowed("http://[::1]/"), "loopback v6")
        expect(!allowed("http://[::ffff:127.0.0.1]/"), "v4-mapped loopback")
    }
    Harness.test("blocks non-http schemes") {
        expect(!allowed("file:///etc/passwd"), "file scheme")
        expect(!allowed("ftp://example.com/"), "ftp scheme")
    }
    Harness.test("allows a public IP literal") {
        // Documentation/example address block is globally routable unicast.
        expect(allowed("https://93.184.216.34/unsubscribe"), "public v4 literal")
    }
}

Harness.suite("Demo mailbox") {
    let messages = DemoData.messages()

    Harness.test("every message parses into a usable sender") {
        expect(!messages.isEmpty, "demo data is not empty")
        let bad = messages.filter { $0.sender.address.isEmpty || $0.sender.host.isEmpty }
        expect(bad.isEmpty, "all From headers parsed: \(bad.count) failures")
        let unnamed = messages.filter { $0.sender.displayName.isEmpty }
        expect(unnamed.isEmpty, "every sender has a display name")
    }

    Harness.test("covers all four unsubscribe methods, for screenshots") {
        // The demo exists partly to show the method icons. If a refactor drops
        // one of these, the screenshots silently stop demonstrating it.
        let oneClick = messages.contains { $0.unsubscribe?.supportsOneClick == true }
        let web = messages.contains {
            guard let u = $0.unsubscribe else { return false }
            return !u.webTargets.isEmpty && !u.supportsOneClick
        }
        let mailto = messages.contains {
            guard let u = $0.unsubscribe else { return false }
            return u.webTargets.isEmpty && !u.mailtoTargets.isEmpty
        }
        let manual = messages.contains { $0.unsubscribe == nil }
        expect(oneClick, "has a one-click sender")
        expect(web, "has a web-link-only sender")
        expect(mailto, "has a mailto-only sender")
        expect(manual, "has a sender with no unsubscribe at all")
    }

    Harness.test("groups into a plausible table") {
        let groups = Grouping().group(messages)
        expect(groups.count >= 15, "enough rows to fill a window: \(groups.count)")
        expect(groups.allSatisfy { !$0.messages.isEmpty }, "no empty groups")
    }

    Harness.test("messages are ordered newest first and dated in the past") {
        let now = Date()
        expect(messages.allSatisfy { $0.receivedAt <= now }, "nothing from the future")
        let dates = messages.map(\.receivedAt)
        expect(dates == dates.sorted(by: >), "sorted newest first")
    }

    Harness.test("message ids use a reserved domain") {
        // Demo Message-IDs must never collide with, or resolve to, real hosts.
        let leaked = messages.filter { !$0.messageId.hasSuffix("@example.invalid>") }
        expect(leaked.isEmpty, "all demo Message-IDs use .invalid: \(leaked.count) leaked")
    }
}

Harness.suite("Debug reset") {
    Harness.test("resetAllLocalData clears databases, registry, and providers") {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nevermore-reset-\(UUID().uuidString)")
        let registry = AccountRegistry(directory: dir)
        let account = "tester@example.com"

        registry.add(account)
        registry.setProviderID("gmail", for: account)
        // Scoped so the store's SQLite connection is closed before the reset.
        do { _ = try? MessageStore(path: registry.databasePath(for: account)) }
        do { _ = try? MessageStore(path: registry.demoDatabasePath) }

        let fm = FileManager.default
        expect(registry.accounts() == [account], "account registered")
        expect(fm.fileExists(atPath: registry.databasePath(for: account)), "account db exists")
        expect(fm.fileExists(atPath: registry.demoDatabasePath), "demo db exists")

        registry.resetAllLocalData()

        expect(registry.accounts().isEmpty, "account list cleared")
        expect(registry.providerID(for: account) == nil, "provider mapping cleared")
        expect(
            !fm.fileExists(atPath: registry.databasePath(for: account)), "account db deleted")
        expect(!fm.fileExists(atPath: registry.demoDatabasePath), "demo db deleted")
        // -wal/-shm siblings would otherwise resurrect a "reset" database.
        for suffix in ["-wal", "-shm"] {
            expect(
                !fm.fileExists(atPath: registry.databasePath(for: account) + suffix),
                "account db \(suffix) deleted")
        }

        try? fm.removeItem(at: dir)
    }

    Harness.test("reset leaves an unrelated directory's data alone") {
        // The reset walks its own directory only — a second account registry
        // (or a real user's data, if this ever ran with the wrong path) is
        // untouched.
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
        let dirA = base.appendingPathComponent("nevermore-a-\(UUID().uuidString)")
        let dirB = base.appendingPathComponent("nevermore-b-\(UUID().uuidString)")
        let a = AccountRegistry(directory: dirA)
        let b = AccountRegistry(directory: dirB)
        a.add("a@example.com")
        b.add("b@example.com")

        a.resetAllLocalData()

        expect(a.accounts().isEmpty, "A cleared")
        expect(b.accounts() == ["b@example.com"], "B untouched")

        try? FileManager.default.removeItem(at: dirA)
        try? FileManager.default.removeItem(at: dirB)
    }
}

Harness.suite("Unsubscribe header survives the database") {
    // A mailto: token in ?subject= is what makes many unsubscribes work; the
    // store used to keep only the address.
    let header = "<https://ex.com/u?id=1>, <mailto:unsub@ex.com?subject=stop-abc123>"

    Harness.test("all targets and the mailto query round-trip") {
        do {
            let store = try MessageStore.inMemory()
            try store.upsert([
                EmailMessage(
                    uid: MessageUID(1), sender: EmailSender(header: "A <a@ex.com>"),
                    subject: "s", receivedAt: Date(), isUnread: true,
                    unsubscribe: ListUnsubscribe(
                        header: header, postHeader: "List-Unsubscribe=One-Click"))
            ])
            guard let back = try store.allMessages().first?.unsubscribe else {
                return expect(false, "message read back")
            }
            expect(back.webTargets.count == 1, "web target kept")
            expect(back.mailtoTargets.count == 1, "mailto target kept — was dropped entirely")
            expect(
                back.mailtoTargets.first?.subject == "stop-abc123",
                "mailto subject token kept: \(back.mailtoTargets.first?.subject ?? "nil")")
            expect(back.supportsOneClick, "one-click flag kept")
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("legacy rows holding a bare URI still decode") {
        // Rows written by the previous format have no angle brackets.
        do {
            let store = try MessageStore.inMemory()
            try store.upsert([makeMessage(2, from: "B <b@ex.com>", unsub: "<https://ex.com/legacy>")])
            let back = try store.allMessages().first?.unsubscribe
            expect(
                back?.webTargets.first?.absoluteString == "https://ex.com/legacy",
                "legacy URI decodes")
        } catch { expect(false, "threw: \(error)") }
    }
}

Harness.suite("Sender label determinism") {
    Harness.test("two equally-common display names pick the same one every time") {
        func label() -> String {
            SenderGroup(
                id: GroupID(kind: .domain, key: "ex.com"),
                messages: [
                    EmailMessage(
                        uid: MessageUID(1), sender: EmailSender(header: "Zeta <z@ex.com>"),
                        subject: "", receivedAt: Date(), isUnread: false, unsubscribe: nil),
                    EmailMessage(
                        uid: MessageUID(2), sender: EmailSender(header: "Alpha <a@ex.com>"),
                        subject: "", receivedAt: Date(), isUnread: false, unsubscribe: nil),
                ]
            ).displayName
        }
        let first = label()
        expect(first == "Alpha", "ties resolve to the lexicographically first name, got \(first)")
        expect((0..<50).allSatisfy { _ in label() == first }, "stable across repeats")
    }
}

Harness.suite("Per-message webmail links") {
    Harness.test("Gmail links via rfc822msgid, brackets stripped") {
        let url = MailProvider.gmail.webMessageURL(messageId: "<abc123@mail.example.com>")
        eq(
            url?.absoluteString,
            "https://mail.google.com/mail/u/0/#search/rfc822msgid:abc123%40mail.example.com")
    }

    Harness.test("characters that would break the URL are encoded") {
        // Real Message-IDs contain +, /, ?, & and = — left raw they'd be read
        // as URL syntax and land on the wrong search.
        let url = MailProvider.gmail.webMessageURL(messageId: "<a+b/c?d&e=f@ex.com>")
        let s = url?.absoluteString ?? ""
        expect(s.contains("%2B"), "+ encoded")
        expect(s.contains("%2F"), "/ encoded")
        expect(s.contains("%3F"), "? encoded")
        expect(s.contains("%26"), "& encoded")
        expect(s.contains("%3D"), "= encoded")
        expect(!s.dropFirst("https://mail.google.com/mail/u/0/#search/rfc822msgid:".count)
            .contains("@"), "@ encoded")
    }

    Harness.test("no link without a message id, or for other providers") {
        expect(MailProvider.gmail.webMessageURL(messageId: "") == nil, "empty id")
        expect(MailProvider.gmail.webMessageURL(messageId: "<>") == nil, "brackets only")
        for other in MailProvider.known where other.id != "gmail" {
            expect(
                other.webMessageURL(messageId: "<a@b.com>") == nil,
                "\(other.id) has no documented per-message link")
        }
    }
}

Harness.suite("Trash batching") {
    /// Stands in for the IMAP server: records each MOVE's size and can be told
    /// to fail once a cumulative limit is passed, the way a real timeout does.
    final class FakeMover: @unchecked Sendable {
        var batches: [Int] = []
        var failAfterMoved: Int?
        func move(_ count: Int, movedSoFar: Int) throws {
            if let limit = failAfterMoved, movedSoFar + count > limit {
                struct Timeout: Error {}
                throw Timeout()
            }
            batches.append(count)
        }
    }

    /// Mirrors IMAPBackend.trash's loop so the batching rule is testable
    /// without a live server.
    func runTrash(uids: [MessageUID], chunk: Int, mover: FakeMover) throws -> [MessageUID] {
        var moved: [MessageUID] = []
        var offset = 0
        while offset < uids.count {
            let end = min(offset + chunk, uids.count)
            let batch = Array(uids[offset..<end])
            do {
                try mover.move(batch.count, movedSoFar: moved.count)
                moved.append(contentsOf: batch)
            } catch {
                if moved.isEmpty { throw error }
                return moved
            }
            offset = end
        }
        return moved
    }

    let many = (1...1127).map { MessageUID(UInt32($0)) }

    Harness.test("a 1,127-message trash is split into bounded batches") {
        // The bug: one MOVE with every UID timed out and moved nothing.
        let mover = FakeMover()
        let moved = try? runTrash(uids: many, chunk: 200, mover: mover)
        eq(moved?.count, 1127)
        eq(mover.batches.count, 6)
        expect(mover.batches.allSatisfy { $0 <= 200 }, "no batch exceeds the limit")
        eq(mover.batches.reduce(0, +), 1127)
    }

    Harness.test("a mid-run failure reports what actually moved") {
        let mover = FakeMover()
        mover.failAfterMoved = 500
        let moved = try? runTrash(uids: many, chunk: 200, mover: mover)
        // Two full batches land; the third would cross the limit and stops it.
        eq(moved?.count, 400)
        expect((moved?.count ?? 0) < many.count, "partial, not all")
    }

    Harness.test("failing on the very first batch throws instead of claiming success") {
        let mover = FakeMover()
        mover.failAfterMoved = 0
        var threw = false
        do { _ = try runTrash(uids: many, chunk: 200, mover: mover) } catch { threw = true }
        expect(threw, "nothing moved -> error, not an empty success")
    }
}

Harness.suite("Selection cursor") {
    func ids(_ names: [String]) -> [GroupID] { names.map { GroupID(kind: .domain, key: $0) } }
    func set(_ names: [String]) -> Set<GroupID> { Set(ids(names)) }
    let list = ids(["a", "b", "c", "d", "e"])

    Harness.test("single selection lands on the row below") {
        eq(SelectionCursor.rowAfterRemoving(set(["b"]), from: list)?.key, "c")
    }

    Harness.test("a contiguous block lands below the whole block") {
        // The bug: `selection.first` on a Set could pick "b", land on "c",
        // and select a row that was itself about to disappear.
        eq(SelectionCursor.rowAfterRemoving(set(["b", "c", "d"]), from: list)?.key, "e")
    }

    Harness.test("a scattered selection skips every selected row") {
        eq(SelectionCursor.rowAfterRemoving(set(["a", "c", "e"]), from: list)?.key, "d")
        eq(SelectionCursor.rowAfterRemoving(set(["b", "d", "e"]), from: list)?.key, "c")
    }

    Harness.test("selecting through the end falls back above the selection") {
        eq(SelectionCursor.rowAfterRemoving(set(["d", "e"]), from: list)?.key, "c")
        eq(SelectionCursor.rowAfterRemoving(set(["e"]), from: list)?.key, "d")
    }

    Harness.test("selecting everything leaves nowhere to go") {
        expect(
            SelectionCursor.rowAfterRemoving(set(["a", "b", "c", "d", "e"]), from: list) == nil,
            "nil, not a ghost row")
        expect(SelectionCursor.rowAfterRemoving([], from: list) == nil, "empty selection")
        expect(SelectionCursor.rowAfterRemoving(set(["a"]), from: []) == nil, "empty list")
    }

    Harness.test("the answer doesn't depend on Set iteration order") {
        // The original defect was invisible precisely because it only showed up
        // for some hash orderings. Rebuild the set repeatedly and demand one
        // answer — Set ordering varies per process and per insertion sequence.
        let answers = Set(
            (0..<200).map { seed -> String in
                var s = Set<GroupID>()
                let members = ids(["b", "c", "d"])
                for m in (seed % 2 == 0 ? members : members.reversed()) { s.insert(m) }
                return SelectionCursor.rowAfterRemoving(s, from: list)?.key ?? "nil"
            })
        eq(answers, ["e"])
    }

    Harness.test("j and k anchor on the edge you're travelling from") {
        // Down from the bottom of the block, up from the top — not from an
        // arbitrary row inside it.
        eq(SelectionCursor.move(from: set(["b", "c"]), by: 1, in: list)?.key, "d")
        eq(SelectionCursor.move(from: set(["b", "c"]), by: -1, in: list)?.key, "a")
    }

    Harness.test("moving past either end stays put") {
        eq(SelectionCursor.move(from: set(["e"]), by: 1, in: list)?.key, "e")
        eq(SelectionCursor.move(from: set(["a"]), by: -1, in: list)?.key, "a")
    }

    Harness.test("no selection enters the list from the travelling end") {
        eq(SelectionCursor.move(from: [], by: 1, in: list)?.key, "a")
        eq(SelectionCursor.move(from: [], by: -1, in: list)?.key, "e")
    }
}

Harness.suite("Pre-migration backup") {
    Harness.test("a fresh database is not backed up") {
        do {
            let path = FileManager.default.temporaryDirectory
                .appendingPathComponent("nm-fresh-\(UUID().uuidString).sqlite").path
            _ = try MessageStore(path: path)
            expect(
                !FileManager.default.fileExists(atPath: path + ".pre-v1.bak"),
                "nothing to preserve on a brand-new store")
            try? FileManager.default.removeItem(atPath: path)
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("reopening an already-migrated database makes no new backup") {
        // Every launch runs the migrator; only a *pending* migration should
        // trigger a copy, or the app would duplicate the cache on every start.
        do {
            let path = FileManager.default.temporaryDirectory
                .appendingPathComponent("nm-again-\(UUID().uuidString).sqlite").path
            _ = try MessageStore(path: path)
            _ = try MessageStore(path: path)
            let siblings = try FileManager.default.contentsOfDirectory(
                atPath: FileManager.default.temporaryDirectory.path
            ).filter { $0.hasPrefix(URL(fileURLWithPath: path).lastPathComponent) && $0.hasSuffix(".bak") }
            expect(siblings.isEmpty, "no backup written: \(siblings)")
            try? FileManager.default.removeItem(atPath: path)
        } catch { expect(false, "threw: \(error)") }
    }
}

exit(Harness.finish())
