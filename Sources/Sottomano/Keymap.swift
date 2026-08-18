import Foundation

/// The keymap is data: nix writes the JSON, so adding an entry is a rebuild of
/// the config and not of the app.
struct Keymap: Decodable {
    var hotkey: Hotkey
    var entries: [Entry]

    struct Hotkey: Decodable {
        var key: String
        var modifiers: [String]
    }

    static func load() throws -> Keymap {
        let url = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".config/sottomano/keymap.json")

        return try JSONDecoder().decode(Keymap.self, from: Data(contentsOf: url))
    }
}

struct Entry: Decodable {
    var key: String
    /// Held on top of the key. Only "shift" so far, for the variants.
    var shift: Bool?
    /// No name means the entry binds but stays out of the panel.
    var name: String?
    var entries: [Entry]?

    var launch: String?
    var url: String?
    var shell: [String]?
    /// Literal text, typed into whatever had the focus.
    var type: String?
    /// The same, but the text is the command's output: a timestamp, a uuid.
    var typeOutput: [String]?
    /// A URL with `{}` where the query goes. Asks for the query first.
    var search: String?

    var isLayer: Bool { entries != nil }
}
