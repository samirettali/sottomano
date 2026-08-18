import Carbon.HIToolbox

/// RegisterEventHotKey rather than a CGEventTap: a tap needs Accessibility and
/// goes deaf while macOS holds Secure Input, which is exactly when a password
/// field has the focus. The Carbon hotkey keeps firing and asks no permission.
///
/// One handler for every hotkey, dispatching on the id Carbon reports. An
/// application event handler hears every hotkey, not just the one registered
/// alongside it, so installing one per hotkey would run every binding at once.
@MainActor
enum Hotkeys {
    private static let signature = OSType(0x534D_414E) // 'SMAN'

    private static var actions: [UInt32: () -> Void] = [:]
    private static var references: [EventHotKeyRef?] = []
    private static var installed = false

    static func register(key: String, modifiers: [String], onPress: @escaping () -> Void) -> Bool {
        guard let code = Hotkeys.code(for: key) else { return false }

        install()

        let id = UInt32(actions.count + 1)
        var reference: EventHotKeyRef?

        let status = RegisterEventHotKey(
            code,
            Hotkeys.mask(modifiers),
            EventHotKeyID(signature: signature, id: id),
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr else { return false }

        actions[id] = onPress
        references.append(reference)

        return true
    }

    private static func install() {
        guard !installed else { return }

        installed = true

        var type = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var identifier = EventHotKeyID()

            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &identifier
            )

            // Carbon delivers this on the main thread, and staying on it is
            // what keeps the panel up in the same frame as the keystroke
            MainActor.assumeIsolated {
                Hotkeys.dispatch(identifier)
            }

            return noErr
        }, 1, &type, nil, nil)
    }

    private static func dispatch(_ identifier: EventHotKeyID) {
        guard identifier.signature == signature else { return }

        actions[identifier.id]?()
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
