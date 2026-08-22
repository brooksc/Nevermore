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

Harness.suite("SenderCollection membership") {
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
        eq(SenderCollection.allCases.filter { $0.contains(s) }, [.allSenders])
    }

    Harness.test("unsubscribing takes a sender out of the working list") {
        let s = state(unsubscribed: true)
        expect(!SenderCollection.allSenders.contains(s), "gone from All Senders")
        expect(SenderCollection.unsubscribed.contains(s), "listed under Unsubscribed")
        expect(!SenderCollection.reappeared.contains(s), "they haven't mailed again")
    }

    Harness.test("mailing again moves a sender from Unsubscribed to Reappeared") {
        let s = state(unsubscribed: true, reappeared: true)
        expect(SenderCollection.reappeared.contains(s), "Reappeared")
        expect(!SenderCollection.unsubscribed.contains(s), "and only there — not both")
    }

    Harness.test("ignoring hides a sender from All Senders and Reappeared") {
        expect(!SenderCollection.allSenders.contains(state(ignored: true)))
        expect(!SenderCollection.reappeared.contains(state(ignored: true, unsubscribed: true, reappeared: true)))
        expect(SenderCollection.ignored.contains(state(ignored: true)))
    }

    // Inherited behaviour, pinned rather than endorsed: Unsubscribed doesn't
    // exclude ignored senders, so one that is both is listed twice. Changing it
    // is a product decision, not part of unifying the selection model.
    Harness.test("an ignored sender with a record is listed in both archives") {
        let s = state(ignored: true, unsubscribed: true)
        eq(SenderCollection.allCases.filter { $0.contains(s) }, [.unsubscribed, .ignored])
    }

    Harness.test("losing their messages doesn't remove a record from Unsubscribed") {
        // The point of the durable log: the record outlives the mail.
        expect(SenderCollection.unsubscribed.contains(state(unsubscribed: true, messages: false)))
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
    func context(_ collection: SenderCollection, count: Int, withMessages: Int? = nil)
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
        for collection in SenderCollection.allCases {
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
    Harness.test("the surface is nine read tools and thirteen narrow writes, and nothing else") {
        let names = Set(MCPToolCatalog.tools.map(\.name))
        eq(MCPToolCatalog.tools.count, 22, "and no tool is defined twice")
        eq(
            names,
            [
                // Reads (TASK-44).
                "list_senders", "get_sender", "list_messages", "search_senders",
                "unsubscribe_history", "list_reappeared", "mailbox_summary", "sync_status",
                "list_by_context",
                // Writes (TASK-46).
                "propose_selection", "get_proposal_status", "unsubscribe", "ignore", "unignore",
                "set_classification", "trash_sender_messages", "start_sync", "set_grouping",
                "forget_unsubscribe_record", "get_policy",
                // The browser queue (TASK-47): fill it and read it. There is no
                // third verb, and the absence is the feature.
                "queue_for_browser", "get_browser_queue",
            ])
        // TASK-39/TASK-41: the agent proposes, the human actuates. `unsubscribe`
        // is one sender through the app's own confirmation; a verb that took a
        // set would be the reversal of the product decision, not a convenience.
        for forbidden in [
            "unsubscribe_all", "unsubscribe_senders", "unsubscribe_selection", "batch_unsubscribe",
            "unsubscribe_batch", "act_on_proposal", "accept_proposal", "confirm_selection",
        ] {
            expect(!names.contains(forbidden), "no bulk-unsubscribe verb named \(forbidden)")
        }
    }

    Harness.test("no tool takes a review token, because an agent can never hold one") {
        // The gate is that the batch path needs a human confirmation the MCP
        // surface has no way to produce. A token argument here — however
        // carefully validated — would be the surface offering to carry one.
        for tool in MCPToolCatalog.tools {
            let data = tool.schemaJSON.data(using: .utf8) ?? Data()
            let schema = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let arguments = (schema["properties"] as? [String: Any])?.keys.map { $0.lowercased() }
                ?? []
            for argument in arguments {
                // A token to present, a confirmation to assert, a policy to
                // override: three spellings of the same missing argument.
                for forbidden in ["token", "confirm", "force", "override", "skip", "unattended"] {
                    expect(
                        !argument.contains(forbidden),
                        "\(tool.name) takes an argument named '\(argument)'")
                }
            }
        }
    }

    Harness.test("the policy tells an agent there is no batch unsubscribe") {
        let policy = MCPWriteRoutes.policy
        expect(!policy.batchUnsubscribeAvailable, "and it is not a capability")
        expect(policy.noBatchUnsubscribe.contains("no bulk unsubscribe"))
        eq(policy.proposalCap, SenderProposal.maxItems)
        // The two verbs that reach the mailbox or a third party are never
        // unattended, whatever else moves between the lists.
        for confirmed in ["unsubscribe", "trash_sender_messages"] {
            expect(policy.requiresHumanConfirmation.contains(confirmed), confirmed)
            expect(!policy.unattended.contains(confirmed), "\(confirmed) is not unattended")
        }
        // And every tool the catalog offers is accounted for in one list or the
        // other, so a new tool cannot arrive with an unstated policy.
        let described = Set(policy.unattended + policy.requiresHumanConfirmation)
        let writes = Set(
            MCPToolCatalog.tools.filter { MCPWriteRoutes.paths.contains($0.path) }.map(\.name))
        eq(writes.subtracting(described), [], "writes with no stated policy")
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
        let served = MCPRoutes.paths.union(MCPWriteRoutes.paths)
        for tool in MCPToolCatalog.tools {
            expect(served.contains(tool.path), "\(tool.name) -> \(tool.path)")
        }
        // And nothing is served that no tool can reach — an unreachable route is
        // either a missing tool or dead code, and both want finding.
        let reached = Set(MCPToolCatalog.tools.map(\.path))
        eq(reached, served)
        // The read and write surfaces don't overlap: a path is one or the other,
        // so "does this tool write" is answerable from the route alone.
        eq(MCPRoutes.paths.intersection(MCPWriteRoutes.paths), [])
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

// MARK: - Agent proposals (TASK-45)

/// One proposal item, with only the field under test spelled out.
func proposalItem(_ key: String, reason: String = "no reason given") -> SenderProposal.Item {
    SenderProposal.Item(
        groupKey: "domain:\(key)", senderName: key.capitalized, senderEmail: "hello@\(key)",
        reason: reason)
}

func proposalGroup(_ key: String, messages: Int = 1) -> SenderGroup {
    SenderGroup(
        id: GroupID(kind: .domain, key: key),
        messages: (0..<messages).map { mcpMessage(UInt32(abs(key.hashValue % 1000) + $0), from: "X <a@\(key)>") })
}

Harness.suite("Agent proposals") {
    Harness.test("a proposal under the cap is left alone") {
        let (proposal, dropped) = SenderProposal.capped(items: [proposalItem("a"), proposalItem("b")])
        eq(proposal.items.count, 2)
        eq(dropped, 0)
    }

    Harness.test("an oversized proposal is truncated and says how much was cut") {
        let items = (0..<40).map { proposalItem("s\($0)") }
        let (proposal, dropped) = SenderProposal.capped(items: items)
        // Reviewability is the safety mechanism, so the cap is the product
        // decision and the count is what stops the agent believing all forty
        // are under review.
        eq(proposal.items.count, SenderProposal.maxItems)
        eq(dropped, 40 - SenderProposal.maxItems)
        eq(proposal.items.first?.groupKey, "domain:s0", "kept the agent's first choices")
    }

    Harness.test("one sender proposed twice is one row, and doesn't spend two of the cap") {
        let items = (0..<30).map { proposalItem("s\($0)") } + [proposalItem("s0", reason: "again")]
        let (proposal, dropped) = SenderProposal.capped(items: items)
        eq(proposal.items.count, SenderProposal.maxItems)
        // 30 distinct senders, not 31: the duplicate is dropped before the cap,
        // so the cap counts senders rather than mentions.
        eq(dropped, 30 - SenderProposal.maxItems)
        eq(proposal.items.filter { $0.groupKey == "domain:s0" }.count, 1)
        eq(proposal.items.first?.reason, "no reason given", "the first mention wins")
    }

    Harness.test("removing a sender leaves the rest in the agent's order") {
        let proposal = SenderProposal(items: [proposalItem("a"), proposalItem("b"), proposalItem("c")])
        let edited = proposal.removing(groupKeys: ["domain:b"])
        eq(edited?.items.map(\.groupKey), ["domain:a", "domain:c"])
        eq(edited?.id, proposal.id, "still the same proposal")
    }

    Harness.test("removing the last sender clears the proposal outright") {
        // Nil rather than an empty proposal: the sidebar row exists only while
        // there is something to review, so emptying it must remove it.
        let proposal = SenderProposal(items: [proposalItem("a")])
        expect(proposal.removing(groupKeys: ["domain:a"]) == nil)
    }

    Harness.test("rows come back in the agent's order, not the mailbox's") {
        let proposal = SenderProposal(items: [proposalItem("c"), proposalItem("a"), proposalItem("b")])
        let groups = [proposalGroup("a"), proposalGroup("b"), proposalGroup("c")]
        eq(proposal.senders(in: groups).map(\.id.key), ["c", "a", "b"])
    }

    Harness.test("a sender whose mail has gone still gets a row") {
        // Trashed between the proposal and the review, which are hours apart.
        // The row stays so the human reviews the proposal that was actually
        // made; it simply has no group behind it.
        let proposal = SenderProposal(items: [proposalItem("gone"), proposalItem("here")])
        let rows = proposal.senders(in: [proposalGroup("here")])
        eq(rows.count, 2)
        expect(rows[0].group == nil, "no group for the departed sender")
        expect(rows[0].item.senderName == "Gone", "but still says who it was")
        expect(rows[1].group != nil)
    }

    Harness.test("search matches the agent's reason, not only the sender") {
        let proposal = SenderProposal(items: [
            proposalItem("acme", reason: "left over from the 2026 job search"),
            proposalItem("shop", reason: "unread for two years"),
        ])
        let groups = [proposalGroup("acme"), proposalGroup("shop")]
        eq(proposal.senders(in: groups, matching: "job search").map(\.id.key), ["acme"])
        eq(proposal.senders(in: groups, matching: "SHOP").map(\.id.key), ["shop"])
        eq(proposal.senders(in: groups, matching: "  ").count, 2, "blank search filters nothing")
    }

    Harness.test("an unreadable group key is dropped rather than crashing the list") {
        let proposal = SenderProposal(items: [
            SenderProposal.Item(
                groupKey: "not-a-key", senderName: "?", senderEmail: "?", reason: "?"),
            proposalItem("ok"),
        ])
        eq(proposal.senders(in: [proposalGroup("ok")]).map(\.id.key), ["ok"])
    }
}

Harness.suite("Proposed collection") {
    Harness.test("Proposed holds exactly the senders under review") {
        expect(SenderCollection.proposed.contains(SenderState(isProposed: true)))
        expect(!SenderCollection.proposed.contains(SenderState()))
    }

    Harness.test("being proposed doesn't move a sender out of where it lives") {
        // The overlay rule: a proposal is a suggestion, and until the human
        // says otherwise nothing has happened to the sender.
        let s = SenderState(isProposed: true)
        eq(SenderCollection.allCases.filter { $0.contains(s) }, [.allSenders, .proposed])
    }

    Harness.test("Proposed sorts last, so 'which collection is this sender in' is unchanged") {
        // `MCPSnapshot.collection(of:)` takes the first match. Proposed must
        // never be that answer, or an agent would read "under review" as the
        // sender's state.
        eq(SenderCollection.allCases.last, .proposed)
        eq(
            SenderCollection.allCases.first { $0.contains(SenderState(isProposed: true)) },
            .allSenders)
    }

    Harness.test("adding Proposed did not renumber the collection shortcuts") {
        // ⌘1…⌘4 are positions in `allCases` (Commands.swift). Documented in
        // UI_SPEC.md §8, and in muscle memory.
        eq(
            SenderCollection.allCases,
            [.allSenders, .reappeared, .unsubscribed, .ignored, .proposed])
    }

    Harness.test("reviewing an untouched sender can do everything All Senders can") {
        // A review you can't act on sends the user to another list to finish it.
        // (The one divergence — a row already unsubscribed — is the next test.)
        for action in SelectionAction.allCases {
            for withMessages in [2, 0] {
                let proposed = SelectionContext(
                    collection: .proposed, count: 2, withMessages: withMessages)
                let all = SelectionContext(
                    collection: .allSenders, count: 2, withMessages: withMessages)
                eq(
                    action.unavailability(in: proposed),
                    action.unavailability(in: all),
                    "\(action.rawValue) with \(withMessages) still holding mail")
            }
        }
    }

    Harness.test("a proposed sender who is already done can't be unsubscribed twice") {
        // Acting on a row doesn't remove it from the proposal — the proposal is
        // the record of what was proposed — so this is the one list that can
        // still be showing a sender who is finished.
        let done = SelectionContext(
            collection: .proposed, count: 2, withMessages: 2, alreadyUnsubscribed: 2)
        eq(
            SelectionAction.unsubscribe.unavailability(in: done),
            "Already unsubscribed. Forget the record to unsubscribe again.")
        // And the escape hatch that sentence names is reachable from here.
        expect(SelectionAction.forget.unavailability(in: done) == nil, "forget is offered")

        let mixed = SelectionContext(
            collection: .proposed, count: 3, withMessages: 3, alreadyUnsubscribed: 1)
        eq(
            SelectionAction.unsubscribeAndDelete.unavailability(in: mixed),
            "Some of these are already unsubscribed. Deselect them first.")
        expect(
            SelectionAction.forget.unavailability(in: mixed) != nil,
            "and forget isn't offered for a selection that isn't all records")
    }

    Harness.test("the read-only MCP surface refuses to list Proposed") {
        // It lives in the running app, not the database a snapshot is built
        // from, so serving it would always be an empty list — which an agent
        // would read as the human having cleared it.
        let store = try! MessageStore.inMemory()
        try! store.upsert([mcpMessage(1, from: "A <a@acme.com>")])
        let response = mcpCall("/mcp/senders/list", try! mcpSnapshot(store), ["collection": "proposed"])
        eq(response.statusCode, 400)
        expect(!MCPRoutes.readable.contains(.proposed), "and it isn't offered as an option")
        expect(
            !MCPToolCatalog.tools.contains { $0.schemaJSON.contains("\"proposed\"") },
            "nor advertised in the tool schema")
    }
}

Harness.suite("Proposals survive a relaunch") {
    /// A store on a real path, so it can be closed and opened again — which is
    /// the only way to prove "survives quitting and reopening the app" without
    /// a UI.
    func temporaryPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("nevermore-proposal-\(UUID().uuidString).sqlite").path
    }

    Harness.test("a proposal is still there after the store is closed and reopened") {
        let path = temporaryPath()
        let proposal = SenderProposal(
            summary: "left over from the 2026 job search",
            items: [proposalItem("acme", reason: "you stopped opening these in March")])
        do {
            let store = try! MessageStore(path: path)
            try! store.setProposal(proposal)
        }
        // A second MessageStore on the same file: a relaunch, as far as
        // anything below the app can tell.
        let reopened = try! MessageStore(path: path)
        let read = reopened.proposal()
        eq(read?.id, proposal.id)
        eq(read?.summary, "left over from the 2026 job search")
        eq(read?.items.first?.reason, "you stopped opening these in March")
        eq(read?.items.first?.senderEmail, "hello@acme")
        // Seconds resolution, not identity: the encoding is lossy below that.
        eq(
            read.map { Int($0.createdAt.timeIntervalSince1970) },
            Int(proposal.createdAt.timeIntervalSince1970))
    }

    Harness.test("a fresh mailbox has no proposal") {
        expect(try! MessageStore.inMemory().proposal() == nil)
    }

    Harness.test("a second proposal replaces the first rather than queueing") {
        let store = try! MessageStore.inMemory()
        try! store.setProposal(SenderProposal(items: [proposalItem("a")]))
        try! store.setProposal(SenderProposal(items: [proposalItem("b"), proposalItem("c")]))
        eq(store.proposal()?.items.map(\.groupKey), ["domain:b", "domain:c"])
    }

    Harness.test("dismissing clears the proposal and acts on nothing") {
        // The whole safety argument: declining must be inert. Nothing about the
        // senders — ignored, unsubscribed, or their mail — may move.
        let store = try! MessageStore.inMemory()
        try! store.upsert([mcpMessage(1, from: "A <a@acme.com>")])
        let id = GroupID(kind: .domain, key: "acme.com")
        try! store.ignore(id)
        try! store.recordUnsubscribe(
            GroupID(kind: .domain, key: "shop.com"), senderName: "Shop",
            senderEmail: "s@shop.com", senderDomain: "shop.com", url: nil, outcome: .confirmed)
        try! store.setProposal(SenderProposal(items: [proposalItem("acme.com")]))

        try! store.clearProposal()

        expect(store.proposal() == nil, "the proposal is gone")
        eq(try! store.count(), 1, "their messages are untouched")
        eq(try! store.ignoredGroupKeys(), [id.storageKey], "the ignore list is untouched")
        eq(try! store.unsubscribeHistory().count, 1, "the unsubscribe log is untouched")
    }
}

// MARK: - TASK-46: the agent acts only on a selection the human confirmed

/// `Harness.test` for a body that has to await something.
///
/// The action layer, the token vault and the outcome ledger are all actors —
/// they are reached from the server's actor and from the main actor — so nearly
/// every test below is async. This keeps `runAsync` out of thirty test bodies.
func asyncTest(_ name: String, _ body: @escaping @Sendable () async -> Void) {
    Harness.test(name) { runAsync { await body() } }
}

Harness.suite("Review tokens") {
    let acme = "domain:acme.com"
    let shop = "domain:shop.com"
    let news = "domain:news.com"

    asyncTest("a confirmed selection can be acted on, once") {
        let vault = ReviewTokenVault()
        let token = await vault.mint(confirming: [acme, shop])
        do {
            try await vault.redeem(token, for: [acme, shop])
        } catch { expect(false, "the confirmed set was refused: \(error)") }
    }

    asyncTest("a token cannot be replayed") {
        // The captured-token case: whatever else went wrong, spending it twice
        // must not work, because the human said yes once.
        let vault = ReviewTokenVault()
        let token = await vault.mint(confirming: [acme])
        try? await vault.redeem(token, for: [acme])
        do {
            try await vault.redeem(token, for: [acme])
            expect(false, "a spent token was accepted a second time")
        } catch { eq(error as? ReviewTokenError, .notOutstanding) }
    }

    asyncTest("a token is worthless against a set the user never saw") {
        let vault = ReviewTokenVault()
        let token = await vault.mint(confirming: [acme, shop])
        // One extra sender smuggled into the batch.
        do {
            try await vault.redeem(token, for: [acme, shop, news])
            expect(false, "a token was accepted for a larger set")
        } catch { eq(error as? ReviewTokenError, .setMismatch) }
        // A subset is refused too: the token records what was confirmed, not a
        // budget to spend part of.
        do {
            try await vault.redeem(token, for: [acme])
            expect(false, "a token was accepted for a subset")
        } catch { eq(error as? ReviewTokenError, .setMismatch) }
        // A different set of the same size — the substitution a replay would
        // actually try.
        do {
            try await vault.redeem(token, for: [acme, news])
            expect(false, "a token was accepted for a substituted set")
        } catch { eq(error as? ReviewTokenError, .setMismatch) }
        // And none of that burned the confirmation the user really gave.
        do {
            try await vault.redeem(token, for: [shop, acme])
        } catch { expect(false, "a failed attempt spent the real confirmation: \(error)") }
    }

    asyncTest("an expired token is refused, and stays refused") {
        let vault = ReviewTokenVault()
        let issued = Date(timeIntervalSince1970: 1_700_000_000)
        let token = await vault.mint(confirming: [acme], now: issued)
        let justInside = issued.addingTimeInterval(ReviewTokenVault.lifetime - 1)
        let justOutside = issued.addingTimeInterval(ReviewTokenVault.lifetime)
        expect(!token.isExpired(at: justInside), "still good a second before")
        expect(token.isExpired(at: justOutside), "dead on the boundary")
        do {
            try await vault.redeem(token, for: [acme], now: justOutside)
            expect(false, "an expired token was accepted")
        } catch { eq(error as? ReviewTokenError, .expired) }
        // Not merely refused this once — gone, so a clock that moves back
        // doesn't resurrect it.
        do {
            try await vault.redeem(token, for: [acme], now: justInside)
            expect(false, "an expired token came back to life")
        } catch { eq(error as? ReviewTokenError, .notOutstanding) }
    }

    asyncTest("a token nobody minted is refused") {
        // Belt and braces on the type's non-public initializer: a second vault
        // is as close as anything can get to fabricating one.
        let real = ReviewTokenVault()
        let other = ReviewTokenVault()
        let token = await other.mint(confirming: [acme])
        do {
            try await real.redeem(token, for: [acme])
            expect(false, "a foreign token was accepted")
        } catch { eq(error as? ReviewTokenError, .notOutstanding) }
    }

    asyncTest("the fingerprint is about the senders, not the order or the duplicates") {
        eq(
            ReviewToken.fingerprint(of: [acme, shop]),
            ReviewToken.fingerprint(of: [shop, acme, acme]))
        expect(
            ReviewToken.fingerprint(of: [acme]) != ReviewToken.fingerprint(of: [shop]),
            "different senders, different fingerprint")
        // Not a join that could be gamed by a key containing the separator.
        expect(
            ReviewToken.fingerprint(of: ["a\nb"]) != ReviewToken.fingerprint(of: ["a", "b"]),
            "the separator isn't forgeable through a key")
    }

    asyncTest("expired tokens don't accumulate") {
        let vault = ReviewTokenVault()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for _ in 0 ..< 5 {
            _ = await vault.mint(confirming: [acme], now: start)
        }
        eq(await vault.outstandingCount, 5)
        // One later mint, after they have all aged out.
        _ = await vault.mint(
            confirming: [shop], now: start.addingTimeInterval(ReviewTokenVault.lifetime))
        eq(await vault.outstandingCount, 1, "the dead ones were swept, not kept")
        // A token that is merely old is untouched.
        _ = await vault.mint(
            confirming: [news], now: start.addingTimeInterval(ReviewTokenVault.lifetime + 1))
        eq(await vault.outstandingCount, 2, "the live one survived the next mint")
    }
}

/// A stub action layer, so the write routes can be driven without a running app.
///
/// TASK-41 refuses the MCP surface in demo mode, so there is no mailbox a test
/// may drive these through — the harness is the only place they can be proven,
/// by design rather than by omission. It records what it was asked to do, which
/// is what most of these tests are actually asserting: that the route passed the
/// right thing along, or refused before it got here.
actor StubActions: MCPActions {
    struct Call: Equatable {
        let verb: String
        let detail: String
    }

    private(set) var calls: [Call] = []
    var proposalOutcome: AgentActionOutcome?

    private func note(_ verb: String, _ detail: String = "") {
        calls.append(Call(verb: verb, detail: detail))
    }

    func verbs() -> [String] { calls.map(\.verb) }
    func details(of verb: String) -> [String] {
        calls.filter { $0.verb == verb }.map(\.detail)
    }

    func propose(summary: String?, requests: [AgentProposalRequest]) async -> AgentActionOutcome {
        note(
            "propose",
            requests.map { "\($0.senderId)|\($0.recommendation.rawValue)" }
                .joined(separator: ","))
        let items = requests.map {
            SenderProposal.Item(
                groupKey: $0.senderId, senderName: $0.senderId, senderEmail: "x@\($0.senderId)",
                reason: $0.reason, recommendation: $0.recommendation)
        }
        return .proposal(
            AgentProposalBuilder.build(
                summary: summary, resolved: items, candidatesReceived: requests.count
            ).result)
    }

    func proposalStatus() async -> AgentActionOutcome {
        note("status")
        return .status(
            AgentProposalStatus(
                state: AgentProposalStatus.awaitingReview, proposalId: "p", createdAt: nil,
                summary: nil, proposedCount: 1, remainingCount: 1, removedByHuman: [],
                outcomes: [], note: "note"))
    }

    func requestUnsubscribe(senderId: String) async -> AgentActionOutcome {
        note("unsubscribe", senderId)
        return .result(
            AgentActionResult(
                status: AgentActionResult.awaitingConfirmation, senderId: senderId,
                detail: "asking the user"))
    }

    func requestTrash(senderId: String) async -> AgentActionOutcome {
        note("trash", senderId)
        return .result(
            AgentActionResult(
                status: AgentActionResult.awaitingConfirmation, senderId: senderId,
                detail: "asking the user"))
    }

    /// The browser queue this stub pretends to hold (TASK-47). Real enough to
    /// prove the thing that matters: routes can fill it and read it, and nothing
    /// on the surface can work it.
    private var browserQueue = BrowserQueue()

    func queue() -> BrowserQueue { browserQueue }

    func queueForBrowser(senderIds: [String]) async -> AgentActionOutcome {
        note("queue_for_browser", senderIds.joined(separator: ","))
        var results: [AgentSenderResult] = []
        for senderId in senderIds {
            let queued = browserQueue.queue(
                BrowserQueue.Entry(
                    groupKey: senderId, senderName: senderId, senderEmail: "x@\(senderId)",
                    reason: .noPublishedTarget))
            results.append(
                AgentSenderResult(
                    senderId: senderId, senderName: senderId, applied: queued,
                    detail: queued ? "queued" : "already waiting"))
        }
        return .browserQueue(
            AgentBrowserQueueStatus(queue: browserQueue, results: results, note: "queued."))
    }

    func browserQueueStatus() async -> AgentActionOutcome {
        note("browser_queue_status")
        return .browserQueue(AgentBrowserQueueStatus(queue: browserQueue))
    }

    /// Only a test may do this — it stands in for the human working the sheet,
    /// which is the one thing no route can reach.
    func humanRecords(_ outcome: BrowserQueue.Outcome, for senderId: String) {
        browserQueue.record(outcome, for: senderId)
    }

    func setIgnored(_ ignored: Bool, senderIds: [String]) async -> AgentActionOutcome {
        note(ignored ? "ignore" : "unignore", senderIds.joined(separator: ","))
        return .result(
            AgentActionResult(
                status: AgentActionResult.done, detail: "done",
                results: senderIds.map {
                    AgentSenderResult(senderId: $0, senderName: $0, applied: true, detail: "ok")
                }))
    }

    func setClassification(
        senderId: String, classification: String, reason: String, context: String?
    ) async -> AgentActionOutcome {
        note("classify", "\(senderId)|\(classification)|\(reason)|\(context ?? "-")")
        return .result(
            AgentActionResult(status: AgentActionResult.done, senderId: senderId, detail: "done"))
    }

    func startSync() async -> AgentActionOutcome {
        note("sync")
        return .result(AgentActionResult(status: AgentActionResult.done, detail: "started"))
    }

    func setGrouping(senderId: String, mode: AgentGroupingMode) async -> AgentActionOutcome {
        note("grouping", "\(senderId)|\(mode.rawValue)")
        return .result(
            AgentActionResult(status: AgentActionResult.done, senderId: senderId, detail: "done"))
    }

    func forgetUnsubscribeRecord(senderId: String) async -> AgentActionOutcome {
        note("forget", senderId)
        return .result(
            AgentActionResult(status: AgentActionResult.done, senderId: senderId, detail: "done"))
    }
}

func mcpWrite(_ path: String, _ arguments: [String: Any] = [:], actions: (any MCPActions)?)
    async -> HTTPResponse
{
    let body = try? JSONSerialization.data(withJSONObject: arguments)
    let request = HTTPRequest(
        method: "POST", path: path, headers: ["content-type": "application/json"], body: body)
    return await MCPWriteRoutes.handle(path: path, request: request, actions: actions)
        ?? .error("no such route", code: 404)
}

Harness.suite("MCP write routes") {
    asyncTest("a proposal over the cap is truncated and the agent is told") {
        // AC #3. The half that matters is the reporting: the human sees 25 of
        // the 40, and an agent that wasn't told would go on to report on 15
        // senders nobody ever looked at.
        let actions = StubActions()
        let senders = (0 ..< 40).map {
            ["sender_id": "domain:s\($0)", "reason": "r\($0)", "recommendation": "unsubscribe"]
        }
        let response = await mcpWrite(
            "/mcp/proposal/create", ["summary": "the 2026 job search", "senders": senders],
            actions: actions)
        eq(response.statusCode, 200)
        let json = mcpJSON(response)
        eq(json["proposed"] as? Int, SenderProposal.maxItems)
        eq(json["candidates_received"] as? Int, 40)
        eq(json["dropped"] as? Int, 40 - SenderProposal.maxItems)
        eq(json["truncated"] as? Bool, true)
        eq(json["cap"] as? Int, SenderProposal.maxItems)
        let note = json["note"] as? String ?? ""
        expect(note.contains("\(40 - SenderProposal.maxItems) were dropped"), "note: \(note)")
        expect(note.contains("Do not report them as proposed"), "and says what not to do")
    }

    asyncTest("a proposal under the cap says so too, rather than saying nothing") {
        let response = await mcpWrite(
            "/mcp/proposal/create",
            ["senders": [
                ["sender_id": "domain:a", "reason": "unread since March",
                 "recommendation": "unsubscribe"]
            ]],
            actions: StubActions())
        let json = mcpJSON(response)
        eq(json["truncated"] as? Bool, false)
        eq(json["dropped"] as? Int, 0)
        eq(json["proposed"] as? Int, 1)
        expect(
            (json["note"] as? String ?? "").contains("Nothing has happened to these senders"),
            "and is clear that proposing is not acting")
    }

    asyncTest("a sender with no reason is refused rather than shown blank") {
        // The reason is the only thing that makes the agent's judgement
        // checkable; a row without one can only be rubber-stamped.
        let actions = StubActions()
        let response = await mcpWrite(
            "/mcp/proposal/create",
            ["senders": [
                ["sender_id": "domain:a", "reason": "ok", "recommendation": "ignore"],
                ["sender_id": "domain:b", "recommendation": "ignore"],
            ]],
            actions: actions)
        eq(response.statusCode, 400)
        eq(await actions.verbs(), [], "and nothing was proposed")
        let message = String(decoding: response.body, as: UTF8.self)
        expect(message.contains("rubber-stamp"), "and says why: \(message)")
    }

    asyncTest("an empty proposal is refused") {
        eq(await mcpWrite("/mcp/proposal/create", [:], actions: StubActions()).statusCode, 400)
        eq(
            await mcpWrite("/mcp/proposal/create", ["senders": []], actions: StubActions())
                .statusCode, 400)
    }

    asyncTest("unsubscribe takes one sender, and says why when asked for more") {
        // AC #1 at the surface: the batch path an agent would reach for isn't
        // refused for lack of a token — it does not exist, and the refusal says
        // what to do instead.
        let actions = StubActions()
        let response = await mcpWrite(
            "/mcp/senders/unsubscribe", ["sender_ids": ["domain:a", "domain:b"]], actions: actions)
        eq(response.statusCode, 400)
        eq(await actions.verbs(), [], "nothing was attempted")
        let message = String(decoding: response.body, as: UTF8.self)
        expect(message.contains("no bulk unsubscribe over MCP"), message)
        expect(message.contains("propose_selection"), "and points at the way that works")

        let single = await mcpWrite(
            "/mcp/senders/unsubscribe", ["sender_id": "domain:a"], actions: actions)
        eq(single.statusCode, 200)
        eq(mcpJSON(single)["status"] as? String, "awaiting_confirmation")
        eq(await actions.details(of: "unsubscribe"), ["domain:a"])
    }

    asyncTest("trash asks the user, whatever else is in the request") {
        // AC #6. There is no argument that changes this, so the ones an agent
        // might try are simply ignored.
        let actions = StubActions()
        for extras in [[:], ["confirm": true], ["force": true], ["skip_confirmation": true]]
            as [[String: Any]]
        {
            var arguments: [String: Any] = ["sender_id": "domain:a"]
            for (key, value) in extras { arguments[key] = value }
            let response = await mcpWrite("/mcp/senders/trash", arguments, actions: actions)
            eq(response.statusCode, 200)
            eq(
                mcpJSON(response)["status"] as? String, "awaiting_confirmation",
                "with \(extras.keys.joined(separator: ","))")
        }
        eq(await actions.verbs().count, 4, "each one reached the app as a request, not an action")
    }

    asyncTest("ignore and unignore report per sender, never a total") {
        let actions = StubActions()
        let response = await mcpWrite(
            "/mcp/senders/ignore", ["sender_ids": ["domain:a", "domain:b"]], actions: actions)
        let rows = mcpRows(response, "results")
        eq(rows.count, 2)
        eq(rows.first?["sender_id"] as? String, "domain:a")
        eq(await actions.details(of: "ignore"), ["domain:a,domain:b"])

        eq(
            await mcpWrite("/mcp/senders/unignore", ["sender_id": "domain:a"], actions: actions)
                .statusCode, 200)
        eq(await actions.details(of: "unignore"), ["domain:a"])
        // A single sender and a one-element list mean the same thing.
        eq(await mcpWrite("/mcp/senders/ignore", [:], actions: actions).statusCode, 400)
    }

    asyncTest("a classification needs a label and a reason") {
        let actions = StubActions()
        eq(
            await mcpWrite(
                "/mcp/senders/classify", ["sender_id": "domain:a", "classification": "keep"],
                actions: actions
            ).statusCode, 400, "no reason")
        eq(
            await mcpWrite(
                "/mcp/senders/classify", ["sender_id": "domain:a", "reason": "why"],
                actions: actions
            ).statusCode, 400, "no classification")
        eq(
            await mcpWrite(
                "/mcp/senders/classify",
                [
                    "sender_id": "domain:a", "classification": "expired-situation",
                    "reason": "the job search ended", "context": "job-search-2026",
                ], actions: actions
            ).statusCode, 200)
        eq(
            await actions.details(of: "classify"),
            ["domain:a|expired-situation|the job search ended|job-search-2026"])
    }

    asyncTest("grouping takes one of two modes") {
        let actions = StubActions()
        eq(
            await mcpWrite(
                "/mcp/senders/grouping", ["sender_id": "domain:a", "mode": "shuffle"],
                actions: actions
            ).statusCode, 400)
        for mode in AgentGroupingMode.allCases {
            eq(
                await mcpWrite(
                    "/mcp/senders/grouping", ["sender_id": "domain:a", "mode": mode.rawValue],
                    actions: actions
                ).statusCode, 200, mode.rawValue)
        }
    }

    asyncTest("every write refuses when no mailbox is open") {
        // A 200 for a write that landed nowhere would be reported to the user as
        // done. Only the policy answers without an app behind it.
        for path in MCPWriteRoutes.paths.sorted() {
            let response = await mcpWrite(path, ["sender_id": "domain:a"], actions: nil)
            if path == MCPWriteRoutes.policyPath {
                eq(response.statusCode, 200, "the policy is answerable with no mailbox")
            } else {
                eq(response.statusCode, 503, path)
            }
        }
    }

    asyncTest("the policy route answers with the surface's own rules") {
        let json = mcpJSON(await mcpWrite("/mcp/policy", [:], actions: nil))
        eq(json["batch_unsubscribe_available"] as? Bool, false)
        eq(json["proposal_cap"] as? Int, SenderProposal.maxItems)
        let confirmed = json["requires_human_confirmation"] as? [String] ?? []
        eq(Set(confirmed), ["unsubscribe", "trash_sender_messages"])
    }

    asyncTest("a path that isn't a write route is left for the read surface") {
        let request = HTTPRequest(method: "POST", path: "/mcp/senders/list", headers: [:], body: nil)
        let response = await MCPWriteRoutes.handle(
            path: "/mcp/senders/list", request: request, actions: StubActions())
        expect(response == nil, "the write dispatcher claimed a read route")
    }
}

Harness.suite("Agent outcome honesty") {
    asyncTest("the four outcomes reach the agent as four outcomes") {
        // AC #4/#5. The app itself only says 'confirmed' when a human watched
        // the sender's confirmation page, so an agent reporting 'unsubscribed'
        // for a 'requested' would be inventing evidence Nevermore refuses to.
        eq(UnsubscribeEngine.Outcome.confirmed(detail: "d").agentOutcomeName, "confirmed")
        eq(UnsubscribeEngine.Outcome.requested(detail: "d").agentOutcomeName, "requested")
        eq(UnsubscribeEngine.Outcome.failed(detail: "d").agentOutcomeName, "failed")
        eq(UnsubscribeEngine.Outcome.needsManual(reason: "r").agentOutcomeName, "needs_manual")
        // Distinct, not merely present: nothing collapses two of them.
        let names = Set(
            [
                UnsubscribeEngine.Outcome.confirmed(detail: ""), .requested(detail: ""),
                .failed(detail: ""), .needsManual(reason: ""),
            ].map(\.agentOutcomeName))
        eq(names.count, 4)
    }

    asyncTest("the engine's own words survive the trip") {
        eq(
            UnsubscribeEngine.Outcome.requested(detail: "one-click accepted (HTTP 202), unverifiable")
                .agentDetail,
            "one-click accepted (HTTP 202), unverifiable")
        eq(
            UnsubscribeEngine.Outcome.needsManual(reason: "no unsubscribe link").agentDetail,
            "no unsubscribe link")
    }

    asyncTest("a success flag would have hidden three of the four") {
        // Why the wire carries the name rather than isSuccess: an endpoint
        // answering 'success' proves nothing about an unsubscribe.
        let requested = UnsubscribeEngine.Outcome.requested(detail: "accepted, unverifiable")
        expect(requested.isSuccess, "the app counts it a success")
        eq(requested.agentOutcomeName, "requested", "and still never calls it confirmed")
    }

    asyncTest("the ledger answers per sender, and only about the senders asked for") {
        let ledger = AgentOutcomeLedger()
        await ledger.record([
            AgentOutcome(
                senderId: "domain:a", senderName: "A", outcome: .requested(detail: "accepted")),
            AgentOutcome(
                senderId: "domain:b", senderName: "B", outcome: .needsManual(reason: "no link")),
            AgentOutcome(
                senderId: "domain:c", senderName: "C", outcome: .failed(detail: "HTTP 500")),
        ])
        let mine = await ledger.outcomes(for: ["domain:a", "domain:b"])
        eq(mine.count, 2)
        eq(mine.map(\.outcome), ["requested", "needs_manual"])
        eq(await ledger.outcomes(for: ["domain:z"]).count, 0)
    }

    asyncTest("the ledger is bounded, keeping the newest") {
        let ledger = AgentOutcomeLedger()
        let overflow = AgentOutcomeLedger.capacity + 10
        for index in 0 ..< overflow {
            await ledger.record(
                AgentOutcome(
                    senderId: "domain:s\(index)", senderName: "S", outcome: .failed(detail: "x")))
        }
        let kept = await ledger.recent()
        eq(kept.count, AgentOutcomeLedger.capacity)
        eq(kept.last?.senderId, "domain:s\(overflow - 1)")
    }

    asyncTest("an outcome serialises with the distinction intact") {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let payload = AgentProposalStatus(
            state: AgentProposalStatus.edited, proposalId: "p", createdAt: nil, summary: nil,
            proposedCount: 2, remainingCount: 1, removedByHuman: ["domain:b"],
            outcomes: [
                AgentOutcome(
                    senderId: "domain:a", senderName: "A",
                    outcome: .requested(detail: "accepted, unverifiable"))
            ],
            note: "n")
        let json =
            (try? JSONSerialization.jsonObject(with: encoder.encode(payload))) as? [String: Any]
            ?? [:]
        eq(json["state"] as? String, "edited")
        eq((json["removed_by_human"] as? [String])?.first, "domain:b")
        let outcome = (json["outcomes"] as? [[String: Any]])?.first ?? [:]
        eq(outcome["outcome"] as? String, "requested")
        eq(outcome["sender_id"] as? String, "domain:a")
        expect(json["outcome_count"] == nil, "no total stands in for the per-sender rows")
    }
}

Harness.suite("Agent-initiated trash always confirms") {
    asyncTest("an agent's trash prompts however low the user's threshold is") {
        // AC #6, as a rule rather than as a code path: no message count and no
        // threshold makes an agent-initiated trash silent.
        for threshold in [0, 1, 25, 1000] {
            for count in [0, 1, 5, 5000] {
                expect(
                    TrashConfirmation.requiresPrompt(
                        origin: .agent, messageCount: count, threshold: threshold),
                    "agent, \(count) messages, threshold \(threshold)")
            }
        }
    }

    asyncTest("an agent's unsubscribe confirms even with confirmations turned off") {
        // "Ask before unsubscribing" is the user saying *my* keystroke should
        // just go. The MCP route answers awaiting_confirmation, and that has to
        // be true in both settings of that switch or the answer is a lie.
        for askBefore in [true, false] {
            expect(
                UnsubscribeConfirmation.requiresPrompt(
                    origin: .agent, askBeforeUnsubscribe: askBefore),
                "agent, askBeforeUnsubscribe = \(askBefore)")
        }
        expect(
            UnsubscribeConfirmation.requiresPrompt(origin: .user, askBeforeUnsubscribe: true),
            "the user's own preference still decides for the user")
        expect(
            !UnsubscribeConfirmation.requiresPrompt(origin: .user, askBeforeUnsubscribe: false),
            "including when they turned it off")
    }

    asyncTest("the user's own threshold still applies to the user") {
        expect(
            !TrashConfirmation.requiresPrompt(origin: .user, messageCount: 5, threshold: 25),
            "a small trash the user asked for doesn't prompt")
        expect(
            TrashConfirmation.requiresPrompt(origin: .user, messageCount: 500, threshold: 25),
            "a big one does")
    }
}

/// A server with a token and no mailbox, so what's under test is the order of
/// the checks rather than what any route would answer.
func guardedCall(
    _ path: String, token: String? = "secret", method: String = "POST", isDemo: Bool = false
) async -> HTTPResponse {
    let server = NevermoreServer(isDemo: isDemo, mcpToken: "secret")
    var headers = ["content-type": "application/json"]
    if let token { headers["authorization"] = "Bearer \(token)" }
    return await server.routeRequest(
        HTTPRequest(method: method, path: path, headers: headers, body: Data("{}".utf8)))
}

Harness.suite("The write surface is guarded like the read surface") {
    asyncTest("a write with the wrong credential is 401, before anything else") {
        for path in MCPWriteRoutes.paths.sorted() {
            eq(await guardedCall(path, token: "wrong").statusCode, 401, path)
            eq(await guardedCall(path, token: nil).statusCode, 401, "\(path) with no header")
        }
    }

    asyncTest("a write refuses in demo mode") {
        // TASK-41: the demo mailbox is fabricated, so acting on it is acting on
        // senders that do not exist. Including the policy — an agent that read a
        // policy here would think it had a mailbox to apply it to.
        for path in MCPWriteRoutes.paths.sorted() {
            let response = await guardedCall(path, isDemo: true)
            eq(response.statusCode, 403, path)
        }
    }

    asyncTest("a write over GET is 405, not a silent no-op") {
        eq(await guardedCall("/mcp/senders/ignore", method: "GET").statusCode, 405)
    }

    asyncTest("an unconfigured server refuses writes rather than opening them up") {
        let server = NevermoreServer(mcpToken: "")
        let response = await server.routeRequest(
            HTTPRequest(
                method: "POST", path: "/mcp/senders/ignore",
                headers: ["authorization": "Bearer anything"], body: nil))
        eq(response.statusCode, 503)
    }

    asyncTest("a write reaches the app once one is attached") {
        let actions = StubActions()
        let server = NevermoreServer(mcpToken: "secret")
        await server.setMCPActions(actions)
        let response = await server.routeRequest(
            HTTPRequest(
                method: "POST", path: "/mcp/senders/ignore",
                headers: [
                    "authorization": "Bearer secret", "content-type": "application/json",
                ],
                body: try! JSONSerialization.data(withJSONObject: ["sender_id": "domain:a"])))
        eq(response.statusCode, 200)
        eq(await actions.details(of: "ignore"), ["domain:a"])
        // And it needed no snapshot: the write surface acts on the live app, so
        // a server with actions and no mailbox context still serves it.
    }
}

// MARK: - TASK-47: the browser queue

/// A group with one message, so `BrowserQueue.reason` has something to read.
func queueGroup(
    _ key: String = "acme.com", unsub: String? = "<https://ex.com/u>", oneClick: Bool = false
) -> SenderGroup {
    SenderGroup(
        id: GroupID(kind: .domain, key: key),
        messages: [mcpMessage(1, from: "A <a@\(key)>", unsub: unsub, oneClick: oneClick)])
}

func queueEntry(_ key: String, reason: BrowserReason = .noPublishedTarget) -> BrowserQueue.Entry {
    BrowserQueue.Entry(
        groupKey: "domain:\(key)", senderName: key, senderEmail: "hello@\(key)", reason: reason,
        queuedAt: Date(timeIntervalSince1970: 1_700_000_000))
}

Harness.suite("Browser queue") {
    Harness.test("the queue is worked in the order it was filled") {
        var queue = BrowserQueue()
        queue.queue([queueEntry("a"), queueEntry("b"), queueEntry("c")])
        eq(queue.next?.groupKey, "domain:a")
        eq(queue.pendingCount, 3)
        queue.record(.confirmed, for: "domain:a")
        eq(queue.next?.groupKey, "domain:b", "the next one, not a re-run of the first")
        eq(queue.position(of: "domain:b"), 2, "positions count the whole queue, worked included")
        eq(queue.count, 3, "the total doesn't shrink under the user as they go")
    }

    Harness.test("queueing the same sender twice is one row") {
        // A duplicate is a page the user would be sent to twice for no reason.
        var queue = BrowserQueue()
        eq(queue.queue([queueEntry("a"), queueEntry("a"), queueEntry("b")]), ["domain:a", "domain:b"])
        eq(queue.count, 2)
    }

    Harness.test("re-queueing a sender that was already worked asks to redo it") {
        var queue = BrowserQueue()
        queue.queue([queueEntry("a"), queueEntry("b")])
        queue.record(.abandoned, for: "domain:a")
        expect(queue.queue(queueEntry("a")), "an answered sender can be put back")
        eq(queue.entries.map(\.groupKey), ["domain:b", "domain:a"], "at the end, not in place")
        eq(queue.next?.groupKey, "domain:b", "and it doesn't jump the rest of the sitting")
        eq(queue.pendingCount, 2)
    }

    Harness.test("an answer is terminal") {
        // A stale sheet answering twice must not rewrite what happened.
        var queue = BrowserQueue()
        queue.queue(queueEntry("a"))
        expect(queue.record(.confirmed, for: "domain:a"))
        expect(!queue.record(.abandoned, for: "domain:a"), "the second answer is refused")
        eq(queue.entry(for: "domain:a")?.outcome, .confirmed)
        expect(!queue.record(.confirmed, for: "domain:nobody"), "and an unqueued sender is refused")
    }

    Harness.test("a confirmed unsubscribe is not the same fact as an abandoned one") {
        // AC #3. Three outcomes and not a Bool: "I did it", "their page wouldn't
        // let me", and "I gave up" are different, and only the first is the
        // sender being unsubscribed from.
        var queue = BrowserQueue()
        queue.queue([queueEntry("a"), queueEntry("b"), queueEntry("c")])
        queue.record(.confirmed, for: "domain:a")
        queue.record(.couldNotUnsubscribe, for: "domain:b")
        queue.record(.abandoned, for: "domain:c")
        eq(queue.confirmedCount, 1, "worked is not the same as unsubscribed")
        eq(queue.worked.count, 3)
        eq(queue.pendingCount, 0)
        expect(BrowserQueue.Outcome.confirmed.isUnsubscribed)
        expect(!BrowserQueue.Outcome.abandoned.isUnsubscribed)
        expect(!BrowserQueue.Outcome.couldNotUnsubscribe.isUnsubscribed)
    }

    Harness.test("leaving part-way keeps the rest") {
        // AC #5, as a value: stopping is simply not recording anything more.
        var queue = BrowserQueue()
        queue.queue((0 ..< 5).map { queueEntry("s\($0)") })
        queue.record(.confirmed, for: "domain:s0")
        queue.record(.abandoned, for: "domain:s1")
        eq(queue.pending.map(\.groupKey), ["domain:s2", "domain:s3", "domain:s4"])
        eq(queue.next?.groupKey, "domain:s2")
    }

    Harness.test("the queue survives being written down and read back") {
        var queue = BrowserQueue()
        queue.queue([queueEntry("a", reason: .ignoredAnUnsubscribe), queueEntry("b")])
        queue.record(.couldNotUnsubscribe, for: "domain:a", at: Date(timeIntervalSince1970: 1))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let read = try! decoder.decode(BrowserQueue.self, from: try! encoder.encode(queue))
        eq(read.entries.map(\.groupKey), ["domain:a", "domain:b"])
        eq(read.entry(for: "domain:a")?.outcome, .couldNotUnsubscribe)
        eq(read.entry(for: "domain:a")?.reason, .ignoredAnUnsubscribe)
        eq(read.next?.groupKey, "domain:b")
    }

    Harness.test("removing takes a sender out without working them") {
        var queue = BrowserQueue()
        queue.queue([queueEntry("a"), queueEntry("b")])
        expect(queue.remove("domain:a"))
        eq(queue.entries.map(\.groupKey), ["domain:b"])
        expect(!queue.remove("domain:a"), "and removing it again changes nothing")
        queue.clear()
        expect(queue.isEmpty)
    }
}

Harness.suite("Who needs a browser") {
    // AC #1's other half: the set is decided from stored headers and the
    // unsubscribe record, so it is knowable before anything is attempted.
    Harness.test("a sender with no published target needs a browser") {
        eq(
            BrowserQueue.reason(for: queueGroup(unsub: nil), hasReappeared: false),
            .noPublishedTarget)
    }

    Harness.test("a sender who ignored an unsubscribe needs a browser") {
        eq(
            BrowserQueue.reason(for: queueGroup(), hasReappeared: true),
            .ignoredAnUnsubscribe)
    }

    Harness.test("a bare mailto to an alias we can't send as needs a browser") {
        // The case the engine already refuses to guess at: sending from the
        // wrong identity is a request that quietly goes nowhere.
        let group = queueGroup(unsub: "<mailto:unsub@ex.com>")
        eq(
            BrowserQueue.reason(
                for: group, hasReappeared: false, canSendAsDeliveredAddress: false),
            .wrongDeliveryAddress)
        expect(
            BrowserQueue.reason(for: group, hasReappeared: false) == nil,
            "and not when the account can send as that address")
        // A mailto carrying a per-recipient token identifies you without the
        // From address, so it is not this case.
        expect(
            BrowserQueue.reason(
                for: queueGroup(unsub: "<mailto:unsub@ex.com?subject=stop-a1b2>"),
                hasReappeared: false, canSendAsDeliveredAddress: false) == nil)
    }

    Harness.test("a sender something automated can still finish does not") {
        expect(BrowserQueue.reason(for: queueGroup(), hasReappeared: false) == nil)
        expect(
            BrowserQueue.reason(for: queueGroup(oneClick: true), hasReappeared: false) == nil)
    }

    Harness.test("no target beats every other reason") {
        // Whatever else is true of them, there is nothing to send.
        eq(
            BrowserQueue.reason(
                for: queueGroup(unsub: nil), hasReappeared: true,
                canSendAsDeliveredAddress: false),
            .noPublishedTarget)
    }

    Harness.test("the needs_browser filter and the queue agree about who qualifies") {
        // One definition, so an agent cannot select a set with list_senders that
        // queue_for_browser then declines.
        let store = try! MessageStore.inMemory()
        try! store.upsert([
            mcpMessage(1, from: "None <a@none.com>", unsub: nil),
            mcpMessage(2, from: "Fine <b@fine.com>"),
        ])
        let snapshot = try! mcpSnapshot(store)
        let rows = mcpRows(mcpCall("/mcp/senders/list", snapshot, ["needs_browser": true]))
        eq(rows.map { $0["id"] as? String }, ["domain:none.com"])
        for group in snapshot.groups {
            eq(
                BrowserQueue.reason(for: group, hasReappeared: snapshot.hasReappeared(group)) != nil,
                rows.contains { $0["id"] as? String == group.id.storageKey },
                group.id.storageKey)
        }
    }
}

Harness.suite("The browser queue survives a relaunch") {
    func temporaryPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("nevermore-queue-\(UUID().uuidString).sqlite").path
    }

    Harness.test("a half-worked sitting is still there after the store is reopened") {
        // AC #5 end to end: the user stops, quits, and comes back to the rest.
        let path = temporaryPath()
        var queue = BrowserQueue()
        queue.queue([queueEntry("a"), queueEntry("b"), queueEntry("c")])
        queue.record(.confirmed, for: "domain:a")
        do {
            let store = try! MessageStore(path: path)
            try! store.setBrowserQueue(queue)
        }
        let reopened = try! MessageStore(path: path)
        let read = reopened.browserQueue()
        eq(read.count, 3)
        eq(read.pending.map(\.groupKey), ["domain:b", "domain:c"])
        eq(read.entry(for: "domain:a")?.outcome, .confirmed)
        eq(read.entry(for: "domain:b")?.reason, .noPublishedTarget)
    }

    Harness.test("a fresh mailbox has an empty queue") {
        expect(try! MessageStore.inMemory().browserQueue().isEmpty)
    }

    Harness.test("clearing the queue acts on nothing") {
        let store = try! MessageStore.inMemory()
        try! store.upsert([mcpMessage(1, from: "A <a@acme.com>")])
        try! store.setBrowserQueue(BrowserQueue(entries: [queueEntry("acme.com")]))
        try! store.clearBrowserQueue()
        expect(store.browserQueue().isEmpty)
        eq(try! store.count(), 1, "their messages are untouched")
        eq(try! store.unsubscribeHistory().count, 0, "and nothing was recorded against them")
    }
}

Harness.suite("Browser queue over MCP") {
    asyncTest("an agent can queue senders without attempting an unsubscribe") {
        // AC #1. The route's whole job: collect, and touch nothing.
        let actions = StubActions()
        let response = await mcpWrite(
            "/mcp/browser-queue/add", ["sender_ids": ["domain:a", "domain:b"]], actions: actions)
        eq(response.statusCode, 200)
        let json = mcpJSON(response)
        eq(json["total"] as? Int, 2)
        eq(json["pending"] as? Int, 2)
        eq(json["confirmed"] as? Int, 0)
        eq(await actions.verbs(), ["queue_for_browser"], "and nothing else was called")
        expect(
            !(await actions.verbs()).contains("unsubscribe"),
            "queueing is not an unsubscribe")
    }

    asyncTest("queueing reports per sender, including the ones already waiting") {
        let actions = StubActions()
        _ = await mcpWrite("/mcp/browser-queue/add", ["sender_id": "domain:a"], actions: actions)
        let again = await mcpWrite(
            "/mcp/browser-queue/add", ["sender_ids": ["domain:a", "domain:b"]], actions: actions)
        let results = mcpRows(again, "results")
        eq(results.count, 2)
        eq(results.first?["applied"] as? Bool, false)
        eq(results.last?["applied"] as? Bool, true)
        eq(mcpJSON(again)["total"] as? Int, 2, "and no duplicate row was added")
    }

    asyncTest("queueing nothing is refused with a pointer to the filter") {
        let actions = StubActions()
        let response = await mcpWrite("/mcp/browser-queue/add", [:], actions: actions)
        eq(response.statusCode, 400)
        expect(
            String(decoding: response.body, as: UTF8.self).contains("needs_browser"),
            "the refusal says where the set comes from")
        eq(await actions.verbs(), [], "and never reached the app")
    }

    asyncTest("an agent can read progress but cannot make any") {
        // AC #4, and the point of the whole feature. The human's answers arrive
        // through the sheet; every route on the surface is driven here and the
        // queue is unchanged by all of them.
        let actions = StubActions()
        _ = await mcpWrite(
            "/mcp/browser-queue/add", ["sender_ids": ["domain:a", "domain:b"]], actions: actions)
        await actions.humanRecords(.confirmed, for: "domain:a")

        let status = mcpJSON(await mcpWrite("/mcp/browser-queue/status", actions: actions))
        eq(status["total"] as? Int, 2)
        eq(status["pending"] as? Int, 1)
        eq(status["confirmed"] as? Int, 1)
        let entries = (status["entries"] as? [[String: Any]]) ?? []
        eq(entries.first?["state"] as? String, "confirmed")
        eq(entries.last?["state"] as? String, "pending")
        eq(entries.last?["reason"] as? String, "no_published_target")

        // Every write route, with every argument that might plausibly be read as
        // "and mark it done".
        for path in MCPWriteRoutes.paths.sorted() where path != "/mcp/browser-queue/add" {
            _ = await mcpWrite(
                path,
                [
                    "sender_id": "domain:b", "sender_ids": ["domain:b"], "outcome": "confirmed",
                    "state": "confirmed", "confirmed": true, "classification": "x", "reason": "y",
                    "mode": "keep_as_one", "senders": [["sender_id": "domain:b", "reason": "y"]],
                ],
                actions: actions)
        }
        eq(await actions.queue().pendingCount, 1, "nothing an agent can call worked an entry")
        eq(await actions.queue().entry(for: "domain:b")?.outcome, nil)
    }

    Harness.test("there is no route that advances the queue") {
        // Structural, not a policy: the only two paths are add and status.
        eq(
            MCPWriteRoutes.paths.filter { $0.hasPrefix("/mcp/browser-queue") }.sorted(),
            ["/mcp/browser-queue/add", "/mcp/browser-queue/status"])
        for tool in MCPToolCatalog.tools where tool.path.hasPrefix("/mcp/browser-queue") {
            for forbidden in ["advance", "next", "complete", "record", "open", "confirm"] {
                expect(
                    !tool.name.contains(forbidden),
                    "\(tool.name) reads as a verb that works the queue")
            }
        }
        // And the tool descriptions say so, since a client may show only one.
        for name in ["queue_for_browser", "get_browser_queue"] {
            let tool = MCPToolCatalog.tool(named: name)
            expect(tool != nil, name)
            expect(
                tool?.description.contains("no tool") ?? false,
                "\(name) does not say that no tool advances the queue")
        }
    }

    Harness.test("queueing is unattended, and is not a way to unsubscribe") {
        expect(MCPWriteRoutes.unattendedTools.contains("queue_for_browser"))
        expect(MCPWriteRoutes.unattendedTools.contains("get_browser_queue"))
        expect(!MCPWriteRoutes.confirmedTools.contains("queue_for_browser"))
        expect(!MCPWriteRoutes.policy.batchUnsubscribeAvailable)
    }

    Harness.test("every browser-queue answer says nothing was sent") {
        let queue = BrowserQueue(entries: [queueEntry("a")])
        for status in [
            AgentBrowserQueueStatus(queue: queue),
            AgentBrowserQueueStatus(queue: queue, note: "Queued 1 sender."),
        ] {
            expect(status.note.contains("Queueing sends nothing"), "the note is always there")
            expect(status.note.contains("confirmed"), "and says which state means unsubscribed")
        }
    }
}

// MARK: - Removing an account takes the whole database with it

Harness.suite("Account removal leaves no database file behind") {
    // A SQLite database is a family of files, not one file: `-wal` holds writes
    // that have not been checkpointed, and MessageStore leaves a `.pre-*.bak`
    // copy behind before a migration. Removing an account used to delete only
    // the head of that family, so decisions an agent recorded about the user
    // could outlive the mailbox they were about.
    let siblings = ["", "-wal", "-shm", ".pre-v9.bak"]

    func filesMatching(_ path: String) -> [String] {
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent().path
        let all = (try? FileManager.default.contentsOfDirectory(atPath: parent)) ?? []
        return all.filter { $0.hasPrefix(url.lastPathComponent) }.sorted()
    }

    Harness.test("every file sharing the database's name is gone") {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nevermore-remove-\(UUID().uuidString)")
        let registry = AccountRegistry(directory: dir)
        let account = "tester@example.com"
        registry.add(account)
        registry.setProviderID("gmail", for: account)

        let path = registry.databasePath(for: account)
        // Scoped so SQLite's own connection is closed; the siblings are then
        // written by hand, because whether a real store happens to leave a
        // `-wal` behind at any moment is exactly the timing this must not depend on.
        do { _ = try? MessageStore(path: path) }
        for suffix in siblings {
            FileManager.default.createFile(atPath: path + suffix, contents: Data("x".utf8))
        }
        eq(filesMatching(path).count, siblings.count, "all siblings written")

        registry.remove(account)

        expect(filesMatching(path).isEmpty, "left behind: \(filesMatching(path))")
        expect(registry.accounts().isEmpty, "account deregistered")
        eq(registry.providerID(for: account), nil, "provider mapping cleared")

        try? FileManager.default.removeItem(at: dir)
    }

    Harness.test("another account's database is not swept up with it") {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nevermore-remove-\(UUID().uuidString)")
        let registry = AccountRegistry(directory: dir)
        let (going, staying) = ("tester@example.com", "tester@example.com.au")
        registry.add(going)
        registry.add(staying)
        for account in [going, staying] {
            for suffix in siblings {
                FileManager.default.createFile(
                    atPath: registry.databasePath(for: account) + suffix, contents: Data("x".utf8))
            }
        }

        registry.remove(going)

        expect(filesMatching(registry.databasePath(for: going)).isEmpty, "removed account gone")
        eq(
            filesMatching(registry.databasePath(for: staying)).count, siblings.count,
            "the account with the longer name keeps all of its files")
        eq(registry.accounts(), [staying], "and is still registered")

        try? FileManager.default.removeItem(at: dir)
    }

    Harness.test("resetting the demo database takes its siblings too") {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nevermore-demo-\(UUID().uuidString)")
        let registry = AccountRegistry(directory: dir)
        for suffix in siblings {
            FileManager.default.createFile(
                atPath: registry.demoDatabasePath + suffix, contents: Data("x".utf8))
        }

        registry.resetDemoDatabase()

        expect(filesMatching(registry.demoDatabasePath).isEmpty, "demo rebuilds from nothing")

        try? FileManager.default.removeItem(at: dir)
    }
}

// MARK: - Unsubscribe results report (TASK-28)

/// A run of `n` senders, all with the same outcome.
func report(_ outcome: UnsubscribeEngine.Outcome?, _ n: Int) -> UnsubscribeReport {
    UnsubscribeReport(outcomes: Array(repeating: outcome, count: n))
}

Harness.suite("UnsubscribeReport") {
    Harness.test("sorts what needs the user above what needs nothing") {
        let mixed = UnsubscribeReport(outcomes: [
            .confirmed(detail: "ok"),
            .requested(detail: "HTTP 204"),
            .failed(detail: "HTTP 404"),
            .needsManual(reason: "no unsubscribe link"),
            nil,
        ])
        eq(mixed.buckets, [.failed, .notAttempted, .requested, .confirmed])
        expect(mixed.buckets.first?.needsUser == true, "the first bucket is one that needs a decision")
        // The order is fixed, not a property of this particular run.
        eq(UnsubscribeReport.order, [.failed, .notAttempted, .requested, .confirmed])
        expect(UnsubscribeReport.order.prefix(2).allSatisfy(\.needsUser))
        expect(UnsubscribeReport.order.suffix(2).allSatisfy { !$0.needsUser })
    }

    Harness.test("empty buckets do not render") {
        let all = report(.confirmed(detail: "ok"), 3)
        eq(all.buckets, [.confirmed])
        eq(all.count(.failed), 0)
    }

    Harness.test("needsManual is a failure, because the user still has to finish it") {
        eq(UnsubscribeReport.bucket(for: .needsManual(reason: "no link")), .failed)
        eq(UnsubscribeReport.bucket(for: .failed(detail: "HTTP 500")), .failed)
        expect(UnsubscribeReportBucket.failed.needsUser)
    }

    Harness.test("a cancelled sender lands in NOT ATTEMPTED rather than nowhere") {
        eq(UnsubscribeReport.bucket(for: nil), .notAttempted)
        let cancelled = UnsubscribeReport(outcomes: [.confirmed(detail: "ok"), nil, nil])
        eq(cancelled.count(.notAttempted), 2)
        eq(cancelled.total, 3)
        expect(cancelled.buckets.contains(.notAttempted))
    }

    Harness.test("requested is never counted as confirmed") {
        let r = report(.requested(detail: "accepted (HTTP 204), unverifiable"), 4)
        eq(r.count(.confirmed), 0)
        eq(r.count(.requested), 4)
        // It still counts as unsubscribed for the headline — but the bucket
        // beneath it keeps saying which of the two it was.
        eq(r.succeeded, 4)
        eq(r.headline, "Unsubscribed from 4 senders")
    }

    Harness.test("the headline never claims success a run did not have") {
        eq(report(.failed(detail: "HTTP 404"), 1).headline, "No senders were unsubscribed")
        eq(report(.failed(detail: "HTTP 404"), 10).headline, "No senders were unsubscribed")
        eq(report(nil, 5).headline, "No senders were unsubscribed")
        eq(UnsubscribeReport(outcomes: []).headline, "No senders were unsubscribed")
    }

    Harness.test("the headline reconciles with the buckets when a run has failures") {
        var outcomes: [UnsubscribeEngine.Outcome?] = Array(
            repeating: .requested(detail: "sent"), count: 10)
        outcomes.append(.failed(detail: "endpoint returned HTTP 404"))
        let r = UnsubscribeReport(outcomes: outcomes)
        // The old wording was "Unsubscribed from 10 senders" above "FAILED · 1",
        // leaving the reader to reconcile 10 against 11.
        eq(r.headline, "Unsubscribed from 10 of 11 senders")
        eq(r.total, 11)
        eq(r.succeeded, 10)
        eq(r.needingUser, 1)
    }

    Harness.test("no 'of' when there is nothing to reconcile") {
        eq(report(.confirmed(detail: "ok"), 1).headline, "Unsubscribed from 1 sender")
        eq(report(.confirmed(detail: "ok"), 10).headline, "Unsubscribed from 10 senders")
        eq(report(.confirmed(detail: "ok"), 50).headline, "Unsubscribed from 50 senders")
    }

    Harness.test("the contents line states the size of the report") {
        eq(report(.confirmed(detail: "ok"), 1).contentsLine, "1 sender in this report")
        eq(report(.confirmed(detail: "ok"), 10).contentsLine, "10 senders in this report")
        eq(report(.confirmed(detail: "ok"), 50).contentsLine, "50 senders in this report")
    }

    Harness.test("the contents line says what is still waiting on the user") {
        var outcomes: [UnsubscribeEngine.Outcome?] = Array(
            repeating: .confirmed(detail: "ok"), count: 9)
        outcomes.append(.failed(detail: "HTTP 404"))
        eq(
            UnsubscribeReport(outcomes: outcomes).contentsLine,
            "10 senders in this report · 1 still needs you, listed first")
        outcomes.append(nil)
        outcomes.append(.needsManual(reason: "no unsubscribe link"))
        eq(
            UnsubscribeReport(outcomes: outcomes).contentsLine,
            "12 senders in this report · 3 still need you, listed first")
    }

    // The three sizes from the defect report, plus the run where everything
    // failed — the case that used to be announced as a success.
    Harness.test("holds up at 1, 10 and 50 senders, and at an all-failed run") {
        for n in [1, 10, 50] {
            let good = report(.confirmed(detail: "ok"), n)
            eq(good.total, n)
            eq(good.succeeded, n)
            eq(good.needingUser, 0)
            eq(good.buckets, [.confirmed])
            expect(good.contentsLine.hasPrefix("\(n) sender"))

            let bad = report(.failed(detail: "endpoint returned HTTP 404"), n)
            eq(bad.total, n)
            eq(bad.succeeded, 0)
            eq(bad.needingUser, n)
            eq(bad.headline, "No senders were unsubscribed")
            eq(bad.buckets, [.failed], "an all-failed run opens on the failures")

            // Half and half: the mix that has to be readable at a glance.
            let mixed = UnsubscribeReport(
                outcomes: Array(repeating: .requested(detail: "sent"), count: n)
                    + Array(repeating: .failed(detail: "HTTP 500"), count: n))
            eq(mixed.headline, "Unsubscribed from \(n) of \(2 * n) senders")
            eq(mixed.buckets.first, .failed, "the actionable bucket is first at every size")
        }
    }

    Harness.test("every bucket carries the label and symbol the sheet draws") {
        for bucket in UnsubscribeReportBucket.allCases {
            expect(!bucket.title.isEmpty, "\(bucket) has no title")
            expect(bucket.title == bucket.title.uppercased(), "\(bucket) title is not a heading")
            expect(!bucket.symbolName.isEmpty, "\(bucket) has no symbol")
            expect(UnsubscribeReport.order.contains(bucket), "\(bucket) renders nowhere")
        }
        eq(UnsubscribeReport.order.count, UnsubscribeReportBucket.allCases.count)
    }
}

// MARK: - The action a proposal recommends (TASK-52)

/// Found in use: an agent proposed two cold-outreach senders with reasons
/// beginning "IGNORE, do not unsubscribe", and both were unsubscribed, because
/// the row's primary button said Unsubscribe and `u` was already in the fingers.
/// Prose cannot override a button, so the recommendation is data now.
Harness.suite("A proposal carries the action, not prose about it") {
    Harness.test("an item keeps the action the agent chose, through a round trip") {
        for action in RecommendedAction.allCases {
            let item = SenderProposal.Item(
                groupKey: "domain:a", senderName: "A", senderEmail: "a@a", reason: "why",
                recommendation: action)
            let data = try! JSONEncoder().encode(item)
            let back = try! JSONDecoder().decode(SenderProposal.Item.self, from: data)
            eq(back.recommendation, action, action.rawValue)
        }
    }

    Harness.test("a proposal stored before recommendations existed still opens") {
        // The stored proposal survives a relaunch, so the decoder has to cope
        // with rows written by the previous build. Unsubscribe is what those
        // rows already meant; the difference is that the row now says so.
        let legacy = """
            {"groupKey":"domain:a","senderName":"A","senderEmail":"a@a","reason":"unread"}
            """
        let item = try! JSONDecoder().decode(
            SenderProposal.Item.self, from: Data(legacy.utf8))
        eq(item.recommendation, .unsubscribe)
        eq(item.reason, "unread")
    }

    Harness.test("the contradiction check finds only the rows that disagree") {
        let proposal = SenderProposal(items: [
            SenderProposal.Item(
                groupKey: "domain:a", senderName: "A", senderEmail: "a@a", reason: "recurring",
                recommendation: .unsubscribe),
            SenderProposal.Item(
                groupKey: "domain:b", senderName: "B", senderEmail: "b@b", reason: "cold outreach",
                recommendation: .ignore),
            SenderProposal.Item(
                groupKey: "domain:c", senderName: "C", senderEmail: "c@c", reason: "one-off",
                recommendation: .trash),
        ])
        let all: Set<String> = ["domain:a", "domain:b", "domain:c"]
        eq(
            proposal.items(contradicting: .unsubscribe, in: all).map(\.groupKey),
            ["domain:b", "domain:c"])
        // Only the selection is asked about: unsubscribing from the one sender
        // that *was* recommended for it must not stop to ask about the others.
        expect(proposal.items(contradicting: .unsubscribe, in: ["domain:a"]).isEmpty)
        // And a sender that is not in the proposal at all is not its business.
        expect(proposal.items(contradicting: .unsubscribe, in: ["domain:zz"]).isEmpty)
    }

    Harness.test("the override warning names the sender and repeats the agent's words") {
        let items = [
            SenderProposal.Item(
                groupKey: "domain:b", senderName: "Cold Outreach Co", senderEmail: "b@b",
                reason: "Cold outreach — unsubscribing confirms the address is live.",
                recommendation: .ignore)
        ]
        let message = ProposalOverrideWarning.message(for: items)
        expect(message.contains("Cold Outreach Co"), message)
        expect(
            message.contains("Cold outreach — unsubscribing confirms the address is live."),
            "the agent's reason, verbatim: \(message)")
        expect(message.contains("Ignore"), "and what was recommended instead: \(message)")
        expect(message.contains("cannot be taken back"), "and why this one is different")
        expect(ProposalOverrideWarning.title(count: 1).contains("this sender"))
        expect(ProposalOverrideWarning.title(count: 3).contains("3 of these"))
    }
}

Harness.suite("propose_selection requires an action") {
    asyncTest("the three recommendations reach the action layer intact") {
        for action in RecommendedAction.allCases {
            let actions = StubActions()
            let response = await mcpWrite(
                "/mcp/proposal/create",
                [
                    "senders": [
                        ["sender_id": "domain:a", "reason": "r", "recommendation": action.rawValue]
                    ]
                ],
                actions: actions)
            eq(response.statusCode, 200, action.rawValue)
            eq(await actions.details(of: "propose"), ["domain:a|\(action.rawValue)"])
        }
    }

    asyncTest("a sender with no recommendation is refused rather than assumed to mean unsubscribe") {
        // The defect, in one test. Defaulting here is what turned "IGNORE, do
        // not unsubscribe" into two unsubscribes.
        let actions = StubActions()
        let response = await mcpWrite(
            "/mcp/proposal/create",
            [
                "senders": [
                    ["sender_id": "domain:a", "reason": "r", "recommendation": "ignore"],
                    ["sender_id": "domain:b", "reason": "r"],
                ]
            ],
            actions: actions)
        eq(response.statusCode, 400)
        eq(await actions.verbs(), [], "and nothing was proposed")
        let message = String(decoding: response.body, as: UTF8.self)
        expect(message.contains("will not assume unsubscribe"), message)
        for action in RecommendedAction.allCases {
            expect(message.contains(action.rawValue), "and lists \(action.rawValue)")
        }
    }

    asyncTest("a recommendation Nevermore does not have is refused, with the list") {
        let actions = StubActions()
        let response = await mcpWrite(
            "/mcp/proposal/create",
            ["senders": [["sender_id": "domain:a", "reason": "r", "recommendation": "delete_all"]]],
            actions: actions)
        eq(response.statusCode, 400)
        eq(await actions.verbs(), [])
        expect(
            String(decoding: response.body, as: UTF8.self).contains("not a recommendation"),
            "says the value was the problem")
    }

    Harness.test("the tool says when each action is appropriate, and warns off the default") {
        let tool = MCPToolCatalog.tools.first { $0.name == "propose_selection" }!
        for action in RecommendedAction.allCases {
            expect(tool.description.contains(action.rawValue), "describes \(action.rawValue)")
        }
        expect(
            tool.description.contains("cold outreach and one-off senders are ignored or trashed"),
            "carries the standing rule")
        expect(
            tool.description.contains("not enough"),
            "and says that putting it in the reason will not do")
        let schema =
            (try? JSONSerialization.jsonObject(with: Data(tool.schemaJSON.utf8)))
            as? [String: Any] ?? [:]
        let senders = (schema["properties"] as? [String: Any])?["senders"] as? [String: Any]
        let item = senders?["items"] as? [String: Any]
        eq(
            (item?["required"] as? [String])?.sorted(),
            ["reason", "recommendation", "sender_id"])
        let field = (item?["properties"] as? [String: Any])?["recommendation"] as? [String: Any]
        eq(field?["enum"] as? [String], RecommendedAction.allCases.map(\.rawValue))
    }
}

Harness.suite("get_proposal_status reports followed or overrode") {
    let sent = SenderProposal(items: [
        SenderProposal.Item(
            groupKey: "domain:a", senderName: "A", senderEmail: "a@a", reason: "recurring",
            recommendation: .unsubscribe),
        SenderProposal.Item(
            groupKey: "domain:b", senderName: "B", senderEmail: "b@b", reason: "cold outreach",
            recommendation: .ignore),
        SenderProposal.Item(
            groupKey: "domain:c", senderName: "C", senderEmail: "c@c", reason: "one-off",
            recommendation: .trash),
        SenderProposal.Item(
            groupKey: "domain:d", senderName: "D", senderEmail: "d@d", reason: "wrong about this",
            recommendation: .ignore),
    ])

    Harness.test("following, overriding, striking out and not deciding are four answers") {
        let decisions = AgentProposalDecisions.build(
            sent: sent,
            humanActions: ["domain:a": .unsubscribe, "domain:b": .unsubscribe],
            stillUnderReview: ["domain:c"])
        eq(decisions.count, 4)
        eq(decisions[0].humanAction, "unsubscribe")
        eq(decisions[0].followedRecommendation, true)
        // The case this whole task is about: recommended ignore, unsubscribed.
        eq(decisions[1].recommended, "ignore")
        eq(decisions[1].humanAction, "unsubscribe")
        eq(decisions[1].followedRecommendation, false)
        eq(decisions[2].humanAction, AgentProposalDecision.undecided)
        eq(decisions[2].followedRecommendation, nil, "undecided is neither")
        eq(decisions[3].humanAction, AgentProposalDecision.removed)
        eq(decisions[3].followedRecommendation, nil, "struck out is neither")
    }

    Harness.test("the override note names them and says not to re-propose") {
        let decisions = AgentProposalDecisions.build(
            sent: sent, humanActions: ["domain:b": .unsubscribe], stillUnderReview: [])
        let overrides = AgentProposalDecisions.overrides(in: decisions)
        eq(overrides.map(\.senderId), ["domain:b"])
        let note = AgentProposalDecisions.overrideNote(overrides) ?? ""
        expect(note.contains("B (recommended ignore, the human chose unsubscribe)"), note)
        expect(note.contains("considered disagreement"), note)
        expect(
            AgentProposalDecisions.overrideNote([]) == nil,
            "and there is no note when nothing was overridden")
    }

    Harness.test("the status serialises decisions in the snake case the wire uses") {
        let status = AgentProposalStatus(
            state: AgentProposalStatus.inProgress, proposalId: "p", createdAt: nil, summary: nil,
            proposedCount: 4, remainingCount: 1, removedByHuman: [], outcomes: [],
            decisions: AgentProposalDecisions.build(
                sent: sent, humanActions: ["domain:b": .unsubscribe],
                stillUnderReview: ["domain:c"]),
            note: "n")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let json =
            (try? JSONSerialization.jsonObject(with: try! encoder.encode(status)))
            as? [String: Any] ?? [:]
        let decisions = json["decisions"] as? [[String: Any]] ?? []
        eq(decisions.count, 4)
        eq(decisions[1]["sender_id"] as? String, "domain:b")
        eq(decisions[1]["recommended"] as? String, "ignore")
        eq(decisions[1]["human_action"] as? String, "unsubscribe")
        eq(decisions[1]["followed_recommendation"] as? Bool, false)
        eq(decisions[2]["human_action"] as? String, AgentProposalDecision.undecided)
    }

    Harness.test("get_proposal_status tells the agent what an override means") {
        let tool = MCPToolCatalog.tools.first { $0.name == "get_proposal_status" }!
        expect(tool.description.contains("decisions"), tool.description)
        expect(tool.description.contains("overrode"), "and names the case")
        expect(
            tool.description.contains("considered disagreement"),
            "and says what to make of it")
    }
}

// MARK: - DNS rebinding / pinned HTTP client (TASK-4)

/// A plain HTTP server on loopback that answers a canned response per request
/// and records what it was asked. Stands in for an unsubscribe endpoint.
///
/// Note this is a *test* listener. The app itself never binds one — the App
/// Sandbox entitlements grant `network.client` only, which is exactly why the
/// fix connects outbound rather than running a local proxy.
final class StubHTTPServer: @unchecked Sendable {
    private(set) var port: UInt16 = 0
    private let listener: NWListener
    private let respond: @Sendable (String) -> String
    private let lock = NSLock()
    private var seen: [String] = []

    var requests: [String] { lock.withLock { seen } }
    var requestLines: [String] { requests.map { $0.components(separatedBy: "\r\n").first ?? "" } }

    /// Accepts the connection and then says nothing, ever. A hostile endpoint
    /// costs nothing to run and this is the cheapest thing it can do to you.
    private let staysSilent: Bool

    init?(staysSilent: Bool = false, respond: @escaping @Sendable (String) -> String = { _ in "" }) {
        self.respond = respond
        self.staysSilent = staysSilent
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        guard let listener = try? NWListener(using: params, on: .any) else { return nil }
        self.listener = listener
        // Both handlers must be in place before start(), or the listener fails
        // instead of binding.
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed, .cancelled, .waiting: ready.signal()
            default: break
            }
        }
        listener.start(queue: .global())
        guard ready.wait(timeout: .now() + 3) == .success,
              case .ready = listener.state,
              let bound = listener.port?.rawValue
        else {
            listener.cancel()
            return nil
        }
        port = bound
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global())
        read(connection, accumulated: Data())
    }

    private func read(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = accumulated
            if let data { buffer.append(data) }
            if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[buffer.startIndex..<range.lowerBound], as: UTF8.self)
                self.lock.withLock { self.seen.append(head) }
                // Hold the connection open and answer nothing.
                if self.staysSilent { return }
                connection.send(
                    content: Data(self.respond(head).utf8),
                    completion: .contentProcessed { _ in connection.cancel() })
                return
            }
            if error != nil || isComplete {
                connection.cancel()
                return
            }
            self.read(connection, accumulated: buffer)
        }
    }

    func stop() { listener.cancel() }

    static func ok(_ body: String) -> String {
        "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: \(body.utf8.count)\r\n"
            + "Connection: close\r\n\r\n\(body)"
    }

    static func redirect(to location: String, status: Int = 302) -> String {
        "HTTP/1.1 \(status) Found\r\nLocation: \(location)\r\nContent-Length: 0\r\n"
            + "Connection: close\r\n\r\n"
    }
}

/// Records every lookup and can change its answer between them — the whole
/// point of the exercise.
final class RecordingResolver: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []
    private let answer: @Sendable (String, Int) -> [DestinationGuard.PinnedAddress]

    /// `answer` receives the host and the 1-based number of times *that host*
    /// has been looked up.
    init(_ answer: @escaping @Sendable (String, Int) -> [DestinationGuard.PinnedAddress]) {
        self.answer = answer
    }

    var hosts: [String] { lock.withLock { calls } }
    var callCount: Int { lock.withLock { calls.count } }
    func callCount(for host: String) -> Int { lock.withLock { calls.filter { $0 == host }.count } }

    var resolver: PinnedHTTPClient.Resolver {
        { [self] host in
            let nth: Int = lock.withLock {
                calls.append(host)
                return calls.filter { $0 == host }.count
            }
            return answer(host, nth)
        }
    }
}

private func loopbackPin(_ host: String) -> DestinationGuard.PinnedAddress {
    DestinationGuard.PinnedAddress(host: host, literal: "127.0.0.1", isIPv6: false)
}

/// TEST-NET-2. Routable nowhere, so a connection attempt cannot succeed — which
/// is how "the client used the *other* answer" would show up as a failure.
private func unreachablePin(_ host: String) -> DestinationGuard.PinnedAddress {
    DestinationGuard.PinnedAddress(host: host, literal: "198.51.100.1", isIPv6: false)
}

private func send(
    _ client: PinnedHTTPClient, _ method: String, _ urlString: String,
    body: Data? = nil, timeout: TimeInterval = 8
) -> Result<PinnedHTTPClient.Response, PinnedHTTPClient.Failure> {
    runAsync {
        await client.send(
            method: method, url: URL(string: urlString)!, body: body, timeout: timeout)
    }
}

private func status(
    _ result: Result<PinnedHTTPClient.Response, PinnedHTTPClient.Failure>
) -> Int? {
    guard case .success(let response) = result else { return nil }
    return response.statusCode
}

private func failure(
    _ result: Result<PinnedHTTPClient.Response, PinnedHTTPClient.Failure>
) -> PinnedHTTPClient.Failure? {
    guard case .failure(let failure) = result else { return nil }
    return failure
}

Harness.suite("DestinationGuard pinning") {
    Harness.test("a public literal pins to itself") {
        let pin = DestinationGuard.pin(for: "93.184.216.34")
        eq(pin?.literal, "93.184.216.34")
        eq(pin?.isIPv6, false)
        eq(pin?.host, "93.184.216.34")
    }

    Harness.test("a public IPv6 literal pins, and is marked as v6") {
        let pin = DestinationGuard.pin(for: "2606:2800:220:1:248:1893:25c8:1946")
        expect(pin != nil, "public v6 literal pins")
        eq(pin?.isIPv6, true)
    }

    // The pin is the address the connection uses, so anything isAllowed refuses
    // must be unpinnable too — otherwise the two could drift apart and the one
    // that matters would be the looser one.
    Harness.test("refuses to pin anything the guard would block") {
        for host in [
            "127.0.0.1", "10.0.0.5", "192.168.1.1", "172.16.4.4", "169.254.169.254",
            "0.0.0.0", "::1", "[::1]", "fe80::1", "fc00::1", "::ffff:127.0.0.1",
        ] {
            expect(DestinationGuard.pin(for: host) == nil, "pinned a blocked address: \(host)")
        }
    }

    Harness.test("refuses to pin a name that does not resolve") {
        expect(DestinationGuard.pin(for: "nevermore-nothing-here.invalid") == nil, ".invalid")
        expect(DestinationGuard.pinnedAddresses(for: "nevermore-nothing-here.invalid").isEmpty)
    }

    Harness.test("pin is the first of the addresses, not a separate lookup") {
        // If these two ever disagreed, the address that was checked and the
        // address that gets dialled could differ — which is the entire bug.
        let all = DestinationGuard.pinnedAddresses(for: "93.184.216.34")
        eq(DestinationGuard.pin(for: "93.184.216.34"), all.first)
    }
}

Harness.suite("PinnedHTTPClient wire format") {
    func hop(_ urlString: String) -> PinnedHTTPClient.Hop? {
        PinnedHTTPClient.Hop(URL(string: urlString)!)
    }

    Harness.test("Host omits the scheme's default port and keeps any other") {
        eq(hop("http://acme.test/x")?.hostHeader, "acme.test")
        eq(hop("https://acme.test/x")?.hostHeader, "acme.test")
        eq(hop("http://acme.test:8080/x")?.hostHeader, "acme.test:8080")
        // 443 is default for https but not for http, and vice versa.
        eq(hop("http://acme.test:443/x")?.hostHeader, "acme.test:443")
        eq(hop("https://acme.test:80/x")?.hostHeader, "acme.test:80")
    }

    Harness.test("the request target keeps the query and defaults to /") {
        eq(hop("http://acme.test")?.pathAndQuery, "/")
        eq(hop("http://acme.test/unsub?id=7&k=v")?.pathAndQuery, "/unsub?id=7&k=v")
    }

    Harness.test("only http and https are destinations at all") {
        expect(hop("ftp://acme.test/x") == nil, "ftp")
        expect(hop("file:///etc/passwd") == nil, "file")
        expect(PinnedHTTPClient.Hop(URL(string: "mailto:a@b.com")!) == nil, "mailto")
    }

    Harness.test("a request carries one Host, a length, and closes the connection") {
        let text = String(
            decoding: PinnedHTTPClient.requestBytes(
                hop: hop("http://acme.test/unsub?a=1")!,
                method: "POST",
                // A caller trying to set framing headers must not win.
                headers: ["User-Agent": "nevermore", "Host": "evil.test", "Connection": "keep-alive"],
                body: Data("List-Unsubscribe=One-Click".utf8)),
            as: UTF8.self)
        expect(text.hasPrefix("POST /unsub?a=1 HTTP/1.1\r\n"), "request line; got \(text.prefix(40))")
        eq(text.components(separatedBy: "Host: ").count - 1, 1, "exactly one Host header")
        expect(text.contains("Host: acme.test\r\n"), "the real host, not the caller's")
        expect(text.contains("Content-Length: 26\r\n"), "length of the body")
        expect(text.contains("Connection: close\r\n"), "one-shot")
        expect(text.hasSuffix("\r\n\r\nList-Unsubscribe=One-Click"), "body follows the head")
    }

    Harness.test("a response head parses into status and lowercased headers") {
        let response = PinnedHTTPClient.parseResponseHead(
            Data("HTTP/1.1 302 Found\r\nLocation: https://a.test/x\r\nX-Odd-CASE: 1".utf8))
        eq(response?.statusCode, 302)
        eq(response?.headers["location"], "https://a.test/x")
        eq(response?.headers["x-odd-case"], "1", "lookup does not depend on the sender's casing")
    }

    Harness.test("a first Location wins, so a second cannot override it") {
        let response = PinnedHTTPClient.parseResponseHead(
            Data("HTTP/1.1 302 Found\r\nLocation: https://a.test/\r\nLocation: http://10.0.0.1/".utf8))
        eq(response?.headers["location"], "https://a.test/")
    }

    Harness.test("a malformed head is refused rather than guessed at") {
        for head in ["", "not http at all", "HTTP/1.1\r\n", "HTTP/1.1 abc OK\r\n", "HTTP/1.1 999 X\r\n"] {
            expect(PinnedHTTPClient.parseResponseHead(Data(head.utf8)) == nil, "accepted: \(head)")
        }
    }
}

Harness.suite("PinnedHTTPClient (DNS rebinding)") {
    // AC #4, and the heart of the matter. The resolver answers with a reachable
    // address the first time and an unreachable one every time after, which is
    // the rebinding shape: check one address, connect to another.
    //
    // Two things are asserted and both are needed. That the request arrives at
    // the *first* answer proves the validated address is the one dialled. That
    // the host was looked up exactly once proves there was no second lookup for
    // a hostile resolver to answer differently — the window is gone, not merely
    // narrowed.
    Harness.test("a resolver that changes its answer cannot move the connection") {
        guard let origin = StubHTTPServer(respond: { _ in StubHTTPServer.ok("first-answer") })
        else { return expect(false, "could not start stub origin") }
        defer { origin.stop() }

        let resolver = RecordingResolver { host, nth in
            nth == 1 ? [loopbackPin(host)] : [unreachablePin(host)]
        }
        let result = send(
            PinnedHTTPClient(resolve: resolver.resolver), "GET",
            "http://rebind.invalid:\(origin.port)/unsub")

        eq(status(result), 200, "reached the first, validated answer (\(String(describing: failure(result)))")
        eq(resolver.callCount(for: "rebind.invalid"), 1, "exactly one lookup, so nothing to rebind")
        eq(origin.requestLines.first, "GET /unsub HTTP/1.1")
    }

    // The same setup carries a second proof: `rebind.invalid` has no DNS record
    // anywhere (RFC 6761 guarantees it), so a request that succeeds is one
    // nothing but our own resolver could have routed. That is the pre-fix defect
    // stated as an assertion — a second resolver existing at all.
    Harness.test("nothing but the injected resolver ever looks the host up") {
        guard let origin = StubHTTPServer(respond: { _ in StubHTTPServer.ok("pinned") })
        else { return expect(false, "could not start stub origin") }
        defer { origin.stop() }

        // Independently confirm the name really is unresolvable, so this can't
        // quietly pass because some resolver started answering for it.
        expect(DestinationGuard.pin(for: "unresolvable.invalid") == nil, "name does not resolve")

        let resolver = RecordingResolver { host, _ in [loopbackPin(host)] }
        let result = send(
            PinnedHTTPClient(resolve: resolver.resolver), "GET",
            "http://unresolvable.invalid:\(origin.port)/x")
        eq(status(result), 200, "delivered despite no DNS record anywhere")
    }

    // AC #2 on the wire rather than in a unit test: the origin has to see the
    // name it serves, or every virtual host breaks.
    Harness.test("the origin sees the real hostname in Host") {
        guard let origin = StubHTTPServer(respond: { _ in StubHTTPServer.ok("ok") })
        else { return expect(false, "could not start stub origin") }
        defer { origin.stop() }

        let client = PinnedHTTPClient(resolve: { host in [loopbackPin(host)] })
        _ = send(client, "GET", "http://vhost.invalid:\(origin.port)/path?a=1")

        guard let seen = origin.requests.first else {
            return expect(false, "origin received nothing")
        }
        expect(
            seen.contains("Host: vhost.invalid:\(origin.port)"),
            "Host carries the name and the non-default port; saw:\n\(seen)")
        expect(seen.hasPrefix("GET /path?a=1 HTTP/1.1"), "request line; saw:\n\(seen)")
    }

    Harness.test("a refused host is never dialled") {
        guard let origin = StubHTTPServer(respond: { _ in StubHTTPServer.ok("must-not-arrive") })
        else { return expect(false, "could not start stub origin") }
        defer { origin.stop() }

        // Nil is what the real resolver returns for a private, local, or
        // unresolvable answer.
        let client = PinnedHTTPClient(resolve: { _ in [] })
        let result = send(client, "GET", "http://blocked.invalid:\(origin.port)/")
        eq(failure(result), .blocked(host: "blocked.invalid"))
        expect(origin.requests.isEmpty, "the origin was never contacted")
    }

    // Pinning one address would otherwise throw away the failover a resolver's
    // several answers exist to give. A CDN endpoint with a PoP out of rotation
    // must not read to the user as an unsubscribe link that doesn't work.
    Harness.test("a dead first address fails over to the next validated one") {
        guard let origin = StubHTTPServer(respond: { _ in StubHTTPServer.ok("second-address") })
        else { return expect(false, "could not start stub origin") }
        defer { origin.stop() }

        let client = PinnedHTTPClient(resolve: { host in
            // Both were validated by the same single lookup; only the first is dead.
            [unreachablePin(host), loopbackPin(host)]
        })
        // 8s across two addresses is a 4s slice each, so the dead one is given
        // up on quickly rather than stranding the request.
        let result = send(
            client, "GET", "http://multi.invalid:\(origin.port)/unsub", timeout: 8)
        eq(status(result), 200, "reached the live address (\(String(describing: failure(result))))")
    }

    // Found by measurement, not by reasoning: the timeout fired and reported
    // itself accurately while `send` went on running for 30s, because
    // Network.framework ignores Swift task cancellation and the sibling task sat
    // in a continuation until the OS gave up. A budget nobody honours is worse
    // than none, so this asserts the elapsed time, not the error message.
    Harness.test("a timeout ends the request, not just the waiting for it") {
        let client = PinnedHTTPClient(resolve: { host in
            // TEST-NET-2: a connection here can never complete.
            [DestinationGuard.PinnedAddress(host: host, literal: "198.51.100.1", isIPv6: false)]
        })
        let began = Date()
        let result = send(client, "GET", "http://blackhole.invalid/x", timeout: 4)
        let elapsed = Date().timeIntervalSince(began)
        expect(failure(result) != nil, "the attempt failed")
        expect(elapsed < 12, "returned in \(String(format: "%.1f", elapsed))s, budget was 4s")
    }

    // A host that accepts the connection and then answers nothing is the
    // cheapest thing a hostile endpoint can do, and the deadline has to cover
    // the response read — not just the connect — or an unsubscribe hangs on
    // whatever a stranger put in a header.
    Harness.test("a silent endpoint does not hang the request forever") {
        guard let origin = StubHTTPServer(staysSilent: true)
        else { return expect(false, "could not start stub origin") }
        defer { origin.stop() }

        let client = PinnedHTTPClient(resolve: { host in [loopbackPin(host)] })
        let began = Date()
        let result = send(client, "GET", "http://silent.invalid:\(origin.port)/unsub", timeout: 4)
        let elapsed = Date().timeIntervalSince(began)
        expect(failure(result) != nil, "did not invent a response")
        expect(elapsed < 12, "gave up in \(String(format: "%.1f", elapsed))s, budget was 4s")
        expect(!origin.requests.isEmpty, "the request was actually sent and read")
    }

    Harness.test("failover only ever tries addresses that passed the check") {
        guard let origin = StubHTTPServer(respond: { _ in StubHTTPServer.ok("must-not-arrive") })
        else { return expect(false, "could not start stub origin") }
        defer { origin.stop() }

        // An empty answer is the guard's refusal, and there is nothing to fall
        // back to — a refused host must not become a reachable one.
        let client = PinnedHTTPClient(resolve: { _ in [] })
        let result = send(client, "GET", "http://refused.invalid:\(origin.port)/")
        eq(failure(result), .blocked(host: "refused.invalid"))
        expect(origin.requests.isEmpty, "nothing was dialled")
    }

    Harness.test("a non-http scheme is refused before any lookup") {
        let resolver = RecordingResolver { host, _ in [loopbackPin(host)] }
        let client = PinnedHTTPClient(resolve: resolver.resolver)
        let result = send(client, "GET", "ftp://acme.invalid/x")
        expect(failure(result) != nil, "refused")
        eq(resolver.callCount, 0, "never even resolved")
    }

    // AC #3. Each hop is resolved, checked and pinned on its own account.
    Harness.test("a redirect to another host is pinned again, not inherited") {
        guard let second = StubHTTPServer(respond: { _ in StubHTTPServer.ok("second-hop") })
        else { return expect(false, "could not start second origin") }
        defer { second.stop() }
        let secondPort = second.port
        guard let first = StubHTTPServer(respond: { _ in
            StubHTTPServer.redirect(to: "http://hop-two.invalid:\(secondPort)/done")
        }) else { return expect(false, "could not start first origin") }
        defer { first.stop() }

        let resolver = RecordingResolver { host, _ in [loopbackPin(host)] }
        let result = send(
            PinnedHTTPClient(resolve: resolver.resolver), "GET",
            "http://hop-one.invalid:\(first.port)/start")

        eq(status(result), 200, "followed the redirect")
        expect(resolver.hosts.contains("hop-one.invalid"), "hop one was pinned")
        expect(resolver.hosts.contains("hop-two.invalid"), "hop two got its own pin")
        eq(second.requestLines.first, "GET /done HTTP/1.1")
    }

    // The hop-two guard has to survive, and has to stay distinguishable from a
    // sender who simply answered 302 — the engine reports them differently.
    Harness.test("a redirect into a refused host surfaces the 3xx unfollowed") {
        guard let second = StubHTTPServer(respond: { _ in StubHTTPServer.ok("must-not-arrive") })
        else { return expect(false, "could not start second origin") }
        defer { second.stop() }
        let secondPort = second.port
        guard let first = StubHTTPServer(respond: { _ in
            StubHTTPServer.redirect(to: "http://internal.invalid:\(secondPort)/admin")
        }) else { return expect(false, "could not start first origin") }
        defer { first.stop() }

        let client = PinnedHTTPClient(resolve: { host in
            host == "hop-one.invalid" ? [loopbackPin(host)] : []
        })
        let result = send(client, "GET", "http://hop-one.invalid:\(first.port)/start")

        eq(status(result), 302, "the 3xx comes back unfollowed, for the engine to report")
        expect(second.requests.isEmpty, "the internal host was never contacted")
    }

    Harness.test("a relative Location is resolved against the hop it came from") {
        let box = ResultBox<UInt16>()
        guard let origin = StubHTTPServer(respond: { head in
            head.hasPrefix("GET /start")
                ? StubHTTPServer.redirect(to: "/moved") : StubHTTPServer.ok("relative")
        }) else { return expect(false, "could not start stub origin") }
        defer { origin.stop() }
        box.value = origin.port

        let client = PinnedHTTPClient(resolve: { host in [loopbackPin(host)] })
        let result = send(client, "GET", "http://relative.invalid:\(origin.port)/start")
        eq(status(result), 200)
        eq(origin.requestLines.last, "GET /moved HTTP/1.1")
    }

    Harness.test("a redirect loop ends rather than running forever") {
        guard let origin = StubHTTPServer(respond: { _ in StubHTTPServer.redirect(to: "/again") })
        else { return expect(false, "could not start stub origin") }
        defer { origin.stop() }

        let client = PinnedHTTPClient(resolve: { host in [loopbackPin(host)] })
        let result = send(client, "GET", "http://loop.invalid:\(origin.port)/start")
        eq(failure(result), .tooManyRedirects)
        expect(
            origin.requests.count <= PinnedHTTPClient.maxRedirects + 1,
            "bounded at \(PinnedHTTPClient.maxRedirects) hops; made \(origin.requests.count)")
    }

    // RFC 9110: 301/302/303 turn into GET, 307/308 keep the method. One-click is
    // a POST, so getting this wrong either drops the body or replays it.
    Harness.test("a 302 turns a one-click POST into a GET, and 307 does not") {
        for (code, expected) in [(302, "GET /next HTTP/1.1"), (307, "POST /next HTTP/1.1")] {
            guard let origin = StubHTTPServer(respond: { head in
                head.hasPrefix("POST /start")
                    ? StubHTTPServer.redirect(to: "/next", status: code) : StubHTTPServer.ok("done")
            }) else { return expect(false, "could not start stub origin") }
            defer { origin.stop() }

            let client = PinnedHTTPClient(resolve: { host in [loopbackPin(host)] })
            let result = send(
                client, "POST", "http://method.invalid:\(origin.port)/start",
                body: Data("List-Unsubscribe=One-Click".utf8))
            eq(status(result), 200, "HTTP \(code) chain completed")
            eq(origin.requestLines.last, expected, "after HTTP \(code)")
        }
    }
}

// The engine's own vocabulary, driven through an injected client so the
// outcomes a user actually sees are the thing under test.
Harness.suite("UnsubscribeEngine over a pinned client") {
    @Sendable func engine(_ resolve: @escaping PinnedHTTPClient.Resolver) -> UnsubscribeEngine {
        UnsubscribeEngine(
            sendMail: { _, _, _, _ in },
            client: PinnedHTTPClient(resolve: resolve))
    }

    Harness.test("a refused destination reads as blocked, not as a dead link") {
        guard let target = ListUnsubscribe(header: "<http://blocked.invalid/unsub>") else {
            return expect(false, "could not parse header")
        }
        let outcome = runAsync { await engine({ _ in [] }).run(target) }
        guard case .failed(let detail) = outcome else {
            return expect(false, "expected failure, got \(outcome)")
        }
        expect(detail.contains("private or local address"), "says why; got: \(detail)")
    }

    Harness.test("a redirect into a private address is reported as blocked") {
        guard let second = StubHTTPServer(respond: { _ in StubHTTPServer.ok("must-not-arrive") })
        else { return expect(false, "could not start second origin") }
        defer { second.stop() }
        let secondPort = second.port
        guard let first = StubHTTPServer(respond: { _ in
            StubHTTPServer.redirect(to: "http://internal.invalid:\(secondPort)/admin")
        }) else { return expect(false, "could not start first origin") }
        defer { first.stop() }

        guard let target = ListUnsubscribe(header: "<http://sender.invalid:\(first.port)/unsub>")
        else { return expect(false, "could not parse header") }
        let outcome = runAsync {
            await engine({ host in host == "sender.invalid" ? [loopbackPin(host)] : [] }).run(target)
        }
        guard case .failed(let detail) = outcome else {
            return expect(false, "expected failure, got \(outcome)")
        }
        expect(detail.contains("redirected to a private or local address"), "got: \(detail)")
        expect(second.requests.isEmpty, "the internal host was never contacted")
    }

    // 0.1.0 shipped exactly this bug — "A blocked SSRF redirect was recorded as
    // a successful unsubscribe" — because the unfollowed 3xx fell under
    // `code < 400`. The sender was then moved out of the working list as though
    // it had worked. Nothing in the suite guarded it before this: `main` has no
    // redirect test of any kind. `isSuccess` is the exact property that
    // regressed, so it is what gets asserted, across every redirect status.
    Harness.test("a blocked redirect is never recorded as a success") {
        for code in [301, 302, 303, 307, 308] {
            guard let internalHost = StubHTTPServer(respond: { _ in StubHTTPServer.ok("owned") })
            else { return expect(false, "could not start internal origin") }
            defer { internalHost.stop() }
            let internalPort = internalHost.port
            guard let sender = StubHTTPServer(respond: { _ in
                StubHTTPServer.redirect(to: "http://internal.invalid:\(internalPort)/admin", status: code)
            }) else { return expect(false, "could not start sender origin") }
            defer { sender.stop() }

            guard let target = ListUnsubscribe(header: "<http://sender.invalid:\(sender.port)/unsub>")
            else { return expect(false, "could not parse header") }
            let outcome = runAsync {
                await engine({ host in host == "sender.invalid" ? [loopbackPin(host)] : [] })
                    .run(target)
            }
            expect(!outcome.isSuccess, "HTTP \(code) into a private host read as success: \(outcome)")
            expect(internalHost.requests.isEmpty, "HTTP \(code): the internal host was contacted")
        }
    }

    // An HTTP status can never prove an unsubscribe took effect, so a 200 is
    // still only `requested`. This is load-bearing for the whole UI.
    Harness.test("a 200 is still only requested, never confirmed") {
        guard let origin = StubHTTPServer(respond: { _ in StubHTTPServer.ok("bye") })
        else { return expect(false, "could not start stub origin") }
        defer { origin.stop() }

        guard let target = ListUnsubscribe(
            header: "<http://sender.invalid:\(origin.port)/unsub>",
            postHeader: "List-Unsubscribe=One-Click")
        else { return expect(false, "could not parse header") }
        expect(target.supportsOneClick, "this is the one-click path")

        let outcome = runAsync { await engine({ host in [loopbackPin(host)] }).run(target) }
        guard case .requested(let detail) = outcome else {
            return expect(false, "expected requested, got \(outcome)")
        }
        expect(detail.contains("unverifiable"), "the outcome says so; got: \(detail)")
        expect(origin.requestLines.first?.hasPrefix("POST ") ?? false, "sent as a POST")
        expect(
            origin.requests.first?.contains("Content-Length: 26") ?? false,
            "carried the one-click body")
    }

    Harness.test("a sender that answers 500 falls back to its mailto target") {
        guard let origin = StubHTTPServer(respond: { _ in
            "HTTP/1.1 500 Server Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        }) else { return expect(false, "could not start stub origin") }
        defer { origin.stop() }

        guard let target = ListUnsubscribe(
            header: "<http://sender.invalid:\(origin.port)/unsub>, <mailto:off@sender.invalid>")
        else { return expect(false, "could not parse header") }

        let mailed = ResultBox<String>()
        let engine = UnsubscribeEngine(
            sendMail: { to, _, _, _ in mailed.value = to },
            client: PinnedHTTPClient(resolve: { host in [loopbackPin(host)] }))
        let outcome = runAsync { await engine.run(target) }
        expect(outcome.isSuccess, "the mailto fallback carried it; got \(outcome)")
        eq(mailed.value, "off@sender.invalid", "the fallback actually sent")
    }
}

exit(Harness.finish())
