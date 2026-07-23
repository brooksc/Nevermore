import Foundation
import SwiftMail

/// Gmail over IMAP, authenticated with an app-specific password.
///
/// Chosen over the Gmail API because an app password is a *user credential*
/// rather than an OAuth grant: no Cloud project, no consent screen, no
/// verification, no annual security assessment, no 100-user cap, and no 7-day
/// refresh-token expiry. See PLAN.md §1.
public actor IMAPBackend: MailBackend {
    public struct Config: Sendable {
        public var imapHost = "imap.gmail.com"
        public var imapPort = 993
        public var smtpHost = "smtp.gmail.com"
        public var smtpPort = 587
        /// Gmail's All Mail excludes Trash and Spam, so those exclusions come free.
        public var mailbox = "[Gmail]/All Mail"
        public var sentMailbox = "[Gmail]/Sent Mail"
        public var trashMailbox = "[Gmail]/Trash"
        public var inboxMailbox = "INBOX"

        public init() {}
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
    private var cachedSendAs: [String]?

    public init(address: String, appPassword: String, config: Config = Config()) {
        self.primaryAddress = address
        // Gmail displays app passwords in groups of four; users paste them verbatim.
        self.password = appPassword.replacingOccurrences(of: " ", with: "")
        self.config = config
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
        let selection = try await select(config.mailbox, on: server)

        // Pure RFC 3501. An empty HEADER value matches any message that *has*
        // the header, so this finds every newsletter regardless of which Gmail
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

    /// One-year windows from Gmail's launch to tomorrow, newest first.
    ///
    /// Newest first so the senders a user actually cares about populate the
    /// table before the archaeology finishes.
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

    /// Search one date window, halving it on error until it fits within the
    /// library's command timeout *and* under swift-nio-imap's fixed 8 KB frame
    /// limit (a `SEARCH` whose one-line UID result exceeds that throws
    /// PayloadTooLargeError). Halves down to a one-hour floor — far below the
    /// point any personal account produces >1000 unsubscribe emails in a window.
    private func searchWindow(
        _ window: (start: Date, end: Date),
        on server: IMAPServer,
        depth: Int
    ) async throws -> [UInt32] {
        do {
            let uids: UIDSet = try await server.search(
                criteria: [
                    .header("List-Unsubscribe", ""),
                    .not(.flagged),
                    .since(window.start),
                    .before(window.end),
                ]
            )
            return uids.toArray().map(\.value)
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
        let selection = try await select(config.mailbox, on: server)

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

        // `Delivered-To` is set by Gmail's delivery layer, so it survives
        // forwarding in a way the sender-controlled `To` does not — it is what
        // makes send-as alias detection work.
        // Message-ID is fetched explicitly so trash-undo can find a message again
        // in the Trash folder (IMAP UIDs differ per folder).
        let headerFields =
            FetchMessageInfoOptions.newsletterHeaderFields + ["Delivered-To", "To", "Message-ID"]

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
            messageId: info.messageId?.description ?? header("Message-ID") ?? ""
        )
    }

    /// Drop the user's own sent mail — the IMAP equivalent of `-in:sent`.
    private func filterOutOwnMail(_ messages: [EmailMessage]) -> [EmailMessage] {
        let own = Set((cachedSendAs ?? [primaryAddress]).map { $0.lowercased() })
        return messages.filter { !own.contains($0.sender.address) }
    }

    // MARK: - Mutations

    public func trash(_ uids: [MessageUID]) async throws {
        guard !uids.isEmpty else { return }
        let server = try await connected()
        _ = try await select(config.mailbox, on: server)
        // MOVE is advertised by Gmail post-login, so this is atomic — no
        // COPY/STORE \Deleted/EXPUNGE dance.
        try await server.move(
            messages: UIDSet(uids.map { UID($0.value) }), to: config.trashMailbox
        )
        Log.backend.event("trashed \(uids.count) messages to \(config.trashMailbox)")
    }

    /// Restore messages from Trash by their RFC Message-IDs. Returns how many
    /// were found and moved back to the Inbox. IMAP has no "untrash", so we
    /// search the Trash folder for each Message-ID (its Trash UID differs from
    /// the one we had) and move it out.
    public func untrash(messageIDs: [String]) async throws -> Int {
        let ids = messageIDs.filter { !$0.isEmpty }
        guard !ids.isEmpty else { return 0 }
        let server = try await connected()
        _ = try await select(config.trashMailbox, on: server)

        var restored = 0
        for messageID in ids {
            let uids: UIDSet = try await server.search(
                criteria: [.header("Message-ID", messageID)])
            guard !uids.isEmpty else { continue }
            try await server.move(messages: uids, to: config.inboxMailbox)
            restored += uids.count
        }
        Log.backend.event("untrashed \(restored)/\(ids.count) messages")
        return restored
    }

    public func sendMail(to: String, subject: String, body: String, from: String?) async throws {
        let sender = from ?? primaryAddress
        let smtp = SMTPServer(host: config.smtpHost, port: config.smtpPort)
        do {
            try await smtp.connect()
            try await smtp.login(username: primaryAddress, password: password)
            try await smtp.sendRawMessage(
                Self.rfc822(from: sender, to: to, subject: subject, body: body),
                from: EmailAddress(address: sender),
                to: [EmailAddress(address: to)]
            )
            try await smtp.disconnect()
        } catch {
            throw MailBackendError.sendFailed(error.localizedDescription)
        }
    }

    static func rfc822(from: String, to: String, subject: String, body: String) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

        // Subject and body are encoded as base64 UTF-8 rather than emitted raw:
        // unsubscribe mailto: URIs routinely carry non-ASCII.
        let encodedSubject =
            subject.allSatisfy(\.isASCII)
            ? subject
            : "=?UTF-8?B?\(Data(subject.utf8).base64EncodedString())?="

        let headers = [
            "From: \(from)",
            "To: \(to)",
            "Subject: \(encodedSubject)",
            "Date: \(formatter.string(from: Date()))",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=UTF-8",
            "Content-Transfer-Encoding: base64",
        ].joined(separator: "\r\n")

        let encodedBody = Data(body.utf8).base64EncodedString()
        return Data("\(headers)\r\n\r\n\(encodedBody)\r\n".utf8)
    }

    // MARK: - Aliases

    /// Infer send-as addresses from Sent Mail.
    ///
    /// The Gmail API exposes `users.settings.sendAs.list`; IMAP has no
    /// equivalent, but the distinct `From` addresses on recently sent mail are a
    /// good proxy. The probe recovered 5 real aliases this way.
    public func sendAsAddresses() async throws -> [String] {
        if let cachedSendAs { return cachedSendAs }

        var found: Set<String> = [primaryAddress.lowercased()]
        if let server = try? await connected(),
            let selection = try? await select(config.sentMailbox, on: server),
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
