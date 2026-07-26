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

        init(
            from: String, subjects: [String], unsubscribe: String?, oneClick: Bool = false,
            latestAgeHours: Double, cadenceHours: Double = 72, unreadFraction: Double = 0.5,
            deliveredTo: String = DemoData.address
        ) {
            self.from = from
            self.subjects = subjects
            self.unsubscribe = unsubscribe
            self.oneClick = oneClick
            self.latestAgeHours = latestAgeHours
            self.cadenceHours = cadenceHours
            self.unreadFraction = unreadFraction
            self.deliveredTo = deliveredTo
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
                        messageId: "<demo-\(uid)@example.invalid>"
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
            oneClick: true, latestAgeHours: 0.7, cadenceHours: 168, unreadFraction: 0.6),

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
            deliveredTo: "shopping@example.com"),

        Sender(
            from: "Tidewater Coffee Club <roasts@order.tidewatercoffee.com>",
            subjects: [
                "Your next box ships Thursday",
                "This month: a washed Ethiopian",
                "Rate your last bag",
            ],
            unsubscribe: "<https://tidewatercoffee.com/prefs/2201>",
            oneClick: true, latestAgeHours: 5, cadenceHours: 336, unreadFraction: 0.34,
            deliveredTo: "shopping@example.com"),

        Sender(
            from: "The Lattice <editors@thelattice.news>",
            subjects: [
                "Why the grid went down in three states",
                "The quiet consolidation of local news",
                "Weekend long read: the last switchboard operator",
                "Our most-read stories this month",
            ],
            unsubscribe: "<https://thelattice.news/unsubscribe/abc123>",
            latestAgeHours: 9, cadenceHours: 96, unreadFraction: 0.25),

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
            latestAgeHours: 14, cadenceHours: 120, unreadFraction: 1.0),

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
            oneClick: true, latestAgeHours: 20, cadenceHours: 168, unreadFraction: 0.15),

        Sender(
            from: "Meadowlark Garden Supply <hello@meadowlarkgarden.com>",
            subjects: [
                "Plant these now for a summer of colour",
                "Bare-root season starts Monday",
                "Your soil test results explained",
            ],
            unsubscribe: "<https://meadowlarkgarden.com/mail/off>",
            latestAgeHours: 26, cadenceHours: 200, unreadFraction: 0.67),

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
            oneClick: true, latestAgeHours: 33, cadenceHours: 36, unreadFraction: 0.88),

        Sender(
            from: "Ferndale Public Library <notices@ferndalelibrary.org>",
            subjects: [
                "Your hold is ready for pickup",
                "Three items due this week",
                "Author talk: Thursday at 7pm",
            ],
            unsubscribe: "<mailto:lists@ferndalelibrary.org?subject=unsubscribe>",
            latestAgeHours: 40, cadenceHours: 150, unreadFraction: 0.0),

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
            deliveredTo: "shopping@example.com"),

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
            latestAgeHours: 55, cadenceHours: 220, unreadFraction: 0.2),

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
            oneClick: true, latestAgeHours: 62, cadenceHours: 84, unreadFraction: 0.5),

        Sender(
            from: "Junction Theatre <boxoffice@junctiontheatre.org>",
            subjects: [
                "Tickets on sale: the spring season",
                "Last week to see The Longest Night",
                "A note from our artistic director",
            ],
            unsubscribe: "<https://junctiontheatre.org/email-preferences>",
            latestAgeHours: 71, cadenceHours: 260, unreadFraction: 0.34),

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
            oneClick: true, latestAgeHours: 80, cadenceHours: 48, unreadFraction: 0.72),

        Sender(
            from: "Wexford Hotels <stay@email.wexfordhotels.com>",
            subjects: [
                "Your stay is confirmed — see you Friday",
                "Member rates: up to 25% off spring stays",
                "How was your stay at Wexford Harbour?",
                "A weekend somewhere new",
            ],
            unsubscribe: "<https://wexfordhotels.com/unsubscribe/df20>",
            latestAgeHours: 96, cadenceHours: 190, unreadFraction: 0.5),

        Sender(
            from: "The Slow Signal <post@slowsignal.substack.example>",
            subjects: [
                "On writing less, and better",
                "The attention economy eats itself",
                "A field guide to quitting things",
                "What I got wrong last year",
            ],
            unsubscribe: "<https://slowsignal.substack.example/action/disable_email>",
            oneClick: true, latestAgeHours: 110, cadenceHours: 168, unreadFraction: 0.25),

        Sender(
            from: "Ridgeway Motors Service <service@ridgewaymotors.com>",
            subjects: [
                "Your service is due next month",
                "Winter tyre check — book now",
            ],
            unsubscribe: "<mailto:unsubscribe@ridgewaymotors.com>",
            latestAgeHours: 130, cadenceHours: 400, unreadFraction: 1.0),

        Sender(
            from: "Lumen Photography <hello@lumenphoto.studio>",
            subjects: [
                "Your gallery is ready to view",
                "Booking for spring is open",
                "A print sale, and why we're doing it",
            ],
            unsubscribe: nil,  // second manual-only sender
            latestAgeHours: 150, cadenceHours: 300, unreadFraction: 0.34),

        Sender(
            from: "Grangefield Charity <supporters@grangefield.org>",
            subjects: [
                "Thank you — here's what your gift did",
                "Our winter appeal is open",
                "An update from the shelter",
                "Could you give £5 this month?",
            ],
            unsubscribe: "<https://grangefield.org/email/manage>",
            latestAgeHours: 170, cadenceHours: 240, unreadFraction: 0.75),

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
            oneClick: true, latestAgeHours: 195, cadenceHours: 30, unreadFraction: 0.89),
    ]
}
