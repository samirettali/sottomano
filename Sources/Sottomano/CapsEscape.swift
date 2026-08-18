import AppKit

/// Control tapped on its own is escape; control held with another key is
/// control. macOS already maps caps lock to control, so this is what makes caps
/// lock carry both.
///
/// The one thing here that needs an event tap, and the one thing that stops
/// while macOS holds Secure Input — the launcher is unaffected, since its hotkey
/// and its panel never go through a tap.
@MainActor
final class CapsEscape {
    static let shared = CapsEscape()

    /// Held longer than this and it was meant as a modifier, not as escape.
    private let hold: TimeInterval = 0.15

    private var tap: CFMachPort?
    private var held = false
    private var armed = false
    private var since = Date()

    func start() {
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)

        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
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

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        // the system switches a tap off if it ever takes too long, and a tap
        // that is off looks exactly like a feature that stopped working
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }

            return
        }

        // anything pressed while control is down means it was a modifier
        if type == .keyDown {
            armed = false

            return
        }

        guard type == .flagsChanged else { return }

        let control = event.flags.contains(.maskControl)

        if control == held {
            // another modifier joined control, so this is a combination too
            armed = false

            return
        }

        held = control

        if control {
            armed = true
            since = Date()

            return
        }

        if armed, Date().timeIntervalSince(since) < hold {
            escape()
        }

        armed = false
    }

    private func escape() {
        let source = CGEventSource(stateID: .hidSystemState)

        for down in [true, false] {
            CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: down)?
                .post(tap: .cghidEventTap)
        }
    }
}
