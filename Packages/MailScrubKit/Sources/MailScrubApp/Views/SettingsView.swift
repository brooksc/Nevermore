import OSLog
import SwiftUI
import MailScrubKit

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
    @AppStorage("notifyNewSenders") private var notifyNewSenders = true
    // Advanced
    @AppStorage("verboseLogging") private var verboseLogging = false

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            accounts.tabItem { Label("Accounts", systemImage: "person.crop.circle") }
            sync.tabItem { Label("Sync", systemImage: "arrow.clockwise") }
            advanced.tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 480, height: 320)
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
                Toggle("Notify when new senders appear", isOn: $notifyNewSenders)
            }
            Section {
                Button("Full Resync…") { Task { await model.sync() } }
                Text("Discards the local database and re-reads every header.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
            Section("Diagnostics") {
                Toggle("Verbose logging", isOn: $verboseLogging)
                Text("When on, detailed events are recorded to the system log and shown in Console. Sender addresses are logged; message contents and your password never are.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Export Diagnostics…") { exportDiagnostics() }
            }
        }
        .formStyle(.grouped)
    }

    /// Dump the last hour of MailScrub's unified log to a file and reveal it, so
    /// the user can hand it over when something's wrong. Uses OSLogStore rather
    /// than spawning `/usr/bin/log`, which the App Sandbox forbids.
    private func exportDiagnostics() {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailScrub-diagnostics.log")
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
                ? "No MailScrub log entries in the last hour."
                : lines.joined(separator: "\n")
            try text.write(to: out, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([out])
        } catch {
            Log.app.problem("export diagnostics failed: \(error.localizedDescription)")
        }
    }
}
