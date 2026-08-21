import Foundation

/// Manages the MCP authentication token at `~/.nevermore-mcp-token`.
///
/// The app generates a fresh token on each launch and deletes it on normal shutdown, so the
/// credential is transient and does not outlive the running server. The MCP bridge reads it to
/// authenticate its requests to the loopback HTTP server.
///
/// A file on disk is the only channel available: the bridge is a separate process started by a
/// third-party AI client, so it cannot be handed the token in memory. The 0600 policy is what keeps
/// that file from being a shared secret — see `read(at:)`.
public enum MCPTokenManager {
    public static let tokenURL = URL.homeDirectory.appending(path: ".nevermore-mcp-token")

    // MARK: - Public API (operates on the real ~/.nevermore-mcp-token)

    /// Generate a fresh UUID token, write it 0600, and return it. Throws if the file cannot be
    /// written or the permissions cannot be set — callers must not start MCP routes if this fails
    /// (a partial or over-permissive file is removed before throwing).
    @discardableResult
    public static func generateAndWrite() throws -> String {
        try generateAndWrite(at: tokenURL)
    }

    /// Read the current token. Returns nil if the file is missing, unreadable, or has permissions
    /// broader than 0600 (e.g. group- or world-readable).
    public static func read() -> String? {
        read(at: tokenURL)
    }

    /// Remove the token file (on normal shutdown, logout, or uninstall).
    public static func delete() {
        delete(at: tokenURL)
    }

    // MARK: - Shared URL-seam implementation

    // Operate on an explicit URL so the lifecycle can be unit-tested without touching the user's
    // real home directory, and so the MCP bridge (TASK-44) can share this exact path + permission
    // policy rather than duplicating it and drifting.

    @discardableResult
    public static func generateAndWrite(at url: URL) throws -> String {
        let token = UUID().uuidString
        do {
            // Write atomically, then lock down permissions immediately.
            try token.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // Don't leave a partial or over-permissive token file behind on failure.
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        return token
    }

    public static func read(at url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let perms = attrs[.posixPermissions] as? Int,
              perms & 0o077 == 0 else {
            // File missing, or permissions broad enough that another account could have read the
            // token — refuse to use it rather than authenticate against a secret that leaked.
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func delete(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
