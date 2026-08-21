// nevermore-mcp — a stdio-to-HTTP bridge between an MCP client and the running
// Nevermore.app.
//
// It holds nothing but a token and a port: no database, no mailbox, no
// entitlements, no state that outlives a request. That is the whole point of the
// shape — an MCP client spawns this binary as an arbitrary child process, and a
// child process that could open the user's mail store would be a far larger
// thing to hand out than a forwarder that can only ask the running app.
//
// Direct-download builds only. `Project.swift` (the Mac App Store target)
// depends on the NevermoreKit *library* product and never on this executable, so
// the store build cannot contain it.
import Foundation
import NevermoreKit

// MARK: - Discovery

/// Find the port Nevermore is listening on by probing the contract range.
///
/// `/health` and not `/api/ping`: it is the cheapest 200 the server has, and it
/// needs no credential — so a bad token surfaces later, as a 401 from the route
/// that needed it, instead of as "the app isn't running".
func discoverPort() -> UInt16? {
    for port in ServerPortContract.discoveryPorts {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { continue }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0
        var found = false
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 { found = true }
            done.signal()
        }.resume()
        done.wait()
        if found { return port }
    }
    return nil
}

/// The token and port this bridge is currently forwarding to. Mutable and
/// long-lived on purpose — see `MCPBridge.shouldRefresh`.
final class BridgeSession {
    var token: String
    var port: UInt16
    init(token: String, port: UInt16) {
        self.token = token
        self.port = port
    }
}

// MARK: - Forwarding

/// POST to the app. Returns the HTTP status and the raw response body.
///
/// The status 500 with a nil body is this function's "the request never got
/// there" — the same marker `MCPBridge.shouldRefresh` reads to decide the port
/// needs re-probing.
func post(path: String, body: Data, session: BridgeSession) -> (status: Int, body: Data?) {
    guard let url = URL(string: "http://127.0.0.1:\(session.port)\(path)") else {
        return (500, nil)
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    // Bearer, NOT jobhunt's X-MCP-Token: NevermoreServer authenticates
    // `Authorization: Bearer <token>` and a request without it is a 401 the
    // refresh path will burn a retry on before failing.
    request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 30

    request.httpBody = body

    var status = 500
    var data: Data?
    let done = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { responseData, response, _ in
        if let http = response as? HTTPURLResponse { status = http.statusCode }
        data = responseData
        done.signal()
    }.resume()
    done.wait()
    return (status, data)
}

/// Why a forward could not be answered, in words meant for the model that asked.
struct BridgeFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// Forward one tool call, refreshing the credential and port once if the app was
/// relaunched underneath us.
func callTool(name: String, argumentsJSON: Data, session: BridgeSession)
    -> Result<String, BridgeFailure>
{
    guard let tool = MCPToolCatalog.tool(named: name) else {
        return .failure(
            BridgeFailure(
                "Unknown tool '\(name)'. Available: "
                    + MCPToolCatalog.tools.map(\.name).joined(separator: ", ")))
    }

    var (status, body) = post(path: tool.path, body: argumentsJSON, session: session)

    if MCPBridge.shouldRefresh(status: status, hasBody: body != nil) {
        if let fresh = MCPTokenManager.read() { session.token = fresh }
        if MCPBridge.refreshNeedsPortProbe(status: status), let port = discoverPort() {
            session.port = port
        }
        (status, body) = post(path: tool.path, body: argumentsJSON, session: session)
    }

    let text = body.flatMap { String(data: $0, encoding: .utf8) }
    guard status < 400 else {
        // The server's error bodies are `{"error": "..."}`; surface that
        // sentence rather than a bare status, since it is written for a reader.
        let message =
            body
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            .flatMap { $0["error"] as? String }
        return .failure(BridgeFailure(message ?? "Nevermore returned HTTP \(status)"))
    }
    return .success(text ?? #"{"ok":true}"#)
}

// MARK: - Startup

guard let startingToken = MCPTokenManager.read() else {
    fputs(
        """
        nevermore-mcp: no token at \(MCPTokenManager.tokenURL.path).
        Open Nevermore, then Settings → Local Server, and turn the local server on.
        (A token file readable by anyone but you is ignored, so check its permissions
        are 0600 if you believe it is there.)

        """, stderr)
    exit(1)
}

guard let startingPort = discoverPort() else {
    fputs(
        """
        nevermore-mcp: nothing answering on 127.0.0.1:\(ServerPortContract.firstPort)\
        -\(ServerPortContract.lastPort).
        Nevermore has to be running with its local server turned on — this bridge
        forwards to the app and holds no mail of its own.

        """, stderr)
    exit(1)
}

let session = BridgeSession(token: startingToken, port: startingPort)

func emit(_ line: String) {
    print(line)
    fflush(stdout)
}

while let line = readLine() {
    guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

    switch MCPBridge.parse(line) {
    case let .initialize(id):
        emit(MCPBridge.initializeResponse(id: id))
    case .notification:
        continue
    case let .toolsList(id):
        emit(MCPBridge.toolsListResponse(id: id))
    case let .toolsCall(id, name, argumentsJSON):
        switch callTool(name: name, argumentsJSON: argumentsJSON, session: session) {
        case let .success(text):
            emit(MCPBridge.toolResultResponse(id: id, text: text))
        case let .failure(failure):
            emit(MCPBridge.toolErrorResponse(id: id, message: failure.message))
        }
    case let .unknownMethod(id, method):
        emit(MCPBridge.errorResponse(id: id, code: -32601, message: "Method not found: \(method)"))
    case .parseError:
        emit(MCPBridge.errorResponse(id: nil, code: -32700, message: "Parse error"))
    }
}
