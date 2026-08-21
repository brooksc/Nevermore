import Foundation

/// The mailbox an MCP request is served from: which account is open, and its
/// store.
///
/// `NevermoreServer` is built once, when the local server starts, but the open
/// account changes underneath it — so this is set on the running server rather
/// than passed at init. Nil means no mailbox is open and every tool answers 503
/// instead of quietly serving an empty one, which an agent would read as "this
/// person has no senders".
public struct MCPContext: Sendable {
    public let account: String
    public let store: MessageStore

    public init(account: String, store: MessageStore) {
        self.account = account
        self.store = store
    }
}

/// The app's grouped read model, rebuilt from the store for one request.
///
/// Deliberately built here rather than read off `AppModel`: the model is
/// `@MainActor` and lives in the app target, so a server route that reached for
/// it could neither be reached from an actor nor tested without a UI. Everything
/// it needs — messages, grouping rules, ignore list, unsubscribe history,
/// decisions — is in the store, so this reconstructs the same rows from the same
/// inputs. The rules that decide what a row *means* (`Grouping`, `SenderCollection`,
/// `SenderState`) are shared, not re-implemented; if they change, both callers
/// change together.
///
/// Rebuilt per request, not cached: the app writes to this database whenever a
/// sync lands or the user acts, and an agent that read a cached snapshot would
/// be reasoning about a mailbox that no longer exists.
public struct MCPSnapshot: Sendable {
    public let account: String
    public let groups: [SenderGroup]
    public let ignoredKeys: Set<String>
    public let history: [String: MessageStore.UnsubscribeRecord]
    public let decisions: [String: MessageStore.SenderDecision]
    public let syncToken: SyncToken?
    public let messageCount: Int

    public init(
        account: String,
        groups: [SenderGroup],
        ignoredKeys: Set<String>,
        history: [String: MessageStore.UnsubscribeRecord],
        decisions: [String: MessageStore.SenderDecision],
        syncToken: SyncToken?,
        messageCount: Int
    ) {
        self.account = account
        self.groups = groups
        self.ignoredKeys = ignoredKeys
        self.history = history
        self.decisions = decisions
        self.syncToken = syncToken
        self.messageCount = messageCount
    }

    public static func load(_ context: MCPContext) throws -> MCPSnapshot {
        let store = context.store
        let messages = try store.allMessages()
        return MCPSnapshot(
            account: context.account,
            groups: Grouping(rules: store.groupingRules()).group(messages),
            ignoredKeys: try store.ignoredGroupKeys(),
            history: try store.unsubscribeHistory(),
            decisions: try store.allDecisions(),
            syncToken: try store.syncToken(),
            messageCount: messages.count)
    }

    // MARK: - Derived state

    /// What the app knows about a sender, in the form `SenderCollection.contains`
    /// wants. The same four facts `AppModel.state(of:)` assembles.
    public func state(of group: SenderGroup) -> SenderState {
        SenderState(
            isIgnored: ignoredKeys.contains(group.id.storageKey),
            isUnsubscribed: history[group.id.storageKey] != nil,
            hasReappeared: hasReappeared(group),
            hasMessages: !group.messages.isEmpty)
    }

    /// A sender that mailed again after a recorded unsubscribe attempt.
    public func hasReappeared(_ group: SenderGroup) -> Bool {
        guard let record = history[group.id.storageKey] else { return false }
        return group.messages.contains { $0.receivedAt > record.attemptedAt }
    }

    /// How many messages arrived after the recorded unsubscribe.
    public func messagesSinceUnsubscribe(_ group: SenderGroup) -> Int {
        guard let record = history[group.id.storageKey] else { return 0 }
        return group.messages.filter { $0.receivedAt > record.attemptedAt }.count
    }

    /// The collection a sender currently belongs to. Exactly one holds any
    /// sender that has messages, so naming it on every row saves an agent
    /// running four filtered queries to work out where a sender sits.
    public func collection(of group: SenderGroup) -> SenderCollection? {
        let state = state(of: group)
        return SenderCollection.allCases.first { $0.contains(state) }
    }

    public func groups(in collection: SenderCollection) -> [SenderGroup] {
        groups.filter { collection.contains(state(of: $0)) }
    }

    public func group(withStorageKey key: String) -> SenderGroup? {
        groups.first { $0.id.storageKey == key }
    }

    /// The agent's decision about a group, if any of its addresses carry one.
    ///
    /// Newest wins when a merged group holds several decided addresses: they are
    /// judgements about the same row, and the later one is the one that stands.
    public func decision(for group: SenderGroup) -> MessageStore.SenderDecision? {
        group.messages
            .compactMap { decisions[$0.sender.address.lowercased()] }
            .max { $0.decidedAt < $1.decidedAt }
    }
}
