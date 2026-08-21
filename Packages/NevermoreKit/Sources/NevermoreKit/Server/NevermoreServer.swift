import Foundation
import Network

// MARK: - Response types

private struct PingResponse: Encodable {
    let app: String
    let version: String
    let isDemo: Bool

    enum CodingKeys: String, CodingKey {
        case app, version
        case isDemo = "is_demo"
    }
}

private struct HealthResponse: Encodable {
    let isOK: Bool

    enum CodingKeys: String, CodingKey {
        case isOK = "ok"
    }
}

/// Hands a continuation to `NWListener`'s callbacks, which run on a network queue and may report a
/// terminal state more than once. Resuming a continuation twice is a crash, not a warning, so the
/// gate takes the continuation on the first resume and drops it. A plain `var didResume` can't do
/// this job under strict concurrency — it would be a mutable capture in a `@Sendable` closure.
private final class ContinuationGate<T, E: Error>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, E>?

    init(_ continuation: CheckedContinuation<T, E>) {
        self.continuation = continuation
    }

    func resume(_ result: sending Result<T, E>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}

// MARK: - NevermoreServer

/// Nevermore's loopback-only companion HTTP server, ported from jobhunt.
///
/// It exists so the MCP bridge (TASK-44) has something to forward to. Today it serves only
/// `/health` and `/api/ping` — enough for a client to discover which contract port the app is on —
/// plus the authenticated `/mcp/*` prefix that the tool routes will hang off.
public actor NevermoreServer {
    /// The bound port, or 0 when not listening.
    public private(set) var port: UInt16 = 0
    private var listener: NWListener?
    private let appVersion: String
    private let isDemo: Bool
    /// The token `/mcp/*` requests must present. Empty means MCP is not configured, and every MCP
    /// route answers 503 — fail closed rather than fail open.
    private let mcpToken: String
    /// Which account the MCP routes read, and its store. Settable rather than an init parameter
    /// because the server outlives the open account: the user switches accounts, or closes the one
    /// that was open, without the listener going down.
    private var mcpContext: MCPContext?

    public init(
        appVersion: String = AppVersion.marketing,
        isDemo: Bool = false,
        mcpToken: String = ""
    ) {
        self.appVersion = appVersion
        self.isDemo = isDemo
        self.mcpToken = mcpToken
    }

    /// Bind the first free port in `ServerPortContract.discoveryPorts` (8775–8779).
    ///
    /// There is NO ephemeral fallback: an OS-assigned port is undiscoverable by the bridge, so if
    /// every contract port is taken this throws `ServerError.noPortAvailable` and the failure gets
    /// surfaced (Settings → Local Server, TASK-48) rather than the server running on a port no
    /// client can find.
    ///
    /// Idempotent: if a listener is already bound this is a no-op, so a "Retry" flow can't bind a
    /// second conflicting listener. A failed start leaves `listener == nil`, so a retry after a
    /// failure still proceeds.
    public func start() async throws {
        guard listener == nil else { return }

        for candidate in ServerPortContract.discoveryPorts {
            do {
                try await startListener(on: candidate)
                port = candidate
                Log.app.event("local server listening on 127.0.0.1:\(candidate)")
                return
            } catch {
                continue
            }
        }
        Log.app.problem("local server could not bind any port in \(ServerPortContract.discoveryPorts)")
        throw ServerError.noPortAvailable
    }

    /// Start on an OS-assigned ephemeral port. For tests only, where the exact port doesn't matter
    /// and port reuse / TIME_WAIT must be avoided. Never a production fallback — see `start()`.
    public func startOnAnyPort() async throws {
        guard listener == nil else { return }
        try await startListener(on: 0)
    }

    public func stop() async {
        guard let l = listener else { return }
        // Wait for the listener to reach .cancelled so the OS releases the port before returning —
        // otherwise the next test's server gets an RST on the port this one just gave up.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let gate = ContinuationGate(continuation)
            l.stateUpdateHandler = { state in
                if case .cancelled = state { gate.resume(.success(())) }
            }
            l.cancel()
        }
        listener = nil
        port = 0
    }

    public var listeningPort: UInt16 { port }

    public var isListening: Bool { listener != nil }

    /// Point the MCP routes at an open account, or at nothing.
    ///
    /// Nil is meaningful: with no context every tool answers 503 rather than serving an empty
    /// mailbox, because "this account has no senders" and "no account is open" are answers an agent
    /// would act on very differently.
    public func setMCPContext(_ context: MCPContext?) {
        mcpContext = context
    }

    // MARK: - Listener parameters

    /// The parameters every listener is built with. Public and separate so a test can assert the
    /// loopback restriction directly — it is the security boundary (see SECURITY MODEL below), and
    /// a silent change to it would otherwise only show up as LAN exposure in the field.
    public static func listenerParameters() -> NWParameters {
        let params = NWParameters.tcp
        // Bind the loopback interface only. Non-loopback peers are refused at the OS networking
        // layer and never reach route handling — this does not rely on client behaviour or on any
        // route-level check. Loopback clients (the MCP bridge, via 127.0.0.1) are unaffected.
        //
        // Note that `lsof -iTCP:8775` reports the socket as `*:8775`, not `127.0.0.1:8775`:
        // Network.framework enforces the restriction by evaluating each incoming connection's path
        // rather than by narrowing the bind address. So a tool that reads the bind address will
        // claim this port is exposed to the LAN. It is not — verified with
        // `nc <this-machine-LAN-IP> 8775`, which is refused while `nc 127.0.0.1 8775` succeeds.
        // Re-verify that way, not by reading lsof, if this is ever in doubt.
        params.requiredInterfaceType = .loopback
        return params
    }

    // MARK: - Private

    private func startListener(on candidatePort: UInt16) async throws {
        let params = Self.listenerParameters()
        // candidatePort == 0 lets the OS assign an ephemeral port (tests only).
        let nwPort: NWEndpoint.Port = candidatePort == 0 ? .any : {
            guard let p = NWEndpoint.Port(rawValue: candidatePort) else { return .any }
            return p
        }()

        let listener = try NWListener(using: params, on: nwPort)
        // Set before start(), and weakly, so the listener's retained handler doesn't keep the actor
        // alive after the app drops it.
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.handleConnection(connection) }
        }

        // The continuation carries the actual bound port so we read it inside the .ready callback,
        // where NWListener.port is guaranteed to be set. A 3-second timeout guards against the
        // listener sitting in .waiting forever (seen when nw_path_create_evaluator fails).
        let boundPort: UInt16 = try await withThrowingTaskGroup(of: UInt16.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
                    let gate = ContinuationGate(continuation)
                    listener.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            gate.resume(.success(listener.port?.rawValue ?? candidatePort))
                        case let .failed(error):
                            gate.resume(.failure(error))
                        case .cancelled:
                            gate.resume(.failure(ServerError.listenerCancelled))
                        case .waiting:
                            // .waiting means the port is temporarily unavailable — treat it as a
                            // failure so the caller moves on to the next candidate port.
                            gate.resume(.failure(ServerError.listenerWaiting))
                        default:
                            break
                        }
                    }
                    listener.start(queue: .global(qos: .userInitiated))
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 3_000_000_000) // 3-second timeout
                listener.cancel()
                throw ServerError.listenerTimeout
            }
            guard let result = try await group.next() else {
                group.cancelAll()
                throw ServerError.listenerTimeout
            }
            group.cancelAll()
            return result
        }

        self.listener = listener
        if boundPort != 0 {
            port = boundPort
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveRequest(on: connection)
    }

    /// Maximum request body size per route. MCP payloads are moderate; everything else is small.
    /// An oversized request is rejected with 413 from its Content-Length, before the body is read.
    public static func maxBodySize(forPath path: String) -> Int {
        switch path {
        case _ where path.hasPrefix("/mcp/"): 1_048_576 // 1 MB — MCP metadata/read routes
        default: 64 * 1024 // 64 KB (health/ping)
        }
    }

    /// Header-block size cap. 64 KB is far above any legitimate request's headers and bounds
    /// resource use from a slow or malformed local client before the body is read.
    public static let maxHeaderBytes = 64 * 1024

    /// Upper bound on total bytes accumulated for one request before giving up: the largest
    /// per-route body budget plus the header cap. Bounds memory from a slow or oversized client
    /// while still letting an in-budget body finish arriving.
    public static let maxRequestBytes = 1_048_576 + maxHeaderBytes

    // nonisolated: only touches NWConnection and spawns Tasks back onto the actor.
    // Accumulates TCP chunks until a complete HTTP request is available before processing.
    private nonisolated func receiveRequest(on connection: NWConnection, accumulated: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [self] data, _, isComplete, _ in
            var buffer = accumulated
            if let data, !data.isEmpty {
                buffer.append(data)
            }

            func reject(_ reason: String, _ code: Int) {
                Task { await self.sendResponse(HTTPResponse.error(reason, code: code), on: connection) }
            }
            func readMoreOrFail() {
                // Keep accumulating until the largest legitimate request could fit (max body budget
                // + header cap). A lower ceiling here would reject in-budget bodies before they
                // finished arriving. Over-Content-Length bodies are still rejected with 413 above.
                if !isComplete, buffer.count < Self.maxRequestBytes {
                    receiveRequest(on: connection, accumulated: buffer)
                } else {
                    reject("Bad request", 400)
                }
            }

            // Validate framing (header size + Content-Length) before routing — fail closed.
            switch inspectRequestFraming(buffer, maxHeaderBytes: Self.maxHeaderBytes) {
            case .incomplete:
                readMoreOrFail()
            case let .invalid(reason, code):
                reject(reason, code)
            case let .valid(_, path, contentLength):
                let limit = Self.maxBodySize(forPath: path)
                if contentLength > limit {
                    reject("Request body too large (\(contentLength) bytes; limit \(limit))", 413)
                    return
                }
                if let request = parseHTTPRequest(buffer) {
                    Task { await self.sendResponse(self.routeRequest(request), on: connection) }
                } else {
                    // Headers are framed but the body bytes haven't all arrived — keep reading.
                    readMoreOrFail()
                }
            }
        }
    }

    private func sendResponse(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.toHTTPBytes(), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // SECURITY MODEL — read this before adding an `Origin` check and calling it authentication.
    //
    // **The loopback binding is the boundary.** `params.requiredInterfaceType = .loopback` (see
    // `listenerParameters()`) is what keeps other machines out: a non-loopback peer is refused at
    // the OS networking layer and never reaches any of this code. Nothing below is load-bearing for
    // that, and nothing below can substitute for it.
    //
    // An `Origin` header is set by a browser and forged by any local process in one line of curl,
    // so it cannot authenticate a caller. Jobhunt carries an origin allowlist because its server is
    // also driven by a Chrome extension, and the allowlist's only job there is stopping *other*
    // extensions driving it from inside the browser, where the same-origin policy makes `Origin`
    // trustworthy. Nevermore has no browser client, so there is nothing for such a check to do —
    // and a CORS surface here would only invite a later reader to mistake it for access control.
    // Do not add one.
    //
    // So `/health` and `/api/ping` are protected against the network and NOT against a hostile
    // process already running as this user. That is deliberate for a single-user localhost
    // companion: both routes report only the app's version and whether it is in demo mode, and any
    // such process could read the GRDB store directly anyway.
    //
    // `/mcp/*` DOES carry a bearer token, for a different reason: those routes are driven by
    // third-party AI clients, and the token scopes which of them may act on the user's mail. That
    // is a real distinction, not belt-and-braces — the MCP surface acts, the discovery routes only
    // describe.
    //
    // If a hostile-localhost threat model ever matters for the discovery routes, the fix is the
    // same launch-time secret the token already is, handed over at port discovery — not a stricter
    // origin list.

    /// Public so routing policy can be unit-tested directly, without a socket.
    public func routeRequest(_ request: HTTPRequest) -> HTTPResponse {
        // The parser frames bodies by Content-Length only. A request using Transfer-Encoding (e.g.
        // chunked) would otherwise parse with an empty body and be misreported as invalid JSON.
        // Reject it explicitly, before MCP dispatch, so framing policy doesn't vary by route.
        if request.headers["transfer-encoding"] != nil {
            return .error("Transfer-Encoding is not supported; send a Content-Length body.", code: 400)
        }

        if request.path.hasPrefix("/mcp/") {
            return routeMCPRequest(request)
        }

        switch (request.method, request.path) {
        case ("GET", "/health"):
            return .ok(HealthResponse(isOK: true))
        case ("GET", "/api/ping"):
            return .ok(PingResponse(app: "nevermore", version: appVersion, isDemo: isDemo))
        default:
            return .error("Not found", code: 404)
        }
    }

    /// Authenticate and dispatch `/mcp/*`.
    ///
    /// The order of the checks is the contract a client reads its situation from, and each answer
    /// means one thing only: 401 the credential, 404 the route, 403 demo mode, 503 no mailbox. A
    /// bridge that got 403 where it expected 404 would report "that tool doesn't exist" for an app
    /// that is merely showing the demo.
    private func routeMCPRequest(_ request: HTTPRequest) -> HTTPResponse {
        // Fail closed: an empty server token means MCP is not configured — never "no token
        // required".
        guard !mcpToken.isEmpty else {
            return .error("MCP not configured", code: 503)
        }
        guard let provided = Self.bearerToken(from: request), !provided.isEmpty,
              constantTimeEquals(provided, mcpToken) else {
            return .error("Unauthorized", code: 401)
        }
        // Every MCP tool call is a POST. Reject anything else so the route surface matches the
        // bridge contract rather than accepting whatever a client happens to send.
        guard request.method == "POST" else {
            return .error("Method not allowed; MCP routes require POST", code: 405)
        }
        // Unknown routes are answered before anything about the mailbox, so 404 keeps meaning
        // "no such tool" whatever state the app happens to be in.
        guard MCPRoutes.paths.contains(request.path) else {
            return .error("MCP route not found", code: 404)
        }
        // TASK-41: the demo mailbox is fabricated, and an agent told to triage it would spend a
        // context window reasoning about senders that do not exist. Refuse rather than serve it.
        if isDemo {
            return .error(
                "Nevermore is in demo mode. The demo mailbox is fabricated, so the tools refuse "
                    + "rather than let an agent reason about senders that aren't real. Leave demo "
                    + "mode in the app and try again.",
                code: 403)
        }
        guard let context = mcpContext else {
            return .error(
                "No mailbox is open in Nevermore. Open an account in the app and try again.",
                code: 503)
        }
        // Rebuilt per request: the app writes to this database whenever a sync lands or the user
        // acts, so a cached read model would describe a mailbox that has moved on.
        let snapshot: MCPSnapshot
        do {
            snapshot = try MCPSnapshot.load(context)
        } catch {
            Log.app.problem("MCP snapshot failed: \(error.localizedDescription)")
            return .error("Could not read the mailbox: \(error.localizedDescription)", code: 500)
        }
        return MCPRoutes.handle(path: request.path, request: request, snapshot: snapshot)
            ?? .error("MCP route not found", code: 404)
    }

    /// Extract the credential from `Authorization: Bearer <token>`. The scheme is matched
    /// case-insensitively (RFC 7235 says it is case-insensitive); the token is not.
    public static func bearerToken(from request: HTTPRequest) -> String? {
        guard let header = request.headers["authorization"] else { return nil }
        let parts = header.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else { return nil }
        return parts[1].trimmingCharacters(in: .whitespaces)
    }
}

/// Constant-time equality for the MCP token. Accumulates byte differences without an early exit, so
/// the comparison's duration doesn't reveal the token's length or its matching prefix.
func constantTimeEquals(_ a: String, _ b: String) -> Bool {
    let aBytes = Array(a.utf8)
    let bBytes = Array(b.utf8)
    var diff = aBytes.count ^ bBytes.count
    for i in 0 ..< max(aBytes.count, bBytes.count) {
        let av = i < aBytes.count ? aBytes[i] : 0
        let bv = i < bBytes.count ? bBytes[i] : 0
        diff |= Int(av ^ bv)
    }
    return diff == 0
}
