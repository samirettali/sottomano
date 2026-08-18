import AppKit

/// The emoji list, written next to the keymap by nix from the same emojione
/// data the Hammerspoon picker used.
@MainActor
enum Emoji {
    private struct Item: Decodable {
        var glyph: String
        var name: String
        var keywords: String
    }

    static func choices() -> [Choice] {
        let url = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".config/sottomano/emoji.json")

        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([Item].self, from: data)
        else { return [] }

        return items.map {
            Choice(
                value: $0.glyph,
                name: "\($0.glyph)  \($0.name)",
                subtitle: $0.keywords,
                boost: Frecency.shared.score($0.glyph)
            )
        }
    }
}

extension Applications {
    /// The application's own icon, found the same way `open -a` finds the app.
    static func icon(named name: String) -> NSImage? {
        for root in Applications.roots {
            let path = root + "/" + name + ".app"

            if FileManager.default.fileExists(atPath: path) {
                return NSWorkspace.shared.icon(forFile: path)
            }
        }

        return nil
    }
}

/// Every application macOS knows about, which is what Spotlight lists.
@MainActor
enum Applications {
    static let roots = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Library/CoreServices/Applications",
        FileManager.default.homeDirectoryForCurrentUser.path + "/Applications",
    ]

    static func choices() -> [Choice] {
        var found: [Choice] = []
        var seen: Set<String> = []

        for root in Applications.roots {
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []

            for entry in contents where entry.hasSuffix(".app") {
                let name = String(entry.dropLast(4))

                guard seen.insert(name).inserted else { continue }

                found.append(
                    Choice(
                        value: name,
                        name: name,
                        subtitle: root.replacingOccurrences(
                            of: FileManager.default.homeDirectoryForCurrentUser.path,
                            with: "~"
                        ),
                        boost: Frecency.shared.score(name)
                    )
                )
            }
        }

        // Finder has no bundle in /Applications, and it is the one everybody
        // reaches for
        if seen.insert("Finder").inserted {
            found.append(Choice(value: "Finder", name: "Finder", subtitle: "/System/Library/CoreServices"))
        }

        return found
    }
}
