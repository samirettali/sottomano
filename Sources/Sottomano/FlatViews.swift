import SwiftUI

// MARK: - Matrix

/// Two keys as a coordinate rather than a path: the left hand names the row and
/// the right hand names the column, and they can be struck together. There is
/// no descending and no going back, so there is nothing to be lost inside — a
/// command is a place, and a place is remembered by where it is.
struct MatrixView: View {
    let commands: [Command]
    let typed: String

    private var grid: [(row: String, group: String, cells: [Command])] {
        Codes.grid(commands)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                // the corner of the grid, where the two hands meet
                Text("")
                    .frame(width: 74)

                ForEach(Codes.columns.prefix(width), id: \.self) { column in
                    Text(column)
                        .font(Style.font(size: 10).weight(.medium))
                        .foregroundStyle(Style.text.opacity(typed.count == 1 ? 0.75 : 0.3))
                        .frame(width: 78, height: 12)
                }
            }

            ForEach(grid, id: \.row) { line in
                HStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Text(line.row)
                            .font(Style.font(size: 13).weight(.semibold))
                            .foregroundStyle(
                                Style.text.opacity(typed.hasPrefix(line.row) ? 1 : 0.45)
                            )
                            .frame(width: 16, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.white.opacity(typed.hasPrefix(line.row) ? 0.2 : 0.07))
                            )

                        Text(line.group)
                            .font(.system(size: 8, weight: .semibold))
                            .tracking(0.8)
                            .textCase(.uppercase)
                            .lineLimit(1)
                            .foregroundStyle(Style.text.opacity(0.4))
                            .frame(width: 52, alignment: .leading)
                    }

                    ForEach(line.cells) { cell in
                        let lit = !typed.isEmpty && cell.code.hasPrefix(typed)

                        Text(cell.name)
                            .font(Style.font(size: 11))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(Style.text.opacity(lit ? 1 : 0.62))
                            .frame(width: 78, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.white.opacity(lit ? 0.2 : 0.05))
                            )
                    }

                    // a short row keeps its columns aligned with every other one
                    ForEach(line.cells.count..<width, id: \.self) { _ in
                        Color.clear.frame(width: 78, height: 22)
                    }
                }
            }
        }
    }

    private var width: Int {
        min(grid.map(\.cells.count).max() ?? 0, Codes.columns.count)
    }
}
