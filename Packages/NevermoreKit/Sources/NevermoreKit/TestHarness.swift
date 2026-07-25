import Foundation

/// A minimal test harness.
///
/// Exists because SwiftPM builds `.testTarget`s as `.xctest` bundles on macOS,
/// which requires XCTest from a full Xcode install — unavailable on a Command
/// Line Tools-only machine. This keeps tests runnable via `swift run`.
/// Replace with swift-testing once Xcode is a hard requirement (M5).
public enum Harness {
    nonisolated(unsafe) private static var failures: [String] = []
    nonisolated(unsafe) private static var passed = 0
    nonisolated(unsafe) private static var currentSuite = ""

    public static func suite(_ name: String, _ body: () -> Void) {
        currentSuite = name
        print("\n\u{001B}[1m\(name)\u{001B}[0m")
        body()
    }

    public static func test(_ name: String, _ body: () -> Void) {
        let before = failures.count
        body()
        if failures.count == before {
            passed += 1
            print("  \u{001B}[32m✓\u{001B}[0m \(name)")
        } else {
            print("  \u{001B}[31m✗\u{001B}[0m \(name)")
            for f in failures[before...] { print("      \(f)") }
        }
    }

    public static func expect(
        _ condition: Bool,
        _ message: @autoclosure () -> String = "expectation failed",
        line: Int = #line
    ) {
        if !condition {
            failures.append("line \(line): \(message())")
        }
    }

    public static func expectEqual<T: Equatable>(
        _ actual: T?,
        _ expected: T?,
        _ label: @autoclosure () -> String = "",
        line: Int = #line
    ) {
        if actual != expected {
            let prefix = label().isEmpty ? "" : "\(label()): "
            failures.append(
                "line \(line): \(prefix)expected \(String(describing: expected)), "
                    + "got \(String(describing: actual))"
            )
        }
    }

    /// Prints the summary and returns the process exit code.
    public static func finish() -> Int32 {
        print("\n\(passed) passed, \(failures.count) failed")
        return failures.isEmpty ? 0 : 1
    }
}
