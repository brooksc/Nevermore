import Foundation

/// Tracks which Gmail accounts have been added, and where their databases live.
///
/// Deliberately tiny: the app password lives in the Keychain, the header cache
/// lives in a per-account SQLite file, and this only remembers the list and
/// which one is the default.
public struct AccountRegistry: Sendable {
    public static let shared = AccountRegistry()

    private let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = base.appendingPathComponent("MailScrub", isDirectory: true)
        }
        try? FileManager.default.createDirectory(
            at: self.directory, withIntermediateDirectories: true)
    }

    private var registryFile: URL { directory.appendingPathComponent("accounts.json") }

    public func databasePath(for account: String) -> String {
        directory.appendingPathComponent("\(account).sqlite").path
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
        Keychain.delete(for: account)
        try? FileManager.default.removeItem(atPath: databasePath(for: account))
    }
}
