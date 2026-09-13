import AppKit
import Testing
@testable import Sottomano

@MainActor
struct CapsEscapeTests {
    private func key(_ code: CGKeyCode, down: Bool = true, flags: CGEventFlags = []) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        event.flags = flags
        return event
    }

    private func code(_ event: CGEvent) -> Int64 {
        event.getIntegerValueField(.keyboardEventKeycode)
    }

    @Test func disabledByDefault() throws {
        let keymap = try JSONDecoder().decode(Keymap.self, from: Data(
            #"{"hotkey":{"key":"space","modifiers":["command"]},"entries":[]}"#.utf8
        ))
        #expect(keymap.controlBracketEscape == nil)
        let enabled = try JSONDecoder().decode(Keymap.self, from: Data(
            #"{"controlBracketEscape":true,"hotkey":{"key":"space","modifiers":["command"]},"entries":[]}"#.utf8
        ))
        #expect(enabled.controlBracketEscape == true)
        #expect(enabled.capsEscape == nil)
        let mapping = CapsEscape()
        let event = key(33, flags: .maskControl)
        mapping.handle(.keyDown, event)
        #expect(code(event) == 33)
        #expect(event.flags == .maskControl)
    }

    @Test(arguments: [false, true])
    func mapsImmediatelyIndependentOfCapsEscape(caps: Bool) {
        let mapping = CapsEscape(capsEscape: caps, controlBracketEscape: true)
        let event = key(33, flags: [.maskControl, .maskShift, .maskAlternate, .maskCommand])
        mapping.handle(.keyDown, event)
        #expect(code(event) == 53)
        #expect(event.flags.isEmpty)
        #expect(NSEvent(cgEvent: event)?.characters == "\u{1b}")
    }

    @Test func leavesOtherKeysAndUnmodifiedBracketAlone() {
        let mapping = CapsEscape(controlBracketEscape: true)
        for (keycode, flags) in [(CGKeyCode(33), CGEventFlags.maskShift), (CGKeyCode(0), .maskControl)] {
            let event = key(keycode, flags: flags)
            mapping.handle(.keyDown, event)
            #expect(code(event) == Int64(keycode))
            #expect(event.flags == flags)
        }
    }

    @Test func repeatsAndReleaseRemainPairedAfterControlRelease() {
        let mapping = CapsEscape(controlBracketEscape: true)
        mapping.handle(.keyDown, key(33, flags: .maskControl))
        mapping.handle(.flagsChanged, key(59, down: false))

        let repeated = key(33)
        repeated.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        mapping.handle(.keyDown, repeated)
        #expect(code(repeated) == 53)
        #expect(repeated.getIntegerValueField(.keyboardEventAutorepeat) == 1)

        let release = key(33, down: false)
        mapping.handle(.keyUp, release)
        #expect(code(release) == 53)
        #expect(release.flags.isEmpty)

        let next = key(33)
        mapping.handle(.keyDown, next)
        #expect(code(next) == 33)
    }

    @Test func disablingMidChordStillMapsRelease() {
        let mapping = CapsEscape(controlBracketEscape: true)
        mapping.handle(.keyDown, key(33, flags: .maskControl))
        mapping.configure(capsEscape: false, controlBracketEscape: false)
        let release = key(33, down: false, flags: .maskControl)
        mapping.handle(.keyUp, release)
        #expect(code(release) == 53)
        #expect(release.flags.isEmpty)
        let next = key(33, flags: .maskControl)
        mapping.handle(.keyDown, next)
        #expect(code(next) == 33)
    }
}
