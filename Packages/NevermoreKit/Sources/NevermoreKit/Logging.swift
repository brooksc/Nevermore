import Foundation
import os

/// Unified logging for the whole app.
///
/// Watch live:
///   log stream --predicate 'subsystem == "com.brooksc.nevermore"' --level debug
/// Read recent history:
///   log show --predicate 'subsystem == "com.brooksc.nevermore"' --last 1h --info --debug
///
/// Messages are logged `.public` on purpose — this is a local diagnostic on the
/// user's own machine and they need to read their own logs. Sender addresses and
/// domains are logged (needed to diagnose unsubscribe issues); message subjects,
/// bodies, and the app password are never logged.
public enum Log {
    public static let subsystem = "com.brooksc.nevermore"

    public static let sync = Logger(subsystem: subsystem, category: "sync")
    public static let unsubscribe = Logger(subsystem: subsystem, category: "unsubscribe")
    public static let store = Logger(subsystem: subsystem, category: "store")
    public static let backend = Logger(subsystem: subsystem, category: "backend")
    public static let app = Logger(subsystem: subsystem, category: "app")

    /// Bound to the Settings "Verbose logging" toggle. When on, `detail(...)`
    /// logs are promoted to `.notice` so they persist and appear in Console
    /// without special flags; when off they stay `.debug` (live-stream only).
    public static var verbose: Bool { UserDefaults.standard.bool(forKey: "verboseLogging") }
}

extension Logger {
    /// A significant event — always persisted.
    public func event(_ message: String) {
        self.notice("\(message, privacy: .public)")
    }

    /// Fine-grained detail — persisted only when Verbose logging is on.
    public func detail(_ message: @autoclosure () -> String) {
        let text = message()
        if Log.verbose {
            self.notice("\(text, privacy: .public)")
        } else {
            self.debug("\(text, privacy: .public)")
        }
    }

    /// A problem — always persisted.
    public func problem(_ message: String) {
        self.error("\(message, privacy: .public)")
    }
}
