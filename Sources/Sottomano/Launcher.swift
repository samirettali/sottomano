import AppKit
import SwiftUI

/// Owns the panel and what it is showing: either a layer of keys, or a prompt
/// asking for one line of text. A key press opens a layer, runs an action,
/// goes back, or closes.
/// A borderless window refuses to become key, and a window that never was key
/// never resigns it — which is why the panel could not tell that a click had
/// gone somewhere else. Typing kept working regardless: the key monitor is on
/// the application, not on the window.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class Launcher: NSObject, NSWindowDelegate {
    private let keymap: Keymap
    private let panel: NSPanel
    private var monitor: Any?
    /// Kept across renders: rebuilding it on every keystroke tore the panel
    /// down and put it back up, which is what the flashing was.
    private var hosting: NSHostingView<AnyView>?
    /// Whoever was in front when the panel opened. Activating this application
    /// takes the focus away, and nothing gives it back on its own.
    private var previous: NSRunningApplication?

    /// The layer on screen is the last one; everything before it is the way back.
    private var stack: [[Entry]] = []
    /// The name of each layer entered, so a panel can say where it is.
    private var titles: [String] = []
    /// Set while the panel is asking for text rather than showing a layer.
    private var prompt: Prompt?
    /// Set while the panel is a list to choose from.
    private var picker: Picker?
    /// Set while the panel is walking the filesystem.
    private var browser: Browsing?

    private struct Browsing {
        var directory: URL
        var query = ""
        var selected = 0
        var offset = 0
        var choices: [Choice] = []

        static let rows = 9

        var matches: [Choice] {
            choices
                .compactMap { choice -> (Choice, Int)? in
                    guard let score = Fuzzy.rank(query, name: choice.name, subtitle: "") else {
                        return nil
                    }

                    return (choice, score + choice.boost)
                }
                .sorted { $0.1 == $1.1 ? $0.0.name.count < $1.0.name.count : $0.1 > $1.1 }
                .map(\.0)
        }

        var visible: ArraySlice<Choice> {
            matches.dropFirst(offset).prefix(Browsing.rows)
        }
    }


    private struct Prompt {
        let title: String
        var text: String
        let submit: (String) -> Void
    }

    private struct Picker {
        var choices: [Choice]
        var query = ""
        var selected = 0
        var offset = 0
        /// The flag is true when shift+return picked it: copy rather than run.
        let commit: (Choice, Bool) -> Void

        static let rows = 8

        var matches: [Choice] {
            choices
                .compactMap { choice -> (Choice, Int)? in
                    guard let score = Fuzzy.rank(query, name: choice.name, subtitle: choice.subtitle) else {
                        return nil
                    }

                    return (choice, score + choice.boost)
                }
                .sorted { first, second in
                    if first.1 != second.1 { return first.1 > second.1 }

                    // equal score means the query matched both the same way, so
                    // prefer the shorter name: the query covers more of it
                    return first.0.name.count < second.0.name.count
                }
                .map(\.0)
        }

        var visible: ArraySlice<Choice> {
            matches.dropFirst(offset).prefix(Picker.rows)
        }
    }

    init(keymap: Keymap) {
        self.keymap = keymap

        panel = KeyPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .mainMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]

        super.init()

        panel.delegate = self

        // cmd+tab moves the application without a click, and the panel has to
        // hear about that too
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible else { return }

                self.hide()
            }
        }
    }

    /// A click anywhere else takes the key window with it, and that is the same
    /// thing as being done with the panel. It only works because `KeyPanel` lets
    /// a borderless window become key at all.
    nonisolated func windowDidResignKey(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard panel.isVisible else { return }

            hide()
        }
    }

    /// Redraws what is on screen, for the theme switcher.
    func refresh() {
        if panel.isVisible { show() }
    }

    /// Runs one entry without opening the panel, for a binding of its own.
    func trigger(_ entry: Entry) {
        run(entry)
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            stack = [keymap.entries]
            titles = []
            path = []
            prompt = nil
            show()
        }
    }

    // MARK: - Panel

    private func show() {
        if let prompt {
            present(PromptView(title: prompt.title, text: prompt.text))
        } else if let browser {
            present(
                PickerView(
                    query: browser.query,
                    matches: Array(browser.visible),
                    selected: browser.selected - browser.offset,
                    header: Browser.shorten(browser.directory)
                )
            )
        } else if let picker {
            present(
                PickerView(
                    query: picker.query,
                    matches: Array(picker.visible),
                    selected: picker.selected - picker.offset
                )
            )
        } else if !stack.isEmpty {
            present(
                LauncherView(
                    tree: LauncherView.tree(of: keymap.entries),
                    path: path,
                    title: titles.last
                )
            )
        }
    }

    /// The keys taken to reach the layer on screen.
    private var path: [String] = []

    private func present(_ view: some View) {
        let arriving = !panel.isVisible

        if arriving {
            previous = NSWorkspace.shared.frontmostApplication
        }
        let root = AnyView(view.environment(\.arriving, arriving))

        let hosting: NSHostingView<AnyView>

        if let existing = self.hosting {
            hosting = existing
            hosting.rootView = root
        } else {
            hosting = NSHostingView(rootView: root)
            self.hosting = hosting
            panel.contentView = hosting
        }

        hosting.layout()
        panel.setContentSize(hosting.fittingSize)
        place()
        // the shadow is cached from the previous size, and the corners of the
        // old one show through as black lines around the new panel
        panel.invalidateShadow()

        panel.orderFrontRegardless()
        NSApp.activate()
        panel.makeKey()

        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event)

                return nil
            }
        }
    }

    /// Hangs from one line a third of the way down, so the top edge stays put
    /// however many rows the layer has.
    private func place() {
        guard let screen = NSScreen.main else { return }

        let frame = screen.frame
        let size = panel.frame.size
        let top = frame.maxY - frame.height * 0.32

        panel.setFrameOrigin(
            NSPoint(
                x: (frame.width - size.width).rounded() / 2 + frame.minX,
                y: (top - size.height).rounded()
            )
        )
    }

    private func hide() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }

        monitor = nil
        hosting = nil
        panel.contentView = nil
        panel.orderOut(nil)

        // whatever was in front gets the focus back, which is also what makes a
        // typed action land in the window it was meant for
        if let previous, previous != .current {
            previous.activate()
        }

        previous = nil
        stack = []
        titles = []
        path = []
        prompt = nil
        picker = nil
        browser = nil
    }

    // MARK: - Keys

    private func handle(_ event: NSEvent) {
        if event.keyCode == keyEscape {
            hide()
            return
        }

        #if DEBUG
            // ctrl+1…8 swaps the theme under comparison, in place. It is read
            // before the mode does anything, so it works in a flat theme too,
            // where the plain digits are codes of their own.
            if event.modifierFlags.contains(.control),
               let digit = event.charactersIgnoringModifiers.flatMap(Int.init),
               digit >= 1, digit <= Variant.allCases.count {
                Variant.select(Variant.allCases[digit - 1])
                NotificationCenter.default.post(name: .variantChanged, object: nil)
                show()

                return
            }
        #endif

        if prompt != nil {
            handlePrompt(event)
        } else if picker != nil {
            handlePicker(event)
        } else if browser != nil {
            handleBrowser(event)
        } else {
            handleLayer(event)
        }
    }

    private func handlePicker(_ event: NSEvent) {
        guard var current = picker else { return }

        let flags = event.modifierFlags
        let matches = current.matches

        if event.keyCode == keyReturn {
            guard current.selected < matches.count else { return }

            let choice = matches[current.selected]
            let commit = current.commit

            hide()
            commit(choice, flags.contains(.shift))

            return
        }

        if event.keyCode == keyDown || (flags.contains(.control) && event.charactersIgnoringModifiers == "n") {
            current.selected += 1
        } else if event.keyCode == keyUp || (flags.contains(.control) && event.charactersIgnoringModifiers == "p") {
            current.selected -= 1
        } else if event.keyCode == keyDelete {
            _ = current.query.popLast()
            current.selected = 0
        } else if flags.contains(.control), event.charactersIgnoringModifiers == "u" {
            current.query = ""
            current.selected = 0
        } else if flags.contains(.command), event.charactersIgnoringModifiers == "v" {
            current.query += NSPasteboard.general.string(forType: .string) ?? ""
            current.selected = 0
        } else if !flags.contains(.command), !flags.contains(.control), !flags.contains(.option),
                  let typed = event.characters, !typed.isEmpty {
            current.query += typed
            current.selected = 0
        } else {
            return
        }

        current.selected = max(0, min(current.selected, max(current.matches.count - 1, 0)))

        if current.selected < current.offset {
            current.offset = current.selected
        } else if current.selected >= current.offset + Picker.rows {
            current.offset = current.selected - Picker.rows + 1
        }

        picker = current
        show()
    }

    /// Return goes in, delete on an empty query comes back out, and the arrows
    /// do the same thing for a hand that is already on them.
    private func handleBrowser(_ event: NSEvent) {
        guard var current = browser else { return }

        let flags = event.modifierFlags
        let matches = current.matches
        let chosen = current.selected < matches.count ? matches[current.selected] : nil

        if event.keyCode == keyReturn || event.keyCode == keyRight {
            guard let chosen else { return }

            Frecency.shared.remember(chosen.value)

            let url = URL(fileURLWithPath: chosen.value)

            // shift reveals it where a file manager would, for the times only
            // the Finder will do
            if flags.contains(.shift) {
                hide()
                NSWorkspace.shared.activateFileViewerSelecting([url])

                return
            }

            if chosen.isDirectory, event.keyCode == keyReturn || event.keyCode == keyRight {
                browser = enter(url)
                show()

                return
            }

            hide()
            NSWorkspace.shared.open(url)

            return
        }

        if event.keyCode == keyDelete || event.keyCode == keyLeft {
            if !current.query.isEmpty, event.keyCode == keyDelete {
                _ = current.query.popLast()
                current.selected = 0
            } else {
                let parent = current.directory.deletingLastPathComponent()

                guard parent != current.directory else { return }

                browser = enter(parent)
                show()

                return
            }
        } else if event.keyCode == keyDown || (flags.contains(.control) && event.charactersIgnoringModifiers == "n") {
            current.selected += 1
        } else if event.keyCode == keyUp || (flags.contains(.control) && event.charactersIgnoringModifiers == "p") {
            current.selected -= 1
        } else if flags.contains(.control), event.charactersIgnoringModifiers == "u" {
            current.query = ""
            current.selected = 0
        } else if !flags.contains(.command), !flags.contains(.control), !flags.contains(.option),
                  let typed = event.characters, !typed.isEmpty {
            current.query += typed
            current.selected = 0
        } else {
            return
        }

        current.selected = max(0, min(current.selected, max(current.matches.count - 1, 0)))

        if current.selected < current.offset {
            current.offset = current.selected
        } else if current.selected >= current.offset + Browsing.rows {
            current.offset = current.selected - Browsing.rows + 1
        }

        browser = current
        show()
    }

    private func enter(_ directory: URL) -> Browsing {
        Browsing(directory: directory, choices: Browser.read(directory))
    }

    private func handleLayer(_ event: NSEvent) {
        guard let entries = stack.last else { return }

        // delete goes back a layer instead of out; at the root there is nothing
        // above to go back to
        if event.keyCode == keyDelete {
            if stack.count > 1 {
                stack.removeLast()
                titles.removeLast()
                path.removeLast()
                show()
            }

            return
        }

        guard let typed = event.charactersIgnoringModifiers?.lowercased() else { return }

        let shift = event.modifierFlags.contains(.shift)

        guard let match = entries.first(where: { $0.key == typed && ($0.shift ?? false) == shift }) else {
            return
        }

        if let next = match.entries {
            stack.append(next)
            titles.append(match.name ?? "")
            path.append(match.key)
            show()

            return
        }

        run(match)
    }

    private func handlePrompt(_ event: NSEvent) {
        guard var current = prompt else { return }

        if event.keyCode == keyReturn {
            let submit = current.submit
            let text = current.text

            hide()

            if !text.isEmpty {
                submit(text)
            }

            return
        }

        if event.keyCode == keyDelete {
            _ = current.text.popLast()
            prompt = current
            show()

            return
        }

        let flags = event.modifierFlags

        if flags.contains(.control), event.charactersIgnoringModifiers == "u" {
            current.text = ""
            prompt = current
            show()

            return
        }

        if flags.contains(.command), event.charactersIgnoringModifiers == "v" {
            current.text += NSPasteboard.general.string(forType: .string) ?? ""
            prompt = current
            show()

            return
        }

        guard !flags.contains(.command), !flags.contains(.control), !flags.contains(.option),
              let typed = event.characters, !typed.isEmpty
        else { return }

        current.text += typed
        prompt = current
        show()
    }

    // MARK: - Actions

    private func run(_ entry: Entry) {
        // A search asks first and the panel stays up; everything else acts on
        // the app underneath, which only has the focus once the panel is gone.
        if let template = entry.search {
            // shift searches whatever is selected instead of asking for it
            if entry.shift == true {
                hide()
                selection { query in
                    Sottomano.open(template: template, query: query)
                }

                return
            }

            let host = URL(string: template.replacingOccurrences(of: "{}", with: ""))?.host ?? "the web"

            prompt = Prompt(title: "search \(host)", text: "") { query in
                Sottomano.open(template: template, query: query)
            }

            show()

            return
        }

        if let start = entry.browse {
            browser = enter(Browser.expand(start))
            show()

            return
        }

        if let pick = entry.pick {
            open(pick)

            return
        }

        hide()

        if let app = entry.launch {
            // `open -a` finds the app wherever it lives and matches the name
            // the way Spotlight does
            spawn(["/usr/bin/open", "-a", app])
        }

        if let url = entry.url, let parsed = URL(string: url) {
            NSWorkspace.shared.open(parsed)
        }

        if let command = entry.shell {
            spawn(command)
        }

        if let text = entry.type {
            type(text)
        }

        if let command = entry.typeOutput {
            type(output(of: command).trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if let name = entry.transform {
            Toast.show(Transform.apply(name))
        }

        if let layout = entry.display {
            Toast.show(Display.arrange(layout))
        }

        if entry.layout != nil {
            Toast.show(InputSource.next(), seconds: 1)
        }
    }

    /// macOS exposes no selection, so the only way to read one is to copy it and
    /// put the pasteboard back. The panel is already down by the time this runs,
    /// which is what gives the app underneath the focus that ⌘C needs.
    private func selection(_ use: @escaping (String) -> Void) {
        let board = NSPasteboard.general
        let saved = board.string(forType: .string)
        let stamp = board.changeCount

        Clipboard.shared.pause()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let source = CGEventSource(stateID: .hidSystemState)

            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: down)
                event?.flags = .maskCommand
                event?.post(tap: .cghidEventTap)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let copied = board.changeCount != stamp ? board.string(forType: .string) : nil

                if let saved {
                    board.clearContents()
                    board.setString(saved, forType: .string)
                }

                Clipboard.shared.resume()

                guard let copied, !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    Toast.show("nothing selected")
                    return
                }

                use(copied.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    private func open(_ pick: Pick) {
        let choices: [Choice]

        switch pick.source {
        case "clipboard": choices = Clipboard.shared.choices()
        case "emoji": choices = Emoji.choices()
        case "applications": choices = Applications.choices()
        default: choices = parse(output(of: pick.list ?? []))
        }

        guard !choices.isEmpty else {
            hide()
            return
        }

        picker = Picker(choices: choices) { [weak self] choice, alternate in
            guard let self else { return }

            Frecency.shared.remember(choice.value)

            // shift+return copies rather than acting, which is the escape hatch
            // for anywhere the action would be wrong
            if alternate || pick.copy == true {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(choice.value, forType: .string)

                return
            }

            if pick.type == true {
                self.type(choice.value)

                return
            }

            if let command = pick.typeOutput {
                let text = self.output(of: command.map { $0.replacingOccurrences(of: "{}", with: choice.value) })

                self.type(text.trimmingCharacters(in: .whitespacesAndNewlines))

                return
            }

            if let command = pick.run {
                self.spawn(command.map { $0.replacingOccurrences(of: "{}", with: choice.value) })
            }
        }

        show()
    }

    /// One choice per line: value, name and subtitle separated by tabs. A line
    /// without tabs is all three at once, which is what a plain list gives.
    private func parse(_ text: String) -> [Choice] {
        text.split(separator: "\n").map { line in
            let fields = line.components(separatedBy: "\t")

            return Choice(
                value: fields[0],
                name: fields.count > 1 ? fields[1] : fields[0],
                subtitle: fields.count > 2 ? fields[2] : "",
                boost: Frecency.shared.score(fields[0])
            )
        }
    }

    private func spawn(_ command: [String]) {
        guard let first = command.first else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: first)
        process.arguments = Array(command.dropFirst())

        try? process.run()
    }

    private func output(of command: [String]) -> String {
        guard let first = command.first else { return "" }

        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: first)
        process.arguments = Array(command.dropFirst())
        process.standardOutput = pipe

        guard (try? process.run()) != nil else { return "" }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return String(data: data, encoding: .utf8) ?? ""
    }

    /// The one action that needs Accessibility: posting a synthetic event is
    /// privileged, and pasting instead would be a synthetic ⌘V all the same.
    /// The delay lets the app that had the focus take it back first.
    private func type(_ text: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let source = CGEventSource(stateID: .hidSystemState)

            for character in text.unicodeScalars {
                var unit = UniChar(character.value)

                for down in [true, false] {
                    let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                    event?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
                    event?.post(tap: .cghidEventTap)
                }
            }
        }
    }
}

private func open(template: String, query: String) {
    let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query

    if let url = URL(string: template.replacingOccurrences(of: "{}", with: escaped)) {
        NSWorkspace.shared.open(url)
    }
}

private let keyReturn: UInt16 = 36
private let keyEscape: UInt16 = 53
private let keyDelete: UInt16 = 51
private let keyUp: UInt16 = 126
private let keyDown: UInt16 = 125
private let keyLeft: UInt16 = 123
private let keyRight: UInt16 = 124
