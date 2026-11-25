/// Whether a shape may be turned or flipped when looking for it on a card.
public enum Orientation: String, Codable, CaseIterable, Sendable, Identifiable {
    case fixed
    case rotations
    case rotationsAndReflections

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .fixed: "As drawn"
        case .rotations: "Rotations"
        case .rotationsAndReflections: "Rotate & flip"
        }
    }
}

public enum Corner: String, Codable, CaseIterable, Sendable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }
}

/// Where on the card a shape is allowed to appear.
public enum Placement: Codable, Hashable, Sendable {
    /// Any position where the shape fits.
    case anywhere
    /// Only tucked into the chosen corners.
    case corners(Set<Corner>)
    /// Only in exactly the cells drawn (no moving, turning or flipping).
    case exactlyAsDrawn
}

/// How many placements must be complete to win.
public enum Occurrence: Codable, Hashable, Sendable {
    case any
    case atLeast(Int)
    case all

    public func requiredCount(outOf total: Int) -> Int {
        switch self {
        case .any: 1
        case .atLeast(let count): max(1, count)
        case .all: max(1, total)
        }
    }
}

public enum Pattern: Codable, Hashable, Sendable {
    /// Five in a row: any row or column, plus the two diagonals if enabled.
    case line(includeDiagonals: Bool)
    /// Complete B/I/N/G/O column(s); combine with `.any` or `.all`.
    case columns(Set<BingoColumn>)
    /// A drawn shape, placed according to the rules.
    case shape(PatternShape, placement: Placement, orientation: Orientation)

    /// Every distinct set of cells that would count as one occurrence of this pattern.
    public var placements: [Set<Cell>] {
        let size = Cell.gridSize
        switch self {
        case .line(let includeDiagonals):
            var result = (0..<size).map { row in Set((0..<size).map { Cell(row, $0) }) }
            result += (0..<size).map { column in Set((0..<size).map { Cell($0, column) }) }
            if includeDiagonals {
                result.append(Set((0..<size).map { Cell($0, $0) }))
                result.append(Set((0..<size).map { Cell($0, size - 1 - $0) }))
            }
            return result

        case .columns(let columns):
            return columns.sorted().map { column in
                Set((0..<size).map { Cell($0, column.rawValue) })
            }

        case .shape(let shape, let placement, let orientation):
            guard !shape.isEmpty else { return [] }
            if case .exactlyAsDrawn = placement { return [shape.cells] }

            var result: [Set<Cell>] = []
            for cells in shape.orientations(orientation) {
                let (height, width) = PatternShape.size(of: cells)
                let offsets: [(Int, Int)]
                switch placement {
                case .anywhere:
                    offsets = (0...(size - height)).flatMap { row in
                        (0...(size - width)).map { column in (row, column) }
                    }
                case .corners(let corners):
                    offsets = Corner.allCases.filter(corners.contains).map { corner in
                        switch corner {
                        case .topLeft: (0, 0)
                        case .topRight: (0, size - width)
                        case .bottomLeft: (size - height, 0)
                        case .bottomRight: (size - height, size - width)
                        }
                    }
                case .exactlyAsDrawn:
                    offsets = []
                }
                for (rowOffset, columnOffset) in offsets {
                    result.append(Set(cells.map { Cell($0.row + rowOffset, $0.column + columnOffset) }))
                }
            }
            return result.uniqued()
        }
    }
}

/// The rule for the current game: a pattern plus how many times it must appear.
public struct WinningRule: Codable, Hashable, Sendable {
    public var name: String
    public var pattern: Pattern
    public var occurrence: Occurrence

    public init(name: String, pattern: Pattern, occurrence: Occurrence = .any) {
        self.name = name
        self.pattern = pattern
        self.occurrence = occurrence
    }

    public var placements: [Set<Cell>] { pattern.placements }

    /// A short human description of placement and occurrence settings.
    public var detail: String {
        let total = placements.count
        var parts: [String] = []
        switch pattern {
        case .line(let diagonals):
            parts.append(diagonals ? "rows, columns or diagonals" : "rows or columns only")
        case .columns(let columns):
            parts.append(columns.sorted().map(\.letter).joined(separator: ", "))
        case .shape(_, let placement, let orientation):
            switch placement {
            case .anywhere: parts.append("anywhere")
            case .corners(let corners):
                parts.append(corners.count == 4 ? "corners" : "\(corners.count) chosen corner\(corners.count == 1 ? "" : "s")")
            case .exactlyAsDrawn: parts.append("exactly as drawn")
            }
            if placement != .exactlyAsDrawn && orientation != .fixed {
                parts.append(orientation == .rotations ? "rotations" : "rotate & flip")
            }
        }
        if total > 1 {
            switch occurrence {
            case .any: parts.append("any one")
            case .atLeast(let n): parts.append("at least \(n)")
            case .all: parts.append("all \(total)")
            }
        }
        return parts.joined(separator: " · ")
    }

    public static let fiveInARow = WinningRule(name: "Five in a row", pattern: .line(includeDiagonals: true))
    public static let blackout = WinningRule(
        name: "Blackout",
        pattern: .shape(.fullCard, placement: .exactlyAsDrawn, orientation: .fixed)
    )
}
