import BingoKit
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Vision

/// What was read from a photo of the caller's board.
public struct CalledBoardReading: Hashable, Sendable {
    /// Numbers that look lit up.
    public var called: Set<Int>
    /// Numbers worth a second look: brightness close to the split, or text that couldn't be found.
    public var uncertain: Set<Int>
    /// How many numbers the text reader actually found on the board (the rest were located by position).
    public var foundCount: Int
    /// "Balls called: 16", if the screen shows a count.
    public var shownCount: Int?
    /// The latest call, if the board shows it in its own colour (green on the ship's tablets).
    public var latest: Int?
    /// Whether called and uncalled numbers looked clearly different. When false, the split is a guess.
    public var isClear: Bool
    /// Brightness measured for each number, for debugging.
    public var brightness: [Int: Double]
    /// Whether the board was laid out in five tall columns.
    public var isVertical: Bool
    /// Where each number was measured, as fractions of the upright photo (origin top-left).
    public var boxes: [Int: CGRect]
    /// Numbers whose text was actually read (the others were placed from the board's pattern).
    public var found: Set<Int>
}

/// Photo of the bingo screen → every number on the caller's board, and which are lit.
public enum CalledBoardRecognizer {
    /// Separation (see `CalledBoardClassifier.Result.separation`) needed to trust the split.
    static let clearSeparation = 2.5

    /// Returns nil when the photo doesn't show a caller's board — e.g. just the big called ball.
    public static func read(_ image: CGImage, orientation: CGImagePropertyOrientation = .up) throws -> CalledBoardReading? {
        let context = CIContext()
        guard let upright = BoardRecognizer.uprightImage(image, orientation: orientation, context: context) else {
            return nil
        }
        var text = try recognizedText(in: upright)
        var layout = CalledBoardLayout.fit(text.numbers)
        if layout == nil {
            // In a photo of a whole stage screen the board's numbers can be too small to read.
            // Look again, a piece at a time, so each piece's text is bigger.
            let tiles = try tiledText(in: upright)
            text.numbers += tiles.numbers
            if text.shownCount == nil { text.shownCount = tiles.shownCount }
            layout = CalledBoardLayout.fit(text.numbers)
        }
        guard var layout else { return nil }

        // Dim numbers are often missed the first time. Read again zoomed in on just the board:
        // more numbers read means better positions for measuring every number's brightness.
        if layout.found.count < 75 {
            let zoomed = try recognizedText(in: upright, region: layout.region)
            if let better = CalledBoardLayout.fit(layout.found.values + zoomed.numbers),
               better.found.count > layout.found.count {
                layout = better
            }
            if text.shownCount == nil { text.shownCount = zoomed.shownCount }
        }

        guard let pixels = PixelBuffer(upright) else { return nil }

        var brightness: [Int: Double] = [:]
        var boxes: [Int: CGRect] = [:]
        for number in BingoColumn.validNumbers {
            let box = layout.box(for: number)
            brightness[number] = pixels.textBrightness(in: box)
            boxes[number] = CGRect(x: box.x - box.width / 2, y: box.y - box.height / 2, width: box.width, height: box.height)
        }
        let result = CalledBoardClassifier.classify(brightness)
        // Only trust the colour if exactly one lit number has it.
        let green = result.called.filter { pixels.isGreen(in: layout.box(for: $0)) }

        return CalledBoardReading(
            called: result.called,
            uncertain: result.uncertain,
            foundCount: layout.found.count,
            shownCount: text.shownCount,
            latest: green.count == 1 ? green.first : nil,
            isClear: result.separation >= clearSeparation,
            brightness: brightness,
            isVertical: layout.isVertical,
            boxes: boxes,
            found: Set(layout.found.keys)
        )
    }

    /// Same as `read`, but off the main thread so the UI stays responsive.
    public static func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation = .up) async throws -> CalledBoardReading? {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try read(image, orientation: orientation) })
            }
        }
    }

    struct RecognizedText {
        var numbers: [BoxedNumber] = []
        var shownCount: Int?
    }

    static func recognizedText(in image: CGImage) throws -> RecognizedText {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        // Board numbers can be small in a photo of a whole stage screen.
        request.minimumTextHeight = 0.005
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])

        var result = RecognizedText()
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let string = candidate.string
            if result.shownCount == nil { result.shownCount = shownCount(in: string) }

            // A whole row ("1 16 31 46 61") often comes back as one piece of text;
            // ask for the box of each word separately.
            for word in string.split(whereSeparator: \.isWhitespace) {
                guard case .number(let number)? = NumberToken.value(from: String(word)) else { continue }
                let box = (try? candidate.boundingBox(for: word.startIndex..<word.endIndex))?.boundingBox
                    ?? observation.boundingBox
                result.numbers.append(BoxedNumber(
                    number: number,
                    x: Double(box.midX),
                    y: 1 - Double(box.midY),   // Vision measures from the bottom
                    width: Double(box.width),
                    height: Double(box.height)
                ))
            }
        }
        return result
    }

    /// Pieces of the photo read separately: a 3×3 grid of overlapping tiles, each 40% of the
    /// photo's width and height.
    static let tileSize = 0.4
    static let tileStride = 0.3

    static func tiledText(in image: CGImage) throws -> RecognizedText {
        var result = RecognizedText()
        for row in 0..<3 {
            for column in 0..<3 {
                let region = CGRect(x: Double(column) * tileStride, y: Double(row) * tileStride,
                                    width: tileSize, height: tileSize)
                let text = try recognizedText(in: image, region: region)
                result.numbers += text.numbers
                if result.shownCount == nil { result.shownCount = text.shownCount }
            }
        }
        return result
    }

    /// Reads just one part of the photo (fractions of its size, origin top-left), reporting
    /// positions in whole-photo fractions.
    static func recognizedText(in image: CGImage, region: CGRect) throws -> RecognizedText {
        let region = region.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let width = Double(image.width), height = Double(image.height)
        let pixels = CGRect(x: region.minX * width, y: region.minY * height,
                            width: region.width * width, height: region.height * height).integral
        guard !region.isEmpty, let piece = image.cropping(to: pixels) else { return RecognizedText() }
        // Where the cropped piece actually starts and how big it is, after rounding to whole pixels.
        let x0 = pixels.minX / width, y0 = pixels.minY / height
        let scaleX = Double(piece.width) / width, scaleY = Double(piece.height) / height

        var text = try recognizedText(in: piece)
        text.numbers = text.numbers.map { number in
            var moved = number
            moved.x = x0 + number.x * scaleX
            moved.y = y0 + number.y * scaleY
            moved.width *= scaleX
            moved.height *= scaleY
            return moved
        }
        return text
    }

    /// "BALLS CALLED: 16" / "Numbers called 16" / "Calls: 16" → 16.
    static func shownCount(in text: String) -> Int? {
        let upper = text.uppercased()
        guard let range = upper.range(of: "CALLED") ?? upper.range(of: "CALLS") else { return nil }
        let after = upper[range.upperBound...].drop { !$0.isNumber }
        let digits = after.prefix { $0.isNumber }
        guard let count = Int(digits), (0...75).contains(count) else { return nil }
        return count
    }
}

/// The photo's pixels, for measuring how bright each number's text is.
struct PixelBuffer {
    let width: Int
    let height: Int
    private let data: [UInt8]

    init?(_ image: CGImage) {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        self.data = data
    }

    /// Whether the text in this box is green (the tablets' colour for the latest call):
    /// its brightest pixels have much more green than red or blue.
    func isGreen(in box: (x: Double, y: Double, width: Double, height: Double)) -> Bool {
        var pixels: [(red: Double, green: Double, blue: Double)] = []
        forEachPixel(in: box) { pixels.append(($0, $1, $2)) }
        guard !pixels.isEmpty else { return false }
        // The text strokes: the brightest tenth of the box.
        let strokes = pixels.sorted { $0.green < $1.green }.suffix(max(1, pixels.count / 10))
        let red = strokes.map(\.red).reduce(0, +), green = strokes.map(\.green).reduce(0, +)
        let blue = strokes.map(\.blue).reduce(0, +)
        return green > red * 1.4 && green > blue * 1.4
    }

    /// Calls `body` with each pixel's red, green and blue (0–255) in the middle of the box —
    /// only the middle, so a bright border or neighbouring number just outside doesn't count.
    private func forEachPixel(in box: (x: Double, y: Double, width: Double, height: Double),
                              _ body: (Double, Double, Double) -> Void) {
        let halfWidth = box.width * 0.4 * Double(width)
        let halfHeight = box.height * 0.4 * Double(height)
        let centerX = box.x * Double(width), centerY = box.y * Double(height)
        let x0 = max(0, Int(centerX - halfWidth)), x1 = min(width - 1, Int(centerX + halfWidth))
        let y0 = max(0, Int(centerY - halfHeight)), y1 = min(height - 1, Int(centerY + halfHeight))
        guard x1 > x0, y1 > y0 else { return }
        for y in y0...y1 {
            for x in x0...x1 {
                let offset = (y * width + x) * 4
                body(Double(data[offset]), Double(data[offset + 1]), Double(data[offset + 2]))
            }
        }
    }

    /// How strongly the text in this box stands out from what's around it, 0–1.
    ///
    /// Measures the green channel (or perceived brightness, if higher). The ship's tablets show
    /// called numbers in white and the latest call in green — both count as lit — but show in
    /// red the number a "1 away" card still needs, which hasn't been called, so red must count
    /// as dim. Compares the brightest pixels (the text strokes) with the dimmer ones (the
    /// background), so glare or a darker corner of the photo shifts both and cancels out.
    /// Bigger, bolder text (how the stage screen shows called numbers) also scores higher, as
    /// more of the box is bright.
    func textBrightness(in box: (x: Double, y: Double, width: Double, height: Double)) -> Double {
        var values: [Double] = []
        forEachPixel(in: box) { red, green, blue in
            values.append(max(green, 0.299 * red + 0.587 * green + 0.114 * blue) / 255)
        }
        guard !values.isEmpty else { return 0 }
        values.sort()
        let text = values[Int(Double(values.count - 1) * 0.95)]
        let background = values[Int(Double(values.count - 1) * 0.2)]
        return text - background
    }
}
