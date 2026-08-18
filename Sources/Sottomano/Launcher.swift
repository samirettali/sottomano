import AppKit
import SwiftUI

/// Owns the panel and what it is showing: either a layer of keys, or a prompt
/// asking for one line of text. A key press opens a layer, runs an action,
/// goes back, or closes.
@MainActor
final class Launcher {
    private let keymap: Keymap
    private let panel: NSPanel
    private var monitor: Any?

    /// The layer on screen is the last one; everything before it is the way back.
    private var stack: [[Entry]] = []
    /// Set while the panel is asking for text rather than showing a layer.
    private var prompt: Prompt?

    private struct Prompt {
        let title: String
        var text: String
        let submit: (String) -> Void
    }

    init(keymap: Keymap) {
        self.keymap = keymap

        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .mainMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            stack = [keymap.entries]
            prompt = nil
            show()
        }
    }

    // MARK: - Panel

    private func show() {
        if let prompt {
            present(PromptView(title: prompt.title, text: prompt.text))
        } else if let entries = stack.last {
            present(LauncherView(rows: rows(of: entries)))
        }
    }

    private func rows(of entries: [Entry]) -> [LauncherView.Row] {
        entries.compactMap { entry in
            guard let name = entry.name, entry.shift != true else { return nil }

            return LauncherView.Row(key: entry.key, name: name, isLayer: entry.isLayer)
        }
    }

    private func present(_ view: some View) {
        let hosting = NSHostingView(rootView: view)
        hosting.layout()

        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        place()

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
        stack = []
        prompt = nil
        panel.orderOut(nil)
    }

    // MARK: - Keys

    private func handle(_ event: NSEvent) {
        if event.keyCode == keyEscape {
            hide()
            return
        }

        if prompt != nil {
            handlePrompt(event)
        } else {
            handleLayer(event)
        }
    }

    private func handleLayer(_ event: NSEvent) {
        guard let entries = stack.last else { return }

        // delete goes back a layer instead of out; at the root there is nothing
        // above to go back to
        if event.keyCode == keyDelete {
            if stack.count > 1 {
                stack.removeLast()
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
            let host = URL(string: template.replacingOccurrences(of: "{}", with: ""))?.host ?? "the web"

            prompt = Prompt(title: "search \(host)", text: "") { query in
                open(template: template, query: query)
            }

            show()

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
