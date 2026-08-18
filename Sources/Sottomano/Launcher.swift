import AppKit
import SwiftUI

/// Owns the panel and the layer the panel is showing. One key press either
/// opens a layer, runs an action, goes back, or closes.
@MainActor
final class Launcher {
    private let keymap: Keymap
    private let panel: NSPanel
    /// The layer on screen is the last one; everything before it is the way back.
    private var stack: [[Entry]] = []
    private var monitor: Any?

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
            show()
        }
    }

    private func show() {
        guard let entries = stack.last else { return }

        let rows = entries.compactMap { entry -> LauncherView.Row? in
            guard let name = entry.name, entry.shift != true else { return nil }

            return LauncherView.Row(key: entry.key, name: name, isLayer: entry.isLayer)
        }

        let view = NSHostingView(rootView: LauncherView(rows: rows))
        view.layout()

        panel.contentView = view
        panel.setContentSize(view.fittingSize)
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
        panel.orderOut(nil)
    }

    private func handle(_ event: NSEvent) {
        guard let entries = stack.last else { return }

        if event.keyCode == kVK_Escape {
            hide()
            return
        }

        // delete goes back a layer instead of out; at the root there is nothing
        // above to go back to
        if event.keyCode == kVK_Delete {
            if stack.count > 1 {
                stack.removeLast()
                show()
            }

            return
        }

        guard let typed = event.charactersIgnoringModifiers?.lowercased() else { return }

        let shift = event.modifierFlags.contains(.shift)
        let match = entries.first { $0.key == typed && ($0.shift ?? false) == shift }

        guard let match else { return }

        if let next = match.entries {
            stack.append(next)
            show()

            return
        }

        // hidden first: the action runs against the app that had the focus, and
        // that only comes back once the panel is gone
        hide()
        run(match)
    }

    private func run(_ entry: Entry) {
        // `open -a` rather than a path: it finds the app wherever it lives and
        // matches on the name the way Spotlight does
        if let app = entry.launch {
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
    }

    private func spawn(_ command: [String]) {
        guard let first = command.first else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: first)
        process.arguments = Array(command.dropFirst())

        try? process.run()
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

private let kVK_Escape: UInt16 = 53
private let kVK_Delete: UInt16 = 51
