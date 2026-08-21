import Foundation

/// A response the server is ready to serialise.
///
/// Jobhunt's copy carries a `withCORS(origin:isPreflight:)` helper because its server is also driven
/// by a Chrome extension. Nevermore has no extension and no browser client, so there is no origin to
/// reflect — and no CORS surface for a later reader to mistake for access control. See the SECURITY
/// MODEL comment in `NevermoreServer` for why that distinction matters.
public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public var headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    public static func ok(_ value: some Encodable) -> HTTPResponse {
        do {
            let data = try JSONEncoder().encode(value)
            return HTTPResponse(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: data
            )
        } catch {
            // A serialization failure is a server error, not a successful empty response. Returning
            // 200 with "{}" makes a server bug look to the client like valid empty data.
            return .error("Response serialization failed", code: 500)
        }
    }

    public static func error(_ message: String, code: Int = 400) -> HTTPResponse {
        struct ErrorBody: Encodable { let error: String }
        let data = (try? JSONEncoder().encode(ErrorBody(error: message))) ?? Data()
        return HTTPResponse(
            statusCode: code,
            headers: ["Content-Type": "application/json"],
            body: data
        )
    }

    public static func noContent() -> HTTPResponse {
        HTTPResponse(statusCode: 204, headers: [:], body: Data())
    }

    public func toHTTPBytes() -> Data {
        let statusText = Self.statusText(for: statusCode)
        var headerLines = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
        headerLines += "Content-Length: \(body.count)\r\n"
        for (key, value) in headers {
            headerLines += "\(key): \(value)\r\n"
        }
        headerLines += "\r\n"
        var result = Data(headerLines.utf8)
        result.append(body)
        return result
    }

    /// Public so tests can assert every code the server emits maps to a real reason phrase rather
    /// than silently degrading to "Unknown".
    public static func statusText(for code: Int) -> String {
        switch code {
        case 200: "OK"
        case 201: "Created"
        case 204: "No Content"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 413: "Request Entity Too Large"
        case 431: "Request Header Fields Too Large"
        case 500: "Internal Server Error"
        case 503: "Service Unavailable"
        default: "Unknown"
        }
    }
}
