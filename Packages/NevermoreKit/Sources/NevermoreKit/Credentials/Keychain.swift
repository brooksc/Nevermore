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
    /// expect from the name of the flag. Re-measured on macOS 27: still
    /// `errSecAuthFailed`. So the read status can only be trusted to say
    /// "readable" or "not readable", never why.
    ///
    /// The probe runs in two steps so that "no item" and "item I can't read"
    /// can never be confused for one another:
    ///
    /// 1. An attributes-only read. The ACL guards *decrypting the data*, not
    ///    reading attributes, so this answers "does an item exist" without any
    ///    possibility of a dialog. Measured: a binary that is not on the item's
    ///    ACL still gets `errSecSuccess` here.
    /// 2. Only if one exists, a data read with user interaction suppressed.
    ///
    /// Suppression is still `SecKeychainSetUserInteractionAllowed`, which is
    /// deprecated along with the rest of SecKeychain. There is no modern
    /// replacement for *this* dialog: the per-item keys
    /// (`kSecUseAuthenticationUI`, and `LAContext.interactionNotAllowed` behind
    /// `kSecUseAuthenticationContext`) reach only the data-protection keychain
    /// — Apple says so in SecItem.h about the same mechanism's older spelling:
    /// "on macOS, this attribute only applies to items stored in the Data
    /// Protection keychain. Legacy keychain items will still activate UI if
    /// needed." Measured here too: against an item this binary is not on the
    /// ACL of, adding `kSecUseAuthenticationUI` changes the returned status not
    /// at all. Swapping the toggle for those keys would not suppress the
    /// dialog; it would *cause* the one this function exists to predict.
    ///
    /// `kSecUseAuthenticationUISkip` is passed anyway — it is the one spelling
    /// that is not itself deprecated, it is per-item rather than process-wide,
    /// and it costs nothing (measured: inert on this item today). If the item
    /// ever moves to the data-protection keychain, it, and not the toggle, is
    /// what will do the work. Step 1 is what makes it safe to pass: `Skip`
    /// reports an unreadable item as `errSecItemNotFound`, which on its own
    /// would read as "nothing saved" and silently predict "no prompt".
    ///
    /// The toggle is process-global, so the window is kept narrow and restored
    /// on every path out.
    public static func readWouldPrompt(for account: String) -> Bool {
        withUserInteractionSuppressed {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnAttributes as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var attributes: CFTypeRef?
            let exists = SecItemCopyMatching(query as CFDictionary, &attributes)
            if exists == errSecItemNotFound { return false }  // nothing saved to ask about

            query[kSecReturnAttributes as String] = nil
            query[kSecReturnData as String] = true
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            Log.app.detail(
                "keychain prompt probe for \(account): exists \(exists), read \(status)")
            // Anything but a clean read counts as a prompt, so an unforeseen
            // error fails safe — an unnecessary explanation rather than an
            // unexplained system dialog ambushing the user.
            return status != errSecSuccess
        }
    }

    /// Runs `body` with the process-wide keychain interaction flag off, so a
    /// read that *would* put up the ACL dialog fails instead of showing it.
    ///
    /// The one call site for the deprecated API, and marked deprecated itself
    /// so the compiler stops repeating what the comment above already says. It
    /// is a direct call rather than a `dlsym` lookup on purpose: if Apple ever
    /// does remove the symbol, that should break the build here, loudly, and
    /// not turn into a dialog appearing on a user's screen.
    @available(macOS, deprecated: 10.10, message: "SecKeychain has no modern equivalent here")
    private static func withUserInteractionSuppressed(_ body: () -> Bool) -> Bool {
        SecKeychainSetUserInteractionAllowed(false)
        defer { SecKeychainSetUserInteractionAllowed(true) }
        return body()
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
