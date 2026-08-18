import Foundation

/// Subsequence match: nil when a character is missing, otherwise a score that
/// rewards consecutive hits and matches near the start. Ported from the
/// Hammerspoon picker so the two rank a list the same way.
enum Fuzzy {
    static func score(_ needle: String, _ haystack: String) -> Int? {
        if needle.isEmpty { return 0 }

        let target = Array(haystack.lowercased())
        var total = 0
        var from = 0
        var last: Int?

        for character in needle.lowercased() {
            guard let at = target[from...].firstIndex(of: character) else { return nil }

            if let last, at == last + 1 { total += 12 }
            if at == 0 { total += 8 }

            total -= at - from
            last = at
            from = at + 1
        }

        return total
    }

    /// A hit on the name outranks one that needed the subtitle.
    static func rank(_ query: String, name: String, subtitle: String) -> Int? {
        if let onName = score(query, name) { return onName + 20 }

        return score(query, name + " " + subtitle)
    }
}
