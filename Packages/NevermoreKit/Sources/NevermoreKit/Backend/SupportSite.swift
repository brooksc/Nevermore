import Foundation

/// Every page on the published support site the app links to.
///
/// The site is served from `docs/` by GitHub Pages, which is the point: a page
/// that moves, or wording that turns out to be wrong, is fixable without
/// shipping a build. That only holds while the app links to pages rather than
/// restating them, and while there is *one* list of those links — this one.
/// `AppPasswordGuide` builds its per-provider pages from the same base.
///
/// Pages, not GitHub URLs. `PRIVACY.md` on GitHub renders fine but reads as a
/// repository to someone who has never seen one, and the issue tracker asks for
/// an account before it will take a bug report.
public enum SupportSite {
    /// The site root. Also `AppPasswordGuide`'s base for the per-provider pages.
    public static let home = URL(string: "https://brooksc.github.io/Nevermore/")!

    public static let faq = page("faq.html")
    /// The index of the per-provider app-password guides. The Help menu links
    /// this rather than one provider's page: from a menu there is no account in
    /// hand, and guessing would send someone to the wrong provider's steps.
    public static let appPasswords = page("app-passwords.html")
    public static let privacy = page("privacy.html")
    /// How to get help, and how to report a problem — an email address rather
    /// than an issue tracker.
    public static let support = page("support.html")

    /// Every page linked from the app, for tests that check they all exist.
    public static let all: [URL] = [home, faq, appPasswords, privacy, support]

    private static func page(_ name: String) -> URL { home.appendingPathComponent(name) }
}
