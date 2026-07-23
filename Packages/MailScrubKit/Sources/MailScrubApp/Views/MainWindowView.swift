import SwiftUI
import MailScrubKit

/// The main window: sidebar + content, with the inspector as a toggleable panel
/// (spec §3). Uses `.inspector` rather than a third NavigationSplitView column so
/// it can collapse independently.
struct MainWindowView: View {
    @Bindable var model: AppModel
    @State private var sortOrder = [KeyPathComparator(\SenderRow.lastReceived, order: .reverse)]
    @State private var unsubTargets: [AppModel.UnsubTarget]?
    @State private var manualTarget: AppModel.ManualUnsubscribe?

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
        .sheet(item: unsubBinding) { targets in
            UnsubscribeFlow(model: model, targets: targets.value, onManualFallback: beginManual)
        }
        .sheet(item: $manualTarget) { target in
            WebUnsubscribeSheet(model: model, target: target)
        }
        .onReceive(NotificationCenter.default.publisher(for: .unsubscribeSelected)) { _ in
            beginUnsubscribe(model.selection)
        }
        // Clicking a row (selecting it) opens the inspector by default.
        .onChange(of: model.selection) { _, selection in
            if !selection.isEmpty { model.showInspector = true }
        }
        .task { await model.start() }
    }

    // MARK: - Content region (table or collection-specific view + status bar)

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            switch model.collection {
            case .ignored:
                IgnoredCollectionView(model: model)
            case .unsubscribed:
                HistoryView(model: model)
            case .reappeared:
                ReappearedCollectionView(
                    model: model, onUnsubscribe: beginUnsubscribe, onManual: beginManual)
            default:
                if model.rows.isEmpty {
                    emptyState
                } else {
                    SenderTableView(
                        model: model,
                        sortOrder: $sortOrder,
                        onUnsubscribe: beginUnsubscribe,
                        onManual: beginManual,
                        onDoubleClick: { id in
                            model.selection = [id]
                            model.showInspector = true
                        })
                }
            }
            Divider()
            StatusBarView(model: model)
        }
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
                actionTitle: "Sync Now", action: { Task { await model.sync() } })
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await model.sync() }
            } label: { Image(systemName: "arrow.clockwise") }
            .help("Sync now")
            .disabled(isSyncing)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                beginUnsubscribe(model.selection)
            } label: { Image(systemName: "envelope.open") }
            .help("Unsubscribe from selected")
            .disabled(model.selection.isEmpty)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { model.ignore(model.selection) } label: {
                Image(systemName: "eye.slash")
            }
            .help("Ignore selected")
            .disabled(model.selection.isEmpty)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { Task { await model.trash(model.selection) } } label: {
                Image(systemName: "trash")
            }
            .help("Trash messages from selected")
            .disabled(model.selection.isEmpty)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { model.showInspector.toggle() } label: {
                Image(systemName: "sidebar.trailing")
            }
            .help("Toggle inspector")
        }
    }

    private var isSyncing: Bool {
        if case .idle = model.syncState { return false }
        if case .failed = model.syncState { return false }
        return true
    }

    // MARK: - Unsubscribe flow presentation

    private func beginUnsubscribe(_ ids: Set<GroupID>) {
        let plan = model.plan(for: ids)
        guard !plan.isEmpty else { return }
        unsubTargets = plan
    }

    /// Open the in-app browser for a manual unsubscribe of a single sender.
    private func beginManual(_ id: GroupID) {
        manualTarget = model.manualTarget(for: id)
    }

    /// Wrap the target array so `.sheet(item:)` can present it.
    private var unsubBinding: Binding<IdentifiedTargets?> {
        Binding(
            get: { unsubTargets.map(IdentifiedTargets.init) },
            set: { unsubTargets = $0?.value })
    }

    struct IdentifiedTargets: Identifiable {
        let value: [AppModel.UnsubTarget]
        var id: String { value.map { $0.id.storageKey }.joined() }
        init(_ value: [AppModel.UnsubTarget]) { self.value = value }
    }
}
