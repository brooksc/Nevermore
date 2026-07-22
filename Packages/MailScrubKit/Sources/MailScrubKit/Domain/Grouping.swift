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

    /// User-defined overrides mapping a host to an explicit group key.
    public var overrides: [String: String]

    public init(overrides: [String: String] = [:]) {
        self.overrides = overrides
    }

    public func group(_ messages: [EmailMessage]) -> [SenderGroup] {
        // Bucket by the key that would merge senders together.
        var buckets: [GroupID: [EmailMessage]] = [:]
        for m in messages {
            buckets[mergeKey(for: m), default: []].append(m)
        }

        var groups: [SenderGroup] = []
        for (id, msgs) in buckets {
            // Distinct display names within one domain indicate distinct
            // newsletters sharing a platform (Substack) rather than one brand
            // sending from many addresses (Amazon).
            let names = Set(msgs.map(\.sender.displayName).filter { !$0.isEmpty })
            if names.count > 1 {
                var byAddress: [String: [EmailMessage]] = [:]
                for m in msgs { byAddress[m.sender.address, default: []].append(m) }
                for (address, group) in byAddress {
                    groups.append(
                        SenderGroup(id: GroupID(kind: .address, key: address), messages: group)
                    )
                }
            } else {
                groups.append(SenderGroup(id: id, messages: msgs))
            }
        }

        return groups.sorted {
            ($0.total, $1.id.key) > ($1.total, $0.id.key)
        }
    }

    /// The key that decides which messages are *candidates* to merge.
    ///
    /// Returns a full ``GroupID`` rather than a bare string so the kind travels
    /// with the key: on a shared platform the key is an address, and labelling
    /// that `.domain` reintroduces exactly the ambiguity ``GroupID`` removes.
    func mergeKey(for message: EmailMessage) -> GroupID {
        let host = message.sender.host
        if let override = overrides[host] {
            return GroupID(kind: .domain, key: override)
        }

        let registrable = RegistrableDomain.of(host)
        // On a shared platform the domain identifies the ESP, not the sender,
        // so key on the address instead.
        if Grouping.sharedSendingPlatforms.contains(registrable) {
            return GroupID(kind: .address, key: message.sender.address)
        }
        return GroupID(kind: .domain, key: registrable)
    }
}
