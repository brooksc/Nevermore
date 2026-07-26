import Foundation
import Security

/// Stores the Gmail app password in the login keychain, keyed by account address.
///
/// App-Sandbox-friendly: uses a generic password item scoped to this app's
/// service identifier. The password never touches disk in plaintext, unlike the
/// Python predecessor's `~/.config` token JSON.
public enum Keychain {
    public enum KeychainError: Error, LocalizedError {
        case unexpectedStatus(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
                return "Keychain error \(status): \(message)"
            }
        }
    }

    private static let service = "com.brooksc.nevermore.app-password"

    public static func store(appPassword: String, for account: String) throws {
        let data = Data(appPassword.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Replace rather than SecItemAdd-then-fail on duplicate.
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        // ...ThisDeviceOnly keeps the app password out of keychain migration and
        // unencrypted backups, so a full mail credential can't be restored onto
        // another machine from a Time Machine image or Migration Assistant.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    public static func appPassword(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Whether reading this account's password would make macOS show its
    /// "allow access" dialog — true only when the item exists but this build
    /// isn't on its ACL (the app was moved, re-signed with a different
    /// certificate, or restored from a backup).
    ///
    /// There's no API that asks the question directly, so this probes with user
    /// interaction disabled: a read that *would* have shown the dialog fails
    /// instead of showing it. A read that succeeds proves no dialog was needed.
    ///
    /// Measured, not assumed: a binary that isn't on the item's ACL gets
    /// `errSecAuthFailed` here, not the `errSecInteractionNotAllowed` you'd
    /// expect from the name of the flag. So anything other than "read it" or
    /// "no such item" counts as a prompt — which also means an unforeseen error
    /// fails safe, showing an unnecessary explanation rather than letting an
    /// unexplained system dialog ambush the user.
    ///
    /// `SecKeychainSetUserInteractionAllowed` is deprecated (SecKeychain as a
    /// whole is), but the ACL dialog it governs only exists for the file-based
    /// login keychain — which is exactly where this item lives — so the flag
    /// still applies. The flag is process-global; keep the window narrow.
    public static func readWouldPrompt(for account: String) -> Bool {
        SecKeychainSetUserInteractionAllowed(false)
        defer { SecKeychainSetUserInteractionAllowed(true) }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        Log.app.detail("keychain prompt probe for \(account): status \(status)")
        switch status {
        case errSecSuccess: return false  // readable without asking anyone
        case errSecItemNotFound: return false  // nothing saved — nothing to ask about
        default: return true
        }
    }

    public static func delete(for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
