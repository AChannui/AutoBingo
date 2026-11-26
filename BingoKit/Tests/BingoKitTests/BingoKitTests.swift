import Foundation
import Testing
@testable import BingoKit

// A valid card where cell (row, column) holds column*15 + row + 1.
//   B  I  N  G  O
//   1 16 31 46 61
//   2 17 32 47 62
//   3 18 33 48 63   ← center is 33
//   4 19 34 49 64
//   5 20 35 50 65
func sampleBoard(name: String = "Test", freeCenterBlank: Bool = false) -> BingoBoard {
    var board = BingoBoard(name: name)
    for cell in Cell.all { board[cell] = cell.column * 15 + cell.row + 1 }
    if freeCenterBlank { board[.center] = nil }
    return board
}

/// Marks exactly the given cells (no free center).
func marks(_ cells: [Cell]) -> Set<Cell> { Set(cells) }

func shapeRule(_ shape: PatternShape, _ placement: Placement, _ orientation: Orientation = .rotationsAndReflections,
               _ occurrence: Occurrence = .any) -> WinningRule {
    WinningRule(name: "test", pattern: .shape(shape, placement: placement, orientation: orientation),
                occurrence: occurrence)
}

@Suite("Columns and boards")
struct BoardTests {
    @Test func columnRanges() {
        #expect(BingoColumn(number: 1) == .b)
        #expect(BingoColumn(number: 15) == .b)
        #expect(BingoColumn(number: 16) == .i)
        #expect(BingoColumn(number: 54) == .g)
        #expect(BingoColumn(number: 75) == .o)
        #expect(BingoColumn(number: 0) == nil)
        #expect(BingoColumn(number: 76) == nil)
        #expect(BingoColumn.label(for: 54) == "G-54")
    }

    @Test func validBoardHasNoIssues() {
        #expect(sampleBoard().issues.isEmpty)
        #expect(sampleBoard(freeCenterBlank: true).issues.isEmpty, "Blank center is allowed")
    }

    @Test func detectsMissingOutOfRangeAndDuplicates() {
        var board = sampleBoard()
        board[Cell(0, 0)] = nil          // missing
        board[Cell(1, 0)] = 20           // 20 is an I number in the B column, and duplicates I row 4
        let issues = board.issues
        #expect(issues.contains(.missing(Cell(0, 0))))
        #expect(issues.contains(.outOfColumnRange(Cell(1, 0), 20, .b)))
        #expect(issues.contains(.duplicate(20, [Cell(1, 0), Cell(4, 1)])))
        #expect(!board.isReadyToPlay)
    }
}

@Suite("Calls and marking")
struct MarkingTests {
    @Test func calledNumberMarksAllThreeBoards() {
        var game = BingoGame(boards: [sampleBoard(name: "A"), sampleBoard(name: "B"), sampleBoard(name: "C")],
                             freeCenter: false)
        #expect(game.call(47) == .added)
        for board in game.boards {
            #expect(game.markedCells(on: board) == [Cell(1, 3)])
        }
    }

    @Test func duplicateAndInvalidCalls() {
        var game = BingoGame(boards: [sampleBoard()])
        #expect(game.call(5) == .added)
        #expect(game.call(5) == .duplicate)
        #expect(game.call(0) == .invalid)
        #expect(game.call(76) == .invalid)
        #expect(game.calls == [5])
    }

    @Test func freeCenterSetting() {
        let board = sampleBoard()
        #expect(BingoEngine.markedCells(on: board, called: [], freeCenter: true) == [.center])
        #expect(BingoEngine.markedCells(on: board, called: [], freeCenter: false).isEmpty)
        #expect(BingoEngine.markedCells(on: board, called: [33], freeCenter: false) == [.center])
    }

    @Test func replaceCallsFromBoardPhoto() {
        var game = BingoGame(boards: [sampleBoard()])
        game.call(40); game.call(5); game.call(70)
        // Photo shows 5, 70, 12, 3, 61 lit (61 the latest); 40 isn't lit any more; 99 is junk.
        game.replaceCalls(with: [5, 70, 12, 3, 61, 99], latest: 61)
        #expect(game.calls == [5, 70, 3, 12, 61], "Kept calls keep their order, new ones follow, latest last")
        #expect(game.lastCall == 61)

        game.replaceCalls(with: [5, 70], latest: 44)
        #expect(game.calls == [5, 70], "A latest number that isn't lit is ignored")

        game.replaceCalls(with: [])
        #expect(game.calls.isEmpty)
    }

    @Test func undoRemoveAndNewGame() {
        var game = BingoGame(boards: [sampleBoard()])
        game.call(1); game.call(2); game.call(3)
        #expect(game.undoLastCall() == 3)
        game.removeCall(1)
        #expect(game.calls == [2])
        game.startNewGame(keepActiveBoards: true)
        #expect(game.calls.isEmpty)
        #expect(game.activeBoards.count == 1)
        game.call(4)
        game.startNewGame(keepActiveBoards: false)
        #expect(game.calls.isEmpty)
        #expect(game.boards.count == 1, "Saved boards are kept")
        #expect(game.activeBoards.isEmpty)
    }

    @Test func onlyActiveBoardsCountForHitsAndWins() {
        let a = sampleBoard(name: "A"), b = sampleBoard(name: "B")
        var game = BingoGame(boards: [a, b], activeBoardIDs: [b.id], freeCenter: false)
        for n in [1, 16, 31, 46, 61] { game.call(n) }  // top row
        #expect(game.boards(containing: 1).map(\.name) == ["B"])
        #expect(game.winningBoards.map(\.name) == ["B"])
        game.setActive(true, boardID: a.id)
        #expect(game.winningBoards.map(\.name) == ["B", "A"], "A board switched on mid-game picks up earlier calls")
        game.setActive(false, boardID: b.id)
        #expect(game.activeBoards.map(\.name) == ["A"])
        #expect(game.inactiveBoards.map(\.name) == ["B"])
    }

    @Test func removingABoardTakesItOutOfPlay() {
        let a = sampleBoard(name: "A"), b = sampleBoard(name: "B")
        var game = BingoGame(boards: [a, b])
        game.removeBoard(id: a.id)
        #expect(game.activeBoardIDs == [b.id])
        game.setActive(true, boardID: a.id)  // no longer saved: ignored
        #expect(game.activeBoardIDs == [b.id])
    }

    @Test func manyBoardsCanBeSavedAndActive() {
        var game = BingoGame()
        for _ in 0..<8 { game.addBoard(BingoBoard(name: game.nextBoardName())) }
        #expect(game.boards.count == 8 && game.activeBoards.isEmpty)
        #expect(game.boards.last?.name == "Board 8")
        game.setActiveBoards(game.boards.prefix(5).map(\.id))
        #expect(game.activeBoards.count == 5 && game.inactiveBoards.count == 3)
    }

    @Test func oldSavesWithoutActiveListPlayEveryBoard() throws {
        let board = sampleBoard()
        let old = #"{"boards":[\#(String(decoding: try JSONEncoder().encode(board), as: UTF8.self))],"calls":[5],"freeCenter":true,"rule":\#(String(decoding: try JSONEncoder().encode(WinningRule.fiveInARow), as: UTF8.self))}"#
        let game = try JSONDecoder().decode(BingoGame.self, from: Data(old.utf8))
        #expect(game.activeBoardIDs == [board.id])
        #expect(game.calls == [5])
    }

    @Test func gameRoundTripsThroughJSON() throws {
        var game = BingoGame(boards: [sampleBoard()], freeCenter: false,
                             rule: shapeRule(.tShape, .corners([.topLeft]), .rotations, .atLeast(2)))
        game.call(12)
        game.addBoard(sampleBoard(name: "Saved"))
        game.addGroup(name: "G", boardIDs: game.boards.map(\.id))
        let decoded = try JSONDecoder().decode(BingoGame.self, from: JSONEncoder().encode(game))
        #expect(decoded == game)
    }
}

@Suite("Board groups")
struct GroupTests {
    let a = sampleBoard(name: "A"), b = sampleBoard(name: "B"), c = sampleBoard(name: "C")

    @Test func playingAGroupReplacesOrAdds() {
        var game = BingoGame(boards: [a, b, c], activeBoardIDs: [c.id])
        let group = game.addGroup(name: "Night", boardIDs: [a.id, b.id])
        game.playGroup(id: group, replacingActive: false)
        #expect(game.activeBoardIDs == [c.id, a.id, b.id])
        #expect(game.playState(of: game.group(id: group)!) == .playingWithOthers)
        game.playGroup(id: group)
        #expect(game.activeBoardIDs == [a.id, b.id])
        #expect(game.playState(of: game.group(id: group)!) == .playing)
        game.setActive(false, boardID: b.id)
        #expect(game.playState(of: game.group(id: group)!) == .partlyPlaying)
        game.stopPlayingGroup(id: group)
        #expect(game.activeBoardIDs.isEmpty)
        #expect(game.playState(of: game.group(id: group)!) == .notPlaying)
    }

    @Test func boardsCanBeInSeveralGroups() {
        var game = BingoGame(boards: [a, b, c])
        let one = game.addGroup(name: game.nextGroupName())
        let two = game.addGroup(name: game.nextGroupName())
        #expect(game.groups.map(\.name) == ["Group 1", "Group 2"])
        game.setBoard(a.id, inGroup: one, true)
        game.setBoard(a.id, inGroup: two, true)
        game.setBoard(a.id, inGroup: two, true)  // already in: ignored
        game.setBoard(b.id, inGroup: two, true)
        #expect(game.groups(containing: a.id).count == 2)
        #expect(game.group(id: two)?.boardIDs == [a.id, b.id])
        game.setBoard(a.id, inGroup: two, false)
        #expect(game.group(id: two)?.boardIDs == [b.id])
    }

    @Test func deletingABoardRemovesItFromGroups() {
        var game = BingoGame(boards: [a, b])
        let group = game.addGroup(name: "G", boardIDs: [a.id, b.id, UUID()])
        #expect(game.group(id: group)?.boardIDs == [a.id, b.id], "Unknown boards are dropped")
        game.removeBoard(id: a.id)
        #expect(game.group(id: group)?.boardIDs == [b.id])
        game.removeGroup(id: group)
        #expect(game.groups.isEmpty)
        #expect(game.boards.count == 1, "Deleting a group keeps its boards")
    }
}

@Suite("Five in a row and columns")
struct LineTests {
    let rule = WinningRule.fiveInARow

    @Test func rowColumnAndDiagonalWin() {
        #expect(BingoEngine.evaluate(rule, marked: marks((0..<5).map { Cell(3, $0) })).isWinner)
        #expect(BingoEngine.evaluate(rule, marked: marks((0..<5).map { Cell($0, 1) })).isWinner)
        #expect(BingoEngine.evaluate(rule, marked: marks((0..<5).map { Cell($0, 4 - $0) })).isWinner)
    }

    @Test func diagonalsCanBeExcluded() {
        let noDiagonals = WinningRule(name: "x", pattern: .line(includeDiagonals: false))
        #expect(noDiagonals.placements.count == 10)
        #expect(!BingoEngine.evaluate(noDiagonals, marked: marks((0..<5).map { Cell($0, $0) })).isWinner)
    }

    @Test func noWinWhenOneSquareMissing() {
        let progress = BingoEngine.evaluate(rule, marked: marks((0..<4).map { Cell(0, $0) }))
        #expect(!progress.isWinner)
        #expect(progress.cellsAway == 1)
        #expect(progress.missingCells == [Cell(0, 4)])
        #expect(progress.highlightCells == [Cell(0, 4)])
    }

    @Test func nothingHighlightedOnAFreshCard() {
        let progress = BingoEngine.evaluate(rule, marked: [])
        #expect(progress.highlightCells.isEmpty)
        #expect(progress.cellsAway == 5)
    }

    @Test func nothingHighlightedWhenStillFarAway() {
        // Two in the top row is three to go: too far for a hint.
        let progress = BingoEngine.evaluate(rule, marked: marks((0..<2).map { Cell(0, $0) }))
        #expect(progress.cellsAway == 3)
        #expect(progress.highlightCells.isEmpty)
    }

    @Test func tiedLinesAreAllHighlighted() {
        // Top row and left column are each two away; both should be shown, not just the first.
        let marked = marks([Cell(0, 0), Cell(0, 1), Cell(0, 2), Cell(1, 0), Cell(2, 0)])
        let progress = BingoEngine.evaluate(rule, marked: marked)
        #expect(progress.cellsAway == 2)
        #expect(progress.highlightCells == [Cell(0, 3), Cell(0, 4), Cell(3, 0), Cell(4, 0)])
    }

    @Test func onlyTheClosestLinesAreHighlighted() {
        // Top row is one away; the left column (two away) shouldn't be highlighted.
        let marked = marks([Cell(0, 0), Cell(0, 1), Cell(0, 2), Cell(0, 3), Cell(1, 0), Cell(2, 0)])
        let progress = BingoEngine.evaluate(rule, marked: marked)
        #expect(progress.highlightCells == [Cell(0, 4)])
    }

    @Test func nothingHighlightedOnAWin() {
        let progress = BingoEngine.evaluate(rule, marked: marks((0..<5).map { Cell(0, $0) }))
        #expect(progress.highlightCells.isEmpty)
    }

    @Test func freeCenterCompletesMiddleRowThroughGame() {
        var game = BingoGame(boards: [sampleBoard(freeCenterBlank: true)], freeCenter: true)
        for n in [3, 18, 48, 63] { game.call(n) }  // row 2 without the center
        #expect(game.progress(for: game.boards[0]).isWinner)
        game.freeCenter = false
        #expect(!game.progress(for: game.boards[0]).isWinner)
    }

    @Test func selectedColumnsAnyVersusAll() {
        let columnB = (0..<5).map { Cell($0, 0) }
        let anyRule = WinningRule(name: "x", pattern: .columns([.b, .o]), occurrence: .any)
        let allRule = WinningRule(name: "x", pattern: .columns([.b, .o]), occurrence: .all)
        #expect(BingoEngine.evaluate(anyRule, marked: marks(columnB)).isWinner)
        #expect(!BingoEngine.evaluate(allRule, marked: marks(columnB)).isWinner)
        let columnO = (0..<5).map { Cell($0, 4) }
        #expect(BingoEngine.evaluate(allRule, marked: marks(columnB + columnO)).isWinner)
        // An unselected column doesn't count.
        #expect(!BingoEngine.evaluate(anyRule, marked: marks((0..<5).map { Cell($0, 2) })).isWinner)
    }
}

@Suite("Shapes")
struct ShapeTests {
    @Test func orientationCounts() {
        #expect(PatternShape.square2x2.orientations(.rotationsAndReflections).count == 1)
        #expect(PatternShape.rectangle3x2.orientations(.rotationsAndReflections).count == 2)
        #expect(PatternShape.tShape.orientations(.rotations).count == 4)
        #expect(PatternShape.tShape.orientations(.rotationsAndReflections).count == 4, "T is symmetric")
        let lShape = PatternShape(rows: ["X.", "X.", "XX"])
        #expect(lShape.orientations(.rotations).count == 4)
        #expect(lShape.orientations(.rotationsAndReflections).count == 8)
        #expect(lShape.orientations(.fixed).count == 1)
    }

    @Test func placementCountsAnywhere() {
        #expect(shapeRule(.square2x2, .anywhere).placements.count == 16)
        #expect(shapeRule(.rectangle3x2, .anywhere, .fixed).placements.count == 12)
        #expect(shapeRule(.rectangle3x2, .anywhere).placements.count == 24)
        #expect(shapeRule(.tShape, .anywhere).placements.count == 36)
    }

    @Test func tShapeRotatedAtBoardEdge() {
        // T pointing left, against the right edge: stem along row 2, bar down column 4.
        let marked = marks([Cell(1, 4), Cell(2, 4), Cell(3, 4), Cell(2, 3), Cell(2, 2)])
        #expect(BingoEngine.evaluate(shapeRule(.tShape, .anywhere, .rotations), marked: marked).isWinner)
        #expect(!BingoEngine.evaluate(shapeRule(.tShape, .anywhere, .fixed), marked: marked).isWinner)
    }

    @Test func rectangleVertical() {
        let marked = marks([Cell(2, 0), Cell(3, 0), Cell(4, 0), Cell(2, 1), Cell(3, 1), Cell(4, 1)])
        #expect(BingoEngine.evaluate(shapeRule(.rectangle3x2, .anywhere), marked: marked).isWinner)
        #expect(!BingoEngine.evaluate(shapeRule(.rectangle3x2, .anywhere, .fixed), marked: marked).isWinner)
    }

    @Test func cornerOnlySquare() {
        let topLeft = [Cell(0, 0), Cell(0, 1), Cell(1, 0), Cell(1, 1)]
        let bottomRight = [Cell(3, 3), Cell(3, 4), Cell(4, 3), Cell(4, 4)]
        let middle = [Cell(1, 1), Cell(1, 2), Cell(2, 1), Cell(2, 2)]
        let allCorners = Set(Corner.allCases)

        #expect(shapeRule(.square2x2, .corners(allCorners)).placements.count == 4)
        #expect(BingoEngine.evaluate(shapeRule(.square2x2, .corners(allCorners)), marked: marks(topLeft)).isWinner)
        #expect(!BingoEngine.evaluate(shapeRule(.square2x2, .corners(allCorners)), marked: marks(middle)).isWinner)

        let two = shapeRule(.square2x2, .corners(allCorners), .fixed, .atLeast(2))
        #expect(!BingoEngine.evaluate(two, marked: marks(topLeft)).isWinner)
        #expect(BingoEngine.evaluate(two, marked: marks(topLeft + bottomRight)).isWinner)

        let all = shapeRule(.square2x2, .corners(allCorners), .fixed, .all)
        #expect(!BingoEngine.evaluate(all, marked: marks(topLeft + bottomRight)).isWinner)

        let onlyBottomRight = shapeRule(.square2x2, .corners([.bottomRight]))
        #expect(!BingoEngine.evaluate(onlyBottomRight, marked: marks(topLeft)).isWinner)
        #expect(BingoEngine.evaluate(onlyBottomRight, marked: marks(bottomRight)).isWinner)
    }

    @Test func exactlyAsDrawnOnlyMatchesThoseCells() {
        let drawn = PatternShape([Cell(4, 0), Cell(4, 1), Cell(3, 0)])
        let rule = shapeRule(drawn, .exactlyAsDrawn)
        #expect(rule.placements == [drawn.cells])
        #expect(BingoEngine.evaluate(rule, marked: marks([Cell(4, 0), Cell(4, 1), Cell(3, 0)])).isWinner)
        #expect(!BingoEngine.evaluate(rule, marked: marks([Cell(0, 0), Cell(0, 1), Cell(1, 0)])).isWinner)
    }

    @Test func blackoutNeedsEverything() {
        var almost = Set(Cell.all); almost.remove(Cell(4, 4))
        #expect(!BingoEngine.evaluate(.blackout, marked: almost).isWinner)
        #expect(BingoEngine.evaluate(.blackout, marked: Set(Cell.all)).isWinner)
    }

    @Test func impossibleCountNeverWins() {
        let rule = shapeRule(.square2x2, .corners([.topLeft]), .fixed, .atLeast(2))
        #expect(!BingoEngine.evaluate(rule, marked: Set(Cell.all)).isWinner)
    }

    @Test func emptyCustomShapeNeverWins() {
        #expect(!BingoEngine.evaluate(shapeRule(PatternShape([]), .anywhere), marked: Set(Cell.all)).isWinner)
        #expect(!BingoEngine.evaluate(shapeRule(PatternShape([]), .anywhere, .fixed, .all), marked: Set(Cell.all)).isWinner)
    }
}

@Suite("Call parsing")
struct CallParserTests {
    @Test(arguments: [("G-54", 54), ("g54", 54), ("G 54", 54), ("54", 54), ("B1", 1), ("o-75", 75), (" N—31 ", 31)])
    func validCalls(text: String, expected: Int) {
        #expect(CallParser.parse(text) == expected)
    }

    @Test(arguments: ["", "B-54", "X12", "0", "76", "123", "G", "G-5a"])
    func invalidCalls(text: String) {
        #expect(CallParser.parse(text) == nil)
    }
}

extension BingoBoard {
    func withID(_ id: UUID) -> BingoBoard { var copy = self; copy.id = id; return copy }
}
