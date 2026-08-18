import AppKit

/// Control released without anything else having been pressed is escape;
/// control pressed together with another key is control. macOS already maps caps
/// lock to control, so this is what makes caps lock carry both.
///
/// Escape cannot arrive before the release, and no implementation of a
/// dual-role key can make it: until the key is let go it may still turn out to
/// be a modifier.
///
/// The one thing here that needs an event tap, and the one thing that stops
/// while macOS holds Secure Input — the launcher is unaffected, since its hotkey
/// and its panel never go through a tap.
@MainActor
final class CapsEscape {
    static let shared = CapsEscape()

    private var tap: CFMachPort?
    private var held = false
    private var armed = false

    /// True when the tap is running and allowed to see events.
    var working: Bool { tap != nil && AXIsProcessTrusted() }

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

            return
        }

        // No timeout on purpose: how long it was held says nothing, what says
        // everything is whether anything else was pressed while it was. A tap
        // is a tap however slow it was.
        if armed {
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
