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
        if let app = entry.launch {
            NSWorkspace.shared.open(
                URL(fileURLWithPath: "/Applications/\(app).app"),
                configuration: NSWorkspace.OpenConfiguration()
            )
        }

        if let url = entry.url, let parsed = URL(string: url) {
            NSWorkspace.shared.open(parsed)
        }

        if let command = entry.shell, let first = command.first {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: first)
            process.arguments = Array(command.dropFirst())
            try? process.run()
        }
    }
}

private let kVK_Escape: UInt16 = 53
private let kVK_Delete: UInt16 = 51
