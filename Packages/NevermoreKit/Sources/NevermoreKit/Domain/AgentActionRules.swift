import Foundation

/// Who asked for an action: the person at the keyboard, or an agent over MCP.
///
/// Not a permission level. It exists because two rules in the app differ by
/// origin, and both differences are deliberate rather than incidental.
public enum ActionOrigin: String, Sendable, Equatable {
    case user
    case agent
}

/// When trashing a sender's messages has to stop and ask.
///
/// The user's own trash prompts above the Settings threshold, because trashing
/// is recoverable from the provider's Trash and prompting for three messages is
/// noise. **An agent-initiated trash always prompts** (TASK-46 acceptance
/// criterion 6): it is the destructive verb on the write surface, the human
/// never chose these senders, and the threshold is a preference about the user's
/// own keystrokes rather than a policy an agent may inherit. There is
/// deliberately no argument, setting or policy that turns this off — if you are
/// adding one, that is the convenience path the task says to stop at and report.
public enum TrashConfirmation {
    public static func requiresPrompt(origin: ActionOrigin, messageCount: Int, threshold: Int)
        -> Bool
    {
        switch origin {
        case .agent: true
        case .user: messageCount > threshold
        }
    }
}

/// When an unsubscribe has to stop and ask.
///
/// "Ask before unsubscribing" is a standing preference about the user's own
/// keystrokes — someone who has turned it off has said *my* `u` should just go.
/// It is not consent for an agent, which is why an agent-initiated unsubscribe
/// confirms regardless: the MCP route answers `awaiting_confirmation`, and that
/// answer has to be true in every configuration of the app rather than in most
/// of them.
public enum UnsubscribeConfirmation {
    public static func requiresPrompt(origin: ActionOrigin, askBeforeUnsubscribe: Bool) -> Bool {
        switch origin {
        case .agent: true
        case .user: askBeforeUnsubscribe
        }
    }
}
