import Foundation

/// Reduces a host to its registrable domain (eTLD+1).
///
/// `email.harborfreight.com` → `harborfreight.com`, `foo.co.uk` → `foo.co.uk`.
///
/// This replaces the Python version's hand-maintained table of ~40 specific
/// companies, which didn't generalise past the senders its author happened to
/// have in his inbox.
public enum RegistrableDomain {
    /// Multi-label public suffixes. A pragmatic subset of the Public Suffix List
    /// covering the suffixes that actually appear in consumer mail.
    ///
    /// These are infrastructure facts, not per-company rules. Swapping in the
    /// full PSL is a drop-in change if it ever proves insufficient.
    static let multiLabelSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk", "ltd.uk", "plc.uk", "net.uk",
        "com.au", "net.au", "org.au", "edu.au", "gov.au", "id.au",
        "co.nz", "net.nz", "org.nz", "govt.nz",
        "co.jp", "or.jp", "ne.jp", "ac.jp", "go.jp",
        "co.kr", "or.kr", "ne.kr",
        "com.br", "net.br", "org.br", "gov.br",
        "com.cn", "net.cn", "org.cn", "gov.cn", "edu.cn",
        "co.in", "net.in", "org.in", "gen.in", "firm.in",
        "com.mx", "com.ar", "com.co", "com.pe", "com.ve", "com.tr", "com.tw",
        "com.sg", "com.hk", "com.my", "com.ph", "com.vn", "com.pk", "com.sa",
        "co.za", "org.za", "net.za",
        "co.il", "org.il", "net.il", "ac.il", "gov.il",
        "com.es", "com.pl", "com.ua", "com.ru", "org.ru", "net.ru",
        "co.id", "or.id", "web.id",
        "co.th", "in.th", "go.th",
    ]

    public static func of(_ host: String) -> String {
        let h = host.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        guard !h.isEmpty else { return "" }

        let labels = h.split(separator: ".").map(String.init)
        guard labels.count > 2 else { return h }

        let lastTwo = labels.suffix(2).joined(separator: ".")
        if multiLabelSuffixes.contains(lastTwo) {
            return labels.suffix(3).joined(separator: ".")
        }
        return lastTwo
    }
}

/// Groups messages into table rows.
public struct Grouping: Sendable {
    /// Bulk-sending platforms where the registrable domain identifies the ESP,
    /// not the brand — so every customer would otherwise collapse into one row.
    ///
    /// Unlike a brand-alias table, this list is about mail infrastructure and is
    /// short, stable, and independent of who the user happens to subscribe to.
    static let sharedSendingPlatforms: Set<String> = [
        "sendgrid.net", "sparkpostmail.com", "mailgun.org", "mcsv.net", "mcdlv.net",
        "rsgsv.net", "mailchimpapp.net", "cmail19.com", "cmail20.com", "createsend.com",
        "sendinblue.com", "brevo.com", "klaviyomail.com", "customeriomail.com",
        "postmarkapp.com", "amazonses.com", "mandrillapp.com", "hubspotemail.net",
        "substack.com", "beehiiv.com", "ghost.io", "buttondown.email", "convertkit-mail.com",
    ]

    /// Whether a registrable domain is a bulk-sending platform rather than a
    /// brand.
    ///
    /// Exposed so callers that must leave platforms alone — the domain-ignore
    /// offer, above all — can ask the type that already knows, instead of
    /// growing a second list that would drift out of step with this one.
    public func isSharedSendingPlatform(_ domain: String) -> Bool {
        Grouping.sharedSendingPlatforms.contains(domain)
    }

    /// A user correction to the automatic grouping of one registrable domain.
    public enum Rule: String, Sendable, Codable {
        /// Force this domain to split into one group per sender address
        /// (e.g. `notifications@github.com` where each message is a different person).
        case split
        /// Force this domain to stay a single group, overriding the auto-split
        /// (e.g. a brand the app split apart because its display names vary).
        case merge
    }

    /// Per-registrable-domain overrides, set by the user via Merge/Split.
    public var rules: [String: Rule]

    public init(rules: [String: Rule] = [:]) {
        self.rules = rules
    }

    public func group(_ messages: [EmailMessage]) -> [SenderGroup] {
        // Bucket by registrable domain, then decide split-vs-merge per bucket.
        var buckets: [String: [EmailMessage]] = [:]
        for m in messages {
            buckets[RegistrableDomain.of(m.sender.host), default: []].append(m)
        }

        var groups: [SenderGroup] = []
        for (domain, msgs) in buckets {
            if shouldSplit(domain: domain, messages: msgs) {
                var byAddress: [String: [EmailMessage]] = [:]
                for m in msgs { byAddress[m.sender.address, default: []].append(m) }
                for (address, group) in byAddress {
                    groups.append(
                        SenderGroup(id: GroupID(kind: .address, key: address), messages: group))
                }
            } else {
                groups.append(SenderGroup(id: GroupID(kind: .domain, key: domain), messages: msgs))
            }
        }

        return groups.sorted {
            ($0.total, $1.id.key) > ($1.total, $0.id.key)
        }
    }

    /// Whether a registrable domain's messages should split into per-address
    /// groups. A user rule wins; otherwise shared platforms and domains with
    /// several distinct display names split, and single-brand domains merge.
    func shouldSplit(domain: String, messages: [EmailMessage]) -> Bool {
        if let rule = rules[domain] { return rule == .split }
        if Grouping.sharedSendingPlatforms.contains(domain) { return true }
        // Distinct display names within one domain indicate distinct newsletters
        // sharing a platform rather than one brand sending from many addresses.
        let names = Set(messages.map(\.sender.displayName).filter { !$0.isEmpty })
        return names.count > 1
    }
}
