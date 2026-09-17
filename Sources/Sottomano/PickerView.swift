import SwiftUI

struct Choice: Identifiable {
    let id = UUID()
    var value: String
    var name: String
    var subtitle: String = ""
    /// Breaks ties between equally good matches; with no query it is the order.
    var boost: Int = 0
    var icon: NSImage?
    /// Drawn as a swatch: text that names a colour is more useful seen.
    var color: Color?
    /// A picture to show beside the list when this row is the one selected.
    var imageFile: String?
    /// A table to show beside the list when this row is the one selected:
    /// every form of a timestamp, for text that is data rather than words.
    var details: [Detail]?
    /// A document to show beside the list as a tree, for text that is JSON.
    var tree: JSONValue?
    /// Set when the row stands for a file that was copied, rather than for text
    /// or for pixels: pasting it should hand over the file itself.
    var fileURL: String?
    /// What to draw when there is no picture and no colour, so that a row of
    /// plain text still starts where every other row starts.
    var symbol: String?
    /// A picture to fetch, for a list that names one — a playlist cover.
    var remote: String?
    /// A character that is the picture: an emoji is drawn in the icon's square
    /// rather than crammed into the name, so it is as large as everything else
    /// in that column.
    var glyph: String?
    var isDirectory = false
}

/// The query on top, the matches under it, the selected row filled. The panel
/// grows downwards, so the top edge stays where every other panel starts.
struct PickerView: View {
    /// The list is always this wide, preview or no preview, so the panel can be
    /// placed on it rather than on whatever it happens to be carrying.
    static let listWidth: CGFloat = 560

    let query: String
    let matches: [Choice]
    let selected: Int
    /// Where the query applies, for the browser. The panel is a place before it
    /// is a search, so the place is written above the search.
    var header: String?
    /// The picture the selected row stands for, shown beside the list rather
    /// than squeezed into it.
    var preview: NSImage?
    /// The table the selected row stands for, in the same place a picture
    /// would go.
    var details: [Detail]?
    /// The lines of the document beside the list that are on screen, already
    /// windowed by the launcher.
    var tree: [JSONLine]?
    /// The line of the table or the tree under the cursor, once tab has put
    /// it there, counted from the first line on screen. The list's selection
    /// stays drawn, since what is beside it is about that row.
    var detail: Int?
    /// What the keys do here, on one line under the list: the key at full
    /// light and the verb quieter, which is how a layer writes its own.
    var legend: [(key: String, name: String)]?
    /// Whether cmd+digit picks a row here, and so whether the rows say so.
    var numbered = false
    /// Whether anything in the *whole* list has something to show, not only
    /// what is on screen: worked out from the rows in view, the column and the
    /// height of a row changed as the selection moved past the ones with icons.
    var showsIcons = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            list

            if preview != nil || details != nil || tree != nil {
                Rectangle()
                    .fill(Style.rule)
                    .frame(width: 1)
                    .padding(.horizontal, 14)
            }

            if let preview {
                Image(nsImage: preview)
                    .resizable()
                    .scaledToFit()
                    // top, not centre: a landscape picture is shorter than the
                    // box it is given, and centring it left a gap above that
                    // made it look like it had slipped down the panel
                    .frame(maxWidth: 320, maxHeight: 320, alignment: .top)
            }

            if let details {
                table(details)
            }

            if let tree {
                self.tree(tree)
            }
        }
    }

    /// The document written out, a line each, the keys quieter than the
    /// values: the value is what was wanted, the key only says which.
    private func tree(_ lines: [JSONLine]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                let isSelected = index == detail

                HStack(spacing: 0) {
                    Text(String(repeating: "  ", count: line.depth))

                    if let key = line.key {
                        Text(key + ": ")
                            .foregroundStyle(Style.text.opacity(isSelected ? 0.6 : 0.45))
                    }

                    Text(line.text)
                        .foregroundStyle(Style.text.opacity(line.selectable ? (isSelected ? 1 : 0.85) : 0.45))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(Style.font(size: Style.size - 4))
                .frame(height: Style.lineHeight, alignment: .leading)
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(.horizontal, Style.rowPadding)
        .background(alignment: .topLeading) {
            if let detail {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Style.selection)
                    .frame(height: Style.lineHeight)
                    .offset(y: CGFloat(detail) * Style.lineHeight)
            }
        }
    }

    /// Labels down one side, values down the other, the label quieter: the
    /// value is what was wanted, the label only says which one it is. Its
    /// first line sits on the query's, so the two columns start together.
    private func table(_ details: [Detail]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 0) {
            ForEach(Array(details.enumerated()), id: \.element.id) { index, line in
                let isSelected = index == detail

                GridRow {
                    Text(line.label)
                        .foregroundStyle(Style.text.opacity(isSelected ? 0.6 : 0.45))
                    Text(line.value)
                        .foregroundStyle(Style.text.opacity(isSelected ? 1 : 0.85))
                }
                .font(Style.font(size: Style.size - 4))
                .frame(height: Style.lineHeight, alignment: .leading)
            }
        }
        // the same fill the list uses for its selection, drawn across the
        // whole width of the table rather than around the two cells, with the
        // same room around the text a row of the list has
        .padding(.horizontal, Style.rowPadding)
        .background(alignment: .topLeading) {
            if let detail {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Style.selection)
                    .frame(height: Style.lineHeight)
                    .offset(y: CGFloat(detail) * Style.lineHeight)
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                Text(header)
                    .font(Style.font(size: Style.size - 5))
                    .foregroundStyle(Style.text.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .padding(.bottom, 3)
            }

            Text(query + "|")
                .font(Style.font())
                .foregroundStyle(Style.text)
                .frame(height: Style.lineHeight, alignment: .leading)
                .padding(.bottom, 10)

            if matches.isEmpty {
                Text("no matches")
                    .font(Style.font())
                    .foregroundStyle(Style.text.opacity(0.4))
                    .frame(height: Style.lineHeight, alignment: .leading)
            }

            ForEach(Array(matches.enumerated()), id: \.element.id) { index, choice in
                row(choice, isSelected: index == selected, place: index + 1)
            }

            if let legend {
                Rectangle()
                    .fill(Style.rule)
                    .frame(height: 1)
                    .padding(.top, 10)

                // one line: the key at full light and the verb quieter, so
                // the pairs read as pairs and not as a sentence
                HStack(spacing: 22) {
                    ForEach(legend, id: \.key) { binding in
                        HStack(spacing: 7) {
                            Text(binding.key).foregroundStyle(Style.text.opacity(0.8))
                            Text(binding.name).foregroundStyle(Style.muted.opacity(0.45))
                        }
                    }
                }
                .font(Style.font(size: Style.size - 4))
                .padding(.top, 14)
                // the panel's own padding is below it, and it is more than
                // the gap to the rule above: the legend is pulled down into
                // it so that it sits at the same distance from both
                .padding(.bottom, 14 - Style.padding)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: PickerView.listWidth, alignment: .leading)
    }


    /// The same for every row of a list, whatever a row happens to carry. One
    /// with a subtitle and one without were different heights, so the rows
    /// under the selection shifted as it moved.
    private var rowHeight: CGFloat {
        (showsIcons ? Style.iconSize : Style.lineHeight) + Style.rowPadding * 2
    }

    private func row(_ choice: Choice, isSelected: Bool, place: Int) -> some View {
        HStack(spacing: 10) {
            if showsIcons {
                icon(choice).frame(width: Style.iconSize, height: Style.iconSize)
            }

            content(choice, isSelected: isSelected)

            Spacer(minLength: 0)

            // the key that picks this row without walking to it, faint
            // enough to be found when looked for and not before
            if numbered, place <= 8 {
                Text("⌘\(place)")
                    .font(Style.font(size: Style.size - 6))
                    .foregroundStyle(Style.text.opacity(isSelected ? 0.35 : 0.2))
            }

            if choice.isDirectory {
                Text("›")
                    .font(Style.font())
                    .foregroundStyle(Style.text.opacity(isSelected ? 0.5 : 0.25))
            }
        }
        // the same all the way round: an icon sitting closer to the top of its
        // row than to the side of it reads as a misalignment
        .padding(Style.rowPadding)
        .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Style.selection : .clear)
        )
    }

    @ViewBuilder
    private func icon(_ choice: Choice) -> some View {
        if let glyph = choice.glyph {
            Text(glyph)
                .font(.system(size: Style.iconSize * 0.78))
        } else if let color = choice.color {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
        } else if let icon = choice.icon ?? Covers.image(choice.remote) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        } else if let symbol = choice.symbol {
            Image(systemName: symbol)
                .font(.system(size: Style.iconSize * 0.5))
                .foregroundStyle(Style.muted.opacity(0.7))
        } else {
            Color.clear
        }
    }

    private func content(_ choice: Choice, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(choice.name)
                .font(Style.font())
                .foregroundStyle(Style.text.opacity(isSelected ? 1 : 0.72))
                .lineLimit(1)

            if !choice.subtitle.isEmpty {
                Text(choice.subtitle)
                    .font(Style.font(size: Style.size - 6))
                    .foregroundStyle(Style.text.opacity(isSelected ? 0.6 : 0.4))
                    .lineLimit(1)
            }
        }
    }
}
