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

    /// Carbon binds a physical key, so these are the ANSI positions rather than
    /// what the current layout prints on them. That is what a hotkey wants: it
    /// stays under the same finger when the layout changes.
    private static let codes: [String: Int] = [
        "space": kVK_Space, "return": kVK_Return, "tab": kVK_Tab, "delete": kVK_Delete,
        "escape": kVK_Escape, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
        ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash,
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
        "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
        "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
        "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
    ]

    private static func code(for key: String) -> UInt32? {
        codes[key.lowercased()].map(UInt32.init)
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
