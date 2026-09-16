import Foundation

/// A JSON document as the clipboard reads it: keys in the order they were
/// written and numbers as they were written, since a document is looked at
/// here, not computed with, and `1757068800000000000` should come back out as
/// it went in.
///
/// Sendable is said rather than inferred: working it out for a recursive enum
/// with a tuple inside is a cycle the compiler gives up on.
indirect enum JSONValue: @unchecked Sendable {
    case object([(key: String, value: JSONValue)])
    case array([JSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    var isContainer: Bool {
        switch self {
        case .object, .array: true
        default: false
        }
    }

    /// `{ 3 keys }`, `[ 12 items ]`, `"…"`, or the scalar as written.
    var summary: String {
        switch self {
        case .object(let pairs): "{ \(pairs.count) \(pairs.count == 1 ? "key" : "keys") }"
        case .array(let items): "[ \(items.count) \(items.count == 1 ? "item" : "items") ]"
        case .string(let text): "\"" + text.replacingOccurrences(of: "\n", with: "\\n") + "\""
        case .number(let text): text
        case .bool(let flag): flag ? "true" : "false"
        case .null: "null"
        }
    }

    /// What pasting a node hands over: a string bare, without the quotes it
    /// wears in the document, and a container written out again.
    var pasted: String {
        switch self {
        case .string(let text): text
        case .object, .array: pretty()
        default: summary
        }
    }

    /// The document written out with two spaces of indent, in the order it
    /// came in.
    func pretty(indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        let inner = String(repeating: "  ", count: indent + 1)

        switch self {
        case .object(let pairs):
            guard !pairs.isEmpty else { return "{}" }

            return "{\n" + pairs.map { inner + JSONValue.quote($0.key) + ": " + $0.value.pretty(indent: indent + 1) }
                .joined(separator: ",\n") + "\n" + pad + "}"
        case .array(let items):
            guard !items.isEmpty else { return "[]" }

            return "[\n" + items.map { inner + $0.pretty(indent: indent + 1) }.joined(separator: ",\n") + "\n" + pad + "]"
        case .string(let text):
            return JSONValue.quote(text)
        default:
            return summary
        }
    }

    static func quote(_ text: String) -> String {
        var out = "\""

        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20: out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }

        return out + "\""
    }

    /// The document as it is written out, one line each, with what a line
    /// stands for kept beside it so the cursor can take it.
    func lines() -> [JSONLine] {
        var out: [JSONLine] = []

        func walk(_ value: JSONValue, depth: Int, key: String?, last: Bool) {
            let comma = last ? "" : ","

            switch value {
            case .object(let pairs) where !pairs.isEmpty:
                out.append(JSONLine(depth: depth, key: key, text: "{", value: value))

                for (index, pair) in pairs.enumerated() {
                    walk(pair.value, depth: depth + 1, key: pair.key, last: index == pairs.count - 1)
                }

                out.append(JSONLine(depth: depth, key: nil, text: "}" + comma, value: nil))
            case .array(let items) where !items.isEmpty:
                out.append(JSONLine(depth: depth, key: key, text: "[", value: value))

                for (index, item) in items.enumerated() {
                    walk(item, depth: depth + 1, key: nil, last: index == items.count - 1)
                }

                out.append(JSONLine(depth: depth, key: nil, text: "]" + comma, value: nil))
            default:
                out.append(JSONLine(depth: depth, key: key, text: value.summary + comma, value: value))
            }
        }

        walk(self, depth: 0, key: nil, last: true)

        return out
    }

    // MARK: - Parsing

    /// Reads strict JSON and what the Mongo shell and Compass print, which is
    /// not: bare keys, single quotes, trailing commas, `ObjectId('…')` and
    /// `ISODate('…')` around a value, `undefined`. One reader for both, since
    /// the strict form is a subset of the loose one and JSONSerialization
    /// would in any case lose the order of the keys.
    ///
    /// A document is a whole object or array and nothing else, and a call is
    /// only unwrapped around a single literal: `onClick(event)` is code.
    static func parse(_ text: String) -> JSONValue? {
        var parser = JSONParser(text: text)

        parser.skipSpace()

        guard let first = parser.peek, first == "{" || first == "[" else { return nil }
        guard let value = parser.value(), value.isContainer else { return nil }

        parser.skipSpace()

        return parser.peek == nil ? value : nil
    }
}

/// One line of the document as written out: the indent, the key when there
/// is one, and the rest of the line — a scalar, or the bracket that opens or
/// closes a container.
struct JSONLine {
    let depth: Int
    let key: String?
    let text: String
    /// What the line stands for, and pasting it hands over: a scalar, or the
    /// whole container on the line that opens it. A closing bracket is
    /// nothing, and the cursor passes over it.
    let value: JSONValue?

    /// The root and a closing bracket are passed over: the whole document is
    /// what the row itself pastes.
    var selectable: Bool { value != nil && depth > 0 }
}

private struct JSONParser {
    let chars: [Character]
    var at = 0

    init(text: String) {
        chars = Array(text)
    }

    var peek: Character? { at < chars.count ? chars[at] : nil }

    mutating func skipSpace() {
        while let c = peek, c.isWhitespace { at += 1 }
    }

    mutating func take(_ c: Character) -> Bool {
        skipSpace()

        guard peek == c else { return false }

        at += 1

        return true
    }

    mutating func value() -> JSONValue? {
        skipSpace()

        guard let c = peek else { return nil }

        switch c {
        case "{": return object()
        case "[": return array()
        case "\"", "'": return string().map(JSONValue.string)
        case "-", "0"..."9": return number()
        default: return word()
        }
    }

    mutating func object() -> JSONValue? {
        guard take("{") else { return nil }

        var pairs: [(key: String, value: JSONValue)] = []

        while true {
            if take("}") { return .object(pairs) }

            guard let key = key(), take(":"), let value = value() else { return nil }

            pairs.append((key, value))

            if take(",") { continue }
            if take("}") { return .object(pairs) }

            return nil
        }
    }

    mutating func array() -> JSONValue? {
        guard take("[") else { return nil }

        var items: [JSONValue] = []

        while true {
            if take("]") { return .array(items) }

            guard let value = value() else { return nil }

            items.append(value)

            if take(",") { continue }
            if take("]") { return .array(items) }

            return nil
        }
    }

    /// Quoted, or a bare word as the shell writes it.
    mutating func key() -> String? {
        skipSpace()

        if peek == "\"" || peek == "'" { return string() }

        let start = at

        while let c = peek, c.isLetter || c.isNumber || c == "_" || c == "$" { at += 1 }

        return at > start ? String(chars[start..<at]) : nil
    }

    mutating func string() -> String? {
        guard let quote = peek, quote == "\"" || quote == "'" else { return nil }

        at += 1

        var out = ""

        while let c = peek {
            at += 1

            if c == quote { return out }

            guard c == "\\" else {
                out.append(c)

                continue
            }

            guard let escaped = peek else { return nil }

            at += 1

            switch escaped {
            case "n": out += "\n"
            case "r": out += "\r"
            case "t": out += "\t"
            case "b": out += "\u{8}"
            case "f": out += "\u{c}"
            case "u":
                guard at + 4 <= chars.count,
                      let code = UInt32(String(chars[at..<at + 4]), radix: 16),
                      let scalar = Unicode.Scalar(code)
                else { return nil }

                at += 4
                out.unicodeScalars.append(scalar)
            default: out.append(escaped)
            }
        }

        return nil
    }

    mutating func number() -> JSONValue? {
        let start = at

        while let c = peek, c.isNumber || "+-.eE".contains(c) { at += 1 }

        let text = String(chars[start..<at])

        return Double(text) != nil ? .number(text) : nil
    }

    /// `true`, `null`, `undefined`, or a call such as `ObjectId('…')`
    /// around one literal, which reads as the literal.
    mutating func word() -> JSONValue? {
        let start = at

        while let c = peek, c.isLetter || c.isNumber || c == "_" { at += 1 }

        let name = String(chars[start..<at])

        switch name {
        case "true": return .bool(true)
        case "false": return .bool(false)
        case "null", "undefined": return .null
        case "": return nil
        default: break
        }

        guard take("(") else { return nil }

        let opened = at

        if take(")") { return .string(name + "()") }

        guard let inner = value(), !inner.isContainer else { return nil }

        if take(")") { return inner }

        // two arguments — Timestamp(1, 2), BinData(0, '…') — are kept as
        // they were written, since neither is the value on its own
        var depth = 1

        while let c = peek {
            at += 1

            if c == "(" { depth += 1 }
            if c == ")" { depth -= 1 }
            if depth == 0 { return .string(name + "(" + String(chars[opened..<at - 1]) + ")") }
        }

        return nil
    }
}
