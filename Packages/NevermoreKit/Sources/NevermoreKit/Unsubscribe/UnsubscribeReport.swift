import Foundation

/// The buckets the results sheet groups a run into.
///
/// Deliberately one case per honest outcome: `requested` is never folded into
/// `confirmed`, because only a human seeing the sender's own confirmation page
/// can promote an outcome to confirmed.
public enum UnsubscribeReportBucket: String, Sendable, CaseIterable {
    case failed
    case notAttempted
    case requested
    case confirmed

    /// Whether this bucket asks the user for something. The sheet's only call
    /// to action lives here, which is why these sort first.
    public var needsUser: Bool {
        switch self {
        case .failed, .notAttempted: true
        case .requested, .confirmed: false
        }
    }

    public var title: String {
        switch self {
        case .failed: "FAILED"
        case .notAttempted: "NOT ATTEMPTED"
        case .requested: "REQUESTED"
        case .confirmed: "CONFIRMED"
        }
    }

    public var symbolName: String {
        switch self {
        case .failed: "xmark.octagon.fill"
        case .notAttempted: "minus.circle"
        case .requested: "clock.badge.questionmark"
        case .confirmed: "checkmark.circle.fill"
        }
    }
}

/// What a finished unsubscribe run adds up to, and how the results sheet should
/// say it.
///
/// This exists outside the view because the two things that were wrong with the
/// sheet — the order the buckets render in, and a headline that read as
/// contradicting them — are decisions, not layout, and a layout is not something
/// a test can look at.
public struct UnsubscribeReport: Sendable, Equatable {
    /// Render order: whatever needs the user comes first. A summary sheet whose
    /// call to action is below the fold reads as complete when it isn't.
    public static let order: [UnsubscribeReportBucket] = [
        .failed, .notAttempted, .requested, .confirmed,
    ]

    private let counts: [UnsubscribeReportBucket: Int]

    public init(outcomes: [UnsubscribeEngine.Outcome?]) {
        var counts: [UnsubscribeReportBucket: Int] = [:]
        for outcome in outcomes {
            counts[Self.bucket(for: outcome), default: 0] += 1
        }
        self.counts = counts
    }

    public static func bucket(for outcome: UnsubscribeEngine.Outcome?) -> UnsubscribeReportBucket {
        switch outcome {
        case .confirmed: .confirmed
        case .requested: .requested
        // `needsManual` sits with the failures: nothing was sent, and it is the
        // user who has to finish it.
        case .failed, .needsManual: .failed
        // Cancelling leaves targets with no outcome at all. They used to appear
        // in no bucket, which made them silently missing from the report.
        case nil: .notAttempted
        }
    }

    public func count(_ bucket: UnsubscribeReportBucket) -> Int { counts[bucket] ?? 0 }

    /// The non-empty buckets, in render order.
    public var buckets: [UnsubscribeReportBucket] {
        Self.order.filter { count($0) > 0 }
    }

    public var total: Int { counts.values.reduce(0, +) }

    /// Confirmed plus requested. What "unsubscribed" is allowed to mean.
    public var succeeded: Int { count(.confirmed) + count(.requested) }

    /// Senders still waiting on the user.
    public var needingUser: Int { count(.failed) + count(.notAttempted) }

    /// Counts only what actually worked. `total` includes failures and senders
    /// that were never attempted, so a run where everything failed used to
    /// announce "Unsubscribed from 5 senders".
    ///
    /// When some senders did not succeed it says "10 of 11", because a sheet
    /// headed "Unsubscribed from 10 senders" that also lists "FAILED · 1" makes
    /// the reader reconcile 10 against 11 outcomes.
    public var headline: String {
        guard succeeded > 0 else { return "No senders were unsubscribed" }
        if succeeded == total {
            return "Unsubscribed from \(succeeded) sender\(succeeded == 1 ? "" : "s")"
        }
        return "Unsubscribed from \(succeeded) of \(total) senders"
    }

    /// States the size of the report in words, so a run of ten that shows a few
    /// rows is never mistaken for a complete report of a few.
    public var contentsLine: String {
        let senders = "\(total) sender\(total == 1 ? "" : "s") in this report"
        guard needingUser > 0 else { return senders }
        return "\(senders) · \(needingUser) still need\(needingUser == 1 ? "s" : "") you, listed first"
    }
}
