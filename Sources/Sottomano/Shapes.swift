import SwiftUI

// MARK: - Columns

/// Miller columns, as the NeXTSTEP browser had them and the Finder still does.
///
/// Breaks the assumption that going deeper replaces what you were looking at.
/// Every level stays on screen, side by side, and the layer you are in is the
/// rightmost one — so the panel grows to the right as you go, and the way back
/// is visible rather than remembered.
struct ColumnsView: View {
    let layers: [[Node]]
    let title: String?
    /// The key lit inside the word rather than in a column of its own.
    var inline = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(layers.enumerated()), id: \.offset) { index, layer in
                let active = index == layers.count - 1

                VStack(alignment: .leading, spacing: 0) {
                    Text(index == 0 ? "sottomano" : (title(before: index) ?? ""))
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(Style.text.opacity(active ? 0.55 : 0.25))
                        .padding(.bottom, 8)

                    ForEach(Array(grouped(layer).enumerated()), id: \.offset) { index, block in
                        // a blank line between what leads somewhere and what
                        // ends there, which the rule does in the other themes
                        if index > 0 {
                            Color.clear.frame(height: 12)
                        }

                    ForEach(block) { row in
                        HStack(spacing: 8) {
                            if inline {
                                Spelled(name: row.name, key: row.key)
                                    .foregroundStyle(
                                        Style.text.opacity(active ? (row.continues ? 1 : 0.75) : 0.3)
                                    )
                            } else {
                                Text(row.key)
                                    .foregroundStyle(Style.text.opacity(active ? 1 : 0.35))
                                    .frame(width: 12, alignment: .leading)

                                Text(row.name)
                                    .foregroundStyle(
                                        Style.text.opacity(active ? (row.continues ? 0.95 : 0.62) : 0.28)
                                    )
                            }

                            Spacer(minLength: 6)

                            // only the columns are marked. What opens a search
                            // needs no glyph: it has a block of its own, and a
                            // symbol saying what the blank line already says was
                            // one thing too many on the row.
                            if row.kind == .layer {
                                Text("›")
                                    .foregroundStyle(Style.text.opacity(active ? 0.4 : 0.18))
                            }
                        }
                        .font(Style.font(size: 17))
                        .frame(height: 25, alignment: .leading)
                    }
                    }
                }
                .frame(width: 196, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 4)

                if index < layers.count - 1 {
                    Rectangle()
                        .fill(.white.opacity(0.12))
                        .frame(width: 1)
                }
            }
        }
        .fixedSize()
    }

    /// Grouped by where the key leads: another column of keys, then something to
    /// search in, then what ends there. Opening a column and opening a search
    /// are different enough to be worth a blank line between them.
    private func grouped(_ layer: [Node]) -> [[Node]] {
        [Node.Kind.layer, .search, .action]
            .map { kind in layer.filter { $0.kind == kind } }
            .filter { !$0.isEmpty }
    }

    /// The heading of a column is the entry that opened it.
    private func title(before index: Int) -> String? {
        index == layers.count - 1 ? title : nil
    }
}
