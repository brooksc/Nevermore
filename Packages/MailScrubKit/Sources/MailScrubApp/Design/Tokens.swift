import SwiftUI

/// Design tokens transcribed from `MailScrub UI.dc.html` (Claude Design).
///
/// The mockup is a fixed light-appearance canvas; here the values map onto
/// system semantic colors wherever one exists, so the real app adapts to Dark
/// Mode, increased contrast, and accent-color changes — which a hard-coded hex
/// canvas cannot. The literal hexes are kept only where the design intends a
/// specific brand tint (the accent, the unread bar).
enum Tokens {
    /// The design's `#0A7CFF`. Uses the system accent so user customization wins;
    /// `brandBlue` is the fallback for elements that must stay blue regardless.
    static let accent = Color.accentColor
    static let brandBlue = Color(red: 0x0A / 255, green: 0x7C / 255, blue: 1.0)

    /// The unread-percentage bar fill (`#88b4ee`).
    static let unreadBar = Color(red: 0x88 / 255, green: 0xB4 / 255, blue: 0xEE / 255)

    enum Metric {
        static let sidebarWidth: CGFloat = 208
        static let sidebarMin: CGFloat = 180
        static let sidebarMax: CGFloat = 280
        static let inspectorWidth: CGFloat = 280
        static let inspectorMin: CGFloat = 260
        static let inspectorMax: CGFloat = 400
        static let rowHeight: CGFloat = 44
        static let windowMinWidth: CGFloat = 900
        static let windowMinHeight: CGFloat = 560
    }
}

/// The sidebar collections.
///
/// "Unsubscribable" and "Manual only" were removed: every sender we discover is
/// found *by* its List-Unsubscribe header, so "Unsubscribable" always equalled
/// "All Senders" and "Manual only" was always empty. The remaining destinations
/// are genuinely distinct sender *states*, not filters of one list.
enum Collection: String, CaseIterable, Identifiable, Hashable {
    case allSenders
    case reappeared
    case unsubscribed, ignored

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allSenders: "All Senders"
        case .reappeared: "Reappeared"
        case .unsubscribed: "Unsubscribed"
        case .ignored: "Ignored"
        }
    }

    var systemImage: String {
        switch self {
        case .allSenders: "tray.full"
        case .reappeared: "exclamationmark.triangle"
        case .unsubscribed: "checkmark.circle"
        case .ignored: "eye.slash"
        }
    }

    enum Section: String, CaseIterable, Identifiable {
        case inbox = "INBOX", attention = "ATTENTION", archive = "ARCHIVE"
        var id: String { rawValue }
        var members: [Collection] {
            switch self {
            case .inbox: [.allSenders]
            case .attention: [.reappeared]
            case .archive: [.unsubscribed, .ignored]
            }
        }
    }
}

/// How a sender's unsubscribe target is reached — drives the row icon and the
/// inspector's plain-language explanation (design 1c, spec §5).
enum UnsubscribeMethod {
    case oneClick, webLink, email, manual

    var systemImage: String {
        switch self {
        case .oneClick: "bolt.circle.fill"
        case .webLink: "link.circle"
        case .email: "envelope.circle"
        case .manual: "hand.raised.circle"
        }
    }

    /// VoiceOver label / tooltip.
    var label: String {
        switch self {
        case .oneClick: "One-click unsubscribe available"
        case .webLink: "Unsubscribe by visiting a web page"
        case .email: "Unsubscribe by sending an email"
        case .manual: "No unsubscribe link — opens a webmail search"
        }
    }

    var inspectorTitle: String {
        switch self {
        case .oneClick: "One-click unsubscribe"
        case .webLink: "Web unsubscribe"
        case .email: "Email unsubscribe"
        case .manual: "Manual only"
        }
    }

    /// What pressing Unsubscribe will actually do — the app being honest.
    func inspectorDetail(sender: String) -> String {
        switch self {
        case .oneClick:
            "Sends a one-click request directly to \(sender). No page will open."
        case .webLink:
            "Opens \(sender)'s unsubscribe page — you may need to confirm there."
        case .email:
            "Sends an unsubscribe email to \(sender) on your behalf."
        case .manual:
            "\(sender) published no unsubscribe link. Opens their mail in your webmail."
        }
    }
}
