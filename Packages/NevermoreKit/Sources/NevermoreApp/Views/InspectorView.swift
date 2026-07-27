import SwiftUI
import NevermoreKit

/// Selected-sender detail (design 1c, spec §6). Shows an aggregate summary when
/// more than one sender is selected.
struct InspectorView: View {
    @Bindable var model: AppModel
    var onUnsubscribe: (Set<GroupID>) -> Void
    @State private var copiedEmail = false

    var body: some View {
        Group {
            if model.selection.count == 1, let id = model.selection.first,
                let group = model.group(for: id) {
                single(group)
            } else if model.selection.count > 1 {
                aggregate
            } else {
                EmptyStateView(
                    systemImage: "sidebar.right",
                    title: "No sender selected",
                    message: "Select a sender to see details and actions.")
            }
        }
        .frame(
            minWidth: Tokens.Metric.inspectorMin,
            idealWidth: Tokens.Metric.inspectorWidth,
            maxWidth: Tokens.Metric.inspectorMax)
    }

    // MARK: - Single sender

    private func single(_ group: SenderGroup) -> some View {
        let method = SenderRow.method(for: group)
        let name = group.displayName
        let email = group.latest?.sender.address ?? group.id.key
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Monogram(text: name)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.title3.weight(.semibold)).lineLimit(1)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(email, forType: .string)
                            // Copying is otherwise completely silent — nothing
                            // on screen changes, so it reads as a dead control.
                            copiedEmail = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                copiedEmail = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(copiedEmail ? "Copied" : email)
                                    .font(.caption)
                                    .foregroundStyle(copiedEmail ? Color.green : .secondary)
                                Image(systemName: copiedEmail ? "checkmark" : "doc.on.doc")
                                    .font(.caption2)
                                    .foregroundStyle(copiedEmail ? Color.green : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Copy \(email)")
                    }
                }

                Divider()
                statistics(group)

                if let listID = group.mailingListID {
                    Divider()
                    mailingListNote(listID)
                }

                Divider()
                methodExplanation(method, sender: name)

                historySection(group)

                // Actions sit directly under the sender summary — the primary
                // reason the panel is open — above the secondary message list.
                Divider()
                actions(for: group)

                Divider()
                recentMessages(group)
            }
            .padding(16)
        }
    }

    private func statistics(_ group: SenderGroup) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                stat("Messages", "\(group.total)")
                stat("Unread", "\(Int(group.unreadPercent.rounded()))%")
            }
            GridRow {
                stat("First seen", dateString(group.messages.map(\.receivedAt).min()))
                stat("Last received", dateString(group.newest))
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A List-ID means this is a mailing list or notification stream, not a
    /// marketing blast — a different decision, so say so before the buttons.
    private func mailingListNote(_ listID: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "person.3")
                .font(.system(size: 16)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Mailing list").font(.callout.weight(.semibold))
                Text("Unsubscribing leaves the list \u{201C}\(listID)\u{201D}, not just a promotion.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func methodExplanation(_ method: UnsubscribeMethod, sender: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            MethodIcon(method: method, size: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(method.inspectorTitle).font(.callout.weight(.semibold))
                Text(method.inspectorDetail(sender: sender))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func historySection(_ group: SenderGroup) -> some View {
        if let record = model.unsubscribeRecord(for: group.id) {
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Previously unsubscribed").font(.callout.weight(.semibold))
                    Text("\(record.outcome.rawValue.capitalized) · \(dateString(record.attemptedAt))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Forget") { model.forget([group.id]) }
                    .controlSize(.small)
            }
        }
    }

    private func recentMessages(_ group: SenderGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RECENT MESSAGES")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(group.messages.prefix(10).enumerated()), id: \.offset) { _, message in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(message.subject.isEmpty ? "(no subject)" : message.subject)
                        .font(.caption).lineLimit(1)
                    Spacer()
                    Text(SenderRow(group: SenderGroup(id: group.id, messages: [message]),
                            priorOutcome: nil).relativeAge)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func actions(for group: SenderGroup) -> some View {
        VStack(spacing: 8) {
            Button {
                onUnsubscribe([group.id])
            } label: {
                Text("Unsubscribe").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!group.canUnsubscribe)

            // …AndAdvance, matching i and d. Plain `ignore`/`requestTrash` empty
            // the selection, so clicking a button here left the inspector
            // showing "No sender selected" while the keyboard moved you on.
            HStack(spacing: 8) {
                Button("Ignore") { model.ignoreAndAdvance() }
                    .frame(maxWidth: .infinity)
                Button("Trash Messages") { model.trashAndAdvance() }
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Aggregate

    private var aggregate: some View {
        let groups = model.selectedGroups
        let total = groups.reduce(0) { $0 + $1.total }
        let allOneClick = groups.allSatisfy { SenderRow.method(for: $0) == .oneClick }
        return VStack(alignment: .leading, spacing: 16) {
            Text("\(groups.count) senders selected")
                .font(.title3.weight(.semibold))
            Text("\(total) messages" + (allOneClick ? " · all support one-click" : ""))
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button {
                onUnsubscribe(model.selection)
            } label: {
                Text("Unsubscribe").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            HStack(spacing: 8) {
                Button("Ignore") { model.ignoreAndAdvance() }
                    .frame(maxWidth: .infinity)
                Button("Trash Messages") { model.trashAndAdvance() }
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
    }

    // MARK: - Helpers

    private func dateString(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }
}
