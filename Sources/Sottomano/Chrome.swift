import SwiftUI

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
            .animation(Style.reveal(arriving), value: shown)
            .onAppear { shown = true }
            .fixedSize()
    }
}

private struct Background: View {
    var body: some View {
        if Theme.current.isGlass {
            Vibrancy(material: .hudWindow).overlay(Color.black.opacity(0.45))
        } else {
            Style.background
        }
    }
}

private struct Border: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Style.radius, style: .continuous)
            .strokeBorder(Style.border, lineWidth: Style.borderWidth)
    }
}

/// What is arriving, coming up as what it replaces goes. Without this the new
/// contents were drawn at full strength straight away and covered the old ones
/// before the crossing could be seen at all.
struct Entering: ViewModifier {
    @State private var here = false

    func body(content: Content) -> some View {
        content
            .opacity(here ? 1 : 0)
            .offset(y: here ? 0 : 6)
            .animation(Style.reveal(true), value: here)
            .onAppear { here = true }
    }
}

/// What is leaving, drawn behind what is arriving and dissolving out of it.
struct Ghost<Content: View>: View {
    @ViewBuilder let content: Content

    @State private var gone = false

    var body: some View {
        content
            .opacity(gone ? 0 : 1)
            .allowsHitTesting(false)
            .animation(Style.fade, value: gone)
            .onAppear { gone = true }
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
