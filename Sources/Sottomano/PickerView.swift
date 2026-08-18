import SwiftUI

struct Choice: Identifiable {
    let id = UUID()
    var value: String
    var name: String
    var subtitle: String = ""
    /// Breaks ties between equally good matches; with no query it is the order.
    var boost: Int = 0
}

/// The query on top, the matches under it, the selected row filled. The panel
/// grows downwards, so the top edge stays where every other panel starts.
struct PickerView: View {
    let query: String
    let matches: [Choice]
    let selected: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                row(choice, isSelected: index == selected)
            }
        }
        .frame(width: 560, alignment: .leading)
        .chrome()
    }

    private func row(_ choice: Choice, isSelected: Bool) -> some View {
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
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Style.selectionColor : .clear)
        )
    }
}
