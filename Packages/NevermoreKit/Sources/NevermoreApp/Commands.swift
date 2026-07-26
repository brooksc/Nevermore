import AppKit
import SwiftUI

/// Menu-bar commands (spec §8). Every primary verb has a shortcut, and items
/// disable when there's no selection.
struct AppCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        // File
        CommandGroup(after: .newItem) {
            Button("Add Account…") { model.wantsToAddAccount = true }
            Button("Sync Now") { model.startSync() }
                .keyboardShortcut("r")
        }

        // View — collection switching (⌘1…⌘6)
        CommandGroup(after: .toolbar) {
            ForEach(Array(Collection.allCases.enumerated()), id: \.element) { index, item in
                Button(item.title) { model.collection = item }
                    .keyboardShortcut(
                        KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Divider()
            Button("Toggle Inspector") { model.showInspector.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
        }

        // Undo for the last reversible action (ignore / trash).
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { Task { await model.runUndo() } }
                .keyboardShortcut("z")
                .disabled(!model.canUndo)
        }

        // Help → Keyboard Shortcuts (⌘? works from anywhere; plain ? works while
        // the list is focused, handled by the table).
        CommandGroup(replacing: .help) {
            // Present only in the Developer ID build; the App Store target
            // omits Sparkle and this renders as nothing.
            CheckForUpdatesButton()
            Button("How Nevermore Works") { model.showHowItWorks = true }
            Button("Keyboard Shortcuts") { model.showShortcuts = true }
                .keyboardShortcut("?", modifiers: .command)
            Divider()
            // The App Store requires a support URL anyway; an app that holds a
            // mail credential should also make it easy to find out who wrote it
            // and read the source.
            Button("Frequently Asked Questions") { open("\(Self.website)faq.html") }
            Button("Nevermore Website") { open(Self.website) }
            Button("Privacy Policy") {
                open("https://github.com/brooksc/Nevermore/blob/main/PRIVACY.md")
            }
            Button("Report an Issue…") {
                open("https://github.com/brooksc/Nevermore/issues/new")
            }
        }

        // Actions — the app's verbs
        CommandMenu("Actions") {
            Button("Unsubscribe") { unsubscribeSelected() }
                .keyboardShortcut("u")
                .disabled(model.selection.isEmpty)
            Button("Unsubscribe and Delete Messages") { unsubscribeAndDeleteSelected() }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(model.selection.isEmpty)
            Divider()
            Button("View Latest Message") { model.viewLatestMessage() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .disabled(model.selection.isEmpty)
            Divider()
            Button("Ignore Sender") { model.ignore(model.selection) }
                .keyboardShortcut("i")
                .disabled(model.selection.isEmpty)
            Button("Unignore") { model.unignore(model.selection) }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(model.selection.isEmpty)
            Button("Move Messages to Trash…") { model.requestTrash(model.selection) }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.selection.isEmpty)
            if model.canOpenInWebmail {
                Button("View in \(model.currentProvider.displayName)") {
                    model.openSelectionInWebmail()
                }
                .keyboardShortcut("g")
                .disabled(model.selection.isEmpty)
            }
            Divider()
            Button("Forget Unsubscribe Record") { model.forget(model.selection) }
                .disabled(model.selection.isEmpty)
        }
    }

    /// Where the Help menu's links point. One place, so the marketing site and
    /// the FAQ can't drift apart from the app that links to them.
    static let website = "https://brooksc.github.io/Nevermore/"

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func unsubscribeSelected() {
        // The menu path can't present a sheet directly; post a notification the
        // window observes. Kept simple: drive through the model's selection.
        NotificationCenter.default.post(name: .unsubscribeSelected, object: nil)
    }

    private func unsubscribeAndDeleteSelected() {
        NotificationCenter.default.post(name: .unsubscribeAndDeleteSelected, object: nil)
    }
}

extension Notification.Name {
    static let unsubscribeSelected = Notification.Name("nevermore.unsubscribeSelected")
    static let unsubscribeAndDeleteSelected = Notification.Name(
        "nevermore.unsubscribeAndDeleteSelected")
}
