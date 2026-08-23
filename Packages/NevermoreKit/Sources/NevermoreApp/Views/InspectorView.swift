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
            } else if model.selection.count == 1, let id = model.selection.first,
                let record = model.unsubscribeRecord(for: id) {
                // An Unsubscribed row can outlive the sender's mail — the record
                // is all that's left. Without this the inspector claimed nothing
                // was selected while a row sat highlighted next to it.
                recordOnly(record)
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

                Divider()
                forecastSection(group)

                if let listID = group.mailingListID {
                    Divider()
                    mailingListNote(listID)
                }

                Divider()
                methodExplanation(method, sender: name)

                // Above the buttons, because it is an argument about which
                // button to press (TASK-30).
                trustSection(model.trustVerdict(for: group.id))

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
            GridRow {
                stat("Storage", group.storage.summary())
            }
            // Spelled out here, where there is room for a sentence, rather than
            // left to a tooltip: a total that leaves messages out, or counts
            // only what is still in the mailbox, has to say so somewhere a
            // reader will actually see it before acting on the number.
            if let caveat = group.storage.caveat {
                GridRow {
                    Text(caveat)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .gridCellColumns(2)
                }
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

    /// What this sender will cost going forward (TASK-31).
    ///
    /// Placed directly under the statistics, because it is the same four numbers
    /// read forward instead of backward — and it sits above the buttons for the
    /// same reason the trust section does: it is an argument about which one to
    /// press. The backlog in "Messages" is already spent; this is not.
    ///
    /// The caveat rides along with the estimate rather than being tucked into a
    /// tooltip. It is the sentence that keeps the number above it honest, and
    /// this panel is the only place the number appears.
    private func forecastSection(_ group: SenderGroup) -> some View {
        let forecast = SenderForecast.make(for: group, now: .now)
        return HStack(alignment: .top, spacing: 9) {
            Image(systemName: forecastIcon(forecast.basis))
                .font(.system(size: 16)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(forecast.headline).font(.callout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(forecast.detail)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let trendNote = forecast.trendNote {
                    Text(trendNote)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                if forecast.basis == .estimated {
                    Text(SenderForecast.caveat)
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func forecastIcon(_ basis: SenderForecast.Basis) -> String {
        switch basis {
        case .estimated: "chart.line.uptrend.xyaxis"
        case .lapsed: "moon.zzz"
        case .notEnoughHistory: "questionmark.circle"
        }
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

    /// What the app found in this sender's own headers, and what it thinks you
    /// should do about it (TASK-30).
    ///
    /// It advises and never acts: nothing here disables the Unsubscribe button
    /// or presses another one. The evidence is second-hand and sometimes wrong —
    /// a real newsletter fails DMARC through a misconfiguration all the time —
    /// so the user is told what was seen, by whom, and what it does not cover,
    /// and then makes the call.
    @ViewBuilder
    private func trustSection(_ verdict: SenderTrustVerdict) -> some View {
        if !verdict.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                ForEach(verdict.findings) { finding in
                    HStack(alignment: .top, spacing: 9) {
                        Image(
                            systemName: finding.weight == .strong
                                ? "exclamationmark.shield.fill" : "info.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(finding.weight == .strong ? Color.orange : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.title).font(.callout.weight(.semibold))
                            Text(finding.detail)
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }
                if let action = verdict.recommendedAction {
                    Text(
                        "Nevermore suggests \(action.badgeTitle.lowercased()) — or Trash Messages "
                            + "if you don't want the mail either. Unsubscribing would tell this "
                            + "sender the address is live and read, and that cannot be taken back. "
                            + "Nothing here stops you: the button still works.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
            // Both conditions: this sender may have nothing to unsubscribe
            // with, and the collection may be one where unsubscribing is the
            // wrong verb. Same rule as the toolbar and the Actions menu.
            .disabled(!group.canUnsubscribe || !model.can(.unsubscribe))
            .help(model.reason(.unsubscribe) ?? "")

            // …AndAdvance, matching i and d. Plain `ignore`/`requestTrash` empty
            // the selection, so clicking a button here left the inspector
            // showing "No sender selected" while the keyboard moved you on.
            HStack(spacing: 8) {
                Button("Ignore") { model.ignoreAndAdvance() }
                    .frame(maxWidth: .infinity)
                    .disabled(!model.can(.ignore))
                    .help(model.reason(.ignore) ?? "")
                Button("Trash Messages") { model.trashAndAdvance() }
                    .frame(maxWidth: .infinity)
                    .disabled(!model.can(.trash))
                    .help(model.reason(.trash) ?? "")
            }
        }
    }

    // MARK: - Record only (an unsubscribe whose messages are gone)

    private func recordOnly(_ record: MessageStore.UnsubscribeRecord) -> some View {
        let name = record.senderName.isEmpty ? record.senderEmail : record.senderName
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Monogram(text: name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.title3.weight(.semibold)).lineLimit(1)
                    if !record.senderEmail.isEmpty {
                        Text(record.senderEmail).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 1) {
                Text("Unsubscribed").font(.callout.weight(.semibold))
                Text("\(record.outcome.rawValue.capitalized) · \(dateString(record.attemptedAt))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            // Say why this panel offers less than the one for a live sender,
            // rather than leaving the missing buttons to be read as a bug.
            Text("Their messages are no longer in this mailbox, so there's nothing left to unsubscribe from or trash. The record is kept so you know it happened.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Forget Record") { model.forgetRecord(record.groupKey) }
                .frame(maxWidth: .infinity)
        }
        .padding(16)
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
            .disabled(!model.can(.unsubscribe))
            .help(model.reason(.unsubscribe) ?? "")
            HStack(spacing: 8) {
                Button("Ignore") { model.ignoreAndAdvance() }
                    .frame(maxWidth: .infinity)
                    .disabled(!model.can(.ignore))
                    .help(model.reason(.ignore) ?? "")
                Button("Trash Messages") { model.trashAndAdvance() }
                    .frame(maxWidth: .infinity)
                    .disabled(!model.can(.trash))
                    .help(model.reason(.trash) ?? "")
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
