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

application.run()
