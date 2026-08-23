import Foundation

/// The one rule for "this sender mailed again after you unsubscribed".
///
/// It existed in three places in the app — the Reappeared collection, the
/// Unsubscribed log's filter, and the per-sender message count — which is three
/// chances for the sidebar to disagree with the report about the same sender.
/// The rule itself is deliberately narrow: mail whose `receivedAt` is after the
/// recorded attempt. Nothing about compliance, only about arrival.
public enum Reappearance {
    /// How many of `messages` arrived after the unsubscribe was attempted.
    public static func messageCount(since attemptedAt: Date, in messages: [EmailMessage]) -> Int {
        messages.lazy.filter { $0.receivedAt > attemptedAt }.count
    }

    /// True when any message arrived after the unsubscribe was attempted.
    public static func hasMailed(since attemptedAt: Date, in messages: [EmailMessage]) -> Bool {
        messages.contains { $0.receivedAt > attemptedAt }
    }
}

/// A periodic summary of what happened after the unsubscribes in a window
/// (TASK-32): the app's claim, stated as a result instead of as a running list
/// that never concludes.
///
/// ## What this may and may not say
///
/// The app can observe exactly one thing: whether mail arrived after a recorded
/// attempt. It cannot observe compliance. A stored outcome of `.requested` means
/// an endpoint accepted a request — not that anyone acted on it — and even
/// `.confirmed` is the sender's own word. So the report never counts senders who
/// "honoured it". It counts senders who **have mailed again** (evidence) and
/// senders who have **sent nothing since** (an observation, which is what the
/// wording says).
///
/// Silence is weak evidence, so it is not reported unqualified:
///
/// - A sender whose own rhythm has not yet come round again is `.tooEarly`,
///   not quiet. Three weeks of silence from a monthly newsletter says nothing,
///   and counting it as a success would be inventing a result.
/// - A sender whose mail is no longer on file — never synced, or trashed by the
///   user — is `.noMailOnFile`. There is no evidence either way, and absence of
///   a mailbox is not absence of mail. (The Reappeared collection treats this
///   case as "not reappeared", which is right for a list of senders to chase and
///   wrong for a count of results.)
/// - An attempt whose outcome was `.failed` never reached anyone, so silence
///   after it is not a result at all. It is reported as unfinished work.
///
/// Everything here is pure and takes `now` from the caller, so all of it is
/// testable.
public struct UnsubscribePeriodReport: Sendable, Equatable {
    /// What was observed about one unsubscribe. Not a verdict on the sender.
    public enum Observation: Sendable, Equatable {
        /// Mail arrived after the attempt. The only conclusive case, and the
        /// only one that is conclusive against the sender.
        case mailedAgain(messages: Int)
        /// Nothing has arrived, and enough time has passed relative to this
        /// sender's own past rhythm that the silence is worth reporting.
        case quiet(days: Int)
        /// Nothing has arrived, but not enough time has passed to mean anything.
        case tooEarly
        /// The unsubscribe request itself did not go through.
        case requestFailed
        /// None of this sender's mail is on file, so there is nothing to judge by.
        case noMailOnFile
    }

    public struct Entry: Sendable, Equatable, Identifiable {
        public let groupKey: String
        public let senderName: String
        public let attemptedAt: Date
        public let observation: Observation

        public var id: String { groupKey }
    }

    /// Start of the window the report covers.
    public let since: Date
    public let now: Date
    /// One entry per unsubscribe attempted in the window, newest first.
    public let entries: [Entry]

    // MARK: - Building

    /// Silence shorter than this is never reported as quiet, however chatty the
    /// sender was. A sender who mailed daily and has been silent for two days
    /// has most likely just not got round to it.
    static let minimumQuietSpan: TimeInterval = 14 * 86_400
    /// …and silence longer than this is reported as quiet however rare the
    /// sender was, or a quarterly mailer would sit at "too early to say"
    /// forever and the report would never conclude anything.
    static let maximumQuietSpan: TimeInterval = 90 * 86_400

    /// - Parameters:
    ///   - records: every stored unsubscribe; those outside the window are dropped.
    ///   - messagesByGroupKey: the sender's mail currently on file, if any. A key
    ///     that is absent means "we hold none", which is not the same as "none arrived".
    public static func make(
        records: [MessageStore.UnsubscribeRecord],
        messagesByGroupKey: [String: [EmailMessage]],
        since: Date,
        now: Date
    ) -> UnsubscribePeriodReport {
        let entries = records
            .filter { $0.attemptedAt >= since && $0.attemptedAt <= now }
            .sorted { $0.attemptedAt > $1.attemptedAt }
            .map { record -> Entry in
                Entry(
                    groupKey: record.groupKey,
                    senderName: record.senderName,
                    attemptedAt: record.attemptedAt,
                    observation: observe(
                        record, messages: messagesByGroupKey[record.groupKey], now: now))
            }
        return UnsubscribePeriodReport(since: since, now: now, entries: entries)
    }

    private static func observe(
        _ record: MessageStore.UnsubscribeRecord, messages: [EmailMessage]?, now: Date
    ) -> Observation {
        // Mail since the attempt is checked first and for every record,
        // including failed ones: it is the one thing that is certain, and a
        // failed attempt that was followed by more mail is still a sender who
        // kept mailing.
        if let messages, Reappearance.hasMailed(since: record.attemptedAt, in: messages) {
            return .mailedAgain(messages: Reappearance.messageCount(
                since: record.attemptedAt, in: messages))
        }
        if record.outcome == .failed { return .requestFailed }
        guard let messages, !messages.isEmpty else { return .noMailOnFile }

        let elapsed = now.timeIntervalSince(record.attemptedAt)
        guard elapsed >= quietSpan(forMailBefore: record.attemptedAt, in: messages) else {
            return .tooEarly
        }
        return .quiet(days: Int(elapsed / 86_400))
    }

    /// How long this sender has to stay silent before the silence is worth
    /// reporting: twice their usual gap between messages, bounded at both ends.
    ///
    /// Twice, not once, because a newsletter that slips a week is common and a
    /// report that flips between "quiet" and "mailed again" week to week is
    /// worth nothing. The gap is the median of their past gaps, so one burst of
    /// five messages in an hour does not redefine "usual".
    public static func quietSpan(forMailBefore attemptedAt: Date, in messages: [EmailMessage]) -> TimeInterval {
        let dates = messages.map(\.receivedAt).filter { $0 <= attemptedAt }.sorted()
        guard dates.count >= 2 else {
            // One message tells us nothing about a rhythm. Fall back to the
            // floor rather than to a guess.
            return minimumQuietSpan
        }
        let gaps = zip(dates.dropFirst(), dates).map { $0.timeIntervalSince($1) }.sorted()
        let median = gaps.count % 2 == 1
            ? gaps[gaps.count / 2]
            : (gaps[gaps.count / 2 - 1] + gaps[gaps.count / 2]) / 2
        return min(max(median * 2, minimumQuietSpan), maximumQuietSpan)
    }

    // MARK: - Counts

    public var total: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }

    public var mailedAgainCount: Int {
        entries.count { if case .mailedAgain = $0.observation { true } else { false } }
    }
    public var quietCount: Int {
        entries.count { if case .quiet = $0.observation { true } else { false } }
    }
    public var tooEarlyCount: Int {
        entries.count { $0.observation == .tooEarly }
    }
    public var requestFailedCount: Int {
        entries.count { $0.observation == .requestFailed }
    }
    public var noMailOnFileCount: Int {
        entries.count { $0.observation == .noMailOnFile }
    }

    // MARK: - Wording

    /// Whole days the window spans, for the headline.
    public var windowDays: Int {
        max(1, Int((now.timeIntervalSince(since) / 86_400).rounded()))
    }

    public var headline: String {
        let window = "the last \(windowDays) days"
        guard total > 0 else { return "No unsubscribes in \(window)." }
        return total == 1
            ? "You unsubscribed from 1 sender in \(window)."
            : "You unsubscribed from \(total) senders in \(window)."
    }

    /// The body of the report: one line per thing that was actually observed.
    ///
    /// Every line is phrased as an observation about mail — "have mailed you
    /// since", "have sent nothing since" — because that is all the app measured.
    /// If a line here ever starts claiming senders honoured or respected
    /// anything, the report has stopped being defensible from its own data.
    public var findings: [String] {
        var lines: [String] = []
        if mailedAgainCount > 0 {
            lines.append(mailedAgainCount == 1
                ? "1 has mailed you since."
                : "\(mailedAgainCount) have mailed you since.")
        }
        if quietCount > 0 {
            lines.append(quietCount == 1
                ? "1 has sent nothing since, for longer than its usual gap between messages."
                : "\(quietCount) have sent nothing since, for longer than their usual gap between messages.")
        }
        if tooEarlyCount > 0 {
            lines.append(tooEarlyCount == 1
                ? "1 is too recent to say — that sender doesn't mail often enough yet to tell."
                : "\(tooEarlyCount) are too recent to say — those senders don't mail often enough yet to tell.")
        }
        if requestFailedCount > 0 {
            lines.append(requestFailedCount == 1
                ? "1 request didn't go through, so nothing was actually asked."
                : "\(requestFailedCount) requests didn't go through, so nothing was actually asked.")
        }
        if noMailOnFileCount > 0 {
            lines.append(noMailOnFileCount == 1
                ? "1 has no mail on file, so there's nothing to judge by."
                : "\(noMailOnFileCount) have no mail on file, so there's nothing to judge by.")
        }
        return lines
    }

    /// Printed with the report, always. The counts are honest on their own, but
    /// only if the reader knows what silence is and isn't worth.
    public static let caveat =
        "Nevermore can only see what arrives. A sender that has sent nothing may have "
        + "honoured your request, or may simply have had nothing to send — the app doesn't "
        + "claim to know which."

    /// Whether the report, taken as a whole, avoids claiming compliance.
    ///
    /// Asserted in the tests. If this goes false, someone has rewritten the copy
    /// into a claim the data cannot support, and the fix is the copy.
    public var staysWithinTheEvidence: Bool {
        let text = ([headline] + findings).joined(separator: " ").lowercased()
        return !["honoured", "honored", "respected", "complied", "worked", "succeeded"]
            .contains { text.contains($0) }
    }
}
