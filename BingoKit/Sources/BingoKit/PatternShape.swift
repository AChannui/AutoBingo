/// A set of cells drawn on a 5×5 grid, e.g. a 2×2 square or a T.
/// `cells` keeps the position as drawn (used for "exactly as drawn" rules);
/// orientations are computed from the shape moved to the top-left corner.
public struct PatternShape: Codable, Hashable, Sendable {
    public private(set) var cells: Set<Cell>

    public init(_ cells: Set<Cell>) {
        self.cells = cells.filter(\.isOnBoard)
    }

    /// Draw a shape with strings, using "X" for a filled cell: `PatternShape(rows: ["XX", "XX"])`.
    public init(rows: [String]) {
        var cells = Set<Cell>()
        for (row, line) in rows.enumerated() {
            for (column, character) in line.enumerated() where character == "X" {
                cells.insert(Cell(row, column))
            }
        }
        self.init(cells)
    }

    public var isEmpty: Bool { cells.isEmpty }

    public mutating func toggle(_ cell: Cell) {
        if cells.contains(cell) { cells.remove(cell) } else if cell.isOnBoard { cells.insert(cell) }
    }

    /// The shape moved so its top-most row and left-most column are 0.
    public var normalized: Set<Cell> { PatternShape.normalize(cells) }

    /// Distinct orientations of the shape (each normalized), in a stable order.
    public func orientations(_ orientation: Orientation) -> [Set<Cell>] {
        guard !cells.isEmpty else { return [] }
        var candidates: [Set<Cell>] = [normalized]

        if orientation != .fixed {
            for _ in 0..<3 { candidates.append(PatternShape.rotate(candidates.last!)) }
        }
        if orientation == .rotationsAndReflections {
            candidates += candidates.map(PatternShape.reflect)
        }
        return candidates.uniqued()
    }

    // MARK: Presets

    public static let square2x2 = PatternShape(rows: ["XX",
                                               "XX"])
    /// Three columns wide, two rows tall.
    public static let rectangle3x2 = PatternShape(rows: ["XXX",
                                                  "XXX"])
    /// Three across with a stem extending two squares down from the middle.
    public static let tShape = PatternShape(rows: ["XXX",
                                            ".X.",
                                            ".X."])
    public static let fullCard = PatternShape(Set(Cell.all))

    // MARK: Geometry helpers

    static func normalize(_ cells: Set<Cell>) -> Set<Cell> {
        guard let minRow = cells.map(\.row).min(), let minColumn = cells.map(\.column).min() else {
            return []
        }
        return Set(cells.map { Cell($0.row - minRow, $0.column - minColumn) })
    }

    /// Rotate 90° clockwise.
    static func rotate(_ cells: Set<Cell>) -> Set<Cell> {
        normalize(Set(cells.map { Cell($0.column, -$0.row) }))
    }

    /// Mirror left ↔ right.
    static func reflect(_ cells: Set<Cell>) -> Set<Cell> {
        normalize(Set(cells.map { Cell($0.row, -$0.column) }))
    }

    /// Height and width of a normalized cell set.
    static func size(of cells: Set<Cell>) -> (height: Int, width: Int) {
        ((cells.map(\.row).max() ?? -1) + 1, (cells.map(\.column).max() ?? -1) + 1)
    }
}

extension Array where Element: Hashable {
    /// Removes duplicates while keeping the first occurrence's order.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
