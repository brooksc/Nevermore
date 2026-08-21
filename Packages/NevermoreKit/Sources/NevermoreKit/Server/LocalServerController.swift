import Foundation

/// What the local server is doing, in the terms Settings has to show.
///
/// `failed` carries a ready-to-display message rather than the error: the whole point of TASK-48 is
/// that a bind failure reaches the user, and `ServerError.noPortAvailable` only names the port range
/// through `localizedDescription`.
public enum LocalServerStatus: Equatable, Sendable {
    case off
    case starting
    case running(port: UInt16)
    case failed(message: String)

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

/// Owns the local server's lifecycle: the token exists exactly as long as the listener does.
///
/// `NevermoreServer` takes its MCP token at init and never mutates it, so "start" means generate a
/// fresh token and build a server around it, and "stop" means cancel the listener and remove the
/// token file. Keeping both halves here is what makes that pairing hard to get wrong — TASK-42 built
/// the two pieces and nothing joined them, so the server never actually ran.
///
/// An actor rather than a `@MainActor` observable object: the UI wants a value it can render, and
/// `start`/`stop` return the resulting status for the caller to publish. That keeps the waiting on
/// `NWListener` off the main actor and keeps this testable without a UI.
public actor LocalServerController {
    private var server: NevermoreServer?
    private let tokenURL: URL
    private let appVersion: String
    /// The open account the MCP routes serve. Held here as well as on the server because the two
    /// change independently: the user can switch accounts while the server is off, and the server
    /// can be restarted (demo mode) while the account stays put. Whichever happens second has to
    /// find the other already recorded.
    private var mcpContext: MCPContext?

    public private(set) var status: LocalServerStatus = .off

    public init(
        tokenURL: URL = MCPTokenManager.tokenURL,
        appVersion: String = AppVersion.marketing
    ) {
        self.tokenURL = tokenURL
        self.appVersion = appVersion
    }

    /// The path an MCP client needs to read its credential from, shown in Settings so nobody has to
    /// know it by heart. Available whether or not the server is running.
    public nonisolated var tokenPath: String { tokenURL.path }

    /// Write a token, bind a contract port, and report what happened.
    ///
    /// Every failure path leaves nothing behind: no listener, and no token file that would outlive
    /// the server it authenticates for.
    @discardableResult
    public func start(isDemo: Bool) async -> LocalServerStatus {
        if let server, await server.isListening {
            status = .running(port: await server.listeningPort)
            return status
        }
        status = .starting
        do {
            let token = try MCPTokenManager.generateAndWrite(at: tokenURL)
            let fresh = NevermoreServer(appVersion: appVersion, isDemo: isDemo, mcpToken: token)
            await fresh.setMCPContext(mcpContext)
            server = fresh
            try await fresh.start()
            status = .running(port: await fresh.listeningPort)
        } catch {
            await server?.stop()
            server = nil
            MCPTokenManager.delete(at: tokenURL)
            status = .failed(message: error.localizedDescription)
            Log.app.problem("local server did not start: \(error.localizedDescription)")
        }
        return status
    }

    /// Release the port and remove the token file. Safe to call when already off.
    @discardableResult
    public func stop() async -> LocalServerStatus {
        await server?.stop()
        server = nil
        MCPTokenManager.delete(at: tokenURL)
        status = .off
        return status
    }

    /// Record which account the MCP routes serve, and tell a running server about it.
    ///
    /// Nil when no account is open. Called on every account change, not only at launch: the MCP
    /// surface is defined as "the account currently open", and a server still pointing at the
    /// previous account's store would answer questions about a mailbox the user has left — while
    /// naming the new one in every response.
    public func setMCPContext(_ context: MCPContext?) async {
        mcpContext = context
        await server?.setMCPContext(context)
    }

    /// Stop and start again, so a running server picks up a changed `isDemo` — otherwise
    /// `/api/ping` keeps reporting the mode the app was in when the server came up.
    @discardableResult
    public func restartIfRunning(isDemo: Bool) async -> LocalServerStatus {
        guard status.isRunning else { return status }
        await stop()
        return await start(isDemo: isDemo)
    }

    /// Remove the token file without awaiting anything, for `NSApplication` termination — the
    /// process is going away, so the OS releases the port regardless, but the credential on disk
    /// would outlive it.
    public nonisolated func deleteTokenFile() {
        MCPTokenManager.delete(at: tokenURL)
    }
}
