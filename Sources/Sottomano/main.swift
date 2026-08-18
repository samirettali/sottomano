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

if let theme = keymap.theme, let variant = Variant(rawValue: theme) {
    Variant.configured = variant
}

Clipboard.shared.start()

if keymap.capsEscape == true {
    CapsEscape.shared.start()
}

if let command = keymap.hooks?.inputSourceChanged {
    InputSource.observe(command)
}

let launcher = Launcher(keymap: keymap)

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

#if DEBUG
    VariantSwitcher.show { launcher.refresh() }
#endif

application.run()
