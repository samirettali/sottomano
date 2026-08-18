import SwiftUI

/// One node of the keymap as the panel sees it. The whole tree is handed to the
/// view, not just the layer on screen: three of the themes show what is *not*
/// under the cursor, and cannot do it from a single layer.
struct Node: Identifiable {
    let id = UUID()
    let key: String
    let name: String
    let children: [Node]?
    /// What running it would produce, for the theme that shows outcomes rather
    /// than names.
    var preview: Preview = .none

    var isLayer: Bool { children != nil }
}

enum Preview {
    case app(String)
    case url(String)
    case text(String)
    /// A list that only exists once the command has run.
    case list(String)
    case display(String)
    case none
}

/// Shows the keymap, focused on the layer the path leads to. Which shape it
/// takes is the theme.
struct LauncherView: View {
    let tree: [Node]
    /// The keys taken to reach the layer on screen.
    let path: [String]
    /// The name of that layer, nil at the root.
    var title: String?

    /// An entry with no name binds without being listed, which is how the shift
    /// variants stay out of the panel.
    static func tree(of entries: [Entry]) -> [Node] {
        entries.compactMap { entry in
            guard let name = entry.name, entry.shift != true else { return nil }

            return Node(
                key: entry.key,
                name: name,
                children: entry.entries.map(LauncherView.tree(of:)),
                preview: LauncherView.preview(of: entry)
            )
        }
    }

    static func preview(of entry: Entry) -> Preview {
        if let app = entry.launch { return .app(app) }
        if let url = entry.url { return .url(URL(string: url)?.host ?? url) }
        if let text = entry.type { return .text(text) }
        if let command = entry.typeOutput { return .text((command.first?.split(separator: "/").last).map(String.init) ?? "") }
        if let template = entry.search { return .url(URL(string: template.replacingOccurrences(of: "{}", with: ""))?.host ?? "") }
        if let layout = entry.display { return .display(layout) }
        if let pick = entry.pick { return .list(pick.source ?? "list") }

        return .none
    }

    /// Every layer from the root down to the one on screen.
    var layers: [[Node]] {
        var result = [tree]
        var level = tree

        for key in path {
            guard let next = level.first(where: { $0.key == key })?.children else { break }

            result.append(next)
            level = next
        }

        return result
    }

    var rows: [Node] { layers.last ?? [] }

    var body: some View {
        switch Style.variant {
        case .classic: RowsView(rows: rows).chrome()
        case .keyboard: KeyboardView(rows: rows).chrome()
        case .depth: DepthView(layers: layers)
        case .columns: ColumnsView(layers: layers, title: title).chrome()
        }
    }
}

// MARK: - Rows

/// The list as it has always been: layers above the rule, actions below.
struct RowsView: View {
    let rows: [Node]

    private var layers: [Node] { rows.filter(\.isLayer) }
    private var actions: [Node] { rows.filter { !$0.isLayer } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(layers) { row in
                line(row)
            }

            if !layers.isEmpty && !actions.isEmpty {
                Rectangle()
                    .fill(Style.ruleColor)
                    .frame(height: 1)
                    .padding(.vertical, Style.ruleGap / 2)
                    .padding(.horizontal, -(Style.padding - 1))
            }

            ForEach(actions) { row in
                line(row)
            }
        }
    }

    private func line(_ row: Node) -> some View {
        HStack(spacing: Style.gap) {
            Text(row.key)
                .foregroundStyle(Style.text)
                .frame(width: Style.keyColumn, alignment: .leading)

            Text("→")
                .foregroundStyle(Style.text.opacity(Style.arrowOpacity))

            Text(row.name)
                .foregroundStyle(Style.text.opacity(Style.nameOpacity(isLayer: row.isLayer)))
        }
        .font(Style.font())
        .frame(height: Style.lineHeight, alignment: .leading)
    }
}

// MARK: - Keyboard

/// The panel *is* the keyboard. A bound key lights up where the finger already
/// goes, and the shape a layer makes on the board is what you come to know.
struct KeyboardView: View {
    let rows: [Node]

    private static let board = [
        "qwertyuiop",
        "asdfghjkl",
        "zxcvbnm",
    ]

    /// The stagger of a real keyboard, in fractions of a key.
    private static let indents: [CGFloat] = [0, 0.35, 0.9]

    private static let width: CGFloat = 52
    private static let height: CGFloat = 46
    private static let gap: CGFloat = 5

    private func row(for character: Character) -> Node? {
        rows.first { $0.key == String(character) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KeyboardView.gap) {
            ForEach(Array(KeyboardView.board.enumerated()), id: \.offset) { index, line in
                HStack(spacing: KeyboardView.gap) {
                    ForEach(Array(line), id: \.self) { character in
                        cap(character)
                    }
                }
                .padding(.leading, KeyboardView.indents[index] * (KeyboardView.width + KeyboardView.gap))
            }
        }
    }

    private func cap(_ character: Character) -> some View {
        let bound = row(for: character)
        let isLayer = bound?.isLayer ?? false

        return VStack(spacing: 1) {
            Text(String(character))
                .font(Style.font(size: 15).weight(bound == nil ? .regular : .medium))
                .foregroundStyle(Style.text.opacity(bound == nil ? 0.13 : 1))

            if let bound {
                Text(bound.name)
                    .font(.system(size: 8, weight: .medium))
                    .tracking(0.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Style.text.opacity(isLayer ? 0.85 : 0.5))
                    .padding(.horizontal, 2)
            }
        }
        .frame(width: KeyboardView.width, height: KeyboardView.height)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(bound == nil ? 0.015 : (isLayer ? 0.13 : 0.07)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    .white.opacity(bound == nil ? 0.05 : (isLayer ? 0.5 : 0.22)),
                    lineWidth: 1
                )
        )
        // a bound key is lit, and a layer is lit brighter: the glow is what the
        // eye picks up before it reads anything
        .shadow(
            color: .white.opacity(bound == nil ? 0 : (isLayer ? 0.18 : 0.07)),
            radius: isLayer ? 10 : 6
        )
    }
}

// MARK: - Depth

/// The layers you came through are still there, pushed back and blurred. Where
/// you are is a place rather than a line of text naming it.
struct DepthView: View {
    let layers: [[Node]]

    var body: some View {
        ZStack {
            ForEach(Array(layers.enumerated()), id: \.offset) { index, layer in
                let behind = layers.count - 1 - index

                RowsView(rows: layer)
                    .padding(Style.padding)
                    .background(Vibrancy(material: .hudWindow).overlay(Color.black.opacity(0.4)))
                    .overlay(
                        RoundedRectangle(cornerRadius: Style.radius, style: .continuous)
                            .strokeBorder(.white.opacity(behind == 0 ? 0.35 : 0.12), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Style.radius, style: .continuous))
                    .blur(radius: CGFloat(behind) * 2.5)
                    .scaleEffect(1 - CGFloat(behind) * 0.05)
                    .offset(y: CGFloat(behind) * -18)
                    .opacity(behind == 0 ? 1 : 0.55)
            }
        }
        .padding(.top, CGFloat(max(layers.count - 1, 0)) * 18)
        .modifier(Reveal())
        .fixedSize()
    }
}

/// The arrival on its own, for a theme that draws its own background.
struct Reveal: ViewModifier {
    @Environment(\.arriving) private var arriving

    @State private var shown = false

    private var revealed: Bool { shown || !arriving }

    func body(content: Content) -> some View {
        content
            .scaleEffect(revealed ? 1 : 0.97)
            .opacity(revealed ? 1 : 0)
            .animation(arriving ? .spring(response: 0.18, dampingFraction: 0.85) : nil, value: shown)
            .onAppear { shown = true }
    }
}

enum Style {
    static let size: CGFloat = 19
    static let gap: CGFloat = 10
    static let ruleGap: CGFloat = 12
    static let lineHeight: CGFloat = 26
    static let keyColumn: CGFloat = 12

    /// Falls back to the system monospaced face, as Pulse does: the panel is
    /// meant to match the terminal, and the font is not bundled.
    static func font(size: CGFloat = size) -> Font {
        if NSFont(name: "JetBrainsMono Nerd Font", size: size) != nil {
            return .custom("JetBrainsMono Nerd Font", size: size)
        }

        return .system(size: size, design: .monospaced)
    }
}
