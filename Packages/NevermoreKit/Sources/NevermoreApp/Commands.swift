import AppKit
import SwiftUI
import NevermoreKit

/// Menu-bar commands (spec §8). Every primary verb has a shortcut, and items
/// disable when there's no selection.
struct AppCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        // A custom About, so the panel carries the real version, the licence,
        // and where to read the privacy policy — an app holding a mail
        // credential should say who wrote it.
        CommandGroup(replacing: .appInfo) {
            Button("About Nevermore") { showAboutPanel() }
        }

        // File. `replacing:` rather than `after:` deliberately: the default
        // group contributes New Window, and a second window shares this app's
        // single AppModel — same selection, same search, same collection. Two
        // linked mirrors of one mailbox is worse than one window.
        CommandGroup(replacing: .newItem) {
            Button("Add Account…") { model.wantsToAddAccount = true }
            Button("Sync Now") { model.startSync() }
                .keyboardShortcut("r")
        }

        // View — collection switching (⌘1…⌘5)
        CommandGroup(after: .toolbar) {
            ForEach(Array(SenderCollection.allCases.enumerated()), id: \.element) { index, item in
                Button(item.title) { model.collection = item }
                    .keyboardShortcut(
                        KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    // Proposed comes and goes with the proposal, so its shortcut
                    // has to as well: ⌘5 with nothing proposed would select a
                    // collection that has no sidebar row and nothing in it.
                    // The number itself is fixed — it is the position in
                    // `allCases` — so the other four never renumber.
                    //
                    // Only Proposed: Reappeared's section also hides when empty,
                    // but ⌘2 has always worked and lands on an empty state that
                    // says everyone honoured your unsubscribes, which is worth
                    // being able to check.
                    .disabled(item == .proposed && !model.shows(.proposed))
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
            // The four pages someone stuck actually needs, in the order they
            // get stuck: a question about what the app did, a password that
            // won't work, a worry about what leaves the Mac, and then a person
            // to write to. Every one is a page on the site, so it can be fixed
            // without shipping a build and needs no GitHub account to read.
            //
            // The site's own home page is deliberately not a fifth item: it
            // sells the app to someone who hasn't got it, and all four pages
            // carry a link back to it anyway. Nor are the six per-provider
            // app-password guides listed individually — from a menu there is no
            // address in hand to pick the right one, so this links their index
            // and lets the user choose. The add-account sheet, which does know
            // the provider, already links that provider's page directly.
            Button("Frequently Asked Questions") { open(SupportSite.faq) }
            Button("Setting Up an App Password") { open(SupportSite.appPasswords) }
            Button("Privacy Policy") { open(SupportSite.privacy) }
            Button("Nevermore Support") { open(SupportSite.support) }
        }

        // Actions — the app's verbs
        // Every item disables through the same rule the toolbar and the
        // single-key shortcuts use, with the reason as its tooltip — an item
        // that stays live in a collection it can't act in is how ⌘U used to
        // unsubscribe a sender that wasn't on screen.
        CommandMenu("Actions") {
            Button("Unsubscribe") { unsubscribeSelected() }
                .keyboardShortcut("u")
                .disabled(!model.can(.unsubscribe))
                .help(model.reason(.unsubscribe) ?? "")
            Button("Unsubscribe and Delete Messages") { unsubscribeAndDeleteSelected() }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(!model.can(.unsubscribeAndDelete))
                .help(model.reason(.unsubscribeAndDelete) ?? "")
            Divider()
            Button("View Latest Message") { model.viewLatestMessage() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .disabled(!model.can(.viewLatestMessage))
                .help(model.reason(.viewLatestMessage) ?? "")
            Divider()
            Button("Ignore Sender") { model.ignore(model.selection) }
                .keyboardShortcut("i")
                .disabled(!model.can(.ignore))
                .help(model.reason(.ignore) ?? "")
            Button("Unignore") { model.unignore(model.selection) }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(!model.can(.unignore))
                .help(model.reason(.unignore) ?? "")
            Button("Move Messages to Trash…") { model.requestTrash(model.selection) }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!model.can(.trash))
                .help(model.reason(.trash) ?? "")
            if model.canOpenInWebmail {
                Button("View in \(model.currentProvider.displayName)") {
                    model.openSelectionInWebmail()
                }
                .keyboardShortcut("g")
                .disabled(model.selection.isEmpty)
            }
            Divider()
            // The browser queue (TASK-47). Filling it is ordinary triage — it
            // sends nothing — and working it is a sitting, not a per-sender
            // action, which is why it isn't tied to the selection.
            Button("Add to Browser Queue") { model.queueSelectionForBrowser() }
                .disabled(model.selection.isEmpty)
                .help("Collect senders that need a browser, to work through later.")
            Button("Work the Browser Queue…") { workBrowserQueue() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(model.browserQueue.pendingCount == 0)
                .help(
                    model.browserQueue.pendingCount == 0
                        ? "No senders are waiting for a browser."
                        : "Open the \(model.browserQueue.pendingCount) senders waiting, one after another.")
            Divider()
            Button("Forget Unsubscribe Record") { model.forget(model.selection) }
                .disabled(!model.can(.forget))
                .help(model.reason(.forget) ?? "")
        }
    }

    private func showAboutPanel() {
        let credits = NSAttributedString(
            string: """
                Find and bulk-unsubscribe from newsletters, entirely on your Mac.

                Reads message headers only — never bodies — and never sends your                 data anywhere except to the unsubscribe endpoint the sender                 published. Deleted mail moves to your provider's Trash and is                 never permanently destroyed.

                Personal-use licence. Source available for inspection.
                """,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationVersion: AppVersion.marketing,
            .version: AppVersion.build,
            .credits: credits,
        ])
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Opens a page in the default browser. Only ever from a menu item the user
    /// picked — nothing here opens a window on its own.
    private func open(_ url: URL) {
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

    private func workBrowserQueue() {
        NotificationCenter.default.post(name: .workBrowserQueue, object: nil)
    }
}

extension Notification.Name {
    static let unsubscribeSelected = Notification.Name("nevermore.unsubscribeSelected")
    static let unsubscribeAndDeleteSelected = Notification.Name(
        "nevermore.unsubscribeAndDeleteSelected")
    static let workBrowserQueue = Notification.Name("nevermore.workBrowserQueue")
}
