import Foundation

/// A fabricated mailbox for the demo mode and for product screenshots.
///
/// Built from real header *strings* rather than hand-constructed domain values,
/// so it runs through the same `EmailSender` and `ListUnsubscribe` parsers as
/// live mail. A demo that bypassed the parsers could show a layout the real app
/// can't actually produce.
///
/// Dates are relative to a supplied `now`, so the list always looks freshly
/// synced no matter when a screenshot is taken.
public enum DemoData {
    /// The address the demo mailbox pretends to belong to.
    public static let address = "you@example.com"

    /// Aliases the demo account can "send as" — enough to show the
    /// delivered-to line in the inspector.
    public static let sendAsAddresses = [address, "shopping@example.com"]

    /// One sender's worth of demo mail.
    private struct Sender {
        let from: String
        let subjects: [String]
        /// `List-Unsubscribe` header, or nil for a sender that publishes none
        /// (which is what drives the "manual only" state).
        let unsubscribe: String?
        /// Whether the sender advertises RFC 8058 one-click.
        let oneClick: Bool
        /// Hours since `now` for the most recent message.
        let latestAgeHours: Double
        /// Average gap between messages, in hours.
        let cadenceHours: Double
        /// Fraction of messages left unread, 0...1.
        let unreadFraction: Double
        /// Which alias the mail was delivered to.
        let deliveredTo: String
        /// RFC 2919 List-ID, for senders that are actually mailing lists.
        let listID: String?
        /// Typical `RFC822.SIZE` for one of this sender's messages, in bytes.
        ///
        /// Deliberately spread over two orders of magnitude: an image-heavy
        /// retail blast is megabytes and a plain-text newsletter is tens of
        /// kilobytes, and a demo where every sender cost the same would make
        /// the storage column look like decoration.
        let bytesPerMessage: Int
        /// How many of this sender's oldest messages have no size on file.
        ///
        /// Not padding. This is what a real mailbox looks like the day after
        /// the feature ships — messages synced earlier were stored before sizes
        /// were kept — and the demo should show the "at least" total rather than
        /// pretend every sender is fully measured.
        let unsizedOldest: Int

        init(
            from: String, subjects: [String], unsubscribe: String?, oneClick: Bool = false,
            latestAgeHours: Double, cadenceHours: Double = 72, unreadFraction: Double = 0.5,
            deliveredTo: String = DemoData.address, listID: String? = nil,
            bytesPerMessage: Int = 48_000, unsizedOldest: Int = 0
        ) {
            self.bytesPerMessage = bytesPerMessage
            self.unsizedOldest = unsizedOldest
            self.from = from
            self.subjects = subjects
            self.unsubscribe = unsubscribe
            self.oneClick = oneClick
            self.latestAgeHours = latestAgeHours
            self.cadenceHours = cadenceHours
            self.unreadFraction = unreadFraction
            self.deliveredTo = deliveredTo
            self.listID = listID
        }
    }

    /// Every demo message, newest first.
    ///
    /// Fictional brands throughout: shipping real companies' names in
    /// screenshots implies an endorsement (or an accusation) that isn't ours to
    /// make, and a demo that says "unsubscribe from <real brand>" invites
    /// exactly the wrong reading.
    public static func messages(now: Date = Date()) -> [EmailMessage] {
        var uid: UInt32 = 1000
        var out: [EmailMessage] = []

        for sender in senders {
            let parsed = EmailSender(header: sender.from)
            let unsub = ListUnsubscribe(
                header: sender.unsubscribe,
                postHeader: sender.oneClick ? "List-Unsubscribe=One-Click" : nil)

            for (index, subject) in sender.subjects.enumerated() {
                uid += 1
                let ageHours = sender.latestAgeHours + Double(index) * sender.cadenceHours
                // Deterministic unread pattern: the first N of each sender's
                // messages are unread. Avoids randomness, which would make
                // screenshots differ run to run.
                let unreadCount = Int((Double(sender.subjects.count) * sender.unreadFraction).rounded())
                out.append(
                    EmailMessage(
                        uid: MessageUID(uid),
                        sender: parsed,
                        subject: subject,
                        receivedAt: now.addingTimeInterval(-ageHours * 3600),
                        isUnread: index < unreadCount,
                        unsubscribe: unsub,
                        deliveredTo: sender.deliveredTo,
                        messageId: "<demo-\(uid)@example.invalid>",
                        listID: sender.listID,
                        // Deterministic spread around the sender's typical size,
                        // for the same reason the unread pattern is
                        // deterministic: a screenshot must not change run to
                        // run. `subjects` is newest-first, so the last
                        // `unsizedOldest` of them are the ones left unmeasured.
                        byteSize: index >= sender.subjects.count - sender.unsizedOldest
                            ? nil
                            : sender.bytesPerMessage + (index % 5) * (sender.bytesPerMessage / 8)
                    ))
            }
        }
        return out.sorted { $0.receivedAt > $1.receivedAt }
    }

    // MARK: - The cast

    private static let senders: [Sender] = [
        Sender(
            from: "Vellum Weekly <hello@news.vellumreads.com>",
            subjects: [
                "The five books our editors argued about most",
                "A short history of the paperback",
                "What we're reading in the shortest month",
                "Your Tuesday reading list",
                "The case for finishing bad books",
            ],
            unsubscribe: "<https://vellumreads.com/u/9f2a>, <mailto:unsub@vellumreads.com?subject=unsubscribe>",
            oneClick: true, latestAgeHours: 0.7, cadenceHours: 168, unreadFraction: 0.6,
            bytesPerMessage: 90_000),

        Sender(
            from: "Northbound Outfitters <deals@mail.northboundgear.com>",
            subjects: [
                "48 hours only: 40% off everything for the trail",
                "New arrivals — the winter shell you asked for",
                "Your cart is waiting (and so is free shipping)",
                "Last chance: the sale ends tonight",
                "Members get early access to the spring range",
                "We restocked your size",
            ],
            unsubscribe: "<https://northboundgear.com/email/unsubscribe?t=8812>",
            oneClick: true, latestAgeHours: 2.5, cadenceHours: 40, unreadFraction: 0.83,
            deliveredTo: "shopping@example.com", bytesPerMessage: 2_400_000),

        Sender(
            from: "Tidewater Coffee Club <roasts@order.tidewatercoffee.com>",
            subjects: [
                "Your next box ships Thursday",
                "This month: a washed Ethiopian",
                "Rate your last bag",
            ],
            unsubscribe: "<https://tidewatercoffee.com/prefs/2201>",
            oneClick: true, latestAgeHours: 5, cadenceHours: 336, unreadFraction: 0.34,
            deliveredTo: "shopping@example.com", bytesPerMessage: 480_000),

        Sender(
            from: "The Lattice <editors@thelattice.news>",
            subjects: [
                "Why the grid went down in three states",
                "The quiet consolidation of local news",
                "Weekend long read: the last switchboard operator",
                "Our most-read stories this month",
            ],
            unsubscribe: "<https://thelattice.news/unsubscribe/abc123>",
            latestAgeHours: 9, cadenceHours: 96, unreadFraction: 0.25, bytesPerMessage: 60_000),

        Sender(
            from: "Harbourview Fitness <noreply@harbourviewfit.com>",
            subjects: [
                "You haven't checked in for a while",
                "New classes added for the new year",
                "Your membership renews on the 1st",
                "Bring a friend for free this weekend",
                "We miss you at the 6am class",
            ],
            unsubscribe: "<mailto:unsubscribe@harbourviewfit.com?subject=Unsubscribe%20me>",
            latestAgeHours: 14, cadenceHours: 120, unreadFraction: 1.0, bytesPerMessage: 310_000),

        Sender(
            from: "Pixel & Press <studio@pixelandpress.co>",
            subjects: [
                "Issue 84: the typography of train tickets",
                "Issue 83: what a good error message does",
                "Issue 82: designing for the tired user",
                "Issue 81: the return of the sidebar",
                "Issue 80: eighty issues, one lesson",
                "Issue 79: colour on cheap screens",
                "Issue 78: the anatomy of a receipt",
            ],
            unsubscribe: "<https://pixelandpress.co/u/aa71>, <mailto:leave@pixelandpress.co>",
            oneClick: true, latestAgeHours: 20, cadenceHours: 168, unreadFraction: 0.15,
            bytesPerMessage: 55_000, unsizedOldest: 2),

        Sender(
            from: "Meadowlark Garden Supply <hello@meadowlarkgarden.com>",
            subjects: [
                "Plant these now for a summer of colour",
                "Bare-root season starts Monday",
                "Your soil test results explained",
            ],
            unsubscribe: "<https://meadowlarkgarden.com/mail/off>",
            latestAgeHours: 26, cadenceHours: 200, unreadFraction: 0.67, bytesPerMessage: 700_000),

        Sender(
            from: "Cadence Running Co. <team@e.cadencerunning.com>",
            subjects: [
                "The shoe you loved, now in three new colours",
                "Train for a spring half — 12 week plan inside",
                "Your race photos are ready",
                "Free returns extended through January",
                "Restock alert: your size is back",
                "An extra 20% off clearance",
                "Join the Sunday long run",
                "The gear our team actually uses",
            ],
            unsubscribe: "<https://cadencerunning.com/unsub?u=5510>",
            oneClick: true, latestAgeHours: 33, cadenceHours: 36, unreadFraction: 0.88,
            bytesPerMessage: 1_900_000, unsizedOldest: 3),

        Sender(
            from: "Ferndale Public Library <notices@ferndalelibrary.org>",
            subjects: [
                "Your hold is ready for pickup",
                "Three items due this week",
                "Author talk: Thursday at 7pm",
            ],
            unsubscribe: "<mailto:lists@ferndalelibrary.org?subject=unsubscribe>",
            latestAgeHours: 40, cadenceHours: 150, unreadFraction: 0.0,
            listID: "notices.ferndalelibrary.org", bytesPerMessage: 18_000),

        Sender(
            from: "Sable & Finch <hello@sableandfinch.com>",
            subjects: [
                "The linen edit has landed",
                "Our first-ever archive sale",
                "You left something behind",
                "Now in stock: the everyday coat",
            ],
            unsubscribe: nil,  // publishes nothing — demonstrates "manual only"
            latestAgeHours: 47, cadenceHours: 90, unreadFraction: 0.75,
            deliveredTo: "shopping@example.com", bytesPerMessage: 1_600_000),

        Sender(
            from: "Orchard Software Updates <updates@mail.orchardsoftware.io>",
            subjects: [
                "Orchard 4.2 is out — what's new",
                "Scheduled maintenance this Sunday",
                "Your plan renews next month",
                "Security advisory: please update",
                "New: shared workspaces",
            ],
            unsubscribe: "<https://orchardsoftware.io/notifications>",
            latestAgeHours: 55, cadenceHours: 220, unreadFraction: 0.2, bytesPerMessage: 22_000),

        Sender(
            from: "Copperline Kitchen <recipes@copperlinekitchen.com>",
            subjects: [
                "A one-pan dinner for a cold night",
                "The only pancake recipe you need",
                "Six things to do with a lemon",
                "Sunday baking: a very forgiving loaf",
                "Reader favourites from this year",
                "What to cook when you can't be bothered",
            ],
            unsubscribe: "<https://copperlinekitchen.com/u/77c1>",
            oneClick: true, latestAgeHours: 62, cadenceHours: 84, unreadFraction: 0.5,
            bytesPerMessage: 620_000),

        Sender(
            from: "Junction Theatre <boxoffice@junctiontheatre.org>",
            subjects: [
                "Tickets on sale: the spring season",
                "Last week to see The Longest Night",
                "A note from our artistic director",
            ],
            unsubscribe: "<https://junctiontheatre.org/email-preferences>",
            latestAgeHours: 71, cadenceHours: 260, unreadFraction: 0.34, bytesPerMessage: 300_000),

        Sender(
            from: "Brightpath Careers <alerts@brightpathcareers.com>",
            subjects: [
                "9 new roles matching “product designer”",
                "Your weekly job digest",
                "A recruiter viewed your profile",
                "12 new roles matching “product designer”",
                "Salary trends in your field",
                "Your weekly job digest",
                "Three companies are hiring near you",
            ],
            unsubscribe: "<https://brightpathcareers.com/settings/email>, <mailto:stop@brightpathcareers.com>",
            oneClick: true, latestAgeHours: 80, cadenceHours: 48, unreadFraction: 0.72,
            bytesPerMessage: 140_000),

        Sender(
            from: "Wexford Hotels <stay@email.wexfordhotels.com>",
            subjects: [
                "Your stay is confirmed — see you Friday",
                "Member rates: up to 25% off spring stays",
                "How was your stay at Wexford Harbour?",
                "A weekend somewhere new",
            ],
            unsubscribe: "<https://wexfordhotels.com/unsubscribe/df20>",
            latestAgeHours: 96, cadenceHours: 190, unreadFraction: 0.5, bytesPerMessage: 900_000),

        Sender(
            from: "The Slow Signal <post@slowsignal.substack.example>",
            subjects: [
                "On writing less, and better",
                "The attention economy eats itself",
                "A field guide to quitting things",
                "What I got wrong last year",
            ],
            unsubscribe: "<https://slowsignal.substack.example/action/disable_email>",
            oneClick: true, latestAgeHours: 110, cadenceHours: 168, unreadFraction: 0.25,
            bytesPerMessage: 40_000),

        Sender(
            from: "Ridgeway Motors Service <service@ridgewaymotors.com>",
            subjects: [
                "Your service is due next month",
                "Winter tyre check — book now",
            ],
            unsubscribe: "<mailto:unsubscribe@ridgewaymotors.com>",
            latestAgeHours: 130, cadenceHours: 400, unreadFraction: 1.0, bytesPerMessage: 30_000),

        Sender(
            from: "Lumen Photography <hello@lumenphoto.studio>",
            subjects: [
                "Your gallery is ready to view",
                "Booking for spring is open",
                "A print sale, and why we're doing it",
            ],
            unsubscribe: nil,  // second manual-only sender
            latestAgeHours: 150, cadenceHours: 300, unreadFraction: 0.34,
            bytesPerMessage: 3_100_000),

        Sender(
            from: "Grangefield Charity <supporters@grangefield.org>",
            subjects: [
                "Thank you — here's what your gift did",
                "Our winter appeal is open",
                "An update from the shelter",
                "Could you give £5 this month?",
            ],
            unsubscribe: "<https://grangefield.org/email/manage>",
            latestAgeHours: 170, cadenceHours: 240, unreadFraction: 0.75, bytesPerMessage: 210_000),

        Sender(
            from: "Halcyon Travel Deals <deals@halcyontravel.example>",
            subjects: [
                "Error fare: £180 return to Lisbon",
                "This week's cheapest long-haul",
                "Your saved route just dropped in price",
                "Five city breaks under £200",
                "Flash sale: 36 hours only",
                "Deals from your home airport",
                "Where to go in shoulder season",
                "Your weekly deal digest",
                "Last call: the sale ends at midnight",
            ],
            unsubscribe: "<https://halcyontravel.example/u/2f8b>",
            oneClick: true, latestAgeHours: 195, cadenceHours: 30, unreadFraction: 0.89,
            bytesPerMessage: 1_150_000, unsizedOldest: 4),
    ]

    // MARK: - Unsubscribes the demo has already made

    /// One unsubscribe the demo pretends you made earlier, expressed the same
    /// way the app records a real one.
    public struct PriorUnsubscribe: Sendable {
        /// Matched against the sender address in `senders`.
        public let senderEmail: String
        /// How long ago the attempt was recorded. Whether the sender lands in
        /// **Reappeared** or stays quietly in **Unsubscribed** is decided by
        /// this against their newest message — the app's own test, not a flag.
        public let attemptedAgeHours: Double
        public let outcome: String
    }

    /// One record the demo should write, already matched to a real group.
    public struct PlannedUnsubscribe: Sendable {
        public let groupID: GroupID
        public let senderName: String
        public let senderEmail: String
        public let senderDomain: String
        public let url: String?
        public let outcome: String
        public let attemptedAt: Date
    }

    /// Match `priorUnsubscribes` against real groups and say what to write.
    ///
    /// Deliberately pure, and deliberately here rather than in the app: the app
    /// target is an executable, so anything living there cannot be imported by
    /// the tests. The rule that decides whether the demo shows a reappearance
    /// is worth testing — a regression is silent, since the collection simply
    /// goes back to being empty, which is the bug this fixed in the first
    /// place.
    public static func plannedUnsubscribes(
        for groups: [SenderGroup], now: Date = Date()
    ) -> [PlannedUnsubscribe] {
        priorUnsubscribes.compactMap { prior in
            guard
                let group = groups.first(where: {
                    $0.messages.contains {
                        $0.sender.address.caseInsensitiveCompare(prior.senderEmail) == .orderedSame
                    }
                })
            else { return nil }
            let source = group.messages.first
            return PlannedUnsubscribe(
                groupID: group.id,
                senderName: group.displayName,
                senderEmail: source?.sender.address ?? group.id.key,
                senderDomain: source?.sender.host ?? "",
                url: source?.unsubscribe?.webTargets.first?.absoluteString,
                outcome: prior.outcome,
                attemptedAt: now.addingTimeInterval(-prior.attemptedAgeHours * 3600))
        }
    }

    /// Without these, demo mode can never show Reappeared — the one behaviour
    /// the app is named for, and the thing that distinguishes it from a service
    /// that unsubscribes and hopes. Anyone seeing the app for the first time
    /// through the demo, including an App Review reviewer, would miss it.
    ///
    /// Two senders kept mailing after being asked to stop, and two honoured it.
    /// The contrast is the point: "Reappeared" only means something next to
    /// senders who behaved.
    public static let priorUnsubscribes: [PriorUnsubscribe] = [
        // Newest mail 2.5h old against a 7-day-old request: a deals list that
        // simply carried on.
        PriorUnsubscribe(
            senderEmail: "deals@mail.northboundgear.com", attemptedAgeHours: 168,
            outcome: "requested"),
        // Confirmed on a real confirmation page, and still mailing 33h ago.
        // The unflattering case the app exists to catch: even "confirmed"
        // proves nothing.
        PriorUnsubscribe(
            senderEmail: "team@e.cadencerunning.com", attemptedAgeHours: 120,
            outcome: "confirmed"),
        // Asked yesterday, nothing since — these two are what success looks
        // like, and they stay out of Reappeared.
        PriorUnsubscribe(
            senderEmail: "service@ridgewaymotors.com", attemptedAgeHours: 24,
            outcome: "requested"),
        PriorUnsubscribe(
            senderEmail: "hello@lumenphoto.studio", attemptedAgeHours: 24,
            outcome: "confirmed"),
    ]
}
