import SwiftUI

// MARK: - Columns

/// Miller columns, as the NeXTSTEP browser had them and the Finder still does:
/// going deeper adds a column instead of replacing what you were looking at, so
/// the way back is visible rather than remembered.
struct ColumnsView: View {
    let layers: [[Node]]
    let title: String?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(layers.enumerated()), id: \.offset) { index, layer in
                column(layer, at: index)

                if index < layers.count - 1 {
                    Rectangle()
                        .fill(Style.rule)
                        .frame(width: 1)
                }
            }
        }
        .fixedSize()
    }

    private func column(_ layer: [Node], at index: Int) -> some View {
        let active = index == layers.count - 1

        return VStack(alignment: .leading, spacing: 0) {
            if Theme.current.title {
                Heading(text: heading(index))
            }

            ForEach(Array(blocks(of: layer).enumerated()), id: \.offset) { block, rows in
                if block > 0 {
                    Color.clear.frame(height: Style.ruleGap)
                }

                ForEach(rows) { row in
                    RowView(node: row, dimmed: !active, chevron: true)
                }
            }
        }
        .frame(width: Style.columnWidth, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    /// The heading of a column is the entry that opened it, and of the first one
    /// the launcher itself. A theme showing a single column passes the whole
    /// road as the title, and that is what goes up there instead.
    private func heading(_ index: Int) -> String {
        if index == layers.count - 1, let title { return title }

        return index == 0 ? "sottomano" : ""
    }
}
