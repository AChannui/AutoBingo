/// A position on a 5×5 bingo card. Row 0 is the top row, column 0 is the "B" column.
public struct Cell: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let row: Int
    public let column: Int

    public init(_ row: Int, _ column: Int) {
        self.row = row
        self.column = column
    }

    public static let gridSize = 5
    public static let center = Cell(2, 2)

    /// All 25 cells in row-major order (left to right, top to bottom).
    public static let all: [Cell] = (0..<gridSize).flatMap { row in
        (0..<gridSize).map { column in Cell(row, column) }
    }

    /// Index into a row-major array of 25 values.
    public var index: Int { row * Cell.gridSize + column }
    public var isCenter: Bool { self == .center }
    public var isOnBoard: Bool {
        (0..<Cell.gridSize).contains(row) && (0..<Cell.gridSize).contains(column)
    }

    public var description: String { "(\(row),\(column))" }

    public static func < (lhs: Cell, rhs: Cell) -> Bool {
        (lhs.row, lhs.column) < (rhs.row, rhs.column)
    }
}

/// The five lettered columns of a 75-ball bingo card and the numbers each may hold.
public enum BingoColumn: Int, CaseIterable, Codable, Sendable, Comparable, Identifiable {
    case b, i, n, g, o

    public var id: Int { rawValue }
    public var letter: String { ["B", "I", "N", "G", "O"][rawValue] }

    /// B: 1–15, I: 16–30, N: 31–45, G: 46–60, O: 61–75
    public var range: ClosedRange<Int> { (rawValue * 15 + 1)...(rawValue * 15 + 15) }

    /// The column a called number belongs to, or nil if it isn't 1–75.
    public init?(number: Int) {
        guard BingoColumn.validNumbers.contains(number) else { return nil }
        self.init(rawValue: (number - 1) / 15)
    }

    public init?(letter: Character) {
        guard let index = ["B", "I", "N", "G", "O"].firstIndex(of: String(letter).uppercased()) else {
            return nil
        }
        self.init(rawValue: index)
    }

    public static let validNumbers = 1...75

    /// "G-54" style label for a called number.
    public static func label(for number: Int) -> String {
        guard let column = BingoColumn(number: number) else { return "\(number)" }
        return "\(column.letter)-\(number)"
    }

    public static func < (lhs: BingoColumn, rhs: BingoColumn) -> Bool { lhs.rawValue < rhs.rawValue }
}
