import Foundation

/// Decides whether an outbound unsubscribe HTTP request may be sent to a URL.
///
/// The URL comes straight from an attacker-authored `List-Unsubscribe` header,
/// so without a guard a sender could point it at `http://127.0.0.1:…`, a LAN
/// admin panel, a cloud metadata endpoint, or any other host reachable only
/// from the victim's machine (SSRF). This resolves the host and requires every
/// address it maps to be a public, global-unicast address; anything loopback,
/// private, link-local, ULA, or otherwise special is refused, as is a host that
/// won't resolve. The same check re-runs on each redirect hop.
///
/// Checking is not enough on its own. Deciding here and letting something else
/// resolve the name again leaves a window for a hostile resolver to answer
/// public for the check and private for the connection (DNS rebinding), so the
/// address that passed the check has to be the address that gets dialled. That
/// is what `pin(for:)` is for, and `PinnedProxy` is what dials it.
public enum DestinationGuard {
    public static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return false }
        guard let host = url.host, !host.isEmpty else { return false }
        return pin(for: host) != nil
    }

    // MARK: - Pinning

    /// One address, resolved once, already checked — the whole point being that
    /// the caller connects to *this* rather than resolving the name a second
    /// time and getting a different answer.
    public struct PinnedAddress: Sendable, Equatable {
        /// The name as it appeared in the URL. Kept so the caller can still send
        /// it as `Host:`/SNI, which is what makes vhosts and TLS keep working.
        public let host: String
        /// Presentation form of the validated address, e.g. `93.184.216.34`.
        public let literal: String
        public let isIPv6: Bool

        public init(host: String, literal: String, isIPv6: Bool) {
            self.host = host
            self.literal = literal
            self.isIPv6 = isIPv6
        }
    }

    /// Resolve `host` **once** and, if every answer is a public address, return
    /// all of them in the order the resolver gave. Empty means refuse: no
    /// answer, or an answer that includes anything loopback/private/link-local.
    ///
    /// Every address is checked, not just the one that ends up used. A name that
    /// answers with a public address *and* a private one is a rebinding attempt
    /// wearing a hat, and no legitimate unsubscribe endpoint needs it.
    ///
    /// All of them rather than just the first because a caller that dials a
    /// single pinned address loses the failover a resolver's multiple answers
    /// exist to provide — most CDN-backed endpoints publish several, and one
    /// being out of rotation would otherwise read to the user as an unsubscribe
    /// that simply doesn't work. Every address here has passed the same check,
    /// so trying them in turn gives up nothing.
    public static func pinnedAddresses(for host: String) -> [PinnedAddress] {
        let addresses = resolve(host)
        // A host that resolves to nothing is refused rather than sent blind.
        guard !addresses.isEmpty, addresses.allSatisfy(\.isGlobalUnicast) else { return [] }
        return addresses.compactMap { address in
            address.presentation.map {
                PinnedAddress(host: host, literal: $0, isIPv6: address.isIPv6)
            }
        }
    }

    /// The first address `pinnedAddresses(for:)` would return, or nil if the
    /// host is refused.
    public static func pin(for host: String) -> PinnedAddress? {
        pinnedAddresses(for: host).first
    }

    // MARK: - Resolution

    fileprivate enum IPAddress {
        case v4(in_addr)
        case v6(in6_addr)
    }

    /// Resolve a host name or IP literal to its addresses via getaddrinfo.
    private static func resolve(_ host: String) -> [IPAddress] {
        let clean =
            host.hasPrefix("[") && host.hasSuffix("]")
            ? String(host.dropFirst().dropLast()) : host

        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var out: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(clean, nil, &hints, &out) == 0 else { return [] }
        defer { freeaddrinfo(out) }

        var addresses: [IPAddress] = []
        var node = out
        while let n = node {
            if let sa = n.pointee.ai_addr {
                switch n.pointee.ai_family {
                case AF_INET:
                    sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                        addresses.append(.v4($0.pointee.sin_addr))
                    }
                case AF_INET6:
                    sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                        addresses.append(.v6($0.pointee.sin6_addr))
                    }
                default:
                    break
                }
            }
            node = n.pointee.ai_next
        }
        return addresses
    }
}

/// A sender-supplied URL that has passed `DestinationGuard`.
///
/// The only initialisers run the check and return nil when it fails, so holding
/// one of these *is* the proof that the check happened. Every exit that hands a
/// `List-Unsubscribe` URL to something outside the app takes a `VettedURL`
/// rather than a `URL`, which is what stops the next call site from forgetting:
/// two exits on one History row disagreed precisely because each was expected to
/// remember the check on its own (TASK-60).
public struct VettedURL: Sendable, Equatable {
    public let url: URL

    public init?(_ url: URL) {
        guard DestinationGuard.isAllowed(url) else { return nil }
        self.url = url
    }

    /// The stored form is a string — `MessageStore.UnsubscribeRecord.url` — so
    /// parsing and vetting are one step, and there is no intermediate `URL` for
    /// a caller to reach for by mistake.
    public init?(string: String?) {
        guard let string, let url = URL(string: string) else { return nil }
        self.init(url)
    }
}

extension DestinationGuard.IPAddress {
    var isIPv6: Bool {
        if case .v6 = self { return true }
        return false
    }

    /// Presentation form, for handing to a connect call as a literal so no
    /// second name lookup can happen.
    var presentation: String? {
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let result: UnsafePointer<CChar>? = {
            switch self {
            case .v4(var addr):
                return inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET6_ADDRSTRLEN))
            case .v6(var addr):
                return inet_ntop(AF_INET6, &addr, &buffer, socklen_t(INET6_ADDRSTRLEN))
            }
        }()
        guard result != nil else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// True only for ordinary public/global-unicast addresses. Every special
    /// range an SSRF would abuse — loopback, private, link-local, CGNAT, ULA,
    /// multicast, unspecified/reserved — returns false.
    var isGlobalUnicast: Bool {
        switch self {
        case .v4(let addr):
            return Self.isGlobalUnicastV4(UInt32(bigEndian: addr.s_addr))
        case .v6(let addr):
            var a = addr
            let b = withUnsafeBytes(of: &a) { Array($0) }  // 16 bytes, network order
            return Self.isGlobalUnicastV6(b)
        }
    }

    /// `host` is the address as a host-order 32-bit int (byte 0 = first octet).
    private static func isGlobalUnicastV4(_ host: UInt32) -> Bool {
        let o0 = (host >> 24) & 0xff
        let o1 = (host >> 16) & 0xff
        if o0 == 0 { return false }  // 0.0.0.0/8 "this host"
        if o0 == 10 { return false }  // 10.0.0.0/8 private
        if o0 == 127 { return false }  // 127.0.0.0/8 loopback
        if o0 == 169 && o1 == 254 { return false }  // 169.254.0.0/16 link-local
        if o0 == 172 && (o1 & 0xf0) == 16 { return false }  // 172.16.0.0/12 private
        if o0 == 192 && o1 == 168 { return false }  // 192.168.0.0/16 private
        if o0 == 100 && (o1 & 0xc0) == 64 { return false }  // 100.64.0.0/10 CGNAT
        if o0 >= 224 { return false }  // 224/4 multicast + 240/4 reserved + broadcast
        return true
    }

    private static func isGlobalUnicastV6(_ b: [UInt8]) -> Bool {
        guard b.count == 16 else { return false }
        let firstTenZero = b[0...9].allSatisfy { $0 == 0 }
        // IPv4-mapped (::ffff:a.b.c.d): classify the embedded IPv4 address so a
        // mapped loopback/private address can't slip through as "IPv6".
        if firstTenZero, b[10] == 0xff, b[11] == 0xff {
            let embedded =
                UInt32(b[12]) << 24 | UInt32(b[13]) << 16 | UInt32(b[14]) << 8 | UInt32(b[15])
            return isGlobalUnicastV4(embedded)
        }
        if b.allSatisfy({ $0 == 0 }) { return false }  // :: unspecified
        if firstTenZero && b[10...14].allSatisfy({ $0 == 0 }) && b[15] == 1 {
            return false  // ::1 loopback
        }
        if b[0] == 0xfe && (b[1] & 0xc0) == 0x80 { return false }  // fe80::/10 link-local
        if (b[0] & 0xfe) == 0xfc { return false }  // fc00::/7 unique-local
        if b[0] == 0xff { return false }  // ff00::/8 multicast
        return true
    }
}
