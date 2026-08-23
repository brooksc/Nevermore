import Foundation

/// How often a sender mails, read off the dates of the mail on file.
///
/// TASK-32 needed this to decide whether a sender's silence meant anything yet;
/// TASK-31 needs the same notion to decide whether a rate is worth quoting and
/// whether a sender has stopped. It lives here so there is one definition of
/// "this sender's usual rhythm" rather than two that can drift apart.
///
/// Nothing here is a claim about the sender's intent. It is arithmetic over the
/// dates of messages **still in this mailbox**, which is not the same as the
/// dates of messages that were sent — anything the user trashed is not on file,
/// and a sender that has been cleared out looks rarer than it is.
public struct SenderCadence: Sendable, Equatable {
    /// How many messages the cadence was read from.
    public let messages: Int
    public let first: Date
    public let last: Date
    /// The middle gap between consecutive messages.
    ///
    /// The median and not the mean, so one burst of five messages in an hour
    /// does not redefine "usual". Zero when there is only one message, which is
    /// why every caller checks `messages >= 2` before trusting it.
    public let medianGap: TimeInterval

    /// First message to last. Zero for a single message.
    public var span: TimeInterval { last.timeIntervalSince(first) }

    /// Read the rhythm out of a set of message dates. Nil when there are none.
    ///
    /// Order and duplicates do not matter; the dates are sorted here.
    public static func of(_ dates: [Date]) -> SenderCadence? {
        let sorted = dates.sorted()
        guard let first = sorted.first, let last = sorted.last else { return nil }
        return SenderCadence(
            messages: sorted.count,
            first: first,
            last: last,
            medianGap: median(of: zip(sorted.dropFirst(), sorted).map { $0.timeIntervalSince($1) }))
    }

    static func median(of values: [TimeInterval]) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted.count % 2 == 1
            ? sorted[sorted.count / 2]
            : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
    }

    // MARK: - Silence

    /// Silence shorter than this is never worth reporting, however chatty the
    /// sender was. A sender who mailed daily and has been silent for two days
    /// has most likely just not got round to it.
    public static let minimumSilence: TimeInterval = 14 * 86_400
    /// …and silence longer than this is worth reporting however rare the sender
    /// was, or a quarterly mailer would sit at "too early to say" forever and
    /// nothing would ever conclude.
    public static let maximumSilence: TimeInterval = 90 * 86_400

    /// How long this sender has to stay silent before the silence means
    /// anything: twice their usual gap, bounded at both ends.
    ///
    /// Twice, not once, because a newsletter that slips a week is common and a
    /// verdict that flips week to week is worth nothing.
    public var silenceThreshold: TimeInterval {
        guard messages >= 2 else {
            // One message tells us nothing about a rhythm. Fall back to the
            // floor rather than to a guess.
            return Self.minimumSilence
        }
        return min(max(medianGap * 2, Self.minimumSilence), Self.maximumSilence)
    }
}
