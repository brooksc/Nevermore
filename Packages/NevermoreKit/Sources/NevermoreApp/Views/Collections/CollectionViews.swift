import SwiftUI
import NevermoreKit

/// Ignored senders (design 1k). A local-only list; nothing is touched on the server.
struct IgnoredCollectionView: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.rows.isEmpty {
            EmptyStateView(
                systemImage: "eye.slash",
                title: "No ignored senders",
                message: "Senders you ignore are hidden here — never touched on the server.")
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
            EmptyStateView(
                systemImage: "checkmark.shield",
                title: "Everyone honored your unsubscribes",
                message: "No sender has mailed you since you unsubscribed.")
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
                    ForEach(model.rows) { row in
                        HStack(spacing: 12) {
                            MethodIcon(method: row.method, size: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name).fontWeight(.semibold).lineLimit(1)
                                Text(row.email).font(.caption).foregroundStyle(.secondary)
                                Text(row.latestSubject).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                // row.count is the sender's whole history, which
                                // is not what "since unsubscribing" means — it
                                // read as though a sender had sent hundreds of
                                // messages since you unsubscribed last week.
                                Text("\(model.messagesSinceUnsubscribe(row.id)) new since unsubscribing")
                                    .font(.caption).foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    // Escalate to the browser — retrying the same
                                    // automated method that already failed is pointless.
                                    Button("Unsubscribe in Browser") { onManual(row.id) }
                                        .buttonStyle(.borderedProminent)
                                    Button("Trash and Ignore") {
                                        Task { await model.trashAndIgnore(row.id) }
                                    }
                                    Button("Forget Record") { model.forget([row.id]) }
                                }
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
}
