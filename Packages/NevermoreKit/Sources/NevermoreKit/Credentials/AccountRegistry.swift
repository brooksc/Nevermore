import Foundation

/// Tracks which mail accounts have been added, which provider each uses, and
/// where their databases live.
///
/// Deliberately tiny: the app password lives in the Keychain, the header cache
/// lives in a per-account SQLite file, and this only remembers the account list
/// and each account's provider id (so a custom domain's manually-chosen provider
/// survives relaunch).
public struct AccountRegistry: Sendable {
    public static let shared = AccountRegistry()

    private let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = base.appendingPathComponent("Nevermore", isDirectory: true)
        }
        try? FileManager.default.createDirectory(
            at: self.directory, withIntermediateDirectories: true)
    }

    private var registryFile: URL { directory.appendingPathComponent("accounts.json") }
    private var providersFile: URL { directory.appendingPathComponent("providers.json") }

    public func databasePath(for account: String) -> String {
        directory.appendingPathComponent("\(account).sqlite").path
    }

    /// Where the demo mailbox lives. Deliberately not an entry in `accounts()`:
    /// the demo is a mode, not an account, so it can't be switched to by
    /// accident, can't be picked up as `accounts.first` on launch, and its data
    /// can never mingle with a real mailbox's.
    public var demoDatabasePath: String {
        directory.appendingPathComponent("Demo.sqlite").path
    }

    /// Delete the demo database so the next entry into demo mode rebuilds it.
    /// Demo mode is for showing the app off; it should look the same every time.
    public func resetDemoDatabase() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: demoDatabasePath + suffix)
        }
    }

    /// Delete every account database, the demo database, and the registry
    /// itself — returning the app to its never-launched state.
    ///
    /// Keychain items are deliberately left alone: this exists so onboarding can
    /// be tested repeatedly, and dropping the saved password would mean fetching
    /// a fresh app password from the provider before each run. `Keychain.delete`
    /// is the separate, explicit way to do that.
    public func resetAllLocalData() {
        for account in accounts() {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: databasePath(for: account) + suffix)
            }
        }
        resetDemoDatabase()
        try? FileManager.default.removeItem(at: registryFile)
        try? FileManager.default.removeItem(at: providersFile)
    }

    public func accounts() -> [String] {
        guard let data = try? Data(contentsOf: registryFile),
            let list = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return list
    }

    public func add(_ account: String) {
        var list = accounts()
        guard !list.contains(account) else { return }
        list.append(account)
        try? JSONEncoder().encode(list).write(to: registryFile)
    }

    public func remove(_ account: String) {
        let list = accounts().filter { $0 != account }
        try? JSONEncoder().encode(list).write(to: registryFile)
        var map = providerMap()
        map[account] = nil
        try? JSONEncoder().encode(map).write(to: providersFile)
        Keychain.delete(for: account)
        try? FileManager.default.removeItem(atPath: databasePath(for: account))
    }

    // MARK: - Provider association

    private func providerMap() -> [String: String] {
        guard let data = try? Data(contentsOf: providersFile),
            let map = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return map
    }

    /// The provider id stored for an account, if one was recorded.
    public func providerID(for account: String) -> String? {
        providerMap()[account]
    }

    public func setProviderID(_ id: String, for account: String) {
        var map = providerMap()
        map[account] = id
        try? JSONEncoder().encode(map).write(to: providersFile)
    }
}
