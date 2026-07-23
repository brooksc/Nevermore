import SwiftUI

/// Menu-bar commands (spec §8). Every primary verb has a shortcut, and items
/// disable when there's no selection.
struct AppCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        // File
        CommandGroup(after: .newItem) {
            Button("Sync Now") { Task { await model.sync() } }
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

        // Actions — the app's verbs
        CommandMenu("Actions") {
            Button("Unsubscribe") { unsubscribeSelected() }
                .keyboardShortcut("u")
                .disabled(model.selection.isEmpty)
            Divider()
            Button("Ignore Sender") { model.ignore(model.selection) }
                .keyboardShortcut("i")
                .disabled(model.selection.isEmpty)
            Button("Unignore") { model.unignore(model.selection) }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(model.selection.isEmpty)
            Button("Move Messages to Trash…") { Task { await model.trash(model.selection) } }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.selection.isEmpty)
            Divider()
            Button("Forget Unsubscribe Record") { model.forget(model.selection) }
                .disabled(model.selection.isEmpty)
        }
    }

    private func unsubscribeSelected() {
        // The menu path can't present a sheet directly; post a notification the
        // window observes. Kept simple: drive through the model's selection.
        NotificationCenter.default.post(name: .unsubscribeSelected, object: nil)
    }
}

extension Notification.Name {
    static let unsubscribeSelected = Notification.Name("mailscrub.unsubscribeSelected")
}
