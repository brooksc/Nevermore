import SwiftUI
import MailScrubKit

/// The sender table — native multi-selection, no checkbox column (spec §5).
struct SenderTableView: View {
    @Bindable var model: AppModel
    @Binding var sortOrder: [KeyPathComparator<SenderRow>]
    var onUnsubscribe: (Set<GroupID>) -> Void
    var onManual: (GroupID) -> Void
    var onDoubleClick: (GroupID) -> Void

    var body: some View {
        Table(rows, selection: $model.selection, sortOrder: $sortOrder) {
            TableColumn("Sender", value: \.name) { row in
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.name)
                        .fontWeight(row.unreadPercent > 0 ? .semibold : .regular)
                        .lineLimit(1)
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

            TableColumn("") { row in
                MethodIcon(method: row.method)
                    .frame(maxWidth: .infinity)
            }
            .width(44)
        }
        .contextMenu(forSelectionType: GroupID.self) { ids in
            rowMenu(ids)
        } primaryAction: { ids in
            if let id = ids.first { onDoubleClick(id) }
        }
    }

    private var rows: [SenderRow] {
        model.rows.sorted(using: sortOrder)
    }

    @ViewBuilder
    private func rowMenu(_ ids: Set<GroupID>) -> some View {
        let targets = ids.isEmpty ? model.selection : ids
        Button("Unsubscribe") { onUnsubscribe(targets) }
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
        Divider()
        Button("View in Gmail") { openGmail(targets) }
        Button("Copy Sender Address") { copyAddress(targets) }
    }

    private func openGmail(_ ids: Set<GroupID>) {
        for id in ids {
            guard let email = model.group(for: id)?.latest?.sender.address else { continue }
            if let url = URL(string: "https://mail.google.com/mail/u/0/#search/from:\(email)") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func copyAddress(_ ids: Set<GroupID>) {
        let addresses = ids.compactMap { model.group(for: $0)?.latest?.sender.address }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(addresses.joined(separator: ", "), forType: .string)
    }
}
