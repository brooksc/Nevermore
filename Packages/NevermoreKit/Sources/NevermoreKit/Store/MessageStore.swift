import Foundation
import GRDB

/// Local SQLite store for message headers. Bodies are never stored.
///
/// WAL + `synchronous = NORMAL`: this is a cache that can be rebuilt from Gmail
/// in seconds, so the Python version's `FULL` + `journal_mode = DELETE` bought
/// durability nobody needed at a large cost in write speed.
public final class MessageStore: Sendable {
    private let pool: DatabasePool

    public init(path: String) throws {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }
        pool = try DatabasePool(path: path, configuration: config)
        try Self.backUpIfMigrationPending(path: path, pool: pool)
        try Self.migrator.migrate(pool)
    }

    /// Copy the database aside before a migration that hasn't run here before.
    ///
    /// Migrations are forward-only and a shipped one is never edited, so the
    /// realistic failure is a *new* migration going wrong on real data — at
    /// which point the user's only copy has already been rewritten. The cache is
    /// rebuildable, but re-reading a six-figure mailbox is a bad afternoon.
    ///
    /// Best-effort by design: a failed backup must not stop the app opening.
    /// One backup per schema version, overwritten if it already exists.
    private static func backUpIfMigrationPending(path: String, pool: DatabasePool) throws {
        let applied = try pool.read { try migrator.appliedIdentifiers($0) }
        let pending = migrator.migrations.filter { !applied.contains($0) }
        // Nothing applied yet means a brand-new database — nothing to lose.
        guard let next = pending.first, !applied.isEmpty else { return }

        let backup = "\(path).pre-\(next).bak"
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return }
        try? fm.removeItem(atPath: backup)
        do {
            try fm.copyItem(atPath: path, toPath: backup)
            Log.store.event("backed up database before migration '\(next)'")
        } catch {
            Log.store.problem("pre-migration backup failed: \(error.localizedDescription)")
        }
    }

    /// Ephemeral store for tests. Backed by a unique temp file (not `:memory:`,
    /// which GRDB's DatabasePool can't use because WAL needs a real file).
    public static func inMemory() throws -> MessageStore {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("nevermore-test-\(UUID().uuidString).sqlite").path
        return try MessageStore(path: path)
    }

    // MARK: - Schema

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()

        m.registerMigration("v1") { db in
            try db.create(table: "message") { t in
                t.primaryKey("uid", .integer)
                t.column("senderAddress", .text).notNull().indexed()
                t.column("senderHost", .text).notNull()
                t.column("senderName", .text).notNull().defaults(to: "")
                t.column("subject", .text).notNull().defaults(to: "")
                t.column("receivedAt", .double).notNull().indexed()
                t.column("isUnread", .boolean).notNull().defaults(to: true)
                t.column("unsubscribeRaw", .text)
                t.column("unsubscribePost", .text)
                t.column("deliveredTo", .text).notNull().defaults(to: "")
                t.column("syncedAt", .double).notNull()
            }

            // Keyed by GroupID.storageKey, which carries whether the key is a
            // domain or an address. The Python schema named this column `domain`
            // but stored an address in it for split groups.
            try db.create(table: "unsubscribeHistory") { t in
                t.primaryKey("groupKey", .text)
                t.column("url", .text)
                t.column("attemptedAt", .double).notNull()
                // 'requested' | 'confirmed' | 'failed'. The Python client always
                // reported success, which is why reappearing senders needed a
                // whole separate detection feature.
                t.column("outcome", .text).notNull()
            }

            // Ignoring is a sender-level decision. Storing it per-message, as
            // the Python version did, means new mail from an ignored sender
            // reappears at the next sync.
            try db.create(table: "ignoredSender") { t in
                t.primaryKey("groupKey", .text)
                t.column("ignoredAt", .double).notNull()
            }

            try db.create(table: "syncState") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
        }

        // Self-contained unsubscribe history: keep enough about each sender that
        // the record survives after its messages are deleted.
        m.registerMigration("v2-history-metadata") { db in
            try db.alter(table: "unsubscribeHistory") { t in
                t.add(column: "senderName", .text).notNull().defaults(to: "")
                t.add(column: "senderEmail", .text).notNull().defaults(to: "")
                t.add(column: "senderDomain", .text).notNull().defaults(to: "")
            }
        }

        // Message-ID, so a trashed message can be found again in Trash for undo.
        m.registerMigration("v3-message-id") { db in
            try db.alter(table: "message") { t in
                t.add(column: "messageId", .text).notNull().defaults(to: "")
            }
        }
        // RFC 2919 List-ID, so the UI can tell a discussion list or a
        // notification stream from a marketing blast.
        m.registerMigration("v4-list-id") { db in
            try db.alter(table: "message") { t in
                t.add(column: "listId", .text)
            }
        }

        // What an external agent decided about a sender, and why.
        //
        // Keyed by ADDRESS, not GroupID, and deliberately so: `Grouping.Rule`
        // moves a sender between a domain group and an address group whenever
        // the user splits or merges, so a GroupID key would throw the agent's
        // judgement away every time the table was regrouped. Addresses don't
        // move. The roll-up to whatever group is current happens at read time.
        m.registerMigration("v5-sender-decisions") { db in
            try db.create(table: "senderDecision") { t in
                t.primaryKey("address", .text)
                // classification, reason and context are opaque agent text.
                // Nothing in this app parses, matches or branches on them.
                t.column("classification", .text).notNull()
                t.column("reason", .text).notNull()
                // NULL when the decision isn't contingent on any situation.
                // Indexed because "what did I decide during job-search-2026"
                // is the query that lets a whole cohort be re-opened at once.
                t.column("context", .text).indexed()
                t.column("decidedAt", .double).notNull()
            }
        }
        return m
    }

    // MARK: - Messages

    public func upsert(_ messages: [EmailMessage]) throws {
        guard !messages.isEmpty else { return }
        let now = Date().timeIntervalSince1970
        try pool.write { db in
            for m in messages {
                try db.execute(
                    sql: """
                        INSERT INTO message
                          (uid, senderAddress, senderHost, senderName, subject, receivedAt,
                           isUnread, unsubscribeRaw, unsubscribePost, deliveredTo, syncedAt,
                           messageId, listId)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(uid) DO UPDATE SET
                          isUnread = excluded.isUnread,
                          syncedAt = excluded.syncedAt,
                          -- Re-sync heals rows written by an older, buggier
                          -- version rather than leaving them stale forever.
                          unsubscribeRaw = excluded.unsubscribeRaw,
                          unsubscribePost = excluded.unsubscribePost,
                          deliveredTo = excluded.deliveredTo,
                          messageId = excluded.messageId,
                          listId = excluded.listId
                        """,
                    arguments: [
                        Int(m.uid.value), m.sender.address, m.sender.host, m.sender.displayName,
                        m.subject, m.receivedAt.timeIntervalSince1970, m.isUnread,
                        // The whole header, not just the first target. Storing
                        // one URL discarded every fallback target, and for
                        // mailto: it discarded the query string — where senders
                        // put the token that makes the unsubscribe work.
                        m.unsubscribe?.raw,
                        // Store the canonical RFC 8058 token, because that is
                        // exactly what ListUnsubscribe looks for when decoding.
                        m.unsubscribe?.supportsOneClick == true
                            ? "List-Unsubscribe=One-Click" : nil,
                        m.deliveredTo, now, m.messageId, m.listID,
                    ])
            }
        }
    }

    /// All stored messages, newest first.
    ///
    /// Ignored senders are *not* filtered here — that would keep them out of the
    /// grouped model entirely, so the Ignored collection would have nothing to
    /// show. Ignore is applied per-collection in the model instead.
    public func allMessages() throws -> [EmailMessage] {
        try pool.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM message ORDER BY receivedAt DESC")
                .compactMap(Self.decode)
        }
    }

    public func count() throws -> Int {
        try pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM message") ?? 0
        }
    }

    public func delete(uids: [MessageUID]) throws {
        guard !uids.isEmpty else { return }
        try pool.write { db in
            for chunk in stride(from: 0, to: uids.count, by: 500).map({
                Array(uids[$0..<min($0 + 500, uids.count)])
            }) {
                let placeholders = chunk.map { _ in "?" }.joined(separator: ",")
                try db.execute(
                    sql: "DELETE FROM message WHERE uid IN (\(placeholders))",
                    arguments: StatementArguments(chunk.map { Int($0.value) })
                )
            }
        }
    }

    public func deleteAllMessages() throws {
        _ = try pool.write { db in try db.execute(sql: "DELETE FROM message") }
    }

    private static func decode(_ row: Row) -> EmailMessage? {
        guard let uid: Int = row["uid"] else { return nil }
        let raw: String? = row["unsubscribeRaw"]
        return EmailMessage(
            uid: MessageUID(UInt32(uid)),
            sender: EmailSender(
                displayName: row["senderName"] ?? "",
                address: row["senderAddress"] ?? "",
                host: row["senderHost"] ?? ""
            ),
            subject: row["subject"] ?? "",
            receivedAt: Date(timeIntervalSince1970: row["receivedAt"] ?? 0),
            isUnread: row["isUnread"] ?? false,
            // Rows written before the full header was stored hold a bare URI
            // with no angle brackets, which the parser needs. Detect and wrap
            // those; anything already bracketed is a whole header, pass it
            // through. Re-syncing rewrites old rows into the new form.
            unsubscribe: ListUnsubscribe(
                header: raw.map { $0.contains("<") ? $0 : "<\($0)>" },
                postHeader: row["unsubscribePost"]
            ),
            deliveredTo: row["deliveredTo"] ?? "",
            messageId: row["messageId"] ?? "",
            listID: row["listId"]
        )
    }

    // MARK: - Ignored senders

    public func ignore(_ id: GroupID) throws {
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO ignoredSender (groupKey, ignoredAt) VALUES (?, ?)
                    ON CONFLICT(groupKey) DO NOTHING
                    """,
                arguments: [id.storageKey, Date().timeIntervalSince1970])
        }
    }

    public func unignore(_ id: GroupID) throws {
        try pool.write { db in
            try db.execute(
                sql: "DELETE FROM ignoredSender WHERE groupKey = ?", arguments: [id.storageKey])
        }
    }

    public func ignoredGroupKeys() throws -> Set<String> {
        try pool.read { db in
            Set(try String.fetchAll(db, sql: "SELECT groupKey FROM ignoredSender"))
        }
    }

    // MARK: - Unsubscribe history

    public enum Outcome: String, Sendable {
        /// The request was sent and accepted, but nothing confirms it worked.
        case requested
        /// A confirmation page or reply positively acknowledged the request.
        case confirmed
        case failed
    }

    /// A durable record of one unsubscribe, independent of whether the sender's
    /// messages still exist locally.
    public struct UnsubscribeRecord: Sendable, Identifiable {
        public let groupKey: String
        public let senderName: String
        public let senderEmail: String
        public let senderDomain: String
        /// The unsubscribe / email-preferences URL, if the sender published one —
        /// the closest thing to a "manage or re-subscribe" link.
        public let url: String?
        public let attemptedAt: Date
        public let outcome: Outcome

        public var id: String { groupKey }
    }

    public func recordUnsubscribe(
        _ id: GroupID,
        senderName: String,
        senderEmail: String,
        senderDomain: String,
        url: String?,
        outcome: Outcome,
        // Overridable so restoring a forgotten record keeps its original time.
        // Stamping "now" would move the record past the sender's existing mail
        // and quietly clear their reappeared status.
        attemptedAt: Date = Date()
    ) throws {
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO unsubscribeHistory
                      (groupKey, senderName, senderEmail, senderDomain, url, attemptedAt, outcome)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(groupKey) DO UPDATE SET
                      senderName = excluded.senderName, senderEmail = excluded.senderEmail,
                      senderDomain = excluded.senderDomain, url = excluded.url,
                      attemptedAt = excluded.attemptedAt, outcome = excluded.outcome
                    """,
                arguments: [
                    id.storageKey, senderName, senderEmail, senderDomain, url,
                    attemptedAt.timeIntervalSince1970, outcome.rawValue,
                ])
        }
    }

    public func unsubscribeHistory() throws -> [String: UnsubscribeRecord] {
        try pool.read { db in
            var out: [String: UnsubscribeRecord] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT * FROM unsubscribeHistory") {
                guard let key: String = row["groupKey"],
                    let outcome = Outcome(rawValue: row["outcome"] ?? "")
                else { continue }
                out[key] = UnsubscribeRecord(
                    groupKey: key,
                    senderName: row["senderName"] ?? "",
                    senderEmail: row["senderEmail"] ?? "",
                    senderDomain: row["senderDomain"] ?? "",
                    url: row["url"],
                    attemptedAt: Date(timeIntervalSince1970: row["attemptedAt"] ?? 0),
                    outcome: outcome)
            }
            return out
        }
    }

    public func forgetUnsubscribe(_ id: GroupID) throws {
        try pool.write { db in
            try db.execute(
                sql: "DELETE FROM unsubscribeHistory WHERE groupKey = ?",
                arguments: [id.storageKey])
        }
    }

    // MARK: - Agent decisions

    /// What an external agent decided about one sender, and why.
    ///
    /// `classification`, `reason` and `context` are opaque text written by the
    /// agent and stored verbatim. Nevermore never parses them, never matches on
    /// them, and never branches on their content — that is what keeps an LLM out
    /// of this app while still letting the agent's judgement be durable. The
    /// only thing the store compares is `address`, which is an identifier.
    ///
    /// Lifetime: a decision lives in the account's own database, alongside its
    /// unsubscribe history and ignore list. It survives sync, quit, regrouping
    /// and re-sync, and it dies with the account — `resetAllState` and removing
    /// an account both delete that file. See `forgetAllDecisions()`.
    public struct SenderDecision: Sendable, Hashable, Identifiable {
        /// The sender address the judgement is about, lowercased. Never a
        /// `GroupID`: grouping is mutable and would take the record with it.
        public let address: String
        public let classification: String
        public let reason: String
        /// The situation this decision was contingent on (e.g. `job-search-2026`),
        /// or nil when the decision stands on its own. A label to match exactly,
        /// not a phrase to interpret.
        public let context: String?
        public let decidedAt: Date

        public var id: String { address }

        public init(
            address: String, classification: String, reason: String, context: String?,
            decidedAt: Date
        ) {
            self.address = address
            self.classification = classification
            self.reason = reason
            self.context = context
            self.decidedAt = decidedAt
        }
    }

    /// Record (or replace) the agent's decision about one sender.
    ///
    /// One decision per address: a later call supersedes the earlier judgement
    /// rather than accumulating a history nothing would ever read back.
    public func recordDecision(
        address: String,
        classification: String,
        reason: String,
        context: String? = nil,
        decidedAt: Date = Date()
    ) throws {
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO senderDecision
                      (address, classification, reason, context, decidedAt)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(address) DO UPDATE SET
                      classification = excluded.classification, reason = excluded.reason,
                      context = excluded.context, decidedAt = excluded.decidedAt
                    """,
                arguments: [
                    Self.addressKey(address), classification, reason, context,
                    decidedAt.timeIntervalSince1970,
                ])
        }
    }

    public func decision(forAddress address: String) throws -> SenderDecision? {
        try pool.read { db in
            try Row.fetchOne(
                db, sql: "SELECT * FROM senderDecision WHERE address = ?",
                arguments: [Self.addressKey(address)]
            ).flatMap(Self.decodeDecision)
        }
    }

    /// Every decision, keyed by sender address.
    public func allDecisions() throws -> [String: SenderDecision] {
        try pool.read { db in
            var out: [String: SenderDecision] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT * FROM senderDecision") {
                guard let d = Self.decodeDecision(row) else { continue }
                out[d.address] = d
            }
            return out
        }
    }

    /// Decisions carrying exactly this context label, newest first.
    ///
    /// An exact match on a stored field, deliberately not a search: "I'm done
    /// job hunting, what can go now" is answerable because the agent wrote the
    /// label, not because Nevermore understands the words in it.
    public func decisions(inContext context: String) throws -> [SenderDecision] {
        try pool.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM senderDecision WHERE context = ? ORDER BY decidedAt DESC",
                arguments: [context]
            ).compactMap(Self.decodeDecision)
        }
    }

    /// The distinct context labels in use, so a caller can offer the cohorts
    /// that exist without having to invent or guess at a label.
    public func decisionContexts() throws -> [String] {
        try pool.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT context FROM senderDecision
                    WHERE context IS NOT NULL ORDER BY context
                    """)
        }
    }

    /// The decisions attached to the senders in `group`, as grouping stands now.
    ///
    /// This is the whole point of keying on address: a merged `amazon.com` group
    /// rolls up every decided address beneath it, and after a split each address
    /// group carries away exactly its own — in either direction, and back again,
    /// without losing a record.
    public func decisions(for group: SenderGroup) throws -> [SenderDecision] {
        try decisions(forAddresses: group.messages.map(\.sender.address))
    }

    /// The decisions for a set of sender addresses, newest first. Addresses with
    /// no decision are simply absent.
    public func decisions(forAddresses addresses: [String]) throws -> [SenderDecision] {
        let keys = Array(Set(addresses.map(Self.addressKey)))
        guard !keys.isEmpty else { return [] }
        return try pool.read { db in
            var out: [SenderDecision] = []
            for chunk in stride(from: 0, to: keys.count, by: 500).map({
                Array(keys[$0..<min($0 + 500, keys.count)])
            }) {
                let placeholders = chunk.map { _ in "?" }.joined(separator: ",")
                out += try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM senderDecision WHERE address IN (\(placeholders))",
                    arguments: StatementArguments(chunk)
                ).compactMap(Self.decodeDecision)
            }
            return out.sorted { $0.decidedAt > $1.decidedAt }
        }
    }

    public func forgetDecision(forAddress address: String) throws {
        try pool.write { db in
            try db.execute(
                sql: "DELETE FROM senderDecision WHERE address = ?",
                arguments: [Self.addressKey(address)])
        }
    }

    /// Drop every decision in this account's database.
    ///
    /// Explicit rather than incidental: resetting the app and removing an
    /// account both delete the database file, so decisions go with it either
    /// way. They are judgements about *this* mailbox's senders, and their
    /// free-text reasons describe the user's own situation, so keeping them
    /// alive past "return Nevermore to its never-launched state" would be both
    /// surprising and a small privacy leak.
    public func forgetAllDecisions() throws {
        try pool.write { db in try db.execute(sql: "DELETE FROM senderDecision") }
    }

    /// Addresses are identifiers, so they are matched case-insensitively —
    /// unlike the agent's text, which is never touched.
    private static func addressKey(_ address: String) -> String {
        address.lowercased()
    }

    private static func decodeDecision(_ row: Row) -> SenderDecision? {
        guard let address: String = row["address"] else { return nil }
        return SenderDecision(
            address: address,
            classification: row["classification"] ?? "",
            reason: row["reason"] ?? "",
            context: row["context"],
            decidedAt: Date(timeIntervalSince1970: row["decidedAt"] ?? 0))
    }

    // MARK: - Sync state

    public func syncToken() throws -> SyncToken? {
        let raw = try pool.read { db in
            try String.fetchOne(
                db, sql: "SELECT value FROM syncState WHERE key = 'syncToken'")
        }
        guard let data = raw?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SyncToken.self, from: data)
    }

    /// Forget where the last sync stopped, forcing the next one to rediscover
    /// the whole mailbox. The only way to notice messages deleted on the
    /// server: incremental sync searches forward from the token and upserts,
    /// so it can add rows but never removes them.
    public func clearSyncToken() throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM syncState WHERE key = 'syncToken'")
        }
    }

    public func setSyncToken(_ token: SyncToken) throws {
        let json = String(decoding: try JSONEncoder().encode(token), as: UTF8.self)
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO syncState (key, value) VALUES ('syncToken', ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """,
                arguments: [json])
        }
    }

    // MARK: - Grouping rules

    /// Persisted per-domain grouping corrections (domain -> "split"/"merge").
    public func groupingRules() -> [String: Grouping.Rule] {
        let raw = try? pool.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM syncState WHERE key = 'groupingRules'")
        }
        guard let value = raw ?? nil, let data = value.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String: Grouping.Rule].self, from: data)
        else { return [:] }
        return decoded
    }

    public func setGroupingRules(_ rules: [String: Grouping.Rule]) {
        let json = (try? JSONEncoder().encode(rules))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        try? pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO syncState (key, value) VALUES ('groupingRules', ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """,
                arguments: [json])
        }
    }

    // MARK: - Agent proposal

    private static let proposalKey = "agentProposal"

    /// The proposal currently awaiting review, if any.
    ///
    /// Stored as JSON in `syncState` rather than in a table of its own, like
    /// the grouping rules: there is exactly one live proposal, it is read and
    /// written whole, and nothing ever queries it by field. A table would buy
    /// indexes nobody uses and a migration to maintain.
    ///
    /// It lives in the account's database, so it is per-account, and it dies
    /// with the account — which is right, since a proposal names that mailbox's
    /// senders and carries an agent's free-text reasons about them.
    public func proposal() -> SenderProposal? {
        let raw = try? pool.read { db in
            try String.fetchOne(
                db, sql: "SELECT value FROM syncState WHERE key = ?",
                arguments: [Self.proposalKey])
        }
        guard let value = raw ?? nil, let data = value.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(SenderProposal.self, from: data)
    }

    /// Replace the live proposal. One at a time on purpose: a second proposal
    /// arriving while the first is on screen would either queue up unreviewed
    /// or silently merge, and both leave the human reviewing something nobody
    /// proposed.
    public func setProposal(_ proposal: SenderProposal) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let json = String(decoding: try encoder.encode(proposal), as: UTF8.self)
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO syncState (key, value) VALUES (?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """,
                arguments: [Self.proposalKey, json])
        }
    }

    /// Drop the proposal. Touches nothing else — dismissing a proposal is the
    /// human declining to act, and it must not act.
    public func clearProposal() throws {
        try pool.write { db in
            try db.execute(
                sql: "DELETE FROM syncState WHERE key = ?", arguments: [Self.proposalKey])
        }
    }

    /// A persisted set of strings under `key`. Best-effort — used for
    /// bookkeeping (e.g. which reappeared senders have already been notified).
    public func stringSet(forKey key: String) -> Set<String> {
        let raw = try? pool.read { db in
            try String.fetchOne(
                db, sql: "SELECT value FROM syncState WHERE key = ?", arguments: [key])
        }
        guard let value = raw ?? nil, let data = value.data(using: .utf8),
            let array = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(array)
    }

    public func setStringSet(_ set: Set<String>, forKey key: String) {
        let json = (try? JSONEncoder().encode(Array(set)))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        try? pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO syncState (key, value) VALUES (?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """,
                arguments: [key, json])
        }
    }
}
