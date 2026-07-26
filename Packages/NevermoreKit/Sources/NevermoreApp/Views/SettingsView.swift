import OSLog
import SwiftUI
import NevermoreKit

/// Settings window (design 1m, spec §11). Standard four-tab layout.
struct SettingsView: View {
    @Bindable var model: AppModel

    // General
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("askBeforeUnsubscribe") private var askBeforeUnsubscribe = true
    @AppStorage("deleteIsDefault") private var deleteIsDefault = false
    @AppStorage("trashConfirmThreshold") private var trashThreshold = 500
    // Sync
    @AppStorage("syncOnLaunch") private var syncOnLaunch = true
    @AppStorage("backgroundInterval") private var backgroundInterval = "hourly"
    // Advanced
    @AppStorage("verboseLogging") private var verboseLogging = false
    @State private var showResetConfirm = false
    @State private var showResyncConfirm = false

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            accounts.tabItem { Label("Accounts", systemImage: "person.crop.circle") }
            sync.tabItem { Label("Sync", systemImage: "arrow.clockwise") }
            advanced.tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        // 320 was enough before Advanced grew a Demo section and a version
        // footer; at that height the footer sat below the fold.
        .frame(width: 480, height: 500)
    }

    private var general: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)
            Section("Unsubscribing") {
                Toggle("Ask before unsubscribing", isOn: $askBeforeUnsubscribe)
                Toggle("Make “Unsubscribe and Delete” the default action", isOn: $deleteIsDefault)
            }
            Section("Trashing") {
                Stepper(
                    "Confirm when trashing more than \(trashThreshold) messages",
                    value: $trashThreshold, in: 50...5000, step: 50)
                Text("Trashing is recoverable — messages go to your Trash folder and ⌘Z untrashes them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var accounts: some View {
        Form {
            Section {
                ForEach(model.accounts, id: \.self) { account in
                    HStack(spacing: 12) {
                        Monogram(text: account, diameter: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(account).fontWeight(.medium)
                            Text(account == model.currentAccount ? "Active" : "Registered")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove", role: .destructive) {
                            Task { await model.removeAccount(account) }
                        }
                        .controlSize(.small)
                    }
                }
            }
            if let url = model.currentProvider.appPasswordURL {
                Link("Open \(model.currentProvider.displayName) App Passwords", destination: url)
            }
        }
        .formStyle(.grouped)
    }

    private var sync: some View {
        Form {
            Section("Syncing") {
                Toggle("Sync on launch", isOn: $syncOnLaunch)
                Picker("In the background", selection: $backgroundInterval) {
                    Text("Off").tag("off")
                    Text("Every 15 minutes").tag("15m")
                    Text("Every hour").tag("hourly")
                    Text("Daily").tag("daily")
                }
            }
            Section {
                Button("Full Resync…") { showResyncConfirm = true }
                    .disabled(model.isDemoMode || model.isSyncing)
                Text("Discards the local header cache and re-reads the whole mailbox. Use this after deleting mail outside Nevermore — a normal sync only looks for new messages, so it can't notice ones that went away. Your unsubscribe history, ignored senders, and grouping corrections are kept.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Re-read the whole mailbox?", isPresented: $showResyncConfirm,
            titleVisibility: .visible
        ) {
            Button("Full Resync") { model.fullResync() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Nevermore will forget its local copy of your headers and scan your mail history again, which takes a few minutes. Nothing on the mail server is changed, and your unsubscribe history is kept.")
        }
    }

    private var advanced: some View {
        Form {
            Section("Grouping corrections") {
                if model.groupingRules.isEmpty {
                    Text("Right-click a sender to Split by Address or Keep as One Group when the automatic grouping gets it wrong. Your corrections appear here.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(model.groupingRules.sorted(by: { $0.key < $1.key }), id: \.key) { domain, rule in
                        HStack {
                            Text(domain)
                            Spacer()
                            Text(rule == .split ? "Split by address" : "Kept as one group")
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                    Button("Reset All Grouping Corrections", role: .destructive) {
                        model.resetGroupingRules()
                    }
                }
            }
            Section("Demo mode") {
                if model.isDemoMode {
                    Button("Leave Demo Mode") { Task { await model.exitDemoMode() } }
                    Text("Nevermore is showing example data. Leave demo mode to go back to your own mail.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Switch to Demo Mode…") { Task { await model.enterDemoMode() } }
                    Text("Swaps your mail for a sample mailbox — useful for showing Nevermore to someone without exposing your inbox. Your own data is untouched, and no action in demo mode reaches a server. The demo resets each time you enter it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Diagnostics") {
                Toggle("Verbose logging", isOn: $verboseLogging)
                Text("When on, detailed events are recorded to the system log and shown in Console. Sender addresses are logged; message contents and your password never are.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Export Diagnostics…") { exportDiagnostics() }
            }
            if model.debugToolsUnlocked { debugSection }
            versionFooter
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Reset Nevermore to a fresh install?",
            isPresented: $showResetConfirm, titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                Task { await model.resetAllState() }
            }
            Button("Reset and Forget Password", role: .destructive) {
                // Passwords first: the reset clears the account list this reads.
                model.deleteSavedPasswords()
                Task { await model.resetAllState() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(AppModel.resetDescription)
        }
    }

    /// Double-clicking the version reveals the debug tools. Hidden rather than
    /// absent: resetting to a fresh install is exactly the wrong button for a
    /// real user to find by accident, and exactly the one needed to test
    /// onboarding more than once.
    private var versionFooter: some View {
        Section {
            HStack {
                Spacer()
                Text("Nevermore \(AppVersion.display)")
                    .font(.caption)
                    .foregroundStyle(model.debugToolsUnlocked ? Tokens.demoAccent : .secondary)
                    // Text hit-tests only its glyphs; without a content shape a
                    // double-click between characters misses.
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { model.debugToolsUnlocked.toggle() }
                    .help(model.debugToolsUnlocked ? "Double-click to hide debug tools" : "")
                Spacer()
            }
        }
    }

    private var debugSection: some View {
        Section("Debug") {
            Button("Reset App State…", role: .destructive) { showResetConfirm = true }
            Text("Returns Nevermore to its never-launched state so onboarding can be tested again. Local data only — nothing on the mail server changes. Works from demo mode too; the reset leaves it.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Dump the last hour of Nevermore's unified log to a file and reveal it, so
    /// the user can hand it over when something's wrong. Uses OSLogStore rather
    /// than spawning `/usr/bin/log`, which the App Sandbox forbids.
    private func exportDiagnostics() {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("Nevermore-diagnostics.log")
        do {
            // .currentProcessIdentifier is the only scope a sandboxed app may
            // read — exactly this app's own log entries.
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let since = store.position(date: Date().addingTimeInterval(-3600))
            let entries = try store.getEntries(at: since)
            var lines: [String] = []
            let formatter = ISO8601DateFormatter()
            for case let entry as OSLogEntryLog in entries
            where entry.subsystem == Log.subsystem {
                lines.append(
                    "\(formatter.string(from: entry.date)) [\(entry.category)] \(entry.composedMessage)")
            }
            let text = lines.isEmpty
                ? "No Nevermore log entries in the last hour."
                : lines.joined(separator: "\n")
            try text.write(to: out, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([out])
        } catch {
            Log.app.problem("export diagnostics failed: \(error.localizedDescription)")
        }
    }
}
