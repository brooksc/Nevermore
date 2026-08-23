import Foundation

/// Reasons Nevermore has, from the mail itself, for not asking a sender to stop
/// (TASK-30).
///
/// Unsubscribing is the one thing this app does that cannot be undone and that a
/// stranger finds out about: the request proves the address is live and that a
/// person read the message. For a real newsletter that is a fair trade. For cold
/// outreach or a list broker it is the confirmation they were fishing for, and
/// the right answer is to say nothing and hide the sender instead.
///
/// Everything here is designed around one failure mode: **a warning that fires on
/// ordinary mail is worse than no warning at all**, because it teaches people to
/// click through the one that matters. So findings come in two weights, and only
/// the strong ones are allowed to change what the app recommends. Anything that
/// is merely unusual — and an unsubscribe link on a different domain is merely
/// unusual, it is how every bulk-mail provider works — is shown as context in the
/// inspector and changes nothing.
public struct TrustFinding: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        /// The delivering provider's SPF/DKIM/DMARC verdicts came back failing.
        case authenticationFailed
        /// The unsubscribe link goes through a URL shortener.
        case shortenedUnsubscribeTarget
        /// The unsubscribe link points at a bare IP address.
        case bareAddressUnsubscribeTarget
        /// The unsubscribe mailto: goes to a free consumer mailbox.
        case consumerMailboxUnsubscribeTarget
        /// The unsubscribe target is on a registrable domain unrelated to the
        /// sender's, and not one of the bulk-mail platforms this app knows.
        case unrelatedUnsubscribeTarget
    }

    /// How much a finding is allowed to do.
    public enum Weight: Sendable, Hashable {
        /// Shown, explained, and nothing more.
        case advisory
        /// Also turns the recommended action away from unsubscribing.
        case strong
    }

    public let kind: Kind
    public let weight: Weight
    /// The heading, in the inspector.
    public let title: String
    /// The explanation. Always says whose finding it is and what it does not
    /// cover — this is second-hand evidence and pretending otherwise is the
    /// quickest way to make it worth less than nothing.
    public let detail: String

    public var id: Kind { kind }

    public init(kind: Kind, weight: Weight, title: String, detail: String) {
        self.kind = kind
        self.weight = weight
        self.title = title
        self.detail = detail
    }
}

/// What the app's own reading of a sender's headers amounts to.
public struct SenderTrustVerdict: Sendable, Hashable {
    public let findings: [TrustFinding]

    public init(findings: [TrustFinding] = []) {
        self.findings = findings
    }

    public static let none = SenderTrustVerdict()

    public var isEmpty: Bool { findings.isEmpty }

    /// True when something here is solid enough to argue against unsubscribing.
    public var advisesAgainstUnsubscribing: Bool {
        findings.contains { $0.weight == .strong }
    }

    /// What the app recommends instead, or nil when it has nothing to say.
    ///
    /// `.ignore` and not `.trash`, though the task asks for both: ignoring is
    /// the part that follows from the evidence — say nothing to this sender —
    /// while trashing is a separate judgement about whether the mail already in
    /// the mailbox is worth keeping, which no header can answer. The copy names
    /// Trash as the other half, and the button is right there.
    public var recommendedAction: RecommendedAction? {
        advisesAgainstUnsubscribing ? .ignore : nil
    }

    /// The one strong finding to lead with, for a badge or a dialog that has
    /// room for a sentence rather than a list.
    public var headline: TrustFinding? {
        findings.first { $0.weight == .strong }
    }

    // MARK: - Computing it

    /// Read a sender's stored headers.
    ///
    /// Per group rather than per message on purpose: one message failing DMARC
    /// is a thing that happens to forwarded mail, and the decision on offer is
    /// about the sender, not the message.
    public static func of(_ group: SenderGroup) -> SenderTrustVerdict {
        var findings: [TrustFinding] = []
        if let authentication = authenticationFinding(group) { findings.append(authentication) }
        findings.append(contentsOf: targetFindings(group))
        return SenderTrustVerdict(findings: findings)
    }

    // MARK: - Authentication

    /// A message whose verdict can be attributed to the sender the row shows.
    ///
    /// A header whose `header.from` disagrees with the address on screen is
    /// describing some other identity — a forwarder's, most often — and reading
    /// it as this sender's verdict would be inventing evidence.
    static func usableVerdicts(_ group: SenderGroup) -> [AuthenticationResults] {
        group.messages.compactMap { message -> AuthenticationResults? in
            guard let auth = message.authentication, !auth.isSilent else { return nil }
            guard let claimed = auth.headerFrom else { return auth }
            let sender = RegistrableDomain.of(message.sender.host)
            guard !sender.isEmpty else { return auth }
            return RegistrableDomain.of(claimed) == sender ? auth : nil
        }
    }

    /// Whether the provider's verdicts add up to a failure for this message.
    ///
    /// DMARC is the one that means something on its own: it is the sender's own
    /// published policy being applied, so a failure says the mail did not come
    /// from where it claims. SPF and DKIM are only read together, and only when
    /// no DMARC verdict was given at all — either alone fails constantly on mail
    /// that was forwarded or passed through a list.
    static func isFailing(_ auth: AuthenticationResults) -> Bool {
        if let dmarc = auth.dmarc { return dmarc.isFailure }
        return auth.spf?.isFailure == true && auth.dkim?.isFailure == true
    }

    static func authenticationFinding(_ group: SenderGroup) -> TrustFinding? {
        let usable = usableVerdicts(group)
        guard !usable.isEmpty else { return nil }
        let failing = usable.filter(isFailing)
        guard !failing.isEmpty else { return nil }

        let authority = failing.first?.authority
        let named = (authority?.isEmpty == false) ? authority! : "your mail provider"
        let domain = group.messages.first.map { RegistrableDomain.of($0.sender.host) } ?? group.id.key

        // Every checked message failing is the shape of a sender that never
        // authenticated. Some failing and some passing is the shape of mail that
        // took an unusual route — which happens to legitimate senders every day,
        // and is not something to advise anybody about.
        let allFailed = failing.count == usable.count
        // A mailing list breaks DMARC by rewriting what it forwards. That is a
        // known property of mailing lists, not a finding about the sender.
        let isList = group.isMailingList

        if allFailed && !isList {
            return TrustFinding(
                kind: .authenticationFailed,
                weight: .strong,
                title: "Your mail provider could not verify this sender",
                detail: "\(named) checked \(usable.count) \(usable.count == 1 ? "message" : "messages") "
                    + "from \(domain) and none of them passed. Mail that fails these checks often "
                    + "is not from where it says it is. This is the provider's finding about "
                    + "delivery into your mailbox, not Nevermore's about the sender, and genuine "
                    + "senders do fail it through misconfiguration — so treat it as a reason to "
                    + "ignore or trash this sender rather than to ask them to stop."
            )
        }
        return TrustFinding(
            kind: .authenticationFailed,
            weight: .advisory,
            title: "Some messages failed your mail provider's checks",
            detail: "\(named) found \(failing.count) of \(usable.count) messages from \(domain) "
                + (isList
                    ? "did not pass. This is a mailing list, and lists break these checks by "
                        + "rewriting the mail they pass on, so it is weak evidence about the sender."
                    : "did not pass, and the rest did. Forwarded mail fails these checks routinely, "
                        + "so an occasional failure says little.")
        )
    }

    // MARK: - Where the unsubscribe would actually go

    /// URL shorteners. A bulk sender never shortens an unsubscribe link — the
    /// link carries a per-recipient token and the domain is part of how the
    /// receiving provider decides to trust them. Somebody hiding where the link
    /// goes has a reason.
    static let urlShorteners: Set<String> = [
        "bit.ly", "tinyurl.com", "t.co", "goo.gl", "ow.ly", "is.gd", "buff.ly",
        "rebrand.ly", "cutt.ly", "shorturl.at", "rb.gy", "tiny.cc", "t.ly",
        "s.id", "shorte.st", "adf.ly", "bl.ink", "short.io", "trib.al",
    ]

    /// Free consumer mailboxes. An unsubscribe address here is a person's inbox,
    /// not a list manager: the request does not remove anything, it just tells
    /// someone the address is worth keeping.
    static let consumerMailboxDomains: Set<String> = [
        "gmail.com", "googlemail.com", "yahoo.com", "ymail.com", "outlook.com",
        "hotmail.com", "live.com", "msn.com", "aol.com", "icloud.com", "me.com",
        "mac.com", "gmx.com", "gmx.net", "gmx.de", "mail.com", "mail.ru",
        "yandex.ru", "yandex.com", "protonmail.com", "proton.me", "zoho.com",
        "qq.com", "163.com", "126.com", "sina.com", "naver.com",
    ]

    /// Domains bulk-mail platforms host unsubscribe links on. Only used to keep
    /// the *advisory* mismatch note quiet on the common case; nothing depends on
    /// this list being complete, and it never will be.
    static let bulkMailLinkDomains: Set<String> = [
        "list-manage.com", "list-manage1.com", "list-manage2.com", "campaign-archive.com",
        "sendgrid.net", "klaviyo.com", "hubspot.com", "hs-sites.com", "constantcontact.com",
        "rs6.net", "ctctusercontent.com", "exacttarget.com", "marketo.com", "mktoresp.com",
        "pardot.com", "salesforce.com", "mailerlite.com", "ml-attach.com", "activehosted.com",
        "aweber.com", "getresponse.com", "icptrack.com", "sailthru.com", "iterable.com",
        "braze.com", "customer.io", "drip.com", "omnisend.com", "emarsys.net",
        "responsys.net", "silverpop.com", "pages03.net", "mailjet.com", "mailgun.com",
        "postmarkapp.com", "mandrillapp.com", "sparkpostmail.com", "amazonses.com",
        "everestengagement.com", "cmail19.com", "cmail20.com", "createsend.com",
        "unsubscribe.email", "listrakbi.com", "bronto.com", "dotdigital.com",
    ]

    static func targetFindings(_ group: SenderGroup) -> [TrustFinding] {
        guard let source = group.unsubscribeSource, let unsubscribe = source.unsubscribe else {
            return []
        }
        let sender = RegistrableDomain.of(source.sender.host)
        var findings: [TrustFinding] = []

        for url in unsubscribe.webTargets {
            guard let host = url.host?.lowercased(), !host.isEmpty else { continue }
            if isBareAddress(host) {
                findings.append(
                    TrustFinding(
                        kind: .bareAddressUnsubscribeTarget,
                        weight: .strong,
                        title: "The unsubscribe link points at a bare address",
                        detail: "It goes to \(host) — a numeric address with no domain name behind "
                            + "it. Senders who run a real mailing list do not do this, because "
                            + "their own provider would stop trusting them for it."
                    ))
                break
            }
            let target = RegistrableDomain.of(host)
            if urlShorteners.contains(target) {
                findings.append(
                    TrustFinding(
                        kind: .shortenedUnsubscribeTarget,
                        weight: .strong,
                        title: "The unsubscribe link is hidden behind a shortener",
                        detail: "It goes to \(target), which forwards somewhere it does not say. "
                            + "Mailing lists do not shorten their unsubscribe links: the link "
                            + "already carries a code identifying you, and hiding the destination "
                            + "costs the sender the trust their own mail provider gives them."
                    ))
                break
            }
        }

        for mailto in unsubscribe.mailtoTargets {
            guard let at = mailto.address.lastIndex(of: "@") else { continue }
            let host = String(mailto.address[mailto.address.index(after: at)...]).lowercased()
            if consumerMailboxDomains.contains(RegistrableDomain.of(host)) {
                findings.append(
                    TrustFinding(
                        kind: .consumerMailboxUnsubscribeTarget,
                        weight: .strong,
                        title: "The unsubscribe reply would go to a personal mailbox",
                        detail: "It is addressed to \(mailto.address), a free consumer mailbox "
                            + "rather than a list manager. Nothing at that address can remove you "
                            + "from anything automatically — replying only tells whoever reads it "
                            + "that a person is at this address."
                    ))
                break
            }
        }

        // Last, and only advisory: a target on somebody else's domain is how
        // almost all legitimate bulk mail works. Worth showing, never worth
        // acting on.
        if let mismatch = mismatchFinding(unsubscribe, sender: sender, group: group) {
            findings.append(mismatch)
        }
        return findings
    }

    static func mismatchFinding(
        _ unsubscribe: ListUnsubscribe, sender: String, group: SenderGroup
    ) -> TrustFinding? {
        guard !sender.isEmpty else { return nil }
        let targets =
            unsubscribe.webTargets.compactMap { $0.host.map { RegistrableDomain.of($0.lowercased()) } }
            + unsubscribe.mailtoTargets.compactMap { target -> String? in
                guard let at = target.address.lastIndex(of: "@") else { return nil }
                return RegistrableDomain.of(
                    String(target.address[target.address.index(after: at)...]).lowercased())
            }
        let unrelated = targets.filter { !$0.isEmpty && !isRelated($0, to: sender, group: group) }
        guard let first = unrelated.first else { return nil }
        return TrustFinding(
            kind: .unrelatedUnsubscribeTarget,
            weight: .advisory,
            title: "The unsubscribe goes to a different domain",
            detail: "Mail from \(sender), unsubscribe handled by \(first). That is normal when a "
                + "sender uses a bulk-mail provider, and most do — it is only worth a second look "
                + "when \(first) is not a company you would expect to be handling their mail."
        )
    }

    /// Whether an unsubscribe target's domain can be accounted for.
    static func isRelated(_ target: String, to sender: String, group: SenderGroup) -> Bool {
        if target == sender { return true }
        if Grouping.sharedSendingPlatforms.contains(target) { return true }
        if bulkMailLinkDomains.contains(target) { return true }
        // `Acme <news@acme.com>` unsubscribing at `acme.co.uk` is the same brand
        // on a second registration, which is common and not interesting.
        if brandLabel(target) == brandLabel(sender) { return true }
        // A mailing list's own domain is as good an explanation as the From is.
        if let listID = group.mailingListID, RegistrableDomain.of(listID) == target { return true }
        return false
    }

    /// The registrable domain without its public suffix — `harborfreight.com`
    /// and `harborfreight.co.uk` both reduce to `harborfreight`.
    static func brandLabel(_ domain: String) -> String {
        String(domain.split(separator: ".").first ?? "")
    }

    /// Whether a URL host is a literal IPv4 or IPv6 address rather than a name.
    public static func isBareAddress(_ host: String) -> Bool {
        if host.contains(":") { return true }
        let labels = host.split(separator: ".")
        return labels.count == 4 && labels.allSatisfy { label in
            !label.isEmpty && label.allSatisfy(\.isNumber)
        }
    }
}

// MARK: - Which recommendation the row leads with

extension SenderTrustVerdict {
    /// The action the row should lead with, given what an agent recommended.
    ///
    /// **The decision TASK-52 left open, settled here: the local verdict may veto
    /// an unsubscribe, and may never mint one.**
    ///
    /// The evidence is asymmetric, so the rule is too. A provider verdict that a
    /// sender cannot be verified is evidence *against* that sender. The same
    /// verdict coming back clean is evidence of nothing at all — a spammer
    /// publishing SPF and DKIM for their own throwaway domain passes DMARC on
    /// the first try, and does, routinely. So a clean read must never be allowed
    /// to talk over an agent that has looked at the content and said "this is
    /// cold outreach, ignore it": the agent knows something the headers do not.
    ///
    /// In the other direction the app wins, because it knows something the agent
    /// does not. An agent reading subjects and senders through the MCP tools
    /// never sees `Authentication-Results`, and cannot see that the unsubscribe
    /// link resolves to a shortener. Where they disagree about unsubscribing,
    /// the side holding evidence the other could not have is the side to follow —
    /// and it is the side arguing for the reversible action.
    ///
    /// The agent's reason is not replaced by any of this. Both are shown: the
    /// badge says what to do, and the reasons say who thought so and why.
    public func recommendation(given agent: RecommendedAction?) -> RecommendedAction {
        let stated = agent ?? .unsubscribe
        guard stated == .unsubscribe else { return stated }
        return recommendedAction ?? stated
    }
}

/// One reason the app is stopping to ask before an unsubscribe goes out.
///
/// Two things can object — an agent that reviewed the sender, and the app's own
/// reading of the headers — and they get one dialog between them rather than two
/// in a row. Which one spoke is part of the message: "your mail provider could
/// not verify this sender" and "the agent thought this was cold outreach" are
/// different claims with different standing, and a user deciding whether to
/// override needs to know which they are looking at.
public struct UnsubscribeObjection: Sendable, Hashable {
    public enum Source: Sendable, Hashable {
        /// Nevermore, from the headers of the mail itself.
        case mailProvider
        /// An external agent, from whatever it looked at.
        case agent

        public var label: String {
            switch self {
            case .mailProvider: "Nevermore, from the message headers"
            case .agent: "the agent"
            }
        }
    }

    public let senderName: String
    public let recommendation: RecommendedAction
    /// Verbatim from whoever objected. Never rewritten: a reason the app
    /// paraphrased would be the app's judgement wearing somebody else's name.
    public let reason: String
    public let source: Source

    public init(
        senderName: String, recommendation: RecommendedAction, reason: String, source: Source
    ) {
        self.senderName = senderName
        self.recommendation = recommendation
        self.reason = reason
        self.source = source
    }

    public var line: String {
        "\(senderName) — recommended: \(recommendation.badgeTitle), by \(source.label). \(reason)"
    }
}

/// The confirmation shown when an unsubscribe would go out against advice.
///
/// The same dialog TASK-52 built, widened to carry the app's own objections
/// alongside an agent's. Deliberately not a second warning surface: a user who
/// has to dismiss two dialogs to unsubscribe learns to dismiss dialogs.
public enum UnsubscribeExposureWarning {
    public static let confirmTitle = ProposalOverrideWarning.confirmTitle

    public static func title(for objections: [UnsubscribeObjection]) -> String {
        let count = objections.count
        // An agent-only set keeps TASK-52's wording exactly: it names who is
        // objecting, which is the whole point of the dialog. Anything the app
        // itself found needs wording that fits every finding — "your provider
        // could not verify them" would be a lie about a shortened link.
        if Set(objections.map(\.source)) == [.agent] {
            return ProposalOverrideWarning.title(count: count)
        }
        return count == 1
            ? "There is a reason not to unsubscribe from this sender"
            : "There are reasons not to unsubscribe from \(count) of these senders"
    }

    public static func message(for objections: [UnsubscribeObjection]) -> String {
        (objections.map(\.line) + [ProposalOverrideWarning.closingParagraph])
            .joined(separator: "\n\n")
    }
}
