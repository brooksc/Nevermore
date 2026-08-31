import SwiftUI
import NevermoreKit

/// The sender table — native multi-selection, no checkbox column (spec §5).
struct SenderTableView: View {
    @Bindable var model: AppModel
    var onUnsubscribe: (Set<GroupID>) -> Void
    var onUnsubscribeAndDelete: (Set<GroupID>) -> Void
    var onManual: (GroupID) -> Void
    /// Owned by the window so focus can be handed back after a sheet closes —
    /// otherwise dismissing one leaves nothing focused and the single-key
    /// shortcuts stop responding until the user clicks a row.
    @FocusState.Binding var isFocused: Bool
    var onDoubleClick: (GroupID) -> Void

    var body: some View {
        Table(rows, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn("Sender", value: \.name) { row in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(row.name)
                            .fontWeight(row.unreadPercent > 0 ? .semibold : .regular)
                            .lineLimit(1)
                        // A sender the user opened and could not finish stays in
                        // this list, so it needs to say it has already been
                        // tried — otherwise the only way to tell it apart from
                        // one never touched is to open its page again (TASK-57).
                        if row.priorOutcome == .failed {
                            Text("Tried")
                                .font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.orange.opacity(0.2), in: Capsule())
                                .foregroundStyle(.secondary)
                                .help("You opened this sender's page and couldn't finish "
                                    + "unsubscribing. They are still subscribed.")
                        }
                    }
                    Text(row.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 2)
            }
            .width(min: 180, ideal: 240)

            TableColumn("Latest Subject") { row in
                Text(row.latestSubject)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            TableColumn("Messages", value: \.count) { row in
                Text("\(row.count)")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(80)

            // Sorted on measured bytes, shown as a rounded size — and shown as
            // "Unknown" rather than "0 bytes" where nothing is measured, since
            // zero would read as "this sender costs you nothing" (TASK-29).
            TableColumn("Size", value: \.storageBytes) { row in
                Text(row.storage.summary())
                    .monospacedDigit()
                    .foregroundStyle(row.storage.isUnknown ? .tertiary : .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .help(row.storage.caveat ?? "")
            }
            .width(110)

            TableColumn("Unread", value: \.unreadPercent) { row in
                UnreadBar(percent: row.unreadPercent)
            }
            .width(120)

            TableColumn("Last Received", value: \.lastReceived) { row in
                Text(row.relativeAge)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .width(110)

            // Named, not blank: an unlabelled glyph column reads as decoration,
            // so nobody thinks to hover it for the tooltip that's already there.
            // Help ▸ How Nevermore Works carries the full legend.
            TableColumn("Unsubscribe") { row in
                MethodIcon(method: row.method)
                    .frame(maxWidth: .infinity)
            }
            .width(88)
        }
        .focused($isFocused)
        .contextMenu(forSelectionType: GroupID.self) { ids in
            rowMenu(ids)
        } primaryAction: { ids in
            if let id = ids.first { onDoubleClick(id) }
        }
        // The one triage keyboard, shared with the other collections.
        .selectionKeyboard(
            model: model,
            onUnsubscribe: onUnsubscribe,
            onUnsubscribeAndDelete: onUnsubscribeAndDelete)
    }

    private var rows: [SenderRow] {
        model.visibleRows
    }

    @ViewBuilder
    private func rowMenu(_ ids: Set<GroupID>) -> some View {
        let targets = ids.isEmpty ? model.selection : ids
        Button("View Latest Message") { model.viewLatestMessage() }
            .disabled(targets.count != 1)
        Divider()
        Button("Unsubscribe") { onUnsubscribe(targets) }
        Button("Unsubscribe and Delete Messages") { onUnsubscribeAndDelete(targets) }
        if targets.count == 1, let id = targets.first {
            Button("Unsubscribe in Browser…") { onManual(id) }
        }
        Divider()
        Button("Ignore Sender") { model.ignore(targets) }
        Button("Move Messages to Trash…") { model.requestTrash(targets) }
        if targets.count == 1, let id = targets.first {
            Divider()
            // Correct the automatic grouping: split an over-merged domain into
            // per-sender rows, or keep an over-split sender as one group.
            if id.kind == .domain {
                Button("Split by Address") { model.splitByAddress(id) }
            } else {
                Button("Keep as One Group") { model.keepAsOneGroup(id) }
            }
        }
        if model.currentProvider.webSearchURL(fromSender: "x@x") != nil {
            Divider()
            Button("View in \(model.currentProvider.displayName)") { openInWebmail(targets) }
        } else {
            Divider()
        }
        Button("Copy Sender Address") { copyAddress(targets) }
    }

    private func openInWebmail(_ ids: Set<GroupID>) {
        for id in ids {
            guard let email = model.group(for: id)?.latest?.sender.address else { continue }
            model.openInWebmail(senderAddress: email)
        }
    }

    private func copyAddress(_ ids: Set<GroupID>) {
        let addresses = ids.compactMap { model.group(for: $0)?.latest?.sender.address }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(addresses.joined(separator: ", "), forType: .string)
    }
}
