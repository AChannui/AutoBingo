import BingoKit

/// What a piece of card text says: a number or the FREE square.
public enum TokenValue: Hashable, Sendable {
    case number(Int)
    case free
}

/// One number (or "FREE") found on a card photo, with where it was.
public struct NumberToken: Hashable, Sendable {
    public var value: TokenValue
    /// Center of the text, 0–1 from the left edge of the photo.
    public var x: Double
    /// Center of the text, 0–1 from the TOP edge of the photo.
    public var y: Double
    public var confidence: Double

    public init(value: TokenValue, x: Double, y: Double, confidence: Double = 1) {
        self.value = value
        self.x = x
        self.y = y
        self.confidence = confidence
    }

    /// Interprets one word of OCR text: "54" → 54, "S4" → 54, "FREE" → free, "BINGO" → nil.
    public static func value(from text: String) -> TokenValue? {
        let cleaned = text.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "|" }
        if cleaned.contains("FREE") { return .free }
        guard let number = CallTextInterpreter.digits(Substring(cleaned)),
              BingoColumn.validNumbers.contains(number) else { return nil }
        return .number(number)
    }
}

/// The result of reading a card: 25 numbers (row-major) plus squares worth double-checking.
public struct BoardReading: Hashable, Sendable {
    public var numbers: [Int?]
    /// Squares where the reading is doubtful: low OCR confidence, two readings landed in the
    /// same square, or the number doesn't belong in that column.
    public var uncertainCells: Set<Cell>

    public init(numbers: [Int?], uncertainCells: Set<Cell>) {
        self.numbers = numbers
        self.uncertainCells = uncertainCells
    }

    public static let empty = BoardReading(numbers: Array(repeating: nil, count: 25), uncertainCells: [])

    public var filledCount: Int { numbers.compactMap { $0 }.count }

    /// Numbers that are in a square of the right column — used to pick the better of two readings.
    public var quality: Int {
        Cell.all.filter { cell in
            guard let number = numbers[cell.index] else { return false }
            return BingoColumn(rawValue: cell.column)!.range.contains(number)
        }.count
    }
}

public enum BoardGridReaderSettings {
    /// How far (in squares) a number may sit from a square's center and still count as in it.
    public static let snapTolerance = 0.4
    /// OCR confidence below this marks a square as worth checking.
    public static let lowConfidence = 0.5
}

/// Turns positioned numbers from a card photo into a 5×5 grid.
///
/// How it works:
/// 1. Every bingo number tells us its column (B = 1–15, I = 16–30, …).
/// 2. In columns where we found exactly 5 numbers (or 4 + FREE), sorting top-to-bottom tells us
///    each number's row. Those are "anchors" with a known (column, row).
/// 3. Fit a straight-line model from (column, row) to photo position using the anchors.
///    This handles cards that are shifted, tilted, rotated or slightly angled.
/// 4. Use the model to place EVERY number, including ones in incomplete columns, and drop
///    text that isn't near a grid square (serial numbers, game titles…).
public enum BoardGridReader {
    public static func read(_ tokens: [NumberToken]) -> BoardReading {
        guard !tokens.isEmpty else { return .empty }
        if let model = GridModel.fit(anchors: anchors(in: tokens)) {
            return place(tokens, using: model)
        }
        return fallbackPlacement(tokens)
    }

    // MARK: Step 2 — anchors

    struct Anchor {
        let token: NumberToken
        let column: Int
        let row: Int
    }

    static func anchors(in tokens: [NumberToken]) -> [Anchor] {
        var byColumn: [Int: [NumberToken]] = [:]
        for token in tokens {
            switch token.value {
            case .number(let n): byColumn[BingoColumn(number: n)!.rawValue, default: []].append(token)
            case .free: byColumn[2, default: []].append(token)
            }
        }

        var result: [Anchor] = []
        for (column, columnTokens) in byColumn {
            let sorted = columnTokens.sorted { $0.y < $1.y }
            let rows: [Int]
            if sorted.count == 5 {
                rows = [0, 1, 2, 3, 4]
            } else if column == 2, sorted.count == 4, !sorted.contains(where: { $0.value == .free }) {
                rows = [0, 1, 3, 4]   // N column with a blank FREE square
            } else {
                continue   // too few to know which row is which, or extra stray numbers
            }
            result += zip(sorted, rows).map { Anchor(token: $0, column: column, row: $1) }
        }
        return result
    }

    // MARK: Step 4 — placement

    static func place(_ tokens: [NumberToken], using model: GridModel) -> BoardReading {
        struct Placed {
            let token: NumberToken
            let fitsColumn: Bool
            func isBetter(than other: Placed) -> Bool {
                if fitsColumn != other.fitsColumn { return fitsColumn }
                return token.confidence > other.token.confidence
            }
        }

        var placed: [Cell: Placed] = [:]
        var conflicts = Set<Cell>()
        let tolerance = BoardGridReaderSettings.snapTolerance

        for token in tokens {
            guard let (columnF, rowF) = model.gridPosition(x: token.x, y: token.y) else { continue }
            let column = Int(columnF.rounded()), row = Int(rowF.rounded())
            guard (0..<5).contains(column), (0..<5).contains(row),
                  abs(columnF - Double(column)) <= tolerance,
                  abs(rowF - Double(row)) <= tolerance
            else { continue }   // not on the grid: serial number, title, etc.

            let cell = Cell(row, column)
            let fits: Bool = switch token.value {
            case .number(let n): BingoColumn(rawValue: column)!.range.contains(n)
            case .free: cell.isCenter
            }
            let candidate = Placed(token: token, fitsColumn: fits)
            if let existing = placed[cell] {
                conflicts.insert(cell)
                if candidate.isBetter(than: existing) { placed[cell] = candidate }
            } else {
                placed[cell] = candidate
            }
        }

        var numbers: [Int?] = Array(repeating: nil, count: 25)
        var uncertain = conflicts
        for (cell, entry) in placed {
            guard case .number(let n) = entry.token.value else { continue }
            numbers[cell.index] = n
            if !entry.fitsColumn || entry.token.confidence < BoardGridReaderSettings.lowConfidence {
                uncertain.insert(cell)
            }
        }
        return BoardReading(numbers: numbers, uncertainCells: uncertain.filter { numbers[$0.index] != nil || !$0.isCenter })
    }

    /// Used when no column was complete enough to fit the grid: columns come from the numbers'
    /// values and rows from splitting the card's height into five bands. Everything is marked
    /// for checking, since this guess is rough.
    static func fallbackPlacement(_ tokens: [NumberToken]) -> BoardReading {
        let numberTokens = tokens.filter { if case .number = $0.value { true } else { false } }
        guard let minY = numberTokens.map(\.y).min(), let maxY = numberTokens.map(\.y).max(), maxY > minY else {
            return .empty
        }
        var numbers: [Int?] = Array(repeating: nil, count: 25)
        for token in numberTokens.sorted(by: { $0.confidence > $1.confidence }) {
            guard case .number(let n) = token.value else { continue }
            let column = BingoColumn(number: n)!.rawValue
            let row = min(4, max(0, Int(((token.y - minY) / (maxY - minY) * 4).rounded())))
            let index = Cell(row, column).index
            if numbers[index] == nil { numbers[index] = n }
        }
        let uncertain = Set(Cell.all.filter { numbers[$0.index] != nil })
        return BoardReading(numbers: numbers, uncertainCells: uncertain)
    }
}

/// Straight-line (affine) mapping between grid coordinates and photo coordinates:
///   x = a0 + a1·column + a2·row
///   y = b0 + b1·column + b2·row
struct GridModel {
    let a: (Double, Double, Double)
    let b: (Double, Double, Double)

    static func fit(anchors: [BoardGridReader.Anchor]) -> GridModel? {
        guard anchors.count >= 4,
              Set(anchors.map(\.column)).count >= 2,
              Set(anchors.map(\.row)).count >= 2
        else { return nil }
        let features = anchors.map { (1.0, Double($0.column), Double($0.row)) }
        guard let a = leastSquares(features, anchors.map(\.token.x)),
              let b = leastSquares(features, anchors.map(\.token.y))
        else { return nil }
        return GridModel(a: a, b: b)
    }

    /// Fractional (column, row) for a photo position, or nil if the grid is degenerate.
    func gridPosition(x: Double, y: Double) -> (column: Double, row: Double)? {
        let det = a.1 * b.2 - a.2 * b.1
        guard abs(det) > 1e-9 else { return nil }
        let dx = x - a.0, dy = y - b.0
        return ((dx * b.2 - a.2 * dy) / det, (a.1 * dy - b.1 * dx) / det)
    }

    /// Solves the 3-variable least-squares problem with the normal equations.
    static func leastSquares(_ features: [(Double, Double, Double)], _ targets: [Double]) -> (Double, Double, Double)? {
        var m = [[Double]](repeating: [0, 0, 0, 0], count: 3)
        for (f, t) in zip(features, targets) {
            let v = [f.0, f.1, f.2]
            for i in 0..<3 {
                for j in 0..<3 { m[i][j] += v[i] * v[j] }
                m[i][3] += v[i] * t
            }
        }
        // Gaussian elimination with partial pivoting.
        for col in 0..<3 {
            guard let pivot = (col..<3).max(by: { abs(m[$0][col]) < abs(m[$1][col]) }),
                  abs(m[pivot][col]) > 1e-12 else { return nil }
            m.swapAt(col, pivot)
            for row in 0..<3 where row != col {
                let factor = m[row][col] / m[col][col]
                for k in col..<4 { m[row][k] -= factor * m[col][k] }
            }
        }
        return (m[0][3] / m[0][0], m[1][3] / m[1][1], m[2][3] / m[2][2])
    }
}
