import Foundation

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

        public var id: String { groupKey }

        public init(groupKey: String, senderName: String, senderEmail: String, reason: String) {
            self.groupKey = groupKey
            self.senderName = senderName
            self.senderEmail = senderEmail
            self.reason = reason
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
}
