#if DEBUG
    import AppKit
    import SwiftUI

    /// Debug builds only, so it cannot ship. `make dev` is the build that has it.
    /// It sits in a window of its own in the corner of the screen rather than on
    /// the panel: a control drawn inside the thing being judged would change it.
    /// ctrl+1…4 does the same from the keyboard.
    @MainActor
    enum VariantSwitcher {
        private static var panel: NSPanel?

        static func show(onSelect: @escaping () -> Void) {
            let view = NSHostingView(rootView: SwitcherView(onSelect: onSelect))
            view.layout()

            let window = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .mainMenu
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
            window.contentView = view
            window.setContentSize(view.fittingSize)

            if let screen = NSScreen.main {
                window.setFrameOrigin(
                    NSPoint(
                        x: screen.frame.maxX - window.frame.width - 20,
                        y: screen.frame.minY + 20
                    )
                )
            }

            window.orderFrontRegardless()
            panel = window
        }
    }

    private struct SwitcherView: View {
        let onSelect: () -> Void

        @State private var current = Variant.current

        var body: some View {
            HStack(spacing: 5) {
                Text("THEME")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)

                ForEach(Array(Variant.allCases.enumerated()), id: \.element) { index, variant in
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 18, height: 18)
                        .background(
                            Circle().fill(
                                variant == current
                                    ? AnyShapeStyle(Color.orange.opacity(0.8))
                                    : AnyShapeStyle(Color.white.opacity(0.12))
                            )
                        )
                        .foregroundStyle(variant == current ? Color.black : Color.white)
                        .help("\(index + 1). \(variant.label)")
                        .onTapGesture {
                            Variant.select(variant)
                            current = variant
                            onSelect()
                        }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.orange.opacity(0.55), lineWidth: 1))
            .padding(6)
            .onReceive(NotificationCenter.default.publisher(for: .variantChanged)) { _ in
                current = Variant.current
            }
        }
    }

    extension Notification.Name {
        /// ctrl+1…4 changes the variant too, and the capsule has to follow.
        static let variantChanged = Notification.Name("dev.variantChanged")
    }
#endif
