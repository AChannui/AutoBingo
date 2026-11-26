import BingoKit
import BingoRecognition
import SwiftUI

/// What was read from a photo of the caller's board — every number, lit or not — laid out
/// B I N G O so it can be checked against the screen. Tapping a number flips it.
/// The photo is the source of truth: applying replaces the called numbers with these.
struct CalledBoardReviewView: View {
    let reading: CalledBoardReading
    /// The numbers to apply; starts as what the photo showed, edited by tapping.
    @Binding var selection: Set<Int>
    /// Numbers called in the game right now, to show what will change.
    let current: Set<Int>

    private var added: [Int] { selection.subtracting(current).sorted() }
    private var removed: [Int] { current.subtracting(selection).sorted() }
    /// Numbers the person has already tapped to fix, so they stop being flagged.
    @State private var checked: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            summary
            grid
            legend
            changes
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(selection.count) called")
                .font(.title2.bold())
            if let shown = reading.shownCount {
                if shown == selection.count {
                    Label("Matches the screen's count of \(shown)", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                } else {
                    Label("The screen says \(shown) called — check the board below", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            if !reading.isClear {
                Label("Lit and unlit numbers were hard to tell apart in this photo. Please check every number, or retake it closer.",
                      systemImage: "eye")
                    .foregroundStyle(.orange)
            } else if !flagged.isEmpty {
                Label("Not sure about \(flagged.count == 1 ? "1 number" : "\(flagged.count) numbers") — outlined in orange",
                      systemImage: "eye")
                    .foregroundStyle(.orange)
            }
        }
        .font(.subheadline)
    }

    private var flagged: Set<Int> { reading.uncertain.subtracting(checked) }

    /// Five columns of 15, like the tablets' board.
    private var grid: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 5) {
            GridRow {
                ForEach(BingoColumn.allCases) { column in
                    Text(column.letter)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<15, id: \.self) { step in
                GridRow {
                    ForEach(BingoColumn.allCases) { column in
                        cell(column.range.lowerBound + step)
                    }
                }
            }
        }
    }

    private func cell(_ number: Int) -> some View {
        let isCalled = selection.contains(number)
        let isFlagged = flagged.contains(number)
        let changed = isCalled != current.contains(number)
        return Button {
            if isCalled { selection.remove(number) } else { selection.insert(number) }
            checked.insert(number)
        } label: {
            Text("\(number)")
                .font(.callout.weight(isCalled ? .bold : .regular).monospacedDigit())
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isCalled ? Color.accentColor : Color(.tertiarySystemFill))
                )
                .foregroundStyle(isCalled ? Color.white : Color.secondary)
                .overlay {
                    if isFlagged {
                        RoundedRectangle(cornerRadius: 7).strokeBorder(.orange, lineWidth: 2.5)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if changed {
                        // A dot on numbers this photo will add or remove.
                        Circle()
                            .fill(isCalled ? Color.green : Color.red)
                            .frame(width: 7, height: 7)
                            .padding(3)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BingoColumn.label(for: number))
        .accessibilityValue(isCalled ? "Called" : "Not called")
        .accessibilityHint("Double-tap to change")
    }

    private var legend: some View {
        HStack(spacing: 14) {
            Label("Tap a number to fix it", systemImage: "hand.tap")
            Spacer()
            legendDot(.green, "new")
            legendDot(.red, "removed")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
    }

    @ViewBuilder
    private var changes: some View {
        if added.isEmpty && removed.isEmpty {
            Label("Same as your called numbers — nothing to change", systemImage: "checkmark")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if !added.isEmpty {
                    Text("Adds \(labels(added))")
                }
                if !removed.isEmpty {
                    Text("Removes \(labels(removed))")
                        .foregroundStyle(.red)
                }
            }
            .font(.subheadline)
        }
    }

    private func labels(_ numbers: [Int]) -> String {
        numbers.map(BingoColumn.label(for:)).joined(separator: ", ")
    }
}
