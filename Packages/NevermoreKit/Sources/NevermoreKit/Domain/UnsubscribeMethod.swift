import Foundation

/// How a sender can be unsubscribed from, decided from headers already stored.
///
/// The point of naming this is that it is knowable *before* anything is
/// attempted: `ListUnsubscribe` has already parsed the targets and the RFC 8058
/// one-click token out of the header at sync time, so "which of these 400
/// senders will need me to open a browser" is a question about the local cache,
/// not a question you answer by trying and seeing what fails.
///
/// The order matches `UnsubscribeEngine.run`: it prefers the web target, uses a
/// one-click POST when the sender published the RFC 8058 token and a plain GET
/// otherwise, and falls back to `mailto:` only when there is no web target or
/// the web attempt failed outright.
public enum UnsubscribeMethod: String, Sendable, Hashable, CaseIterable, Codable {
    /// RFC 8058: a POST the app can make silently, and the only method the
    /// sender has promised will work without a human.
    case oneClick = "one_click"
    /// A plain `https` link. The app can fetch it, but a fetch only proves the
    /// page loaded — plenty of these are really "click the button on this page".
    case web
    /// Only a `mailto:` target. The app sends the unsubscribe email itself.
    case mailto
    /// The sender published no machine-readable target at all. Nothing can be
    /// attempted; a human has to find the preferences page in a browser.
    case none

    /// The method for a group, taken from the newest message that carries a
    /// `List-Unsubscribe` header — the same message `UnsubscribeEngine` would
    /// act on, so this cannot describe a different attempt than the one the app
    /// would make.
    public static func of(_ group: SenderGroup) -> UnsubscribeMethod {
        guard let unsubscribe = group.unsubscribeSource?.unsubscribe else { return .none }
        return of(unsubscribe)
    }

    public static func of(_ unsubscribe: ListUnsubscribe) -> UnsubscribeMethod {
        if !unsubscribe.webTargets.isEmpty {
            return unsubscribe.supportsOneClick ? .oneClick : .web
        }
        return unsubscribe.mailtoTargets.isEmpty ? .none : .mailto
    }

    /// Whether working this sender needs a human in a browser.
    ///
    /// True only for `.none`: every other method has an automated path. A sender
    /// that has already ignored one unsubscribe also needs the browser, but that
    /// is a fact about their history rather than about their headers — see
    /// `MCPSenderSummary.needsBrowser`, which combines the two.
    public var needsBrowser: Bool { self == .none }
}
