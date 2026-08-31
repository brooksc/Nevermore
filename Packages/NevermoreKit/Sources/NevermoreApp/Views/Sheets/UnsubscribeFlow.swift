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
    /// Who asked for this. An agent-initiated unsubscribe always shows the
    /// confirm step, whatever the user's standing preference says about their
    /// own keystrokes — see `UnsubscribeConfirmation`.
    var origin: ActionOrigin = .user
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
        // The results stage is wider: an outcome reads "one-click accepted
        // (HTTP 204), unverifiable", which nearly fills a 460pt row on its own
        // and pushes rows into a second line for no reason.
        .frame(width: stage == .results ? 560 : 460)
        .padding(24)
        // Closable with Cmd-W and Escape like any other window — except while
        // requests are in flight, where the Cancel button is the only correct
        // exit because it stops cleanly between senders.
        .overlay {
            Button("") { if stage != .progress { dismiss() } }
                .keyboardShortcut("w", modifiers: .command)
                .hidden()
        }
        .onExitCommand { if stage != .progress { dismiss() } }
        .onAppear {
            // Honor "Ask before unsubscribing": when off, skip the confirm and
            // go straight to the action, deleting if that's the default.
            guard stage == .confirm else { return }
            // An agent-initiated unsubscribe stops here whatever the settings
            // say. The MCP route has already told the agent a human is being
            // asked, and that has to be true in every configuration of the app —
            // including the one where the user turned confirmations off for
            // their own keystrokes.
            // A selection a rule filled has never been looked at — this sheet is
            // where it gets looked at, so neither the setting nor the ⇧U
            // keystroke may skip past it. See `UnsubscribeConfirmation`.
            let fromRule = model.selectionIsSmart
            let mustAsk = UnsubscribeConfirmation.requiresPrompt(
                origin: origin, askBeforeUnsubscribe: AppSettings.askBeforeUnsubscribe,
                selectionWasAutomatic: fromRule)
            if immediateDelete, origin == .user, !fromRule {
                start(delete: true)
            } else if !mustAsk {
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

            if let lists = mailingListWarning {
                Label(lists, systemImage: "person.3")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
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

    /// Mailing lists are a different decision from marketing: leaving one can
    /// mean losing a discussion you're a member of, or notifications you rely
    /// on. Worth naming before the button, not after.
    private var mailingListWarning: String? {
        let lists = targets.compactMap(\.mailingListID)
        guard !lists.isEmpty else { return nil }
        if lists.count == 1, let only = lists.first {
            return "\(only) is a mailing list, not a marketing sender — unsubscribing leaves it."
        }
        return "\(lists.count) of these are mailing lists, not marketing senders — unsubscribing leaves them."
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
            // `UnsubscribeReport` owns the counting and the wording: what
            // "unsubscribed" is allowed to mean, and how to say it next to a
            // failure without the two reading as contradictory.
            Text(report.headline).font(.title3.weight(.semibold))
            Text("A confirmation from the sender is the only real proof — here's what each one said.")
                .font(.caption).foregroundStyle(.secondary)
            // Says how big the report is before the list clips it, so a run of
            // ten is never read as a complete report of the two rows that fit.
            Text(report.contentsLine)
                .font(.caption).foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Actionable buckets first — see `UnsubscribeReport.order`.
                    // "Open in Browser" used to sit below the fold while the
                    // senders needing nothing held the visible region.
                    ForEach(report.buckets, id: \.self) { bucket($0) }
                }
                // Room for the fade below, so it never eats the last row.
                .padding(.bottom, 12)
            }
            // A floor as well as a ceiling, and the floor is the load-bearing
            // half. A ScrollView has no intrinsic height along its scroll axis,
            // so inside a sheet that sizes itself to its content it collapses to
            // a couple of rows and `maxHeight` never comes into it — which is
            // why raising the ceiling from 280 to 420 changed nothing, and why a
            // thirty-sender report still showed one clipped line.
            .frame(minHeight: 260, maxHeight: 420)
            // macOS overlay indicators stay hidden until you scroll, which is
            // exactly the state that needs an indicator.
            .scrollIndicators(.visible)
            // And fade the boundary, so an overflowing report ends in a fade
            // rather than a line of text sliced through its glyphs. A report
            // shorter than the box has nothing down there to fade.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.93),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )

            HStack {
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
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var report: UnsubscribeReport {
        UnsubscribeReport(outcomes: results.map(\.outcome))
    }

    private func targets(in bucket: UnsubscribeReportBucket) -> [AppModel.UnsubTarget] {
        results.filter { UnsubscribeReport.bucket(for: $0.outcome) == bucket }
    }

    /// Confirmed plus requested — the senders the footer may call unsubscribed.
    private var succeeded: [AppModel.UnsubTarget] {
        targets(in: .confirmed) + targets(in: .requested)
    }

    private func color(for bucket: UnsubscribeReportBucket) -> Color {
        switch bucket {
        case .failed: .red
        case .notAttempted: .secondary
        case .requested: .orange
        case .confirmed: .green
        }
    }

    @ViewBuilder
    private func bucket(_ bucket: UnsubscribeReportBucket) -> some View {
        let items = targets(in: bucket)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("\(bucket.title) · \(items.count)", systemImage: bucket.symbolName)
                    .font(.caption.weight(.semibold)).foregroundStyle(color(for: bucket))
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
                if bucket == .requested {
                    Text("Sent. If mail continues, they'll show up under Reappeared.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func detail(_ outcome: UnsubscribeEngine.Outcome?) -> String {
        switch outcome {
        case .confirmed(let d), .requested(let d), .failed(let d): d
        case .needsManual(let reason): reason
        case nil: ""
        }
    }

    // MARK: - Drive

    private func start(delete: Bool) {
        alsoDelete = delete
        stage = .progress
        task = Task {
            // A person is looking at exactly these senders and has just said go
            // — whether by pressing the button, or by the ⇧U keystroke that says
            // it in one move. That is what a review token records, and the batch
            // path below will not run without one. See `ReviewToken`.
            let token = await model.confirmSelection(targets)
            let outcomes = await model.performUnsubscribe(targets, token: token) { index, _ in
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
