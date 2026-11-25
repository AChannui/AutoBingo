/// Everything about the game in progress: three boards, the calls so far and the rules.
/// Marks are never stored — they're derived from `calls`, so undo is always safe.
public struct BingoGame: Codable, Hashable, Sendable {
    public static let boardCount = 3

    public var boards: [BingoBoard]
    public private(set) var calls: [Int]
    public var freeCenter: Bool
    public var rule: WinningRule

    public init(
        boards: [BingoBoard] = BingoGame.emptyBoards(),
        calls: [Int] = [],
        freeCenter: Bool = true,
        rule: WinningRule = .fiveInARow
    ) {
        self.boards = boards
        self.calls = calls
        self.freeCenter = freeCenter
        self.rule = rule
    }

    public static func emptyBoards() -> [BingoBoard] {
        (1...boardCount).map { BingoBoard(name: "Board \($0)") }
    }

    public enum CallResult: Equatable, Sendable {
        case added
        case duplicate
        case invalid
    }

    public var calledNumbers: Set<Int> { Set(calls) }
    public var lastCall: Int? { calls.last }

    @discardableResult
    public mutating func call(_ number: Int) -> CallResult {
        guard BingoColumn.validNumbers.contains(number) else { return .invalid }
        guard !calls.contains(number) else { return .duplicate }
        calls.append(number)
        return .added
    }

    @discardableResult
    public mutating func undoLastCall() -> Int? {
        calls.popLast()
    }

    public mutating func removeCall(_ number: Int) {
        calls.removeAll { $0 == number }
    }

    /// Clears the calls. Rules and free-center setting carry over; boards optionally do too.
    public mutating func startNewGame(keepBoards: Bool) {
        calls.removeAll()
        if !keepBoards { boards = BingoGame.emptyBoards() }
    }

    public func markedCells(on board: BingoBoard) -> Set<Cell> {
        BingoEngine.markedCells(on: board, called: calledNumbers, freeCenter: freeCenter)
    }

    public func progress(for board: BingoBoard) -> RuleProgress {
        BingoEngine.evaluate(rule, marked: markedCells(on: board))
    }

    public var winningBoards: [BingoBoard] {
        boards.filter { progress(for: $0).isWinner }
    }

    /// Boards that have this number somewhere on them.
    public func boards(containing number: Int) -> [BingoBoard] {
        boards.filter { !$0.cells(containing: number).isEmpty }
    }
}
