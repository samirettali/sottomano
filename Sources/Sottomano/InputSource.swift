import Carbon
import Foundation

/// The keyboard layouts, and the one hotkey that cycles them.
///
/// Sketchybar has no event of its own for this, so it is pushed one — by the
/// launcher when it switches, and by the observer when anything else does.
@MainActor
enum InputSource {
    /// Sorted by identifier, so the cycle is the same every time rather than
    /// whatever order the system happens to answer in.
    static func selectable() -> [TISInputSource] {
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsSelectCapable: true,
        ]

        let list = TISCreateInputSourceList(filter as CFDictionary, false)?
            .takeRetainedValue() as? [TISInputSource] ?? []

        return list.sorted { identifier(of: $0) < identifier(of: $1) }
    }

    static func identifier(of source: TISInputSource) -> String {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return ""
        }

        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    static func name(of source: TISInputSource) -> String {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else {
            return identifier(of: source)
        }

        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    static var current: TISInputSource? {
        TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    @discardableResult
    static func next() -> String {
        let sources = selectable()

        guard sources.count > 1 else { return "one layout" }

        let now = current.map(identifier(of:)) ?? ""
        let index = sources.firstIndex { identifier(of: $0) == now } ?? -1
        let following = sources[(index + 1) % sources.count]

        TISSelectInputSource(following)

        return name(of: following)
    }

    /// `{}` in the command is the identifier of the layout now in use.
    static func observe(_ command: [String]) {
        guard !command.isEmpty else { return }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                push(command)
            }
        }

        // once at startup as well: sketchybar is drawn before this is running
        push(command)
    }

    private static func push(_ command: [String]) {
        guard let first = command.first else { return }

        let identifier = current.map(identifier(of:)) ?? ""
        let process = Process()

        process.executableURL = URL(fileURLWithPath: first)
        process.arguments = command.dropFirst().map {
            $0.replacingOccurrences(of: "{}", with: identifier)
        }

        try? process.run()
    }
}
