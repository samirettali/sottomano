import SwiftUI

/// Four ways of showing a layer, not four skins of one. Temporary: once one
/// wins, the others and the switcher go.
/// How the panel shows a layer. Set in the keymap, so the theme is declared
/// with the rest of the configuration rather than kept in the app.
enum Variant: String, CaseIterable {
    /// The list it has always been: black, white, and a rule between the layers
    /// and the leaf actions.
    case classic
    /// The panel is the keyboard. Bound keys light up where the fingers already
    /// are, so the shape of a layer is something the hand knows before the eye
    /// reads a word.
    case keyboard
    /// The layers you came through stay behind the one you are in, pushed back
    /// and blurred, so depth says where you are instead of a breadcrumb.
    case depth
    /// Miller columns, as the NeXTSTEP browser had them: every level stays on
    /// screen, side by side, and the way back is visible rather than remembered.
    case columns
    /// The list, with the letter to press lit inside the word it belongs to
    /// rather than standing in a column of its own.
    case inline
    /// The same, in columns.
    case inlineColumns

    var label: String {
        switch self {
        case .classic: "Classic — the black and white list"
        case .keyboard: "Keyboard — the layer lit on the keys themselves"
        case .depth: "Depth — the layers you came through, behind"
        case .columns: "Columns — every level side by side"
        case .inline: "Inline — the letter lit inside the word"
        case .inlineColumns: "Inline columns — the same, side by side"
        }
    }

    /// What the keymap asked for.
    nonisolated(unsafe) static var configured: Variant = .classic

    #if DEBUG
        /// ctrl+1…4 overrides it for this run only, so trying a theme never
        /// disagrees with what nix declares.
        nonisolated(unsafe) static var override: Variant?

        static var current: Variant { override ?? configured }

        static func select(_ variant: Variant) { override = variant }
    #else
        static var current: Variant { configured }
    #endif
}

extension Style {
    static var variant: Variant { Variant.current }

    static let text = Color.white

    static var radius: CGFloat {
        switch variant {
        case .classic, .inline: 12
        case .keyboard: 16
        default: 14
        }
    }

    static var padding: CGFloat {
        switch variant {
        case .classic, .depth, .inline: 24
        case .keyboard: 20
        default: 16
        }
    }

    static var arrowOpacity: Double { 0.3 }

    static func nameOpacity(continues: Bool) -> Double {
        continues ? 1 : 0.68
    }

    static var ruleColor: Color {
        variant == .classic || variant == .inline
            ? .white.opacity(0.25)
            : .white.opacity(0.14)
    }

    static var selectionColor: Color { .white.opacity(0.12) }
}

// MARK: - Chrome

/// Whether this render is the panel arriving or the panel already up. Only the
/// arrival is animated: every keystroke redraws the panel, and a reveal on each
/// of those is a flash.
private struct ArrivingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var arriving: Bool {
        get { self[ArrivingKey.self] }
        set { self[ArrivingKey.self] = newValue }
    }
}

/// The background, the border, the corner and the way the panel arrives. The
/// panel is laid out at its final size and only then revealed, so nothing
/// re-flows while it appears — the spring is on the compositor alone.
struct Chrome: ViewModifier {
    @Environment(\.arriving) private var arriving

    @State private var shown = false

    private var revealed: Bool { shown || !arriving }

    func body(content: Content) -> some View {
        content
            .padding(Style.padding)
            .background(Background())
            .overlay(Border())
            .clipShape(RoundedRectangle(cornerRadius: Style.radius, style: .continuous))
            .scaleEffect(revealed ? 1 : 0.97)
            .opacity(revealed ? 1 : 0)
            .animation(arriving ? .spring(response: 0.18, dampingFraction: 0.85) : nil, value: shown)
            .onAppear { shown = true }
            .fixedSize()
    }
}

private struct Background: View {
    var body: some View {
        if Style.variant == .classic || Style.variant == .inline {
            Color.black
        } else {
            Vibrancy(material: .hudWindow).overlay(Color.black.opacity(0.45))
        }
    }
}

private struct Border: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Style.radius, style: .continuous)

        if Style.variant == .classic || Style.variant == .inline {
            shape.strokeBorder(.white.opacity(0.4), lineWidth: 3)
        } else {
            // lit along the top edge and dim at the bottom, the way a physical
            // thing sits under a light rather than being outlined in grey
            shape.strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.5), .white.opacity(0.1)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
        }
    }
}

/// The frosted background macOS draws behind a window, which the Hammerspoon
/// canvas had no way to ask for.
struct Vibrancy: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active

        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension View {
    func chrome() -> some View { modifier(Chrome()) }
}
