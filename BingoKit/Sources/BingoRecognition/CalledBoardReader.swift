import BingoKit
import CoreGraphics
import Foundation

/// One bingo number found in a photo of the caller's board, with where it is.
/// Coordinates are fractions of the photo: x from the left edge, y from the TOP edge.
public struct BoxedNumber: Hashable, Sendable {
    public var number: Int
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(number: Int, x: Double, y: Double, width: Double = 0.02, height: Double = 0.02) {
        self.number = number
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Where each of the 75 numbers sits on a caller's board ("flashboard"), the big table of
/// every number that lights up as it's called.
///
/// Boards come laid out either way round — five tall columns (B I N G O across the top, 15 rows),
/// or five long rows (B I N G O down the side, 15 columns). Either way, number n sits at
/// letter = (n − 1) / 15 and step = (n − 1) % 15, so one straight-line model
///   x = a0 + a1·letter + a2·step,   y = b0 + b1·letter + b2·step
/// covers both layouts (and tilted or angled photos) without needing to know which it is.
public struct CalledBoardLayout: Sendable {
    let model: GridModel
    /// The numbers whose text was found where the model expects them.
    public let found: [Int: BoxedNumber]
    /// Typical size of a number's text, used for numbers the text reader missed.
    public let typicalWidth: Double
    public let typicalHeight: Double

    /// Fewer than this many numbers in the right places and it isn't a caller's board
    /// (a single ball on screen, a bingo card, prize amounts…).
    public static let minimumFound = 20
    /// How far (in steps between numbers) text may sit from its expected spot.
    static let tolerance = 0.35

    static func coordinates(of number: Int) -> (letter: Double, step: Double) {
        (Double((number - 1) / 15), Double((number - 1) % 15))
    }

    /// Finds the board among all the numbers in the photo. Numbers elsewhere in the picture —
    /// on the player's own cards, the big called ball, prize amounts — don't fit the board's
    /// pattern and are ignored.
    public static func fit(_ numbers: [BoxedNumber]) -> CalledBoardLayout? {
        let candidates = numbers.filter { BingoColumn.validNumbers.contains($0.number) }
        guard candidates.count >= minimumFound else { return nil }

        // Try models made from three numbers at a time and keep the one most numbers agree with
        // (RANSAC). Seeded, so the same photo always reads the same way.
        var random = SeededRandom(seed: 0x5EED)
        var bestInliers: [BoxedNumber] = []
        for _ in 0..<4000 {
            let sample = (0..<3).map { _ in candidates[random.next(below: candidates.count)] }
            guard Set(sample.map(\.number)).count == 3,
                  let model = GridModel.fit(points: sample),
                  model.isUsable
            else { continue }
            let inliers = self.inliers(candidates, model: model)
            if inliers.count > bestInliers.count { bestInliers = inliers }
        }
        guard bestInliers.count >= minimumFound else { return nil }

        // Refine using every agreeing number, then collect them once more with the better model.
        guard let refined = GridModel.fit(points: bestInliers), refined.isUsable else { return nil }
        let final = inliers(candidates, model: refined)
        guard final.count >= minimumFound,
              Set(final.map { Int(coordinates(of: $0.number).letter) }).count >= 3
        else { return nil }

        let model = GridModel.fit(points: final) ?? refined
        var found: [Int: BoxedNumber] = [:]
        for number in final {
            // If a number was read twice near its spot, keep the one closest to it.
            if let existing = found[number.number],
               model.error(for: existing) <= model.error(for: number) { continue }
            found[number.number] = number
        }
        return CalledBoardLayout(
            model: model,
            found: found,
            typicalWidth: median(found.values.map(\.width)),
            typicalHeight: median(found.values.map(\.height))
        )
    }

    /// Numbers sitting within tolerance of where `model` puts them, at most one per number.
    private static func inliers(_ numbers: [BoxedNumber], model: GridModel) -> [BoxedNumber] {
        var best: [Int: (BoxedNumber, Double)] = [:]
        for number in numbers {
            let error = model.error(for: number)
            guard error <= tolerance else { continue }
            if let existing = best[number.number], existing.1 <= error { continue }
            best[number.number] = (number, error)
        }
        return best.values.map(\.0)
    }

    /// The box to look at for this number: where its text was found, or where it should be.
    public func box(for number: Int) -> (x: Double, y: Double, width: Double, height: Double) {
        if let seen = found[number] {
            return (seen.x, seen.y, seen.width, seen.height)
        }
        let (letter, step) = Self.coordinates(of: number)
        let (x, y) = model.position(column: letter, row: step)
        // The straight-line model drifts across a photo taken at an angle, so nudge the guess by
        // how far off the model was for the nearest numbers that were actually read.
        let (dx, dy) = nearbyCorrection(letter: letter, step: step)
        return (x + dx, y + dy, typicalWidth, typicalHeight)
    }

    /// Average of the model's misses at the closest read numbers, closer ones counting more.
    private func nearbyCorrection(letter: Double, step: Double) -> (Double, Double) {
        let nearest = found.values
            .map { seen -> (BoxedNumber, Double) in
                let (seenLetter, seenStep) = Self.coordinates(of: seen.number)
                // A letter apart is a bigger jump than a step apart on every board we've seen.
                let distance = (pow((seenLetter - letter) * 2, 2) + pow(seenStep - step, 2)).squareRoot()
                return (seen, distance)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(4)
        var totalWeight = 0.0, dx = 0.0, dy = 0.0
        for (seen, distance) in nearest {
            let (seenLetter, seenStep) = Self.coordinates(of: seen.number)
            let expected = model.position(column: seenLetter, row: seenStep)
            let weight = 1 / (distance * distance + 0.25)
            dx += (seen.x - expected.x) * weight
            dy += (seen.y - expected.y) * weight
            totalWeight += weight
        }
        return totalWeight > 0 ? (dx / totalWeight, dy / totalWeight) : (0, 0)
    }

    /// The part of the photo the board covers (fractions, origin top-left), with a margin
    /// of one number's spacing all round.
    public var region: CGRect {
        let corners = [(-1.0, -1.0), (5.0, -1.0), (-1.0, 15.0), (5.0, 15.0)]
            .map { model.position(column: $0.0, row: $0.1) }
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    /// Whether the board runs in five tall columns (true) or five long rows (false).
    public var isVertical: Bool {
        // A step down the list of numbers moves mostly vertically on a tall-column board.
        abs(model.b.2) > abs(model.a.2)
    }
}

/// Splits the 75 numbers into called and not called from how bright each one looks.
///
/// Every caller's board we've seen shows called numbers lit up (bright white or coloured) and
/// the rest dimmed, so there are two clusters of brightness. The split point is the one that
/// separates them best (Otsu's method). Numbers about halfway between the groups are flagged
/// for a person to check.
public enum CalledBoardClassifier {
    public struct Result: Hashable, Sendable {
        public var called: Set<Int>
        /// Numbers whose brightness was close to the split point.
        public var uncertain: Set<Int>
        /// How clearly the numbers fall into two groups: around 1 or less is muddy, 3+ is clear.
        public var separation: Double
    }

    /// How close to halfway between the two groups' averages (as a fraction of the gap between
    /// them) counts as uncertain.
    static let uncertainMargin = 0.15

    public static func classify(_ brightness: [Int: Double]) -> Result {
        let values = brightness.sorted { $0.value < $1.value }
        guard values.count >= 2 else { return Result(called: [], uncertain: Set(brightness.keys), separation: 0) }

        // Otsu: try each split between neighbours in sorted order; keep the one with the most
        // variance between the two groups.
        let total = values.reduce(0) { $0 + $1.value }
        var lowSum = 0.0
        var bestSplit = 1
        var bestScore = -1.0
        for split in 1..<values.count {
            lowSum += values[split - 1].value
            let lowCount = Double(split), highCount = Double(values.count - split)
            let lowMean = lowSum / lowCount, highMean = (total - lowSum) / highCount
            let score = lowCount * highCount * (highMean - lowMean) * (highMean - lowMean)
            if score > bestScore {
                bestScore = score
                bestSplit = split
            }
        }

        let low = values[..<bestSplit].map(\.value)
        let high = values[bestSplit...].map(\.value)
        let lowMean = mean(low), highMean = mean(high)
        let spread = (standardDeviation(low) + standardDeviation(high)) / 2
        let gap = highMean - lowMean
        let middle = (lowMean + highMean) / 2

        let called = Set(values[bestSplit...].map(\.key))
        let margin = gap * uncertainMargin
        let uncertain = Set(values.filter { abs($0.value - middle) < margin }.map(\.key))
        return Result(called: called, uncertain: uncertain, separation: spread > 0 ? gap / spread : .infinity)
    }
}

// MARK: - Helpers

extension GridModel {
    /// Exact or least-squares fit from numbers' board coordinates to their photo positions.
    static func fit(points: [BoxedNumber]) -> GridModel? {
        guard points.count >= 3 else { return nil }
        let features = points.map { point -> (Double, Double, Double) in
            let (letter, step) = CalledBoardLayout.coordinates(of: point.number)
            return (1, letter, step)
        }
        guard let a = leastSquares(features, points.map(\.x)),
              let b = leastSquares(features, points.map(\.y)),
              a.0.isFinite, a.1.isFinite, a.2.isFinite, b.0.isFinite, b.1.isFinite, b.2.isFinite
        else { return nil }
        return GridModel(a: a, b: b)
    }

    func position(column: Double, row: Double) -> (x: Double, y: Double) {
        (a.0 + a.1 * column + a.2 * row, b.0 + b.1 * column + b.2 * row)
    }

    /// Distance, in steps between neighbouring numbers, from where the model expects this number.
    func error(for point: BoxedNumber) -> Double {
        guard let (column, row) = gridPosition(x: point.x, y: point.y) else { return .infinity }
        let (letter, step) = CalledBoardLayout.coordinates(of: point.number)
        return max(abs(column - letter), abs(row - step))
    }

    /// Rules out models that squash the board to almost nothing or make it bigger than the photo.
    var isUsable: Bool {
        let letterSpacing = (a.1 * a.1 + b.1 * b.1).squareRoot()
        let stepSpacing = (a.2 * a.2 + b.2 * b.2).squareRoot()
        return letterSpacing > 0.005 && stepSpacing > 0.002
            && letterSpacing * 4 < 1.5 && stepSpacing * 14 < 1.5
    }
}

/// Small deterministic random generator (SplitMix64).
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(below bound: Int) -> Int { Int(next() % UInt64(bound)) }
}

func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
}

func mean(_ values: [Double]) -> Double {
    values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
}

func standardDeviation(_ values: [Double]) -> Double {
    guard values.count > 1 else { return 0 }
    let m = mean(values)
    return (values.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(values.count)).squareRoot()
}
