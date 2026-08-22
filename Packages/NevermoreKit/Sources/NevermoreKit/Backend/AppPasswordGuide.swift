import Foundation

/// What to tell the user about creating an app-specific password, per provider.
///
/// The app password is the one thing Nevermore asks for before it can do
/// anything, and every provider hides it somewhere different under a different
/// name. This is the content behind that: the provider's own console link, the
/// provider's own documentation, Nevermore's help page for it, and — only where
/// the steps were checked against the provider's current documentation — a short
/// list of steps.
///
/// `steps` is deliberately allowed to be sparse. A confidently wrong UI path is
/// worse than a link, so a provider whose flow could not be verified carries no
/// steps at all and the UI falls back to `documentationURL`.
///
/// This lives in the kit rather than the view so the wording, the URLs, and the
/// provider→guidance mapping are testable; the views only render it.
public struct AppPasswordGuide: Sendable, Hashable {
    /// The `MailProvider.id` this guides, or `"imap"` for the generic page.
    public let providerID: String
    public let displayName: String
    /// What this provider calls the credential, in its own words. Using the
    /// provider's noun is most of the battle — someone hunting for "app
    /// password" in Apple's settings finds nothing.
    public let credentialName: String
    /// Whether the provider requires two-factor auth before it will issue one.
    /// Gmail's is the step people miss: without 2-Step Verification the app
    /// password page simply isn't there.
    public let requiresTwoFactor: Bool
    /// The provider's own page for creating one, where a stable URL exists.
    /// Read from `MailProvider` so there is one place to fix when a provider
    /// moves the page.
    public var createURL: URL? { MailProvider.byID(providerID)?.appPasswordURL }
    /// The provider's own documentation. Nil for the generic guide: there is no
    /// one provider to point at, and inventing one would be a lie.
    public let documentationURL: URL?
    /// Nevermore's help page for this provider, on the support site.
    public let helpPageURL: URL
    /// Steps verified against `documentationURL`. Empty means "we did not check
    /// this flow — link, don't describe".
    public let steps: [String]
    /// A provider-specific caveat worth saying out loud, if any.
    public let caveat: String?

    public init(
        providerID: String, displayName: String, credentialName: String,
        requiresTwoFactor: Bool, documentationURL: URL?,
        helpPage: String, steps: [String], caveat: String? = nil
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.credentialName = credentialName
        self.requiresTwoFactor = requiresTwoFactor
        self.documentationURL = documentationURL
        self.helpPageURL = SupportSite.home.appendingPathComponent(helpPage)
        self.steps = steps
        self.caveat = caveat
    }

    // MARK: - Per-provider guidance

    // Steps below were checked against each provider's current documentation on
    // 2026-08-22; the URL in `documentationURL` is the one they were read from.

    public static let gmail = AppPasswordGuide(
        providerID: "gmail", displayName: "Gmail",
        credentialName: "App password",
        requiresTwoFactor: true,
        documentationURL: URL(string: "https://support.google.com/accounts/answer/185833")!,
        helpPage: "app-password-gmail.html",
        steps: [
            "Turn on 2-Step Verification for your Google Account. Google only offers app passwords once it is on — this is the step most people miss.",
            "Open the app passwords page and sign in.",
            "Give it a name you'll recognise later, such as Nevermore, and create it.",
            "Copy the 16-character password Google shows you.",
        ],
        caveat:
            "On a Google Workspace account, an administrator can switch app passwords off for the whole organisation. If the page says they're unavailable, that's why."
    )

    public static let icloud = AppPasswordGuide(
        providerID: "icloud", displayName: "iCloud Mail",
        credentialName: "App-Specific Password",
        requiresTwoFactor: true,
        documentationURL: URL(string: "https://support.apple.com/en-us/102654")!,
        helpPage: "app-password-icloud.html",
        steps: [
            "Sign in to your Apple Account at account.apple.com. Your account must have two-factor authentication turned on.",
            "In the Sign-In and Security section, select App-Specific Passwords.",
            "Select \u{201C}Generate an app-specific password\u{201D} and follow the steps on screen.",
            "Copy the password Apple shows you.",
        ],
        caveat:
            "Apple calls it an app-specific password, not an app password — that's the wording to look for."
    )

    public static let yahoo = AppPasswordGuide(
        providerID: "yahoo", displayName: "Yahoo Mail",
        credentialName: "App password",
        requiresTwoFactor: false,
        documentationURL: URL(string: "https://help.yahoo.com/kb/SLN15241.html")!,
        helpPage: "app-password-yahoo.html",
        steps: [
            "Sign in to your Yahoo Account Security page.",
            "Under External connections, choose Create app password.",
            "Follow the prompts, then copy the password Yahoo generates.",
        ],
        caveat:
            "Yahoo decides whether you're eligible to create one. Their advice is to use a browser you've been signed in to Yahoo with for a few days, and not a private window."
    )

    public static let fastmail = AppPasswordGuide(
        providerID: "fastmail", displayName: "Fastmail",
        credentialName: "App Password",
        requiresTwoFactor: false,
        documentationURL: URL(string: "https://www.fastmail.help/hc/en-us/articles/360058752854")!,
        helpPage: "app-password-fastmail.html",
        steps: [
            "In the Fastmail web app, go to Settings, then Privacy & Security.",
            "Under \u{201C}Connected apps & API tokens\u{201D}, choose Manage app passwords and access.",
            "Choose New app password and name it. Fastmail may ask for your account password first.",
            "Leave the access set to Mail, Contacts & Calendars — that covers IMAP, which is all Nevermore uses.",
            "Choose Generate password and copy the result.",
        ],
        caveat:
            "Fastmail's Basic plans don't include IMAP, so they can't create app passwords at all."
    )

    public static let aol = AppPasswordGuide(
        providerID: "aol", displayName: "AOL Mail",
        credentialName: "App password",
        requiresTwoFactor: false,
        documentationURL: URL(string: "https://help.aol.com/articles/create-and-manage-app-password")!,
        helpPage: "app-password-aol.html",
        steps: [
            "Sign in to your AOL Account Security page.",
            "Create an app password there and follow the prompts.",
            "Copy the password AOL generates.",
        ],
        caveat:
            "AOL runs the same system as Yahoo: use a browser you've been signed in to AOL with for a few days, and not a private window."
    )

    /// Custom domains and anything else that speaks IMAP. No steps — we have no
    /// idea what that provider's settings look like, and guessing would be worse
    /// than saying so.
    public static let generic = AppPasswordGuide(
        providerID: "imap", displayName: "your mail provider",
        credentialName: "app password",
        requiresTwoFactor: false,
        documentationURL: nil,
        helpPage: "app-password-imap.html",
        steps: [],
        caveat: nil
    )

    public static let all: [AppPasswordGuide] = [gmail, icloud, yahoo, fastmail, aol, generic]

    // MARK: - Lookup

    /// Guidance for a detected provider, falling back to the generic page for a
    /// provider we have nothing specific to say about.
    public static func forProvider(_ provider: MailProvider) -> AppPasswordGuide {
        all.first { $0.providerID == provider.id } ?? generic
    }

    /// Guidance for an address whose provider hasn't been picked yet. An
    /// unrecognised domain gets the generic page rather than Gmail's — the
    /// connection default guesses Gmail, but *instructions* that guess would send
    /// someone to the wrong website.
    public static func forEmail(_ email: String) -> AppPasswordGuide {
        MailProvider.detect(forEmail: email).map(forProvider) ?? generic
    }

    /// What to say when a sign-in is rejected.
    ///
    /// Providers reject the account password with the same error they use for a
    /// wrong password, so the generic "check your credentials" wording sends
    /// people to retype the thing that cannot work. Name the actual likely cause
    /// first.
    public var authFailureExplanation: String {
        let credential = credentialName.lowercased()
        if requiresTwoFactor {
            return """
                \(displayName) rejects your normal account password over IMAP — \
                it only accepts a \(credential), and only once two-factor \
                authentication is on. If you entered your account password, that's \
                the likely cause.
                """
        }
        return """
            \(displayName) rejects your normal account password over IMAP — it only \
            accepts a \(credential). If you entered your account password, that's the \
            likely cause.
            """
    }
}
