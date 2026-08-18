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

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(layers.enumerated()), id: \.offset) { index, layer in
                let active = index == layers.count - 1

                VStack(alignment: .leading, spacing: 0) {
                    Text(index == 0 ? "sottomano" : (title(before: index) ?? ""))
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(Style.text.opacity(active ? 0.55 : 0.25))
                        .padding(.bottom, 8)

                    ForEach(layer) { row in
                        HStack(spacing: 8) {
                            Text(row.key)
                                .foregroundStyle(Style.text.opacity(active ? 1 : 0.35))
                                .frame(width: 11, alignment: .leading)

                            Text(row.name)
                                .foregroundStyle(
                                    Style.text.opacity(active ? (row.continues ? 0.95 : 0.62) : 0.28)
                                )

                            Spacer(minLength: 6)

                            if row.isLayer {
                                Text("›")
                                    .foregroundStyle(Style.text.opacity(active ? 0.4 : 0.18))
                            }
                        }
                        .font(Style.font(size: 15))
                        .frame(height: 22, alignment: .leading)
                    }
                }
                .frame(width: 172, alignment: .leading)
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

    /// The heading of a column is the entry that opened it.
    private func title(before index: Int) -> String? {
        index == layers.count - 1 ? title : nil
    }
}
