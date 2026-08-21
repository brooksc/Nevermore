import Foundation

/// Arguments for every read tool, in one tolerant shape.
///
/// One struct rather than nine: the bridge forwards the client's arguments
/// object untouched, so the server has to accept whatever an agent sent and
/// ignore what this route doesn't use. Every field is optional and an absent
/// body is an empty request — a tool that takes no arguments must not 400
/// because the client sent `{}` or nothing at all.
public struct MCPToolRequest: Decodable, Sendable {
    public var senderId: String?
    public var collection: String?
    public var query: String?
    public var limit: Int?
    public var offset: Int?
    public var minMessages: Int?
    public var maxMessages: Int?
    public var minUnreadPercent: Double?
    public var maxUnreadPercent: Double?
    /// ISO-8601 timestamp or `YYYY-MM-DD`, matched against the sender's most
    /// recent message.
    public var receivedAfter: String?
    public var receivedBefore: String?
    public var unsubscribeMethod: String?
    public var needsBrowser: Bool?
    public var isMailingList: Bool?
    public var classification: String?
    public var context: String?
    public var outcome: String?

    public init() {}
}

/// The read-only MCP surface: nine tools, dispatched from a snapshot of the open
/// account's store.
///
/// Every handler is a pure function of `(MCPSnapshot, MCPToolRequest)`, which is
/// what lets the whole surface be exercised in the test harness. TASK-41 refuses
/// these routes in demo mode, so there is no demo mailbox to drive them through
/// end to end — the harness is the only place they can be proven, and that is by
/// design rather than by omission.
///
/// **Read-only, and structurally so.** Nothing here writes: not to the mailbox,
/// not to the store, not to the ignore list. Acting on mail requires a selection
/// the human has confirmed in the app (TASK-46), and the bearer token is not
/// what holds that line — an agent that can reach these routes can reach any
/// route that exists. If you are adding a route that changes state, it does not
/// belong in this file.
public enum MCPRoutes {
    /// Repeated on every response, not only in the tool descriptions.
    ///
    /// An agent that reads one response without having read the tool list — a
    /// second session, a summarised context, a client that trims descriptions —
    /// would otherwise have nothing telling it the subjects are all there is,
    /// and would reason as though it could go and read the mail.
    public static let bodiesNote =
        "Nevermore stores message headers only. Message bodies are not available "
        + "locally and never will be — classify from sender, domain, subject lines, "
        + "dates and read rate."

    public static let defaultLimit = 50
    public static let maxLimit = 200

    /// Every path this surface serves. The tool catalog is checked against this
    /// list in the tests, so a tool can't point at a route that doesn't exist.
    public static let paths: Set<String> = [
        "/mcp/senders/list",
        "/mcp/senders/get",
        "/mcp/senders/search",
        "/mcp/senders/messages",
        "/mcp/senders/reappeared",
        "/mcp/unsubscribe/history",
        "/mcp/mailbox/summary",
        "/mcp/sync/status",
        "/mcp/decisions/by-context",
    ]

    // MARK: - Dispatch

    /// Serve one already-authenticated request. Returns nil when the path is not
    /// an MCP route, so the caller can answer 404 about the *route* rather than
    /// about the credential.
    public static func handle(path: String, request: HTTPRequest, snapshot: MCPSnapshot)
        -> HTTPResponse?
    {
        guard paths.contains(path) else { return nil }
        let args: MCPToolRequest
        do {
            args = try decodeArguments(request)
        } catch {
            return .error("Could not read the tool arguments as JSON: \(error)", code: 400)
        }

        switch path {
        case "/mcp/senders/list": return listSenders(snapshot, args)
        case "/mcp/senders/get": return getSender(snapshot, args)
        case "/mcp/senders/search": return searchSenders(snapshot, args)
        case "/mcp/senders/messages": return listMessages(snapshot, args)
        case "/mcp/senders/reappeared": return listReappeared(snapshot, args)
        case "/mcp/unsubscribe/history": return unsubscribeHistory(snapshot, args)
        case "/mcp/mailbox/summary": return mailboxSummary(snapshot)
        case "/mcp/sync/status": return syncStatus(snapshot)
        case "/mcp/decisions/by-context": return listByContext(snapshot, args)
        default: return nil
        }
    }

    static func decodeArguments(_ request: HTTPRequest) throws -> MCPToolRequest {
        guard let body = request.body, !body.isEmpty else { return MCPToolRequest() }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(MCPToolRequest.self, from: body)
    }

    // MARK: - Handlers

    static func listSenders(_ snapshot: MCPSnapshot, _ args: MCPToolRequest) -> HTTPResponse {
        let collection: Collection
        if let raw = args.collection {
            guard let parsed = parseCollection(raw) else {
                return .error(
                    "Unknown collection '\(raw)'. Use one of: "
                        + Collection.allCases.map(\.rawValue).joined(separator: ", "),
                    code: 400)
            }
            collection = parsed
        } else {
            collection = .allSenders
        }

        var matched = snapshot.groups(in: collection)
        if let method = args.unsubscribeMethod {
            guard let parsed = UnsubscribeMethod(rawValue: method) else {
                return .error(
                    "Unknown unsubscribe_method '\(method)'. Use one of: "
                        + UnsubscribeMethod.allCases.map(\.rawValue).joined(separator: ", "),
                    code: 400)
            }
            matched = matched.filter { UnsubscribeMethod.of($0) == parsed }
        }
        if let needsBrowser = args.needsBrowser {
            matched = matched.filter { self.needsBrowser($0, snapshot) == needsBrowser }
        }
        if let min = args.minMessages { matched = matched.filter { $0.total >= min } }
        if let max = args.maxMessages { matched = matched.filter { $0.total <= max } }
        if let min = args.minUnreadPercent { matched = matched.filter { $0.unreadPercent >= min } }
        if let max = args.maxUnreadPercent { matched = matched.filter { $0.unreadPercent <= max } }
        if let raw = args.receivedAfter {
            guard let after = parseDate(raw) else { return badDate("received_after", raw) }
            matched = matched.filter { $0.newest > after }
        }
        if let raw = args.receivedBefore {
            guard let before = parseDate(raw) else { return badDate("received_before", raw) }
            matched = matched.filter { $0.newest < before }
        }
        if let isList = args.isMailingList { matched = matched.filter { $0.isMailingList == isList } }
        if let classification = args.classification {
            matched = matched.filter { snapshot.decision(for: $0)?.classification == classification }
        }
        if let context = args.context {
            matched = matched.filter { snapshot.decision(for: $0)?.context == context }
        }

        return json(page(matched, collection: collection.rawValue, args: args, snapshot: snapshot))
    }

    static func searchSenders(_ snapshot: MCPSnapshot, _ args: MCPToolRequest) -> HTTPResponse {
        guard let raw = args.query?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
        else {
            return .error("search_senders needs a non-empty query.", code: 400)
        }
        let needle = raw.lowercased()
        // Across every collection, not only the working list: "did I already
        // unsubscribe from these people" is exactly the question a search is
        // asked, and answering it from All Senders alone says no when the truth
        // is "yes, and they came back".
        let matched = snapshot.groups.filter { group in
            if group.displayName.lowercased().contains(needle) { return true }
            if group.id.key.lowercased().contains(needle) { return true }
            return group.messages.contains {
                $0.sender.address.lowercased().contains(needle)
                    || $0.sender.host.lowercased().contains(needle)
                    || $0.subject.lowercased().contains(needle)
            }
        }
        return json(page(matched, collection: nil, args: args, snapshot: snapshot))
    }

    static func listReappeared(_ snapshot: MCPSnapshot, _ args: MCPToolRequest) -> HTTPResponse {
        let matched = snapshot.groups(in: .reappeared)
            .sorted { snapshot.messagesSinceUnsubscribe($0) > snapshot.messagesSinceUnsubscribe($1) }
        return json(page(matched, collection: Collection.reappeared.rawValue, args: args, snapshot: snapshot))
    }

    static func getSender(_ snapshot: MCPSnapshot, _ args: MCPToolRequest) -> HTTPResponse {
        guard let id = args.senderId else {
            return .error("get_sender needs a sender_id, as returned by list_senders.", code: 400)
        }
        guard let group = snapshot.group(withStorageKey: id) else {
            return .error("No sender with id '\(id)' in \(snapshot.account).", code: 404)
        }
        let unsubscribe = group.unsubscribeSource?.unsubscribe
        let limit = clampedLimit(args.limit)
        let decision = snapshot.decision(for: group)
        let detail = MCPSenderDetail(
            account: snapshot.account,
            sender: summary(group, snapshot),
            addresses: orderedUnique(group.messages.map(\.sender.address)),
            hosts: orderedUnique(group.messages.map(\.sender.host)),
            supportsOneClick: unsubscribe?.supportsOneClick ?? false,
            webTargets: unsubscribe?.webTargets.map(\.absoluteString) ?? [],
            mailtoTargets: unsubscribe?.mailtoTargets.map {
                MCPMailtoTarget(
                    address: $0.address, subject: $0.subject,
                    identifiesRecipient: $0.identifiesRecipient)
            } ?? [],
            unsubscribeHeader: unsubscribe?.raw,
            unsubscribeRecord: snapshot.history[group.id.storageKey].map {
                record($0, reappeared: snapshot.hasReappeared(group))
            },
            messagesSinceUnsubscribe: snapshot.messagesSinceUnsubscribe(group),
            decision: decision.map(decisionRow),
            recentSubjects: group.messages.prefix(limit).map(messageRow),
            note: bodiesNote)
        return json(detail)
    }

    static func listMessages(_ snapshot: MCPSnapshot, _ args: MCPToolRequest) -> HTTPResponse {
        guard let id = args.senderId else {
            return .error("list_messages needs a sender_id, as returned by list_senders.", code: 400)
        }
        guard let group = snapshot.group(withStorageKey: id) else {
            return .error("No sender with id '\(id)' in \(snapshot.account).", code: 404)
        }
        let limit = clampedLimit(args.limit)
        let offset = max(args.offset ?? 0, 0)
        let window = slice(group.messages, offset: offset, limit: limit)
        return json(
            MCPMessagePage(
                account: snapshot.account,
                senderId: group.id.storageKey,
                senderName: group.displayName,
                total: group.total,
                offset: offset,
                limit: limit,
                hasMore: offset + window.count < group.total,
                nextOffset: offset + window.count < group.total ? offset + window.count : nil,
                messages: window.map(messageRow),
                note: bodiesNote))
    }

    static func unsubscribeHistory(_ snapshot: MCPSnapshot, _ args: MCPToolRequest) -> HTTPResponse {
        var records = snapshot.history.values.sorted { $0.attemptedAt > $1.attemptedAt }
        if let outcome = args.outcome {
            guard MessageStore.Outcome(rawValue: outcome) != nil else {
                return .error(
                    "Unknown outcome '\(outcome)'. Use one of: requested, confirmed, failed.",
                    code: 400)
            }
            records = records.filter { $0.outcome.rawValue == outcome }
        }
        let limit = clampedLimit(args.limit)
        let offset = max(args.offset ?? 0, 0)
        let window = slice(records, offset: offset, limit: limit)
        return json(
            MCPHistoryPage(
                account: snapshot.account,
                total: records.count,
                offset: offset,
                limit: limit,
                hasMore: offset + window.count < records.count,
                nextOffset: offset + window.count < records.count ? offset + window.count : nil,
                records: window.map {
                    record(
                        $0,
                        reappeared: snapshot.group(withStorageKey: $0.groupKey)
                            .map(snapshot.hasReappeared) ?? false)
                },
                note: "An outcome of 'requested' means the request was accepted, not that the "
                    + "sender honoured it. Check `reappeared`, which is the only evidence either "
                    + "way. " + bodiesNote))
    }

    static func mailboxSummary(_ snapshot: MCPSnapshot) -> HTTPResponse {
        var byCollection: [String: Int] = [:]
        for collection in Collection.allCases {
            byCollection[collection.rawValue] = snapshot.groups(in: collection).count
        }
        var byMethod: [String: Int] = [:]
        for method in UnsubscribeMethod.allCases { byMethod[method.rawValue] = 0 }
        for group in snapshot.groups {
            byMethod[UnsubscribeMethod.of(group).rawValue, default: 0] += 1
        }
        let dates = snapshot.groups.flatMap { $0.messages.map(\.receivedAt) }
        return json(
            MCPMailboxSummary(
                account: snapshot.account,
                senders: snapshot.groups.count,
                messages: snapshot.messageCount,
                unread: snapshot.groups.reduce(0) { $0 + $1.unreadCount },
                byCollection: byCollection,
                byUnsubscribeMethod: byMethod,
                needBrowser: snapshot.groups.filter { needsBrowser($0, snapshot) }.count,
                mailingLists: snapshot.groups.filter(\.isMailingList).count,
                decided: snapshot.decisions.count,
                contexts: contexts(snapshot),
                oldestMessage: dates.min().map(iso),
                newestMessage: dates.max().map(iso),
                lastSyncedAt: snapshot.syncToken?.lastSyncedAt.map(iso),
                note: bodiesNote))
    }

    static func syncStatus(_ snapshot: MCPSnapshot) -> HTTPResponse {
        json(
            MCPSyncStatus(
                account: snapshot.account,
                hasSynced: snapshot.syncToken != nil,
                lastSyncedAt: snapshot.syncToken?.lastSyncedAt.map(iso),
                messages: snapshot.messageCount,
                senders: snapshot.groups.count,
                uidValidity: snapshot.syncToken?.uidValidity,
                highestUid: snapshot.syncToken?.highestUID,
                note: "Nevermore only ever syncs messages carrying a List-Unsubscribe header, so "
                    + "these counts describe the bulk mail in the mailbox, not the mailbox. "
                    + bodiesNote))
    }

    static func listByContext(_ snapshot: MCPSnapshot, _ args: MCPToolRequest) -> HTTPResponse {
        guard let context = args.context, !context.isEmpty else {
            return .error(
                "list_by_context needs a context label. The labels in use are: "
                    + (contexts(snapshot).isEmpty
                        ? "(none recorded yet)" : contexts(snapshot).joined(separator: ", ")),
                code: 400)
        }
        let matched = snapshot.decisions.values
            .filter { $0.context == context }
            .sorted { $0.decidedAt > $1.decidedAt }
        // Join each decision back to the group its address currently sits in.
        // Grouping is mutable — a merge or a split moves an address into a
        // different row — which is exactly why the decision is keyed by address
        // and resolved here rather than stored against a group.
        var groupByAddress: [String: SenderGroup] = [:]
        for group in snapshot.groups {
            for message in group.messages {
                groupByAddress[message.sender.address.lowercased()] = group
            }
        }
        return json(
            MCPContextCohort(
                account: snapshot.account,
                context: context,
                total: matched.count,
                decisions: matched.map { decision in
                    MCPCohortRow(
                        decision: decisionRow(decision),
                        sender: groupByAddress[decision.address].map { summary($0, snapshot) })
                },
                availableContexts: contexts(snapshot),
                note: "A null sender means the decision's address has no messages left in this "
                    + "mailbox. The decision outlives the mail. " + bodiesNote))
    }

    // MARK: - Row builders

    static func summary(_ group: SenderGroup, _ snapshot: MCPSnapshot) -> MCPSenderSummary {
        let decision = snapshot.decision(for: group)
        return MCPSenderSummary(
            id: group.id.storageKey,
            kind: group.id.kind.rawValue,
            key: group.id.key,
            name: group.displayName,
            messages: group.total,
            unread: group.unreadCount,
            unreadPercent: Int(group.unreadPercent.rounded()),
            newest: group.messages.first.map { iso($0.receivedAt) },
            oldest: group.messages.last.map { iso($0.receivedAt) },
            collection: snapshot.collection(of: group)?.rawValue ?? "",
            unsubscribeMethod: UnsubscribeMethod.of(group).rawValue,
            needsBrowser: needsBrowser(group, snapshot),
            isMailingList: group.isMailingList,
            mailingListId: group.mailingListID,
            classification: decision?.classification,
            context: decision?.context,
            latestSubject: group.latest?.subject)
    }

    static func messageRow(_ message: EmailMessage) -> MCPMessageRow {
        MCPMessageRow(
            uid: message.uid.value,
            from: message.sender.address,
            subject: message.subject,
            receivedAt: iso(message.receivedAt),
            isUnread: message.isUnread)
    }

    static func record(_ record: MessageStore.UnsubscribeRecord, reappeared: Bool)
        -> MCPUnsubscribeRecord
    {
        MCPUnsubscribeRecord(
            senderId: record.groupKey,
            senderName: record.senderName,
            senderEmail: record.senderEmail,
            senderDomain: record.senderDomain,
            url: record.url,
            attemptedAt: iso(record.attemptedAt),
            outcome: record.outcome.rawValue,
            reappeared: reappeared)
    }

    static func decisionRow(_ decision: MessageStore.SenderDecision) -> MCPDecision {
        MCPDecision(
            address: decision.address,
            classification: decision.classification,
            reason: decision.reason,
            context: decision.context,
            decidedAt: iso(decision.decidedAt))
    }

    // MARK: - Helpers

    /// A sender needs a human in a browser when nothing automated is left to
    /// try: no machine-readable target, or they already ignored one attempt.
    static func needsBrowser(_ group: SenderGroup, _ snapshot: MCPSnapshot) -> Bool {
        UnsubscribeMethod.of(group).needsBrowser || snapshot.hasReappeared(group)
    }

    static func contexts(_ snapshot: MCPSnapshot) -> [String] {
        Array(Set(snapshot.decisions.values.compactMap(\.context))).sorted()
    }

    static func page(
        _ groups: [SenderGroup], collection: String?, args: MCPToolRequest, snapshot: MCPSnapshot
    ) -> MCPSenderPage {
        let limit = clampedLimit(args.limit)
        let offset = max(args.offset ?? 0, 0)
        let window = slice(groups, offset: offset, limit: limit)
        let more = offset + window.count < groups.count
        var note = bodiesNote
        if let asked = args.limit, asked > maxLimit {
            note = "limit was reduced from \(asked) to \(maxLimit). " + note
        }
        return MCPSenderPage(
            account: snapshot.account,
            collection: collection,
            total: groups.count,
            offset: offset,
            limit: limit,
            hasMore: more,
            nextOffset: more ? offset + window.count : nil,
            senders: window.map { summary($0, snapshot) },
            note: note)
    }

    /// Bounded so one call can never return a thousand-sender mailbox in full.
    /// A limit above the cap is honoured up to the cap and reported in `note`
    /// rather than refused — an agent that asked for too much should still get
    /// an answer it can page from.
    static func clampedLimit(_ requested: Int?) -> Int {
        guard let requested else { return defaultLimit }
        return min(max(requested, 1), maxLimit)
    }

    static func slice<T>(_ items: [T], offset: Int, limit: Int) -> [T] {
        guard offset < items.count else { return [] }
        return Array(items[offset ..< min(offset + limit, items.count)])
    }

    static func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func parseCollection(_ raw: String) -> Collection? {
        Collection(rawValue: raw)
            // Tolerate the snake_case an agent will infer from the wire format,
            // since every other field it sees is snake_case.
            ?? Collection.allCases.first { $0.rawValue.lowercased() == raw.replacingOccurrences(
                of: "_", with: "").lowercased() }
    }

    /// ISO-8601 with a time, or a bare `YYYY-MM-DD` read as UTC midnight.
    static func parseDate(_ raw: String) -> Date? {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = full.date(from: raw) { return date }
        full.formatOptions = [.withInternetDateTime]
        if let date = full.date(from: raw) { return date }
        let dayOnly = ISO8601DateFormatter()
        dayOnly.formatOptions = [.withFullDate]
        dayOnly.timeZone = TimeZone(secondsFromGMT: 0)
        return dayOnly.date(from: raw)
    }

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func badDate(_ field: String, _ raw: String) -> HTTPResponse {
        .error(
            "Could not read \(field) '\(raw)'. Use an ISO-8601 timestamp or YYYY-MM-DD.",
            code: 400)
    }

    /// snake_case on the wire, because that is what every MCP tool schema an
    /// agent has seen looks like, and a surface that mixes the two invites
    /// arguments that silently don't apply.
    static func json(_ value: some Encodable, code: Int = 200) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let data = try? encoder.encode(value) else {
            return .error("Response serialization failed", code: 500)
        }
        return HTTPResponse(
            statusCode: code, headers: ["Content-Type": "application/json"], body: data)
    }
}
