import Foundation
import MailScrubKit
import Observation
import UserNotifications

/// The single source of UI truth. Bridges MailScrubKit's actor backend and
/// GRDB store to SwiftUI, on the main actor.
@MainActor
@Observable
final class AppModel {
    // MARK: - Account / session

    private(set) var accounts: [String]
    private(set) var currentAccount: String?

    /// Set when a *registered* account's password can't be read from the
    /// Keychain — e.g. after an app update signed with a rotated certificate,
    /// moving the app, or restoring from backup. The UI explains this and asks
    /// the user to re-enter, rather than showing a silent empty window.
    private(set) var reauthAccount: String?

    /// Show the add/re-auth sheet when there's no account yet, or a saved one
    /// couldn't be unlocked.
    var needsOnboarding: Bool { currentAccount == nil || reauthAccount != nil }

    private let registry = AccountRegistry.shared
    private var store: MessageStore?
    private var backend: IMAPBackend?

    // MARK: - Data

    private(set) var groups: [SenderGroup] = []
    private var ignoredKeys: Set<String> = []
    private var history: [String: MessageStore.UnsubscribeRecord] = [:]
    private(set) var sendAsAddresses: [String] = []

    // MARK: - UI state

    var collection: Collection = .allSenders
    var selection: Set<GroupID> = []
    var searchText: String = ""
    var showInspector = false

    enum SyncState: Equatable {
        case idle
        case discovering(window: Int, of: Int, found: Int)
        case fetching(done: Int, of: Int)
        case failed(String)
    }
    private(set) var syncState: SyncState = .idle
    private(set) var lastSyncedAt: Date?

    /// Transient status-bar message with an optional undo, mirroring the design.
    struct Toast: Equatable { var message: String; var undo: UndoAction? }
    struct UndoAction: Equatable { let id = UUID(); var label: String }
    private(set) var toast: Toast?
    /// Whether the current toast offers an undo (drives ⌘Z / the Undo menu item).
    var canUndo: Bool { toast?.undo != nil }
    private var pendingUndo: (@MainActor () async -> Void)?

    init() {
        accounts = registry.accounts()
        currentAccount = accounts.first
    }

    // MARK: - Session lifecycle

    func start() async {
        guard let account = currentAccount else { return }
        await open(account: account)
    }

    private func open(account: String) async {
        guard let password = Keychain.appPassword(for: account) else {
            // The account is registered but its Keychain item is unreadable.
            // Keep it selected and flag re-auth so the UI can explain why.
            Log.app.event("keychain read failed for \(account) — needs re-auth")
            reauthAccount = account
            return
        }
        reauthAccount = nil
        do {
            store = try MessageStore(path: registry.databasePath(for: account))
        } catch {
            Log.app.problem("could not open database: \(error.localizedDescription)")
            syncState = .failed("Could not open local database: \(error.localizedDescription)")
            return
        }
        backend = IMAPBackend(address: account, appPassword: password)
        currentAccount = account
        Log.app.event("opened account \(account)")
        await reloadFromStore()
        if AppSettings.syncOnLaunch { await sync() }
        startBackgroundSync()
    }

    // MARK: - Background sync

    private var backgroundSyncTask: Task<Void, Never>?

    /// Periodically re-syncs per the Settings interval. Re-reads the interval
    /// each loop so changing it (or turning it off) takes effect without relaunch.
    private func startBackgroundSync() {
        backgroundSyncTask?.cancel()
        backgroundSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let seconds = AppSettings.backgroundIntervalSeconds else {
                    try? await Task.sleep(for: .seconds(300))  // "off" — re-check later
                    continue
                }
                try? await Task.sleep(for: .seconds(seconds))
                if Task.isCancelled { break }
                Log.sync.detail("background sync tick")
                await self?.sync()
            }
        }
    }

    private func stopBackgroundSync() {
        backgroundSyncTask?.cancel()
        backgroundSyncTask = nil
    }

    // MARK: - Onboarding

    /// Validate credentials by authenticating, then persist and open. Retries a
    /// couple of times on transient failures (Gmail throttling / flaky network)
    /// so a bad moment doesn't look like a wrong password; a genuine auth failure
    /// is reported immediately.
    func addAccount(email: String, appPassword: String) async throws {
        let candidate = IMAPBackend(address: email, appPassword: appPassword)
        defer { Task { await candidate.disconnect() } }

        var lastError: Error?
        for attempt in 1...3 {
            do {
                try await candidate.verifyConnection()
                lastError = nil
                break
            } catch MailBackendError.authenticationFailed(let detail) {
                throw MailBackendError.authenticationFailed(detail)  // won't self-fix
            } catch {
                lastError = error
                await candidate.disconnect()
                if attempt < 3 { try? await Task.sleep(for: .seconds(Double(attempt) * 2)) }
            }
        }
        if let lastError { throw lastError }

        try Keychain.store(appPassword: appPassword, for: email)
        registry.add(email)
        accounts = registry.accounts()
        await open(account: email)
    }

    /// Set by the UI to request the add-account sheet (a second account, while
    /// one is already open). RootView presents onboarding in response.
    var wantsToAddAccount = false

    /// Switch the active account, tearing down the current session and opening
    /// the other one (which may prompt re-auth if its Keychain item is missing).
    func switchAccount(_ email: String) async {
        guard email != currentAccount, accounts.contains(email) else { return }
        stopBackgroundSync()
        store = nil
        backend = nil
        groups = []
        selection = []
        currentAccount = email
        await open(account: email)
    }

    func removeAccount(_ email: String) async {
        registry.remove(email)
        accounts = registry.accounts()
        if currentAccount == email {
            stopBackgroundSync()
            currentAccount = accounts.first
            store = nil
            backend = nil
            groups = []
            if let next = currentAccount { await open(account: next) }
        }
    }

    // MARK: - Loading & sync

    private(set) var groupingRules: [String: Grouping.Rule] = [:]

    private func reloadFromStore() async {
        guard let store else { return }
        do {
            let messages = try store.allMessages()
            groupingRules = store.groupingRules()
            groups = Grouping(rules: groupingRules).group(messages)
            ignoredKeys = try store.ignoredGroupKeys()
            history = try store.unsubscribeHistory()
        } catch {
            syncState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Grouping corrections (Merge / Split)

    /// Force a sender's registrable domain to split into per-address groups.
    func splitByAddress(_ id: GroupID) {
        applyRule(.split, forDomainOf: id)
    }

    /// Force a sender's registrable domain to stay one merged group.
    func keepAsOneGroup(_ id: GroupID) {
        applyRule(.merge, forDomainOf: id)
    }

    private func applyRule(_ rule: Grouping.Rule, forDomainOf id: GroupID) {
        guard let store, let domain = domain(of: id) else { return }
        groupingRules[domain] = rule
        store.setGroupingRules(groupingRules)
        Log.app.event("grouping rule for \(domain): \(rule.rawValue)")
        selection = []
        Task { await reloadFromStore() }
    }

    func resetGroupingRules() {
        guard let store else { return }
        groupingRules = [:]
        store.setGroupingRules([:])
        Task { await reloadFromStore() }
    }

    /// The registrable domain a group belongs to (the group key for a domain
    /// group, or the address's host reduced to eTLD+1 for an address group).
    private func domain(of id: GroupID) -> String? {
        switch id.kind {
        case .domain: return id.key
        case .address:
            let host = id.key.split(separator: "@").last.map(String.init) ?? ""
            return RegistrableDomain.of(host)
        }
    }

    func sync() async {
        guard let backend, let store else { return }

        // A cached IMAP connection that has errored (Gmail throttling, a dropped
        // socket, a mid-stream server error) stays poisoned and keeps failing.
        // Retry a couple of times, dropping the connection between attempts so
        // the next one reconnects fresh.
        let maxAttempts = 3
        for attempt in 1...maxAttempts {
            do {
                Log.sync.event("sync start (attempt \(attempt)/\(maxAttempts))")
                let token = try store.syncToken()
                let (messages, newToken) = try await backend.changes(since: token) {
                    [weak self] phase in
                    Task { @MainActor in self?.apply(phase) }
                }
                try store.upsert(messages)
                try store.setSyncToken(newToken)
                sendAsAddresses = try await backend.sendAsAddresses()
                await reloadFromStore()
                await notifyNewReappearances()
                await notifyNewSenders()
                syncState = .idle
                lastSyncedAt = Date()
                Log.sync.event("sync complete: \(messages.count) new, \(groups.count) senders")
                return
            } catch is CancellationError {
                Log.sync.detail("sync cancelled")
                syncState = .idle
                return
            } catch {
                // Bad credentials won't fix themselves on retry — prompt re-auth
                // (works for background syncs too, where a status message alone
                // would be missed).
                if case MailBackendError.authenticationFailed = error {
                    Log.sync.problem("sync auth failed: \(friendly(error))")
                    syncState = .idle
                    if let account = currentAccount { reauthAccount = account }
                    stopBackgroundSync()
                    return
                }
                await backend.disconnect()  // drop the poisoned connection
                if attempt == maxAttempts {
                    Log.sync.problem("sync failed after \(maxAttempts) attempts: \(friendly(error))")
                    syncState = .failed(friendly(error))
                    return
                }
                Log.sync.event("sync attempt \(attempt) failed (\(friendly(error))); reconnecting")
                // Exponential backoff gives Gmail's rate limiter room to recover.
                try? await Task.sleep(for: .seconds(Double(attempt) * 2))
            }
        }
    }

    private func apply(_ phase: SyncPhase) {
        switch phase {
        case .discovering(let window, let total, let found):
            syncState = .discovering(window: window, of: total, found: found)
        case .fetching(let done, let total):
            syncState = .fetching(done: done, of: total)
        }
    }

    private func friendly(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: - Derived rows

    var rows: [SenderRow] {
        let visible = groups.filter(matchesCollection).filter(matchesSearch)
        return visible.map { group in
            SenderRow(group: group, priorOutcome: outcome(for: group.id))
        }
    }

    private func outcome(for id: GroupID) -> MessageStore.Outcome? {
        history[id.storageKey]?.outcome
    }

    func unsubscribeRecord(for id: GroupID) -> MessageStore.UnsubscribeRecord? {
        history[id.storageKey]
    }

    /// The durable unsubscribe log for the History view — every recorded
    /// unsubscribe that hasn't started mailing again, newest first. Read from
    /// the history table, so it survives after the sender's messages are gone.
    var unsubscribedRecords: [MessageStore.UnsubscribeRecord] {
        history.values
            .filter { !isReappearedRecord($0) }
            .sorted { $0.attemptedAt > $1.attemptedAt }
    }

    private func isReappearedRecord(_ r: MessageStore.UnsubscribeRecord) -> Bool {
        guard let g = groups.first(where: { $0.id.storageKey == r.groupKey }) else { return false }
        return g.messages.contains { $0.receivedAt > r.attemptedAt }
    }

    /// Drop a record entirely (e.g. an accidental unsubscribe the user wants to
    /// forget). Also clears the notified-reappeared bookkeeping for that key.
    func forgetRecord(_ groupKey: String) {
        guard let store, let id = GroupID(storageKey: groupKey) else { return }
        try? store.forgetUnsubscribe(id)
        history = (try? store.unsubscribeHistory()) ?? history
    }

    private func matchesCollection(_ g: SenderGroup) -> Bool {
        matches(g, in: collection)
    }

    /// Pure membership test. Takes the collection as a parameter so counting
    /// never has to mutate `self.collection` — doing that during view-body
    /// evaluation triggers an observation-graph mutation mid-render, which on
    /// macOS escalates to an AppKit constraint-update exception and aborts.
    private func matches(_ g: SenderGroup, in collection: Collection) -> Bool {
        let ignored = ignoredKeys.contains(g.id.storageKey)
        let unsubscribed = history[g.id.storageKey] != nil
        switch collection {
        // Once a sender has been unsubscribed it leaves the working list — it
        // lives in Unsubscribed, or in Reappeared if it starts mailing again.
        // (`unsubscribed` already implies not-reappeared, since reappearance
        // requires a history record.)
        case .allSenders: return !ignored && !unsubscribed
        case .ignored: return ignored
        case .unsubscribed: return unsubscribed && !isReappeared(g)
        case .reappeared: return !ignored && isReappeared(g)
        }
    }

    /// True once this sender has any recorded unsubscribe attempt — meaning the
    /// automated path already ran and, if they mail again, we should escalate to
    /// a manual browser unsubscribe rather than silently retrying it.
    func hasPriorAttempt(_ id: GroupID) -> Bool {
        history[id.storageKey] != nil
    }

    // MARK: - Reappearance notifications

    private static let notifiedReappearedKey = "notifiedReappeared"

    /// After a sync, notify the user about senders that have *newly* started
    /// mailing again after an unsubscribe. Only genuinely new ones fire a
    /// notification; keys that stop reappearing are cleared so they can notify
    /// again if they come back later.
    private func notifyNewReappearances() async {
        guard let store else { return }
        let current = Set(groups.filter(isReappeared).map(\.id.storageKey))
        let alreadyNotified = store.stringSet(forKey: Self.notifiedReappearedKey)
        let fresh = current.subtracting(alreadyNotified)
        store.setStringSet(current, forKey: Self.notifiedReappearedKey)
        guard !fresh.isEmpty else { return }

        let center = UNUserNotificationCenter.current()
        guard let granted = try? await center.requestAuthorization(options: [.alert, .sound]),
            granted
        else { return }

        let content = UNMutableNotificationContent()
        content.title = "Senders ignored your unsubscribe"
        content.body = fresh.count == 1
            ? "1 sender kept emailing after you unsubscribed. Open MailScrub to finish it in the browser."
            : "\(fresh.count) senders kept emailing after you unsubscribed. Open MailScrub to finish them in the browser."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }

    private static let knownSendersKey = "knownSenders"

    /// Notify about senders that have newly appeared since the last sync, when
    /// the setting is on. The first sync just seeds the known set — otherwise it
    /// would "announce" the entire mailbox.
    private func notifyNewSenders() async {
        guard let store, AppSettings.notifyNewSenders else { return }
        let current = Set(
            groups
                .filter { !ignoredKeys.contains($0.id.storageKey) && history[$0.id.storageKey] == nil }
                .map(\.id.storageKey))
        let known = store.stringSet(forKey: Self.knownSendersKey)
        store.setStringSet(current, forKey: Self.knownSendersKey)
        guard !known.isEmpty else { return }  // first run — seed only
        let fresh = current.subtracting(known)
        guard !fresh.isEmpty else { return }

        let center = UNUserNotificationCenter.current()
        guard let granted = try? await center.requestAuthorization(options: [.alert, .sound]),
            granted
        else { return }
        let content = UNMutableNotificationContent()
        content.title = "New senders in MailScrub"
        content.body = fresh.count == 1
            ? "1 new sender to review."
            : "\(fresh.count) new senders to review."
        content.sound = .default
        try? await center.add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// A sender that mailed again after a recorded unsubscribe attempt.
    private func isReappeared(_ g: SenderGroup) -> Bool {
        guard let record = history[g.id.storageKey] else { return false }
        return g.messages.contains { $0.receivedAt > record.attemptedAt }
    }

    private func matchesSearch(_ g: SenderGroup) -> Bool {
        guard !searchText.isEmpty else { return true }
        let q = searchText.lowercased()
        if g.displayName.lowercased().contains(q) { return true }
        if g.id.key.lowercased().contains(q) { return true }
        return g.messages.prefix(20).contains { $0.subject.lowercased().contains(q) }
    }

    // MARK: - Counts for the sidebar

    func count(for collection: Collection) -> Int {
        // Unsubscribed is counted from the durable history log, not from
        // messages, so it's correct even after a sender's mail is deleted.
        if collection == .unsubscribed { return unsubscribedRecords.count }
        return groups.filter { matches($0, in: collection) }.count
    }

    var totalMessages: Int { rows.reduce(0) { $0 + $1.count } }

    // MARK: - Selection helpers

    var selectedGroups: [SenderGroup] {
        groups.filter { selection.contains($0.id) }
    }

    func group(for id: GroupID) -> SenderGroup? {
        groups.first { $0.id == id }
    }

    // MARK: - Actions: ignore / trash / forget

    func ignore(_ ids: Set<GroupID>) {
        guard let store else { return }
        let targets = groups.filter { ids.contains($0.id) }
        try? targets.forEach { try store.ignore($0.id) }
        ignoredKeys = (try? store.ignoredGroupKeys()) ?? ignoredKeys
        selection.subtract(ids)
        Log.app.event("ignored \(targets.count) sender(s): \(targets.map(\.id.key).joined(separator: ", "))")
        showToast(
            "Ignored \(targets.count) sender\(targets.count == 1 ? "" : "s")",
            undoLabel: "Undo"
        ) { [weak self] in
            guard let self, let store = self.store else { return }
            try? targets.forEach { try store.unignore($0.id) }
            self.ignoredKeys = (try? store.ignoredGroupKeys()) ?? self.ignoredKeys
        }
    }

    func unignore(_ ids: Set<GroupID>) {
        guard let store else { return }
        try? ids.forEach { try store.unignore($0) }
        ignoredKeys = (try? store.ignoredGroupKeys()) ?? ignoredKeys
        selection.subtract(ids)
    }

    /// A large trash awaiting confirmation (Settings threshold).
    struct PendingTrash: Identifiable {
        let id = UUID()
        let ids: Set<GroupID>
        let messageCount: Int
        let senderCount: Int
    }
    var pendingTrash: PendingTrash?

    /// Entry point for trashing from the UI: confirms first if the batch exceeds
    /// the Settings threshold, otherwise trashes immediately. Trashing is
    /// recoverable from Gmail's Trash for 30 days, so small batches don't prompt.
    func requestTrash(_ ids: Set<GroupID>) {
        let targets = groups.filter { ids.contains($0.id) }
        let count = targets.reduce(0) { $0 + $1.messages.count }
        if count > AppSettings.trashConfirmThreshold {
            pendingTrash = PendingTrash(ids: ids, messageCount: count, senderCount: targets.count)
        } else {
            Task { await trash(ids) }
        }
    }

    func confirmPendingTrash() {
        guard let pending = pendingTrash else { return }
        pendingTrash = nil
        Task { await trash(pending.ids) }
    }

    /// Undo is offered only up to this size — untrash searches the Trash folder
    /// once per message, so a huge batch would be slow. Larger trashes rely on
    /// Gmail's own 30-day Trash retention.
    private static let maxUndoableTrash = 100

    func trash(_ ids: Set<GroupID>) async {
        guard let backend, let store else { return }
        let targets = groups.filter { ids.contains($0.id) }
        let messages = targets.flatMap(\.messages)
        let uids = messages.map(\.uid)
        do {
            try await backend.trash(uids)
            try store.delete(uids: uids)
            await reloadFromStore()
            selection.subtract(ids)
            let n = uids.count
            Log.app.event("trashed \(n) messages from \(targets.count) sender(s)")

            let restorable = messages.filter { !$0.messageId.isEmpty }
            if n <= Self.maxUndoableTrash, !restorable.isEmpty {
                showToast("Trashed \(n) message\(n == 1 ? "" : "s")", undoLabel: "Undo") {
                    [weak self] in await self?.untrash(restorable)
                }
            } else {
                showToast(
                    "Trashed \(n) message\(n == 1 ? "" : "s") — recoverable in Gmail Trash for 30 days",
                    undoLabel: nil, undo: nil)
            }
        } catch {
            Log.app.problem("trash failed: \(friendly(error))")
            showToast("Trash failed: \(friendly(error))", undoLabel: nil, undo: nil)
        }
    }

    /// Restore trashed messages: move them out of Gmail's Trash and re-insert
    /// them locally so they reappear immediately.
    private func untrash(_ messages: [EmailMessage]) async {
        guard let backend, let store else { return }
        do {
            let restored = try await backend.untrash(messageIDs: messages.map(\.messageId))
            try store.upsert(messages)
            await reloadFromStore()
            Log.app.event("undo trash: restored \(restored)/\(messages.count)")
        } catch {
            Log.app.problem("undo trash failed: \(friendly(error))")
            showToast("Couldn't restore: \(friendly(error))", undoLabel: nil, undo: nil)
        }
    }

    func forget(_ ids: Set<GroupID>) {
        guard let store else { return }
        try? ids.forEach { try store.forgetUnsubscribe($0) }
        history = (try? store.unsubscribeHistory()) ?? history
    }

    // MARK: - Unsubscribe

    /// A single sender's planned unsubscribe, surfaced in the confirm/results UI.
    struct UnsubTarget: Identifiable {
        let id: GroupID
        let name: String
        let email: String
        let count: Int
        let method: UnsubscribeMethod
        let deliveredTo: String
        var outcome: UnsubscribeEngine.Outcome?
    }

    func plan(for ids: Set<GroupID>) -> [UnsubTarget] {
        groups.filter { ids.contains($0.id) }.map { g in
            UnsubTarget(
                id: g.id,
                name: g.displayName,
                email: g.latest?.sender.address ?? g.id.key,
                count: g.total,
                method: SenderRow.method(for: g),
                deliveredTo: g.unsubscribeSource?.deliveredTo ?? "",
                outcome: nil
            )
        }
    }

    /// Resolve the send-as From address for a delivered-to address, or nil.
    func sendAsFrom(for deliveredTo: String) -> String? {
        guard !deliveredTo.isEmpty, deliveredTo != currentAccount else { return nil }
        return sendAsAddresses.contains(deliveredTo) ? deliveredTo : nil
    }

    private func describe(_ outcome: UnsubscribeEngine.Outcome) -> String {
        switch outcome {
        case .confirmed(let d): "confirmed (\(d))"
        case .requested(let d): "requested (\(d))"
        case .failed(let d): "failed (\(d))"
        case .needsManual: "needs manual"
        }
    }

    /// Perform unsubscribes one at a time, reporting progress via `onProgress`.
    /// Returns the targets annotated with outcomes.
    func performUnsubscribe(
        _ targets: [UnsubTarget],
        onProgress: @MainActor (Int, UnsubTarget) -> Void
    ) async -> [UnsubTarget] {
        guard let backend, let store else { return targets }
        let engine = UnsubscribeEngine { to, subject, body, from in
            try await backend.sendMail(to: to, subject: subject, body: body, from: from)
        }

        var results = targets
        for index in results.indices {
            if Task.isCancelled { break }
            onProgress(index, results[index])

            guard let group = self.group(for: results[index].id),
                let source = group.unsubscribeSource,
                let unsub = source.unsubscribe
            else {
                results[index].outcome = .needsManual
                continue
            }
            let from = sendAsFrom(for: source.deliveredTo)
            let outcome = await engine.run(unsub, fromAddress: from)
            results[index].outcome = outcome
            Log.unsubscribe.event(
                "\(group.id.key) [\(SenderRow.method(for: group))]: \(describe(outcome))")

            if outcome.isSuccess {
                let storeOutcome: MessageStore.Outcome =
                    { if case .confirmed = outcome { return .confirmed } else { return .requested } }()
                try? store.recordUnsubscribe(
                    group.id,
                    senderName: group.displayName,
                    senderEmail: source.sender.address,
                    senderDomain: source.sender.host,
                    url: unsub.webTargets.first?.absoluteString,
                    outcome: storeOutcome
                )
            }
        }
        history = (try? store.unsubscribeHistory()) ?? history
        selection.subtract(Set(targets.map(\.id)))
        return results
    }

    /// Delete messages from senders whose unsubscribe confirmed.
    func deleteMessages(for ids: [GroupID]) async {
        await trash(Set(ids))
    }

    // MARK: - Manual (browser) unsubscribe

    /// Everything the in-app browser sheet needs to run a manual unsubscribe.
    struct ManualUnsubscribe: Identifiable {
        let id: GroupID
        let name: String
        /// The alias the mail was delivered to — shown in the sheet header so the
        /// user can paste it into a sender's "confirm your email" field.
        let deliveredTo: String
        let url: URL
        /// True when this is an escalation after an automated attempt failed to stick.
        let isEscalation: Bool
    }

    /// Build a manual-unsubscribe target for a sender, or nil if there's no web
    /// page to open (e.g. a mailto:-only sender, which can't be done in a browser).
    func manualTarget(for id: GroupID) -> ManualUnsubscribe? {
        guard let group = self.group(for: id), let source = group.unsubscribeSource else {
            return nil
        }
        // Prefer the published web link; fall back to a Gmail search so "manual"
        // always has somewhere to go.
        let url = source.unsubscribe?.webTargets.first
            ?? URL(string: "https://mail.google.com/mail/u/0/#search/from:\(source.sender.address)")
        guard let url else { return nil }
        return ManualUnsubscribe(
            id: id,
            name: group.displayName,
            deliveredTo: source.deliveredTo,
            url: url,
            isEscalation: hasPriorAttempt(id))
    }

    /// Record the result of a manual browser unsubscribe and drop the sender.
    func recordManual(_ id: GroupID, confirmed: Bool) {
        guard let store, let group = self.group(for: id) else { return }
        let source = group.unsubscribeSource
        let url = source?.unsubscribe?.webTargets.first?.absoluteString
        try? store.recordUnsubscribe(
            id,
            senderName: group.displayName,
            senderEmail: source?.sender.address ?? group.id.key,
            senderDomain: source?.sender.host ?? "",
            url: url,
            outcome: confirmed ? .confirmed : .requested)
        history = (try? store.unsubscribeHistory()) ?? history
        // Updating attemptedAt to now clears the reappeared state — old messages
        // predate it — so a re-unsubscribed sender leaves Reappeared.
        selection.remove(id)
    }

    // MARK: - Toast

    private func showToast(
        _ message: String, undoLabel: String?,
        undo: (@MainActor () async -> Void)?
    ) {
        pendingUndo = undo
        toast = Toast(message: message, undo: undoLabel.map { UndoAction(label: $0) })
    }

    private func showToast(
        _ message: String, undoLabel: String?, action: @escaping @MainActor () async -> Void
    ) {
        showToast(message, undoLabel: undoLabel, undo: action)
    }

    func runUndo() async {
        await pendingUndo?()
        pendingUndo = nil
        toast = nil
        await reloadFromStore()
    }

    func dismissToast() { toast = nil; pendingUndo = nil }
}
