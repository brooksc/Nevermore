import Foundation
import SwiftMail

/// Any provider over IMAP, authenticated with an app-specific password.
///
/// Plain IMAP + an app password was chosen over provider-specific APIs (e.g. the
/// Gmail API) because an app password is a *user credential* rather than an OAuth
/// grant: no Cloud project, no consent screen, no verification, no annual
/// security assessment, no user cap, and no refresh-token expiry — and the same
/// code works across Gmail, iCloud, Yahoo, Fastmail, and more. See PLAN.md §1.
public actor IMAPBackend: MailBackend {
    /// Connection endpoints. Folder names are discovered per-account at connect
    /// (SPECIAL-USE), not hard-coded, so this works on any IMAP provider.
    public struct Config: Sendable {
        public var imapHost: String
        public var imapPort: Int
        public var smtpHost: String
        public var smtpPort: Int
        /// Fallback to INBOX rather than an all-mail folder for the discovery
        /// scope. Providers without a virtual all-mail folder (i.e. not Gmail)
        /// have their newsletters in the inbox.
        public let inboxMailbox = "INBOX"

        public init(imapHost: String, imapPort: Int = 993, smtpHost: String, smtpPort: Int = 587) {
            self.imapHost = imapHost
            self.imapPort = imapPort
            self.smtpHost = smtpHost
            self.smtpPort = smtpPort
        }

        public init(provider: MailProvider) {
            self.init(
                imapHost: provider.imapHost, imapPort: provider.imapPort,
                smtpHost: provider.smtpHost, smtpPort: provider.smtpPort)
        }
    }

    /// Folders resolved at connect: the scope to search, plus Sent and Trash.
    struct Folders {
        var searchScope: String  // an "all mail" folder if the provider has one, else INBOX
        var sent: String
        var trash: String
    }

    /// How many UIDs to fetch per FETCH command.
    ///
    /// The probe measured ~1,084 msg/s at 500 per command. Chunking also gives
    /// the progress callback something to report and bounds the response buffer.
    private static let fetchChunkSize = 500

    public nonisolated let primaryAddress: String
    private let password: String
    private let config: Config

    private var server: IMAPServer?
    private var folders: Folders?
    private var cachedSendAs: [String]?

    public init(address: String, appPassword: String, config: Config) {
        self.primaryAddress = address
        // Providers show app passwords in groups of four; users paste verbatim.
        self.password = appPassword.replacingOccurrences(of: " ", with: "")
        self.config = config
    }

    /// Convenience: detect the provider from the address, falling back to Gmail.
    public init(address: String, appPassword: String) {
        let provider = MailProvider.detect(forEmail: address) ?? .gmail
        self.init(address: address, appPassword: appPassword, config: Config(provider: provider))
    }

    // MARK: - Connection

    private func connected() async throws -> IMAPServer {
        if let server { return server }
        Log.backend.detail("connecting to \(config.imapHost):\(config.imapPort)")
        let s = IMAPServer(
            host: config.imapHost,
            port: config.imapPort,
            // A SEARCH over a six-figure mailbox returns a UID list that can
            // approach the 1 MB default and fail with PayloadTooLargeError.
            responseBufferLimit: 32 * 1024 * 1024
        )
        do {
            try await s.connect()
            try await s.login(username: primaryAddress, password: password)
        } catch {
            Log.backend.problem("login failed: \(error.localizedDescription)")
            throw MailBackendError.authenticationFailed(error.localizedDescription)
        }
        Log.backend.detail("connected and authenticated")
        server = s
        return s
    }

    /// Resolve the search-scope / Sent / Trash folders for this account. Sent and
    /// Trash come from the IMAP SPECIAL-USE extension (or name heuristics); the
    /// search scope is an all-mail folder when the provider has one (Gmail), else
    /// the inbox.
    private func resolvedFolders(on server: IMAPServer) async throws -> Folders {
        if let folders { return folders }

        // SPECIAL-USE gives Sent/Trash reliably (falls back to name heuristics
        // internally). It does NOT surface Gmail's All Mail — the library models
        // no `\All` attribute — so All Mail is found by scanning every mailbox.
        let special = (try? await server.listSpecialUseMailboxes()) ?? []
        let allMailboxes = (try? await server.listMailboxes()) ?? special

        func named(in list: [String], _ candidates: [String]) -> String? {
            list.first { name in
                candidates.contains { name.caseInsensitiveCompare($0) == .orderedSame }
            }
        }
        let allNames = allMailboxes.map(\.name)

        let sent =
            special.first { $0.attributes.contains(.sent) }?.name
            ?? named(in: allNames, ["Sent", "Sent Mail", "Sent Items", "Sent Messages", "[Gmail]/Sent Mail"])
            ?? "Sent"
        let trash =
            special.first { $0.attributes.contains(.trash) }?.name
            ?? named(in: allNames, ["Trash", "Deleted Messages", "Deleted Items", "Bin", "[Gmail]/Trash"])
            ?? "Trash"
        // Gmail's virtual All Mail (every message regardless of label, minus
        // Trash/Spam) is the ideal discovery scope. Providers without one have
        // their newsletters in the inbox, so fall back to INBOX.
        let searchScope =
            allNames.first { $0.lowercased().hasSuffix("all mail") } ?? config.inboxMailbox

        let resolved = Folders(searchScope: searchScope, sent: sent, trash: trash)
        Log.backend.event(
            "resolved folders — scope: \(searchScope), sent: \(sent), trash: \(trash)")
        folders = resolved
        return resolved
    }

    public func disconnect() async {
        try? await server?.disconnect()
        server = nil
        Log.backend.detail("disconnected")
    }

    /// Prove the credentials work by forcing an authenticated connection.
    /// Throws `MailBackendError.authenticationFailed` on bad credentials (unlike
    /// `sendAsAddresses`, which swallows connection errors), or a transient
    /// error on network/throttle issues.
    public func verifyConnection() async throws {
        _ = try await connected()
    }

    // MARK: - Discovery

    public func discoverAll(
        progress: @Sendable @escaping (SyncPhase) -> Void
    ) async throws -> (messages: [EmailMessage], token: SyncToken) {
        let server = try await connected()
        let folders = try await resolvedFolders(on: server)
        let selection = try await select(folders.searchScope, on: server)

        // Pure RFC 3501. An empty HEADER value matches any message that *has*
        // the header, so this finds every newsletter regardless of which mailbox
        // category it landed in — no X-GM-RAW, and so no dependency fork.
        //
        // Run it in date windows rather than one command: an unbounded search
        // over a large mailbox takes ~94s and SwiftMail hard-codes a 60s command
        // timeout. Windowing also lets Gmail use its date index, and gives the
        // UI something honest to show during the slowest part of first run.
        let windows = Self.dateWindows()
        Log.backend.event("full discovery: \(windows.count) date windows")
        var found: Set<UInt32> = []

        for (index, window) in windows.enumerated() {
            try Task.checkCancellation()
            let uids = try await searchWindow(window, on: server, depth: 0)
            found.formUnion(uids)
            Log.backend.detail("window \(index + 1)/\(windows.count): +\(uids.count), \(found.count) total")
            progress(.discovering(window: index + 1, of: windows.count, found: found.count))
        }

        let sorted = found.sorted()
        Log.backend.event("discovery found \(sorted.count) messages; fetching headers")
        let messages = try await fetch(
            uids: UIDSet(sorted.map { UID($0) }), from: server, progress: progress
        )
        return (
            filterOutOwnMail(messages),
            SyncToken(
                uidValidity: selection.uidValidity.value,
                highestUID: sorted.last ?? selection.uidNext.value,
                lastSyncedAt: Date()
            )
        )
    }

    /// One-year windows from 2004 (roughly the dawn of modern webmail) to
    /// tomorrow, newest first.
    ///
    /// Newest first so the senders a user actually cares about populate the
    /// table before the archaeology finishes. Empty early windows are cheap.
    static func dateWindows(now: Date = Date()) -> [(start: Date, end: Date)] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let floor = calendar.date(from: DateComponents(year: 2004, month: 1, day: 1))!
        let ceiling = calendar.date(byAdding: .day, value: 1, to: now)!

        var windows: [(Date, Date)] = []
        var end = ceiling
        while end > floor {
            let start = max(calendar.date(byAdding: .year, value: -1, to: end)!, floor)
            windows.append((start, end))
            end = start
        }
        return windows
    }

    /// The UIDs an extended search matched.
    ///
    /// `ExtendedSearchResult.all` is `nil` for "nothing matched", not just for
    /// "the server didn't report it": on the ESEARCH path a server that finds
    /// nothing omits the ALL datum, and on the plain-SEARCH fallback SwiftMail
    /// nils out an empty set itself. The deprecated `search` returned an empty
    /// set for that case, so collapsing `nil` to empty here keeps every caller
    /// reading the way it always did — an absent answer must never be mistaken
    /// for an unfinished one.
    ///
    /// Separate so a test can pin both directions. The two plausible
    /// "simplifications" of this line (`result.all!`, or treating `nil` as an
    /// error) both fail the same way: discovery returns fewer messages, sync
    /// reports success, and nobody finds out.
    ///
    /// It used to be `public` purely to be reachable from the test executable,
    /// which made it the only public signature in the kit naming a SwiftMail
    /// type. The suite is a real test target now, so `@testable import` reaches
    /// it and the API surface goes back to nothing (TASK-19).
    static func matched(_ result: ExtendedSearchResult<UID>) -> UIDSet {
        result.all ?? UIDSet()
    }

    /// Search one date window, halving it on error until it fits within the
    /// library's command timeout *and* under swift-nio-imap's fixed 8 KB frame
    /// limit (a `SEARCH` whose one-line UID result exceeds that throws
    /// PayloadTooLargeError). Halves down to a one-hour floor — far below the
    /// point any personal account produces >1000 unsubscribe emails in a window.
    ///
    /// The halving stays even though ESEARCH returns the match set as compacted
    /// ranges rather than one UID per number, which makes the frame limit much
    /// harder to hit: SwiftMail falls back to a plain `SEARCH` on any server
    /// that doesn't advertise ESEARCH, and the 60s timeout is unaffected either
    /// way. Nothing about the window strategy is safe to relax on the strength
    /// of a capability the next server might not have.
    private func searchWindow(
        _ window: (start: Date, end: Date),
        on server: IMAPServer,
        depth: Int
    ) async throws -> [UInt32] {
        do {
            let result: ExtendedSearchResult<UID> = try await server.extendedSearch(
                criteria: [
                    .header("List-Unsubscribe", ""),
                    .not(.flagged),
                    .since(window.start),
                    .before(window.end),
                ]
            )
            return Self.matched(result).toArray().map(\.value)
        } catch {
            let span = window.end.timeIntervalSince(window.start)
            guard depth < 14, span > 3600 else { throw error }

            let mid = window.start.addingTimeInterval(span / 2)
            let first = try await searchWindow((window.start, mid), on: server, depth: depth + 1)
            let second = try await searchWindow((mid, window.end), on: server, depth: depth + 1)
            return first + second
        }
    }

    public func changes(
        since token: SyncToken?,
        progress: @Sendable @escaping (SyncPhase) -> Void
    ) async throws -> (messages: [EmailMessage], token: SyncToken) {
        guard let token else { return try await discoverAll(progress: progress) }

        let server = try await connected()
        let folders = try await resolvedFolders(on: server)
        let selection = try await select(folders.searchScope, on: server)

        // UIDVALIDITY changing means the server's UID space was reset and every
        // stored UID is meaningless. Only a full rediscovery is correct.
        guard selection.uidValidity.value == token.uidValidity else {
            Log.backend.event("UIDVALIDITY changed — full rediscovery")
            return try await discoverAll(progress: progress)
        }

        // Search by date, overlapping the previous run by two days. IMAP SINCE
        // has day granularity and servers disagree about timezone handling, so
        // the overlap avoids dropping messages at the boundary; re-fetched UIDs
        // collapse harmlessly on the store's primary key.
        guard let lastSync = token.lastSyncedAt else {
            Log.backend.event("no lastSyncedAt in token — full rediscovery")
            return try await discoverAll(progress: progress)
        }
        let since = lastSync.addingTimeInterval(-2 * 86400)

        // Use the same adaptive windowing as discovery so a busy window can't
        // overflow the 8 KB frame limit.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let ceiling = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let uidValues = try await searchWindow((since, ceiling), on: server, depth: 0)
        let candidates = UIDSet(uidValues.map { UID($0) })
        Log.backend.event("incremental sync since \(lastSync): \(candidates.count) candidate messages")

        let messages = try await fetch(uids: candidates, from: server, progress: progress)
        return (
            filterOutOwnMail(messages),
            SyncToken(
                uidValidity: selection.uidValidity.value,
                highestUID: max(
                    token.highestUID, maxUID(in: candidates, fallback: token.highestUID)),
                lastSyncedAt: Date()
            )
        )
    }

    // MARK: - Fetching

    private func fetch(
        uids: UIDSet,
        from server: IMAPServer,
        progress: @Sendable @escaping (SyncPhase) -> Void
    ) async throws -> [EmailMessage] {
        guard !uids.isEmpty else { return [] }

        let all = uids.toArray()
        let total = all.count
        var result: [EmailMessage] = []
        result.reserveCapacity(total)

        // `Delivered-To` is set by the receiving mail server (Gmail and many
        // other MTAs), so it survives forwarding in a way the sender-controlled
        // `To` does not — it is what makes send-as alias detection work. Absent
        // on providers that don't set it, in which case the feature degrades to
        // the `To` header.
        // Message-ID is fetched explicitly so trash-undo can find a message again
        // in the Trash folder (IMAP UIDs differ per folder).
        // Authentication-Results joins this list only when SyncHeaderFields says
        // so — it is the one field here whose per-message cost nobody has
        // measured yet (TASK-36).
        let headerFields =
            FetchMessageInfoOptions.newsletterHeaderFields + ["Delivered-To", "To", "Message-ID"]
            + SyncHeaderFields.optional

        var offset = 0
        while offset < total {
            try Task.checkCancellation()
            let end = min(offset + Self.fetchChunkSize, total)
            let chunk = UIDSet(Array(all[offset..<end]))

            let infos = try await server.fetchMessageInfosBulk(
                using: chunk, options: .slim, headerFields: headerFields
            )
            result.append(contentsOf: infos.compactMap(Self.convert))

            offset = end
            progress(.fetching(done: offset, of: total))
        }
        Log.backend.detail("fetched headers for \(result.count)/\(total) messages")
        return result
    }

    /// Map SwiftMail's `MessageInfo` onto our domain type.
    private static func convert(_ info: MessageInfo) -> EmailMessage? {
        guard let uid = info.uid else { return nil }

        // Header lookup is case-insensitive per RFC 5322.
        let fields = info.additionalFields ?? [:]
        func header(_ name: String) -> String? {
            fields.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }

        let unsubscribe = ListUnsubscribe(
            header: header("List-Unsubscribe"),
            postHeader: header("List-Unsubscribe-Post")
        )
        // A message with no unsubscribe target is not actionable, and storing it
        // would only inflate the local database.
        guard unsubscribe != nil else { return nil }

        let deliveredTo = header("Delivered-To") ?? header("To") ?? ""

        return EmailMessage(
            uid: MessageUID(uid.value),
            sender: EmailSender(header: info.from ?? ""),
            subject: MIMEHeader.decode(info.subject ?? ""),
            receivedAt: info.internalDate ?? info.date ?? .distantPast,
            isUnread: !info.flags.contains(.seen),
            unsubscribe: unsubscribe,
            deliveredTo: EmailSender(header: deliveredTo).address,
            messageId: info.messageId?.description ?? header("Message-ID") ?? "",
            listID: MailingList.id(fromHeader: header("List-ID")),
            authentication: AuthenticationResults(
                header: header(SyncHeaderFields.authenticationResults))
        )
    }

    /// Drop the user's own sent mail — the IMAP equivalent of `-in:sent`.
    private func filterOutOwnMail(_ messages: [EmailMessage]) -> [EmailMessage] {
        let own = Set((cachedSendAs ?? [primaryAddress]).map { $0.lowercased() })
        return messages.filter { !own.contains($0.sender.address) }
    }

    // MARK: - Mutations

    /// Batch size for MOVE. One command per batch keeps each round-trip well
    /// inside the library's command timeout: a single MOVE covering a big
    /// sender (1,127 messages was the case that exposed this) times out and
    /// moves nothing at all.
    private static let moveChunkSize = 200

    /// Move messages to Trash, in batches. Returns the UIDs actually moved.
    ///
    /// Partial success is real and worth reporting rather than hiding: if batch
    /// four of six times out, the first three *are* in Trash, and the caller
    /// needs to know which so the local cache doesn't drift from the server.
    /// Throws only when nothing moved at all.
    public func trash(_ uids: [MessageUID], recordOrigin: Bool) async throws -> TrashOutcome {
        guard !uids.isEmpty else { return TrashOutcome(moved: []) }
        let server = try await connected()
        let folders = try await resolvedFolders(on: server)
        _ = try await select(folders.searchScope, on: server)

        // Establish origin *before* the move, because afterwards the answer is
        // gone: Gmail strips every label from a message that lands in Trash, so
        // a trashed message that used to be archived and one that used to be in
        // the inbox are indistinguishable. There is nothing to look up at undo
        // time — it is captured here or it is lost.
        let archived =
            recordOrigin ? await archivedUIDs(among: uids, on: server, folders: folders) : []

        var moved: [MessageUID] = []
        var offset = 0
        while offset < uids.count {
            try Task.checkCancellation()
            let end = min(offset + Self.moveChunkSize, uids.count)
            let chunk = Array(uids[offset..<end])
            do {
                // MOVE is advertised by most IMAP servers post-login, so this is
                // atomic per batch — no COPY/STORE \Deleted/EXPUNGE dance.
                try await server.move(
                    messages: UIDSet(chunk.map { UID($0.value) }), to: folders.trash)
                moved.append(contentsOf: chunk)
            } catch {
                Log.backend.problem(
                    "trash stopped after \(moved.count)/\(uids.count): \(error.localizedDescription)")
                if moved.isEmpty { throw error }
                return TrashOutcome(moved: moved, archived: archived.intersection(moved))
            }
            offset = end
        }
        Log.backend.event(
            "trashed \(moved.count) messages to \(folders.trash) "
                + "(\(archived.count) of them archived)")
        return TrashOutcome(moved: moved, archived: archived.intersection(moved))
    }

    /// Which of `uids` are archived: present in the all-mail folder but without
    /// Gmail's `\Inbox` label.
    ///
    /// Gmail-only, and deliberately best-effort — any failure returns an empty
    /// set, which restores everything to the inbox exactly as this did before
    /// origin was tracked at all. That asymmetry is on purpose: guessing "inbox"
    /// wrongly puts a message somewhere the user can see and re-file, while
    /// guessing "archived" wrongly hides mail they asked to have back.
    ///
    /// The caller has All Mail selected, so this is one FETCH per chunk on a
    /// connection that is already where it needs to be.
    private func archivedUIDs(
        among uids: [MessageUID], on server: IMAPServer, folders: Folders
    ) async -> Set<MessageUID> {
        // No all-mail folder means discovery only ever searched the inbox, so
        // every message this app can trash came from there. Nothing to ask.
        guard folders.searchScope != config.inboxMailbox,
            Self.isGmailHost(config.imapHost)
        else { return [] }

        var archived: Set<MessageUID> = []
        var offset = 0
        while offset < uids.count {
            let end = min(offset + Self.fetchChunkSize, uids.count)
            let chunk = Array(uids[offset..<end])
            do {
                let attributes = try await server.fetchGmailAttributes(
                    for: UIDSet(chunk.map { UID($0.value) }))
                for (uid, info) in attributes where Self.isArchived(labels: info.labels) {
                    archived.insert(MessageUID(uid.value))
                }
            } catch {
                // Give up on the whole batch rather than keep a partial answer:
                // the UIDs from chunks that never ran would silently read as
                // "was in the inbox", which is a guess dressed up as a fact.
                Log.backend.detail(
                    "trash origin unavailable, undo will restore to the inbox: "
                        + error.localizedDescription)
                return []
            }
            offset = end
        }
        return archived
    }

    /// Whether a message's Gmail labels say it is archived.
    ///
    /// Gmail reports mailbox membership as labels: a message in the inbox
    /// carries the system label `\Inbox`, and an archived one simply does not.
    /// User labels are folders in Gmail's UI but play no part in this decision
    /// — mail filed under "Receipts" and archived is still archived.
    public static func isArchived(labels: [String]) -> Bool {
        !labels.contains { $0.caseInsensitiveCompare("\\Inbox") == .orderedSame }
    }

    /// Whether this host speaks Gmail's IMAP extensions (`X-GM-EXT-1`).
    ///
    /// A hostname test rather than a capability test because SwiftMail keeps the
    /// capability set internal. Being wrong only costs a tagged BAD that the
    /// callers already treat as "no answer".
    public static func isGmailHost(_ host: String) -> Bool {
        let host = host.lowercased()
        return host.contains("gmail") || host.contains("google")
    }

    /// Restore messages from Trash by their RFC Message-IDs, into the inbox or
    /// back into the archive. Returns how many were found and moved. IMAP has
    /// no "untrash", so we search the Trash folder for each Message-ID (its
    /// Trash UID differs from the one we had) and move it out.
    ///
    /// Restoring to `.archive` does not restore Gmail *labels*: the move to
    /// Trash dropped them, and SwiftMail can only `STORE` flags, not
    /// `X-GM-LABELS`. A message that was filed under a user label and archived
    /// comes back archived and unlabelled. That part is not recoverable without
    /// a fork of the IMAP library.
    public func untrash(messageIDs: [String], to target: RestoreTarget) async throws -> Int {
        let ids = messageIDs.filter { !$0.isEmpty }
        guard !ids.isEmpty else { return 0 }
        let server = try await connected()
        let folders = try await resolvedFolders(on: server)
        _ = try await select(folders.trash, on: server)
        let destination = mailbox(for: target, folders)

        var restored = 0
        for messageID in ids {
            let result: ExtendedSearchResult<UID> = try await server.extendedSearch(
                criteria: [.header("Message-ID", messageID)])
            let uids = Self.matched(result)
            guard !uids.isEmpty else { continue }
            do {
                try await server.move(messages: uids, to: destination)
            } catch {
                // Restoring to the archive rests on Gmail accepting All Mail as
                // a MOVE destination. If it doesn't, put the message in the
                // inbox rather than leaving it in Trash: mail in the wrong
                // folder is a nuisance the user can fix, mail still in Trash
                // looks like Undo did nothing at all.
                guard destination != config.inboxMailbox else { throw error }
                Log.backend.problem(
                    "restore to \(destination) failed, falling back to the inbox: "
                        + error.localizedDescription)
                try await server.move(messages: uids, to: config.inboxMailbox)
            }
            restored += uids.count
        }
        Log.backend.event("untrashed \(restored)/\(ids.count) messages to \(destination)")
        return restored
    }

    /// The mailbox a restore target names on this account.
    private func mailbox(for target: RestoreTarget, _ folders: Folders) -> String {
        switch target {
        case .inbox:
            return config.inboxMailbox
        case .archive:
            // No all-mail folder means the provider has no archive that IMAP can
            // see, and everything Nevermore ever found came from the inbox.
            return folders.searchScope == config.inboxMailbox
                ? config.inboxMailbox : folders.searchScope
        }
    }

    public func sendMail(to: String, subject: String, body: String, from: String?) async throws {
        let sender = from ?? primaryAddress
        // Require STARTTLS rather than SwiftMail's port-inferred `.automatic`
        // (which on 587 is startTLS-*if-available*): a network attacker who
        // strips the STARTTLS capability from the server's EHLO must not be able
        // to downgrade the session so the app password is sent in cleartext.
        let smtp = SMTPServer(
            host: config.smtpHost, port: config.smtpPort, transportSecurity: .startTLS)
        do {
            try await smtp.connect()
            // Close the session even when sending throws: the previous code
            // only disconnected on the success path, leaking an authenticated
            // SMTP connection for every failed unsubscribe.
            defer { Task { try? await smtp.disconnect() } }
            try await smtp.login(username: primaryAddress, password: password)
            try await smtp.sendRawMessage(
                Self.rfc822(from: sender, to: to, subject: subject, body: body),
                from: EmailAddress(address: sender),
                to: [EmailAddress(address: to)]
            )
        } catch {
            throw MailBackendError.sendFailed(error.localizedDescription)
        }
    }

    static func rfc822(from: String, to: String, subject: String, body: String) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

        // `from`, `to`, and `subject` originate from an attacker-controlled
        // `mailto:` List-Unsubscribe URI, whose subject/address URLComponents
        // percent-decodes — so `%0D%0A` becomes a real CRLF. Left raw, a CR/LF
        // would terminate a header early and inject attacker-chosen headers (or
        // a forged body) into mail sent from the user's own account. Strip all
        // control characters from the address headers, and RFC 2047-encode the
        // subject unconditionally so its bytes can never be read as structure.
        // (The body is already base64-encoded below, so it cannot inject.)
        let safeFrom = stripControlCharacters(from)
        let safeTo = stripControlCharacters(to)
        let encodedSubject =
            "=?UTF-8?B?\(Data(stripControlCharacters(subject).utf8).base64EncodedString())?="

        let headers = [
            "From: \(safeFrom)",
            "To: \(safeTo)",
            "Subject: \(encodedSubject)",
            "Date: \(formatter.string(from: Date()))",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=UTF-8",
            "Content-Transfer-Encoding: base64",
        ].joined(separator: "\r\n")

        let encodedBody = Data(body.utf8).base64EncodedString()
        return Data("\(headers)\r\n\r\n\(encodedBody)\r\n".utf8)
    }

    /// Remove C0/C1 control characters (including CR and LF) and DEL from a
    /// value destined for an email header, defeating header/body injection.
    public static func stripControlCharacters(_ value: String) -> String {
        String(String.UnicodeScalarView(
            value.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7f && !($0.value >= 0x80 && $0.value <= 0x9f) }))
    }

    // MARK: - Aliases

    /// Infer send-as addresses from Sent Mail.
    ///
    /// Some providers expose alias APIs; IMAP has no equivalent, but the distinct
    /// `From` addresses on recently sent mail are a good proxy. The probe
    /// recovered 5 real aliases this way.
    /// Gmail's conversation id for one message.
    ///
    /// Fetched on demand rather than stored: it is only needed when the user
    /// asks to view a message, so paying for it on every message of every sync
    /// — and carrying a schema migration — would be a poor trade. One extra
    /// round trip on an already-open connection.
    ///
    /// Returns nil rather than throwing: a non-Gmail server answers this with a
    /// tagged BAD, and the caller has a working fallback either way.
    public func gmailThreadID(for uid: MessageUID) async -> UInt64? {
        guard Self.isGmailHost(config.imapHost) else { return nil }

        // Retry once on a fresh connection. A cached IMAP connection that has
        // gone stale — Gmail drops idle ones, and this runs only when the user
        // asks, often hours after the last sync — fails on first use. Sync
        // already reconnects on error; without the same here, a stale socket
        // silently degraded "view message" to a search result.
        for attempt in 1...2 {
            do {
                let server = try await connected()
                let folders = try await resolvedFolders(on: server)
                _ = try await select(folders.searchScope, on: server)
                let attributes = try await server.fetchGmailAttributes(
                    for: UIDSet([UID(uid.value)]))
                guard let threadID = attributes.values.first?.threadID else {
                    Log.backend.detail("no gmail thread id for uid \(uid.value)")
                    return nil
                }
                Log.backend.detail("gmail thread id for uid \(uid.value): \(threadID)")
                return threadID
            } catch {
                Log.backend.detail(
                    "gmail thread id attempt \(attempt) failed: \(error.localizedDescription)")
                guard attempt == 1 else { return nil }
                await disconnect()
            }
        }
        return nil
    }

    public func sendAsAddresses() async throws -> [String] {
        if let cachedSendAs { return cachedSendAs }

        var found: Set<String> = [primaryAddress.lowercased()]
        if let server = try? await connected(),
            let folders = try? await resolvedFolders(on: server),
            let selection = try? await select(folders.sent, on: server),
            selection.messageCount > 0
        {
            // Fetch the last 300 sent messages by *sequence number*. A `SEARCH
            // ALL` returns every UID on a single line, which for a large Sent
            // folder exceeds swift-nio-imap's fixed 8 KB frame limit and throws
            // PayloadTooLargeError; a bounded sequence range avoids that entirely.
            let count = selection.messageCount
            let low = max(1, count - 299)
            let infos = try await server.fetchMessageInfosBulk(
                using: SequenceNumberSet(low...count), options: .slim
            )
            for info in infos {
                let addr = EmailSender(header: info.from ?? "").address
                if addr.contains("@") { found.insert(addr) }
            }
        }
        let result = found.sorted()
        cachedSendAs = result
        return result
    }

    // MARK: - Helpers

    private func select(_ name: String, on server: IMAPServer) async throws -> Mailbox.Selection {
        do {
            return try await server.selectMailbox(name)
        } catch {
            throw MailBackendError.mailboxUnavailable(name)
        }
    }

    private func maxUID(in set: UIDSet, fallback: UInt32) -> UInt32 {
        UInt32(set.ranges.map(\.upperBound).max() ?? Int(fallback))
    }
}
