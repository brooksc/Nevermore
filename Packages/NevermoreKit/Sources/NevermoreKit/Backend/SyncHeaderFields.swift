import Foundation
import SwiftMail

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

    /// The per-message attributes the sync requests, beside the header fields.
    ///
    /// Named here rather than written inline at the call site so the one thing
    /// that decides TASK-29's cost is stated in one place and can be asserted
    /// against.
    ///
    /// **`RFC822.SIZE` is not one of the switches above, and deliberately not.**
    ///
    /// TASK-29 shows what senders cost in storage, and the obvious worry is that
    /// it repeats TASK-30's problem: another field on every message, at a price
    /// only TASK-36 can measure on a mailbox nobody here has. It does not, and
    /// the reason is structural rather than a judgement about what is
    /// affordable.
    ///
    /// `attributes` is `.slim`, which SwiftMail defines as
    /// `[.envelope, .internalDate, .flags, .size]`. `.size` *is* `RFC822.SIZE`.
    /// The sync has been asking the server for it, and SwiftMail has been
    /// parsing it into `MessageInfo.size`, since before TASK-29 existed —
    /// `IMAPBackend.convert` simply threw the value away. Reading it changes no
    /// FETCH command, adds no header field, and moves no extra bytes: the
    /// request is identical before and after, which is a fact about the code
    /// rather than a measurement, and `SyncHeaderFieldsSuite` asserts it.
    ///
    /// So there is nothing here for TASK-36 to price. What TASK-29 *does* cost
    /// is a nullable column and a backfill gap: messages stored before the value
    /// was kept have no size until they are fetched again, and incremental sync
    /// only re-reads a two-day overlap. That gap is visible in the UI as
    /// "Unknown" rather than papered over — see `SenderStorage`.
    public static let attributes: FetchMessageInfoOptions = .slim
}
