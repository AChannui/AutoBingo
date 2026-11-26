import Foundation

/// Everything about the game in progress: every saved board, how they're grouped, which of them
/// are in play, the calls so far and the rules.
/// Marks are never stored — they're derived from `calls`, so undo is always safe, and a board
/// switched into play mid-game picks up every number already called.
public struct BingoGame: Codable, Hashable, Sendable {
    /// All saved boards, whether or not they're being played right now.
    public var boards: [BingoBoard] {
        didSet { forgetDeletedBoards() }
    }
    /// Named sets of saved boards, for putting several into play at once.
    public var groups: [BoardGroup] {
        didSet { forgetDeletedBoards() }
    }
    /// The boards in play, in the order they were switched on. Only these are marked and checked for wins.
    public private(set) var activeBoardIDs: [UUID]
    public private(set) var calls: [Int]
    public var freeCenter: Bool
    public var rule: WinningRule

    /// - Parameter activeBoardIDs: which boards are in play; `nil` means all of them.
    public init(
        boards: [BingoBoard] = [],
        groups: [BoardGroup] = [],
        activeBoardIDs: [UUID]? = nil,
        calls: [Int] = [],
        freeCenter: Bool = true,
        rule: WinningRule = .fiveInARow
    ) {
        self.boards = boards
        self.groups = groups
        self.activeBoardIDs = activeBoardIDs ?? boards.map(\.id)
        self.calls = calls
        self.freeCenter = freeCenter
        self.rule = rule
        forgetDeletedBoards()
    }

    private enum CodingKeys: String, CodingKey {
        case boards, groups, activeBoardIDs, calls, freeCenter, rule
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let boards = try container.decode([BingoBoard].self, forKey: .boards)
        self.init(
            boards: boards,
            groups: try container.decodeIfPresent([BoardGroup].self, forKey: .groups) ?? [],
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

    /// Makes the called numbers exactly `numbers` — used when a photo of the caller's board,
    /// which shows every call so far, is the source of truth.
    ///
    /// The photo doesn't say what order numbers were called in, so calls already made keep
    /// their order and new ones follow, lowest first — except `latest`, which goes last
    /// (if it's one of `numbers`). Invalid numbers are ignored.
    public mutating func replaceCalls(with numbers: Set<Int>, latest: Int? = nil) {
        let valid = numbers.filter { BingoColumn.validNumbers.contains($0) }
        let latest = latest.flatMap { valid.contains($0) ? $0 : nil }
        var result = calls.filter { valid.contains($0) && $0 != latest }
        let kept = Set(result)
        result += valid.filter { !kept.contains($0) && $0 != latest }.sorted()
        if let latest { result.append(latest) }
        calls = result
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
        forgetDeletedBoards()
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

    // MARK: Groups

    /// Saves a new group and returns its ID. Board IDs that aren't saved boards are ignored.
    @discardableResult
    public mutating func addGroup(name: String, boardIDs: [UUID] = []) -> UUID {
        let group = BoardGroup(name: name, boardIDs: boardIDs)
        groups.append(group)
        return group.id
    }

    public mutating func removeGroup(id: UUID) {
        groups.removeAll { $0.id == id }
    }

    public mutating func removeGroups(ids: Set<UUID>) {
        groups.removeAll { ids.contains($0.id) }
    }

    public func group(id: UUID) -> BoardGroup? {
        groups.first { $0.id == id }
    }

    /// The group's boards, in group order, skipping any that were deleted.
    public func boards(in group: BoardGroup) -> [BingoBoard] {
        let byID = Dictionary(uniqueKeysWithValues: boards.map { ($0.id, $0) })
        return group.boardIDs.compactMap { byID[$0] }
    }

    /// Groups this board belongs to.
    public func groups(containing boardID: UUID) -> [BoardGroup] {
        groups.filter { $0.contains(boardID) }
    }

    public mutating func setBoard(_ boardID: UUID, inGroup groupID: UUID, _ included: Bool) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        if included {
            guard boards.contains(where: { $0.id == boardID }), !groups[index].contains(boardID) else { return }
            groups[index].boardIDs.append(boardID)
        } else {
            groups[index].boardIDs.removeAll { $0 == boardID }
        }
    }

    /// Puts a group's boards into play. Replacing takes every other board out of play;
    /// otherwise the group's boards are added after the ones already playing.
    public mutating func playGroup(id: UUID, replacingActive: Bool = true) {
        guard let group = group(id: id) else { return }
        setActiveBoards((replacingActive ? [] : activeBoardIDs) + group.boardIDs)
    }

    /// Takes a group's boards out of play, leaving any others playing.
    public mutating func stopPlayingGroup(id: UUID) {
        guard let group = group(id: id) else { return }
        activeBoardIDs.removeAll { group.contains($0) }
    }

    public enum GroupPlayState: Equatable, Sendable {
        /// None of the group's boards are playing (or the group is empty).
        case notPlaying
        /// Some of its boards are playing.
        case partlyPlaying
        /// All of its boards are playing, along with others.
        case playingWithOthers
        /// Exactly this group's boards are playing.
        case playing
    }

    public func playState(of group: BoardGroup) -> GroupPlayState {
        let members = Set(group.boardIDs)
        let active = Set(activeBoardIDs)
        let playingMembers = members.intersection(active)
        if members.isEmpty || playingMembers.isEmpty { return .notPlaying }
        if playingMembers.count < members.count { return .partlyPlaying }
        return active == members ? .playing : .playingWithOthers
    }

    /// "Group N", one past the highest such number already used.
    public func nextGroupName() -> String {
        let used = groups.compactMap { group -> Int? in
            guard group.name.hasPrefix("Group ") else { return nil }
            return Int(group.name.dropFirst("Group ".count))
        }
        return "Group \((used.max() ?? 0) + 1)"
    }

    /// Drops deleted boards from the play list and from every group.
    private mutating func forgetDeletedBoards() {
        let saved = Set(boards.map(\.id))
        if activeBoardIDs.contains(where: { !saved.contains($0) }) {
            activeBoardIDs.removeAll { !saved.contains($0) }
        }
        for index in groups.indices where groups[index].boardIDs.contains(where: { !saved.contains($0) }) {
            groups[index].boardIDs.removeAll { !saved.contains($0) }
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
