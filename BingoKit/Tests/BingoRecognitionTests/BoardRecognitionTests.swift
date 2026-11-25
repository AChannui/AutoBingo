import BingoKit
import CoreGraphics
import CoreImage
import CoreText
import Foundation
import Testing
@testable import BingoRecognition

/// A valid card used throughout: rows of B, I, N, G, O numbers with a FREE center.
let sampleCard: [[Int?]] = [
    [7, 19, 34, 52, 66],
    [12, 23, 41, 47, 70],
    [3, 28, nil, 59, 61],
    [14, 16, 38, 50, 73],
    [9, 30, 45, 56, 64],
]
let sampleNumbers: [Int?] = sampleCard.flatMap { $0 }

/// Tokens laid out on a perfect grid, optionally rotated by `degrees` around the card center.
func gridTokens(_ card: [[Int?]] = sampleCard, degrees: Double = 0, origin: (Double, Double) = (0.2, 0.25),
                spacing: Double = 0.12, includeFree: Bool = true) -> [NumberToken] {
    let angle = degrees * .pi / 180
    let center = (origin.0 + 2 * spacing, origin.1 + 2 * spacing)
    var tokens: [NumberToken] = []
    for row in 0..<5 {
        for column in 0..<5 {
            let value: TokenValue
            if let n = card[row][column] { value = .number(n) } else if includeFree { value = .free } else { continue }
            let x0 = origin.0 + Double(column) * spacing - center.0
            let y0 = origin.1 + Double(row) * spacing - center.1
            tokens.append(NumberToken(
                value: value,
                x: center.0 + x0 * cos(angle) - y0 * sin(angle),
                y: center.1 + x0 * sin(angle) + y0 * cos(angle)
            ))
        }
    }
    return tokens
}

@Suite("Placing numbers on the grid")
struct GridReaderTests {
    @Test func perfectGrid() {
        let reading = BoardGridReader.read(gridTokens())
        #expect(reading.numbers == sampleNumbers)
        #expect(reading.uncertainCells.isEmpty)
    }

    @Test(arguments: [-25.0, -10.0, 8.0, 20.0])
    func rotatedCard(degrees: Double) {
        #expect(BoardGridReader.read(gridTokens(degrees: degrees)).numbers == sampleNumbers)
    }

    @Test func blankFreeSquareWithoutFreeText() {
        #expect(BoardGridReader.read(gridTokens(includeFree: false)).numbers == sampleNumbers)
    }

    @Test func missingNumbersStillPlacedCorrectly() {
        // Lose three numbers, including two from the same column — the rest still land correctly.
        var tokens = gridTokens()
        tokens.removeAll { [.number(19), .number(23), .number(59)].contains($0.value) }
        var expected = sampleNumbers
        expected[Cell(0, 1).index] = nil
        expected[Cell(1, 1).index] = nil
        expected[Cell(2, 3).index] = nil
        #expect(BoardGridReader.read(tokens).numbers == expected)
    }

    @Test func ignoresTextOffTheGrid() {
        var tokens = gridTokens()
        tokens.append(NumberToken(value: .number(12), x: 0.05, y: 0.05))   // "Card 12" in a corner
        tokens.append(NumberToken(value: .number(3), x: 0.5, y: 0.95))     // "Game 3" below the card
        #expect(BoardGridReader.read(tokens).numbers == sampleNumbers)
    }

    @Test func misreadNumberIsPlacedByPositionAndFlagged() {
        // 47 (G column) misread as 17 (an I number) — it still goes in the G square, flagged.
        let tokens = gridTokens().map { token in
            var copy = token
            if token.value == .number(47) { copy.value = .number(17) }
            return copy
        }
        let reading = BoardGridReader.read(tokens)
        #expect(reading.numbers[Cell(1, 3).index] == 17)
        #expect(reading.uncertainCells == [Cell(1, 3)])
    }

    @Test func lowConfidenceIsFlagged() {
        let tokens = gridTokens().map { token in
            var copy = token
            if token.value == .number(41) { copy.confidence = 0.3 }
            return copy
        }
        #expect(BoardGridReader.read(tokens).uncertainCells == [Cell(1, 2)])
    }

    @Test func tokenValues() {
        #expect(NumberToken.value(from: "54") == .number(54))
        #expect(NumberToken.value(from: "S4") == .number(54))
        #expect(NumberToken.value(from: "FREE") == .free)
        #expect(NumberToken.value(from: "Free!") == .free)
        #expect(NumberToken.value(from: "BINGO") == nil)
        #expect(NumberToken.value(from: "10482") == nil)
        #expect(NumberToken.value(from: "99") == nil)
    }

    @Test func noTokensGivesEmptyReading() {
        #expect(BoardGridReader.read([]) == .empty)
    }
}

/// Renders a realistic-ish card image and runs the full Vision pipeline on it.
@Suite("Vision recognition of card photos")
struct BoardVisionTests {
    static func renderCard(rotation degrees: CGFloat = 0, width: Int = 1100, height: Int = 1300) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.85, green: 0.82, blue: 0.75, alpha: 1))   // table
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.rotate(by: degrees * .pi / 180)
        context.translateBy(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2)

        let cell: CGFloat = 150
        let left = (CGFloat(width) - 5 * cell) / 2
        let top = CGFloat(height) - 300          // CoreGraphics y goes up
        context.setFillColor(.white)
        context.fill(CGRect(x: left - 30, y: top - 5 * cell - 30, width: 5 * cell + 60, height: 5 * cell + 230))

        func text(_ string: String, size: CGFloat, centerX: CGFloat, baseline: CGFloat, color: CGColor = .black) {
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ]))
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            context.textPosition = CGPoint(x: centerX - width / 2, y: baseline)
            CTLineDraw(line, context)
        }

        text("Card 10482", size: 28, centerX: left + 2.5 * cell, baseline: top + 150, color: CGColor(gray: 0.4, alpha: 1))
        for (index, letter) in ["B", "I", "N", "G", "O"].enumerated() {
            text(letter, size: 80, centerX: left + (CGFloat(index) + 0.5) * cell, baseline: top + 30,
                 color: CGColor(red: 0.1, green: 0.2, blue: 0.6, alpha: 1))
        }
        context.setStrokeColor(CGColor(gray: 0.3, alpha: 1))
        context.setLineWidth(3)
        for row in 0..<5 {
            for column in 0..<5 {
                let x = left + CGFloat(column) * cell
                let y = top - CGFloat(row + 1) * cell
                context.stroke(CGRect(x: x, y: y, width: cell, height: cell))
                if let n = sampleCard[row][column] {
                    text("\(n)", size: 72, centerX: x + cell / 2, baseline: y + 48)
                } else {
                    text("FREE", size: 36, centerX: x + cell / 2, baseline: y + 62)
                }
            }
        }
        return context.makeImage()!
    }

    /// Simulates a photo taken at an angle by squeezing the top of the image.
    static func tilted(_ image: CGImage) -> CGImage {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let filter = CIFilter(name: "CIPerspectiveTransform")!
        filter.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: w * 0.18, y: h * 0.92), forKey: "inputTopLeft")
        filter.setValue(CIVector(x: w * 0.85, y: h * 0.95), forKey: "inputTopRight")
        filter.setValue(CIVector(x: 0, y: h * 0.02), forKey: "inputBottomLeft")
        filter.setValue(CIVector(x: w, y: 0), forKey: "inputBottomRight")
        let background = CIImage(color: CIColor(red: 0.35, green: 0.25, blue: 0.2)).cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
        let output = filter.outputImage!.composited(over: background)
        return CIContext().createCGImage(output, from: background.extent)!
    }

    @Test func straightOnCard() throws {
        let reading = try BoardRecognizer.read(Self.renderCard())
        #expect(reading.numbers == sampleNumbers)
    }

    @Test func rotatedCard() throws {
        let reading = try BoardRecognizer.read(Self.renderCard(rotation: 12))
        #expect(reading.numbers == sampleNumbers)
    }

    @Test func cardPhotographedAtAnAngle() throws {
        let reading = try BoardRecognizer.read(Self.tilted(Self.renderCard()))
        #expect(reading.numbers == sampleNumbers)
    }
}
