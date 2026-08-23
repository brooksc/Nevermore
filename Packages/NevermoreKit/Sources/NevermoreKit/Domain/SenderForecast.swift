import Foundation

/// What one sender is likely to cost you going forward, from the mail already
/// on file (TASK-31).
///
/// The backlog count in the table is sunk: those messages have already arrived
/// and deleting the sender does not give the time back. The forecast is the
/// number that actually argues for or against unsubscribing, and the app has
/// everything it needs to compute it — first seen, last received, and the dates
/// in between. No fetching.
///
/// ## What this is allowed to claim
///
/// A rate is a statement about the future made from a small and biased sample,
/// so the wording is held to what the sample supports:
///
/// - **Nothing is quoted from a short history.** Four messages in three weeks is
///   not "about 69 a year"; it is four messages. Below
///   `minimumMessages` / `minimumObservedSpan` the app says it does not know,
///   which is the true answer.
/// - **A sender that has stopped is not forecast.** Past its own
///   `SenderCadence.silenceThreshold` with nothing new, quoting last year's rate
///   as next year's would be projecting a subscription that may already be over.
/// - **The figure is coarse.** "156 a year" claims a precision the sample cannot
///   carry, so the estimate is rounded to a step that matches the confidence and
///   led by a cadence in words — "about once a week" — with the annual figure as
///   support rather than as the claim.
/// - **Bursts are declared, not smoothed away.** A retailer that mails daily for
///   a week in November and monthly otherwise averages out to a number that
///   describes no month of the year, so it is labelled as arriving in bursts.
/// - **The mailbox is not the record.** The store holds what discovery found and
///   kept (see `SyncAttribution`, TASK-7), and trashed mail is gone from it —
///   so a sender the user has been clearing out reads as quieter than it is.
///   That is what `caveat` is for, and it is not fine print to be trimmed.
///
/// Everything here is pure and takes `now` from the caller.
public struct SenderForecast: Sendable, Equatable {
    /// What the app is standing on when it says anything at all.
    public enum Basis: Sendable, Equatable {
        /// Too few messages, or too short a history, to annualise from.
        case notEnoughHistory
        /// Nothing has arrived for longer than this sender's own usual gap, so
        /// there may be no subscription left to forecast.
        case lapsed(days: Int)
        /// A rate was estimated.
        case estimated
    }

    /// Whether the sender's rhythm has changed over the history on file —
    /// exactly the drift nobody notices from the inbox, because each individual
    /// message looks like the last one.
    public enum Trend: Sendable, Equatable {
        /// Not enough messages on either side of the history to compare.
        case unclear
        /// It changed by less than `materialFactor`, which is noise.
        case steady
        /// Coarse per-year rates for the first and second halves of the history.
        case changed(from: Int, to: Int)
    }

    public let basis: Basis
    public let messagesOnFile: Int
    /// Whole days from the first message on file to the last.
    public let observedDays: Int
    public let daysSinceLast: Int
    /// Coarse messages per year. Nil unless `basis` is `.estimated`.
    public let perYear: Int?
    /// True when the mail clumps rather than arriving on a rhythm.
    public let arrivesInBursts: Bool
    public let trend: Trend

    // MARK: - Thresholds

    /// Below five messages there are fewer than four gaps to average, and one
    /// unusual week is the entire sample.
    public static let minimumMessages = 5
    /// Below two months, annualising multiplies whatever the sample got wrong by
    /// six or more — and most senders have not been through one full cycle of
    /// their own behaviour yet (a monthly newsletter has sent twice).
    public static let minimumObservedSpan: TimeInterval = 60 * 86_400
    /// How far the two halves of the history must diverge before the change is
    /// worth putting on screen. Doubling or halving is drift a person would
    /// recognise; 30% is the sender having a busy quarter.
    public static let materialFactor = 2.0
    /// The mean gap being this many times the median means the mail clumps: half
    /// the messages arrive much closer together than the average suggests.
    static let burstFactor = 3.0

    static let year: TimeInterval = 365.25 * 86_400

    // MARK: - Building

    public static func make(for group: SenderGroup, now: Date) -> SenderForecast {
        make(dates: group.messages.map(\.receivedAt), now: now)
    }

    /// - Parameter dates: when the sender's mail *on file* arrived, in any order.
    ///   Dates after `now` are dropped rather than trusted — a message stamped in
    ///   the future is a sender's clock, not evidence.
    public static func make(dates: [Date], now: Date) -> SenderForecast {
        let dates = dates.filter { $0 <= now }
        guard let cadence = SenderCadence.of(dates) else {
            return SenderForecast(
                basis: .notEnoughHistory, messagesOnFile: 0, observedDays: 0,
                daysSinceLast: 0, perYear: nil, arrivesInBursts: false, trend: .unclear)
        }

        let daysSinceLast = wholeDays(now.timeIntervalSince(cadence.last))
        let observedDays = wholeDays(cadence.span)
        let bursty = isBursty(cadence)

        func forecast(_ basis: Basis, perYear: Int? = nil, trend: Trend = .unclear) -> SenderForecast {
            SenderForecast(
                basis: basis, messagesOnFile: cadence.messages, observedDays: observedDays,
                daysSinceLast: daysSinceLast, perYear: perYear, arrivesInBursts: bursty,
                trend: trend)
        }

        guard cadence.messages >= minimumMessages, cadence.span >= minimumObservedSpan else {
            return forecast(.notEnoughHistory)
        }
        // Checked after the evidence bar, not before: "this sender stopped" is
        // itself a claim about their rhythm, and a sender with three messages
        // has no rhythm to have stopped keeping.
        if now.timeIntervalSince(cadence.last) > recentCadence(of: dates).silenceThreshold {
            return forecast(.lapsed(days: daysSinceLast))
        }
        return forecast(
            .estimated, perYear: coarse(rate(cadence) * year), trend: trend(of: dates.sorted()))
    }

    /// How many of the most recent messages set the rhythm the lapse check uses.
    static let recentWindow = 10

    /// The rhythm the sender is keeping *now*, rather than the one it has kept
    /// on average.
    ///
    /// This is where TASK-31 has to part company with TASK-32, which reads the
    /// cadence from all the mail before an unsubscribe and is right to: it is
    /// asking whether a request was followed by silence, and the sender's habits
    /// before the request are the whole of the baseline.
    ///
    /// "Has this subscription ended?" is a different question, and answering it
    /// from all of history gets a sender that merely *slowed down* wrong. A
    /// weekly newsletter that went monthly a year ago has a median gap of a week
    /// across its whole history, so a perfectly punctual monthly issue looks
    /// like fifteen days of ominous silence. Ten messages is enough for a median
    /// and recent enough to be about the sender as it is.
    static func recentCadence(of dates: [Date]) -> SenderCadence {
        let recent = Array(dates.sorted().suffix(recentWindow))
        return SenderCadence.of(recent) ?? SenderCadence(
            messages: 0, first: .distantPast, last: .distantPast, medianGap: 0)
    }

    /// Messages per second, from the gaps: `n - 1` intervals over the observed
    /// span.
    ///
    /// The mean and not the median gap, which is the opposite of what
    /// `SenderCadence.silenceThreshold` wants and is right here for the same
    /// reason it is wrong there. "Has this sender stopped?" asks about the
    /// typical gap, which a burst must not be allowed to shrink. "How much mail
    /// is coming?" asks for a total, and the burst is part of the total — a
    /// retailer's Black Friday week is mail you will receive.
    static func rate(_ cadence: SenderCadence) -> Double {
        guard cadence.messages >= 2, cadence.span > 0 else { return 0 }
        return Double(cadence.messages - 1) / cadence.span
    }

    static func isBursty(_ cadence: SenderCadence) -> Bool {
        guard cadence.messages >= 2, cadence.medianGap > 0 else { return false }
        let mean = cadence.span / Double(cadence.messages - 1)
        return mean / cadence.medianGap >= burstFactor
    }

    /// Compare the first half of the history on file with the second.
    ///
    /// Halves of the observed span rather than "the last 90 days", so the
    /// comparison means the same thing for a sender seen for three months and
    /// one seen for three years, and so no window has to be picked and defended.
    /// Both halves cover equal time, so the counts compare directly.
    static func trend(of sorted: [Date]) -> Trend {
        guard let first = sorted.first, let last = sorted.last else { return .unclear }
        let half = last.timeIntervalSince(first) / 2
        guard half > 0 else { return .unclear }
        let midpoint = first.addingTimeInterval(half)
        let recent = sorted.count { $0 >= midpoint }
        let earlier = sorted.count - recent
        // Two in each half is the least that can show a direction rather than a
        // coincidence, and eight overall keeps one stray message from swinging
        // the ratio past 2×.
        guard sorted.count >= 8, earlier >= 2, recent >= 2 else { return .unclear }

        let factor = Double(recent) / Double(earlier)
        guard factor >= materialFactor || factor <= 1 / materialFactor else { return .steady }
        return .changed(
            from: coarse(Double(earlier) / half * year),
            to: coarse(Double(recent) / half * year))
    }

    /// Round to a step that does not out-claim the sample: exact only in single
    /// figures, and coarser the larger — and so the less certain — the number.
    static func coarse(_ perYear: Double) -> Int {
        let step: Double = switch perYear {
        case ..<10: 1
        case ..<50: 5
        case ..<200: 10
        default: 25
        }
        return max(1, Int((perYear / step).rounded()) * Int(step))
    }

    static func wholeDays(_ interval: TimeInterval) -> Int {
        max(0, Int((interval / 86_400).rounded()))
    }

    // MARK: - Wording

    /// A rhythm in words. Always hedged, because none of these is exact.
    ///
    /// This is what the user is meant to read; the annual figure is support.
    /// "About once a week" and "52 a year" describe the same estimate, and only
    /// one of them claims to know the number.
    public static func cadencePhrase(perYear: Int) -> String {
        switch perYear {
        case 300...: "Roughly one a day"
        case 130..<300: "A few a week"
        case 78..<130: "About twice a week"
        case 39..<78: "About once a week"
        case 18..<39: "About one every two weeks"
        case 9..<18: "About once a month"
        case 4..<9: "About one every two months"
        default: "A few a year"
        }
    }

    /// The line to lead with.
    public var headline: String {
        switch basis {
        case .estimated:
            guard let perYear else { return "No estimate" }
            return "\(Self.cadencePhrase(perYear: perYear)) — around \(perYear) more a year "
                + "at this rate."
        case .lapsed:
            return "This sender seems to have stopped."
        case .notEnoughHistory:
            return "Not enough history to estimate a rate."
        }
    }

    /// What the headline rests on, said plainly enough to be argued with.
    public var detail: String {
        switch basis {
        case .estimated:
            let base = "Estimated from \(messagesOnFile) messages over "
                + "\(observedDays) \(observedDays == 1 ? "day" : "days") on file."
            return arrivesInBursts
                ? base + " It arrives in bursts rather than steadily, so most months will "
                    + "look nothing like the average."
                : base
        case .lapsed(let days):
            return "Nothing in \(days) days — longer than the gaps it used to keep. Whatever it "
                + "sent before may be over, so Nevermore won't guess at a rate."
        case .notEnoughHistory:
            guard messagesOnFile > 0 else {
                return "None of this sender's mail is on file, so there is nothing to estimate from."
            }
            return "Only \(messagesOnFile) \(messagesOnFile == 1 ? "message" : "messages") over "
                + "\(observedDays) \(observedDays == 1 ? "day" : "days") on file. Nevermore waits "
                + "for \(Self.minimumMessages) messages spanning "
                + "\(Int(Self.minimumObservedSpan / 86_400)) days before putting a yearly number "
                + "on a sender — anything sooner is extrapolating from a coincidence."
        }
    }

    /// The cadence change, when there is one big enough to be worth the space.
    ///
    /// Nil the rest of the time on purpose: a trend line that appears on every
    /// sender to say "steady" is a line nobody reads, and then the one that says
    /// something is not read either.
    public var trendNote: String? {
        guard case .changed(let from, let to) = trend else { return nil }
        let direction = to > from ? "more" : "less"
        return "It mails \(direction) often than it used to — around \(to) a year now, against "
            + "around \(from) a year over the first half of the time you have been getting it."
    }

    /// Printed alongside the estimate. The sample is what is left in the
    /// mailbox, not what the sender sent, and the difference is invisible from
    /// inside the app.
    public static let caveat =
        "An estimate from past mail, not a promise about future mail. It counts only what is "
        + "still in this mailbox — anything already trashed isn't in it, so a sender you have "
        + "been clearing out will look quieter than it is."

    /// Whether the wording still admits it is an estimate.
    ///
    /// Asserted in the tests, like `UnsubscribePeriodReport.staysWithinTheEvidence`.
    /// If this goes false someone has rewritten a guess into a figure, and the
    /// fix is the copy.
    public var staysWithinTheEvidence: Bool {
        let text = ([headline, detail] + [trendNote].compactMap { $0 }).joined(separator: " ")
            .lowercased()
        // Something hedging, and nothing promising.
        let hedges = ["about", "around", "roughly", "estimate", "a few", "seems", "not enough"]
        let promises = ["will send", "will receive", "you will get", "exactly", "guaranteed"]
        return hedges.contains { text.contains($0) } && !promises.contains { text.contains($0) }
    }
}
