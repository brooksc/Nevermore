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
        case .discovering(let w, let total, let found):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Searching \(w)/\(total) — \(found) found")
            }
        case .fetching(let done, let total):
            HStack(spacing: 6) {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .frame(width: 80)
                Text("Reading headers \(done)/\(total)")
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange).lineLimit(1)
        }
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }
}
