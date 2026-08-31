import Foundation
import Testing

@testable import NevermoreApp
@testable import NevermoreKit

// Suites that drive `AppModel` itself rather than a rule extracted out of it.
// They live here rather than in `Suites.swift` because they are the only ones
// that import the app target, and `openForTesting` is the only seam into it.

/// A `MailBackend` that trashes whatever it is handed and remembers nothing
/// else. Enough for `AppModel.trash`, which only reads `moved` and `archived`.
struct AlwaysTrashesBackend: MailBackend {
    var primaryAddress: String { "me@ex.com" }

    func trash(_ uids: [MessageUID], recordOrigin: Bool) async throws -> TrashOutcome {
        TrashOutcome(moved: uids)
    }

    // Nothing here syncs; these exist to satisfy the protocol and say so if
    // a test ever reaches them by accident.
    func discoverAll(progress: @Sendable @escaping (SyncPhase) -> Void) async throws -> SyncResult {
        throw CancellationError()
    }
    func changes(
        since token: SyncToken?, progress: @Sendable @escaping (SyncPhase) -> Void
    ) async throws -> SyncResult {
        throw CancellationError()
    }
    func untrash(messageIDs: [String], to target: RestoreTarget) async throws -> Int { 0 }
    func verifyConnection() async throws {}
    func sendMail(to: String, subject: String, body: String, from: String?) async throws {}
    func gmailThreadID(for uid: MessageUID) async -> UInt64? { nil }
    func sendAsAddresses() async throws -> [String] { [] }
    func disconnect() async {}
}

@MainActor
@Suite("Ignoring a sender")
struct IgnoreWritesTests {
    /// A model open on a fresh store holding `messages`.
    func openModel(_ messages: [EmailMessage]) async -> (AppModel, MessageStore) {
        let store = try! MessageStore.inMemory()
        _ = try! store.upsert(messages)
        let model = AppModel()
        await model.openForTesting(store: store, backend: AlwaysTrashesBackend())
        return (model, store)
    }

    @Test("Trash and Ignore leaves the sender ignored")
    func trashAndIgnoreLeavesTheSenderIgnored() async {
        // The regression. `trashAndIgnore` trashes first, so by the time the
        // ignore runs the sender has no group at all — which is precisely when
        // deriving the write from `groups` wrote nothing while the toast said
        // otherwise (TASK-59).
        let id = GroupID(kind: .domain, key: "acme.com")
        let (model, store) = await openModel([
            makeMessage(1, from: "Acme <hi@acme.com>"),
            makeMessage(2, from: "Acme <hi@acme.com>"),
        ])

        await model.trashAndIgnore(id)

        eq(try! store.count(), 0, "every message went to Trash")
        expect(model.groups.isEmpty, "so the sender has no group left")
        expect(
            try! store.ignoredGroupKeys().contains(id.storageKey),
            "and the ignore is on file anyway")
        eq(
            model.toast?.message, "Trashed 2 messages and ignored the sender",
            "which is what the toast already claimed")
    }

    @Test("undoing Trash and Ignore takes the ignore back")
    func undoingTrashAndIgnoreTakesTheIgnoreBack() async {
        let id = GroupID(kind: .domain, key: "acme.com")
        let (model, store) = await openModel([makeMessage(1, from: "Acme <hi@acme.com>", messageId: "<1@acme>")])

        await model.trashAndIgnore(id)
        await model.runUndo()

        expect(try! store.ignoredGroupKeys().isEmpty, "the ignore is gone again")
    }

    @Test("a sender with no messages left can still be ignored")
    func aSenderWithNoMessagesLeftCanStillBeIgnored() async {
        // Ignoring a sender the store has no mail for is a coherent local
        // decision, not a no-op: it is what keeps them out of the working list
        // when they next write. So `ignore` must not require a present group.
        let (model, store) = await openModel([])
        let id = GroupID(kind: .domain, key: "gone.com")

        model.ignore([id])

        eq(try! store.ignoredGroupKeys(), [id.storageKey], "the record exists")
        eq(model.toast?.message, "Ignored 1 sender", "and the toast counts it")
    }

    @Test("the toast counts the senders actually ignored")
    func theToastCountsTheSendersActuallyIgnored() async {
        let (model, _) = await openModel([makeMessage(1, from: "Acme <hi@acme.com>")])

        model.ignore([
            GroupID(kind: .domain, key: "acme.com"),
            GroupID(kind: .domain, key: "gone.com"),
        ])

        eq(model.toast?.message, "Ignored 2 senders")
    }

    @Test("a Proposed row retired as ignored has a real ignore behind it")
    func aProposedRowRetiredAsIgnoredHasARealIgnoreBehindIt() async {
        // The second manifestation: the row leaves the proposal recording
        // `.ignore`, which is what an agent reads back. That claim has to be
        // true even when the sender's mail went first.
        // A proposal outlives the mail it was built from — it is written in one
        // session and reviewed in another, and the sender's messages may have
        // been trashed in between. The row is still there to decide on.
        let id = GroupID(kind: .domain, key: "acme.com")
        let store = try! MessageStore.inMemory()
        try! store.setProposal(SenderProposal(items: [proposalItem("acme.com")]))
        let model = AppModel()
        await model.openForTesting(store: store, backend: AlwaysTrashesBackend())
        expect(model.groups.isEmpty, "the sender has no mail on file")

        model.ignore([id])

        eq(model.proposalActions[id.storageKey], .ignore, "the row is recorded as ignored")
        eq(model.toast?.message, "Ignored 1 sender", "and the toast agrees")
        expect(
            try! store.ignoredGroupKeys().contains(id.storageKey),
            "and there is an ignore to back that up")
    }

    @Test("the domain-ignore offer survives the sender losing its mail")
    func theDomainIgnoreOfferSurvivesTheSenderLosingItsMail() async {
        // The offer gate is keyed on the ids, not on present groups: it widens
        // to the *siblings*, and the sender just ignored need not still be one.
        let one = GroupID(kind: .address, key: "a@mail.costco.com")
        let (model, _) = await openModel([
            makeMessage(1, from: "Costco <a@mail.costco.com>"),
            makeMessage(2, from: "Costco <b@shop.costco.com>"),
        ])
        // Split so each address is its own row — the offer only fires on one.
        model.splitByAddress(GroupID(kind: .domain, key: "costco.com"))
        await Task.yield()

        _ = await model.trash([one])
        model.ignore([one])

        eq(model.toast?.action?.label, "Also Ignore 1 at costco.com")
    }
}
