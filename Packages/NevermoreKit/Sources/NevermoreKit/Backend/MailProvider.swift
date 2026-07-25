import Foundation

/// A mail provider's IMAP/SMTP connection details, detected from the user's
/// email domain. Keeps the app provider-agnostic — the sync engine is plain
/// IMAP; only these host/port values and the app-password help link differ.
public struct MailProvider: Sendable, Hashable, Identifiable {
    public let id: String
    public let displayName: String
    public let imapHost: String
    public let imapPort: Int
    public let smtpHost: String
    public let smtpPort: Int
    /// Where the user creates an app-specific password, if the provider uses one.
    public let appPasswordURL: URL?
    /// Email domains that map to this provider.
    public let domains: [String]

    public init(
        id: String, displayName: String,
        imapHost: String, imapPort: Int = 993,
        smtpHost: String, smtpPort: Int = 587,
        appPasswordURL: URL?, domains: [String]
    ) {
        self.id = id
        self.displayName = displayName
        self.imapHost = imapHost
        self.imapPort = imapPort
        self.smtpHost = smtpHost
        self.smtpPort = smtpPort
        self.appPasswordURL = appPasswordURL
        self.domains = domains
    }

    // MARK: - Known providers (app-password friendly)

    public static let gmail = MailProvider(
        id: "gmail", displayName: "Gmail",
        imapHost: "imap.gmail.com", smtpHost: "smtp.gmail.com",
        appPasswordURL: URL(string: "https://myaccount.google.com/apppasswords"),
        domains: ["gmail.com", "googlemail.com"])

    public static let icloud = MailProvider(
        id: "icloud", displayName: "iCloud Mail",
        imapHost: "imap.mail.me.com", smtpHost: "smtp.mail.me.com",
        appPasswordURL: URL(string: "https://appleid.apple.com/account/manage"),
        domains: ["icloud.com", "me.com", "mac.com"])

    public static let yahoo = MailProvider(
        id: "yahoo", displayName: "Yahoo Mail",
        imapHost: "imap.mail.yahoo.com", smtpHost: "smtp.mail.yahoo.com",
        appPasswordURL: URL(string: "https://login.yahoo.com/account/security"),
        domains: ["yahoo.com", "ymail.com", "rocketmail.com"])

    public static let fastmail = MailProvider(
        id: "fastmail", displayName: "Fastmail",
        imapHost: "imap.fastmail.com", smtpHost: "smtp.fastmail.com",
        appPasswordURL: URL(string: "https://app.fastmail.com/settings/security/apppasswords"),
        domains: ["fastmail.com", "fastmail.fm"])

    public static let aol = MailProvider(
        id: "aol", displayName: "AOL Mail",
        imapHost: "imap.aol.com", smtpHost: "smtp.aol.com",
        appPasswordURL: URL(string: "https://login.aol.com/account/security"),
        domains: ["aol.com"])

    public static let known: [MailProvider] = [gmail, icloud, yahoo, fastmail, aol]

    /// Detect a provider from an email address's domain, or nil for an unknown
    /// domain (e.g. a custom domain — the user then picks their provider).
    public static func detect(forEmail email: String) -> MailProvider? {
        guard let domain = email.split(separator: "@").last.map({ $0.lowercased() })
        else { return nil }
        return known.first { $0.domains.contains(domain) }
    }

    /// Look up a known provider by its stable id.
    public static func byID(_ id: String) -> MailProvider? {
        known.first { $0.id == id }
    }

    /// A webmail URL for finding a sender's messages, if this provider has a
    /// known web UI. Used to open the sender in the browser (for "View in…" and
    /// as the manual-unsubscribe fallback when a newsletter has no header link).
    /// Returns a deep search link where the provider supports one, else the
    /// webmail home, else nil.
    public func webSearchURL(fromSender address: String) -> URL? {
        let encoded = address.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) ?? address
        switch id {
        case "gmail":
            return URL(string: "https://mail.google.com/mail/u/0/#search/from:\(encoded)")
        case "yahoo":
            return URL(string: "https://mail.yahoo.com/d/search/keyword=from%253A\(encoded)")
        case "fastmail":
            return URL(string: "https://app.fastmail.com/mail/search:from%3A\(encoded)")
        case "icloud":
            return URL(string: "https://www.icloud.com/mail/")
        case "aol":
            return URL(string: "https://mail.aol.com/")
        default:
            return nil
        }
    }

    /// The provider to use for an account: an explicitly-stored id wins, else the
    /// domain is auto-detected, else Gmail (the most common default).
    public static func resolved(forEmail email: String, storedID: String?) -> MailProvider {
        if let storedID, let p = byID(storedID) { return p }
        return detect(forEmail: email) ?? .gmail
    }
}
