import AppKit

/// One thing the launcher can actually do, lifted out of the tree it lives in.
///
/// Three of the themes throw the hierarchy away: a layer is a way of *filing*
/// commands, not a way of reaching them, and reaching them is what the panel is
/// for. What survives is the promise — two keys, and it is done.
struct Command: Identifiable {
    let id = UUID()
    let entry: Entry
    /// The keys the tree would have needed, kept so the action still runs.
    let path: [String]
    let name: String
    /// The layer it was filed under, empty at the top level.
    let group: String
    /// What it takes to reach it here, one or two keys.
    var code: String = ""

    static func flatten(_ entries: [Entry], group: String = "", path: [String] = []) -> [Command] {
        entries.flatMap { entry -> [Command] in
            guard let name = entry.name, entry.shift != true else { return [] }

            if let children = entry.entries {
                return flatten(children, group: name, path: path + [entry.key])
            }

            return [Command(entry: entry, path: path + [entry.key], name: name, group: group)]
        }
    }
}

// MARK: - Codes

enum Codes {
    /// The left hand names the row and the right hand names the column, so a
    /// command is a place on a grid rather than a path through a tree — and the
    /// two keys can be pressed together, one hand each.
    static let rows = ["a", "s", "d", "f", "g", "q", "w", "e", "r", "t"]
    static let columns = ["h", "j", "k", "l", "n", "m", "u", "i", "o", "p"]

    /// Groups keep their order, and each takes a row of its own.
    static func grid(_ commands: [Command]) -> [(row: String, group: String, cells: [Command])] {
        var groups: [String] = []

        for command in commands where !groups.contains(command.group) {
            groups.append(command.group)
        }

        return groups.prefix(rows.count).enumerated().map { index, group in
            let cells = commands
                .filter { $0.group == group }
                .prefix(columns.count)
                .enumerated()
                .map { column, command -> Command in
                    var stamped = command
                    stamped.code = rows[index] + columns[column]

                    return stamped
                }

            return (row: rows[index], group: group.isEmpty ? "direct" : group, cells: cells)
        }
    }
}
