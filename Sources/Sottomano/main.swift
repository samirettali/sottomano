import AppKit

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let keymap: Keymap

do {
    keymap = try Keymap.load()
} catch {
    FileHandle.standardError.write("sottomano: \(error)\n".data(using: .utf8)!)
    exit(1)
}

if let theme = keymap.theme {
    Theme.current = theme
}

MenuBar.shared.start()
Clipboard.shared.start()

if let command = keymap.hooks?.inputSourceChanged {
    InputSource.observe(command)
}

let launcher = Launcher(keymap: keymap)

@MainActor
func bind(_ keymap: Keymap) {
    CapsEscape.shared.configure(
        capsEscape: keymap.capsEscape == true,
        controlBracketEscape: keymap.controlBracketEscape == true
    )
    if (keymap.capsEscape == true || keymap.controlBracketEscape == true),
       !CapsEscape.shared.working {
        Toast.show("escape mappings: no accessibility", seconds: 6)
    }

    Hotkeys.reset()

    guard Hotkeys.register(
        key: keymap.hotkey.key,
        modifiers: keymap.hotkey.modifiers,
        onPress: { launcher.toggle() }
    ) else {
        FileHandle.standardError.write("sottomano: could not register the hotkey\n".data(using: .utf8)!)
        exit(1)
    }

    // each extra binding runs one entry straight away, without the panel
    for binding in keymap.hotkeys ?? [] {
        _ = Hotkeys.register(
            key: binding.key,
            modifiers: binding.modifiers,
            onPress: { launcher.trigger(binding.entry) }
        )
    }
}

bind(keymap)

// written again, taken again: the theme, the bindings and the hotkeys all
Config.shared.watch { fresh in
    if let theme = fresh.theme { Theme.current = theme }

    launcher.reload(fresh)
    bind(fresh)
}

application.run()
