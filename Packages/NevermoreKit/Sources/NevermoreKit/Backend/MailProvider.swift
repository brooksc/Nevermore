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
    /// Deep link to one specific message in the provider's web UI.
    ///
    /// Gmail's own URLs (`#inbox/FMfcgz…`) use an internal thread id that IMAP
    /// never exposes, so those can't be reconstructed. `rfc822msgid:` is
    /// Gmail's documented search operator for the RFC 5322 `Message-ID`, which
    /// *is* fetched and stored — searching it resolves to the single message.
    ///
    /// Returns nil for providers with no documented per-message link; the
    /// caller falls back to a sender search rather than guessing at a URL
    /// scheme that would just 404.
    /// Base Gmail URL that opens *the right account*.
    ///
    /// `/mail/u/<n>/` selects among signed-in Google accounts by index, so a
    /// hardcoded `/u/0/` silently opens whichever Google account was signed
    /// into first — the wrong mailbox for anyone with more than one.
    ///
    /// Measured, not assumed: `/mail/u/<email>/` returns Gmail's "Temporary
    /// Error" page, but `/mail/?authuser=<email>` resolves and redirects to the
    /// correct `/u/<n>/`, preserving the fragment. So use `authuser`.
    static func gmailBase(_ account: String?) -> String {
        guard let account, account.contains("@"),
            let encoded = account.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed)
        else { return "https://mail.google.com/mail/u/0/" }
        return "https://mail.google.com/mail/?authuser=\(encoded)"
    }

    /// Direct link to a Gmail *conversation*, from Gmail's internal thread id.
    ///
    /// Gmail's web UI addresses threads by the lowercase hex of the decimal
    /// `X-GM-THRID` it returns over IMAP. This opens the conversation itself
    /// rather than a search result the user then has to click.
    ///
    /// The `#all/` fragment is an undocumented web-UI convention — stable for
    /// years, but not a promise — so callers keep the `rfc822msgid:` search as
    /// a fallback.
    public func webThreadURL(threadID: UInt64, account: String? = nil) -> URL? {
        guard id == "gmail", threadID != 0 else { return nil }
        return URL(string: "\(Self.gmailBase(account))#all/\(String(threadID, radix: 16))")
    }

    public func webMessageURL(messageId rawID: String, account: String? = nil) -> URL? {
        let messageID = rawID.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
        guard !messageID.isEmpty else { return nil }
        // Message-IDs legitimately contain +, /, ?, and & — encode everything
        // outside the RFC 3986 unreserved set so none of it is read as syntax.
        let unreserved = CharacterSet(
            charactersIn:
                "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let encoded = messageID.addingPercentEncoding(withAllowedCharacters: unreserved)
        else { return nil }

        switch id {
        case "gmail":
            return URL(
                string: "\(Self.gmailBase(account))#search/rfc822msgid:\(encoded)")
        default:
            return nil
        }
    }

    public func webSearchURL(fromSender address: String, account: String? = nil) -> URL? {
        let encoded = address.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) ?? address
        switch id {
        case "gmail":
            return URL(string: "\(Self.gmailBase(account))#search/from:\(encoded)")
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
