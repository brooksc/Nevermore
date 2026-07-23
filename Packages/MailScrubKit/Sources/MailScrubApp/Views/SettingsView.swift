import SwiftUI

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
                Text("Trashing is recoverable — messages go to Gmail's Trash and ⌘Z untrashes them.")
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
            Link("Open Google App Passwords",
                destination: URL(string: "https://myaccount.google.com/apppasswords")!)
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
            Section("Grouping overrides") {
                Text("Correct how senders are grouped. Host → group name.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Verbose logging", isOn: $verboseLogging)
                Button("Reset All Grouping Overrides", role: .destructive) {}
            }
        }
        .formStyle(.grouped)
    }
}
