import SwiftUI

/// The panel Hammerspoon draws today, in SwiftUI: layers above the rule, leaf
/// actions below it, and the key at full white because it is the only thing
/// that has to be read.
struct LauncherView: View {
    let rows: [Row]

    struct Row: Identifiable {
        let id = UUID()
        let key: String
        let name: String
        let isLayer: Bool
    }

    private var layers: [Row] { rows.filter(\.isLayer) }
    private var actions: [Row] { rows.filter { !$0.isLayer } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(layers) { row in
                line(row)
            }

            if !layers.isEmpty && !actions.isEmpty {
                Rectangle()
                    .fill(Style.border)
                    .frame(height: Style.borderWidth)
                    .padding(.vertical, Style.ruleGap / 2)
                    // full bleed: the rule runs into the border either side of
                    // it, so it divides the panel rather than sitting inside it
                    .padding(.horizontal, -Style.padding)
            }

            ForEach(actions) { row in
                line(row)
            }
        }
        .padding(Style.padding)
        .background(Style.fill)
        .overlay(
            RoundedRectangle(cornerRadius: Style.radius)
                .strokeBorder(Style.border, lineWidth: Style.borderWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: Style.radius))
        .fixedSize()
    }

    private func line(_ row: Row) -> some View {
        HStack(spacing: Style.gap) {
            Text(row.key)
                .foregroundStyle(Style.text)
                .frame(width: Style.keyColumn, alignment: .leading)

            Text("→")
                .foregroundStyle(Style.text.opacity(0.3))

            Text(row.name)
                .foregroundStyle(Style.text.opacity(row.isLayer ? 1 : 0.7))
        }
        .font(Style.font())
        .frame(height: Style.lineHeight, alignment: .leading)
    }
}

enum Style {
    static let size: CGFloat = 19
    static let padding: CGFloat = 24
    static let gap: CGFloat = 10
    static let radius: CGFloat = 12
    static let borderWidth: CGFloat = 3
    static let ruleGap: CGFloat = 12
    static let lineHeight: CGFloat = 26
    static let keyColumn: CGFloat = 12

    static let fill = Color.black
    static let border = Color.white.opacity(0.4)
    static let text = Color.white

    /// Falls back to the system monospaced face, as Pulse does: the panel is
    /// meant to match the terminal, and the font is not bundled.
    static func font(size: CGFloat = size) -> Font {
        if NSFont(name: "JetBrainsMono Nerd Font", size: size) != nil {
            return .custom("JetBrainsMono Nerd Font", size: size)
        }

        return .system(size: size, design: .monospaced)
    }
}
