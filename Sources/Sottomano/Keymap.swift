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
    var pick: Pick?
    /// One of the clipboard transforms: base64-decode, jwt, timestamp, …
    var transform: String?

    var isLayer: Bool { entries != nil }
}

/// A list to choose from, and what to do with the choice. `{}` in `run` is
/// replaced by the chosen value.
struct Pick: Decodable {
    /// One of the lists the app builds itself: clipboard, emoji, applications.
    var source: String?
    /// Otherwise a command, one choice per line: value, name and subtitle
    /// separated by tabs. Name and subtitle are optional.
    var list: [String]?
    var run: [String]?
    /// Alternative to `run`: type the value, or put it on the pasteboard.
    var type: Bool?
    var copy: Bool?
}
