import Foundation
import Network
// For SecKeychainGetUserInteractionAllowed, which the Keychain probe toggles.
import Security
// For ExtendedSearchResult/UID/UIDSet, which IMAPBackend.matched(_:) is stated in.
import SwiftMail
import Testing

@testable import NevermoreKit

// `expect` and `eq` are kept rather than rewritten into bare `#expect(a == b)`
// at every call site. Both record a non-fatal issue and let the test carry on,
// which is exactly what the old harness did, so the ~1900 assertion bodies in
// Suites.swift are unchanged from the harness version and still assert what
// they always did. `#_sourceLocation` restores the line reporting that the old
// `line: Int = #line` default provided.
//
// The cost is that a failure prints the described values instead of
// swift-testing's decomposed expression. `eq` already printed expected/got, so
// what is lost is expression capture on `expect`, not the values themselves.
func expect(
    _ condition: Bool,
    _ message: @autoclosure () -> String = "expectation failed",
    sourceLocation: SourceLocation = #_sourceLocation
) {
    if !condition {
        Issue.record(Comment(rawValue: message()), sourceLocation: sourceLocation)
    }
}

func eq<T: Equatable>(
    _ actual: T?,
    _ expected: T?,
    _ label: @autoclosure () -> String = "",
    sourceLocation: SourceLocation = #_sourceLocation
) {
    if actual != expected {
        let prefix = label().isEmpty ? "" : "\(label()): "
        Issue.record(
            Comment(
                rawValue: "\(prefix)expected \(String(describing: expected)), "
                    + "got \(String(describing: actual))"),
            sourceLocation: sourceLocation
        )
    }
}

// MARK: - MIME header decoding


// MARK: - Sender parsing


// MARK: - List-Unsubscribe


// MARK: - Registrable domain


// MARK: - Grouping

func msg(
    _ uid: UInt32,
    from: String,
    subject: String = "s",
    daysAgo: Double = 0,
    unread: Bool = false,
    unsub: String? = "<https://ex.com/u>"
) -> EmailMessage {
    EmailMessage(
        uid: MessageUID(uid),
        sender: EmailSender(header: from),
        subject: subject,
        receivedAt: Date(timeIntervalSince1970: 1_700_000_000 - daysAgo * 86400),
        isUnread: unread,
        unsubscribe: ListUnsubscribe(header: unsub)
    )
}


// MARK: - Round-tripping through storage

// Regression: the store wrote "One-Click" but ListUnsubscribe looks for the
// canonical "List-Unsubscribe=One-Click" token, so every message came back
// reporting no one-click support — 0% instead of the true 79%.

// MARK: - GroupID


// MARK: - Browser confirmation heuristic


// MARK: - MessageStore (in-memory integration)

func makeMessage(
    _ uid: UInt32, from: String, unsub: String? = "<https://ex.com/u>",
    messageId: String = "", deliveredTo: String = "", listID: String? = nil
) -> EmailMessage {
    EmailMessage(
        uid: MessageUID(uid),
        sender: EmailSender(header: from),
        subject: "s\(uid)",
        receivedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(uid)),
        isUnread: true,
        unsubscribe: ListUnsubscribe(header: unsub),
        deliveredTo: deliveredTo,
        messageId: messageId,
        listID: listID)
}


// MARK: - Provider detection


// MARK: - Security hardening















// MARK: - Agent decisions about senders

/// The decision records for whichever group in `groups` has this id, as a set of
/// "address/classification" strings — enough to prove nothing was lost, without
/// depending on ordering.
func decisionSummary(
    _ store: MessageStore, _ groups: [SenderGroup], _ id: GroupID
) throws -> Set<String> {
    guard let group = groups.first(where: { $0.id == id }) else { return [] }
    return Set(try store.decisions(for: group).map { "\($0.address)/\($0.classification)" })
}


// MARK: - Decisions survive regrouping

// The reason records key on address rather than GroupID: splitByAddress and
// keepAsOneGroup move a sender between a `domain:` group and an `address:` one,
// so a GroupID key would silently discard the agent's judgement every time the
// user regrouped a domain.

// MARK: - Loopback HTTP server

// Runs an async body from a synchronous test and blocks until it finishes.
//
// DANGER, and the reason TASK-54 exists: this blocks a cooperative-pool thread
// while waiting on a Task that needs that same pool. Two of these running at
// once can starve the pool and wedge the entire run — not a failure, a hang
// with nothing reported.
//
// The old harness ran every test sequentially, so it could not happen. Under
// swift-testing it can, and does: removing `.serialized` from `NetworkBound`
// hung the suite, with two `Local server lifecycle` tests both parked in
// `done.wait()` below.
//
// What keeps it safe today is that every caller is inside `NetworkBound`, whose
// `.serialized` trait means only one can block at a time. **Do not call
// `runAsync` from a suite outside `NetworkBound`.** Write `@Test ... async` and
// `await` directly instead — which is what TASK-54 will convert these to,
// deleting this function.
final class ResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?
    var value: T? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

func runAsync<T: Sendable>(_ body: @escaping @Sendable () async -> T) -> T {
    let box = ResultBox<T>()
    let done = DispatchSemaphore(value: 0)
    Task {
        box.value = await body()
        done.signal()
    }
    done.wait()
    return box.value!
}

/// A real listener occupying a contract port, so the server has to deal with it the way it would in
/// the field. Uses the server's own parameters, so "taken" means taken the same way.
final class HeldPort {
    private let listener: NWListener
    fileprivate init(_ listener: NWListener) { self.listener = listener }

    /// Wait for `.cancelled` before returning. `NWListener.cancel()` returns before the OS has
    /// released the port, so a test that merely cancels leaves the next one binding a port that is
    /// still occupied — which shows up as an unrelated test failing intermittently.
    func release() {
        let done = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .cancelled = state { done.signal() }
        }
        listener.cancel()
        _ = done.wait(timeout: .now() + 3)
    }
}

func holdPort(_ port: UInt16) -> HeldPort? {
    guard let nwPort = NWEndpoint.Port(rawValue: port),
          let listener = try? NWListener(using: NevermoreServer.listenerParameters(), on: nwPort)
    else { return nil }
    let ready = DispatchSemaphore(value: 0)
    listener.stateUpdateHandler = { state in
        if case .ready = state { ready.signal() }
    }
    listener.newConnectionHandler = { $0.cancel() }
    listener.start(queue: .global())
    guard ready.wait(timeout: .now() + 3) == .success else {
        listener.cancel()
        return nil
    }
    return HeldPort(listener)
}







// MARK: - Local server lifecycle (TASK-48)


// MARK: - One selection model for every collection (TASK-27)





// MARK: - MCP read surface (TASK-44)

/// One header row, with everything the MCP surface reads off it under control.
func mcpMessage(
    _ uid: UInt32,
    from: String,
    subject: String = "Subject",
    daysAgo: Double = 0,
    unread: Bool = false,
    unsub: String? = "<https://ex.com/u>",
    oneClick: Bool = false,
    listID: String? = nil
) -> EmailMessage {
    EmailMessage(
        uid: MessageUID(uid),
        sender: EmailSender(header: from),
        subject: subject,
        receivedAt: Date(timeIntervalSince1970: 1_700_000_000 - daysAgo * 86400),
        isUnread: unread,
        unsubscribe: ListUnsubscribe(
            header: unsub, postHeader: oneClick ? "List-Unsubscribe=One-Click" : nil),
        listID: listID)
}

/// A snapshot built the way the server builds one: through a real store, so the
/// round-trip that reconstitutes `ListUnsubscribe` from the stored header is
/// part of every route test rather than something the tests fake past.
func mcpSnapshot(_ store: MessageStore, account: String = "me@example.com") throws -> MCPSnapshot {
    try MCPSnapshot.load(MCPContext(account: account, store: store))
}

func mcpCall(_ path: String, _ snapshot: MCPSnapshot, _ arguments: [String: Any] = [:])
    -> HTTPResponse
{
    let body = try? JSONSerialization.data(withJSONObject: arguments)
    let request = HTTPRequest(
        method: "POST", path: path, headers: ["content-type": "application/json"], body: body)
    return MCPRoutes.handle(path: path, request: request, snapshot: snapshot)
        ?? .error("no such route", code: 404)
}

func mcpJSON(_ response: HTTPResponse) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any] ?? [:]
}

func mcpRows(_ response: HTTPResponse, _ key: String = "senders") -> [[String: Any]] {
    mcpJSON(response)[key] as? [[String: Any]] ?? []
}








// MARK: - Agent proposals (TASK-45)

/// One proposal item, with only the field under test spelled out.
func proposalItem(_ key: String, reason: String = "no reason given") -> SenderProposal.Item {
    SenderProposal.Item(
        groupKey: "domain:\(key)", senderName: key.capitalized, senderEmail: "hello@\(key)",
        reason: reason)
}

func proposalGroup(_ key: String, messages: Int = 1) -> SenderGroup {
    SenderGroup(
        id: GroupID(kind: .domain, key: key),
        messages: (0..<messages).map { mcpMessage(UInt32(abs(key.hashValue % 1000) + $0), from: "X <a@\(key)>") })
}




// MARK: - TASK-46: the agent acts only on a selection the human confirmed


/// A stub action layer, so the write routes can be driven without a running app.
///
/// TASK-41 refuses the MCP surface in demo mode, so there is no mailbox a test
/// may drive these through — the harness is the only place they can be proven,
/// by design rather than by omission. It records what it was asked to do, which
/// is what most of these tests are actually asserting: that the route passed the
/// right thing along, or refused before it got here.
actor StubActions: MCPActions {
    struct Call: Equatable {
        let verb: String
        let detail: String
    }

    private(set) var calls: [Call] = []
    var proposalOutcome: AgentActionOutcome?

    private func note(_ verb: String, _ detail: String = "") {
        calls.append(Call(verb: verb, detail: detail))
    }

    func verbs() -> [String] { calls.map(\.verb) }
    func details(of verb: String) -> [String] {
        calls.filter { $0.verb == verb }.map(\.detail)
    }

    func propose(summary: String?, requests: [AgentProposalRequest]) async -> AgentActionOutcome {
        note(
            "propose",
            requests.map { "\($0.senderId)|\($0.recommendation.rawValue)" }
                .joined(separator: ","))
        let items = requests.map {
            SenderProposal.Item(
                groupKey: $0.senderId, senderName: $0.senderId, senderEmail: "x@\($0.senderId)",
                reason: $0.reason, recommendation: $0.recommendation)
        }
        return .proposal(
            AgentProposalBuilder.build(
                summary: summary, resolved: items, candidatesReceived: requests.count
            ).result)
    }

    func proposalStatus() async -> AgentActionOutcome {
        note("status")
        return .status(
            AgentProposalStatus(
                state: AgentProposalStatus.awaitingReview, proposalId: "p", createdAt: nil,
                summary: nil, proposedCount: 1, remainingCount: 1, removedByHuman: [],
                outcomes: [], note: "note"))
    }

    func requestUnsubscribe(senderId: String) async -> AgentActionOutcome {
        note("unsubscribe", senderId)
        return .result(
            AgentActionResult(
                status: AgentActionResult.awaitingConfirmation, senderId: senderId,
                detail: "asking the user"))
    }

    func requestTrash(senderId: String) async -> AgentActionOutcome {
        note("trash", senderId)
        return .result(
            AgentActionResult(
                status: AgentActionResult.awaitingConfirmation, senderId: senderId,
                detail: "asking the user"))
    }

    /// The browser queue this stub pretends to hold (TASK-47). Real enough to
    /// prove the thing that matters: routes can fill it and read it, and nothing
    /// on the surface can work it.
    private var browserQueue = BrowserQueue()

    func queue() -> BrowserQueue { browserQueue }

    func queueForBrowser(senderIds: [String]) async -> AgentActionOutcome {
        note("queue_for_browser", senderIds.joined(separator: ","))
        var results: [AgentSenderResult] = []
        for senderId in senderIds {
            let queued = browserQueue.queue(
                BrowserQueue.Entry(
                    groupKey: senderId, senderName: senderId, senderEmail: "x@\(senderId)",
                    reason: .noPublishedTarget))
            results.append(
                AgentSenderResult(
                    senderId: senderId, senderName: senderId, applied: queued,
                    detail: queued ? "queued" : "already waiting"))
        }
        return .browserQueue(
            AgentBrowserQueueStatus(queue: browserQueue, results: results, note: "queued."))
    }

    func browserQueueStatus() async -> AgentActionOutcome {
        note("browser_queue_status")
        return .browserQueue(AgentBrowserQueueStatus(queue: browserQueue))
    }

    /// Only a test may do this — it stands in for the human working the sheet,
    /// which is the one thing no route can reach.
    func humanRecords(_ outcome: BrowserQueue.Outcome, for senderId: String) {
        browserQueue.record(outcome, for: senderId)
    }

    func setIgnored(_ ignored: Bool, senderIds: [String]) async -> AgentActionOutcome {
        note(ignored ? "ignore" : "unignore", senderIds.joined(separator: ","))
        return .result(
            AgentActionResult(
                status: AgentActionResult.done, detail: "done",
                results: senderIds.map {
                    AgentSenderResult(senderId: $0, senderName: $0, applied: true, detail: "ok")
                }))
    }

    func setClassification(
        senderId: String, classification: String, reason: String, context: String?
    ) async -> AgentActionOutcome {
        note("classify", "\(senderId)|\(classification)|\(reason)|\(context ?? "-")")
        return .result(
            AgentActionResult(status: AgentActionResult.done, senderId: senderId, detail: "done"))
    }

    func startSync() async -> AgentActionOutcome {
        note("sync")
        return .result(AgentActionResult(status: AgentActionResult.done, detail: "started"))
    }

    func setGrouping(senderId: String, mode: AgentGroupingMode) async -> AgentActionOutcome {
        note("grouping", "\(senderId)|\(mode.rawValue)")
        return .result(
            AgentActionResult(status: AgentActionResult.done, senderId: senderId, detail: "done"))
    }

    func forgetUnsubscribeRecord(senderId: String) async -> AgentActionOutcome {
        note("forget", senderId)
        return .result(
            AgentActionResult(status: AgentActionResult.done, senderId: senderId, detail: "done"))
    }
}

func mcpWrite(_ path: String, _ arguments: [String: Any] = [:], actions: (any MCPActions)?)
    async -> HTTPResponse
{
    let body = try? JSONSerialization.data(withJSONObject: arguments)
    let request = HTTPRequest(
        method: "POST", path: path, headers: ["content-type": "application/json"], body: body)
    return await MCPWriteRoutes.handle(path: path, request: request, actions: actions)
        ?? .error("no such route", code: 404)
}




/// A server with a token and no mailbox, so what's under test is the order of
/// the checks rather than what any route would answer.
func guardedCall(
    _ path: String, token: String? = "secret", method: String = "POST", isDemo: Bool = false
) async -> HTTPResponse {
    let server = NevermoreServer(isDemo: isDemo, mcpToken: "secret")
    var headers = ["content-type": "application/json"]
    if let token { headers["authorization"] = "Bearer \(token)" }
    return await server.routeRequest(
        HTTPRequest(method: method, path: path, headers: headers, body: Data("{}".utf8)))
}


// MARK: - TASK-47: the browser queue

/// A group with one message, so `BrowserQueue.reason` has something to read.
func queueGroup(
    _ key: String = "acme.com", unsub: String? = "<https://ex.com/u>", oneClick: Bool = false
) -> SenderGroup {
    SenderGroup(
        id: GroupID(kind: .domain, key: key),
        messages: [mcpMessage(1, from: "A <a@\(key)>", unsub: unsub, oneClick: oneClick)])
}

func queueEntry(_ key: String, reason: BrowserReason = .noPublishedTarget) -> BrowserQueue.Entry {
    BrowserQueue.Entry(
        groupKey: "domain:\(key)", senderName: key, senderEmail: "hello@\(key)", reason: reason,
        queuedAt: Date(timeIntervalSince1970: 1_700_000_000))
}





// MARK: - Removing an account takes the whole database with it


// MARK: - Unsubscribe results report (TASK-28)

/// A run of `n` senders, all with the same outcome.
func report(_ outcome: UnsubscribeEngine.Outcome?, _ n: Int) -> UnsubscribeReport {
    UnsubscribeReport(outcomes: Array(repeating: outcome, count: n))
}


// MARK: - The action a proposal recommends (TASK-52)

/// Found in use: an agent proposed two cold-outreach senders with reasons
/// beginning "IGNORE, do not unsubscribe", and both were unsubscribed, because
/// the row's primary button said Unsubscribe and `u` was already in the fingers.
/// Prose cannot override a button, so the recommendation is data now.



// MARK: - DNS rebinding / pinned HTTP client (TASK-4)

/// A plain HTTP server on loopback that answers a canned response per request
/// and records what it was asked. Stands in for an unsubscribe endpoint.
///
/// Note this is a *test* listener. The app itself never binds one — the App
/// Sandbox entitlements grant `network.client` only, which is exactly why the
/// fix connects outbound rather than running a local proxy.
final class StubHTTPServer: @unchecked Sendable {
    private(set) var port: UInt16 = 0
    private let listener: NWListener
    private let respond: @Sendable (String) -> String
    private let lock = NSLock()
    private var seen: [String] = []

    var requests: [String] { lock.withLock { seen } }
    var requestLines: [String] { requests.map { $0.components(separatedBy: "\r\n").first ?? "" } }

    /// Accepts the connection and then says nothing, ever. A hostile endpoint
    /// costs nothing to run and this is the cheapest thing it can do to you.
    private let staysSilent: Bool

    init?(staysSilent: Bool = false, respond: @escaping @Sendable (String) -> String = { _ in "" }) {
        self.respond = respond
        self.staysSilent = staysSilent
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        guard let listener = try? NWListener(using: params, on: .any) else { return nil }
        self.listener = listener
        // Both handlers must be in place before start(), or the listener fails
        // instead of binding.
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed, .cancelled, .waiting: ready.signal()
            default: break
            }
        }
        listener.start(queue: .global())
        guard ready.wait(timeout: .now() + 3) == .success,
              case .ready = listener.state,
              let bound = listener.port?.rawValue
        else {
            listener.cancel()
            return nil
        }
        port = bound
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global())
        read(connection, accumulated: Data())
    }

    private func read(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = accumulated
            if let data { buffer.append(data) }
            if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[buffer.startIndex..<range.lowerBound], as: UTF8.self)
                self.lock.withLock { self.seen.append(head) }
                // Hold the connection open and answer nothing.
                if self.staysSilent { return }
                connection.send(
                    content: Data(self.respond(head).utf8),
                    completion: .contentProcessed { _ in connection.cancel() })
                return
            }
            if error != nil || isComplete {
                connection.cancel()
                return
            }
            self.read(connection, accumulated: buffer)
        }
    }

    func stop() { listener.cancel() }

    static func ok(_ body: String) -> String {
        "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: \(body.utf8.count)\r\n"
            + "Connection: close\r\n\r\n\(body)"
    }

    static func redirect(to location: String, status: Int = 302) -> String {
        "HTTP/1.1 \(status) Found\r\nLocation: \(location)\r\nContent-Length: 0\r\n"
            + "Connection: close\r\n\r\n"
    }
}

/// Records every lookup and can change its answer between them — the whole
/// point of the exercise.
final class RecordingResolver: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []
    private let answer: @Sendable (String, Int) -> [DestinationGuard.PinnedAddress]

    /// `answer` receives the host and the 1-based number of times *that host*
    /// has been looked up.
    init(_ answer: @escaping @Sendable (String, Int) -> [DestinationGuard.PinnedAddress]) {
        self.answer = answer
    }

    var hosts: [String] { lock.withLock { calls } }
    var callCount: Int { lock.withLock { calls.count } }
    func callCount(for host: String) -> Int { lock.withLock { calls.filter { $0 == host }.count } }

    var resolver: PinnedHTTPClient.Resolver {
        { [self] host in
            let nth: Int = lock.withLock {
                calls.append(host)
                return calls.filter { $0 == host }.count
            }
            return answer(host, nth)
        }
    }
}

func loopbackPin(_ host: String) -> DestinationGuard.PinnedAddress {
    DestinationGuard.PinnedAddress(host: host, literal: "127.0.0.1", isIPv6: false)
}

/// TEST-NET-2. Routable nowhere, so a connection attempt cannot succeed — which
/// is how "the client used the *other* answer" would show up as a failure.
func unreachablePin(_ host: String) -> DestinationGuard.PinnedAddress {
    DestinationGuard.PinnedAddress(host: host, literal: "198.51.100.1", isIPv6: false)
}

func send(
    _ client: PinnedHTTPClient, _ method: String, _ urlString: String,
    body: Data? = nil, timeout: TimeInterval = 8
) -> Result<PinnedHTTPClient.Response, PinnedHTTPClient.Failure> {
    runAsync {
        await client.send(
            method: method, url: URL(string: urlString)!, body: body, timeout: timeout)
    }
}

func status(
    _ result: Result<PinnedHTTPClient.Response, PinnedHTTPClient.Failure>
) -> Int? {
    guard case .success(let response) = result else { return nil }
    return response.statusCode
}

func failure(
    _ result: Result<PinnedHTTPClient.Response, PinnedHTTPClient.Failure>
) -> PinnedHTTPClient.Failure? {
    guard case .failure(let failure) = result else { return nil }
    return failure
}




// The engine's own vocabulary, driven through an injected client so the
// outcomes a user actually sees are the thing under test.

// MARK: - The backlog offer after a confirmed browser unsubscribe (TASK-23)


// MARK: - Extended search results

// The nil-vs-empty rule that replaced SwiftMail's deprecated `search`. Both
// directions are pinned because getting either wrong fails silently: a window
// that wrongly reads as "no matches" is indistinguishable from a genuinely
// empty date window, so discovery stores fewer messages and still reports
// success. There is no test here that reaches a real server — this pins the
// result *interpretation* only, not that the search itself is correct.

// MARK: - App-password guidance

// The app password is the one thing the user must go and get before Nevermore
// works at all, and every provider hides it somewhere different. What is pinned
// here is that the *right* guidance reaches the screen: the provider detected
// from the address, the provider's own noun for the credential, and a link
// rather than an invented UI path where the flow could not be checked.


// MARK: - Keychain prompt prediction

// These run against the maintainer's real login keychain, so they are
// deliberately read-only: nothing here adds, updates or deletes an item. The
// account name is one no keychain can hold an item for.
//
// What is therefore *not* covered here, and was verified by hand instead (see
// TASK-6): the case the function exists for — an item that exists but whose ACL
// excludes this binary. Reproducing it needs two differently signed binaries
// and a real item, and getting it wrong puts a system dialog on the screen.

/// Reads back the process-wide flag the probe toggles. The getter is deprecated
/// with the rest of SecKeychain, and warns here for the same reason the setter
/// warns in Keychain.swift: there is no modern spelling of this flag.
func userInteractionAllowed() -> Bool {
    var state: DarwinBoolean = false
    guard SecKeychainGetUserInteractionAllowed(&state) == errSecSuccess else { return false }
    return state.boolValue
}


// The Help menu links pages rather than restating them, so that help can be
// fixed without shipping a build. A link to a page that isn't there is worse
// than no link at all, and nothing in a menu item will tell you — so the checks
// that can be made here are made here: the URLs are on the site, and each one
// names a file that exists in `docs/`, which is what GitHub Pages publishes.

// MARK: - Smart selections (TASK-26)

// A smart selection decides what a batch of live unsubscribe requests will be
// aimed at, so every rule is checked at its boundary rather than in the middle.
// The rules are in the kit and take plain numbers; the menu that calls them is
// app-target and isn't reachable from here.

// MARK: - Undo of a trash restores where the message came from (TASK-8)

// A message identified well enough for undo: undo finds messages again by
// Message-ID, because a UID is only meaningful inside one mailbox.
func trashedMessage(_ uid: UInt32, messageId: String) -> EmailMessage {
    EmailMessage(
        uid: MessageUID(uid),
        sender: EmailSender(header: "News <news@ex.com>"),
        subject: "s",
        receivedAt: Date(timeIntervalSince1970: 1_700_000_000),
        isUnread: false,
        unsubscribe: ListUnsubscribe(header: "<https://ex.com/u>"),
        messageId: messageId)
}




// MARK: - Automatic update checks (TASK-9)


// MARK: - Unsubscribe report (TASK-32)

/// A fixed clock, so nothing here depends on when the suite runs.
let reportNow = Date(timeIntervalSince1970: 1_700_000_000)

func reportMsg(_ uid: UInt32, daysAgo: Double) -> EmailMessage {
    EmailMessage(
        uid: MessageUID(uid),
        sender: EmailSender(header: "Acme <news@acme.com>"),
        subject: "s",
        receivedAt: reportNow.addingTimeInterval(-daysAgo * 86400),
        isUnread: false,
        unsubscribe: ListUnsubscribe(header: "<https://ex.com/u>"))
}

func reportRecord(
    _ key: String = "domain:acme.com",
    daysAgo: Double,
    outcome: MessageStore.Outcome = .requested
) -> MessageStore.UnsubscribeRecord {
    MessageStore.UnsubscribeRecord(
        groupKey: key,
        senderName: "Acme",
        senderEmail: "news@acme.com",
        senderDomain: "acme.com",
        url: nil,
        attemptedAt: reportNow.addingTimeInterval(-daysAgo * 86400),
        outcome: outcome)
}

/// Mail every `every` days, from `from` days ago up to `until` days ago.
func reportSeries(every: Double, from: Double, until: Double) -> [EmailMessage] {
    var out: [EmailMessage] = []
    var d = from
    var uid: UInt32 = 1
    while d >= until {
        out.append(reportMsg(uid, daysAgo: d))
        uid += 1
        d -= every
    }
    return out
}

func makeReport(
    _ records: [MessageStore.UnsubscribeRecord],
    _ messages: [String: [EmailMessage]] = [:],
    windowDays: Double = 30
) -> UnsubscribePeriodReport {
    UnsubscribePeriodReport.make(
        records: records,
        messagesByGroupKey: messages,
        since: reportNow.addingTimeInterval(-windowDays * 86400),
        now: reportNow)
}

// MARK: - Authentication-Results parsing (TASK-30)

/// A Gmail header for mail that authenticated cleanly, comments and all.
let authPassHeader = """
    mx.google.com;
           dkim=pass header.i=@substack.com header.s=google header.b=Xy1zAbc;
           spf=pass (google.com: domain of bounces+1-abc@substack.com designates \
    209.85.220.41 as permitted sender) smtp.mailfrom="bounces+1-abc@substack.com";
           dmarc=pass (p=NONE sp=NONE dis=NONE) header.from=substack.com
    """

/// The shape a cold sender arrives in: nothing lines up, and DMARC says so.
let authFailHeader = """
    mx.google.com;
           spf=softfail (google.com: domain of transitioning sales@coldoutreach.biz does not \
    designate 45.9.1.2 as permitted sender) smtp.mailfrom=sales@coldoutreach.biz;
           dmarc=fail (p=NONE sp=NONE dis=NONE) header.from=coldoutreach.biz
    """


// MARK: - The verdict a sender's own mail supports (TASK-30)

func trustMessage(
    _ uid: UInt32,
    from: String = "news@acme.com",
    name: String = "Acme",
    unsubscribe: String? = "<https://acme.com/u?id=1>",
    auth: String? = nil,
    listID: String? = nil,
    daysAgo: Double = 1
) -> EmailMessage {
    let host = from.contains("@") ? String(from.split(separator: "@").last!) : ""
    return EmailMessage(
        uid: MessageUID(uid),
        sender: EmailSender(displayName: name, address: from, host: host),
        subject: "Subject \(uid)",
        receivedAt: Date().addingTimeInterval(-daysAgo * 86400),
        isUnread: true,
        unsubscribe: ListUnsubscribe(header: unsubscribe),
        deliveredTo: "me@example.com",
        messageId: "<\(uid)@acme.com>",
        listID: listID,
        authentication: AuthenticationResults(header: auth))
}

func trustGroup(_ messages: [EmailMessage], key: String = "acme.com") -> SenderGroup {
    SenderGroup(id: GroupID(kind: .domain, key: key), messages: messages)
}


// MARK: - Where the unsubscribe would actually go (TASK-30 AC #4)


// MARK: - Whose recommendation wins the badge (TASK-52 left this open)


// MARK: - The one dialog both objections share (TASK-30 + TASK-52)


// MARK: - Storing it, and the switch that is not on yet (TASK-30 AC #1)
