import AppIntents
import Foundation
import NevermoreKit

/// A sender, as Shortcuts sees one.
///
/// The id is `GroupID.storageKey` — the same id the MCP surface hands out, and
/// it carries the same warning: it is derived from grouping, so splitting or
/// merging a domain changes it. A shortcut holding a stale id resolves to
/// nothing and says so rather than acting on the wrong sender.
struct SenderEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Sender", numericFormat: "\(placeholder: .int) senders")

    static let defaultQuery = SenderEntityQuery()

    let id: String

    @Property(title: "Name") var name: String
    @Property(title: "Email Address") var email: String
    @Property(title: "Messages") var messageCount: Int
    /// How many messages arrived *after* the recorded unsubscribe — the number
    /// the Reappeared collection is actually claiming. Zero for a sender with no
    /// unsubscribe on file, which is not the same fact and is why the reappeared
    /// intent returns only senders that are genuinely in that collection.
    @Property(title: "Messages Since Unsubscribe") var messagesSinceUnsubscribe: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(email)")
    }

    init(id: String, name: String, email: String, messageCount: Int, messagesSince: Int) {
        self.id = id
        self.name = name
        self.email = email
        self.messageCount = messageCount
        self.messagesSinceUnsubscribe = messagesSince
    }
}

/// How Shortcuts finds a sender to put in a parameter.
///
/// `EntityStringQuery` rather than a free-text parameter so the person building
/// the shortcut picks a sender that exists, from the mailbox that is actually
/// open, instead of typing a name that will be matched at run time against a
/// mailbox that has changed since.
struct SenderEntityQuery: EntityStringQuery {
    func entities(for identifiers: [SenderEntity.ID]) async throws -> [SenderEntity] {
        let wanted = Set(identifiers)
        return await MainActor.run {
            (try? IntentContext.allSenders())?.filter { wanted.contains($0.id) } ?? []
        }
    }

    func entities(matching string: String) async throws -> [SenderEntity] {
        await MainActor.run {
            guard let all = try? IntentContext.allSenders() else { return [] }
            return
                all
                .compactMap { sender -> (SenderEntity, Int)? in
                    SenderMatch.rank(string, name: sender.name, address: sender.email)
                        .map { (sender, $0) }
                }
                .sorted { $0.1 < $1.1 }
                .map(\.0)
        }
    }

    func suggestedEntities() async throws -> [SenderEntity] {
        await MainActor.run { (try? IntentContext.allSenders()) ?? [] }
    }
}
