import AppKit
import ServiceManagement

/// A status item, because an app with no window has nowhere else to put the two
/// things every app is expected to offer: start with the machine, and stop.
@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    static let shared = MenuBar()

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    private lazy var toggle: NSSwitch = {
        let control = NSSwitch()
        control.controlSize = .small
        control.target = self
        control.action = #selector(toggleLogin)

        return control
    }()

    func start() {
        item.button?.image = NSImage(
            systemSymbolName: "command",
            accessibilityDescription: "Sottomano"
        )
        item.button?.image?.isTemplate = true

        menu.delegate = self
        menu.addItem(login())
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: ""
            )
        )

        item.menu = menu
    }

    /// A switch rather than a tick: it says what it will do next as well as what
    /// it is, and it stays under the pointer that just flipped it.
    private func login() -> NSMenuItem {
        let label = NSTextField(labelWithString: "Open at login")
        label.font = .menuFont(ofSize: 0)

        // the label takes whatever is left over, which is what holds the switch
        // against the right edge of the menu
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [label, toggle])
        row.orientation = .horizontal
        row.spacing = 24
        row.edgeInsets = NSEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        row.widthAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true

        let item = NSMenuItem()
        item.view = row

        return item
    }

    /// Read on every open rather than kept: the login state can be changed from
    /// System Settings, and a switch that lies is worse than no switch.
    func menuNeedsUpdate(_ menu: NSMenu) {
        toggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Toast.show("open at login: \(error.localizedDescription)", seconds: 4)
        }

        toggle.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
