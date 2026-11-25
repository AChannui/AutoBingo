import Foundation

/// One physical bingo card: 25 numbers stored in row-major order.
/// A `nil` number means "blank" — normal for a printed FREE center, a problem anywhere else.
public struct BingoBoard: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public private(set) var numbers: [Int?]

    public init(id: UUID = UUID(), name: String, numbers: [Int?] = Array(repeating: nil, count: 25)) {
        precondition(numbers.count == 25, "A bingo board needs exactly 25 cells")
        self.id = id
        self.name = name
        self.numbers = numbers
    }

    /// Convenience for tests/previews: five rows of five values.
    public init(id: UUID = UUID(), name: String, rows: [[Int?]]) {
        precondition(rows.count == 5 && rows.allSatisfy { $0.count == 5 }, "Need 5 rows of 5")
        self.init(id: id, name: name, numbers: rows.flatMap { $0 })
    }

    public subscript(cell: Cell) -> Int? {
        get { numbers[cell.index] }
        set { numbers[cell.index] = newValue }
    }

    public var isEmpty: Bool { numbers.allSatisfy { $0 == nil } }

    /// Replace all 25 numbers at once (e.g. from a scanned photo). Ignores arrays of the wrong size.
    public mutating func replaceNumbers(with newNumbers: [Int?]) {
        guard newNumbers.count == 25 else { return }
        numbers = newNumbers
    }

    public mutating func clear() {
        numbers = Array(repeating: nil, count: 25)
    }

    /// Cells holding the given number (normally zero or one).
    public func cells(containing number: Int) -> [Cell] {
        Cell.all.filter { self[$0] == number }
    }

    /// Problems a person should look at before playing — usually OCR or typing mistakes.
    public var issues: [BoardIssue] {
        var result: [BoardIssue] = []
        var seen: [Int: [Cell]] = [:]

        for cell in Cell.all {
            guard let number = self[cell] else {
                if !cell.isCenter { result.append(.missing(cell)) }
                continue
            }
            let column = BingoColumn(rawValue: cell.column)!
            if !column.range.contains(number) {
                result.append(.outOfColumnRange(cell, number, column))
            }
            seen[number, default: []].append(cell)
        }

        for (number, cells) in seen.sorted(by: { $0.key < $1.key }) where cells.count > 1 {
            result.append(.duplicate(number, cells))
        }
        return result
    }

    public var isReadyToPlay: Bool { issues.isEmpty }
}

public enum BoardIssue: Hashable, Sendable {
    case missing(Cell)
    case outOfColumnRange(Cell, Int, BingoColumn)
    case duplicate(Int, [Cell])

    public var cells: [Cell] {
        switch self {
        case .missing(let cell), .outOfColumnRange(let cell, _, _): [cell]
        case .duplicate(_, let cells): cells
        }
    }

    public var message: String {
        switch self {
        case .missing(let cell):
            "\(BingoColumn(rawValue: cell.column)!.letter) column, row \(cell.row + 1) is empty"
        case .outOfColumnRange(_, let number, let column):
            "\(number) can't be in the \(column.letter) column (\(column.range.lowerBound)–\(column.range.upperBound))"
        case .duplicate(let number, _):
            "\(number) appears more than once"
        }
    }
}
