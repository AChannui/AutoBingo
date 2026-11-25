import BingoKit
import SwiftUI

/// The B I N G O letters above a card.
struct BingoHeaderRow: View {
    var body: some View {
        GridRow {
            ForEach(BingoColumn.allCases) { column in
                Text(column.letter)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// A 5×5 grid with a header row. The caller decides what goes in each cell.
struct FiveByFiveGrid<CellContent: View>: View {
    var showsHeader = true
    var spacing: CGFloat = 4
    @ViewBuilder var content: (Cell) -> CellContent

    var body: some View {
        Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
            if showsHeader { BingoHeaderRow() }
            ForEach(0..<Cell.gridSize, id: \.self) { row in
                GridRow {
                    ForEach(0..<Cell.gridSize, id: \.self) { column in
                        content(Cell(row, column))
                    }
                }
            }
        }
    }
}

/// One square of a card during play.
struct PlayCellView: View {
    let number: Int?
    let isCenter: Bool
    let isMarked: Bool
    let isWinning: Bool
    let isNeeded: Bool
    let isLastCall: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(background)
            if isNeeded && !isMarked {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            }
            if isLastCall {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary, lineWidth: 3)
            }
            Text(label)
                .font(isCenter && number == nil ? .caption2.weight(.bold) : .body.weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .foregroundStyle(isMarked ? Color.white : Color.primary)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label)\(isMarked ? ", marked" : "")")
    }

    private var label: String {
        if let number { return "\(number)" }
        return isCenter ? "FREE" : "?"
    }

    private var background: Color {
        if isWinning { return .green }
        if isMarked { return .accentColor }
        return Color(.secondarySystemFill)
    }
}
