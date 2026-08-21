import Foundation

/// Why the listener could not be brought up.
///
/// `noPortAvailable` is the one that matters to a user: every port in `ServerPortContract` was
/// taken. It is thrown rather than swallowed, and rather than falling back to an ephemeral port,
/// so the failure can be surfaced (TASK-48) instead of the server running where no client looks.
public enum ServerError: Error, Equatable, Sendable {
    case noPortAvailable
    case listenerCancelled
    case listenerWaiting
    case listenerTimeout
}

extension ServerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noPortAvailable:
            let range = "\(ServerPortContract.firstPort)–\(ServerPortContract.lastPort)"
            return "No free local port in \(range). Another app is using all of them."
        case .listenerCancelled: return "The local server was cancelled while starting."
        case .listenerWaiting: return "The local port is temporarily unavailable."
        case .listenerTimeout: return "The local server did not start in time."
        }
    }
}

/// Stable codes returned to clients in HTTP error bodies. Never expose `localizedDescription` or
/// implementation details — the client is a third-party AI tool, not a debugger.
public enum ServerErrorCode: String, Sendable {
    case requestInvalid = "request_invalid"
    case internalError = "internal_error"
}

/// Logs the full error and returns a stable, non-leaking message suitable for an HTTP response body.
func safeServerError(_ error: Error, context: String) -> String {
    Log.app.problem("server \(context): \(error)")
    return ServerErrorCode.internalError.rawValue
}
