import SwiftUI
import MailScrubKit

/// The Unsubscribed history log (design: Unsubscribed collection).
///
/// Reads the durable `unsubscribeHistory` table rather than message-derived
/// groups, so a record stays here after the sender's messages are deleted. Each
/// row keeps enough metadata to identify the sender and — where the sender
/// published one — a link to their preferences page for re-subscribing.
struct HistoryView: View {
    @Bindable var model: AppModel

    var body: some View {
        let records = model.unsubscribedRecords
        if records.isEmpty {
            EmptyStateView(
                systemImage: "checkmark.circle",
                title: "No unsubscribes yet",
                message: "Senders you unsubscribe from are logged here — even after you delete their messages.")
        } else {
            VStack(spacing: 0) {
                Text("A record of every sender you've unsubscribed from. Kept even after their messages are deleted. Use the link to reach a sender's preferences if you unsubscribed by accident.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary.opacity(0.4))
                List(records) { record in
                    row(record)
                }
            }
        }
    }

    private func row(_ record: MessageStore.UnsubscribeRecord) -> some View {
        HStack(spacing: 12) {
            Monogram(text: displayName(record), diameter: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName(record)).fontWeight(.medium).lineLimit(1)
                if !record.senderEmail.isEmpty {
                    Text(record.senderEmail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    outcomeBadge(record.outcome)
                    Text("· \(relativeDate(record.attemptedAt))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()

            if let urlString = record.url, let url = URL(string: urlString) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Manage", systemImage: "arrow.up.forward.square")
                }
                .help("Open the sender's preferences page — where you can re-subscribe if this was a mistake:\n\(urlString)")
                .controlSize(.small)
            }
            if model.canOpenInWebmail {
                Button {
                    model.openInWebmail(senderAddress: record.senderEmail)
                } label: {
                    Label(model.currentProvider.displayName, systemImage: "magnifyingglass")
                }
                .help("Find this sender in \(model.currentProvider.displayName)")
                .controlSize(.small)
                .disabled(record.senderEmail.isEmpty)
            }

            Button("Forget") { model.forgetRecord(record.groupKey) }
                .help("Remove this record from history")
                .controlSize(.small)
        }
        .padding(.vertical, 2)
        .contextMenu {
            if let urlString = record.url, let url = URL(string: urlString) {
                Button("Open Preferences Page") { NSWorkspace.shared.open(url) }
                Button("Copy Preferences URL") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(urlString, forType: .string)
                }
            }
            if !record.senderEmail.isEmpty {
                if model.canOpenInWebmail {
                    Button("View in \(model.currentProvider.displayName)") {
                        model.openInWebmail(senderAddress: record.senderEmail)
                    }
                }
                Button("Copy Sender Address") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(record.senderEmail, forType: .string)
                }
            }
            Divider()
            Button("Forget Record") { model.forgetRecord(record.groupKey) }
        }
    }

    private func outcomeBadge(_ outcome: MessageStore.Outcome) -> some View {
        switch outcome {
        case .confirmed:
            return Label("Confirmed", systemImage: "checkmark.seal.fill")
                .font(.caption).foregroundStyle(.green)
        case .requested, .failed:
            return Label("Requested", systemImage: "clock.badge.questionmark")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    /// Prefer the saved name; fall back to the address, then the group key.
    private func displayName(_ record: MessageStore.UnsubscribeRecord) -> String {
        if !record.senderName.isEmpty { return record.senderName }
        if !record.senderEmail.isEmpty { return record.senderEmail }
        return GroupID(storageKey: record.groupKey)?.key ?? record.groupKey
    }

    private func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return "Unsubscribed \(f.localizedString(for: date, relativeTo: Date()))"
    }
}
