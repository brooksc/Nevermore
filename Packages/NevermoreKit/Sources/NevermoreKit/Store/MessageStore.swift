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
                           messageId)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(uid) DO UPDATE SET
                          isUnread = excluded.isUnread,
                          syncedAt = excluded.syncedAt,
                          -- Re-sync heals rows written by an older, buggier
                          -- version rather than leaving them stale forever.
                          unsubscribeRaw = excluded.unsubscribeRaw,
                          unsubscribePost = excluded.unsubscribePost,
                          deliveredTo = excluded.deliveredTo,
                          messageId = excluded.messageId
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
                        m.deliveredTo, now, m.messageId,
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
            messageId: row["messageId"] ?? ""
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
