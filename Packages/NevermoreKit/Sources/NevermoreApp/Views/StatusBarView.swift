import SwiftUI

/// The window's bottom status row (spec §12): counts · transient toast · sync state.
struct StatusBarView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            leading
            Spacer()
            if let toast = model.toast {
                Text(toast.message).foregroundStyle(.primary)
                if let undo = toast.undo {
                    Button(undo.label) { Task { await model.runUndo() } }
                        .buttonStyle(.link)
                } else if let action = toast.action {
                    Button(action.label) { Task { await model.runToastAction() } }
                        .buttonStyle(.link)
                }
                Spacer()
            }
            trailing
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 26)
        .background(.bar)
    }

    private var leading: some View {
        HStack(spacing: 10) {
            counts
            // The browser queue is worked from here or from the Actions menu.
            // A queue an agent filled while the user was elsewhere needs
            // somewhere to be visible, and the status bar is where the app
            // already says what is outstanding (TASK-47).
            if model.browserQueue.pendingCount > 0 {
                Button {
                    NotificationCenter.default.post(name: .workBrowserQueue, object: nil)
                } label: {
                    Label(
                        "\(model.browserQueue.pendingCount) need a browser",
                        systemImage: "hand.raised")
                }
                .buttonStyle(.link)
                .help("Work through the senders that need a browser, one after another.")
            }
        }
    }

    private var counts: some View {
        Group {
            // Counted against the visible list, not the raw selection: the count
            // used to describe rows from whichever collection they were clicked
            // in, and to read "0 selected" for an Unsubscribed row whose
            // messages are gone.
            if model.selectedCount == 0 {
                Text("\(model.visibleIDs.count) senders · \(model.totalMessages) messages")
            } else {
                let msgs = model.selectedGroups.reduce(0) { $0 + $1.total }
                Text("\(model.selectedCount) selected · \(msgs) messages")
                    .foregroundStyle(.primary)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch model.syncState {
        case .idle:
            if let date = model.lastSyncedAt {
                Text("Last synced \(relative(date))")
            } else {
                Text("Not synced yet")
            }
        case .connecting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Connecting…")
            }
        case .discovering(let w, let total, let found):
            HStack(spacing: 6) {
                ProgressView(value: Double(w), total: Double(max(total, 1)))
                    .frame(width: 80)
                Text("Searching — \(found.formatted()) found").monospacedDigit()
            }
        case .fetching(let done, let total):
            HStack(spacing: 6) {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .frame(width: 80)
                Text("Reading \(done.formatted()) of \(total.formatted())").monospacedDigit()
            }
        case .failed(let message):
            // Was a bare truncated label: a real failure ("Operation timed
            // out") got clipped, explained nothing, and offered no way back.
            HStack(spacing: 6) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .help(message)
                Button("Retry") { model.startSync() }
                    .buttonStyle(.link)
            }
        }
    }

    private func relative(_ date: Date) -> String {
        // RelativeDateTimeFormatter renders a just-finished sync as "in 0
        // seconds" — it rounds to zero and then picks the future phrasing.
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 { return "just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }
}
