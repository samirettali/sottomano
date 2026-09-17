import Foundation

/// A JSON Web Token: three base64url segments, the first two JSON objects and
/// the first naming an algorithm. Read, not verified — there is no key here
/// to verify it with, and what is wanted is to see what it carries.
@MainActor
struct JWT {
    let header: JSONValue
    let payload: JSONValue
    let algorithm: String
    let expires: Date?
    let issued: Date?

    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // every header starts `{"` and that is `ey` in base64: the cheapest
        // test there is, and it rules out nearly every other row
        guard trimmed.hasPrefix("ey"), trimmed.count <= 65_536, !trimmed.contains(where: \.isWhitespace) else { return nil }

        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)

        guard parts.count == 3,
              let head = Base64.decode(String(parts[0])), let headText = String(data: head, encoding: .utf8),
              let body = Base64.decode(String(parts[1])), let bodyText = String(data: body, encoding: .utf8),
              case .object(let fields)? = JSONValue.parse(headText),
              let payload = JSONValue.parse(bodyText), case .object(let claims) = payload,
              case .string(let algorithm)? = fields.first(where: { $0.key == "alg" })?.value
        else { return nil }

        header = .object(fields)
        self.payload = payload
        self.algorithm = algorithm

        func date(_ claim: String) -> Date? {
            guard case .number(let text)? = claims.first(where: { $0.key == claim })?.value, let seconds = Double(text) else { return nil }

            return Date(timeIntervalSince1970: seconds)
        }

        expires = date("exp")
        issued = date("iat")
    }

    /// `JWT · HS256 · expires in 2 days`, or `· expired 3 hours ago`.
    var summary: String {
        var parts = ["JWT", algorithm]

        if let expires {
            let relative = RelativeDateTimeFormatter()
            relative.locale = Locale(identifier: "en_US")

            parts.append((expires < Date() ? "expired " : "expires ") + relative.localizedString(for: expires, relativeTo: Date()))
        }

        return parts.joined(separator: " · ")
    }

    /// Header and payload as one document, so the same lines beside the list
    /// serve it and a claim can be picked off it.
    var document: JSONValue {
        .object([(key: "header", value: header), (key: "payload", value: payload)])
    }
}

/// Text that is base64, standard or url-safe, and decodes to text. Loose by
/// nature — a word of letters is base64 too — so it runs after everything
/// else and asks the bytes to be readable. Four characters and up, one
/// group: a short word that happens to decode to printable bytes is the
/// price of reading a short secret.
enum Base64 {
    static func decode(_ text: String) -> Data? {
        var standard = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")

        while standard.count % 4 != 0 { standard += "=" }

        return Data(base64Encoded: standard)
    }

    /// The decoded text, when it is text: valid UTF-8 with nothing unprintable
    /// in it beyond a line break or a tab.
    static func text(of text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let padding = trimmed.reversed().prefix { $0 == "=" }.count
        let body = trimmed.dropLast(padding)

        guard body.count >= 4, padding <= 2,
              body.allSatisfy({ $0.isLetter || $0.isNumber || "+/-_".contains($0) }),
              // a number is a number: an epoch or an id is not base64
              !body.allSatisfy(\.isNumber),
              (padding == 0 ? body.count % 4 != 1 : trimmed.count % 4 == 0),
              let data = decode(trimmed), let decoded = String(data: data, encoding: .utf8),
              !decoded.unicodeScalars.contains(where: { $0.value < 0x20 && !"\n\t\r".unicodeScalars.contains($0) })
        else { return nil }

        return decoded
    }
}

/// Bytes written as hex: `0x` and an even run of hex digits, or a bare run
/// long enough to be a hash rather than a word — a git sha, a keccak, a
/// transaction. Sixteen digits and up: eight bytes, past which no word in a
/// hex alphabet is likely.
struct Hex {
    let bytes: [UInt8]

    init?(_ text: String) {
        var digits = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        let prefixed = digits.hasPrefix("0x") || digits.hasPrefix("0X")

        if prefixed { digits = digits.dropFirst(2) }

        guard digits.count % 2 == 0, digits.count >= (prefixed ? 2 : 16), digits.count <= 8192,
              digits.allSatisfy(\.isHexDigit)
        else { return nil }

        var bytes: [UInt8] = []
        var index = digits.startIndex

        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)

            bytes.append(UInt8(digits[index..<next], radix: 16)!)
            index = next
        }

        self.bytes = bytes
    }

    /// `32 bytes`, what the row says.
    var summary: String { "\(bytes.count) \(bytes.count == 1 ? "byte" : "bytes")" }

    /// The value in the forms it is read in, then the bytes sixteen to a
    /// line with the printable ones beside them, the way `hexdump -C` lays
    /// them out.
    var details: [Detail] {
        var out = [Detail("Bytes", String(bytes.count))]

        // up to 256 bits: a word, a hash, a balance — beyond that a decimal
        // is not a number anyone reads
        if bytes.count <= 32 {
            out.append(Detail("Decimal", Hex.decimal(bytes)))
        }

        if let text = String(bytes: bytes, encoding: .utf8),
           !text.unicodeScalars.contains(where: { $0.value < 0x20 && !"\n\t\r".unicodeScalars.contains($0) }) {
            out.append(Detail("UTF-8", text))
        }

        for start in stride(from: 0, to: bytes.count, by: 16) {
            let line = bytes[start..<min(start + 16, bytes.count)]
            let hex = line.map { String(format: "%02x", $0) }.joined(separator: " ")
            let ascii = line.map { $0 >= 0x20 && $0 < 0x7f ? String(UnicodeScalar($0)) : "." }.joined()

            out.append(Detail(String(format: "%04x", start), hex.padding(toLength: 47, withPad: " ", startingAt: 0) + "  " + ascii))
        }

        return out
    }

    /// Big-endian bytes to decimal, by long division on the digits: there
    /// is no integer wide enough for 32 bytes, and no library for one here.
    private static func decimal(_ bytes: [UInt8]) -> String {
        var digits: [UInt8] = [0]

        for byte in bytes {
            var carry = Int(byte)

            for index in digits.indices {
                let value = Int(digits[index]) * 256 + carry

                digits[index] = UInt8(value % 10)
                carry = value / 10
            }

            while carry > 0 {
                digits.append(UInt8(carry % 10))
                carry /= 10
            }
        }

        return String(digits.reversed().map { Character(String($0)) })
    }
}
