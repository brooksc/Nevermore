import Foundation

/// Decoding for RFC 2047 encoded-words (`=?UTF-8?B?...?=`).
///
/// Sender display names arrive encoded far more often than not, and an
/// undecoded blob defeats the display-name heuristic that splits shared
/// newsletter platforms apart (see ``Grouping``).
public enum MIMEHeader {
    /// Decode all encoded-words in `raw`, leaving other text untouched.
    public static func decode(_ raw: String) -> String {
        guard raw.contains("=?") else { return raw }

        var out = ""
        var rest = Substring(raw)
        // Whitespace between two adjacent encoded-words is not significant and
        // must be dropped, otherwise multi-part names gain stray spaces.
        var lastWasEncodedWord = false

        while let start = rest.range(of: "=?") {
            let literal = rest[rest.startIndex..<start.lowerBound]
            if !(lastWasEncodedWord && literal.allSatisfy(\.isWhitespace) && !literal.isEmpty) {
                out += literal
            }

            let afterMarker = rest[start.upperBound...]
            guard let word = parseEncodedWord(afterMarker) else {
                // Not a well-formed encoded-word; emit the marker and move on.
                out += "=?"
                rest = afterMarker
                lastWasEncodedWord = false
                continue
            }
            out += word.text
            rest = word.remainder
            lastWasEncodedWord = true
        }
        out += rest
        return out
    }

    /// Parses `charset?enc?payload?=` (the `=?` prefix already consumed).
    private static func parseEncodedWord(
        _ s: Substring
    ) -> (text: String, remainder: Substring)? {
        guard let c1 = s.firstIndex(of: "?") else { return nil }
        let charsetName = String(s[s.startIndex..<c1])

        let afterCharset = s[s.index(after: c1)...]
        guard let c2 = afterCharset.firstIndex(of: "?") else { return nil }
        let encoding = afterCharset[afterCharset.startIndex..<c2].uppercased()

        let afterEncoding = afterCharset[afterCharset.index(after: c2)...]
        guard let end = afterEncoding.range(of: "?=") else { return nil }
        let payload = String(afterEncoding[afterEncoding.startIndex..<end.lowerBound])

        let bytes: Data?
        switch encoding {
        case "B": bytes = Data(base64Encoded: payload)
        case "Q": bytes = decodeQuotedPrintable(payload)
        default: return nil
        }
        guard let bytes else { return nil }

        let encodingID = CFStringConvertIANACharSetNameToEncoding(charsetName as CFString)
        let charset: String.Encoding = encodingID == kCFStringEncodingInvalidId
            ? .utf8
            : String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encodingID))

        let text = String(data: bytes, encoding: charset)
            ?? String(decoding: bytes, as: UTF8.self)
        return (text, afterEncoding[end.upperBound...])
    }

    /// Q-encoding: like quoted-printable, but `_` means space.
    private static func decodeQuotedPrintable(_ s: String) -> Data? {
        var out = Data()
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if ch == "_" {
                out.append(0x20)
                i = s.index(after: i)
            } else if ch == "=" {
                let hexEnd = s.index(i, offsetBy: 3, limitedBy: s.endIndex) ?? s.endIndex
                guard s.distance(from: i, to: hexEnd) == 3,
                      let byte = UInt8(s[s.index(after: i)..<hexEnd], radix: 16)
                else { return nil }
                out.append(byte)
                i = hexEnd
            } else {
                out.append(contentsOf: Array(String(ch).utf8))
                i = s.index(after: i)
            }
        }
        return out
    }
}
