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
public enum DestinationGuard {
    public static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return false }
        guard let host = url.host, !host.isEmpty else { return false }

        let addresses = resolve(host)
        // A host that resolves to nothing is refused rather than sent blind.
        guard !addresses.isEmpty else { return false }
        return addresses.allSatisfy(\.isGlobalUnicast)
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

extension DestinationGuard.IPAddress {
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
