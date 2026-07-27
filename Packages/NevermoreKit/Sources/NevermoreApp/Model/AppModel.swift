import AppKit
import Foundation
import NevermoreKit
import Observation
import UserNotifications

/// The single source of UI truth. Bridges NevermoreKit's actor backend and
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
    /// couldn't be unlocked. Demo mode suppresses it — the whole point is to
    /// look around before handing over a password.
    var needsOnboarding: Bool {
        !isDemoMode && (currentAccount == nil || reauthAccount != nil)
    }

    private let registry = AccountRegistry.shared
    private var store: MessageStore?
    /// Held as the protocol, not `IMAPBackend`, so demo mode can substitute a
    /// backend that has no network code in it at all.
    private var backend: (any MailBackend)?

    // MARK: - Demo mode

    private static let demoModeKey = "demoMode"

    /// Whether the app is showing the fabricated demo mailbox instead of real
    /// mail. Persisted, so a relaunch doesn't silently drop someone back into
    /// their own data mid-presentation — the banner is what gets them out.
    private(set) var isDemoMode: Bool = UserDefaults.standard.bool(forKey: AppModel.demoModeKey)

    /// True when the user has a real account to go back to. When false, leaving
    /// the demo means onboarding.
    var hasRealAccount: Bool { !accounts.isEmpty }

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
        /// Connecting and resolving folders — before the first search returns.
        /// A distinct case so the UI can say something during the seconds
        /// between "sync started" and the first progress report.
        case connecting
        case discovering(window: Int, of: Int, found: Int)
        case fetching(done: Int, of: Int)
        case failed(String)

        /// True while a sync is actually running (not idle, not failed).
        var isActive: Bool {
            switch self {
            case .idle, .failed: false
            case .connecting, .discovering, .fetching: true
            }
        }

        /// One-line description of what the sync is doing right now. Phrased in
        /// terms of the user's mail, not the implementation — "date window" is
        /// our chunking strategy and means nothing to them.
        var detail: String? {
            switch self {
            case .idle, .failed: nil
            case .connecting:
                "Connecting…"
            case .discovering(_, _, let found):
                "Searching your mail history — \(found.formatted()) newsletters found"
            case .fetching(let done, let total):
                "Reading details — \(done.formatted()) of \(total.formatted())"
            }
        }

        /// How far along the current step is, 0...1, for a determinate bar.
        /// Both steps know their own total, so neither needs a spinner.
        var fractionComplete: Double? {
            switch self {
            case .idle, .failed, .connecting: nil
            case .discovering(let window, let total, _):
                Double(window) / Double(max(total, 1))
            case .fetching(let done, let total):
                Double(done) / Double(max(total, 1))
            }
        }

        /// Which of the two sync steps this is, for "Step 1 of 2" framing. The
        /// steps have very different durations, so a single combined bar would
        /// stall visibly at the handover; two honest bars beat one dishonest one.
        var step: (number: Int, name: String)? {
            switch self {
            case .idle, .failed, .connecting: nil
            case .discovering: (1, "Finding newsletters")
            case .fetching: (2, "Reading sender details")
            }
        }
    }
    private(set) var syncState: SyncState = .idle
    private(set) var lastSyncedAt: Date?

    /// Transient status-bar message with an optional undo, mirroring the design.
    struct Toast: Equatable {
        var message: String
        var undo: UndoAction?
        /// A follow-up offer — "delete their messages", "mark unsubscribed".
        /// Separate from `undo` on purpose: it shares the button but must *not*
        /// be bound to ⌘Z, which would make an undo keystroke delete mail.
        var action: UndoAction?
    }
    struct UndoAction: Equatable { let id = UUID(); var label: String }
    private(set) var toast: Toast?
    /// Whether the current toast offers an undo (drives ⌘Z / the Undo menu item).
    var canUndo: Bool { toast?.undo != nil }
    private var pendingUndo: (@MainActor () async -> Void)?
    private var pendingAction: (@MainActor () async -> Void)?

    init() {
        accounts = registry.accounts()
        currentAccount = accounts.first
    }

    // MARK: - Session lifecycle

    func start() async {
        if isDemoMode {
            await openDemo()
            return
        }
        guard let account = currentAccount else { return }
        await open(account: account)
    }

    /// Switch into the fabricated demo mailbox.
    ///
    /// The database is rebuilt from scratch every time so the demo looks
    /// identical on every run — which is what makes it usable for screenshots,
    /// and stops one person's poking around from being the next person's
    /// starting state.
    func enterDemoMode() async {
        stopBackgroundSync()
        cancelSync()
        registry.resetDemoDatabase()
        isDemoMode = true
        UserDefaults.standard.set(true, forKey: Self.demoModeKey)
        Log.app.event("entering demo mode")
        await openDemo()
    }

    private func openDemo() async {
        reauthAccount = nil
        groups = []
        selection = []
        do {
            store = try MessageStore(path: registry.demoDatabasePath)
        } catch {
            Log.app.problem("could not open demo database: \(error.localizedDescription)")
            syncState = .failed("Could not open the demo database: \(error.localizedDescription)")
            return
        }
        backend = DemoBackend()
        await reloadFromStore()
        startSync()
        // No background sync in demo mode: there is nothing to poll, and a tick
        // firing mid-presentation would only reset the progress display.
    }

    /// Leave demo mode and go back to real mail (or to onboarding if there
    /// isn't an account yet).
    func exitDemoMode() async {
        stopBackgroundSync()
        cancelSync()
        isDemoMode = false
        UserDefaults.standard.set(false, forKey: Self.demoModeKey)
        store = nil
        backend = nil
        groups = []
        selection = []
        syncState = .idle
        lastSyncedAt = nil
        Log.app.event("leaving demo mode")
        if let account = currentAccount { await open(account: account) }
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
        backend = makeBackend(for: account, password: password)
        currentAccount = account
        Log.app.event("opened account \(account)")
        await reloadFromStore()
        // Deliberately not awaited: the first sync on a large mailbox takes
        // minutes, and `open` is called from the onboarding sheet's submit
        // handler. Awaiting it here kept the modal sheet up — showing only
        // "Verifying…" — for the whole sync. Kick it off and let the window
        // appear; the status bar reports progress.
        if AppSettings.syncOnLaunch { startSync() }
        startBackgroundSync()
    }

    // MARK: - Sync scheduling

    private var syncTask: Task<Void, Never>?

    /// Whether a sync is currently running (drives the UI's first-sync state and
    /// the toolbar's disabled Sync button).
    var isSyncing: Bool { syncState.isActive }

    /// Start a sync in the background and return immediately. Callers that must
    /// not block — onboarding, launch, the toolbar button — use this instead of
    /// `sync()`. A second call while one is running is a no-op, so a background
    /// tick can't overlap a long first sync on the same IMAP connection.
    func startSync() {
        guard syncTask == nil else { return }
        syncGeneration += 1
        let generation = syncGeneration
        syncTask = Task { [weak self] in
            await self?.sync()
            // Only clear the handle if it's still ours. A cancelled sync
            // finishing late must not clear the handle of the sync that
            // replaced it, which would let a background tick start a second
            // concurrent one.
            guard let self, self.syncGeneration == generation else { return }
            self.syncTask = nil
        }
    }

    /// Bumped on every start and cancel so a stale task can recognize that it
    /// no longer owns `syncTask`.
    private var syncGeneration = 0

    /// Throw away the local header cache and re-read the mailbox from scratch.
    ///
    /// This is the only way to reconcile with the server after messages are
    /// deleted (or trashed) outside Nevermore, or after a partial trash: an
    /// incremental sync searches forward from the sync token and upserts, so it
    /// adds rows but never retires them.
    ///
    /// Deliberately keeps unsubscribe history, ignored senders, and grouping
    /// corrections — those are your decisions, not cached server state, and
    /// they'd be expensive to recreate. Only the message cache is rebuilt.
    func fullResync() {
        guard let store, !isDemoMode else { return }
        cancelSync()
        Log.sync.event("full resync: clearing local message cache and sync token")
        try? store.deleteAllMessages()
        try? store.clearSyncToken()
        groups = []
        selection = []
        lastSyncedAt = nil
        // Back to "nothing loaded" so the window shows first-sync progress
        // rather than an empty list that looks like a finished, empty mailbox.
        hasLoadedOnce = false
        startSync()
    }

    private func cancelSync() {
        syncTask?.cancel()
        syncTask = nil
        syncGeneration += 1
    }

    // MARK: - Debug tools

    /// Whether the hidden debug section in Settings is revealed. Session-only on
    /// purpose — it should not persist into a build a user is actually using.
    var debugToolsUnlocked = false

    /// Everything `resetAllState` clears, for the confirmation dialog. Listing
    /// it is the difference between a destructive button and an informed one.
    static let resetDescription = """
        Deletes every account's local header cache, the demo mailbox, the account \
        list, and the first-run flags — returning Nevermore to the state it was \
        in before it was ever launched.

        Your saved app password stays in the Keychain so you can sign in again \
        without fetching a new one. Nothing on the mail server is touched.
        """

    /// Return the app to a never-launched state, in process.
    ///
    /// Deliberately not "reset and quit": the onboarding sheet is driven by
    /// `needsOnboarding`, so clearing the account here flips it false → true and
    /// the sheet presents immediately. That makes the onboarding path testable
    /// in a loop without a relaunch between runs.
    func resetAllState() async {
        Log.app.event("debug: resetting all app state")
        stopBackgroundSync()
        cancelSync()

        store = nil
        backend = nil
        registry.resetAllLocalData()

        groups = []
        selection = []
        ignoredKeys = []
        history = [:]
        groupingRules = [:]
        sendAsAddresses = []
        accounts = []
        currentAccount = nil
        reauthAccount = nil
        collection = .allSenders
        searchText = ""
        showInspector = false
        toast = nil
        pendingUndo = nil
        syncState = .idle
        lastSyncedAt = nil
        // Back to "nothing has loaded", so the window doesn't briefly claim a
        // status for a mailbox that no longer exists.
        hasLoadedOnce = false

        isDemoMode = false
        for key in ["demoMode", "keychainInfoShown"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Also forget the Keychain password, for testing the full cold start
    /// including the app-password step.
    func deleteSavedPasswords() {
        for account in registry.accounts() + accounts { Keychain.delete(for: account) }
        Log.app.event("debug: deleted saved Keychain password(s)")
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
                self?.startSync()  // no-op if a sync is already running
            }
        }
    }

    private func stopBackgroundSync() {
        backgroundSyncTask?.cancel()
        backgroundSyncTask = nil
    }

    // MARK: - Onboarding

    /// Whether opening the saved account will make macOS show its Keychain
    /// "allow access" dialog — the only case where the explainer sheet is worth
    /// showing. False when there's no saved account (onboarding *writes* the
    /// item, which never prompts) and false when this build already has access.
    var expectsKeychainPrompt: Bool {
        guard let currentAccount else { return false }
        return Keychain.readWouldPrompt(for: currentAccount)
    }

    /// The provider id recorded for an account, if any (used by re-auth).
    func storedProviderID(for account: String) -> String? {
        registry.providerID(for: account)
    }

    /// The active account's mail provider (used for provider-aware UI copy and
    /// "open in webmail" links). Falls back to Gmail when no account is open.
    var currentProvider: MailProvider {
        guard let currentAccount else { return .gmail }
        return MailProvider.resolved(
            forEmail: currentAccount, storedID: registry.providerID(for: currentAccount))
    }

    /// Open the given sender's messages in the provider's webmail, if it has one.
    func openInWebmail(senderAddress address: String) {
        // Demo senders don't exist in anyone's mailbox; opening a webmail search
        // for one would just dump the user into their real inbox mid-demo.
        guard !isDemoMode else {
            showToast("Demo mode — opening webmail is disabled here.", undoLabel: nil, undo: nil)
            return
        }
        guard let url = currentProvider.webSearchURL(fromSender: address, account: currentAccount)
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// Open the selected sender's most recent message in the default browser,
    /// so the user can read it before deciding to unsubscribe.
    ///
    /// Gmail can be linked straight to the message. Everything else falls back
    /// to a search for the sender — stated in a toast rather than silently
    /// landing somewhere other than asked for.
    func viewLatestMessage() {
        Task { await viewLatestMessageAsync() }
    }

    private func viewLatestMessageAsync() async {
        guard !isDemoMode else {
            showToast("Demo mode — there's no real message to open.", undoLabel: nil, undo: nil)
            return
        }
        guard let id = selection.first, let group = group(for: id), let message = group.latest
        else { return }

        // Prefer Gmail's own conversation link. Costs one round trip on an
        // open connection, and only when the user actually asks to view — far
        // cheaper than fetching a thread id for every message of every sync.
        if let backend,
            let threadID = await backend.gmailThreadID(for: message.uid),
            let url = currentProvider.webThreadURL(threadID: threadID, account: currentAccount)
        {
            Log.app.event("opening gmail conversation for \(group.id.key)")
            NSWorkspace.shared.open(url)
            return
        }
        if let url = currentProvider.webMessageURL(
            messageId: message.messageId, account: currentAccount)
        {
            Log.app.event("opening message in \(currentProvider.displayName)")
            NSWorkspace.shared.open(url)
            return
        }
        guard
            let url = currentProvider.webSearchURL(
                fromSender: message.sender.address, account: currentAccount)
        else {
            showToast(
                "\(currentProvider.displayName) has no web link Nevermore can open.",
                undoLabel: nil, undo: nil)
            return
        }
        // Distinguish "your provider can't do this" from "this message predates
        // Message-ID storage" — the second one fixes itself on the next sync.
        let why =
            message.messageId.isEmpty
            ? "this message was synced before Nevermore stored message IDs"
            : "\(currentProvider.displayName) can't link to a single message"
        showToast("Opened a search for the sender — \(why).", undoLabel: nil, undo: nil)
        NSWorkspace.shared.open(url)
    }

    /// Whether the current provider has a webmail search (drives the menu item).
    var canOpenInWebmail: Bool {
        currentProvider.webSearchURL(fromSender: "x@x") != nil
    }

    /// Open every selected sender in the provider's webmail.
    func openSelectionInWebmail() {
        for id in selection {
            guard let address = group(for: id)?.latest?.sender.address else { continue }
            openInWebmail(senderAddress: address)
        }
    }

    /// Build the IMAP backend for an account, using its stored provider (or the
    /// domain-detected one, falling back to Gmail).
    private func makeBackend(for email: String, password: String, provider: MailProvider? = nil) -> IMAPBackend {
        let resolved = provider
            ?? MailProvider.resolved(forEmail: email, storedID: registry.providerID(for: email))
        return IMAPBackend(
            address: email, appPassword: password,
            config: IMAPBackend.Config(provider: resolved))
    }

    /// Validate credentials by authenticating, then persist and open. Retries a
    /// couple of times on transient failures (server throttling / flaky network)
    /// so a bad moment doesn't look like a wrong password; a genuine auth failure
    /// is reported immediately.
    func addAccount(email: String, appPassword: String, provider: MailProvider) async throws {
        let candidate = makeBackend(for: email, password: appPassword, provider: provider)
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

        // Adding a real account always leaves the demo — otherwise the banner
        // would still be up over the user's actual mail.
        if isDemoMode {
            isDemoMode = false
            UserDefaults.standard.set(false, forKey: Self.demoModeKey)
        }
        try Keychain.store(appPassword: appPassword, for: email)
        registry.add(email)
        registry.setProviderID(provider.id, for: email)
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
        // A sync is no longer awaited by its caller, so one may still be in
        // flight for the account we're leaving — it would write its results
        // into the new account's store.
        cancelSync()
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
            cancelSync()
            currentAccount = accounts.first
            store = nil
            backend = nil
            groups = []
            if let next = currentAccount { await open(account: next) }
        }
    }

    // MARK: - Loading & sync

    private(set) var groupingRules: [String: Grouping.Rule] = [:]

    /// False until the store has been read at least once. Before that, the UI
    /// must not claim a status like "all caught up" — nothing has loaded yet.
    private(set) var hasLoadedOnce = false

    private func reloadFromStore() async {
        guard let store else { return }
        do {
            let messages = try store.allMessages()
            groupingRules = store.groupingRules()
            groups = Grouping(rules: groupingRules).group(messages)
            ignoredKeys = try store.ignoredGroupKeys()
            history = try store.unsubscribeHistory()
            hasLoadedOnce = true
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

    /// Private so every caller goes through `startSync()` and its
    /// already-running guard — two concurrent syncs share one IMAP connection
    /// and poison each other.
    private func sync() async {
        guard let backend, let store else { return }

        // A cached IMAP connection that has errored (server throttling, a dropped
        // socket, a mid-stream server error) stays poisoned and keeps failing.
        // Retry a couple of times, dropping the connection between attempts so
        // the next one reconnects fresh.
        let maxAttempts = 3
        for attempt in 1...maxAttempts {
            do {
                Log.sync.event("sync start (attempt \(attempt)/\(maxAttempts))")
                // Connect and folder resolution run before the first progress
                // callback — several seconds on a cold connection. Say so
                // rather than leaving the UI looking idle.
                syncState = .connecting
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
                // Exponential backoff gives the server's rate limiter room to recover.
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

    /// Table sort order. Lives in the model (not the view) so keyboard
    /// navigation moves through the same order the table displays.
    var sortOrder = [KeyPathComparator(\SenderRow.lastReceived, order: .reverse)]
    var sortedRows: [SenderRow] { rows.sorted(using: sortOrder) }

    /// Whether the keyboard-shortcuts help overlay is showing (⌘? / Help menu).
    var showShortcuts = false

    /// Whether the how-it-works sheet is showing (Help menu).
    var showHowItWorks = false

    /// Move the single selection up (-1) or down (+1) through the visible list.
    func moveSelection(by delta: Int) {
        guard
            let next = SelectionCursor.move(
                from: selection, by: delta, in: sortedRows.map(\.id))
        else { return }
        selection = [next]
        showInspector = true
    }

    /// The row to select after the current one is removed — the next one down,
    /// or the previous if it was last. Keeps keyboard triage flowing.
    private func rowAfterSelection() -> GroupID? {
        SelectionCursor.rowAfterRemoving(selection, from: sortedRows.map(\.id))
    }

    private func advance(to id: GroupID?) {
        // Only land on a row that still exists. Selecting a departed row leaves
        // the table with an invisible selection and the inspector on nothing —
        // which is what a multi-row action used to do every time.
        if let id, group(for: id) != nil {
            selection = [id]
            showInspector = true
        } else {
            selection = []
        }
    }

    /// Ignore the selection and move to the next row (keyboard triage).
    func ignoreAndAdvance() {
        guard !selection.isEmpty else { return }
        let next = rowAfterSelection()
        ignore(selection)
        advance(to: next)
    }

    /// Trash the selection and move to the next row — unless the trash needs
    /// confirmation, in which case selection stays until the user confirms.
    func trashAndAdvance() {
        guard !selection.isEmpty else { return }
        let next = rowAfterSelection()
        requestTrash(selection)
        if pendingTrash == nil { advance(to: next) }
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
            // The search field stays visible on this collection, so it has to
            // work here too — it was silently doing nothing.
            .filter { record in
                guard !searchText.isEmpty else { return true }
                let q = searchText.lowercased()
                return record.senderName.lowercased().contains(q)
                    || record.senderEmail.lowercased().contains(q)
                    || record.senderDomain.lowercased().contains(q)
            }
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
            ? "1 sender kept emailing after you unsubscribed. Open Nevermore to finish it in the browser."
            : "\(fresh.count) senders kept emailing after you unsubscribed. Open Nevermore to finish them in the browser."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }

    /// How many messages arrived *after* the recorded unsubscribe — the number
    /// the Reappeared list is actually claiming.
    func messagesSinceUnsubscribe(_ id: GroupID) -> Int {
        guard let record = history[id.storageKey], let group = group(for: id) else { return 0 }
        return group.messages.filter { $0.receivedAt > record.attemptedAt }.count
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

    /// `silently` suppresses the toast so a caller combining several actions can
    /// present one message with one undo instead of a burst that clobbers itself.
    func ignore(_ ids: Set<GroupID>, silently: Bool = false) {
        guard let store else { return }
        let targets = groups.filter { ids.contains($0.id) }
        try? targets.forEach { try store.ignore($0.id) }
        ignoredKeys = (try? store.ignoredGroupKeys()) ?? ignoredKeys
        selection.subtract(ids)
        Log.app.event("ignored \(targets.count) sender(s): \(targets.map(\.id.key).joined(separator: ", "))")
        guard !silently else { return }
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
        /// Where to put the cursor afterwards, captured before the rows go.
        let advanceTo: GroupID?
    }
    var pendingTrash: PendingTrash?

    /// Entry point for trashing from the UI: confirms first if the batch exceeds
    /// the Settings threshold, otherwise trashes immediately. Trashing is
    /// recoverable from the provider's Trash, so small batches don't prompt.
    func requestTrash(_ ids: Set<GroupID>) {
        let targets = groups.filter { ids.contains($0.id) }
        let count = targets.reduce(0) { $0 + $1.messages.count }
        if count > AppSettings.trashConfirmThreshold {
            pendingTrash = PendingTrash(
                ids: ids, messageCount: count, senderCount: targets.count,
                advanceTo: rowAfterSelection())
        } else {
            Task { await trash(ids) }
        }
    }

    func confirmPendingTrash() {
        guard let pending = pendingTrash else { return }
        pendingTrash = nil
        // Advance like the below-threshold path does. The same button behaved
        // two different ways depending on how much mail the sender had sent.
        Task {
            await trash(pending.ids)
            advance(to: pending.advanceTo)
        }
    }

    /// Undo is offered only up to this size — untrash searches the Trash folder
    /// once per message, so a huge batch would be slow. Larger trashes rely on
    /// the provider's own Trash retention.
    private static let maxUndoableTrash = 100

    func trash(_ ids: Set<GroupID>, silently: Bool = false) async {
        guard let backend, let store else { return }
        let targets = groups.filter { ids.contains($0.id) }
        let messages = targets.flatMap(\.messages)
        let uids = messages.map(\.uid)
        do {
            // Only forget locally what the server confirms it moved, so a
            // partial trash leaves the app agreeing with the mailbox instead of
            // hiding messages that are still sitting in the inbox.
            let movedUIDs = try await backend.trash(uids)
            let moved = Set(movedUIDs)
            try store.delete(uids: movedUIDs)
            await reloadFromStore()
            selection.subtract(ids)
            let n = movedUIDs.count
            Log.app.event("trashed \(n) messages from \(targets.count) sender(s)")

            if n < uids.count {
                // Always reported, even when the caller asked for silence: a
                // partial trash is exactly the case the user must be told about.
                showToast(
                    "Trashed \(n.formatted()) of \(uids.count.formatted()) — the rest timed out. Try again to finish.",
                    undoLabel: nil, undo: nil)
                return
            }
            guard !silently else { return }

            let restorable = messages.filter { !$0.messageId.isEmpty && moved.contains($0.uid) }
            if n <= Self.maxUndoableTrash, !restorable.isEmpty {
                showToast("Trashed \(n) message\(n == 1 ? "" : "s")", undoLabel: "Undo") {
                    [weak self] in await self?.untrash(restorable)
                }
            } else {
                showToast(
                    "Trashed \(n) message\(n == 1 ? "" : "s") — recoverable from your Trash folder",
                    undoLabel: nil, undo: nil)
            }
        } catch {
            Log.app.problem("trash failed: \(friendly(error))")
            showToast("Trash failed: \(friendly(error))", undoLabel: nil, undo: nil)
        }
    }

    /// Restore trashed messages: move them out of the provider's Trash and
    /// re-insert them locally so they reappear immediately.
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

    /// Drop unsubscribe records, with an undo.
    ///
    /// Forgetting silently moved a sender back into the working list with no
    /// confirmation and no way back — the record is the app's only memory that
    /// the unsubscribe ever happened, and recreating it means unsubscribing
    /// again for real. So capture the records first and offer to restore them.
    func forget(_ ids: Set<GroupID>) {
        guard let store else { return }
        let removed = ids.compactMap { history[$0.storageKey] }
        try? ids.forEach { try store.forgetUnsubscribe($0) }
        history = (try? store.unsubscribeHistory()) ?? history
        guard !removed.isEmpty else { return }
        let n = removed.count
        showToast(
            "Forgot \(n) unsubscribe record\(n == 1 ? "" : "s")", undoLabel: "Undo"
        ) { [weak self] in
            guard let self, let store = self.store else { return }
            for record in removed {
                guard let id = GroupID(storageKey: record.groupKey) else { continue }
                try? store.recordUnsubscribe(
                    id, senderName: record.senderName, senderEmail: record.senderEmail,
                    senderDomain: record.senderDomain, url: record.url,
                    outcome: record.outcome, attemptedAt: record.attemptedAt)
            }
            self.history = (try? store.unsubscribeHistory()) ?? self.history
        }
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
        /// Set when the sender is an RFC 2919 mailing list.
        let mailingListID: String?
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
                mailingListID: g.mailingListID,
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
        case .needsManual(let reason): "needs manual (\(reason))"
        }
    }

    /// Perform unsubscribes one at a time, reporting progress via `onProgress`.
    /// Returns the targets annotated with outcomes.
    func performUnsubscribe(
        _ targets: [UnsubTarget],
        onProgress: @MainActor (Int, UnsubTarget) -> Void
    ) async -> [UnsubTarget] {
        guard let backend, let store else { return targets }
        // Work out where the cursor should land *before* acting: once these
        // senders are unsubscribed (and possibly trashed) they leave the list,
        // so "the row after the selection" is only answerable now.
        let next = rowAfterSelection()
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
                results[index].outcome = .needsManual(reason: "no unsubscribe link")
                continue
            }
            let from = sendAsFrom(for: source.deliveredTo)

            // A bare mailto: identifies you only by who the mail comes from.
            // If it arrived at a forwarded address we can't send as, the
            // request would go out from the wrong identity and be ignored —
            // and we'd then record it as "requested", quietly retiring a
            // sender that never actually unsubscribed you. Hand it to the
            // manual flow instead of pretending.
            let bareMailto =
                unsub.webTargets.isEmpty
                && unsub.mailtoTargets.first.map { !$0.identifiesRecipient } == true
            if bareMailto, from == nil, !source.deliveredTo.isEmpty,
                source.deliveredTo != currentAccount
            {
                results[index].outcome = .needsManual(
                    reason: "delivered to \(source.deliveredTo), which you can't send from")
                Log.unsubscribe.event(
                    "\(group.id.key): skipped mailto — delivered to \(source.deliveredTo), no send-as")
                continue
            }
            // The engine is the one path that makes its own HTTP requests
            // rather than going through the backend, so demo mode has to stop
            // short of it explicitly. A demo must never send a real
            // unsubscribe request to a real (or fabricated) endpoint.
            let outcome: UnsubscribeEngine.Outcome
            if isDemoMode {
                try? await Task.sleep(for: .milliseconds(350))  // let the progress UI be seen
                outcome = SenderRow.method(for: group) == .manual
                    ? .needsManual(reason: "no unsubscribe link")
                    : .requested(detail: "demo — no request sent")
            } else {
                outcome = await engine.run(unsub, fromAddress: from)
            }
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
        // Keep triage flowing, the same way ignore and trash do. Without this
        // the selection is simply emptied and the next keystroke has nothing
        // to act on.
        advance(to: next)
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
        // The manual flow loads a sender-published URL in a real web view. The
        // demo's senders are invented, so their URLs point at domains we don't
        // own — loading one would send a live request somewhere arbitrary.
        if isDemoMode {
            showToast(
                "Demo mode — the browser unsubscribe is disabled here.",
                undoLabel: nil, undo: nil)
            return nil
        }
        guard let group = self.group(for: id), let source = group.unsubscribeSource else {
            return nil
        }
        // Prefer the published web link; fall back to the provider's webmail
        // search so "manual" always has somewhere to go.
        let url = source.unsubscribe?.webTargets.first
            ?? currentProvider.webSearchURL(
                fromSender: source.sender.address, account: currentAccount)
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

        // The automated flow offers to clear the backlog once an unsubscribe
        // succeeds; the manual flow didn't offer it at all, so finishing in the
        // browser left every message behind with no hint that deleting was even
        // an option. Offer, don't assume — this is the user's mail.
        guard confirmed, !group.messages.isEmpty else { return }
        let count = group.messages.count
        showToast(
            "Unsubscribed from \(group.displayName)",
            actionLabel: "Delete \(count.formatted()) Message\(count == 1 ? "" : "s")"
        ) { [weak self] in
            await self?.trash([id])
        }
    }

    /// Called when the browser sheet closes with no outcome recorded.
    ///
    /// Closing a window is not a statement about whether the unsubscribe
    /// worked, but the user has usually just done the work — so keep it
    /// one click away instead of silently discarding it.
    func promptManualOutcome(_ target: ManualUnsubscribe) {
        guard history[target.id.storageKey] == nil else { return }
        showToast(
            "Closed without recording — did you unsubscribe from \(target.name)?",
            actionLabel: "Mark Unsubscribed"
        ) { [weak self] in
            self?.recordManual(target.id, confirmed: true)
        }
    }

    // MARK: - Toast

    private var toastTask: Task<Void, Never>?

    /// How long a toast — and the undo it offers — stays live.
    ///
    /// Previously neither ever expired: `dismissToast()` had no callers, so the
    /// status bar kept the last message forever and ⌘Z stayed armed
    /// indefinitely. Pressing it an hour later would silently reverse an action
    /// the user had long forgotten.
    private static let toastLifetime: Duration = .seconds(12)

    /// A toast whose button performs a follow-up rather than an undo.
    private func showToast(
        _ message: String, actionLabel: String,
        action: @escaping @MainActor () async -> Void
    ) {
        showToast(message, undoLabel: nil, undo: nil, actionLabel: actionLabel, action: action)
    }

    private func showToast(
        _ message: String, undoLabel: String?,
        undo: (@MainActor () async -> Void)?,
        actionLabel: String? = nil,
        action: (@MainActor () async -> Void)? = nil
    ) {
        toastTask?.cancel()
        pendingUndo = undo
        pendingAction = action
        let shown = Toast(
            message: message,
            undo: undoLabel.map { UndoAction(label: $0) },
            action: actionLabel.map { UndoAction(label: $0) })
        toast = shown
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: Self.toastLifetime)
            guard !Task.isCancelled, let self, self.toast == shown else { return }
            self.toast = nil
            self.pendingUndo = nil
        }
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

    /// Perform a toast's follow-up offer. Deliberately not reachable from ⌘Z.
    func runToastAction() async {
        let action = pendingAction
        pendingAction = nil
        toast = nil
        await action?()
    }

    func dismissToast() {
        toastTask?.cancel()
        toast = nil
        pendingUndo = nil
        pendingAction = nil
    }

    /// Trash a sender's messages and ignore them, as one undoable step.
    ///
    /// Doing these as two calls fired two toasts back to back: the second
    /// replaced the first, so the trash's undo was destroyed a frame after it
    /// appeared and ⌘Z would un-ignore while leaving the messages in Trash.
    func trashAndIgnore(_ id: GroupID) async {
        let targets = groups.filter { $0.id == id }
        let messages = targets.flatMap(\.messages)
        await trash([id], silently: true)
        ignore([id], silently: true)
        let restorable = messages.filter { !$0.messageId.isEmpty }
        showToast(
            "Trashed \(messages.count.formatted()) message\(messages.count == 1 ? "" : "s") and ignored the sender",
            undoLabel: restorable.isEmpty ? nil : "Undo"
        ) { [weak self] in
            guard let self, let store = self.store else { return }
            try? targets.forEach { try store.unignore($0.id) }
            self.ignoredKeys = (try? store.ignoredGroupKeys()) ?? self.ignoredKeys
            await self.untrash(restorable)
        }
    }
}
