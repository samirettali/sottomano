import Foundation

/// The keymap is data: nix writes the JSON, so adding an entry is a rebuild of
/// the config and not of the app.
struct Keymap: Decodable {
    /// How the panel looks and how it moves as you go deeper.
    var theme: Theme?
    /// Control tapped on its own becomes Escape. Needs Accessibility.
    var capsEscape: Bool?
    /// Control+[ becomes Escape on keydown. Opt-in; needs Accessibility.
    var controlBracketEscape: Bool?
    /// Commands run when something changes rather than when a key is pressed.
    var hooks: Hooks?

    struct Hooks: Decodable {
        /// `{}` is the identifier of the layout now in use.
        var inputSourceChanged: [String]?
    }
    var hotkey: Hotkey
    /// Bindings that skip the panel and run one entry straight away, which is
    /// where the applications picker lives.
    var hotkeys: [Binding]?
    var entries: [Entry]

    struct Binding: Decodable {
        var key: String
        var modifiers: [String]
        var entry: Entry
    }

    struct Hotkey: Decodable {
        var key: String
        var modifiers: [String]
    }

    /// `SOTTOMANO_KEYMAP` points the app at another file, which is how a keymap
    /// is tried out before it is declared: the deployed one is a read-only store
    /// symlink, so iterating on it would mean a rebuild of the whole machine.
    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["SOTTOMANO_KEYMAP"], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }

        return folder.appendingPathComponent("keymap.json")
    }

    static let folder = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".config/sottomano")

    static func load() throws -> Keymap {
        try JSONDecoder().decode(Keymap.self, from: Data(contentsOf: url))
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
    /// A directory to start walking from, `~` included.
    var browse: String?
    /// Cycles the keyboard layout. Only "next" so far.
    var layout: String?
    /// Takes a colour off the screen with the loupe. Only "hex" so far, which
    /// is what it puts on the pasteboard.
    var color: String?
    /// One of the monitor arrangements: docked, side-by-side, external.
    var display: String?

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
    /// A name to keep the answer under. With one, the list on disk is shown at
    /// once and the command refreshes it behind — which is the difference
    /// between a panel that opens and a panel that waits for the tailnet.
    var cache: String?
    /// Runs the command and types its output, which is how a password reaches
    /// the field without the launcher ever holding it. Alongside `run` it
    /// becomes the second verb of the same row: return runs, shift+return types.
    var typeOutput: [String]?
    /// Alternative to `run`: type the value, or put it on the pasteboard.
    var type: Bool?
    var copy: Bool?
}
