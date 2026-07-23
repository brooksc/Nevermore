import Foundation
import MailScrubKit

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
    Harness.test("applies user overrides ahead of the registrable domain") {
        eq(
            Grouping(overrides: ["weird-cdn.net": "mybrand.com"]).group([
                msg(1, from: "Brand <a@weird-cdn.net>"),
                msg(2, from: "Brand <b@mybrand.com>"),
            ]).count, 1)
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

exit(Harness.finish())
