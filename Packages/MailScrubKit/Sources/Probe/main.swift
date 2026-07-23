import Foundation
import MailScrubKit

// CLI harness for verifying M1/M2 against a real mailbox without a UI.
//
//   MAILSCRUB_EMAIL=you@gmail.com MAILSCRUB_APP_PASSWORD=xxxx \
//     swift run mailscrub-probe [--full]

// Diagnostic: open the app's real Application Support DB and report what
// AppModel would see, without any network. `mailscrub-probe --count-appdb <email>`
if CommandLine.arguments.contains("--count-appdb") {
    guard let email = CommandLine.arguments.last, email.contains("@") else {
        print("usage: mailscrub-probe --count-appdb <email>")
        exit(2)
    }
    let path = AccountRegistry.shared.databasePath(for: email)
    print("app-support DB: \(path)")
    let store = try MessageStore(path: path)
    let all = try store.allMessages()
    print("store.count(): \(try store.count())")
    print("allMessages(): \(all.count)")
    print("ignoredGroupKeys: \(try store.ignoredGroupKeys().count)")
    print("history: \(try store.unsubscribeHistory().count)")
    let groups = Grouping().group(all)
    print("grouped: \(groups.count) senders")
    exit(0)
}

let env = ProcessInfo.processInfo.environment
guard let address = env["MAILSCRUB_EMAIL"], let password = env["MAILSCRUB_APP_PASSWORD"] else {
    print("Set MAILSCRUB_EMAIL and MAILSCRUB_APP_PASSWORD.")
    exit(2)
}
let forceFull = CommandLine.arguments.contains("--full")

let dbPath = NSString(string: "~/.config/mailscrub-mac/\(address).sqlite").expandingTildeInPath
try FileManager.default.createDirectory(
    atPath: (dbPath as NSString).deletingLastPathComponent,
    withIntermediateDirectories: true
)

// Line-buffer stdout: piped output is block-buffered by default, so a crash
// discards everything written so far and makes failures look like they happened
// before any work started.
setvbuf(stdout, nil, _IOLBF, 0)

@Sendable func stamp(_ s: String) {
    let t = Date().formatted(date: .omitted, time: .standard)
    print("\u{001B}[2m[\(t)]\u{001B}[0m \(s)")
    fflush(stdout)
}

/// Run a step, reporting which one failed instead of aborting anonymously.
func step<T>(_ name: String, _ body: () async throws -> T) async -> T? {
    do {
        return try await body()
    } catch {
        stamp("\u{001B}[31mFAILED\u{001B}[0m during \(name): \(error)")
        return nil
    }
}

let store = try MessageStore(path: dbPath)
let backend = IMAPBackend(address: address, appPassword: password)

stamp("store: \(dbPath)")
stamp("already stored: \(try store.count()) messages")

let existingToken = forceFull ? nil : try store.syncToken()
stamp(existingToken == nil ? "running full discovery…" : "running incremental sync…")

@Sendable func report(_ phase: SyncPhase) {
    switch phase {
    case .discovering(let window, let total, let found):
        stamp("  searching window \(window)/\(total) — \(found) found so far")
    case .fetching(let done, let total):
        if done % 2000 == 0 || done == total {
            stamp("  fetched \(done)/\(total)")
        }
    }
}

let started = Date()
let synced = await step("sync") {
    try await backend.changes(since: existingToken, progress: report)
}
guard let (messages, token) = synced else { exit(1) }
let elapsed = Date().timeIntervalSince(started)

try store.upsert(messages)
try store.setSyncToken(token)

stamp("fetched \(messages.count) messages in \(String(format: "%.1f", elapsed))s")
stamp("token: uidValidity=\(token.uidValidity) highestUID=\(token.highestUID)")
stamp("stored total: \(try store.count())")

// Group them the way the UI will, and show the top senders.
let all = try store.allMessages()
let groups = Grouping().group(all)

let oneClick = all.filter { $0.unsubscribe?.supportsOneClick == true }.count
let withAlias = all.filter { !$0.deliveredTo.isEmpty && $0.deliveredTo != address }.count
let pct = all.isEmpty ? 0 : oneClick * 100 / all.count

print("")
stamp("\(all.count) messages across \(groups.count) senders")
stamp("  RFC 8058 one-click available: \(oneClick) (\(pct)%)")
stamp("  delivered to a non-primary address: \(withAlias)")

let aliases = await step("sendAsAddresses") { try await backend.sendAsAddresses() } ?? []
stamp("send-as addresses: \(aliases.joined(separator: ", "))")

print("\n\u{001B}[1mTop 25 senders\u{001B}[0m")
for g in groups.prefix(25) {
    let flag = g.canUnsubscribe ? "" : "  \u{001B}[33m(no unsubscribe target)\u{001B}[0m"
    let name = g.displayName.count > 42 ? String(g.displayName.prefix(41)) + "…" : g.displayName
    let padded = name.padding(toLength: 44, withPad: " ", startingAt: 0)
    print("  \(String(format: "%5d", g.total))  \(padded)\(g.id.key)\(flag)")
}

await backend.disconnect()
