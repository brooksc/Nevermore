import Foundation
import Network
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
    messageId: String = "", deliveredTo: String = "", listID: String? = nil
) -> EmailMessage {
    EmailMessage(
        uid: MessageUID(uid),
        sender: EmailSender(header: from),
        subject: "s\(uid)",
        receivedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(uid)),
        isUnread: true,
        unsubscribe: ListUnsubscribe(header: unsub),
        deliveredTo: deliveredTo,
        messageId: messageId,
        listID: listID)
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

Harness.suite("Demo unsubscribe history") {
    // The demo seeds unsubscribe records so Reappeared is not empty. Whether a
    // seeded sender reads as reappeared or as honoured is not a flag: it falls
    // out of comparing the record's date against that sender's newest message,
    // exactly as it does for a real unsubscribe. These tests use that same
    // comparison, so they fail if the seed dates drift past the mail.
    let now = Date()
    let groups = Grouping().group(DemoData.messages(now: now))
    let planned = DemoData.plannedUnsubscribes(for: groups, now: now)

    func newest(_ id: GroupID) -> Date {
        groups.first { $0.id == id }?.messages.map(\.receivedAt).max() ?? .distantPast
    }

    Harness.test("every prior unsubscribe matches a sender in the demo mailbox") {
        expect(
            planned.count == DemoData.priorUnsubscribes.count,
            "matched \(planned.count) of \(DemoData.priorUnsubscribes.count)")
    }

    Harness.test("two senders kept mailing after the request") {
        let reappeared = planned.filter { newest($0.groupID) > $0.attemptedAt }
        expect(reappeared.count == 2, "expected 2 reappeared, got \(reappeared.count)")
    }

    Harness.test("two senders honoured it, so the contrast lands") {
        let honoured = planned.filter { newest($0.groupID) <= $0.attemptedAt }
        expect(honoured.count == 2, "expected 2 honoured, got \(honoured.count)")
    }

    Harness.test("one reappearance is a confirmed unsubscribe") {
        // The unflattering case the app exists to catch: a sender that showed a
        // confirmation page and carried on regardless.
        let confirmedAndBack = planned.contains {
            $0.outcome == "confirmed" && newest($0.groupID) > $0.attemptedAt
        }
        expect(confirmedAndBack, "a confirmed unsubscribe is among the reappeared")
    }

    Harness.test("records carry the sender details a real one would") {
        expect(planned.allSatisfy { !$0.senderName.isEmpty }, "every record names its sender")
        expect(planned.allSatisfy { $0.senderEmail.contains("@") }, "every record has an address")
        expect(planned.allSatisfy { !$0.senderDomain.isEmpty }, "every record has a domain")
    }

    Harness.test("outcomes are values the store accepts") {
        // A typo here would be silently dropped by the app, leaving Reappeared
        // empty for the reason this whole feature exists to avoid.
        let valid = Set(["requested", "confirmed", "failed"])
        expect(planned.allSatisfy { valid.contains($0.outcome) }, "outcomes are known values")
    }

    Harness.test("attempt dates are in the past") {
        expect(planned.allSatisfy { $0.attemptedAt < now }, "nothing attempted in the future")
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

    Harness.test("a known account routes via authuser, not /u/0/") {
        // /u/0/ is "whichever Google account signed in first", which is the
        // wrong mailbox for anyone with several. Verified in a real browser:
        // /mail/u/<email>/ gives Gmail's "Temporary Error"; ?authuser= resolves.
        let url = MailProvider.gmail.webMessageURL(
            messageId: "<abc@ex.com>", account: "someone@gmail.com")
        eq(
            url?.absoluteString,
            "https://mail.google.com/mail/?authuser=someone@gmail.com#search/rfc822msgid:abc%40ex.com"
        )
        let search = MailProvider.gmail.webSearchURL(
            fromSender: "news@ex.com", account: "someone@gmail.com")
        expect(
            search?.absoluteString.contains("?authuser=someone@gmail.com#search/from:") == true,
            "sender search also routes: \(search?.absoluteString ?? "nil")")
    }

    Harness.test("a Gmail thread id becomes a direct conversation link") {
        // Gmail's web UI addresses threads by lowercase hex of the decimal
        // X-GM-THRID. 1785028440153 -> 19f9c0f2599.
        let url = MailProvider.gmail.webThreadURL(
            threadID: 1_785_028_440_153, account: "someone@gmail.com")
        eq(
            url?.absoluteString,
            "https://mail.google.com/mail/?authuser=someone@gmail.com#all/19f9bfc7059")
    }

    Harness.test("thread links are Gmail-only and reject a zero id") {
        expect(
            MailProvider.gmail.webThreadURL(threadID: 0) == nil, "0 is not a thread")
        for other in MailProvider.known where other.id != "gmail" {
            expect(other.webThreadURL(threadID: 123) == nil, "\(other.id) has no thread URL")
        }
    }

    Harness.test("no account falls back to /u/0/") {
        expect(
            MailProvider.gmail.webMessageURL(messageId: "<a@b.com>", account: nil)?
                .absoluteString.contains("/mail/u/0/") == true,
            "unchanged when the account is unknown")
        expect(
            MailProvider.gmail.webMessageURL(messageId: "<a@b.com>", account: "not-an-email")?
                .absoluteString.contains("/mail/u/0/") == true,
            "a malformed account can't produce a broken authuser URL")
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

Harness.suite("Forwarded-address mailto handling") {
    Harness.test("a tokenised mailto identifies the recipient") {
        // ?subject= carries the sender's own token, so which address you send
        // from doesn't matter.
        let u = ListUnsubscribe(header: "<mailto:unsub@ex.com?subject=unsub-a1b2c3>")
        eq(u?.mailtoTargets.first?.identifiesRecipient, true)
        eq(u?.mailtoTargets.first?.subject, "unsub-a1b2c3")
    }

    Harness.test("a bare mailto identifies you only by the From address") {
        let u = ListUnsubscribe(header: "<mailto:unsub@ex.com>")
        eq(u?.mailtoTargets.first?.identifiesRecipient, false)
        // Falls back to a generic subject, which tells the sender nothing.
        eq(u?.mailtoTargets.first?.subject, "unsubscribe")
    }

    Harness.test("a body token counts too") {
        let u = ListUnsubscribe(header: "<mailto:u@ex.com?body=remove%20id%3A99>")
        eq(u?.mailtoTargets.first?.identifiesRecipient, true)
    }

    Harness.test("needsManual carries a reason the UI can show") {
        // Both cases land in the same bucket but mean different things to a
        // user: one has no link at all, the other can't be sent as you.
        let noLink = UnsubscribeEngine.Outcome.needsManual(reason: "no unsubscribe link")
        let wrongIdentity = UnsubscribeEngine.Outcome.needsManual(
            reason: "delivered to alias@ex.com, which you can't send from")
        expect(noLink != wrongIdentity, "distinguishable")
        expect(!noLink.isSuccess && !wrongIdentity.isSuccess, "neither counts as done")
    }
}

Harness.suite("Mailing list detection") {
    Harness.test("List-ID with a description keeps only the identifier") {
        eq(
            MailingList.id(fromHeader: "Ruby Talk <ruby-talk.ruby-lang.org>"),
            "ruby-talk.ruby-lang.org")
        eq(
            MailingList.id(fromHeader: "<ptamemberconnection.wastatepta.org>"),
            "ptamemberconnection.wastatepta.org")
    }

    Harness.test("case and whitespace are normalised") {
        eq(MailingList.id(fromHeader: "  <Ruby-Talk.Example.ORG>  "), "ruby-talk.example.org")
    }

    Harness.test("a bare identifier is accepted, a bare description is not") {
        eq(MailingList.id(fromHeader: "list.example.com"), "list.example.com")
        // A phrase with no brackets is a description missing its id.
        expect(MailingList.id(fromHeader: "Some Newsletter") == nil, "description alone")
        expect(MailingList.id(fromHeader: nil) == nil, "absent")
        expect(MailingList.id(fromHeader: "") == nil, "empty")
        expect(MailingList.id(fromHeader: "<>") == nil, "empty brackets")
    }

    Harness.test("a group reports its list id from any message that carries one") {
        // Senders don't always repeat List-ID on every message.
        let group = SenderGroup(
            id: GroupID(kind: .domain, key: "ex.org"),
            messages: [
                makeMessage(2, from: "L <l@ex.org>"),
                makeMessage(1, from: "L <l@ex.org>", listID: "chat.ex.org"),
            ])
        eq(group.mailingListID, "chat.ex.org")
        expect(group.isMailingList, "flagged as a list")
    }

    Harness.test("ordinary marketing is not a mailing list") {
        let group = SenderGroup(
            id: GroupID(kind: .domain, key: "shop.com"),
            messages: [makeMessage(1, from: "Shop <a@shop.com>")])
        expect(!group.isMailingList, "no List-ID means not a list")
    }
}

// MARK: - Agent decisions about senders

/// The decision records for whichever group in `groups` has this id, as a set of
/// "address/classification" strings — enough to prove nothing was lost, without
/// depending on ordering.
func decisionSummary(
    _ store: MessageStore, _ groups: [SenderGroup], _ id: GroupID
) throws -> Set<String> {
    guard let group = groups.first(where: { $0.id == id }) else { return [] }
    return Set(try store.decisions(for: group).map { "\($0.address)/\($0.classification)" })
}

Harness.suite("Sender decisions") {
    Harness.test("stores classification, reason and context verbatim") {
        do {
            let store = try MessageStore.inMemory()
            let when = Date(timeIntervalSince1970: 1_700_000_000)
            try store.recordDecision(
                address: "jobs@recruiter.com",
                classification: "  Keep While Searching  ",
                reason: "Sends the only listings worth reading; noisy but useful.",
                context: "job-search-2026",
                decidedAt: when)
            let d = try store.decision(forAddress: "jobs@recruiter.com")
            // Whitespace and case are the agent's, not ours to tidy.
            eq(d?.classification, "  Keep While Searching  ")
            eq(d?.reason, "Sends the only listings worth reading; noisy but useful.")
            eq(d?.context, "job-search-2026")
            eq(d?.decidedAt.timeIntervalSince1970, when.timeIntervalSince1970)
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("a later decision supersedes the earlier one for that sender") {
        do {
            let store = try MessageStore.inMemory()
            try store.recordDecision(
                address: "a@x.com", classification: "keep", reason: "useful",
                context: "job-search-2026")
            try store.recordDecision(
                address: "a@x.com", classification: "drop", reason: "changed my mind",
                context: nil)
            eq(try store.allDecisions().count, 1)
            eq(try store.decision(forAddress: "a@x.com")?.classification, "drop")
            expect(try store.decision(forAddress: "a@x.com")?.context == nil, "context cleared")
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("addresses match case-insensitively, unlike the agent's text") {
        do {
            let store = try MessageStore.inMemory()
            try store.recordDecision(
                address: "News@Acme.COM", classification: "Keep", reason: "r", context: "C")
            eq(try store.decision(forAddress: "news@acme.com")?.classification, "Keep")
            // The context is an opaque label: "C" and "c" are different labels.
            eq(try store.decisions(inContext: "C").count, 1)
            eq(try store.decisions(inContext: "c").count, 0)
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("query by context is an exact match, not a search") {
        do {
            let store = try MessageStore.inMemory()
            try store.recordDecision(
                address: "a@x.com", classification: "keep", reason: "r1",
                context: "job-search-2026")
            try store.recordDecision(
                address: "b@x.com", classification: "keep", reason: "r2",
                context: "job-search-2026")
            try store.recordDecision(
                address: "c@x.com", classification: "drop", reason: "r3", context: "house-move")
            try store.recordDecision(
                address: "d@x.com", classification: "keep", reason: "r4", context: nil)

            eq(
                Set(try store.decisions(inContext: "job-search-2026").map(\.address)),
                Set(["a@x.com", "b@x.com"]))
            eq(try store.decisions(inContext: "house-move").map(\.address), ["c@x.com"])
            // No prefix, substring or fuzzy matching — the app does not read the
            // words, it matches the label the agent wrote.
            eq(try store.decisions(inContext: "job-search").count, 0)
            eq(try store.decisions(inContext: "job").count, 0)
            // An unconditional decision belongs to no cohort.
            eq(try store.decisions(inContext: "").count, 0)
            eq(try store.decisionContexts(), ["house-move", "job-search-2026"])
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("a decision survives sync deleting and re-adding the messages") {
        do {
            let store = try MessageStore.inMemory()
            try store.upsert([makeMessage(1, from: "Acme <news@acme.com>")])
            try store.recordDecision(
                address: "news@acme.com", classification: "keep", reason: "r",
                context: "job-search-2026")
            // A full re-sync: drop the local cache, fetch it again.
            try store.deleteAllMessages()
            try store.upsert([makeMessage(2, from: "Acme <news@acme.com>")])
            eq(try store.decision(forAddress: "news@acme.com")?.classification, "keep")
            eq(try store.decisions(inContext: "job-search-2026").count, 1)
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("decisions persist across reopening the same database") {
        do {
            let path = FileManager.default.temporaryDirectory
                .appendingPathComponent("nm-decisions-\(UUID().uuidString).sqlite").path
            do {
                let store = try MessageStore(path: path)
                try store.recordDecision(
                    address: "a@x.com", classification: "keep", reason: "r", context: "ctx")
            }
            let reopened = try MessageStore(path: path)
            eq(try reopened.decision(forAddress: "a@x.com")?.reason, "r")
            // ...and die with the file, which is what account removal and
            // resetAllState delete. A different account starts with none.
            let other = try MessageStore.inMemory()
            expect(try other.allDecisions().isEmpty, "not shared between accounts")
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: path + suffix)
            }
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("forgetting removes one decision, or all of them") {
        do {
            let store = try MessageStore.inMemory()
            try store.recordDecision(
                address: "a@x.com", classification: "keep", reason: "r", context: "ctx")
            try store.recordDecision(
                address: "b@x.com", classification: "drop", reason: "r", context: "ctx")
            try store.forgetDecision(forAddress: "A@X.com")
            eq(try store.allDecisions().count, 1)
            try store.forgetAllDecisions()
            expect(try store.allDecisions().isEmpty, "all forgotten")
            expect(try store.decisionContexts().isEmpty, "no contexts left")
        } catch { expect(false, "threw: \(error)") }
    }
}

// MARK: - Decisions survive regrouping

// The reason records key on address rather than GroupID: splitByAddress and
// keepAsOneGroup move a sender between a `domain:` group and an `address:` one,
// so a GroupID key would silently discard the agent's judgement every time the
// user regrouped a domain.
Harness.suite("Decisions survive regrouping") {
    // Two senders on one registrable domain, with distinct display names so the
    // automatic grouping has an opinion that the user's rule then overrides.
    let messages = [
        makeMessage(1, from: "Acme Deals <deals@acme.com>"),
        makeMessage(2, from: "Acme Deals <deals@acme.com>"),
        makeMessage(3, from: "Acme Status <status@acme.com>"),
    ]
    let merged = GroupID(kind: .domain, key: "acme.com")
    let deals = GroupID(kind: .address, key: "deals@acme.com")
    let status = GroupID(kind: .address, key: "status@acme.com")

    func seeded() throws -> MessageStore {
        let store = try MessageStore.inMemory()
        try store.upsert(messages)
        try store.recordDecision(
            address: "deals@acme.com", classification: "unsubscribe-later",
            reason: "Only worth it during the sale.", context: "job-search-2026")
        try store.recordDecision(
            address: "status@acme.com", classification: "keep",
            reason: "Outage notices.", context: nil)
        return store
    }

    Harness.test("merged, then split by address") {
        do {
            let store = try seeded()
            // As the user sees it merged: the group rolls up both decisions.
            let mergedGroups = Grouping(rules: ["acme.com": .merge]).group(messages)
            eq(
                try decisionSummary(store, mergedGroups, merged),
                Set(["deals@acme.com/unsubscribe-later", "status@acme.com/keep"]))

            // splitByAddress: each address group carries away exactly its own.
            let splitGroups = Grouping(rules: ["acme.com": .split]).group(messages)
            eq(try decisionSummary(store, splitGroups, deals), Set(["deals@acme.com/unsubscribe-later"]))
            eq(try decisionSummary(store, splitGroups, status), Set(["status@acme.com/keep"]))
            eq(try store.allDecisions().count, 2)
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("split, then kept as one group") {
        do {
            let store = try seeded()
            let splitGroups = Grouping(rules: ["acme.com": .split]).group(messages)
            eq(try decisionSummary(store, splitGroups, deals), Set(["deals@acme.com/unsubscribe-later"]))

            // keepAsOneGroup: both decisions roll back up under the domain.
            let mergedGroups = Grouping(rules: ["acme.com": .merge]).group(messages)
            eq(
                try decisionSummary(store, mergedGroups, merged),
                Set(["deals@acme.com/unsubscribe-later", "status@acme.com/keep"]))
            eq(try store.allDecisions().count, 2)
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("regrouping back and forth loses nothing, including the context") {
        do {
            let store = try seeded()
            for rule in [Grouping.Rule.merge, .split, .merge, .split, .merge] {
                _ = Grouping(rules: ["acme.com": rule]).group(messages)
            }
            eq(try store.allDecisions().count, 2)
            eq(try store.decisions(inContext: "job-search-2026").map(\.address), ["deals@acme.com"])
            eq(try store.decision(forAddress: "deals@acme.com")?.reason,
               "Only worth it during the sale.")
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("a group with no decided senders reports none") {
        do {
            let store = try seeded()
            let group = SenderGroup(
                id: GroupID(kind: .domain, key: "other.com"),
                messages: [makeMessage(9, from: "Other <hi@other.com>")])
            expect(try store.decisions(for: group).isEmpty, "nothing decided here")
        } catch { expect(false, "threw: \(error)") }
    }
}

// MARK: - Loopback HTTP server

// The harness runs each test synchronously, and everything below is actor-isolated
// or built on NWListener. Run the async body on the cooperative pool and block until
// it finishes — nothing here needs the main thread, so there is no deadlock to hit.
private final class ResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?
    var value: T? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

func runAsync<T: Sendable>(_ body: @escaping @Sendable () async -> T) -> T {
    let box = ResultBox<T>()
    let done = DispatchSemaphore(value: 0)
    Task {
        box.value = await body()
        done.signal()
    }
    done.wait()
    return box.value!
}

/// A real listener occupying a contract port, so the server has to deal with it the way it would in
/// the field. Uses the server's own parameters, so "taken" means taken the same way.
final class HeldPort {
    private let listener: NWListener
    fileprivate init(_ listener: NWListener) { self.listener = listener }

    /// Wait for `.cancelled` before returning. `NWListener.cancel()` returns before the OS has
    /// released the port, so a test that merely cancels leaves the next one binding a port that is
    /// still occupied — which shows up as an unrelated test failing intermittently.
    func release() {
        let done = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .cancelled = state { done.signal() }
        }
        listener.cancel()
        _ = done.wait(timeout: .now() + 3)
    }
}

func holdPort(_ port: UInt16) -> HeldPort? {
    guard let nwPort = NWEndpoint.Port(rawValue: port),
          let listener = try? NWListener(using: NevermoreServer.listenerParameters(), on: nwPort)
    else { return nil }
    let ready = DispatchSemaphore(value: 0)
    listener.stateUpdateHandler = { state in
        if case .ready = state { ready.signal() }
    }
    listener.newConnectionHandler = { $0.cancel() }
    listener.start(queue: .global())
    guard ready.wait(timeout: .now() + 3) == .success else {
        listener.cancel()
        return nil
    }
    return HeldPort(listener)
}

Harness.suite("Server port contract") {
    Harness.test("is 8775-8779, and does not collide with jobhunt's range") {
        eq(ServerPortContract.firstPort, 8775)
        eq(ServerPortContract.lastPort, 8779)
        eq(ServerPortContract.discoveryPorts, [8775, 8776, 8777, 8778, 8779])
        // jobhunt owns 8765-8769 and 8770-8774 is its growth gap. Two apps, one Mac.
        expect(!ServerPortContract.discoveryPorts.contains(where: { $0 < 8775 }), "no overlap below")
    }

    Harness.test("the listener is restricted to loopback") {
        // This restriction IS the security boundary — a non-loopback peer is refused by the OS and
        // never reaches route handling. Asserted here so it can't be dropped without a red test.
        eq(NevermoreServer.listenerParameters().requiredInterfaceType, .loopback)
    }
}

Harness.suite("Server port binding") {
    Harness.test("falls back to the next contract port when the first is taken") {
        guard let held = holdPort(ServerPortContract.firstPort) else {
            expect(false, "could not occupy \(ServerPortContract.firstPort) to set up the test")
            return
        }
        defer { held.release() }

        let bound: UInt16 = runAsync {
            let server = NevermoreServer()
            try? await server.start()
            let p = await server.port
            await server.stop()
            return p
        }
        eq(bound, ServerPortContract.firstPort + 1, "skipped the occupied port")
    }

    Harness.test("fails closed when every contract port is taken") {
        var held: [HeldPort] = []
        for p in ServerPortContract.discoveryPorts {
            guard let l = holdPort(p) else { break }
            held.append(l)
        }
        guard held.count == ServerPortContract.discoveryPorts.count else {
            held.forEach { $0.release() }
            expect(false, "could not occupy all \(ServerPortContract.discoveryPorts.count) ports")
            return
        }
        defer { held.forEach { $0.release() } }

        struct Outcome: Sendable {
            let error: ServerError?
            let port: UInt16
            let listening: Bool
        }
        let outcome: Outcome = runAsync {
            let server = NevermoreServer()
            var caught: ServerError?
            do { try await server.start() } catch let e as ServerError { caught = e } catch {}
            let boundPort = await server.port
            let listening = await server.isListening
            await server.stop()
            return Outcome(error: caught, port: boundPort, listening: listening)
        }
        // No ephemeral fallback: a port the bridge can't guess is worse than no server at all,
        // because "running" and "unreachable" look identical from the client side.
        eq(outcome.error, ServerError.noPortAvailable)
        eq(outcome.port, 0, "did not bind anything")
        expect(!outcome.listening, "no listener left behind")
        expect(outcome.error?.localizedDescription.contains("8775") == true, "failure names the range")
    }
}

Harness.suite("Server over a real socket") {
    Harness.test("a loopback client gets the health route off the wire") {
        // The routing tests call routeRequest directly; this is the only one that proves the
        // listener accepts, the parser frames, and the response serialises as real HTTP.
        struct Result: Sendable {
            let status: Int
            let body: String
            let port: UInt16
        }
        let result: Result? = runAsync {
            let server = NevermoreServer(appVersion: "9.9.9")
            // An ephemeral port: this test is about the wire, not about port discovery, and the
            // contract ports may legitimately be busy on a developer's Mac.
            try? await server.startOnAnyPort()
            let port = await server.port
            defer { Task { await server.stop() } }
            guard port != 0,
                  let url = URL(string: "http://127.0.0.1:\(port)/health") else { return nil }
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse else { return nil }
            return Result(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? "",
                port: port)
        }
        guard let result else {
            expect(false, "no response from the loopback server")
            return
        }
        eq(result.status, 200)
        eq(result.body, "{\"ok\":true}")
    }
}

Harness.suite("Server routing") {
    func get(_ path: String, headers: [String: String] = [:]) -> HTTPRequest {
        HTTPRequest(method: "GET", path: path, headers: headers)
    }
    func route(_ request: HTTPRequest, token: String = "") -> HTTPResponse {
        runAsync {
            await NevermoreServer(appVersion: "9.9.9", mcpToken: token).routeRequest(request)
        }
    }
    func bodyText(_ response: HTTPResponse) -> String {
        String(data: response.body, encoding: .utf8) ?? ""
    }

    Harness.test("health and ping answer, so a client can find the port") {
        eq(route(get("/health")).statusCode, 200)
        expect(bodyText(route(get("/health"))).contains("\"ok\":true"), "reports ok")

        let ping = route(get("/api/ping"))
        eq(ping.statusCode, 200)
        expect(bodyText(ping).contains("\"app\":\"nevermore\""), "identifies the app")
        expect(bodyText(ping).contains("9.9.9"), "reports its version")
    }

    Harness.test("an unknown path is 404") {
        eq(route(get("/nope")).statusCode, 404)
    }

    Harness.test("Transfer-Encoding is refused rather than parsed as an empty body") {
        eq(route(get("/health", headers: ["transfer-encoding": "chunked"])).statusCode, 400)
    }

    Harness.test("MCP routes are 503 until a token is configured") {
        // Fail closed: no token must never mean "no token required".
        let r = route(HTTPRequest(method: "POST", path: "/mcp/senders/list"), token: "")
        eq(r.statusCode, 503)
    }

    Harness.test("MCP routes reject a missing or wrong token with 401") {
        let secret = "s3cret-token"
        let mcp = { (headers: [String: String]) in
            route(HTTPRequest(method: "POST", path: "/mcp/senders/list", headers: headers), token: secret)
        }
        eq(mcp([:]).statusCode, 401, "no Authorization header")
        eq(mcp(["authorization": "Bearer wrong"]).statusCode, 401, "wrong token")
        eq(mcp(["authorization": "Bearer "]).statusCode, 401, "empty token")
        eq(mcp(["authorization": secret]).statusCode, 401, "token without the Bearer scheme")
        eq(mcp(["authorization": "Basic \(secret)"]).statusCode, 401, "wrong scheme")
        // Near-misses must not pass: the compare is constant-time, not a prefix match.
        eq(mcp(["authorization": "Bearer s3cret"]).statusCode, 401, "prefix of the token")
        eq(mcp(["authorization": "Bearer s3cret-tokenX"]).statusCode, 401, "token plus a suffix")
    }

    Harness.test("the right token gets past auth, and the scheme is case-insensitive") {
        let secret = "s3cret-token"
        let authed = route(
            HTTPRequest(method: "POST", path: "/mcp/not-a-tool",
                        headers: ["authorization": "bearer \(secret)"]),
            token: secret)
        // Auth passed, so the 404 is about the route rather than the credential. A real tool route
        // is used for that distinction in the TASK-44 suites, where a mailbox exists to serve it.
        eq(authed.statusCode, 404)
        expect(bodyText(authed).contains("MCP route not found"), "404 is about the route")
    }

    Harness.test("a non-POST MCP request is 405, but only after it authenticates") {
        let secret = "s3cret-token"
        eq(route(get("/mcp/senders/list", headers: ["authorization": "Bearer \(secret)"]),
                 token: secret).statusCode, 405)
        // Unauthenticated, the method never gets a say — 401 comes first.
        eq(route(get("/mcp/senders/list"), token: secret).statusCode, 401)
    }

    Harness.test("MCP bodies get a larger budget than the discovery routes") {
        eq(NevermoreServer.maxBodySize(forPath: "/mcp/senders/list"), 1_048_576)
        eq(NevermoreServer.maxBodySize(forPath: "/health"), 64 * 1024)
    }
}

Harness.suite("HTTP framing") {
    func framing(_ raw: String, cap: Int = NevermoreServer.maxHeaderBytes) -> RequestFraming {
        inspectRequestFraming(Data(raw.utf8), maxHeaderBytes: cap)
    }

    Harness.test("a complete GET frames with no body") {
        eq(framing("GET /health HTTP/1.1\r\nHost: x\r\n\r\n"),
           .valid(method: "GET", path: "/health", contentLength: 0))
    }

    Harness.test("headers without a terminator are incomplete, not invalid") {
        eq(framing("GET /health HTTP/1.1\r\nHost: x"), .incomplete)
    }

    Harness.test("headers past the cap are rejected rather than accumulated") {
        let long = "GET /health HTTP/1.1\r\nX: " + String(repeating: "a", count: 200) + "\r\n\r\n"
        eq(framing(long, cap: 64), .invalid(reason: "Request header fields too large", statusCode: 431))
    }

    Harness.test("conflicting or malformed Content-Length is refused") {
        eq(framing("POST /x HTTP/1.1\r\nContent-Length: 3\r\nContent-Length: 4\r\n\r\nabc"),
           .invalid(reason: "Conflicting Content-Length headers", statusCode: 400))
        eq(framing("POST /x HTTP/1.1\r\nContent-Length: -1\r\n\r\n"),
           .invalid(reason: "Malformed Content-Length", statusCode: 400))
        eq(framing("POST /x HTTP/1.1\r\nContent-Length: abc\r\n\r\n"),
           .invalid(reason: "Malformed Content-Length", statusCode: 400))
    }

    Harness.test("a POST with no Content-Length is unframable, not empty") {
        eq(framing("POST /x HTTP/1.1\r\nHost: x\r\n\r\n"),
           .invalid(reason: "Missing Content-Length on POST", statusCode: 400))
    }

    Harness.test("the parser lowercases header names and splits the query") {
        let raw = "GET /api/ping?a=1&b=two HTTP/1.1\r\nAuthorization: Bearer t\r\n\r\n"
        let request = parseHTTPRequest(Data(raw.utf8))
        eq(request?.path, "/api/ping")
        eq(request?.queryValue(for: "b"), "two")
        eq(request?.headers["authorization"], "Bearer t")
        eq(NevermoreServer.bearerToken(from: request!), "t")
    }

    Harness.test("a UTF-8 body is sliced by bytes, not characters") {
        // "Café" is 5 bytes and 4 characters — slicing by character count truncates the JSON.
        let json = "{\"n\":\"Café\"}"
        let bytes = Data(json.utf8)
        let raw = Data("POST /mcp/x HTTP/1.1\r\nContent-Length: \(bytes.count)\r\n\r\n".utf8) + bytes
        eq(parseHTTPRequest(raw)?.body, bytes)
    }

    Harness.test("a body that hasn't fully arrived parses as nil so the server reads more") {
        let raw = "POST /mcp/x HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc"
        expect(parseHTTPRequest(Data(raw.utf8)) == nil, "incomplete body")
    }

    Harness.test("every status the server emits has a real reason phrase") {
        for code in [200, 204, 400, 401, 403, 404, 405, 413, 431, 500, 503] {
            expect(HTTPResponse.statusText(for: code) != "Unknown", "reason phrase for \(code)")
        }
    }
}

Harness.suite("MCP token file") {
    /// A scratch directory so the lifecycle is exercised without touching the real
    /// ~/.nevermore-mcp-token, which a running app may own.
    func withScratchToken(_ body: (URL) -> Void) {
        let dir = URL.temporaryDirectory.appending(path: "nevermore-token-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        body(dir.appending(path: ".nevermore-mcp-token"))
    }

    Harness.test("the real token path is ~/.nevermore-mcp-token") {
        eq(MCPTokenManager.tokenURL.lastPathComponent, ".nevermore-mcp-token")
        eq(MCPTokenManager.tokenURL.deletingLastPathComponent().path,
           URL.homeDirectory.path)
    }

    Harness.test("a written token is 0600 and reads back") {
        withScratchToken { url in
            guard let written = try? MCPTokenManager.generateAndWrite(at: url) else {
                expect(false, "write failed")
                return
            }
            let perms = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int
            eq(perms, 0o600)
            eq(MCPTokenManager.read(at: url), written)
            expect(UUID(uuidString: written) != nil, "a fresh UUID, not a fixed secret")
        }
    }

    Harness.test("each launch gets a different token") {
        withScratchToken { url in
            let first = try? MCPTokenManager.generateAndWrite(at: url)
            let second = try? MCPTokenManager.generateAndWrite(at: url)
            expect(first != second, "transient credential, not a stored one")
        }
    }

    Harness.test("a token with broader permissions is refused on read") {
        // Group- or world-readable means another account could already have taken a copy, so the
        // secret is spent — refuse it rather than authenticate against it.
        for mode in [0o644, 0o640, 0o604, 0o666] {
            withScratchToken { url in
                _ = try? MCPTokenManager.generateAndWrite(at: url)
                try? FileManager.default.setAttributes(
                    [.posixPermissions: mode], ofItemAtPath: url.path)
                expect(MCPTokenManager.read(at: url) == nil, "refused mode \(String(mode, radix: 8))")
            }
        }
        // 0400 is narrower than 0600, so it is still acceptable.
        withScratchToken { url in
            _ = try? MCPTokenManager.generateAndWrite(at: url)
            try? FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: url.path)
            expect(MCPTokenManager.read(at: url) != nil, "0400 is not broader than 0600")
        }
    }

    Harness.test("a missing token reads as nil, and delete is what makes it missing") {
        withScratchToken { url in
            expect(MCPTokenManager.read(at: url) == nil, "nothing written yet")
            _ = try? MCPTokenManager.generateAndWrite(at: url)
            expect(MCPTokenManager.read(at: url) != nil, "present after write")
            MCPTokenManager.delete(at: url)
            expect(!FileManager.default.fileExists(atPath: url.path), "removed on shutdown")
            expect(MCPTokenManager.read(at: url) == nil, "gone")
        }
    }

    Harness.test("a client whose token file went over-permissive is refused, not admitted") {
        // The two halves of the policy composed: the bridge reads the file to get its credential,
        // a widened file reads as nil, so it has nothing to present — and the server answers 401
        // rather than treating an absent credential as "no credential required".
        withScratchToken { url in
            let secret = (try? MCPTokenManager.generateAndWrite(at: url)) ?? ""
            expect(!secret.isEmpty, "a token was written")
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)

            let presented = MCPTokenManager.read(at: url) ?? ""
            expect(presented.isEmpty, "an over-permissive file yields no credential")

            let response = runAsync {
                await NevermoreServer(mcpToken: secret).routeRequest(
                    HTTPRequest(method: "POST", path: "/mcp/senders/list",
                                headers: ["authorization": "Bearer \(presented)"]))
            }
            eq(response.statusCode, 401)
        }
    }

    Harness.test("a token that fails to be written leaves nothing behind") {
        // A directory that doesn't exist makes the write fail; the point is that no partial or
        // over-permissive file survives the failure.
        let url = URL.temporaryDirectory
            .appending(path: "nevermore-missing-\(UUID().uuidString)")
            .appending(path: ".nevermore-mcp-token")
        var threw = false
        do { _ = try MCPTokenManager.generateAndWrite(at: url) } catch { threw = true }
        expect(threw, "the write failure is reported, not swallowed")
        expect(!FileManager.default.fileExists(atPath: url.path), "no leftover file")
    }
}

// MARK: - Local server lifecycle (TASK-48)

Harness.suite("Local server lifecycle") {
    /// A scratch token path, so starting and stopping a server here never disturbs the real
    /// ~/.nevermore-mcp-token that a running Nevermore may own.
    func withScratchTokenPath(_ body: (URL) -> Void) {
        let dir = URL.temporaryDirectory.appending(path: "nevermore-lifecycle-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        body(dir.appending(path: ".nevermore-mcp-token"))
    }

    /// The status code for a POST to an /mcp/ route with whatever credential the token file holds.
    /// 401 means the file and the running server disagree; 503 means they match and the request
    /// got all the way to "no mailbox is open", which is as far as a controller started without an
    /// account can go.
    @Sendable func mcpStatus(port: UInt16, token: String?) async -> Int? {
        guard let url = URL(string: "http://127.0.0.1:\(port)/mcp/senders/list") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization") }
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return nil }
        return (response as? HTTPURLResponse)?.statusCode
    }

    Harness.test("starting binds a contract port and writes the token the server will accept") {
        withScratchTokenPath { tokenURL in
            let controller = LocalServerController(tokenURL: tokenURL, appVersion: "9.9.9")
            let status = runAsync { await controller.start(isDemo: false) }
            defer { runAsync { await controller.stop() } }

            guard case let .running(port) = status else {
                expect(false, "expected a running server, got \(status)")
                return
            }
            expect(ServerPortContract.discoveryPorts.contains(port), "bound a discoverable port")

            // The token file is the only channel to the bridge, so "started" has to mean the file
            // on disk authenticates against the server that is actually listening.
            let token = MCPTokenManager.read(at: tokenURL)
            expect(token != nil, "a 0600 token exists while the server runs")
            eq(runAsync { await mcpStatus(port: port, token: token) }, 503,
               "the written token is accepted (503 is the absent mailbox, not the credential)")
            eq(runAsync { await mcpStatus(port: port, token: nil) }, 401,
               "and the gate is still closed without it")
        }
    }

    Harness.test("stopping releases the port and removes the token file") {
        withScratchTokenPath { tokenURL in
            let controller = LocalServerController(tokenURL: tokenURL)
            let started = runAsync { await controller.start(isDemo: false) }
            guard case let .running(port) = started else {
                expect(false, "expected a running server, got \(started)")
                return
            }
            eq(runAsync { await controller.stop() }, LocalServerStatus.off)
            expect(!FileManager.default.fileExists(atPath: tokenURL.path),
                   "the credential does not outlive the server")
            // Re-binding the port is the only honest proof the OS actually got it back.
            guard let held = holdPort(port) else {
                expect(false, "port \(port) was not released")
                return
            }
            held.release()
        }
    }

    Harness.test("stopping a server that never started is not an error") {
        withScratchTokenPath { tokenURL in
            let controller = LocalServerController(tokenURL: tokenURL)
            eq(runAsync { await controller.stop() }, LocalServerStatus.off)
        }
    }

    Harness.test("a bind failure is reported with the port range, and Retry works once it frees up") {
        withScratchTokenPath { tokenURL in
            var held: [HeldPort] = []
            for p in ServerPortContract.discoveryPorts {
                guard let l = holdPort(p) else { break }
                held.append(l)
            }
            guard held.count == ServerPortContract.discoveryPorts.count else {
                held.forEach { $0.release() }
                expect(false, "could not occupy all \(ServerPortContract.discoveryPorts.count) ports")
                return
            }

            let controller = LocalServerController(tokenURL: tokenURL)
            let failed = runAsync { await controller.start(isDemo: false) }
            guard case let .failed(message) = failed else {
                held.forEach { $0.release() }
                runAsync { await controller.stop() }
                expect(false, "expected a reported failure, got \(failed)")
                return
            }
            // The message is what Settings shows; naming the range is what makes it actionable.
            expect(message.contains("8775"), "the failure names the port range: \(message)")
            expect(message.contains("8779"), "the failure names the port range: \(message)")
            expect(!FileManager.default.fileExists(atPath: tokenURL.path),
                   "a failed start leaves no token behind")

            // Whatever held the ports quits — which is exactly the case Retry exists for.
            held.forEach { $0.release() }
            let retried = runAsync { await controller.start(isDemo: false) }
            defer { runAsync { await controller.stop() } }
            expect(retried.isRunning, "retry succeeded after the ports freed up, got \(retried)")
        }
    }

    Harness.test("the token path is shown before the server has ever run") {
        withScratchTokenPath { tokenURL in
            let controller = LocalServerController(tokenURL: tokenURL)
            eq(controller.tokenPath, tokenURL.path)
        }
        // And the default is the real per-user path, not the scratch one.
        eq(LocalServerController().tokenPath, MCPTokenManager.tokenURL.path)
    }
}

// MARK: - One selection model for every collection (TASK-27)

Harness.suite("Collection membership") {
    func state(
        ignored: Bool = false, unsubscribed: Bool = false,
        reappeared: Bool = false, messages: Bool = true
    ) -> SenderState {
        SenderState(
            isIgnored: ignored, isUnsubscribed: unsubscribed,
            hasReappeared: reappeared, hasMessages: messages)
    }

    Harness.test("a plain sender is in All Senders and nowhere else") {
        let s = state()
        eq(Collection.allCases.filter { $0.contains(s) }, [.allSenders])
    }

    Harness.test("unsubscribing takes a sender out of the working list") {
        let s = state(unsubscribed: true)
        expect(!Collection.allSenders.contains(s), "gone from All Senders")
        expect(Collection.unsubscribed.contains(s), "listed under Unsubscribed")
        expect(!Collection.reappeared.contains(s), "they haven't mailed again")
    }

    Harness.test("mailing again moves a sender from Unsubscribed to Reappeared") {
        let s = state(unsubscribed: true, reappeared: true)
        expect(Collection.reappeared.contains(s), "Reappeared")
        expect(!Collection.unsubscribed.contains(s), "and only there — not both")
    }

    Harness.test("ignoring hides a sender from All Senders and Reappeared") {
        expect(!Collection.allSenders.contains(state(ignored: true)))
        expect(!Collection.reappeared.contains(state(ignored: true, unsubscribed: true, reappeared: true)))
        expect(Collection.ignored.contains(state(ignored: true)))
    }

    // Inherited behaviour, pinned rather than endorsed: Unsubscribed doesn't
    // exclude ignored senders, so one that is both is listed twice. Changing it
    // is a product decision, not part of unifying the selection model.
    Harness.test("an ignored sender with a record is listed in both archives") {
        let s = state(ignored: true, unsubscribed: true)
        eq(Collection.allCases.filter { $0.contains(s) }, [.unsubscribed, .ignored])
    }

    Harness.test("losing their messages doesn't remove a record from Unsubscribed") {
        // The point of the durable log: the record outlives the mail.
        expect(Collection.unsubscribed.contains(state(unsubscribed: true, messages: false)))
    }
}

Harness.suite("Selection across collections") {
    func ids(_ names: [String]) -> [GroupID] { names.map { GroupID(kind: .domain, key: $0) } }
    func set(_ names: [String]) -> Set<GroupID> { Set(ids(names)) }
    let list = ids(["a", "b", "c"])

    // The decision recorded for this task: a selection does not survive a
    // collection switch. It is what fixes the inspector describing a sender the
    // visible list doesn't contain.
    Harness.test("switching collections clears the selection outright") {
        eq(SelectionCursor.surviving(set(["a", "b"]), in: list, collectionChanged: true), [])
    }

    Harness.test("a sender present in both collections is still dropped") {
        // "a" is on screen in the new collection too. It still goes: the same
        // sender is a different decision in each list.
        eq(SelectionCursor.surviving(set(["a"]), in: list, collectionChanged: true), [])
    }

    Harness.test("within one collection the selection survives, minus what left") {
        eq(
            SelectionCursor.surviving(set(["a", "z"]), in: list, collectionChanged: false),
            set(["a"]))
    }

    Harness.test("nothing visible means nothing selected") {
        eq(SelectionCursor.surviving(set(["a"]), in: [], collectionChanged: false), [])
    }
}

Harness.suite("Selection action availability") {
    func context(_ collection: Collection, count: Int, withMessages: Int? = nil)
        -> SelectionContext
    {
        SelectionContext(
            collection: collection, count: count, withMessages: withMessages ?? count)
    }
    func can(_ action: SelectionAction, _ context: SelectionContext) -> Bool {
        action.unavailability(in: context) == nil
    }

    Harness.test("with nothing selected every action says so") {
        for action in SelectionAction.allCases {
            eq(
                action.unavailability(in: context(.allSenders, count: 0)),
                "Select a sender first.", action.rawValue)
        }
    }

    Harness.test("All Senders can do everything except unignore and forget") {
        let c = context(.allSenders, count: 1)
        expect(can(.unsubscribe, c))
        expect(can(.unsubscribeAndDelete, c))
        expect(can(.viewLatestMessage, c))
        expect(can(.ignore, c))
        expect(can(.trash, c))
        expect(!can(.unignore, c), "they aren't ignored")
        expect(!can(.forget, c), "there's no record to forget")
    }

    Harness.test("Ignored offers unignore, and refuses to unsubscribe with a reason") {
        let c = context(.ignored, count: 2)
        expect(can(.unignore, c))
        expect(!can(.ignore, c))
        eq(
            SelectionAction.unsubscribe.unavailability(in: c),
            "Ignored senders are hidden, not unsubscribed. Unignore them first.")
    }

    Harness.test("Unsubscribed refuses a second unsubscribe and says what to do") {
        let c = context(.unsubscribed, count: 1)
        eq(
            SelectionAction.unsubscribe.unavailability(in: c),
            "Already unsubscribed. Forget the record to unsubscribe again.")
        expect(can(.forget, c), "forgetting is the way back")
    }

    Harness.test("a record whose messages are gone can't be opened or trashed") {
        // The Unsubscribed row that outlived its mail. These used to be live
        // controls acting on a sender the app no longer had.
        let c = context(.unsubscribed, count: 1, withMessages: 0)
        expect(!can(.trash, c))
        expect(!can(.viewLatestMessage, c))
        expect(can(.forget, c), "the record itself is still there")
    }

    Harness.test("Reappeared can unsubscribe again — that's what it's for") {
        let c = context(.reappeared, count: 1)
        expect(can(.unsubscribe, c))
        expect(can(.unsubscribeAndDelete, c))
        expect(can(.viewLatestMessage, c), "read it before deciding")
        expect(can(.trash, c))
        expect(can(.forget, c))
    }

    Harness.test("viewing the latest message needs exactly one sender") {
        eq(
            SelectionAction.viewLatestMessage.unavailability(
                in: context(.allSenders, count: 3)),
            "Select a single sender.")
    }

    Harness.test("every refusal is a sentence, not an empty string") {
        // The reason becomes the disabled control's tooltip; a blank one is no
        // better than the silent no-op this replaced.
        for collection in Collection.allCases {
            for action in SelectionAction.allCases {
                for c in [context(collection, count: 1), context(collection, count: 2, withMessages: 0)] {
                    guard let reason = action.unavailability(in: c) else { continue }
                    expect(
                        reason.count > 10 && reason.hasSuffix("."),
                        "\(collection.rawValue)/\(action.rawValue): \(reason)")
                }
            }
        }
    }
}


// MARK: - MCP read surface (TASK-44)

/// One header row, with everything the MCP surface reads off it under control.
func mcpMessage(
    _ uid: UInt32,
    from: String,
    subject: String = "Subject",
    daysAgo: Double = 0,
    unread: Bool = false,
    unsub: String? = "<https://ex.com/u>",
    oneClick: Bool = false,
    listID: String? = nil
) -> EmailMessage {
    EmailMessage(
        uid: MessageUID(uid),
        sender: EmailSender(header: from),
        subject: subject,
        receivedAt: Date(timeIntervalSince1970: 1_700_000_000 - daysAgo * 86400),
        isUnread: unread,
        unsubscribe: ListUnsubscribe(
            header: unsub, postHeader: oneClick ? "List-Unsubscribe=One-Click" : nil),
        listID: listID)
}

/// A snapshot built the way the server builds one: through a real store, so the
/// round-trip that reconstitutes `ListUnsubscribe` from the stored header is
/// part of every route test rather than something the tests fake past.
func mcpSnapshot(_ store: MessageStore, account: String = "me@example.com") throws -> MCPSnapshot {
    try MCPSnapshot.load(MCPContext(account: account, store: store))
}

func mcpCall(_ path: String, _ snapshot: MCPSnapshot, _ arguments: [String: Any] = [:])
    -> HTTPResponse
{
    let body = try? JSONSerialization.data(withJSONObject: arguments)
    let request = HTTPRequest(
        method: "POST", path: path, headers: ["content-type": "application/json"], body: body)
    return MCPRoutes.handle(path: path, request: request, snapshot: snapshot)
        ?? .error("no such route", code: 404)
}

func mcpJSON(_ response: HTTPResponse) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any] ?? [:]
}

func mcpRows(_ response: HTTPResponse, _ key: String = "senders") -> [[String: Any]] {
    mcpJSON(response)[key] as? [[String: Any]] ?? []
}

Harness.suite("Unsubscribe method partition") {
    func method(_ header: String?, oneClick: Bool = false) -> UnsubscribeMethod {
        UnsubscribeMethod.of(
            SenderGroup(
                id: GroupID(kind: .domain, key: "x.com"),
                messages: [mcpMessage(1, from: "A <a@x.com>", unsub: header, oneClick: oneClick)]))
    }

    Harness.test("an RFC 8058 sender is one-click, the same link without it is web") {
        eq(method("<https://ex.com/u>", oneClick: true), .oneClick)
        eq(method("<https://ex.com/u>"), .web)
    }

    Harness.test("a mailto-only sender is mailto, and no header at all is none") {
        eq(method("<mailto:stop@ex.com?subject=off>"), .mailto)
        eq(method(nil), UnsubscribeMethod.none)
    }

    Harness.test("a web target wins over a mailto, matching what the engine would do") {
        // UnsubscribeEngine tries the web target first, so reporting `mailto`
        // here would tell an agent about an attempt the app would never make.
        eq(method("<https://ex.com/u>, <mailto:stop@ex.com>"), .web)
    }

    Harness.test("only 'none' needs a browser — every other method has an automated path") {
        for method in UnsubscribeMethod.allCases {
            eq(method.needsBrowser, method == .none, method.rawValue)
        }
    }

    Harness.test("the method is taken from the newest message that has a target") {
        // Senders drop the header from the odd message; falling back to "none"
        // because the newest one happens to lack it would wrongly queue a sender
        // for the browser.
        let group = SenderGroup(
            id: GroupID(kind: .domain, key: "x.com"),
            messages: [
                mcpMessage(2, from: "A <a@x.com>", daysAgo: 0, unsub: nil),
                mcpMessage(1, from: "A <a@x.com>", daysAgo: 5, oneClick: true),
            ])
        eq(UnsubscribeMethod.of(group), .oneClick)
    }
}

Harness.suite("MCP snapshot") {
    Harness.test("rebuilds the app's collections from the store alone") {
        do {
            let store = try MessageStore.inMemory()
            try store.upsert([
                mcpMessage(1, from: "Working <a@working.com>"),
                mcpMessage(2, from: "Hidden <b@hidden.com>"),
                mcpMessage(3, from: "Gone <c@gone.com>", daysAgo: 10),
                mcpMessage(4, from: "Back <d@back.com>", daysAgo: 0),
            ])
            try store.ignore(GroupID(kind: .domain, key: "hidden.com"))
            try store.recordUnsubscribe(
                GroupID(kind: .domain, key: "gone.com"), senderName: "Gone",
                senderEmail: "c@gone.com", senderDomain: "gone.com", url: nil,
                outcome: .requested, attemptedAt: Date(timeIntervalSince1970: 1_700_000_000))
            // Recorded *before* their most recent message: that is what reappeared means.
            try store.recordUnsubscribe(
                GroupID(kind: .domain, key: "back.com"), senderName: "Back",
                senderEmail: "d@back.com", senderDomain: "back.com", url: nil,
                outcome: .requested,
                attemptedAt: Date(timeIntervalSince1970: 1_700_000_000 - 86400))

            let snapshot = try mcpSnapshot(store)
            eq(snapshot.groups(in: .allSenders).count, 1, "all senders")
            eq(snapshot.groups(in: .ignored).count, 1, "ignored")
            eq(snapshot.groups(in: .unsubscribed).count, 1, "unsubscribed")
            eq(snapshot.groups(in: .reappeared).count, 1, "reappeared")
            eq(snapshot.messagesSinceUnsubscribe(snapshot.groups(in: .reappeared)[0]), 1)
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("a decision on any address in a merged group rolls up to the row") {
        // The whole reason TASK-43 keys decisions by address: regrouping must not
        // throw the agent's judgement away.
        do {
            let store = try MessageStore.inMemory()
            try store.upsert([
                mcpMessage(1, from: "Acme <news@acme.com>"),
                mcpMessage(2, from: "Acme <deals@mail.acme.com>"),
            ])
            try store.recordDecision(
                address: "deals@mail.acme.com", classification: "keep",
                reason: "order receipts", context: "shopping")
            let snapshot = try mcpSnapshot(store)
            eq(snapshot.groups.count, 1, "one merged row")
            eq(snapshot.decision(for: snapshot.groups[0])?.classification, "keep")
        } catch { expect(false, "threw: \(error)") }
    }
}

Harness.suite("MCP read routes") {
    /// A mailbox big enough that paging is not theoretical.
    func bigStore(senders: Int) throws -> MessageStore {
        let store = try MessageStore.inMemory()
        var messages: [EmailMessage] = []
        var uid: UInt32 = 1
        for i in 0 ..< senders {
            for _ in 0 ..< (i % 3 + 1) {
                messages.append(
                    mcpMessage(uid, from: "Sender \(i) <news@brand\(i).com>", daysAgo: Double(i)))
                uid += 1
            }
        }
        try store.upsert(messages)
        return store
    }

    Harness.test("list_senders defaults to a limit that won't swamp an agent") {
        do {
            let snapshot = try mcpSnapshot(try bigStore(senders: 400))
            let page = mcpJSON(mcpCall("/mcp/senders/list", snapshot))
            eq(MCPRoutes.defaultLimit, 50, "the documented default")
            eq(page["limit"] as? Int, 50)
            eq(page["total"] as? Int, 400)
            eq(mcpRows(mcpCall("/mcp/senders/list", snapshot)).count, 50)
            eq(page["has_more"] as? Bool, true)
            eq(page["next_offset"] as? Int, 50)
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("paging walks the whole list exactly once") {
        do {
            let snapshot = try mcpSnapshot(try bigStore(senders: 120))
            var seen: Set<String> = []
            var offset = 0
            var pages = 0
            while true {
                let page = mcpCall(
                    "/mcp/senders/list", snapshot, ["limit": 25, "offset": offset])
                for row in mcpRows(page) { seen.insert(row["id"] as? String ?? "") }
                pages += 1
                guard let next = mcpJSON(page)["next_offset"] as? Int, pages < 20 else { break }
                offset = next
            }
            eq(seen.count, 120, "every sender seen, none twice")
            eq(pages, 5)
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("a limit above the cap is reduced and says so, rather than refused") {
        do {
            let snapshot = try mcpSnapshot(try bigStore(senders: 400))
            let page = mcpJSON(mcpCall("/mcp/senders/list", snapshot, ["limit": 5000]))
            eq(page["limit"] as? Int, MCPRoutes.maxLimit)
            expect(
                (page["note"] as? String ?? "").contains("reduced from 5000"),
                "the reduction is reported, not silent")
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("every response names the account it is about") {
        do {
            let store = try MessageStore.inMemory()
            try store.upsert([mcpMessage(1, from: "A <a@x.com>")])
            try store.recordDecision(
                address: "a@x.com", classification: "drop", reason: "why", context: "cohort")
            let snapshot = try mcpSnapshot(store, account: "someone@example.org")
            for path in MCPRoutes.paths.sorted() {
                let arguments: [String: Any] = [
                    "sender_id": "domain:x.com", "context": "cohort", "query": "a",
                ]
                let response = mcpCall(path, snapshot, arguments)
                eq(response.statusCode, 200, path)
                eq(mcpJSON(response)["account"] as? String, "someone@example.org", path)
            }
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("every response repeats that message bodies do not exist here") {
        // An agent may only ever see one response, without the tool description
        // that came with it — so the ceiling on what it can know has to travel
        // on the data.
        do {
            let store = try MessageStore.inMemory()
            try store.upsert([mcpMessage(1, from: "A <a@x.com>")])
            let snapshot = try mcpSnapshot(store)
            for path in MCPRoutes.paths.sorted() where path != "/mcp/decisions/by-context" {
                let response = mcpCall(
                    path, snapshot, ["sender_id": "domain:x.com", "query": "a"])
                let note = mcpJSON(response)["note"] as? String ?? ""
                expect(note.lowercased().contains("bodies"), "\(path) note: \(note)")
            }
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("senders are partitioned by unsubscribe method without attempting anything") {
        do {
            let store = try MessageStore.inMemory()
            try store.upsert([
                mcpMessage(1, from: "One <a@one.com>", oneClick: true),
                mcpMessage(2, from: "Web <b@web.com>"),
                mcpMessage(3, from: "Mail <c@mail.com>", unsub: "<mailto:stop@mail.com?subject=x>"),
                mcpMessage(4, from: "Nothing <d@nothing.com>", unsub: nil),
            ])
            let snapshot = try mcpSnapshot(store)
            for (method, key) in [
                ("one_click", "domain:one.com"), ("web", "domain:web.com"),
                ("mailto", "domain:mail.com"), ("none", "domain:nothing.com"),
            ] {
                let rows = mcpRows(
                    mcpCall("/mcp/senders/list", snapshot, ["unsubscribe_method": method]))
                eq(rows.count, 1, method)
                eq(rows.first?["id"] as? String, key, method)
            }
            let browser = mcpRows(mcpCall("/mcp/senders/list", snapshot, ["needs_browser": true]))
            eq(browser.count, 1, "only the sender with no target needs a human")
            eq(browser.first?["id"] as? String, "domain:nothing.com")
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("a sender that ignored an unsubscribe also needs the browser") {
        do {
            let store = try MessageStore.inMemory()
            try store.upsert([mcpMessage(1, from: "Back <d@back.com>", oneClick: true)])
            try store.recordUnsubscribe(
                GroupID(kind: .domain, key: "back.com"), senderName: "Back",
                senderEmail: "d@back.com", senderDomain: "back.com", url: nil, outcome: .requested,
                attemptedAt: Date(timeIntervalSince1970: 1_700_000_000 - 86400))
            let snapshot = try mcpSnapshot(store)
            let rows = mcpRows(mcpCall("/mcp/senders/reappeared", snapshot))
            eq(rows.count, 1)
            eq(rows.first?["needs_browser"] as? Bool, true, "retrying the same POST is what failed")
            eq(rows.first?["unsubscribe_method"] as? String, "one_click", "the method is unchanged")
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("filters narrow on count, read rate, recency and list status") {
        do {
            let store = try MessageStore.inMemory()
            try store.upsert([
                mcpMessage(1, from: "Loud <a@loud.com>", daysAgo: 1, unread: true),
                mcpMessage(2, from: "Loud <a@loud.com>", daysAgo: 2, unread: true),
                mcpMessage(3, from: "Loud <a@loud.com>", daysAgo: 3, unread: true),
                mcpMessage(4, from: "Read <b@read.com>", daysAgo: 400, unread: false),
                mcpMessage(5, from: "List <c@list.com>", daysAgo: 1, listID: "<x.list.com>"),
            ])
            let snapshot = try mcpSnapshot(store)
            func ids(_ arguments: [String: Any]) -> [String] {
                mcpRows(mcpCall("/mcp/senders/list", snapshot, arguments))
                    .compactMap { $0["id"] as? String }
            }
            eq(ids(["min_messages": 3]), ["domain:loud.com"])
            eq(ids(["max_messages": 1]).count, 2)
            eq(ids(["min_unread_percent": 100]), ["domain:loud.com"])
            eq(ids(["max_unread_percent": 0]).count, 2)
            eq(ids(["is_mailing_list": true]), ["domain:list.com"])
            eq(ids(["received_before": "2023-01-01"]), ["domain:read.com"])
            eq(ids(["received_after": "2023-01-01"]).count, 2)
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("classification and context filter on what a previous session decided") {
        do {
            let store = try MessageStore.inMemory()
            try store.upsert([
                mcpMessage(1, from: "A <a@a.com>"),
                mcpMessage(2, from: "B <b@b.com>"),
                mcpMessage(3, from: "C <c@c.com>"),
            ])
            try store.recordDecision(
                address: "a@a.com", classification: "drop", reason: "over", context: "job-search")
            try store.recordDecision(
                address: "b@b.com", classification: "keep", reason: "bank", context: nil)
            let snapshot = try mcpSnapshot(store)
            func ids(_ arguments: [String: Any]) -> [String] {
                mcpRows(mcpCall("/mcp/senders/list", snapshot, arguments))
                    .compactMap { $0["id"] as? String }
            }
            eq(ids(["classification": "drop"]), ["domain:a.com"])
            eq(ids(["context": "job-search"]), ["domain:a.com"])
            eq(ids(["classification": "keep"]), ["domain:b.com"])
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("an unknown collection is refused with the names that would have worked") {
        do {
            let snapshot = try mcpSnapshot(try bigStore(senders: 2))
            let response = mcpCall("/mcp/senders/list", snapshot, ["collection": "inbox"])
            eq(response.statusCode, 400)
            let error = mcpJSON(response)["error"] as? String ?? ""
            expect(error.contains("allSenders"), "names the valid collections: \(error)")
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("the collection an agent would guess from the wire format is accepted") {
        do {
            let store = try MessageStore.inMemory()
            try store.upsert([mcpMessage(1, from: "A <a@x.com>")])
            let snapshot = try mcpSnapshot(store)
            eq(mcpCall("/mcp/senders/list", snapshot, ["collection": "all_senders"]).statusCode, 200)
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("get_sender reports the parsed targets and what was already tried") {
        do {
            let store = try MessageStore.inMemory()
            try store.upsert([
                mcpMessage(
                    1, from: "Acme <news@acme.com>", subject: "Sale",
                    unsub: "<https://acme.com/u?t=1>, <mailto:stop@acme.com?subject=tok>",
                    oneClick: true)
            ])
            try store.recordUnsubscribe(
                GroupID(kind: .domain, key: "acme.com"), senderName: "Acme",
                senderEmail: "news@acme.com", senderDomain: "acme.com",
                url: "https://acme.com/u?t=1", outcome: .requested,
                attemptedAt: Date(timeIntervalSince1970: 1_800_000_000))
            let snapshot = try mcpSnapshot(store)
            let detail = mcpJSON(
                mcpCall("/mcp/senders/get", snapshot, ["sender_id": "domain:acme.com"]))
            eq(detail["supports_one_click"] as? Bool, true)
            eq((detail["web_targets"] as? [String])?.first, "https://acme.com/u?t=1")
            let mailto = (detail["mailto_targets"] as? [[String: Any]])?.first
            eq(mailto?["address"] as? String, "stop@acme.com")
            eq(mailto?["identifies_recipient"] as? Bool, true)
            let record = detail["unsubscribe_record"] as? [String: Any]
            eq(record?["outcome"] as? String, "requested")
            eq(record?["reappeared"] as? Bool, false)
            eq((detail["recent_subjects"] as? [[String: Any]])?.first?["subject"] as? String, "Sale")
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("get_sender and list_messages refuse an id that isn't there") {
        do {
            let snapshot = try mcpSnapshot(try bigStore(senders: 1))
            for path in ["/mcp/senders/get", "/mcp/senders/messages"] {
                eq(mcpCall(path, snapshot, ["sender_id": "domain:nope.com"]).statusCode, 404, path)
                eq(mcpCall(path, snapshot).statusCode, 400, "\(path) without an id")
            }
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("list_messages pages subjects newest first") {
        do {
            let store = try MessageStore.inMemory()
            try store.upsert(
                (1 ... 30).map {
                    mcpMessage(
                        UInt32($0), from: "A <a@x.com>", subject: "S\($0)", daysAgo: Double(30 - $0))
                })
            let snapshot = try mcpSnapshot(store)
            let first = mcpCall(
                "/mcp/senders/messages", snapshot, ["sender_id": "domain:x.com", "limit": 10])
            eq(mcpJSON(first)["total"] as? Int, 30)
            eq(mcpRows(first, "messages").count, 10)
            eq(mcpRows(first, "messages").first?["subject"] as? String, "S30", "newest first")
            eq(mcpJSON(first)["next_offset"] as? Int, 10)
            let last = mcpCall(
                "/mcp/senders/messages", snapshot,
                ["sender_id": "domain:x.com", "limit": 10, "offset": 20])
            eq(mcpJSON(last)["has_more"] as? Bool, false)
            eq(mcpRows(last, "messages").count, 10)
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("search reaches senders already unsubscribed from or ignored") {
        // "Did I already deal with these people" is what a search is asked, and
        // answering it from the working list alone says no when the answer is yes.
        do {
            let store = try MessageStore.inMemory()
            try store.upsert([
                mcpMessage(1, from: "Acme Deals <news@acme.com>", subject: "Spring sale"),
                mcpMessage(2, from: "Other <x@other.com>", subject: "Acme mentioned here"),
            ])
            try store.ignore(GroupID(kind: .domain, key: "acme.com"))
            let snapshot = try mcpSnapshot(store)
            eq(mcpRows(mcpCall("/mcp/senders/search", snapshot, ["query": "acme"])).count, 2)
            eq(mcpRows(mcpCall("/mcp/senders/search", snapshot, ["query": "spring"])).count, 1)
            eq(mcpRows(mcpCall("/mcp/senders/search", snapshot, ["query": "other.com"])).count, 1)
            eq(mcpCall("/mcp/senders/search", snapshot).statusCode, 400, "an empty query is refused")
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("unsubscribe_history reports reappearance alongside the outcome") {
        do {
            let store = try MessageStore.inMemory()
            try store.upsert([
                mcpMessage(1, from: "Back <a@back.com>", daysAgo: 0),
                mcpMessage(2, from: "Quiet <b@quiet.com>", daysAgo: 30),
            ])
            try store.recordUnsubscribe(
                GroupID(kind: .domain, key: "back.com"), senderName: "Back",
                senderEmail: "a@back.com", senderDomain: "back.com", url: nil, outcome: .requested,
                attemptedAt: Date(timeIntervalSince1970: 1_700_000_000 - 86400))
            try store.recordUnsubscribe(
                GroupID(kind: .domain, key: "quiet.com"), senderName: "Quiet",
                senderEmail: "b@quiet.com", senderDomain: "quiet.com", url: nil,
                outcome: .confirmed, attemptedAt: Date(timeIntervalSince1970: 1_700_000_000))
            let snapshot = try mcpSnapshot(store)
            let all = mcpRows(mcpCall("/mcp/unsubscribe/history", snapshot), "records")
            eq(all.count, 2)
            let back = all.first { $0["sender_id"] as? String == "domain:back.com" }
            eq(back?["reappeared"] as? Bool, true)
            let quiet = all.first { $0["sender_id"] as? String == "domain:quiet.com" }
            eq(quiet?["reappeared"] as? Bool, false)
            eq(
                mcpRows(
                    mcpCall("/mcp/unsubscribe/history", snapshot, ["outcome": "confirmed"]),
                    "records"
                ).count, 1)
            eq(
                mcpCall("/mcp/unsubscribe/history", snapshot, ["outcome": "maybe"]).statusCode, 400)
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("mailbox_summary orients without returning rows") {
        do {
            let store = try MessageStore.inMemory()
            try store.upsert([
                mcpMessage(1, from: "One <a@one.com>", oneClick: true, listID: "<l.one.com>"),
                mcpMessage(2, from: "Nothing <d@nothing.com>", unsub: nil),
                mcpMessage(3, from: "Hidden <e@hidden.com>"),
            ])
            try store.ignore(GroupID(kind: .domain, key: "hidden.com"))
            try store.recordDecision(
                address: "a@one.com", classification: "keep", reason: "r", context: "cohort")
            let summary = mcpJSON(mcpCall("/mcp/mailbox/summary", try mcpSnapshot(store)))
            eq(summary["senders"] as? Int, 3)
            eq(summary["messages"] as? Int, 3)
            eq(summary["need_browser"] as? Int, 1)
            eq(summary["mailing_lists"] as? Int, 1)
            eq(summary["decided"] as? Int, 1)
            eq(summary["contexts"] as? [String], ["cohort"])
            eq((summary["by_collection"] as? [String: Int])?["ignored"], 1)
            eq((summary["by_collection"] as? [String: Int])?["allSenders"], 2)
            eq((summary["by_unsubscribe_method"] as? [String: Int])?["one_click"], 1)
            eq((summary["by_unsubscribe_method"] as? [String: Int])?["none"], 1)
            expect(summary["senders_list"] == nil, "no rows are returned")
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("sync_status reports the token, and says so when there isn't one") {
        do {
            let store = try MessageStore.inMemory()
            try store.upsert([mcpMessage(1, from: "A <a@x.com>")])
            eq(
                mcpJSON(mcpCall("/mcp/sync/status", try mcpSnapshot(store)))["has_synced"] as? Bool,
                false)
            try store.setSyncToken(
                SyncToken(
                    uidValidity: 7, highestUID: 99,
                    lastSyncedAt: Date(timeIntervalSince1970: 1_700_000_000)))
            let status = mcpJSON(mcpCall("/mcp/sync/status", try mcpSnapshot(store)))
            eq(status["has_synced"] as? Bool, true)
            eq(status["uid_validity"] as? Int, 7)
            eq(status["highest_uid"] as? Int, 99)
            expect(
                (status["last_synced_at"] as? String ?? "").hasPrefix("2023-11-"),
                "an ISO date, not a float: \(status["last_synced_at"] ?? "nil")")
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("list_by_context returns the cohort, including decisions whose mail is gone") {
        do {
            let store = try MessageStore.inMemory()
            try store.upsert([mcpMessage(1, from: "Still <a@still.com>")])
            try store.recordDecision(
                address: "a@still.com", classification: "drop", reason: "over",
                context: "job-search-2026")
            try store.recordDecision(
                address: "deleted@gone.com", classification: "drop", reason: "over",
                context: "job-search-2026")
            try store.recordDecision(
                address: "other@x.com", classification: "keep", reason: "bank", context: "money")
            let snapshot = try mcpSnapshot(store)
            let cohort = mcpJSON(
                mcpCall("/mcp/decisions/by-context", snapshot, ["context": "job-search-2026"]))
            eq(cohort["total"] as? Int, 2)
            eq(cohort["available_contexts"] as? [String], ["job-search-2026", "money"])
            let rows = cohort["decisions"] as? [[String: Any]] ?? []
            let orphan = rows.first {
                ($0["decision"] as? [String: Any])?["address"] as? String == "deleted@gone.com"
            }
            expect(orphan != nil, "the decision outlives the mail")
            expect(
                orphan?["sender"] is NSNull || orphan?["sender"] == nil,
                "and reports no sender rather than inventing one")
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("list_by_context without a label lists the labels that exist") {
        do {
            let store = try MessageStore.inMemory()
            try store.recordDecision(
                address: "a@x.com", classification: "drop", reason: "r", context: "job-search-2026")
            let response = mcpCall("/mcp/decisions/by-context", try mcpSnapshot(store))
            eq(response.statusCode, 400)
            expect(
                (mcpJSON(response)["error"] as? String ?? "").contains("job-search-2026"),
                "an agent shouldn't have to guess the label")
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("the whole surface is read-only — driving every route changes nothing") {
        // The safety argument for TASK-46 rests on this: the token does not bound
        // what an agent can do, so the read surface has to be incapable of acting.
        do {
            let store = try MessageStore.inMemory()
            try store.upsert([mcpMessage(1, from: "A <a@x.com>")])
            try store.ignore(GroupID(kind: .domain, key: "y.com"))
            try store.recordUnsubscribe(
                GroupID(kind: .domain, key: "z.com"), senderName: "Z", senderEmail: "z@z.com",
                senderDomain: "z.com", url: nil, outcome: .requested)
            try store.recordDecision(
                address: "a@x.com", classification: "keep", reason: "r", context: "c")
            let before = (
                try store.count(), try store.ignoredGroupKeys().count,
                try store.unsubscribeHistory().count, try store.allDecisions().count
            )
            let snapshot = try mcpSnapshot(store)
            for path in MCPRoutes.paths.sorted() {
                _ = mcpCall(
                    path, snapshot, ["sender_id": "domain:x.com", "context": "c", "query": "a"])
            }
            let after = (
                try store.count(), try store.ignoredGroupKeys().count,
                try store.unsubscribeHistory().count, try store.allDecisions().count
            )
            expect(before == after, "the store is untouched: \(before) -> \(after)")
        } catch { expect(false, "threw: \(error)") }
    }
}

Harness.suite("MCP server dispatch") {
    func serve(
        path: String, token: String = "s3cret", presented: String = "s3cret", isDemo: Bool = false,
        context: MCPContext?
    ) -> HTTPResponse {
        runAsync {
            let server = NevermoreServer(appVersion: "9.9.9", isDemo: isDemo, mcpToken: token)
            await server.setMCPContext(context)
            return await server.routeRequest(
                HTTPRequest(
                    method: "POST", path: path,
                    headers: ["authorization": "Bearer \(presented)"],
                    body: Data("{}".utf8)))
        }
    }

    Harness.test("a real route serves the open account") {
        do {
            let store = try MessageStore.inMemory()
            try store.upsert([mcpMessage(1, from: "A <a@x.com>")])
            let response = serve(
                path: "/mcp/senders/list",
                context: MCPContext(account: "me@example.com", store: store))
            eq(response.statusCode, 200)
            eq(mcpJSON(response)["account"] as? String, "me@example.com")
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("with no mailbox open the answer is 503, never an empty mailbox") {
        // "This person has no senders" and "no account is open" are answers an
        // agent would act on very differently.
        let response = serve(path: "/mcp/senders/list", context: nil)
        eq(response.statusCode, 503)
        expect(
            (mcpJSON(response)["error"] as? String ?? "").contains("No mailbox is open"),
            "says which it is")
    }

    Harness.test("demo mode refuses every tool") {
        do {
            let store = try MessageStore.inMemory()
            try store.upsert([mcpMessage(1, from: "A <a@x.com>")])
            let context = MCPContext(account: "me@example.com", store: store)
            for path in MCPRoutes.paths.sorted() {
                let response = serve(path: path, isDemo: true, context: context)
                eq(response.statusCode, 403, path)
                expect(
                    (mcpJSON(response)["error"] as? String ?? "").contains("demo mode"), path)
            }
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("the four refusals stay distinguishable, demo mode included") {
        // A bridge reads its situation off these codes: 401 fix your token, 404
        // that tool doesn't exist, 403 leave demo mode, 503 open an account.
        do {
            let store = try MessageStore.inMemory()
            let context = MCPContext(account: "me@example.com", store: store)
            eq(
                serve(path: "/mcp/senders/list", presented: "wrong", isDemo: true, context: context)
                    .statusCode, 401, "credential first, even in demo mode")
            eq(
                serve(path: "/mcp/not-a-tool", isDemo: true, context: context).statusCode, 404,
                "an unknown route is still about the route in demo mode")
            eq(
                serve(path: "/mcp/senders/list", isDemo: true, context: nil).statusCode, 403,
                "demo mode is reported before the absent mailbox")
        } catch { expect(false, "threw: \(error)") }
    }

    Harness.test("the local server hands the context on to a server it starts later") {
        // The account and the server come up in either order, so whichever is
        // second has to find the other already recorded.
        do {
            let store = try MessageStore.inMemory()
            try store.upsert([mcpMessage(1, from: "A <a@x.com>")])
            let dir = URL.temporaryDirectory.appending(path: "nevermore-mcp-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let tokenURL = dir.appending(path: ".nevermore-mcp-token")

            let controller = LocalServerController(tokenURL: tokenURL, appVersion: "9.9.9")
            runAsync {
                await controller.setMCPContext(
                    MCPContext(account: "me@example.com", store: store))
            }
            let status = runAsync { await controller.start(isDemo: false) }
            defer { runAsync { await controller.stop() } }
            guard case let .running(port) = status, let token = MCPTokenManager.read(at: tokenURL)
            else {
                expect(false, "expected a running server with a token, got \(status)")
                return
            }
            let result: (status: Int, body: String)? = runAsync {
                guard let url = URL(string: "http://127.0.0.1:\(port)/mcp/mailbox/summary")
                else { return nil }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.httpBody = Data("{}".utf8)
                guard let (data, response) = try? await URLSession.shared.data(for: request),
                    let http = response as? HTTPURLResponse
                else { return nil }
                return (http.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
            eq(result?.status, 200, "the tool answers over the socket, not just in-process")
            expect(result?.body.contains("me@example.com") ?? false, "and names the account")
        } catch { expect(false, "threw: \(error)") }
    }
}

Harness.suite("MCP tool catalog") {
    Harness.test("the nine read tools are present, and nothing that writes") {
        eq(MCPToolCatalog.tools.count, 9)
        let names = Set(MCPToolCatalog.tools.map(\.name))
        eq(
            names,
            [
                "list_senders", "get_sender", "list_messages", "search_senders",
                "unsubscribe_history", "list_reappeared", "mailbox_summary", "sync_status",
                "list_by_context",
            ])
        // TASK-41: the agent proposes, the human actuates. A verb here would be a
        // reversal of that, not a feature.
        for forbidden in ["unsubscribe_sender", "ignore", "trash", "delete", "propose", "act"] {
            expect(!names.contains(forbidden), "no write verb named \(forbidden)")
        }
    }

    Harness.test("every description states that message bodies are unavailable") {
        for tool in MCPToolCatalog.tools {
            let description = MCPToolCatalog.fullDescription(of: tool).lowercased()
            expect(description.contains("bodies are unavailable"), tool.name)
            expect(description.contains("headers only"), "\(tool.name) says why")
        }
    }

    Harness.test("every description states the account rule and that the app must be running") {
        for tool in MCPToolCatalog.tools {
            let description = MCPToolCatalog.fullDescription(of: tool)
            expect(description.contains("account currently open"), tool.name)
            expect(description.contains("app must be running"), tool.name)
            expect(description.contains("demo mode"), tool.name)
        }
    }

    Harness.test("every schema is valid JSON describing an object of arguments") {
        for tool in MCPToolCatalog.tools {
            guard let data = tool.schemaJSON.data(using: .utf8),
                let schema = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                expect(false, "\(tool.name): schema is not a JSON object")
                continue
            }
            eq(schema["type"] as? String, "object", tool.name)
            expect(schema["properties"] is [String: Any], "\(tool.name) declares properties")
        }
    }

    Harness.test("every tool points at a route the server actually serves") {
        for tool in MCPToolCatalog.tools {
            expect(MCPRoutes.paths.contains(tool.path), "\(tool.name) -> \(tool.path)")
        }
        // And nothing is served that no tool can reach — an unreachable route is
        // either a missing tool or dead code, and both want finding.
        let reached = Set(MCPToolCatalog.tools.map(\.path))
        eq(reached, MCPRoutes.paths)
    }

    Harness.test("the paging contract in the schema matches the one the server enforces") {
        guard let list = MCPToolCatalog.tool(named: "list_senders") else {
            expect(false, "list_senders is missing")
            return
        }
        expect(list.schemaJSON.contains("\"default\": \(MCPRoutes.defaultLimit)"), "default limit")
        expect(list.schemaJSON.contains("\"maximum\": \(MCPRoutes.maxLimit)"), "maximum limit")
        expect(
            MCPToolCatalog.fullDescription(of: list).contains("has_more"),
            "tells the agent how to know it saw everything")
    }
}

Harness.suite("MCP bridge protocol") {
    Harness.test("recognises the three methods a client actually sends") {
        eq(MCPBridge.parse(#"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#), .initialize(id: .number(1)))
        eq(MCPBridge.parse(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#), .toolsList(id: .number(2)))
        eq(
            MCPBridge.parse(
                #"{"jsonrpc":"2.0","id":"a","method":"tools/call","params":{"name":"sync_status"}}"#),
            .toolsCall(id: .string("a"), name: "sync_status", argumentsJSON: Data("{}".utf8)))
    }

    Harness.test("a notification is answered with silence, as the spec requires") {
        eq(MCPBridge.parse(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#),
           .notification(method: "notifications/initialized"))
    }

    Harness.test("garbage on stdin is a parse error rather than a crash") {
        eq(MCPBridge.parse("not json"), .parseError)
        eq(MCPBridge.parse("{}"), .parseError, "no method")
        eq(MCPBridge.parse(""), .parseError)
    }

    Harness.test("the request id comes back exactly as it was sent") {
        for line in [
            #"{"id":7,"method":"initialize"}"#, #"{"id":"seven","method":"initialize"}"#,
        ] {
            guard case let .initialize(id) = MCPBridge.parse(line) else {
                expect(false, "did not parse: \(line)")
                continue
            }
            let response =
                (try? JSONSerialization.jsonObject(
                    with: Data(MCPBridge.initializeResponse(id: id).utf8))) as? [String: Any]
            expect(response?["id"] != nil, "the id is echoed: \(line)")
        }
    }

    Harness.test("tool arguments are forwarded verbatim, not re-interpreted") {
        // The bridge holds no schema of its own; the server is the only place
        // that decides what an argument means.
        let line =
            #"{"id":1,"method":"tools/call","params":{"name":"list_senders","arguments":{"limit":5,"collection":"ignored"}}}"#
        guard case let .toolsCall(_, name, argumentsJSON) = MCPBridge.parse(line) else {
            expect(false, "did not parse a tools/call")
            return
        }
        eq(name, "list_senders")
        let arguments =
            (try? JSONSerialization.jsonObject(with: argumentsJSON)) as? [String: Any] ?? [:]
        eq(arguments["limit"] as? Int, 5)
        eq(arguments["collection"] as? String, "ignored")
    }

    Harness.test("tools/list ships every catalogued tool with a parsed schema") {
        let response =
            (try? JSONSerialization.jsonObject(
                with: Data(MCPBridge.toolsListResponse(id: .number(1)).utf8))) as? [String: Any]
        let result = response?["result"] as? [String: Any]
        let tools = result?["tools"] as? [[String: Any]] ?? []
        eq(tools.count, MCPToolCatalog.tools.count)
        for tool in tools {
            expect(tool["inputSchema"] is [String: Any], "\(tool["name"] ?? "?") carries an object schema")
            expect(
                (tool["description"] as? String ?? "").contains("bodies are unavailable"),
                "\(tool["name"] ?? "?") keeps the caveat on the wire")
        }
    }

    Harness.test("a failed tool call is a result carrying isError, not a transport error") {
        // A JSON-RPC error would tell the client the bridge broke; the call
        // reached the server and came back with a refusal.
        let response =
            (try? JSONSerialization.jsonObject(
                with: Data(MCPBridge.toolErrorResponse(id: .number(1), message: "nope").utf8)))
            as? [String: Any]
        expect(response?["error"] == nil, "not a protocol-level error")
        eq((response?["result"] as? [String: Any])?["isError"] as? Bool, true)
    }

    Harness.test("a 401 refreshes the token only; a dead connection re-probes the port") {
        // The bridge outlives the app: a relaunch rotates the token and may move
        // the port, and without this every later call fails until the MCP client
        // itself is restarted.
        expect(MCPBridge.shouldRefresh(status: 401, hasBody: true), "401 = rotated token")
        expect(!MCPBridge.refreshNeedsPortProbe(status: 401), "401 means we reached a server")
        expect(MCPBridge.shouldRefresh(status: 500, hasBody: false), "no body = never got there")
        expect(MCPBridge.refreshNeedsPortProbe(status: 500), "so the port may have moved")
    }

    Harness.test("a real error from the app is not retried into a second failure") {
        expect(!MCPBridge.shouldRefresh(status: 500, hasBody: true), "the app answered")
        expect(!MCPBridge.shouldRefresh(status: 503, hasBody: true), "no mailbox open")
        expect(!MCPBridge.shouldRefresh(status: 403, hasBody: true), "demo mode")
        expect(!MCPBridge.shouldRefresh(status: 404, hasBody: true), "unknown route")
        expect(!MCPBridge.shouldRefresh(status: 200, hasBody: true), "success")
    }
}

Harness.suite("Store build excludes the bridge") {
    /// The repo root, from this file's own path.
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // NevermoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // NevermoreKit
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repo root

    Harness.test("Project.swift names neither the bridge target nor its product") {
        // The Mac App Store target depends on the NevermoreKit *library* product,
        // so the bridge cannot ride along — but "cannot" is only true while
        // nothing here mentions it, which is what this pins.
        guard let manifest = try? String(contentsOf: root.appending(path: "Project.swift"),
                                         encoding: .utf8) else {
            expect(false, "could not read Project.swift at \(root.path)")
            return
        }
        expect(!manifest.contains("NevermoreMCP"), "no bridge target")
        expect(!manifest.contains("nevermore-mcp"), "no bridge product")
        expect(
            manifest.contains("Sources/NevermoreApp/**"),
            "the store target still builds only the app's sources")
    }

    Harness.test("the package declares the bridge as its own executable product") {
        guard let manifest = try? String(
            contentsOf: root.appending(path: "Packages/NevermoreKit/Package.swift"),
            encoding: .utf8) else {
            expect(false, "could not read Package.swift")
            return
        }
        expect(
            manifest.contains(#".executable(name: "nevermore-mcp", targets: ["NevermoreMCP"])"#),
            "a separate executable product, not a dependency of the app")
    }
}

exit(Harness.finish())
