import Foundation

/// A `MailBackend` that talks to nobody.
///
/// Every network-touching operation is a no-op that reports success, so the UI
/// exercises its real code paths — including the sync progress phases — without
/// a server, an account, or a password. This is what makes demo mode safe to
/// hand to a stranger: there is no credential to leak and no request to send.
///
/// Deliberately *not* a subclass or a flag on `IMAPBackend`: the guarantee that
/// demo mode cannot reach the network should be structural, not conditional.
public actor DemoBackend: MailBackend {
    public nonisolated var primaryAddress: String { DemoData.address }

    /// Set once per sync so a screenshot taken mid-sync shows plausible ages.
    private var issuedToken: SyncToken?

    public init() {}

    public func discoverAll(
        progress: @Sendable @escaping (SyncPhase) -> Void
    ) async throws -> SyncResult {
        // Walk the same two phases a real sync does, briefly. Without this the
        // demo would snap straight to a full table and never show the first-run
        // progress screen — which is one of the things worth demonstrating.
        let windows = 8
        for window in 1...windows {
            try Task.checkCancellation()
            try? await Task.sleep(for: .milliseconds(90))
            progress(
                .discovering(
                    window: window, of: windows,
                    found: Int(Double(demoMessages.count) * Double(window) / Double(windows))))
        }

        let total = demoMessages.count
        var done = 0
        while done < total {
            try Task.checkCancellation()
            try? await Task.sleep(for: .milliseconds(70))
            done = min(done + max(total / 8, 1), total)
            progress(.fetching(done: done, of: total))
        }

        let token = SyncToken(uidValidity: 1, highestUID: 9999, lastSyncedAt: Date())
        issuedToken = token
        // The demo mailbox drops nothing: every message in it is storable, and
        // inventing losses would put numbers on screen that describe no
        // mailbox anyone has.
        var attribution = SyncAttribution()
        attribution.located = demoMessages.count
        attribution.fetched = demoMessages.count
        attribution.handedToStore = demoMessages.count
        return SyncResult(messages: demoMessages, token: token, attribution: attribution)
    }

    public func changes(
        since token: SyncToken?,
        progress: @Sendable @escaping (SyncPhase) -> Void
    ) async throws -> SyncResult {
        guard token != nil else { return try await discoverAll(progress: progress) }
        // An incremental demo sync finds nothing new — the demo mailbox is
        // fixed, and inventing arrivals would make "Sync Now" quietly change
        // the screenshot you were about to take.
        return SyncResult(
            messages: [],
            token: SyncToken(uidValidity: 1, highestUID: 9999, lastSyncedAt: Date()),
            attribution: SyncAttribution())
    }

    private var demoMessages: [EmailMessage] { DemoData.messages() }

    // MARK: - Actions that would touch a server

    public func trash(_ uids: [MessageUID], recordOrigin: Bool) async throws -> TrashOutcome {
        Log.app.event("demo: pretending to trash \(uids.count) message(s)")
        // The demo mailbox is all inbox, so undo has nowhere else to put things.
        return TrashOutcome(moved: uids)
    }

    public func untrash(messageIDs: [String], to target: RestoreTarget) async throws -> Int {
        Log.app.event(
            "demo: pretending to restore \(messageIDs.count) message(s) to \(target.rawValue)")
        return messageIDs.count
    }

    public func verifyConnection() async throws {}

    public func sendMail(to: String, subject: String, body: String, from: String?) async throws {
        Log.app.event("demo: suppressed unsubscribe mail to \(to)")
    }

    public func sendAsAddresses() async throws -> [String] { DemoData.sendAsAddresses }

    /// The demo has no Gmail behind it, so there is no conversation to open.
    public func gmailThreadID(for uid: MessageUID) async -> UInt64? { nil }

    public func disconnect() async {}
}
