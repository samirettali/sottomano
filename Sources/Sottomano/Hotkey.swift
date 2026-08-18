import Carbon.HIToolbox

/// RegisterEventHotKey rather than a CGEventTap: a tap needs Accessibility and
/// goes deaf while macOS holds Secure Input, which is exactly when a password
/// field has the focus. The Carbon hotkey keeps firing and asks no permission.
final class Hotkey {
    private var reference: EventHotKeyRef?
    private var onPress: () -> Void = {}

    private static let signature = OSType(0x534D_414E) // 'SMAN'

    func register(key: String, modifiers: [String], id: UInt32 = 1, onPress: @escaping () -> Void) -> Bool {
        self.onPress = onPress

        guard let code = Hotkey.code(for: key) else { return false }

        var type = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }

            Unmanaged<Hotkey>.fromOpaque(context).takeUnretainedValue().onPress()

            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), nil)

        let status = RegisterEventHotKey(
            code,
            Hotkey.mask(modifiers),
            EventHotKeyID(signature: Hotkey.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &reference
        )

        return status == noErr
    }

    private static func code(for key: String) -> UInt32? {
        switch key {
        case "space": return UInt32(kVK_Space)
        case "return": return UInt32(kVK_Return)
        case "tab": return UInt32(kVK_Tab)
        default: return nil
        }
    }

    private static func mask(_ names: [String]) -> UInt32 {
        var mask: UInt32 = 0

        for name in names {
            switch name {
            case "command": mask |= UInt32(cmdKey)
            case "option": mask |= UInt32(optionKey)
            case "control": mask |= UInt32(controlKey)
            case "shift": mask |= UInt32(shiftKey)
            default: break
            }
        }

        return mask
    }
}
