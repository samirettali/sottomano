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

Clipboard.shared.start()

let launcher = Launcher(keymap: keymap)
let hotkey = Hotkey()

guard hotkey.register(
    key: keymap.hotkey.key,
    modifiers: keymap.hotkey.modifiers,
    onPress: { launcher.toggle() }
) else {
    FileHandle.standardError.write("sottomano: could not register the hotkey\n".data(using: .utf8)!)
    exit(1)
}

// each extra binding runs one entry straight away, without the panel
var extras: [Hotkey] = []

for (index, binding) in (keymap.hotkeys ?? []).enumerated() {
    let hotkey = Hotkey()

    _ = hotkey.register(
        key: binding.key,
        modifiers: binding.modifiers,
        id: UInt32(index + 2),
        onPress: { launcher.trigger(binding.entry) }
    )

    extras.append(hotkey)
}

application.run()
