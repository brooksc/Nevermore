import Foundation

/// A JSON-RPC request id, which the spec allows to be a number or a string, and
/// which must come back on the response exactly as it was sent.
public enum MCPRequestID: Sendable, Equatable {
    case number(Int)
    case string(String)

    var jsonValue: Any {
        switch self {
        case let .number(n): n
        case let .string(s): s
        }
    }

    static func from(_ raw: Any?) -> MCPRequestID? {
        switch raw {
        case let n as Int: .number(n)
        case let n as NSNumber: .number(n.intValue)
        case let s as String: .string(s)
        default: nil
        }
    }
}

/// One line of stdin, understood.
public enum MCPBridgeRequest: Sendable, Equatable {
    case initialize(id: MCPRequestID?)
    /// A notification (no `id`, no response owed) — `notifications/initialized`
    /// and friends. Answering one is a protocol error, not a harmless extra.
    case notification(method: String)
    case toolsList(id: MCPRequestID?)
    /// `arguments` is carried as raw JSON rather than decoded: the bridge holds
    /// no schema of its own and forwards what the client sent, so the server is
    /// the single place that decides what an argument means.
    case toolsCall(id: MCPRequestID?, name: String, argumentsJSON: Data)
    case unknownMethod(id: MCPRequestID?, method: String)
    case parseError
}

/// The bridge's protocol half: parsing stdin, framing responses, and deciding
/// when a failed forward is worth retrying.
///
/// Pure, and in NevermoreKit rather than in `main.swift`, because top-level code
/// in an executable is unreachable from the test harness — which is where the
/// refresh-and-retry rule has to be pinned down, since it exists to survive a
/// situation (an app relaunch mid-session) that is awkward to stage on purpose.
public enum MCPBridge {
    public static let protocolVersion = "2024-11-05"
    public static let serverName = "nevermore"

    // MARK: - Parsing

    public static func parse(_ line: String) -> MCPBridgeRequest {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let method = json["method"] as? String
        else { return .parseError }

        let id = MCPRequestID.from(json["id"])
        switch method {
        case "initialize":
            return .initialize(id: id)
        case "tools/list":
            return .toolsList(id: id)
        case "tools/call":
            let params = json["params"] as? [String: Any] ?? [:]
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let argumentsJSON = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
            return .toolsCall(id: id, name: name, argumentsJSON: argumentsJSON)
        default:
            // A method with no id is a notification: the client is telling us
            // something, not asking. JSON-RPC forbids a response.
            return id == nil ? .notification(method: method) : .unknownMethod(id: id, method: method)
        }
    }

    // MARK: - Responses

    public static func initializeResponse(id: MCPRequestID?) -> String {
        success(
            id: id,
            result: [
                "protocolVersion": protocolVersion,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": serverName, "version": AppVersion.marketing],
            ])
    }

    public static func toolsListResponse(id: MCPRequestID?) -> String {
        let tools: [[String: Any]] = MCPToolCatalog.tools.map { tool in
            var entry: [String: Any] = [
                "name": tool.name,
                "description": MCPToolCatalog.fullDescription(of: tool),
            ]
            if let data = tool.schemaJSON.data(using: .utf8),
                let schema = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                entry["inputSchema"] = schema
            } else {
                // A malformed schema is a bug in the catalog, caught by the
                // tests. Ship a permissive one rather than an unusable tool.
                entry["inputSchema"] = ["type": "object"] as [String: Any]
            }
            return entry
        }
        return success(id: id, result: ["tools": tools])
    }

    /// A successful tool call. `text` is the server's JSON response, handed to
    /// the model as text — MCP's content blocks are text, and re-encoding the
    /// JSON into a structure would only lose the field names.
    public static func toolResultResponse(id: MCPRequestID?, text: String) -> String {
        success(id: id, result: ["content": [["type": "text", "text": text]]])
    }

    /// A tool that failed. Reported as a *successful* JSON-RPC response carrying
    /// `isError`, which is what the MCP spec asks for: the call reached the
    /// server and came back with a refusal, and a protocol-level error would
    /// tell the client the transport broke instead.
    public static func toolErrorResponse(id: MCPRequestID?, message: String) -> String {
        success(
            id: id,
            result: [
                "isError": true,
                "content": [["type": "text", "text": message]],
            ])
    }

    public static func errorResponse(id: MCPRequestID?, code: Int, message: String) -> String {
        encode([
            "jsonrpc": "2.0",
            "error": ["code": code, "message": message] as [String: Any],
        ], id: id)
    }

    static func success(id: MCPRequestID?, result: [String: Any]) -> String {
        encode(["jsonrpc": "2.0", "result": result], id: id)
    }

    static func encode(_ object: [String: Any], id: MCPRequestID?) -> String {
        var payload = object
        if let id { payload["id"] = id.jsonValue }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
            let string = String(data: data, encoding: .utf8)
        else {
            return #"{"jsonrpc":"2.0","error":{"code":-32603,"message":"Could not encode response"}}"#
        }
        return string
    }

    // MARK: - Recovery

    /// Whether a failed forward should refresh the token and port and retry once.
    ///
    /// The bridge outlives the app it forwards to: an MCP client spawns it once
    /// and keeps it for the session, while Nevermore is quit and relaunched
    /// underneath. Each relaunch writes a new token — 401ing the one the bridge
    /// read at startup — and may bind a different contract port, so without this
    /// every call after the first relaunch fails until the *client* is
    /// restarted, which is not a thing a user knows to do.
    ///
    /// A 401 means the request reached a server, so only the token is stale. A
    /// 5xx with no body is this bridge's own "the connection failed" marker, and
    /// the port has to be re-probed as well. A 5xx *with* a body came from the
    /// app and is a real error — retrying it would just fail twice.
    public static func shouldRefresh(status: Int, hasBody: Bool) -> Bool {
        status == 401 || (status >= 500 && !hasBody)
    }

    /// Whether a refresh needs to re-probe the port, or only re-read the token.
    public static func refreshNeedsPortProbe(status: Int) -> Bool {
        status != 401
    }
}
