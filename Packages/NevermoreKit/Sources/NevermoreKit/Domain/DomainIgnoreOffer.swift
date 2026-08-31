import Foundation

/// The offer to ignore the rest of a company when one of its addresses is
/// ignored (TASK-56).
///
/// Ignoring keys on whatever the row is, so ignoring `order-refund@costco.com`
/// says nothing about `membership@costco.com`, and the sender keeps arriving
/// under a new address. Measured against a real mailbox, that is the common
/// case rather than the exotic one: mail on `mcmap.chase.com` against an ignore
/// on `chase.com`, on `info11.citi.com` against `citi.com`, three separate
/// `costco.com` addresses.
///
/// The answer is an offer, not a second menu item. "Ignore this domain" sitting
/// permanently beside "Ignore" is one mis-click from silencing `gmail.com`, and
/// the damage is invisible — mail simply stops appearing. So the app asks, once,
/// naming the domain and the count, at the moment the user has already decided
/// they want less from this sender. Same posture as the Proposed collection:
/// propose, never assume.
///
/// Nothing here ignores anything. It is the rule for *which* senders the
/// question would cover plus the wording of the question, so both can be tested
/// without a window.
public struct DomainIgnoreOffer: Sendable, Equatable {
    /// The registrable domain the offer would widen to.
    public let domain: String
    /// The other senders on that domain, none of them already ignored.
    public let targets: [GroupID]

    public var count: Int { targets.count }

    /// Whether widening one address ignore to `domain` is a question worth
    /// asking at all.
    ///
    /// The single exclusion that matters is the shared sending platforms, and it
    /// reads `Grouping`'s own list rather than keeping a second one: every
    /// Substack is deliberately its own row, so ignoring one newsletter must
    /// never offer to silence the rest. A domain split into rows because its
    /// display names differ — which is what `costco.com` and `chase.com` are —
    /// is not a platform and is exactly the case this exists for.
    static func isOfferable(domain: String, grouping: Grouping) -> Bool {
        !domain.isEmpty && !grouping.isSharedSendingPlatform(domain)
    }

    /// The offer to make after `ignored` was ignored, or nil when there is none.
    ///
    /// Nil, deliberately, when:
    /// - `ignored` is a domain group — that ignore already covers the domain;
    /// - the domain is a shared sending platform;
    /// - the user has already declined this domain (`declinedDomains`);
    /// - nothing else is left on the domain to ignore.
    ///
    /// One remaining sender still counts. Most of the leaks measured in the real
    /// mailbox were a single sibling host, so a threshold of two would have
    /// suppressed the offer in the clearest case there was.
    public init?(
        after ignored: GroupID,
        groups: [SenderGroup],
        ignoredKeys: Set<String>,
        grouping: Grouping,
        declinedDomains: Set<String>
    ) {
        guard ignored.kind == .address else { return nil }
        let domain = ignored.registrableDomain
        guard Self.isOfferable(domain: domain, grouping: grouping),
            !declinedDomains.contains(domain)
        else { return nil }

        let targets =
            groups
            .map(\.id)
            .filter {
                $0 != ignored && $0.registrableDomain == domain
                    && !ignoredKeys.contains($0.storageKey)
            }
            .sorted { $0.key < $1.key }
        guard !targets.isEmpty else { return nil }

        self.domain = domain
        self.targets = targets
    }

    /// What the offer says. The count and the domain are both in it: an offer to
    /// widen an ignore that does not say how far it widens is not a question.
    public var question: String {
        "Also ignore the other \(count) sender\(count == 1 ? "" : "s") at \(domain)?"
    }

    /// The status-bar button, which has to carry the whole question itself.
    public var actionLabel: String {
        "Also Ignore \(count.formatted()) at \(domain)"
    }
}
