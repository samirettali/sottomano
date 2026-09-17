import SwiftUI

/// One node of the keymap as the panel sees it. The whole tree is handed to the
/// view, not just the layer on screen: three of the themes show what is *not*
/// under the cursor, and cannot do it from a single layer.
struct Node: Identifiable {
    let id = UUID()
    let key: String
    let name: String
    let children: [Node]?
    /// What pressing it leads to, which is the only thing the panels sort on.
    let kind: Kind

    enum Kind {
        /// Another layer of keys.
        case layer
        /// Something to search in: a picker, the filesystem, a question.
        case search
        /// It acts, and it is done.
        case action
    }

    /// Leads somewhere rather than finishing.
    var continues: Bool { kind != .action }
    /// An action that starts an application, which the grouping keeps apart
    /// from the ones that do something: a row of apps reads as a dock, and
    /// the loupe and the layout toggle are not that.
    var launches = false
    /// What running it would produce, for the theme that shows outcomes rather
    /// than names.
    var preview: Preview = .none
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
                kind: LauncherView.kind(of: entry),
                launches: entry.launch != nil,
                preview: LauncherView.preview(of: entry)
            )
        }
    }

    static func kind(of entry: Entry) -> Node.Kind {
        if entry.entries != nil { return .layer }
        if entry.pick != nil || entry.browse != nil || entry.search != nil { return .search }

        return .action
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

    /// `sottomano › query`, the road taken to the layer on screen.
    var trailText: String {
        var names = ["sottomano"]
        var level = tree

        for key in path {
            guard let node = level.first(where: { $0.key == key }) else { break }

            names.append(node.name)
            level = node.children ?? []
        }

        return names.joined(separator: "  ›  ")
    }

    var body: some View {
        switch Theme.current.shape {
        case .keyboard: KeyboardView(rows: rows)
        case .depth: DepthView(layers: layers)
        case .list:
            switch Theme.current.flow {
            case .columns: ColumnsView(layers: layers, title: title)
            case .replace: RowsView(rows: rows, title: trailText)
            }
        }
    }
}

// MARK: - Rows

/// The name, with the key in front of it when the key is not its initial. Where
/// it is, showing it again would only be pointing at the first letter.
struct Spelled: View {
    let name: String
    let key: String

    var body: some View {
        if name.lowercased().hasPrefix(key.lowercased()) {
            Text(name)
        } else {
            Text(key + "  " + name)
        }
    }
}

/// One row, wherever it is drawn. Both the list and the columns come here, so a
/// knob that changes a row changes it in one place — they drifted apart once,
/// and the options stopped working in half the panel.
struct RowView: View {
    let node: Node
    /// A column that has been left behind, drawn quieter than the current one.
    var dimmed = false
    /// Whether a layer says that a column follows. Nothing follows in a panel
    /// that replaces itself.
    var chevron = false

    private var strength: Double {
        if dimmed { return 0.32 }

        return node.continues ? 1 : 0.72
    }

    var body: some View {
        HStack(spacing: Style.gap) {
            if Theme.current.key == .column {
                Text(node.key)
                    .foregroundStyle(Style.text.opacity(dimmed ? 0.35 : 1))
                    .frame(width: Style.keyColumn, alignment: .leading)

                if Theme.current.arrow {
                    Text("→")
                        .foregroundStyle(Style.muted.opacity(dimmed ? 0.2 : 0.45))
                }

                Text(node.name)
                    .foregroundStyle(Style.text.opacity(strength))
            } else {
                Spelled(name: node.name, key: node.key)
                    .foregroundStyle(Style.text.opacity(strength))
            }

            if chevron {
                Spacer(minLength: 6)

                if node.kind == .layer {
                    Text("›")
                        .foregroundStyle(Style.muted.opacity(dimmed ? 0.2 : 0.5))
                }
            }
        }
        .font(Style.font())
        .frame(height: Style.lineHeight, alignment: .leading)
    }
}

/// Layers first, then what opens a search, then the applications, then what
/// acts and is done — or the order they were written in, when the theme says
/// not to group.
func blocks(of rows: [Node]) -> [[Node]] {
    guard Theme.current.group else { return [rows] }

    let groups: [(Node) -> Bool] = [
        { $0.kind == .layer },
        { $0.kind == .search },
        { $0.kind == .action && $0.launches },
        { $0.kind == .action && !$0.launches },
    ]

    // alphabetical inside each block: the key is the initial of its own word,
    // so ordering by key is ordering by name, and a row keeps its seat
    return groups
        .map { belongs in rows.filter(belongs).sorted { $0.key < $1.key } }
        .filter { !$0.isEmpty }
}

/// A heading over a panel: the road taken, or the name of the column.
struct Heading: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(Style.muted.opacity(0.65))
            .padding(.bottom, 8)
    }
}

/// The layer as a list.
struct RowsView: View {
    let rows: [Node]
    /// The road taken, drawn over the list when the theme asks for it.
    var title: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if Theme.current.title, let title {
                Heading(text: title)
            }

            ForEach(Array(blocks(of: rows).enumerated()), id: \.offset) { index, block in
                if index > 0 {
                    Color.clear.frame(height: Style.ruleGap)
                }

                ForEach(block) { row in
                    RowView(node: row)
                }
            }
        }
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
        let continues = bound?.continues ?? false

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
                    .foregroundStyle(Style.text.opacity(continues ? 0.85 : 0.5))
                    .padding(.horizontal, 2)
            }
        }
        .frame(width: KeyboardView.width, height: KeyboardView.height)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(bound == nil ? 0.015 : (continues ? 0.13 : 0.07)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    .white.opacity(bound == nil ? 0.05 : (continues ? 0.5 : 0.22)),
                    lineWidth: 1
                )
        )
        // a bound key is lit, and a layer is lit brighter: the glow is what the
        // eye picks up before it reads anything
        .shadow(
            color: .white.opacity(bound == nil ? 0 : (continues ? 0.18 : 0.07)),
            radius: continues ? 10 : 6
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
    static let gap: CGFloat = 10
    static let keyColumn: CGFloat = 12

    static var size: CGFloat { Theme.current.size }
    static var iconSize: CGFloat { Theme.current.iconSize }
    /// Around the contents of a row, the same on every side.
    static var rowPadding: CGFloat { (iconSize * 0.28).rounded() }
    static var padding: CGFloat { Theme.current.padding }
    static var radius: CGFloat { Theme.current.radius }
    static var borderWidth: CGFloat { Theme.current.borderWidth }
    static var lineHeight: CGFloat { (size * 1.35).rounded() }
    /// The blank line between two groups of rows.
    static var ruleGap: CGFloat { (size * 0.7).rounded() }
    /// Wide enough for the longest name a layer holds, at the size it is drawn.
    static var columnWidth: CGFloat { (size * 11.5).rounded() }

    static var text: Color { Color(hex: Theme.current.text) }
    static var muted: Color { Color(hex: Theme.current.muted) }
    static var rule: Color { Color(hex: Theme.current.rule) }
    static var selection: Color { Color(hex: Theme.current.selection) }
    static var border: Color { Color(hex: Theme.current.border) }
    static var background: Color { Color(hex: Theme.current.background) }

    /// Zero seconds means no animation at all, not a very quick one.
    static func reveal(_ wanted: Bool) -> Animation? {
        guard wanted, Theme.current.animation > 0 else { return nil }

        return .spring(response: Theme.current.animation, dampingFraction: 0.88)
    }

    static var fade: Animation? {
        guard Theme.current.animation > 0 else { return nil }

        return .easeOut(duration: Theme.current.animation * 0.75)
    }

    /// Falls back to the system monospaced face: the panel is meant to match the
    /// terminal, and no font is bundled, so a name the machine has not got must
    /// still leave a panel that reads.
    static func font(size: CGFloat = size) -> Font {
        let named = Theme.current.font

        if !named.isEmpty, NSFont(name: named, size: size) != nil {
            return .custom(named, size: size)
        }

        return .system(size: size, design: .monospaced)
    }
}
