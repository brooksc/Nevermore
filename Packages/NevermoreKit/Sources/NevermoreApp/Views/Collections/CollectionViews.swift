import SwiftUI
import NevermoreKit

/// Ignored senders (design 1k). A local-only list; nothing is touched on the server.
struct IgnoredCollectionView: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.rows.isEmpty {
            // Distinguish "you have none" from "none match your search" — the
            // search field stays live here, so the old copy claimed you had no
            // ignored senders whenever a query missed.
            if !model.searchText.isEmpty {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "No ignored senders match \u{201C}\(model.searchText)\u{201D}",
                    message: "Clear the search to see everything you've ignored.",
                    actionTitle: "Clear Search", action: { model.searchText = "" })
            } else {
                EmptyStateView(
                    systemImage: "eye.slash",
                    title: "No ignored senders",
                    message: "Senders you ignore are hidden here — never touched on the server.")
            }
        } else {
            VStack(spacing: 0) {
                banner("Hidden from your lists on this Mac only — nothing is changed on the server. Right-click to unignore (⇧⌘I).")
                List {
                    ForEach(model.rows) { row in
                        HStack(spacing: 12) {
                            Monogram(text: row.name, diameter: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.name).fontWeight(.medium).lineLimit(1)
                                Text(row.email).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(row.count) msgs").font(.callout).foregroundStyle(.secondary)
                            Button("Unignore") { model.unignore([row.id]) }
                                .controlSize(.small)
                        }
                        .padding(.vertical, 2)
                        .contextMenu {
                            Button("Unignore") { model.unignore([row.id]) }
                        }
                    }
                }
            }
        }
    }

    private func banner(_ text: String) -> some View {
        Text(text)
            .font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.quaternary.opacity(0.4))
    }
}

/// Reappeared senders (design 1j): banner + per-row actions. Not a launch modal.
struct ReappearedCollectionView: View {
    @Bindable var model: AppModel
    var onUnsubscribe: (Set<GroupID>) -> Void
    var onManual: (GroupID) -> Void

    var body: some View {
        if model.rows.isEmpty {
            if !model.searchText.isEmpty {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "No reappeared senders match \u{201C}\(model.searchText)\u{201D}",
                    message: "Clear the search to see everyone who kept emailing.",
                    actionTitle: "Clear Search", action: { model.searchText = "" })
            } else {
                EmptyStateView(
                    systemImage: "checkmark.shield",
                    title: "Everyone honored your unsubscribes",
                    message: "No sender has mailed you since you unsubscribed.")
            }
        } else {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("These senders kept emailing after you unsubscribed — the automated request didn't stick. Finish it by hand in the browser, or trash and ignore them for good.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))

                List {
                    ForEach(model.rows) { sender in
                        row(sender)
                    }
                }
            }
        }
    }

    /// Extracted from `body`: inlined, the added count call tipped the
    /// expression past what the type checker would solve, and it silently fell
    /// back to `ForEach(0..<n)` — reporting the row as an Int.
    private func row(_ sender: SenderRow) -> some View {
        // row.count is the sender's whole history, which is not what "since
        // unsubscribing" means — it read as though a sender had sent hundreds
        // of messages since you unsubscribed last week.
        let since = model.messagesSinceUnsubscribe(sender.id)
        return HStack(spacing: 12) {
            MethodIcon(method: sender.method, size: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(sender.name).fontWeight(.semibold).lineLimit(1)
                Text(sender.email).font(.caption).foregroundStyle(.secondary)
                Text(sender.latestSubject).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text("\(since) new since unsubscribing")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    // Escalate to the browser — retrying the same automated
                    // method that already failed is pointless.
                    Button("Unsubscribe in Browser") { onManual(sender.id) }
                        .buttonStyle(.borderedProminent)
                    Button("Trash and Ignore") {
                        Task { await model.trashAndIgnore(sender.id) }
                    }
                    Button("Forget Record") { model.forget([sender.id]) }
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
