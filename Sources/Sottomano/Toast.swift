import AppKit
import SwiftUI

/// Confirms that something happened, in the same chrome as every other panel.
@MainActor
enum Toast {
    private static var panel: NSPanel?
    private static var timer: Timer?

    static func show(_ message: String, seconds: TimeInterval = 3) {
        hide()

        let view = NSHostingView(
            rootView: Text(preview(message))
                .font(Style.font(size: Style.size - 2))
                .foregroundStyle(Style.text)
                .padding(Style.padding)
                .background(Style.fill)
                .overlay(
                    RoundedRectangle(cornerRadius: Style.radius)
                        .strokeBorder(Style.border, lineWidth: Style.borderWidth)
                )
                .clipShape(RoundedRectangle(cornerRadius: Style.radius))
                .fixedSize()
        )

        view.layout()

        let window = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .mainMenu
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.contentView = view
        window.setContentSize(view.fittingSize)

        if let screen = NSScreen.main {
            let frame = screen.frame
            let size = window.frame.size

            window.setFrameOrigin(
                NSPoint(
                    x: (frame.width - size.width).rounded() / 2 + frame.minX,
                    y: (frame.maxY - frame.height * 0.32 - size.height).rounded()
                )
            )
        }

        window.orderFrontRegardless()
        panel = window

        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            Task { @MainActor in hide() }
        }
    }

    static func hide() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    /// A toast confirms, it is not there to read the whole result in.
    private static func preview(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let shown = lines.prefix(8).map { $0.count > 60 ? String($0.prefix(59)) + "…" : $0 }

        return shown.joined(separator: "\n") + (lines.count > 8 ? "\n…" : "")
    }
}
