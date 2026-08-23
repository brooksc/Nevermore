import NevermoreKit
import SwiftUI

/// The window's bottom status row (spec §12): counts · transient toast · sync state.
struct StatusBarView: View {
    @Bindable var model: AppModel

    /// Whether the breakdown of the last sync is open.
    @State private var showingAccounting = false

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
                let storage = model.visibleStorage
                Text(
                    "\(model.visibleIDs.count) senders · \(model.totalMessages) messages"
                        + size(storage))
                    .help(storage.caveat ?? "")
            } else {
                let msgs = model.selectedGroups.reduce(0) { $0 + $1.total }
                let storage = model.selectedStorage
                Text("\(model.selectedCount) selected · \(msgs) messages" + size(storage))
                    .foregroundStyle(.primary)
                    .help(storage.caveat ?? "")
            }
        }
    }

    /// The storage clause of a counts line, or nothing at all.
    ///
    /// Omitted rather than shown as "Unknown" when no size is on file: the
    /// status bar is a running summary, and a collection that has never been
    /// re-synced would otherwise carry a permanent apology in it. The Size
    /// column is where a per-sender unknown has to be stated, because there a
    /// blank could be mistaken for zero.
    private func size(_ storage: SenderStorage) -> String {
        storage.isUnknown ? "" : " · \(storage.summary())"
    }

    @ViewBuilder
    private var trailing: some View {
        switch model.syncState {
        case .idle:
            if let date = model.lastSyncedAt {
                // A plain label until there is something to explain. The
                // breakdown hangs off "last synced" because that is where a
                // user looks after noticing the server found more messages
                // than the app is showing (TASK-7).
                if let attribution = model.lastSyncAttribution, attribution.located > 0 {
                    Button("Last synced \(relative(date))") { showingAccounting.toggle() }
                        .buttonStyle(.link)
                        .help("What the last sync found, and what became of it.")
                        .popover(isPresented: $showingAccounting, arrowEdge: .top) {
                            SyncAccountingView(attribution: attribution)
                        }
                } else {
                    Text("Last synced \(relative(date))")
                }
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

    /// Where the last sync's messages went.
    ///
    /// The app has always shown "N found" during a sync and a smaller number of
    /// senders afterwards, and had no answer for the difference. Every line
    /// here is one reason a located message was not stored, with a count — so
    /// the answer is arithmetic a user can check rather than reassurance.
    private struct SyncAccountingView: View {
        let attribution: SyncAttribution

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("Last sync")
                    .font(.headline)
                Text("\(attribution.located.formatted()) messages matched on the server.")
                    .foregroundStyle(.secondary)

                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    row(attribution.inserted, "Added to Nevermore", nil)
                    if attribution.updated > 0 {
                        row(
                            attribution.updated, "Already had them",
                            "Re-read on purpose: each sync overlaps the last by two days so nothing falls through the gap."
                        )
                    }
                    ForEach(attribution.significantDrops, id: \.reason) { drop in
                        row(drop.count, drop.reason.label, drop.reason.detail)
                    }
                    if !attribution.balances {
                        row(
                            attribution.unaccounted, "Unaccounted for",
                            "Nevermore cannot explain these. Worth reporting."
                        )
                    }
                }
            }
            .frame(width: 340, alignment: .leading)
            .padding(14)
        }

        private func row(_ count: Int, _ label: String, _ detail: String?) -> some View {
            GridRow(alignment: .firstTextBaseline) {
                Text(count.formatted())
                    .monospacedDigit()
                    .gridColumnAlignment(.trailing)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
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
