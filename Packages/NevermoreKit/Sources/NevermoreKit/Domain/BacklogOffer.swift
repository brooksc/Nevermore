import Foundation

/// The offer to clear a sender's remaining mail, made the moment their
/// unsubscribe is confirmed (TASK-23).
///
/// Confirming an unsubscribe says nothing about the mail already in the mailbox,
/// and that is the moment the user has decided they want nothing more from this
/// sender. So the app asks — once, where the user is already looking — and never
/// assumes. Nothing here trashes anything: it is the wording and the shape of the
/// question, kept out of the sheet so the answer to "what does the app offer, and
/// does it say what it is about to do" can be tested without a `WKWebView`.
///
/// The offer stands in for the Settings trash-confirmation dialog rather than
/// preceding it, which is only honest while it says what that dialog says: the
/// exact number of messages and where they go. `namesWhatItWillDo` is that
/// invariant, asserted in the tests.
public struct BacklogOffer: Sendable, Equatable {
    /// What accepting means. Two verbs, because a sender that already ignored one
    /// unsubscribe is one you want gone rather than merely tidied — that is the
    /// button the Reappeared row offers, and this is the same decision.
    public enum Accept: Sendable, Equatable {
        case trash
        case trashAndIgnore
    }

    /// Which moment this offer is being made at.
    ///
    /// Three, because the sentence that is honest at each is a different
    /// sentence. `couldNotUnsubscribe` is TASK-57's: the user opened the
    /// sender's page, hit a login wall, and said so. Nothing was unsubscribed,
    /// so nothing here may say it was — but that is exactly the moment *ignore*
    /// and *trash* are the useful next actions, and the sheet was closing
    /// without offering either.
    public enum Context: Sendable, Equatable {
        /// Confirmed, first time of asking.
        case unsubscribed
        /// Confirmed, after an earlier automated attempt failed to stick.
        case escalated
        /// The user tried on the sender's page and could not finish.
        case couldNotUnsubscribe
    }

    public let senderName: String
    /// How many of the sender's messages are still in the mailbox.
    public let messageCount: Int
    public let context: Context

    /// Nil when there is nothing to offer. A sender with no mail left gets told
    /// so (`nothingToClear`) rather than being shown a button that would do
    /// nothing — an offer with no subject is the kind of prompt that trains
    /// people to dismiss prompts.
    public init?(senderName: String, messageCount: Int, context: Context) {
        guard messageCount > 0 else { return nil }
        self.senderName = senderName
        self.messageCount = messageCount
        self.context = context
    }

    /// The two confirmed-unsubscribe contexts, named the way callers that only
    /// know "was this an escalation" already ask for them.
    public init?(senderName: String, messageCount: Int, isEscalation: Bool) {
        self.init(
            senderName: senderName, messageCount: messageCount,
            context: isEscalation ? .escalated : .unsubscribed)
    }

    /// True when this unsubscribe was an escalation after an automated attempt
    /// failed to stick.
    public var isEscalation: Bool { context == .escalated }

    /// A sender who has already ignored one unsubscribe, or whose page would not
    /// let the user finish, is one you want gone rather than merely tidied — so
    /// both of those accept into `trashAndIgnore`. Trashing alone would leave
    /// the sender in the working list to be met again next sync.
    public var accept: Accept { context == .unsubscribed ? .trash : .trashAndIgnore }

    /// What the offer says, naming the count and the destination.
    public var question: String {
        let count = messageCount.formatted()
        let noun = messageCount == 1 ? "message" : "messages"
        let isAre = messageCount == 1 ? "is" : "are"
        switch context {
        case .escalated:
            return "\(senderName) kept mailing after the last unsubscribe. \(count) of their "
                + "\(noun) \(isAre) still in your mailbox. Trashing "
                + "them also ignores the sender, and deleted mail moves to your provider's Trash."
        case .couldNotUnsubscribe:
            // Says plainly that nothing was unsubscribed. The offer is a way out
            // of a sender you cannot leave, not a substitute claim that you did.
            return "Nothing was unsubscribed — \(senderName) is still sending to you. \(count) of "
                + "their \(noun) \(isAre) still in your mailbox. Trashing them also ignores the "
                + "sender, so they stay out of your lists, and deleted mail moves to your "
                + "provider's Trash."
        case .unsubscribed:
            return "\(count) \(noun) from this sender \(isAre) still in "
                + "your mailbox. Deleted mail moves to your provider's Trash."
        }
    }

    /// The escalation wording is the Reappeared row's, deliberately: the same
    /// decision should not be called two different things in two places.
    public var acceptLabel: String {
        accept == .trashAndIgnore
            ? "Trash and Ignore"
            : "Delete \(messageCount.formatted()) Message\(messageCount == 1 ? "" : "s")"
    }

    /// Declining a failed attempt is not "keep the messages" — the sender is
    /// staying in the list to be dealt with, which is the point of the fix.
    public var declineLabel: String {
        context == .couldNotUnsubscribe ? "Leave in My List" : "Keep Messages"
    }

    /// The offer as a toast, for the one case where the user leaves the sheet
    /// without answering. A toast has no room for the question, so the count has
    /// to be in the button.
    public var toastMessage: String {
        context == .couldNotUnsubscribe
            ? "Couldn't unsubscribe from \(senderName)"
            : "Unsubscribed from \(senderName)"
    }

    public var toastActionLabel: String {
        accept == .trashAndIgnore
            ? "Trash \(messageCount.formatted()) and Ignore"
            : "Delete \(messageCount.formatted()) Message\(messageCount == 1 ? "" : "s")"
    }

    /// Whether the interaction, taken as a whole, states the number of messages
    /// and where they are going.
    ///
    /// This is the property that lets the offer replace the trash-confirmation
    /// dialog instead of being followed by it. If it ever goes false, the copy
    /// has drifted into asking the user to accept something it has not described,
    /// and the answer is to fix the copy — not to trash on a vaguer question.
    public var namesWhatItWillDo: Bool {
        let interaction = question + " " + acceptLabel
        return interaction.contains(messageCount.formatted())
            && interaction.contains("Trash")
    }

    /// Shown in place of the offer when the sender has no mail left. Not a
    /// question: there is nothing to decide.
    public static let nothingToClear = "There is no mail left from this sender to clear."
}
