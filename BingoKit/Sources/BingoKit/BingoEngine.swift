/// How close a board is to satisfying the winning rule.
public struct RuleProgress: Hashable, Sendable {
    public let totalPlacements: Int
    public let requiredPlacements: Int
    public let completedPlacements: [Set<Cell>]
    /// The placements the board is closest to finishing (enough to meet the rule).
    public let targetCells: Set<Cell>
    /// Cells in `targetCells` that still need to be called.
    public let missingCells: Set<Cell>

    public var isWinner: Bool {
        totalPlacements > 0
            && requiredPlacements <= totalPlacements
            && completedPlacements.count >= requiredPlacements
    }

    /// Cells that are part of a completed placement — highlight these on a win.
    public var winningCells: Set<Cell> {
        completedPlacements.reduce(into: Set<Cell>()) { $0.formUnion($1) }
    }

    /// Roughly how many more numbers this board needs (0 when it has won).
    public var cellsAway: Int { isWinner ? 0 : missingCells.count }
}

/// Pure bingo logic: no UI, no camera, easy to unit test.
public enum BingoEngine {
    /// Cells covered by a called number, plus the center when it's free.
    public static func markedCells(on board: BingoBoard, called: Set<Int>, freeCenter: Bool) -> Set<Cell> {
        Set(Cell.all.filter { cell in
            if cell.isCenter && freeCenter { return true }
            guard let number = board[cell] else { return false }
            return called.contains(number)
        })
    }

    public static func evaluate(_ rule: WinningRule, marked: Set<Cell>) -> RuleProgress {
        let placements = rule.placements
        let required = rule.occurrence.requiredCount(outOf: placements.count)
        let completed = placements.filter { $0.isSubset(of: marked) }

        // Pick the placements nearest completion so the UI can show what's still needed.
        let nearest = placements.enumerated()
            .sorted { lhs, rhs in
                let l = lhs.element.subtracting(marked).count
                let r = rhs.element.subtracting(marked).count
                return l != r ? l < r : lhs.offset < rhs.offset
            }
            .prefix(required)
            .map(\.element)
        let target = nearest.reduce(into: Set<Cell>()) { $0.formUnion($1) }

        return RuleProgress(
            totalPlacements: placements.count,
            requiredPlacements: required,
            completedPlacements: completed,
            targetCells: target,
            missingCells: target.subtracting(marked)
        )
    }

    public static func evaluate(
        _ rule: WinningRule, board: BingoBoard, called: Set<Int>, freeCenter: Bool
    ) -> RuleProgress {
        evaluate(rule, marked: markedCells(on: board, called: called, freeCenter: freeCenter))
    }
}
