import Foundation

/// A named way of filling the selection from what is already on screen.
///
/// The core loop is one sender at a time, which is right when the answer is
/// uncertain and wrong when it is obvious: a sender with forty messages and
/// nothing ever opened does not need thinking about individually.
///
/// **A smart selection selects. It never acts.** It fills `selection` with rows
/// the user is already looking at and stops; the user reviews the list and
/// presses the button, and the button asks for confirmation exactly as it does
/// for a hand-made selection. There is deliberately no "clean my inbox" here —
/// every rule below is a description of senders, not an instruction to do
/// anything to them.
///
/// Lives in the kit rather than the app because every rule is a predicate over
/// numbers the sync already stored — no store, no backend, no UI — and a
/// predicate that decides what forty live unsubscribe requests will be aimed at
/// is exactly the kind of thing that should be testable without a window.
public enum SmartSelection: String, CaseIterable, Identifiable, Sendable {
    /// Nothing in the group has ever been read.
    case neverOpened
    /// A high-volume sender read almost never.
    case rarelyOpened
    /// Nothing has arrived from them in a year.
    case dormant
    /// Every one can be finished by the app alone, with no browser.
    case oneClick

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .neverOpened: "Never Opened"
        case .rarelyOpened: "Rarely Opened"
        case .dormant: "Nothing in a Year"
        case .oneClick: "One-Click Capable"
        }
    }

    /// The rule, in the user's terms. Shown as the menu item's help — a
    /// selection whose rule you can't read is one you can't check the result of.
    public var help: String {
        switch self {
        case .neverOpened:
            "Senders with at least \(SmartSelection.minimumVolume) messages, none of them ever opened."
        case .rarelyOpened:
            "Senders with at least \(SmartSelection.highVolume) messages, fewer than \(SmartSelection.rarelyReadPercent)% of them opened."
        case .dormant:
            "Senders who haven't sent anything in the last year."
        case .oneClick:
            "Senders the app can unsubscribe from on its own, with no browser."
        }
    }

    // MARK: - Thresholds

    /// The floor under "never opened".
    ///
    /// The task's starting set said simply "0% read". Taken literally that also
    /// selects every sender who has mailed once and not been read yet, which
    /// after a first sync is most of the mailbox — a fact about how new the
    /// sync is, not evidence that the mail is unwanted. Three messages is the
    /// smallest number where "you have never opened one of these" is a claim
    /// about the user's behaviour rather than about the calendar.
    public static let minimumVolume = 3

    /// The volume above which "rarely opened" becomes evidence. The same
    /// reasoning as above, one step further: 1 read out of 12 is a habit, 0 read
    /// out of 4 is a fortnight.
    public static let highVolume = 10

    /// "Rarely" — under a tenth opened.
    public static let rarelyReadPercent = 10.0

    /// How long silence has to last to count as dormant.
    public static let dormantDays = 365

    /// The most rows one smart selection will fill in.
    ///
    /// Not a performance limit — the same reasoning the agent proposals were
    /// capped at 25 for. The safety mechanism in this app is that a human looks
    /// at the list before pressing the button, and "400 selected" is not
    /// something anyone looks at; it is a number they trust. Fifty is roughly
    /// what a person will actually scroll through, and the remainder is not
    /// lost — running the same selection again after acting picks up the next
    /// fifty.
    public static let maxSelected = 50
}

/// One row, as the smart-selection rules see it.
///
/// Every field is already stored: the counts and read flags come from the
/// header sync, and one-click capability is decided by the RFC 8058 token in
/// the `List-Unsubscribe-Post` header. Nothing here requires a network call.
public struct SmartSelectionCandidate: Hashable, Sendable {
    public let id: GroupID
    /// Carried so the rules can refuse a sender who isn't in the collection on
    /// screen — see `SmartSelection.select(from:in:)`.
    public let state: SenderState
    public let messageCount: Int
    /// Percentage of the group still unread, 0…100 — the same figure the table
    /// column shows. "Read" is its complement.
    public let unreadPercent: Double
    public let lastReceived: Date
    /// The sender published an RFC 8058 one-click target, so a whole batch of
    /// these can finish without a browser.
    public let isOneClick: Bool

    public init(
        id: GroupID,
        state: SenderState,
        messageCount: Int,
        unreadPercent: Double,
        lastReceived: Date,
        isOneClick: Bool
    ) {
        self.id = id
        self.state = state
        self.messageCount = messageCount
        self.unreadPercent = unreadPercent
        self.lastReceived = lastReceived
        self.isOneClick = isOneClick
    }
}

/// What one smart selection came to.
public struct SmartSelectionResult: Hashable, Sendable {
    /// The rows to select, in the order they were given — display order, so the
    /// user reviews them where they already are.
    public let ids: [GroupID]
    /// How many matched before the cap. Never smaller than `ids.count`.
    public let matched: Int
    public let rule: SmartSelection

    public init(ids: [GroupID], matched: Int, rule: SmartSelection) {
        self.ids = ids
        self.matched = matched
        self.rule = rule
    }

    public var wasCapped: Bool { matched > ids.count }

    /// What to tell the user, in one line. States the rule and the cap, because
    /// a selection that quietly stopped at fifty of three hundred would read as
    /// "that's all of them" — and the next action is aimed at exactly this list.
    public var summary: String {
        guard !ids.isEmpty else { return "No senders here match “\(rule.title)”." }
        let selected = "Selected \(ids.count) sender\(ids.count == 1 ? "" : "s")"
        if wasCapped {
            return
                "\(selected) — the first \(ids.count) of \(matched) matching “\(rule.title)”. Review them, act, then run it again for the rest."
        }
        return "\(selected) matching “\(rule.title)”. Review before acting."
    }
}

extension SmartSelection {
    /// Whether one sender matches this rule, ignoring the collection.
    public func matches(_ candidate: SmartSelectionCandidate, now: Date = Date()) -> Bool {
        switch self {
        case .neverOpened:
            return candidate.messageCount >= SmartSelection.minimumVolume
                && candidate.unreadPercent >= 100
        case .rarelyOpened:
            let readPercent = 100 - candidate.unreadPercent
            return candidate.messageCount >= SmartSelection.highVolume
                && readPercent < SmartSelection.rarelyReadPercent
        case .dormant:
            guard
                let cutoff = Calendar.current.date(
                    byAdding: .day, value: -SmartSelection.dormantDays, to: now)
            else { return false }
            return candidate.lastReceived < cutoff
        case .oneClick:
            return candidate.isOneClick
        }
    }

    /// Fill a selection from the rows on screen.
    ///
    /// `candidates` must already be the visible list in display order, and the
    /// collection is checked again here regardless: a smart selection run in
    /// Ignored that returned senders who aren't ignored would put rows in
    /// `selection` that the list does not show, which is the invariant the
    /// collection switch and the search field both exist to maintain.
    public func select(
        from candidates: [SmartSelectionCandidate],
        in collection: SenderCollection,
        now: Date = Date(),
        limit: Int = SmartSelection.maxSelected
    ) -> SmartSelectionResult {
        let matching = candidates.filter {
            collection.contains($0.state) && matches($0, now: now)
        }
        return SmartSelectionResult(
            ids: Array(matching.prefix(max(limit, 0)).map(\.id)),
            matched: matching.count,
            rule: self)
    }
}
