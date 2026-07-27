import SwiftUI

/// Keyboard shortcut cheat-sheet (opened with `?` or Help → Keyboard Shortcuts).
struct KeyboardShortcutsView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Shortcut: Identifiable {
        let id = UUID()
        let keys: String
        let action: String
    }

    private let sections: [(title: String, items: [Shortcut])] = [
        (
            "Navigate",
            [
                Shortcut(keys: "↑ ↓  /  j  k", action: "Move up / down the list"),
                Shortcut(keys: "⌘1 – ⌘4", action: "Switch collection"),
                Shortcut(keys: "⌘F", action: "Search"),
            ]
        ),
        (
            "Triage the selected sender",
            [
                Shortcut(keys: "v  /  ⌘⇧V", action: "View newest message in the browser"),
                Shortcut(keys: "u  /  ⌘U", action: "Unsubscribe"),
                Shortcut(
                    keys: "⇧U  /  ⌘⇧U",
                    action: "Unsubscribe and delete — no confirmation"),
                Shortcut(keys: "i  /  ⌘I", action: "Ignore"),
                Shortcut(keys: "d  /  ⌘⌫", action: "Trash messages"),
                Shortcut(keys: "⌘Z", action: "Undo the last ignore or trash"),
                Shortcut(keys: "⌘G", action: "View in webmail"),
            ]
        ),
        (
            "App",
            [
                Shortcut(keys: "⌘R", action: "Sync now"),
                Shortcut(keys: "⌥⌘S", action: "Toggle sidebar"),
                Shortcut(keys: "⌥⌘I", action: "Toggle inspector"),
                Shortcut(keys: "⌘,", action: "Settings"),
                Shortcut(keys: "?", action: "Show this list"),
            ]
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                Button("") { dismiss() }
                    .keyboardShortcut("w", modifiers: .command)
                    .hidden()
            }
            .padding(20)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(sections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title.uppercased())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(section.items) { item in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(item.keys)
                                        .font(.system(.callout, design: .monospaced))
                                        .frame(width: 130, alignment: .leading)
                                    Text(item.action).font(.callout)
                                    Spacer()
                                }
                            }
                        }
                    }
                    Text("Single-key shortcuts (j, k, u, ⇧U, i, d, ?) work while the sender list is focused. The ⌘ versions work anywhere.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(20)
            }
        }
        .frame(width: 420, height: 480)
        .onExitCommand { dismiss() }
    }
}
