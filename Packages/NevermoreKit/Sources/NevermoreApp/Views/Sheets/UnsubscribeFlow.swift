import SwiftUI
import NevermoreKit

/// The confirm → progress → results flow (design 1f/1g/1h) in one sheet.
struct UnsubscribeFlow: View {
    @Bindable var model: AppModel
    let targets: [AppModel.UnsubTarget]
    /// Skip the confirm step and go straight to unsubscribe-and-delete.
    ///
    /// Set by the ⇧U / ⌘⇧U path, whose whole point is not stopping to click
    /// anything. Distinct from the "Ask before unsubscribing" setting: that's a
    /// standing preference, this is one deliberate keystroke that already said
    /// what it wanted.
    var immediateDelete = false
    /// Escalate a sender to the in-app browser after the automated attempt failed.
    var onManualFallback: (GroupID) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var stage: Stage = .confirm
    @State private var alsoDelete = false
    @State private var currentIndex = 0
    @State private var results: [AppModel.UnsubTarget] = []
    @State private var task: Task<Void, Never>?

    enum Stage { case confirm, progress, results }

    var body: some View {
        Group {
            switch stage {
            case .confirm: confirm
            case .progress: progress
            case .results: resultsView
            }
        }
        .frame(width: 460)
        .padding(24)
        .onAppear {
            // Honor "Ask before unsubscribing": when off, skip the confirm and
            // go straight to the action, deleting if that's the default.
            guard stage == .confirm else { return }
            if immediateDelete {
                start(delete: true)
            } else if !AppSettings.askBeforeUnsubscribe {
                start(delete: AppSettings.deleteIsDefault)
            }
        }
    }

    // MARK: - Confirm (design 1f)

    private var confirm: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "envelope.open")
                    .font(.system(size: 26)).foregroundStyle(Tokens.brandBlue)
                Text("Unsubscribe from \(targets.count) sender\(targets.count == 1 ? "" : "s")?")
                    .font(.title3.weight(.semibold))
            }

            Text(methodBreakdown)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("This can't be undone — the requests go straight to the senders.")
                .font(.callout).foregroundStyle(.secondary)

            if targets.count <= 3 {
                Text(targets.map(\.name).formatted(.list(type: .and)))
                    .font(.callout)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(targets.prefix(5)) { t in
                            HStack(spacing: 8) {
                                MethodIcon(method: t.method)
                                Text(t.name).lineLimit(1)
                                Spacer()
                                Text("\(t.count) msgs").foregroundStyle(.secondary)
                            }.font(.callout)
                        }
                        if targets.count > 5 {
                            Text("and \(targets.count - 5) more…")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }

            if let warning = aliasWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                // The prominent default follows the "Make Delete the default"
                // setting.
                // Both actions carry a key equivalent so the dialog never
                // requires the mouse: Return takes the prominent default, ⇧U
                // always means unsubscribe-and-delete, matching the list.
                if AppSettings.deleteIsDefault {
                    Button("Unsubscribe") { start(delete: false) }
                    Button("Unsubscribe and Delete Messages") { start(delete: true) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Unsubscribe and Delete Messages") { start(delete: true) }
                        .keyboardShortcut("u", modifiers: [.command, .shift])
                    Button("Unsubscribe") { start(delete: false) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var methodBreakdown: String {
        let oneClick = targets.filter { $0.method == .oneClick }.count
        let web = targets.filter { $0.method == .webLink }.count
        let email = targets.filter { $0.method == .email }.count
        var parts: [String] = []
        // "1 use one-click" reads as a typo; agree the verb with the count.
        if oneClick > 0 { parts.append("\(oneClick) use\(oneClick == 1 ? "s" : "") one-click") }
        if web > 0 { parts.append("\(web) will open a web page") }
        if email > 0 { parts.append("\(email) send\(email == 1 ? "s" : "") an email") }
        return parts.joined(separator: ". ") + (parts.isEmpty ? "" : ".")
    }

    private var aliasWarning: String? {
        let unaliased = targets.filter {
            !$0.deliveredTo.isEmpty
                && $0.deliveredTo != model.currentAccount
                && model.sendAsFrom(for: $0.deliveredTo) == nil
        }
        guard let first = unaliased.first else {
            // Positive case: note the send-as that WILL be used.
            if let aliased = targets.first(where: { model.sendAsFrom(for: $0.deliveredTo) != nil }) {
                return "Will send as \(aliased.deliveredTo) — the address these were delivered to."
            }
            return nil
        }
        return "\(unaliased.count) sender\(unaliased.count == 1 ? "" : "s") delivered to \(first.deliveredTo), which has no verified send-as alias — their requests may be rejected."
    }

    // MARK: - Progress (design 1g)

    private var progress: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Unsubscribing…").font(.title3.weight(.semibold))
            ProgressView(value: Double(currentIndex), total: Double(max(targets.count, 1)))
            Text("Sending request to \(currentName) … \(currentIndex + 1) of \(targets.count)")
                .font(.callout)
            Text("Completed senders stay done. Cancel stops before the next sender — never mid-request.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { task?.cancel() }
            }
        }
    }

    private var currentName: String {
        guard currentIndex < targets.count else { return "" }
        return targets[currentIndex].name
    }

    // MARK: - Results (design 1h)

    private var resultsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Count what actually worked. `results.count` includes failures and
            // senders that were never attempted, so a run where everything
            // failed still announced "Unsubscribed from 5 senders".
            Text(
                (confirmed + requested).isEmpty
                    ? "No senders were unsubscribed"
                    : "Unsubscribed from \((confirmed + requested).count) sender\((confirmed + requested).count == 1 ? "" : "s")"
            )
            .font(.title3.weight(.semibold))
            Text("A confirmation from the sender is the only real proof — here's what each one said.")
                .font(.caption).foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    bucket("CONFIRMED", "checkmark.circle.fill", .green, confirmed)
                    bucket("REQUESTED", "clock.badge.questionmark", .orange, requested)
                    bucket("FAILED", "xmark.octagon.fill", .red, failed)
                    // Cancelling left these with no outcome, so they appeared in
                    // no bucket at all — silently missing from the report.
                    bucket("NOT ATTEMPTED", "minus.circle", .secondary, notAttempted)
                }
            }
            .frame(maxHeight: 280)

            HStack {
                let succeeded = confirmed + requested
                if alsoDelete {
                    // Only the senders that actually unsubscribed got deleted,
                    // so don't imply every listed sender's mail is gone.
                    Label(
                        succeeded.isEmpty
                            ? "Nothing was deleted — no unsubscribe succeeded."
                            : "Messages from \(succeeded.count) sender\(succeeded.count == 1 ? "" : "s") were moved to Trash.",
                        systemImage: "trash"
                    )
                    .font(.caption).foregroundStyle(.secondary)
                } else if !succeeded.isEmpty {
                    // Plain unsubscribe — offer to clear the backlog now.
                    Button("Delete Messages from \(succeeded.count) Unsubscribed Sender\(succeeded.count == 1 ? "" : "s")") {
                        let ids = succeeded.map(\.id)
                        Task { await model.deleteMessages(for: ids); dismiss() }
                    }
                }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
            }
        }
    }

    /// Targets the run never reached — only possible after Cancel.
    private var notAttempted: [AppModel.UnsubTarget] {
        results.filter { $0.outcome == nil }
    }

    private var confirmed: [AppModel.UnsubTarget] {
        results.filter { if case .confirmed = $0.outcome { return true } else { return false } }
    }
    private var requested: [AppModel.UnsubTarget] {
        results.filter { if case .requested = $0.outcome { return true } else { return false } }
    }
    private var failed: [AppModel.UnsubTarget] {
        results.filter {
            switch $0.outcome {
            case .failed, .needsManual: return true
            default: return false
            }
        }
    }

    @ViewBuilder
    private func bucket(
        _ title: String, _ symbol: String, _ color: Color, _ items: [AppModel.UnsubTarget]
    ) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("\(title) · \(items.count)", systemImage: symbol)
                    .font(.caption.weight(.semibold)).foregroundStyle(color)
                ForEach(items) { t in
                    HStack {
                        Text(t.name).font(.callout)
                        Spacer()
                        Text(detail(t.outcome)).font(.caption).foregroundStyle(.secondary)
                        if case .failed = t.outcome {
                            // Failed automated → hand off to the browser rather
                            // than retry the same request that just failed.
                            Button("Open in Browser") {
                                dismiss()
                                onManualFallback(t.id)
                            }
                            .controlSize(.small)
                        }
                    }
                }
                if title == "REQUESTED" {
                    Text("Sent. If mail continues, they'll show up under Reappeared.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func detail(_ outcome: UnsubscribeEngine.Outcome?) -> String {
        switch outcome {
        case .confirmed(let d), .requested(let d), .failed(let d): d
        case .needsManual: "no unsubscribe link"
        case nil: ""
        }
    }

    // MARK: - Drive

    private func start(delete: Bool) {
        alsoDelete = delete
        stage = .progress
        task = Task {
            let outcomes = await model.performUnsubscribe(targets) { index, _ in
                currentIndex = index
            }
            results = outcomes
            if delete {
                let ids = outcomes.filter { $0.outcome?.isSuccess == true }.map(\.id)
                await model.deleteMessages(for: ids)
            }
            stage = .results
            // The ⇧U path asked for one keystroke, so don't make it end in a
            // results screen the user has to Escape out of. Close automatically
            // — but only when there's nothing to act on. Anything that failed or
            // needs the browser stays up, because that's the case where the
            // results screen is the whole point.
            if immediateDelete, outcomes.allSatisfy({ $0.outcome?.isSuccess == true }) {
                dismiss()
            }
        }
    }

}
