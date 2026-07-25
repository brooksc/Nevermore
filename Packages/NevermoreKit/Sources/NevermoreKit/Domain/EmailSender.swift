import Foundation

/// A parsed `From:` header.
public struct EmailSender: Hashable, Sendable {
    public let displayName: String
    public let address: String
    /// Host portion of `address`, lowercased. Empty when the address is unparseable.
    public let host: String

    public init(displayName: String, address: String, host: String) {
        self.displayName = displayName
        self.address = address
        self.host = host
    }

    /// Parse a `From:` header value, e.g. `=?UTF-8?Q?Acme?= <news@mail.acme.com>`.
    public init(header: String) {
        let decoded = MIMEHeader.decode(header)
        let (name, addr) = Self.split(decoded)
        let lowered = addr.lowercased()
        self.displayName = name
        self.address = lowered
        self.host = lowered.contains("@")
            ? String(lowered[lowered.index(after: lowered.lastIndex(of: "@")!)...])
            : ""
    }

    /// Splits `Display Name <addr@host>` into its parts.
    ///
    /// Angle brackets win when present; otherwise the whole string is treated as
    /// the address. Quotes around the display name are stripped.
    private static func split(_ s: String) -> (name: String, address: String) {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)

        // Use the LAST angle-bracket pair: display names sometimes contain one,
        // e.g. `"Foo <bar>" <real@example.com>`.
        if let close = trimmed.lastIndex(of: ">"),
           let open = trimmed[trimmed.startIndex..<close].lastIndex(of: "<") {
            let addr = String(trimmed[trimmed.index(after: open)..<close])
            var name = String(trimmed[trimmed.startIndex..<open])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if name.count >= 2, name.hasPrefix("\""), name.hasSuffix("\"") {
                name = String(name.dropFirst().dropLast())
            }
            return (name.trimmingCharacters(in: .whitespacesAndNewlines), addr)
        }

        return ("", trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "<>")))
    }

    /// What to show in the sender column: display name, else address, else host.
    public var label: String {
        if !displayName.isEmpty { return displayName }
        if !address.isEmpty { return address }
        return host
    }
}
