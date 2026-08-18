import AppKit

/// Runs on the pasteboard and writes the result back, so a transform is a
/// keystroke rather than a trip to a website.
enum Transform {
    static func apply(_ name: String) -> String {
        let board = NSPasteboard.general

        guard let input = board.string(forType: .string), !input.isEmpty else {
            return "the clipboard is empty"
        }

        guard let result = run(name, input) else {
            return "not \(name)"
        }

        board.clearContents()
        board.setString(result, forType: .string)

        return result
    }

    private static func run(_ name: String, _ input: String) -> String? {
        switch name {
        case "base64-decode": return decodeBase64(input).flatMap { String(data: $0, encoding: .utf8) }
        case "base64-encode": return Data(input.utf8).base64EncodedString()
        case "hex-decode": return decodeHex(input).flatMap { String(data: $0, encoding: .utf8) }
        case "hex-encode": return Data(input.utf8).map { String(format: "%02x", $0) }.joined()
        case "url-decode": return input.removingPercentEncoding
        case "url-encode": return input.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        case "json": return formatJSON(input)
        case "jwt": return decodeJWT(input)
        case "timestamp": return fromTimestamp(input)
        default: return nil
        }
    }

    /// Takes base64url too, which is what a JWT carries.
    private static func decodeBase64(_ input: String) -> Data? {
        var clean = input
            .replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        while clean.count % 4 != 0 { clean += "=" }

        return Data(base64Encoded: clean)
    }

    private static func decodeHex(_ input: String) -> Data? {
        var clean = input.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)

        if clean.hasPrefix("0x") || clean.hasPrefix("0X") { clean = String(clean.dropFirst(2)) }

        guard clean.count % 2 == 0, clean.allSatisfy(\.isHexDigit) else { return nil }

        var bytes = Data()
        var index = clean.startIndex

        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)

            guard let byte = UInt8(clean[index..<next], radix: 16) else { return nil }

            bytes.append(byte)
            index = next
        }

        return bytes
    }

    private static func formatJSON(_ input: String) -> String? {
        guard let data = input.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: value,
                  options: [.prettyPrinted, .sortedKeys]
              )
        else { return nil }

        return String(data: pretty, encoding: .utf8)
    }

    /// Header and payload only: the signature is bytes, and nothing readable
    /// comes of printing it.
    private static func decodeJWT(_ input: String) -> String? {
        let parts = input
            .replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
            .components(separatedBy: ".")

        guard parts.count >= 2 else { return nil }

        return parts.prefix(2).compactMap { part in
            guard let data = decodeBase64(part), let text = String(data: data, encoding: .utf8) else {
                return nil
            }

            return formatJSON(text) ?? text
        }.joined(separator: "\n")
    }

    private static func fromTimestamp(_ input: String) -> String? {
        guard var seconds = Double(input.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }

        // a value this large is milliseconds, which is what a JS payload carries
        if seconds > 1e11 { seconds /= 1000 }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        formatter.timeZone = TimeZone(identifier: "UTC")

        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }
}
