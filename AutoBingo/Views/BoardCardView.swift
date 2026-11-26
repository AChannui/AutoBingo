import BingoKit
import SwiftUI

/// A board during play: its name, how close it is to winning, and the marked grid.
struct BoardCardView: View {
    let board: BingoBoard
    let marked: Set<Cell>
    let progress: RuleProgress
    let lastCall: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(board.name)
                    .font(.headline)
                Spacer()
                status
            }

            FiveByFiveGrid { cell in
                PlayCellView(
                    number: board[cell],
                    isCenter: cell.isCenter,
                    isMarked: marked.contains(cell),
                    isWinning: progress.isWinner && progress.winningCells.contains(cell),
                    isNeeded: !board.isEmpty && progress.highlightCells.contains(cell),
                    isLastCall: lastCall != nil && board[cell] == lastCall
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(progress.isWinner ? Color.green : .clear, lineWidth: 3)
        )
    }

    @ViewBuilder
    private var status: some View {
        if board.isEmpty {
            Label("Not set up", systemImage: "exclamationmark.circle")
                .foregroundStyle(.orange)
        } else if progress.isWinner {
            Label("BINGO!", systemImage: "star.fill")
                .font(.headline)
                .foregroundStyle(.green)
        } else if progress.requiredPlacements > progress.totalPlacements {
            Text("Rule can't be met")
                .foregroundStyle(.secondary)
        } else {
            Text(progress.cellsAway == 1 ? "1 to go" : "\(progress.cellsAway) to go")
                .foregroundStyle(progress.cellsAway <= 1 ? .orange : .secondary)
                .fontWeight(progress.cellsAway <= 1 ? .bold : .regular)
        }
    }
}
