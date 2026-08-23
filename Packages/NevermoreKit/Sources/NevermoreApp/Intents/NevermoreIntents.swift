import AppIntents
import Foundation
import NevermoreKit

// The Shortcuts surface (TASK-35). Three intents, and no unsubscribe — see
// `ShortcutsSurface.refused` in NevermoreKit for why, and `IntentContext` for
// the mechanism that would make an unsubscribe intent fail if one were added.
//
// Nothing here is behind `#if`. The whole point of putting these verbs on
// `MCPActions` rather than beside it is that the action layer sits *below* the
// split between the two channels: the MCP server is compiled out of the store
// build, and these intents are not.

/// Fetch new headers. The one verb with no target: it acts on the open mailbox.
struct SyncMailboxIntent: AppIntent {
    static let title: LocalizedStringResource = "Sync Mailbox"
    static let description = IntentDescription(
        """
        Fetches new message headers from the open mailbox. Nevermore never downloads message \
        bodies, and a sync changes nothing on the mail server.
        """,
        categoryName: "Mailbox")

    /// False so a scheduled sync does not take the screen. The trade is that an
    /// intent arriving while Nevermore is closed refuses instead of launching
    /// it — which is the right way round for a verb whose whole value is that it
    /// happens quietly.
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let detail = try await IntentContext.sync()
        return .result(dialog: IntentDialog("\(detail)"))
    }
}

/// Hide senders on this Mac.
struct IgnoreSendersIntent: AppIntent {
    static let title: LocalizedStringResource = "Ignore Senders"
    static let description = IntentDescription(
        """
        Hides senders in Nevermore on this Mac. They are not unsubscribed and they are not told \
        anything — they keep mailing, and the mail keeps arriving. Undone by Unignore Senders.
        """,
        categoryName: "Senders")

    static let openAppWhenRun = false

    @Parameter(title: "Senders")
    var senders: [SenderEntity]

    static var parameterSummary: some ParameterSummary {
        Summary("Ignore \(\.$senders) in Nevermore")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let detail = try await IntentContext.setIgnored(true, senders)
        return .result(dialog: IntentDialog("\(detail)"))
    }
}

/// Put ignored senders back in the working list.
struct UnignoreSendersIntent: AppIntent {
    static let title: LocalizedStringResource = "Unignore Senders"
    static let description = IntentDescription(
        "Puts senders back in Nevermore's working list after they were ignored.",
        categoryName: "Senders")

    static let openAppWhenRun = false

    @Parameter(title: "Senders")
    var senders: [SenderEntity]

    static var parameterSummary: some ParameterSummary {
        Summary("Unignore \(\.$senders) in Nevermore")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let detail = try await IntentContext.setIgnored(false, senders)
        return .result(dialog: IntentDialog("\(detail)"))
    }
}

/// The senders who kept mailing after a recorded unsubscribe.
///
/// The read that makes the rest of the surface worth automating: a shortcut can
/// sync, ask who ignored an unsubscribe, and hand that list to a notification.
/// Deciding what to do about them stays in the app, which is where the sender's
/// own page gets opened and the click gets made.
struct ReappearedSendersIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Reappeared Senders"
    static let description = IntentDescription(
        """
        The senders who have mailed again since Nevermore recorded an unsubscribe for them. \
        Reads only — nothing is sent, and nothing changes.
        """,
        categoryName: "Mailbox")

    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<[SenderEntity]> & ProvidesDialog
    {
        let senders = try await MainActor.run { try IntentContext.reappeared() }
        let dialog =
            senders.isEmpty
            ? "No sender has mailed again since you unsubscribed."
            : "\(senders.count) sender\(senders.count == 1 ? "" : "s") kept mailing after an "
                + "unsubscribe was recorded."
        return .result(value: senders, dialog: IntentDialog("\(dialog)"))
    }
}

/// The shortcuts offered without the user building anything.
///
/// Only the two that need no parameter. An `AppShortcut` for Ignore Senders
/// would appear in Spotlight as a one-tap action with no sender attached, which
/// is a prompt for a mistake rather than a convenience; both ignore intents are
/// still there for anyone assembling a shortcut in the editor.
struct NevermoreAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SyncMailboxIntent(),
            phrases: ["Sync \(.applicationName)", "Sync my \(.applicationName) mailbox"],
            shortTitle: "Sync Mailbox",
            systemImageName: "arrow.clockwise")
        AppShortcut(
            intent: ReappearedSendersIntent(),
            phrases: [
                "Reappeared senders in \(.applicationName)",
                "Who ignored my \(.applicationName) unsubscribes",
            ],
            shortTitle: "Reappeared Senders",
            systemImageName: "exclamationmark.triangle")
    }
}
