import AppKit
import NevermoreKit

/// The one route from a sender-authored URL to the user's real browser.
///
/// The browser carries the user's cookies and sits inside their LAN, so opening
/// an unvetted `List-Unsubscribe` link there is worse than fetching it: a link
/// to `http://192.168.1.1/admin/…` becomes an authenticated request against
/// their router. `VettedURL` cannot be built without passing `DestinationGuard`,
/// and this is the only function that opens one, so a new call site has to go
/// through the check to have anything to pass.
enum ExternalBrowser {
    static func open(_ vetted: VettedURL) {
        NSWorkspace.shared.open(vetted.url)
    }
}
