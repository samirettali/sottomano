import Foundation

/// zoxide style: a use count that decays with age, so something used constantly
/// outranks something used once a year without ever forgetting either. Capped,
/// because it is only there to break ties between comparable matches.
@MainActor
final class Frecency {
    static let shared = Frecency()

    private struct Use: Codable {
        var count: Int
        var last: Date
    }

    private let url = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/sottomano/frecency.json")

    private var uses: [String: Use]

    private init() {
        let data = (try? Data(contentsOf: url)) ?? Data()
        uses = (try? JSONDecoder().decode([String: Use].self, from: data)) ?? [:]
    }

    func score(_ id: String) -> Int {
        guard let use = uses[id] else { return 0 }

        let age = Date().timeIntervalSince(use.last)
        let decay: Double

        switch age {
        case ..<3600: decay = 4
        case ..<86400: decay = 2
        case ..<604800: decay = 0.5
        default: decay = 0.25
        }

        return min(Int(Double(use.count) * decay * 3), 30)
    }

    func remember(_ id: String) {
        var use = uses[id] ?? Use(count: 0, last: Date())
        use.count += 1
        use.last = Date()
        uses[id] = use

        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try? JSONEncoder().encode(uses).write(to: url)
    }
}
