import Foundation

/// A verb Nevermore exposes to Shortcuts (TASK-35).
///
/// The list is short on purpose, and the reason is the one `ReviewToken` was
/// written for. A Shortcut is automation, and unlike an agent asking over MCP it
/// can be *scheduled*: an intent runs at three in the morning with nobody at the
/// keyboard, which is exactly the condition under which this app refuses to
/// unsubscribe from anything. So the admission test is not "does the intent ask
/// for confirmation" — every confirmation an unattended run can produce is a
/// dialog nobody reads — but `isLocalAndReversible`: the verb changes nothing
/// outside this Mac, and anything it changes here can be put back.
///
/// That test is what keeps `unsubscribe` off this surface. See `refused`.
public enum ShortcutVerb: String, CaseIterable, Sendable {
    /// Fetch new headers. Reads the mailbox; changes nothing in it.
    case sync
    /// Hide senders on this Mac. The sender is not told, and `unignoreSender`
    /// puts them back.
    case ignoreSender
    case unignoreSender
    /// Read the senders who kept mailing after a recorded unsubscribe.
    case listReappeared

    /// The admission test for this surface.
    ///
    /// Exhaustive rather than a stored flag, so a case added to this enum has to
    /// answer the question before the module compiles — and a case that has to
    /// answer `false` is a case that does not belong here.
    public var isLocalAndReversible: Bool {
        switch self {
        case .sync, .listReappeared, .ignoreSender, .unignoreSender: true
        }
    }

    /// The name the intent carries in the Shortcuts editor.
    public var title: String {
        switch self {
        case .sync: "Sync Mailbox"
        case .ignoreSender: "Ignore Senders"
        case .unignoreSender: "Unignore Senders"
        case .listReappeared: "Get Reappeared Senders"
        }
    }
}

/// A verb an automation surface would be expected to carry, and the reason
/// Nevermore does not carry it.
///
/// Written down rather than merely omitted. A missing feature looks like an
/// oversight, and the next person to read the acceptance criteria for TASK-35
/// will find `unsubscribe` named there; this is the answer to why no such intent
/// exists, kept next to the surface it constrains instead of in a document.
public struct ShortcutRefusal: Sendable, Equatable {
    /// The verb as the MCP surface names it, so the two lists can be compared.
    public let verb: String
    public let reason: String

    public init(verb: String, reason: String) {
        self.verb = verb
        self.reason = reason
    }
}

public enum ShortcutsSurface {
    /// Everything Shortcuts can drive.
    public static let verbs = ShortcutVerb.allCases

    /// Everything it deliberately cannot, and why.
    public static let refused: [ShortcutRefusal] = [
        ShortcutRefusal(
            verb: "unsubscribe",
            reason:
                "Unsubscribing reaches a third party, tells them the address is live, and cannot be "
                + "taken back. A set of senders is unsubscribed only after a human has reviewed "
                + "that exact set in Nevermore and confirmed it. A Shortcut can be scheduled, so "
                + "an intent for this would either act with nobody looking or raise a dialog with "
                + "nobody there to read it — and a dialog that fires on a schedule is answered by "
                + "reflex, which is worse than no dialog at all. Unsubscribe from the app."),
        ShortcutRefusal(
            verb: "unsubscribe_and_delete",
            reason:
                "Both halves are irreversible: the request cannot be recalled and the messages are "
                + "gone. Same answer as unsubscribe."),
        ShortcutRefusal(
            verb: "trash_sender_messages",
            reason:
                "Moves real mail on the server. Nevermore confirms it even when the user asks for "
                + "it themselves, and a confirmation nobody is present for is not a confirmation."),
    ]

    /// The refusals stated as one paragraph, for anywhere a person asks why
    /// their shortcut cannot unsubscribe.
    public static var refusalSummary: String {
        refused.map { "\($0.verb): \($0.reason)" }.joined(separator: "\n\n")
    }
}
