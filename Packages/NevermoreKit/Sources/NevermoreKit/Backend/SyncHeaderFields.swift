import Foundation

/// Header fields the sync asks IMAP for beyond the fixed set, and the switches
/// that decide whether it asks.
///
/// This exists so TASK-30 can ship the parsing, the storage and the verdict for
/// `Authentication-Results` without anybody having to guess at what fetching it
/// costs. Discovery on a real 12,000-message mailbox already takes about 95
/// seconds, 40 of it in the header fetch (TASK-36), and every added field is
/// paid for on every message. Nobody here has a mailbox that size to measure
/// against, and asserting a cost that was never measured is worse than leaving
/// the switch off.
///
/// So: everything downstream of the fetch is built and tested, and turning it on
/// is this one Boolean. TASK-36 measures, and flips it or does not.
public enum SyncHeaderFields {
    /// RFC 8601, written by the receiving provider.
    public static let authenticationResults = "Authentication-Results"

    /// Whether the sync asks for `Authentication-Results`.
    ///
    /// **Off, and not because it is unwanted.** It is the one signal that can
    /// tell a sender who is who they claim to be from one who is not, and
    /// TASK-30's whole point rests on it. It stays off until TASK-36 reports
    /// what the extra bytes cost per message on a real mailbox. Everything else
    /// in TASK-30 — the parser, the column, the verdict, the copy — works the
    /// moment this is `true`, and the checks that need no new fetch (where the
    /// unsubscribe link actually goes) are live regardless.
    public static let fetchesAuthenticationResults = false

    /// The extra fields the fetch should ask for, given the switches above.
    public static var optional: [String] {
        fetchesAuthenticationResults ? [authenticationResults] : []
    }
}
