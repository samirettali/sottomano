import AppKit

/// The optional Control-to-Escape mappings share one event tap. They need
/// Accessibility and stop during Secure Input; the launcher is unaffected.
@MainActor
final class CapsEscape {
    static let shared = CapsEscape()

    private var tap: CFMachPort?
    private var held = false
    private var armed = false
    private var bracketHeld = false
    private var capsEscape: Bool
    private var controlBracketEscape: Bool

    init(capsEscape: Bool = false, controlBracketEscape: Bool = false) {
        self.capsEscape = capsEscape
        self.controlBracketEscape = controlBracketEscape
    }

    /// True when the tap is running and allowed to see events.
    var working: Bool { tap != nil && AXIsProcessTrusted() }

    func configure(capsEscape: Bool, controlBracketEscape: Bool) {
        if self.capsEscape != capsEscape { armed = false }
        self.capsEscape = capsEscape
        self.controlBracketEscape = controlBracketEscape

        // Keep an existing tap so a remapped key's release is still paired with
        // its press if the configuration changes while the key is held.
        guard capsEscape || controlBracketEscape, tap == nil else { return }
        start()
    }

    private func start() {
        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, _ in
                MainActor.assumeIsolated {
                    CapsEscape.shared.handle(type, event)
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        )

        guard let tap else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func handle(_ type: CGEventType, _ event: CGEvent) {
        // The system switches a tap off if it ever takes too long.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            armed = false
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        if type == .keyDown { armed = false }

        if (type == .keyDown || type == .keyUp),
           event.getIntegerValueField(.keyboardEventKeycode) == 33 {
            if type == .keyDown, controlBracketEscape, event.flags.contains(.maskControl) {
                bracketHeld = true
            }

            if bracketHeld {
                // Rewrite in place: no original bracket reaches the app and no
                // posted event needs to make another trip through the tap. Pair
                // the release even if Control was released first; repeats stay Escape.
                event.setIntegerValueField(.keyboardEventKeycode, value: 53)
                event.flags = []
                if type == .keyUp { bracketHeld = false }
            }
        }

        guard type == .flagsChanged else { return }

        let control = event.flags.contains(.maskControl)

        if control == held {
            // Another modifier joined Control, so this is a combination too.
            armed = false
            return
        }

        held = control

        if control {
            armed = capsEscape
            return
        }

        // No duration threshold: a tap is a tap however slow it was.
        if armed { escape() }
        armed = false
    }

    private func escape() {
        let source = CGEventSource(stateID: .hidSystemState)

        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: down)
            event?.flags = []
            event?.post(tap: .cghidEventTap)
        }
    }
}
