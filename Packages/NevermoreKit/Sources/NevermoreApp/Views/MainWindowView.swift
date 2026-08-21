import SwiftUI
import NevermoreKit

/// The main window: sidebar + content, with the inspector as a toggleable panel
/// (spec §3). Uses `.inspector` rather than a third NavigationSplitView column so
/// it can collapse independently.
struct MainWindowView: View {
    @Bindable var model: AppModel
    @State private var unsubTargets: [AppModel.UnsubTarget]?
    @State private var immediateDelete = false
    @State private var manualTarget: AppModel.ManualUnsubscribe?
    /// Keyboard focus for the sender list, so it can be restored after any
    /// sheet closes and single-key triage keeps working without a click.
    @FocusState private var listFocused: Bool

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
        } detail: {
            content
                .inspector(isPresented: $model.showInspector) {
                    InspectorView(model: model, onUnsubscribe: beginUnsubscribe)
                }
        }
        .navigationTitle(model.collection.title)
        .searchable(text: $model.searchText, prompt: "Search")
        .toolbar { toolbar }
        .sheet(item: unsubBinding, onDismiss: refocusList) { targets in
            UnsubscribeFlow(
                model: model, targets: targets.value,
                immediateDelete: targets.immediateDelete,
                onManualFallback: beginManual)
        }
        .sheet(item: $manualTarget, onDismiss: refocusList) { target in
            WebUnsubscribeSheet(model: model, target: target)
        }
        .sheet(isPresented: $model.showShortcuts, onDismiss: refocusList) {
            KeyboardShortcutsView()
        }
        .sheet(isPresented: $model.showHowItWorks, onDismiss: refocusList) {
            HowItWorksSheet { model.showHowItWorks = false }
        }
        .confirmationDialog(
            "Move messages to Trash?",
            isPresented: Binding(
                get: { model.pendingTrash != nil },
                set: { if !$0 { model.pendingTrash = nil } }),
            presenting: model.pendingTrash
        ) { pending in
            Button("Move \(pending.messageCount) Messages to Trash", role: .destructive) {
                model.confirmPendingTrash()
            }
            Button("Cancel", role: .cancel) { model.pendingTrash = nil }
        } message: { pending in
            Text("This trashes \(pending.messageCount) messages from \(pending.senderCount) sender\(pending.senderCount == 1 ? "" : "s"). They stay recoverable in your Trash folder.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .unsubscribeSelected)) { _ in
            beginUnsubscribe(model.selection)
        }
        .onReceive(NotificationCenter.default.publisher(for: .unsubscribeAndDeleteSelected)) { _ in
            beginUnsubscribeAndDelete(model.selection)
        }
        // Clicking a row (selecting it) opens the inspector by default.
        .onChange(of: model.selection) { _, selection in
            if !selection.isEmpty { model.showInspector = true }
        }
    }

    // MARK: - Content region (table or collection-specific view + status bar)

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            if model.isDemoMode {
                DemoBanner(model: model)
                Divider()
            }
            if !model.hasLoadedOnce {
                // Nothing has loaded yet (e.g. behind the Keychain dialog or
                // during first connect) — don't claim any status.
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading your mailbox…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.isSyncing && model.groups.isEmpty {
                // First sync on a new account: the list is empty because
                // nothing has been read yet, not because there's nothing to
                // find. Without this the window claims "You're all caught up"
                // for the several minutes the first sync takes.
                firstSyncState
            } else {
                collectionContent
            }
            Divider()
            StatusBarView(model: model)
        }
    }

    @ViewBuilder
    private var collectionContent: some View {
        Group {
            switch model.collection {
            case .ignored:
                IgnoredCollectionView(
                    model: model,
                    onUnsubscribe: beginUnsubscribe,
                    onUnsubscribeAndDelete: beginUnsubscribeAndDelete,
                    isFocused: $listFocused)
            case .unsubscribed:
                HistoryView(
                    model: model,
                    onUnsubscribe: beginUnsubscribe,
                    onUnsubscribeAndDelete: beginUnsubscribeAndDelete,
                    isFocused: $listFocused)
            case .proposed:
                ProposedCollectionView(
                    model: model,
                    onUnsubscribe: beginUnsubscribe,
                    onUnsubscribeAndDelete: beginUnsubscribeAndDelete,
                    isFocused: $listFocused)
            case .reappeared:
                ReappearedCollectionView(
                    model: model,
                    onUnsubscribe: beginUnsubscribe,
                    onUnsubscribeAndDelete: beginUnsubscribeAndDelete,
                    onManual: beginManual,
                    isFocused: $listFocused)
            default:
                if model.rows.isEmpty {
                    emptyState
                } else {
                    SenderTableView(
                        model: model,
                        onUnsubscribe: beginUnsubscribe,
                        onUnsubscribeAndDelete: beginUnsubscribeAndDelete,
                        onManual: beginManual,
                        isFocused: $listFocused,
                        onDoubleClick: { id in
                            model.selection = [id]
                            model.showInspector = true
                        })
                }
            }
        }
    }

    /// Full-window progress for the very first sync, which scans the whole
    /// mailbox and can run for minutes. Doubles as the first-run explanation —
    /// the user is looking at this screen anyway, so it's the one moment they'll
    /// actually read how the app works.
    private var firstSyncState: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Text("Setting up your mailbox").font(.title3.weight(.semibold))

                if let step = model.syncState.step {
                    Text("Step \(step.number) of 2 · \(step.name)")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let fraction = model.syncState.fractionComplete {
                    HStack(spacing: 10) {
                        ProgressView(value: fraction).frame(width: 220)
                        Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .leading)
                    }
                } else {
                    ProgressView().controlSize(.small)
                }

                if let detail = model.syncState.detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                // A definite width, and no `fixedSize`. Under `maxWidth` alone
                // the text gets no concrete width proposal, wraps to almost one
                // character per line, and reports a ~9000pt ideal height — which
                // NavigationSplitView adopts for *both* columns, pushing the
                // sidebar thousands of points off-screen.
                Text("Only the first sync reads your whole mail history. Later syncs just look at what's new.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: 380)
            }

            Divider().frame(width: 300)

            HowItWorksView(compact: true)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var emptyState: some View {
        if !model.searchText.isEmpty {
            EmptyStateView(
                systemImage: "magnifyingglass",
                title: "No senders match “\(model.searchText)”",
                message: "Search covers names, addresses, and recent subjects.",
                actionTitle: "Clear Search", action: { model.searchText = "" })
        } else if model.collection == .allSenders {
            EmptyStateView(
                systemImage: "checkmark.seal",
                title: "You're all caught up",
                message: "Every sender has been unsubscribed, ignored, or cleaned out.",
                actionTitle: "Show Ignored", action: { model.collection = .ignored })
        } else {
            EmptyStateView(
                systemImage: "tray",
                title: "No newsletters found",
                message: "Nothing in this mailbox carries an unsubscribe header yet.",
                actionTitle: "Sync Now", action: { model.startSync() })
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.startSync()
            } label: { Image(systemName: "arrow.clockwise") }
            .help("Sync now")
            .accessibilityLabel("Sync Now")
            .disabled(model.isSyncing)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                beginUnsubscribe(model.selection)
            } label: { Image(systemName: "envelope.open") }
            // The tooltip carries the reason when the button is disabled: in the
            // other collections these buttons used to stay live and act on a
            // sender that wasn't on screen.
            .help(model.reason(.unsubscribe) ?? "Unsubscribe from selected")
            .accessibilityLabel("Unsubscribe from Selected Senders")
            .disabled(!model.can(.unsubscribe))
        }
        ToolbarItem(placement: .primaryAction) {
            Button { model.ignore(model.selection) } label: {
                Image(systemName: "eye.slash")
            }
            .help(model.reason(.ignore) ?? "Ignore selected")
            .accessibilityLabel("Ignore Selected Senders")
            .disabled(!model.can(.ignore))
        }
        ToolbarItem(placement: .primaryAction) {
            Button { model.requestTrash(model.selection) } label: {
                Image(systemName: "trash")
            }
            .help(model.reason(.trash) ?? "Trash messages from selected")
            .accessibilityLabel("Move Messages to Trash")
            .disabled(!model.can(.trash))
        }
        ToolbarItem(placement: .primaryAction) {
            Button { model.showInspector.toggle() } label: {
                Image(systemName: "sidebar.trailing")
            }
            .help("Toggle inspector")
            .accessibilityLabel("Toggle Inspector")
        }
    }

    // MARK: - Unsubscribe flow presentation

    /// Hand keyboard focus back to the list after a sheet closes.
    ///
    /// A beat late on purpose: setting focus in the same turn the sheet is torn
    /// down gets swallowed, because the window is still resigning the sheet's
    /// first responder.
    private func refocusList() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { listFocused = true }
    }

    private func beginUnsubscribe(_ ids: Set<GroupID>) {
        let plan = model.plan(for: ids)
        guard !plan.isEmpty else { return }
        immediateDelete = false
        unsubTargets = plan
    }

    /// Unsubscribe and trash the messages in one keystroke, no confirmation.
    /// Recoverable: the messages go to the provider's Trash, and ⌘Z restores
    /// them for batches under the undo limit.
    private func beginUnsubscribeAndDelete(_ ids: Set<GroupID>) {
        let plan = model.plan(for: ids)
        guard !plan.isEmpty else { return }
        immediateDelete = true
        unsubTargets = plan
    }

    /// Open the in-app browser for a manual unsubscribe of a single sender.
    private func beginManual(_ id: GroupID) {
        manualTarget = model.manualTarget(for: id)
    }

    /// Wrap the target array so `.sheet(item:)` can present it.
    private var unsubBinding: Binding<IdentifiedTargets?> {
        Binding(
            get: {
                unsubTargets.map { IdentifiedTargets($0, immediateDelete: immediateDelete) }
            },
            set: { unsubTargets = $0?.value })
    }

    struct IdentifiedTargets: Identifiable {
        let value: [AppModel.UnsubTarget]
        let immediateDelete: Bool
        /// Include the mode in the identity: presenting the same senders once
        /// with a confirm and once without must count as two different sheets.
        var id: String {
            value.map { $0.id.storageKey }.joined() + (immediateDelete ? "|delete" : "")
        }
        init(_ value: [AppModel.UnsubTarget], immediateDelete: Bool = false) {
            self.value = value
            self.immediateDelete = immediateDelete
        }
    }
}
