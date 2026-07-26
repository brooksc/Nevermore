import Foundation

/// Typed reads of the user's Settings, with defaults matching SettingsView's
/// `@AppStorage`. Non-view code reads these at decision time.
enum AppSettings {
    static var appearance: String {
        UserDefaults.standard.string(forKey: "appearance") ?? "system"
    }
    static var askBeforeUnsubscribe: Bool {
        UserDefaults.standard.object(forKey: "askBeforeUnsubscribe") as? Bool ?? true
    }
    static var deleteIsDefault: Bool {
        UserDefaults.standard.bool(forKey: "deleteIsDefault")
    }
    static var trashConfirmThreshold: Int {
        let v = UserDefaults.standard.integer(forKey: "trashConfirmThreshold")
        return v == 0 ? 500 : v
    }
    static var syncOnLaunch: Bool {
        UserDefaults.standard.object(forKey: "syncOnLaunch") as? Bool ?? true
    }
    /// "off" | "15m" | "hourly" | "daily"
    static var backgroundInterval: String {
        UserDefaults.standard.string(forKey: "backgroundInterval") ?? "hourly"
    }
    static var backgroundIntervalSeconds: TimeInterval? {
        switch backgroundInterval {
        case "15m": 15 * 60
        case "hourly": 60 * 60
        case "daily": 24 * 60 * 60
        default: nil  // "off"
        }
    }
}
