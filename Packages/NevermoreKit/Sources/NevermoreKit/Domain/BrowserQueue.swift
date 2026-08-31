import Foundation

/// Why one sender cannot be finished without a person in a browser.
///
/// Every case is decided from what is already stored — the parsed
/// `List-Unsubscribe` header, the unsubscribe record, and which addresses this
/// account can send as. None of them requires attempting anything, which is the
/// property TASK-47 rests on: an agent that has just triaged four hundred
/// senders can hand over the thirty that need a browser as a set, rather than
/// discovering them one failure at a time.
public enum BrowserReason: String, Codable, Sendable, Hashable, CaseIterable {
    /// The sender published no machine-readable target at all, so there is
    /// nothing for the engine to send.
    ///
    /// The raw values are snake_case because they are both the stored form and
    /// what an agent reads off the wire, where every other value is.
    case noPublishedTarget = "no_published_target"
    /// An unsubscribe was already recorded and they kept mailing. The automated
    /// path has been tried and did not work.
    case ignoredAnUnsubscribe = "ignored_an_unsubscribe"
    /// A bare `mailto:` that identifies you only by who the mail comes from,
    /// delivered to an alias this account cannot send as. Sending it anyway
    /// would go out from the wrong identity and be quietly ignored — the app
    /// already refuses to do that (`AppModel.performUnsubscribe`).
    case wrongDeliveryAddress = "wrong_delivery_address"
    /// The automated request went out in this run and the sender's server
    /// refused it. Unlike the other three this one is not decidable in advance —
    /// it is what a finished run knows and nothing else does, which is why the
    /// results sheet is the only thing that queues it.
    case automatedAttemptFailed = "automated_attempt_failed"

    /// One line, in the words the user and the agent both read.
    public var explanation: String {
        switch self {
        case .automatedAttemptFailed:
            "The automated unsubscribe was sent and the sender refused it, so it has to be "
                + "finished on their page."
        case .noPublishedTarget:
            "This sender published no unsubscribe link Nevermore can use, so there is nothing to "
                + "send. Their preferences page has to be found by hand."
        case .ignoredAnUnsubscribe:
            "An unsubscribe was already recorded for this sender and they kept mailing. The "
                + "automated path did not work, so finish it on their page."
        case .wrongDeliveryAddress:
            "This sender's only unsubscribe is an email that identifies you by the address it "
                + "comes from, and the mail arrived at an alias this account cannot send as."
        }
    }
}

/// The senders that need a human in a browser, in the order they will be worked.
///
/// A value, like `SenderProposal` and for the same reason: the sequence is the
/// part of TASK-47 that is worth getting right, and it should be answerable
/// without a `WKWebView`, a window, or a mailbox. The app owns presenting the
/// page; this owns what is left to do, what has been done, and what happened.
///
/// Self-contained per entry — name and address are copied in — because a queue
/// outlives the state it was built against. It is worked in a sitting hours
/// after an agent filled it, and in between a sync can land, mail can be
/// trashed, and a group can be split or merged.
public struct BrowserQueue: Codable, Sendable, Hashable {
    /// What the human said happened, once they had the sender's page in front of
    /// them.
    ///
    /// Three cases and not a Bool: "I did it", "I tried and their page would not
    /// let me", and "I looked and gave up" are different facts, and the third is
    /// the one a summary would otherwise quietly count as a success. Only
    /// `confirmed` records an unsubscribe against the sender.
    public enum Outcome: String, Codable, Sendable, Hashable, CaseIterable {
        /// The sender's own page said it was done.
        case confirmed
        /// The page was there and it did not work — a login wall, a dead link,
        /// a form that refused the address.
        ///
        /// Spelled snake_case because this raw value is both the stored form and
        /// what an agent reads off the wire, where every other value is.
        case couldNotUnsubscribe = "could_not_unsubscribe"
        /// The human looked at this one and moved on without answering.
        case abandoned

        /// Whether this outcome is the sender being unsubscribed from. Only one
        /// of them is, and flattening the other two into "not confirmed yet"
        /// would lose the distinction the queue exists to record.
        public var isUnsubscribed: Bool { self == .confirmed }
    }

    /// One sender waiting for a browser, and what became of it.
    public struct Entry: Codable, Sendable, Hashable, Identifiable {
        /// `GroupID.storageKey`, as grouping stood when the entry was queued.
        public let groupKey: String
        public let senderName: String
        public let senderEmail: String
        public let reason: BrowserReason
        public let queuedAt: Date
        /// Nil while this entry is still to be worked. Terminal once set.
        public var outcome: Outcome?
        public var completedAt: Date?

        public var id: String { groupKey }
        public var isPending: Bool { outcome == nil }

        public init(
            groupKey: String, senderName: String, senderEmail: String, reason: BrowserReason,
            queuedAt: Date = Date(), outcome: Outcome? = nil, completedAt: Date? = nil
        ) {
            self.groupKey = groupKey
            self.senderName = senderName
            self.senderEmail = senderEmail
            self.reason = reason
            self.queuedAt = queuedAt
            self.outcome = outcome
            self.completedAt = completedAt
        }
    }

    /// In queueing order. Worked entries stay put rather than being removed:
    /// what happened to them is the answer to "how did that sitting go", and an
    /// agent reads it back through `get_browser_queue`.
    public private(set) var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    // MARK: - Reading

    public var isEmpty: Bool { entries.isEmpty }
    /// Still to be worked, in order.
    public var pending: [Entry] { entries.filter(\.isPending) }
    /// Worked, whatever the answer was.
    public var worked: [Entry] { entries.filter { !$0.isPending } }
    /// The next sender to put in front of the human, or nil once the sitting is
    /// finished.
    public var next: Entry? { entries.first(where: \.isPending) }

    public func entry(for groupKey: String) -> Entry? {
        entries.first { $0.groupKey == groupKey }
    }

    /// One-based position of a pending entry within the whole queue, for "3 of
    /// 12". Counts every entry, worked or not, so the total does not shrink
    /// under the user as they go.
    public func position(of groupKey: String) -> Int? {
        entries.firstIndex { $0.groupKey == groupKey }.map { $0 + 1 }
    }

    public var count: Int { entries.count }
    public var pendingCount: Int { pending.count }
    public var confirmedCount: Int { entries.filter { $0.outcome == .confirmed }.count }

    // MARK: - Writing

    /// Add a sender to the end of the queue.
    ///
    /// Returns false when the sender is already pending: queueing something
    /// twice is one row that can only be worked once, and a second copy would
    /// make the user open the same page again for no reason. A sender that was
    /// already *worked* is different — asking for it again is asking to redo it,
    /// so the entry is reset and moved to the end where the rest of this
    /// session's work is.
    @discardableResult
    public mutating func queue(_ entry: Entry) -> Bool {
        guard let index = entries.firstIndex(where: { $0.groupKey == entry.groupKey }) else {
            entries.append(entry)
            return true
        }
        guard !entries[index].isPending else { return false }
        entries.remove(at: index)
        entries.append(entry)
        return true
    }

    /// Add several, in the order given. Returns the keys that were actually
    /// queued, so a caller can tell the agent which of its senders were already
    /// waiting rather than reporting a count that means two different things.
    @discardableResult
    public mutating func queue(_ incoming: [Entry]) -> [String] {
        incoming.filter { queue($0) }.map(\.groupKey)
    }

    /// Record what the human said about one sender. Returns false when the key
    /// is not in the queue, or when it has already been answered — an answer is
    /// terminal, and overwriting one would let a stale sheet rewrite history.
    @discardableResult
    public mutating func record(_ outcome: Outcome, for groupKey: String, at now: Date = Date())
        -> Bool
    {
        guard let index = entries.firstIndex(where: { $0.groupKey == groupKey }),
            entries[index].isPending
        else { return false }
        entries[index].outcome = outcome
        entries[index].completedAt = now
        return true
    }

    /// Drop a sender from the queue without working it — the user deciding this
    /// one does not belong in the sitting.
    @discardableResult
    public mutating func remove(_ groupKey: String) -> Bool {
        let before = entries.count
        entries.removeAll { $0.groupKey == groupKey }
        return entries.count != before
    }

    /// Everything, gone. The queue is a to-do list rather than a record, so
    /// clearing it is the user saying they are finished with it.
    public mutating func clear() {
        entries.removeAll()
    }

    // MARK: - Deciding who belongs

    /// Why this sender needs a browser, or nil when something automated can
    /// still be tried.
    ///
    /// `canSendAsDeliveredAddress` is the app's send-as knowledge, which lives
    /// in the model rather than in the group; callers that do not have it (the
    /// read-only MCP snapshot) leave it true and get the two reasons that are
    /// decidable from stored headers alone.
    ///
    /// Order matters where several apply: a sender with no target at all cannot
    /// be finished automatically whatever else is true of them, so that reason
    /// is reported first.
    public static func reason(
        for group: SenderGroup,
        hasReappeared: Bool,
        canSendAsDeliveredAddress: Bool = true
    ) -> BrowserReason? {
        let method = UnsubscribeMethod.of(group)
        if method.needsBrowser { return .noPublishedTarget }
        if method == .mailto, !canSendAsDeliveredAddress,
            group.unsubscribeSource?.unsubscribe?.mailtoTargets.first?.identifiesRecipient == false
        {
            return .wrongDeliveryAddress
        }
        if hasReappeared { return .ignoredAnUnsubscribe }
        return nil
    }

    /// Why a sender a finished unsubscribe run has just been through still needs
    /// a person, or nil when the run left nothing for one to do.
    ///
    /// The results sheet's counterpart to `reason(for:hasReappeared:)`: that one
    /// decides from stored state, before anything is attempted, and this one
    /// from what the attempt returned. Both exist because the sheet has senders
    /// of both kinds in front of it at once — `needsManual` means nothing was
    /// sent and the stored reason is exactly why, while `failed` means the
    /// request went out and came back refused, which no stored fact can say.
    ///
    /// `storedReason` is what `reason(for:hasReappeared:)` says about the same
    /// sender, and is only consulted for `needsManual`. Its fallback is
    /// `noPublishedTarget` because that is what the engine's own `needsManual`
    /// reasons describe, and a sender needing a person with no reason recorded
    /// would queue with a blank explanation.
    public static func reason(
        afterRunOutcome outcome: UnsubscribeEngine.Outcome?,
        storedReason: BrowserReason?
    ) -> BrowserReason? {
        switch outcome {
        // Sent and accepted, or never attempted at all. Neither is a browser
        // job: the first is done, and the second was not part of the run.
        case .confirmed, .requested, nil: nil
        case .needsManual: storedReason ?? .noPublishedTarget
        // The freshest fact about this sender is that the request just failed,
        // so say that rather than whatever was true of them beforehand.
        case .failed: .automatedAttemptFailed
        }
    }
}
