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
        Group {
            if model.selection.isEmpty {
                Text("\(model.rows.count) senders · \(model.totalMessages) messages")
            } else {
                let groups = model.selectedGroups
                let msgs = groups.reduce(0) { $0 + $1.total }
                Text("\(groups.count) selected · \(msgs) messages")
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
