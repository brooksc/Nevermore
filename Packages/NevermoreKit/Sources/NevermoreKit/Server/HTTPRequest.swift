import Foundation

/// A parsed HTTP request. `public` because the test harness is a separate executable target and
/// cannot see internal declarations — the same reason every other testable type in this package is.
public struct HTTPRequest: Sendable {
    public let method: String
    public let path: String
    public let queryItems: [URLQueryItem]
    /// Header names are lowercased on parse, so lookups never depend on the sender's casing.
    public let headers: [String: String]
    public let body: Data?

    public init(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
    }

    public func queryValue(for name: String) -> String? {
        queryItems.first { $0.name == name }?.value
    }

    public func decodeBody<T: Decodable>(as type: T.Type) throws -> T {
        guard let data = body else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Empty body")
            )
        }
        return try JSONDecoder().decode(type, from: data)
    }
}

/// Outcome of inspecting a (possibly partial) request's header block for framing validity, without
/// waiting for the body. Lets the parser fail closed on an oversized or malformed local client.
public enum RequestFraming: Equatable, Sendable {
    /// Header terminator not seen yet and the buffer is still within the header cap — read more.
    case incomplete
    /// Reject now with this status (e.g. 431 oversized headers, 400 bad framing).
    case invalid(reason: String, statusCode: Int)
    /// Headers parsed and framing is valid; body (if any) is `contentLength` bytes.
    case valid(method: String, path: String, contentLength: Int)
}

/// Inspect the request's header block once it's complete (or detect it's oversized / malformed)
/// WITHOUT waiting for the body. Enforces a header-block size cap and strict Content-Length rules
/// (no malformed/negative/conflicting values; body-bearing methods must declare a length) so the
/// server frames requests deterministically before routing.
public func inspectRequestFraming(_ data: Data, maxHeaderBytes: Int) -> RequestFraming {
    let sepBytes = Data([13, 10, 13, 10]) // \r\n\r\n
    guard let sepRange = data.range(of: sepBytes) else {
        // No complete header block yet. If we've buffered more than the cap without a terminator,
        // the headers are oversized — reject instead of accumulating to the hard body cap.
        if data.count > maxHeaderBytes {
            return .invalid(reason: "Request header fields too large", statusCode: 431)
        }
        return .incomplete
    }

    let headerByteCount = data.distance(from: data.startIndex, to: sepRange.lowerBound)
    if headerByteCount > maxHeaderBytes {
        return .invalid(reason: "Request header fields too large", statusCode: 431)
    }
    guard let headerString = String(data: data[data.startIndex ..< sepRange.lowerBound], encoding: .ascii) else {
        return .invalid(reason: "Malformed request headers", statusCode: 400)
    }
    var lines = headerString.components(separatedBy: "\r\n")
    guard !lines.isEmpty else { return .invalid(reason: "Malformed request line", statusCode: 400) }
    let requestLine = lines.removeFirst()
    let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
    guard parts.count >= 2 else { return .invalid(reason: "Malformed request line", statusCode: 400) }
    let method = parts[0].uppercased()
    let rawTarget = parts[1]
    let path = rawTarget.firstIndex(of: "?").map { String(rawTarget[rawTarget.startIndex ..< $0]) } ?? rawTarget

    // Collect every Content-Length value so duplicates/conflicts can be detected.
    var contentLengthValues: [String] = []
    for line in lines {
        guard let colonIdx = line.firstIndex(of: ":") else { continue }
        let key = String(line[line.startIndex ..< colonIdx]).trimmingCharacters(in: .whitespaces).lowercased()
        if key == "content-length" {
            contentLengthValues.append(
                String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            )
        }
    }
    if Set(contentLengthValues).count > 1 {
        return .invalid(reason: "Conflicting Content-Length headers", statusCode: 400)
    }

    var contentLength = 0
    if let raw = contentLengthValues.first {
        guard let parsed = Int(raw), parsed >= 0 else {
            return .invalid(reason: "Malformed Content-Length", statusCode: 400)
        }
        contentLength = parsed
    } else if method == "POST" || method == "PUT" || method == "PATCH" {
        // A body-bearing method with no length is unframable — reject rather than treat as empty.
        return .invalid(reason: "Missing Content-Length on \(method)", statusCode: 400)
    }

    return .valid(method: method, path: path, contentLength: contentLength)
}

/// Parse raw HTTP request bytes into an `HTTPRequest`.
/// Returns nil if the request is malformed or incomplete.
/// The body is sliced from the original `Data` using Content-Length as a byte count, so non-ASCII
/// (e.g. UTF-8 multi-byte) JSON bodies are never truncated.
public func parseHTTPRequest(_ data: Data) -> HTTPRequest? {
    // Locate the header/body separator as raw bytes — never convert the body to String first.
    let sepBytes = Data([13, 10, 13, 10]) // \r\n\r\n
    guard let sepRange = data.range(of: sepBytes) else { return nil }

    // HTTP headers are always ASCII; body encoding is determined by Content-Type.
    guard let headerString = String(data: data[data.startIndex ..< sepRange.lowerBound], encoding: .ascii)
    else { return nil }

    var lines = headerString.components(separatedBy: "\r\n")
    guard !lines.isEmpty else { return nil }

    let requestLine = lines.removeFirst()
    let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
    guard parts.count >= 2 else { return nil }

    let method = parts[0]
    let rawTarget = parts[1]

    var path = rawTarget
    var queryItems: [URLQueryItem] = []
    if let qIdx = rawTarget.firstIndex(of: "?") {
        path = String(rawTarget[rawTarget.startIndex ..< qIdx])
        let queryString = String(rawTarget[rawTarget.index(after: qIdx)...])
        let components = URLComponents(string: "http://x?\(queryString)")
        queryItems = components?.queryItems ?? []
    }

    var headers: [String: String] = [:]
    for line in lines {
        if let colonIdx = line.firstIndex(of: ":") {
            let key = String(line[line.startIndex ..< colonIdx]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
    }

    // Slice the body from raw Data using Content-Length as a byte count (not a character count).
    // Return nil if the body bytes haven't all arrived yet — the caller should read more.
    var bodyData: Data?
    let bodyStart = sepRange.upperBound
    if let contentLengthStr = headers["content-length"],
       let contentLength = Int(contentLengthStr),
       contentLength > 0 {
        let bodyBytesAvailable = bodyStart <= data.endIndex ? (data.endIndex - bodyStart) : 0
        guard bodyBytesAvailable >= contentLength else { return nil }
        bodyData = Data(data[bodyStart...].prefix(contentLength))
    }

    return HTTPRequest(method: method, path: path, queryItems: queryItems, headers: headers, body: bodyData)
}
