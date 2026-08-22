import Foundation
import Network

/// The HTTP client unsubscribe requests go out through, built so that the
/// address `DestinationGuard` approved is the address the socket connects to.
///
/// `URLSession` cannot do that. It resolves the hostname itself when it opens
/// the connection, so checking a name and then handing that name to `URLSession`
/// leaves a window where a hostile resolver answers public for the check and
/// private for the connection. Every URL here comes out of a stranger's
/// `List-Unsubscribe` header, so that window is a real way into the user's LAN,
/// not a theoretical one.
///
/// Two approaches were measured and rejected before this one:
///
/// * Rewrite the URL to the validated IP and set `Host:`. CFNetwork does honour
///   a custom `Host` header, but with an IP literal in the URL it sends **no
///   SNI at all**, so shared-hosting and CDN endpoints are served the wrong
///   certificate. Shipping it would mean loosening trust evaluation.
/// * Route `URLSession` through a loopback `CONNECT` proxy. Works, and keeps TLS
///   end-to-end — but a listener needs `com.apple.security.network.server`, which
///   the App Sandbox entitlements deliberately do not grant (see
///   `Resources/Nevermore.entitlements`). It would have failed to bind in the Mac
///   App Store build and broken unsubscribing there completely.
///
/// So the connection is made here instead, outbound only, which
/// `com.apple.security.network.client` already covers:
///
/// * `NWConnection` dials `NWEndpoint.hostPort` with a literal `.ipv4`/`.ipv6`
///   address, so nothing downstream has a name left to resolve.
/// * `sec_protocol_options_set_tls_server_name` sets the real hostname, so the
///   origin still receives correct SNI and serves the right certificate.
/// * Trust evaluation is left at the default. **There is no verify block in this
///   file, and there must never be one.** Verified against badssl.com through
///   this exact configuration: `wrong.host.badssl.com` (validly chained, wrong
///   name) is rejected, as are `expired.` and `self-signed.`, while
///   `badssl.com` itself connects. Hostname, expiry and issuer are all still
///   checked.
///
/// Only response *headers* are read. The engine never looks at a body, and not
/// reading one means no chunked decoding, no content negotiation, and no gzip —
/// which is most of what makes a hand-written HTTP client risky.
public struct PinnedHTTPClient: Sendable {
    /// Returns every validated address for the host, best first, or empty to
    /// refuse. Injected so tests can drive a resolver that changes its answer
    /// between lookups, which is otherwise not something you can arrange
    /// deterministically.
    public typealias Resolver = @Sendable (String) -> [DestinationGuard.PinnedAddress]

    /// Enough hops for the redirect chains real unsubscribe endpoints use, and
    /// few enough that a loop ends.
    public static let maxRedirects = 10

    /// No single address is given less than this, however many a host publishes —
    /// a slice so thin that a healthy but slow endpoint times out would turn
    /// failover into a way of reaching nothing at all.
    static let minimumAttemptSeconds: TimeInterval = 4

    private let resolve: Resolver

    public init(resolve: @escaping Resolver = { DestinationGuard.pinnedAddresses(for: $0) }) {
        self.resolve = resolve
    }

    public struct Response: Sendable {
        public let statusCode: Int
        /// Header names lowercased on parse, so lookups don't depend on the
        /// sender's casing.
        public let headers: [String: String]
    }

    public enum Failure: Error, Equatable {
        /// The guard refused the destination: private, local, unresolvable, or
        /// not http(s).
        case blocked(host: String)
        case tooManyRedirects
        case transport(String)
        case malformedResponse
    }

    /// Send one request, following redirects, pinning every hop separately.
    public func send(
        method: String,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval = 30
    ) async -> Result<Response, Failure> {
        var target = url
        var method = method
        var body = body
        /// The 3xx that sent us to the current hop, if any. A refused *redirect*
        /// is reported by handing this back unfollowed rather than as a failure,
        /// so the caller can still tell "the sender pointed us somewhere
        /// internal" apart from "the unsubscribe URL itself was internal". Those
        /// read differently to a user and always have.
        var arrivedVia: Response?

        for _ in 0...Self.maxRedirects {
            guard let hop = Hop(target) else {
                if let arrivedVia { return .success(arrivedVia) }
                return .failure(.blocked(host: target.host ?? "?"))
            }
            // THE pin: one lookup per hop, and the addresses it returns are what
            // the connection below dials. Nothing re-resolves the name.
            let pinned = resolve(hop.host)
            guard !pinned.isEmpty else {
                Log.unsubscribe.problem(
                    "refusing \(hop.host): resolves to a private or local address, or not at all")
                if let arrivedVia { return .success(arrivedVia) }
                return .failure(.blocked(host: hop.host))
            }

            let response: Response
            do {
                response = try await perform(
                    hop: hop, pinned: pinned, method: method, headers: headers, body: body,
                    timeout: timeout)
            } catch let failure as Failure {
                return .failure(failure)
            } catch {
                return .failure(.transport("\(error)"))
            }

            // Not a redirect, or one we can't follow: hand it back as the final
            // response. A 3xx surfacing to the caller is how a refused redirect
            // is reported, and `UnsubscribeEngine` turns it into "blocked".
            guard (300..<400).contains(response.statusCode),
                  let location = response.headers["location"],
                  let next = URL(string: location, relativeTo: target)?.absoluteURL,
                  Hop(next) != nil
            else { return .success(response) }

            // The next hop is validated on its own account on the next pass
            // round the loop — same resolve, same check, same pin. A redirect
            // into a private address is refused there.
            if response.statusCode != 307 && response.statusCode != 308 {
                // 301/302/303 to a GET, which is what every browser and
                // URLSession do; only 307/308 promise the method is preserved.
                method = "GET"
                body = nil
            }
            target = next
            arrivedVia = response
        }
        return .failure(.tooManyRedirects)
    }

    // MARK: - One hop

    /// A destination this client is willing to talk to at all. Public so the
    /// derivation of `Host:` and the request target can be tested directly —
    /// getting either wrong breaks every virtual-hosted endpoint.
    public struct Hop: Equatable, Sendable {
        public let host: String
        public let port: UInt16
        public let useTLS: Bool
        public let pathAndQuery: String
        /// What goes in `Host:` — the name, plus the port when it isn't the
        /// scheme's default. This is what keeps virtual hosts working.
        public let hostHeader: String

        public init?(_ url: URL) {
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  let host = url.host, !host.isEmpty
            else { return nil }
            useTLS = scheme == "https"
            let defaultPort: UInt16 = useTLS ? 443 : 80
            guard let port = url.port.flatMap({ UInt16(exactly: $0) }) ?? defaultPort as UInt16?
            else { return nil }
            self.host = host
            self.port = port
            var path = url.path.isEmpty ? "/" : url.path
            if let query = url.query { path += "?\(query)" }
            pathAndQuery = path
            // IPv6 literals are bracketed in a Host header.
            let bracketed = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
            hostHeader = port == defaultPort ? bracketed : "\(bracketed):\(port)"
        }
    }

    /// Try each validated address in turn, so one dead address in a set of
    /// answers doesn't read as an endpoint that refuses to unsubscribe you.
    /// Every address here came from the same single lookup and passed the same
    /// check, so failover costs nothing in what is being defended against.
    private func perform(
        hop: Hop,
        pinned: [DestinationGuard.PinnedAddress],
        method: String,
        headers: [String: String],
        body: Data?,
        timeout: TimeInterval
    ) async throws -> Response {
        // Each address gets a slice of the caller's budget rather than the whole
        // of it, so trying several cannot take several times as long as trying
        // one. A single-address host — the common case — still gets everything.
        let slice = max(Self.minimumAttemptSeconds, timeout / Double(pinned.count))
        var lastFailure: Error = Failure.blocked(host: hop.host)
        for address in pinned {
            do {
                return try await perform(
                    hop: hop, address: address, method: method, headers: headers, body: body,
                    timeout: slice)
            } catch {
                lastFailure = error
                if pinned.count > 1 {
                    Log.unsubscribe.detail("\(hop.host) via \(address.literal) failed: \(error)")
                }
            }
        }
        throw lastFailure
    }

    private func perform(
        hop: Hop,
        address: DestinationGuard.PinnedAddress,
        method: String,
        headers: [String: String],
        body: Data?,
        timeout: TimeInterval
    ) async throws -> Response {
        guard let endpointHost = Self.literalHost(address),
              let endpointPort = NWEndpoint.Port(rawValue: hop.port)
        else { throw Failure.blocked(host: hop.host) }

        Log.unsubscribe.detail("\(method) \(hop.host) -> \(address.literal):\(hop.port)")

        let connection = PinnedConnection(
            host: endpointHost, port: endpointPort, serverName: hop.host, useTLS: hop.useTLS,
            connectTimeout: timeout)
        defer { connection.cancel() }

        return try await withThrowingTaskGroup(of: Response.self) { group in
            group.addTask {
                try await connection.start()
                try await connection.send(
                    Self.requestBytes(hop: hop, method: method, headers: headers, body: body))
                let head = try await connection.receiveHead()
                guard let response = Self.parseResponseHead(head) else {
                    throw Failure.malformedResponse
                }
                return response
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                // Cancelling the connection is what actually ends the attempt.
                // Network.framework does not observe Swift task cancellation, so
                // without this the sibling task stays parked in a continuation
                // until the OS gives up — measured at 30s against a blackholed
                // address, whatever budget the caller asked for. The timeout
                // would be reported accurately and honoured by nobody.
                connection.cancel()
                throw Failure.transport("timed out after \(Int(timeout))s")
            }
            guard let first = try await group.next() else { throw Failure.malformedResponse }
            group.cancelAll()
            return first
        }
    }

    /// Build the endpoint from the address that was checked, as an explicit
    /// `.ipv4`/`.ipv6` case rather than a name — so there is no path by which
    /// Network.framework could perform a lookup of its own.
    private static func literalHost(_ pinned: DestinationGuard.PinnedAddress) -> NWEndpoint.Host? {
        if pinned.isIPv6 {
            guard let address = IPv6Address(pinned.literal) else { return nil }
            return .ipv6(address)
        }
        guard let address = IPv4Address(pinned.literal) else { return nil }
        return .ipv4(address)
    }

    // MARK: - Wire format

    /// Serialise the request. `Connection: close` because these are one-shot —
    /// there is no second request to keep a socket warm for.
    public static func requestBytes(
        hop: Hop, method: String, headers: [String: String], body: Data?
    ) -> Data {
        var lines = ["\(method) \(hop.pathAndQuery) HTTP/1.1", "Host: \(hop.hostHeader)"]
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
            // Host and framing are this function's to decide, not the caller's.
            let lower = name.lowercased()
            guard lower != "host", lower != "content-length", lower != "connection" else { continue }
            lines.append("\(name): \(value)")
        }
        if let body {
            lines.append("Content-Length: \(body.count)")
        }
        lines.append("Connection: close")
        var data = Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        if let body { data.append(body) }
        return data
    }

    /// Parse a response head: status line plus headers. Deliberately does not
    /// touch the body.
    public static func parseResponseHead(_ head: Data) -> Response? {
        guard let text = String(data: head, encoding: .ascii) ?? String(data: head, encoding: .utf8)
        else { return nil }
        var lines = text.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let statusLine = lines.removeFirst()
        // "HTTP/1.1 302 Found" — the reason phrase is optional and unused.
        let parts = statusLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0].uppercased().hasPrefix("HTTP/"),
              let status = Int(parts[1]), (100..<600).contains(status)
        else { return nil }

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            // First occurrence wins, so a second Location can't override the first.
            if headers[name] == nil { headers[name] = value }
        }
        return Response(statusCode: status, headers: headers)
    }
}

// MARK: - Connection

/// `NWConnection` with async methods, and a continuation that can only be
/// resumed once — Network.framework reports terminal states more than once, and
/// resuming twice is a crash rather than a warning.
private final class PinnedConnection: @unchecked Sendable {
    private let connection: NWConnection
    /// Header blocks are small; past this it isn't a response we can use.
    private static let maxHeadBytes = 64 * 1024

    init(
        host: NWEndpoint.Host, port: NWEndpoint.Port, serverName: String, useTLS: Bool,
        connectTimeout: TimeInterval
    ) {
        let params: NWParameters
        if useTLS {
            let tls = NWProtocolTLS.Options()
            // The origin gets the real hostname, so shared hosting and CDNs
            // serve the right certificate — and, just as importantly, this is
            // the name trust evaluation checks the certificate against.
            //
            // NO verify block is set. Default evaluation stays in force.
            sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, serverName)
            params = NWParameters(tls: tls)
        } else {
            params = NWParameters.tcp
        }
        if let tcp = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            // Track the caller's budget: a connect phase allowed to outlast the
            // attempt it belongs to would strand the whole request on one address.
            tcp.connectionTimeout = max(1, Int(connectTimeout))
            tcp.noDelay = true
        }
        connection = NWConnection(host: host, port: port, using: params)
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ContinuationGate(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.resume(.success(()))
                case .failed(let error):
                    gate.resume(.failure(PinnedHTTPClient.Failure.transport("\(error)")))
                case .waiting(let error):
                    // A TLS rejection surfaces here, not in .failed. Treat it as
                    // terminal: retrying cannot make an invalid certificate valid.
                    gate.resume(.failure(PinnedHTTPClient.Failure.transport("\(error)")))
                case .cancelled:
                    gate.resume(.failure(PinnedHTTPClient.Failure.transport("cancelled")))
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ContinuationGate(continuation)
            connection.send(
                content: data,
                completion: .contentProcessed { error in
                    if let error {
                        gate.resume(.failure(PinnedHTTPClient.Failure.transport("\(error)")))
                    } else {
                        gate.resume(.success(()))
                    }
                })
        }
    }

    /// Read until the end of the header block. The body is never read.
    func receiveHead() async throws -> Data {
        var buffer = Data()
        while true {
            let chunk = try await receiveChunk()
            if let chunk { buffer.append(chunk) }
            if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                return buffer[buffer.startIndex..<range.lowerBound]
            }
            if chunk == nil { throw PinnedHTTPClient.Failure.malformedResponse }
            if buffer.count > Self.maxHeadBytes { throw PinnedHTTPClient.Failure.malformedResponse }
        }
    }

    /// Nil means the peer finished without completing the header block.
    private func receiveChunk() async throws -> Data? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
            let gate = ContinuationGate(continuation)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) {
                data, _, isComplete, error in
                if let error {
                    gate.resume(.failure(PinnedHTTPClient.Failure.transport("\(error)")))
                } else if isComplete && (data?.isEmpty ?? true) {
                    gate.resume(.success(nil))
                } else {
                    gate.resume(.success(data))
                }
            }
        }
    }

    func cancel() { connection.cancel() }
}
