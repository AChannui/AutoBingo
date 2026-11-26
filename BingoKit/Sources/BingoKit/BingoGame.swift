import Foundation

/// Everything about the game in progress: every saved board, which of them are in play,
/// the calls so far and the rules.
/// Marks are never stored — they're derived from `calls`, so undo is always safe, and a board
/// switched into play mid-game picks up every number already called.
public struct BingoGame: Codable, Hashable, Sendable {
    /// All saved boards, whether or not they're being played right now.
    public var boards: [BingoBoard] {
        didSet { pruneActiveIDs() }
    }
    /// The boards in play, in the order they were switched on. Only these are marked and checked for wins.
    public private(set) var activeBoardIDs: [UUID]
    public private(set) var calls: [Int]
    public var freeCenter: Bool
    public var rule: WinningRule

    /// - Parameter activeBoardIDs: which boards are in play; `nil` means all of them.
    public init(
        boards: [BingoBoard] = [],
        activeBoardIDs: [UUID]? = nil,
        calls: [Int] = [],
        freeCenter: Bool = true,
        rule: WinningRule = .fiveInARow
    ) {
        self.boards = boards
        self.activeBoardIDs = activeBoardIDs ?? boards.map(\.id)
        self.calls = calls
        self.freeCenter = freeCenter
        self.rule = rule
        pruneActiveIDs()
    }

    private enum CodingKeys: String, CodingKey {
        case boards, activeBoardIDs, calls, freeCenter, rule
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let boards = try container.decode([BingoBoard].self, forKey: .boards)
        self.init(
            boards: boards,
            // Games saved before boards could be switched on and off had every board in play.
            activeBoardIDs: try container.decodeIfPresent([UUID].self, forKey: .activeBoardIDs),
            calls: try container.decode([Int].self, forKey: .calls),
            freeCenter: try container.decode(Bool.self, forKey: .freeCenter),
            rule: try container.decode(WinningRule.self, forKey: .rule)
        )
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

    /// Clears the calls. Rules, free-center setting and saved boards carry over; the boards
    /// in play optionally do too (otherwise everything is put aside, ready to pick again).
    public mutating func startNewGame(keepActiveBoards: Bool) {
        calls.removeAll()
        if !keepActiveBoards { activeBoardIDs.removeAll() }
    }

    // MARK: Saved and active boards

    /// The boards in play, in the order they were switched on.
    public var activeBoards: [BingoBoard] {
        let byID = Dictionary(uniqueKeysWithValues: boards.map { ($0.id, $0) })
        return activeBoardIDs.compactMap { byID[$0] }
    }

    /// Saved boards that aren't in play, in the order they were saved.
    public var inactiveBoards: [BingoBoard] {
        let active = Set(activeBoardIDs)
        return boards.filter { !active.contains($0.id) }
    }

    public func isActive(_ boardID: UUID) -> Bool {
        activeBoardIDs.contains(boardID)
    }

    /// Puts a saved board into play (added after the ones already in play), or takes it out.
    public mutating func setActive(_ active: Bool, boardID: UUID) {
        if active {
            guard boards.contains(where: { $0.id == boardID }), !isActive(boardID) else { return }
            activeBoardIDs.append(boardID)
        } else {
            activeBoardIDs.removeAll { $0 == boardID }
        }
    }

    /// Makes exactly these boards the ones in play, in this order.
    public mutating func setActiveBoards(_ boardIDs: [UUID]) {
        var seen = Set<UUID>()
        activeBoardIDs = boardIDs.filter { seen.insert($0).inserted }
        pruneActiveIDs()
    }

    /// Saves a new board; it goes into play only if asked.
    public mutating func addBoard(_ board: BingoBoard, active: Bool = false) {
        boards.append(board)
        if active { setActive(true, boardID: board.id) }
    }

    public mutating func removeBoard(id: UUID) {
        boards.removeAll { $0.id == id }
    }

    /// "Board N", one past the highest such number already used, so names stay unique.
    public func nextBoardName() -> String {
        let used = boards.compactMap { board -> Int? in
            guard board.name.hasPrefix("Board ") else { return nil }
            return Int(board.name.dropFirst("Board ".count))
        }
        return "Board \((used.max() ?? 0) + 1)"
    }

    private mutating func pruneActiveIDs() {
        let saved = Set(boards.map(\.id))
        if activeBoardIDs.contains(where: { !saved.contains($0) }) {
            activeBoardIDs.removeAll { !saved.contains($0) }
        }
    }

    // MARK: Marking and winning

    public func markedCells(on board: BingoBoard) -> Set<Cell> {
        BingoEngine.markedCells(on: board, called: calledNumbers, freeCenter: freeCenter)
    }

    public func progress(for board: BingoBoard) -> RuleProgress {
        BingoEngine.evaluate(rule, marked: markedCells(on: board))
    }

    /// Boards in play that have won.
    public var winningBoards: [BingoBoard] {
        activeBoards.filter { progress(for: $0).isWinner }
    }

    /// Boards in play that have this number somewhere on them.
    public func boards(containing number: Int) -> [BingoBoard] {
        activeBoards.filter { !$0.cells(containing: number).isEmpty }
    }
}
