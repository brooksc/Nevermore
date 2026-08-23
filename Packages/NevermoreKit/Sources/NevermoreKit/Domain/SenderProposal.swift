import Foundation

/// What the agent means should happen to a sender (TASK-52).
///
/// A proposal used to carry only prose, and prose cannot override a button: an
/// agent that wrote "IGNORE, do not unsubscribe" was proposing into a row whose
/// primary action was Unsubscribe and whose habitual keystroke is `u`, and both
/// senders were unsubscribed before anyone read the sentence. The recommendation
/// has to be data the row can act on, so this is the field the row leads with.
///
/// Three cases and no more, because these are the three things the app can
/// actually do to a sender. There is no `none`: an agent that has looked at a
/// sender closely enough to propose it has an opinion, and "no opinion" would be
/// read as the default, which is how this went wrong the first time.
public enum RecommendedAction: String, Codable, Sendable, Hashable, CaseIterable {
    /// Worth telling the sender to stop. Only for a genuine recurring
    /// subscription: the request confirms a live, read address, and that
    /// exposure only pays for itself against mail that keeps coming.
    case unsubscribe
    /// Hide the sender here and tell them nothing. The safe answer for cold
    /// outreach and one-off senders.
    case ignore
    /// Clear the mail out, and still tell them nothing.
    case trash

    /// The button, in the app's existing words for these actions.
    public var buttonTitle: String {
        switch self {
        case .unsubscribe: "Unsubscribe"
        case .ignore: "Ignore"
        case .trash: "Trash Messages"
        }
    }

    /// The badge at the head of the row.
    public var badgeTitle: String {
        switch self {
        case .unsubscribe: "Unsubscribe"
        case .ignore: "Ignore"
        case .trash: "Trash"
        }
    }

    public var symbolName: String {
        switch self {
        case .unsubscribe: "envelope.open"
        case .ignore: "eye.slash"
        case .trash: "trash"
        }
    }

    /// Why an agent would pick this one, in the words the tool description and
    /// the override warning both use.
    public var guidance: String {
        switch self {
        case .unsubscribe:
            "a genuine recurring subscription the sender will honour a request from"
        case .ignore:
            "cold outreach, a one-off sender, or anyone an unsubscribe would only "
                + "confirm a live address to"
        case .trash:
            "the same as ignore, plus the mail already sitting in the mailbox is not "
                + "worth keeping"
        }
    }

    /// Every value, for a refusal that has to say what it would have accepted.
    public static var namesSentence: String {
        allCases.map(\.rawValue).joined(separator: ", ")
    }
}

/// A set of senders an external agent has put forward, waiting for a human to
/// look at it.
///
/// This is the review step the whole MCP feature rests on: the agent classifies,
/// the human actuates, and a proposal is the only thing that crosses between
/// them. So it is a value, storable and testable without a server or a UI —
/// nothing about reviewing a proposal should depend on how it arrived.
///
/// Self-contained, in the same way `MessageStore.UnsubscribeRecord` is: each
/// item carries the sender's name and address rather than only a group key. A
/// proposal outlives the state it was made against — the agent's session and
/// the review session are hours apart, and in between a sync can land, mail can
/// be trashed, and a group can be split or merged. A row whose sender has gone
/// must still be reviewable, and must still say who it was about.
public struct SenderProposal: Codable, Sendable, Hashable, Identifiable {
    /// One proposed sender, and the agent's stated reason for proposing it.
    public struct Item: Codable, Sendable, Hashable, Identifiable {
        /// `GroupID.storageKey` of the sender, as grouping stood when the
        /// proposal was made.
        public let groupKey: String
        public let senderName: String
        public let senderEmail: String
        /// One line, in the agent's words. Shown in the table, never parsed:
        /// this is the only thing that makes the agent's judgement checkable,
        /// and a reason the app rewrote would be the app's judgement, not the
        /// agent's.
        public let reason: String
        /// What the agent means should happen to this sender. The row leads
        /// with it, and an unsubscribe that contradicts it has to be confirmed.
        public let recommendation: RecommendedAction

        public var id: String { groupKey }

        public init(
            groupKey: String, senderName: String, senderEmail: String, reason: String,
            recommendation: RecommendedAction = .unsubscribe
        ) {
            self.groupKey = groupKey
            self.senderName = senderName
            self.senderEmail = senderEmail
            self.reason = reason
            self.recommendation = recommendation
        }

        enum CodingKeys: String, CodingKey {
            case groupKey, senderName, senderEmail, reason, recommendation
        }

        /// Hand-written for one reason: a proposal stored before recommendations
        /// existed has no such key, and it should reappear on the next launch
        /// rather than fail to decode and take the whole review with it.
        /// `.unsubscribe` is what those rows already meant — the difference is
        /// that the row now says so out loud instead of implying it.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            groupKey = try c.decode(String.self, forKey: .groupKey)
            senderName = try c.decode(String.self, forKey: .senderName)
            senderEmail = try c.decode(String.self, forKey: .senderEmail)
            reason = try c.decode(String.self, forKey: .reason)
            recommendation =
                try c.decodeIfPresent(RecommendedAction.self, forKey: .recommendation)
                ?? .unsubscribe
        }
    }

    public let id: UUID
    public let createdAt: Date
    /// What the agent says this proposal is, in one line ("senders from the
    /// 2026 job search"). Optional: an agent that offers nothing gets a
    /// generic banner rather than an invented summary.
    public let summary: String?
    /// In the agent's order, deliberately. It ranked them; re-sorting would
    /// discard information the human is being asked to review.
    public let items: [Item]

    public init(
        id: UUID = UUID(), createdAt: Date = Date(), summary: String? = nil, items: [Item]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.summary = summary
        self.items = items
    }

    /// The most senders one proposal may hold.
    ///
    /// Reviewability *is* the safety mechanism (TASK-41), so an unreviewable
    /// proposal is a broken one rather than a large one. Twenty-five is what
    /// fits on screen and what a person will actually read to the end of.
    public static let maxItems = 25

    /// Trim to `maxItems`, reporting what was dropped.
    ///
    /// Truncating silently would be the worst of both: the agent believes three
    /// hundred senders are under review and the human sees twenty-five. The
    /// count is returned so the caller can tell the agent it was cut — which is
    /// TASK-46's job, not this type's.
    public static func capped(
        summary: String? = nil, items: [Item], id: UUID = UUID(), createdAt: Date = Date()
    ) -> (proposal: SenderProposal, dropped: Int) {
        // Two items for one sender are one row that can only be reviewed once;
        // the first mention wins, and dedupe happens before the cap so the cap
        // counts senders rather than mentions.
        var seen = Set<String>()
        let unique = items.filter { seen.insert($0.groupKey).inserted }
        let kept = Array(unique.prefix(maxItems))
        return (
            SenderProposal(id: id, createdAt: createdAt, summary: summary, items: kept),
            unique.count - kept.count
        )
    }

    /// The proposal without these senders, or nil once nothing is left.
    ///
    /// Nil rather than an empty proposal because an empty proposal is not a
    /// thing the user should be looking at: the sidebar row exists only while
    /// there is something to review, so removing the last row must clear the
    /// whole proposal rather than leave an empty list behind.
    public func removing(groupKeys: Set<String>) -> SenderProposal? {
        let kept = items.filter { !groupKeys.contains($0.groupKey) }
        guard !kept.isEmpty else { return nil }
        return SenderProposal(id: id, createdAt: createdAt, summary: summary, items: kept)
    }
}

/// One row of the Proposed collection: what the agent said, joined to the
/// sender as they stand now.
public struct ProposedSender: Identifiable, Sendable {
    public let id: GroupID
    public let item: SenderProposal.Item
    /// Nil when the sender has no messages left — trashed since the proposal
    /// was made, or regrouped under a different key. The row stays: the human
    /// is reviewing the agent's judgement, and a row that silently vanished
    /// would make the proposal they see disagree with the one the agent sent.
    public let group: SenderGroup?

    public init(id: GroupID, item: SenderProposal.Item, group: SenderGroup?) {
        self.id = id
        self.item = item
        self.group = group
    }
}

extension SenderProposal {
    /// The proposal's rows against the current grouping, in the agent's order.
    ///
    /// `query` is the app's search field, which stays visible on every
    /// collection and so has to work here too. It matches the sender *and* the
    /// reason — "why did it pick these" is the question this list exists to
    /// answer, so the reason is searchable text, not decoration.
    public func senders(in groups: [SenderGroup], matching query: String = "") -> [ProposedSender] {
        let byKey = Dictionary(groups.map { ($0.id.storageKey, $0) }, uniquingKeysWith: { a, _ in a })
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return items.compactMap { item in
            guard let id = GroupID(storageKey: item.groupKey) else { return nil }
            if !q.isEmpty {
                let haystack = [item.senderName, item.senderEmail, item.reason]
                guard haystack.contains(where: { $0.lowercased().contains(q) }) else { return nil }
            }
            return ProposedSender(id: id, item: item, group: byKey[item.groupKey])
        }
    }

    /// The proposed senders among `groupKeys` the agent recommended something
    /// other than `action` for.
    ///
    /// The whole override check, and it lives here rather than in the app so it
    /// can be held to it: an unsubscribe started from Proposed asks this first,
    /// and a non-empty answer is a confirmation the user has to read.
    public func items(contradicting action: RecommendedAction, in groupKeys: Set<String>) -> [Item] {
        items.filter { groupKeys.contains($0.groupKey) && $0.recommendation != action }
    }
}

/// What the user is asked when they unsubscribe from a sender the agent said not
/// to (TASK-52).
///
/// The copy is here, next to the rule, because it is the feature: the dialog has
/// to name the senders and repeat the agent's own reason, or it is a speed bump
/// that teaches nothing and gets clicked through. It never blocks — overriding is
/// a legitimate answer, and the agent is often wrong — it only makes the
/// override a decision rather than the second half of a habitual keystroke.
public enum ProposalOverrideWarning {
    public static let confirmTitle = "Unsubscribe Anyway"

    /// The part that is true whoever objected, so `UnsubscribeExposureWarning`
    /// can say it once rather than keeping a second copy of it (TASK-30).
    public static let closingParagraph =
        "Unsubscribing tells the sender the address is live and read, which cannot be "
        + "taken back. Their recommendation is still one keystroke away in the row."

    public static func title(count: Int) -> String {
        count == 1
            ? "The agent recommended against unsubscribing from this sender"
            : "The agent recommended against unsubscribing from \(count) of these senders"
    }

    /// Names every sender, what the agent asked for instead, and why — verbatim,
    /// because a reason the app paraphrased would be the app's judgement.
    public static func message(for items: [SenderProposal.Item]) -> String {
        let lines = items.map { item in
            "\(item.senderName) — recommended: \(item.recommendation.badgeTitle). \(item.reason)"
        }
        return (lines + [closingParagraph]).joined(separator: "\n\n")
    }
}
