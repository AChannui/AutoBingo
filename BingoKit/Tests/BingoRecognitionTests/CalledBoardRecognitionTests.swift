import BingoKit
import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import BingoRecognition

/// Every number on a caller's board at its spot. Tall: five columns of 15 (like the tablets).
/// Wide: five rows of 15 (like the stage screen).
func boardNumbers(tall: Bool, origin: (Double, Double) = (0.2, 0.1), letterSpacing: Double = 0.12,
                  stepSpacing: Double = 0.05, skipping skipped: Set<Int> = []) -> [BoxedNumber] {
    BingoColumn.validNumbers.filter { !skipped.contains($0) }.map { n in
        let letter = Double((n - 1) / 15), step = Double((n - 1) % 15)
        let across = origin.0 + (tall ? letter * letterSpacing : step * stepSpacing)
        let down = origin.1 + (tall ? step * stepSpacing : letter * letterSpacing)
        return BoxedNumber(number: n, x: across, y: down, width: 0.03, height: 0.02)
    }
}

@Suite("Finding the caller's board")
struct CalledBoardLayoutTests {
    @Test(arguments: [true, false])
    func findsBoardEitherWayRound(tall: Bool) throws {
        let layout = try #require(CalledBoardLayout.fit(boardNumbers(tall: tall)))
        #expect(layout.found.count == 75)
        #expect(layout.isVertical == tall)
    }

    @Test func ignoresNumbersOnThePlayersCards() throws {
        // A card beside the board repeats some numbers in the wrong places.
        var numbers = boardNumbers(tall: true, origin: (0.05, 0.1), letterSpacing: 0.06, stepSpacing: 0.055)
        for (index, n) in [53, 63, 57, 71, 47, 64, 60, 72, 49, 67].enumerated() {
            numbers.append(BoxedNumber(number: n, x: 0.5 + Double(index % 2) * 0.1, y: 0.2 + Double(index / 2) * 0.1))
        }
        let layout = try #require(CalledBoardLayout.fit(numbers))
        #expect(layout.found.count == 75)
        let box = layout.box(for: 53)
        #expect(abs(box.x - (0.05 + 3 * 0.06)) < 0.001)
        #expect(abs(box.y - (0.1 + 7 * 0.055)) < 0.001)
    }

    @Test func placesNumbersTheTextReaderMissed() throws {
        // Dim numbers are often not read; their spots still come from the pattern.
        let missed = Set(1...30)
        let layout = try #require(CalledBoardLayout.fit(boardNumbers(tall: true, skipping: missed)))
        #expect(layout.found.count == 45)
        let box = layout.box(for: 4)
        #expect(abs(box.x - 0.2) < 0.001)
        #expect(abs(box.y - (0.1 + 3 * 0.05)) < 0.001)
    }

    @Test func aBingoCardIsNotACallersBoard() {
        let card = sampleCard.enumerated().flatMap { row, numbers in
            numbers.enumerated().compactMap { column, n in
                n.map { BoxedNumber(number: $0, x: 0.2 + Double(column) * 0.12, y: 0.2 + Double(row) * 0.12) }
            }
        }
        #expect(CalledBoardLayout.fit(card) == nil)
    }

    @Test func tooFewNumbersIsNotABoard() {
        #expect(CalledBoardLayout.fit(Array(boardNumbers(tall: true).prefix(10))) == nil)
    }
}

@Suite("Telling lit numbers from dim ones")
struct CalledBoardClassifierTests {
    @Test func splitsBrightFromDim() {
        var brightness: [Int: Double] = [:]
        for n in 1...75 { brightness[n] = 0.3 + Double(n % 7) * 0.02 }   // dim, a little uneven
        for n in [2, 17, 33, 48, 64, 75] { brightness[n] = 0.85 + Double(n % 3) * 0.02 }
        let result = CalledBoardClassifier.classify(brightness)
        #expect(result.called == [2, 17, 33, 48, 64, 75])
        #expect(result.uncertain.isEmpty)
        #expect(result.separation > 3)
    }

    @Test func borderlineNumbersAreFlagged() {
        var brightness: [Int: Double] = [:]
        for n in 1...75 { brightness[n] = 0.3 }
        for n in [5, 6, 7] { brightness[n] = 0.9 }
        brightness[8] = 0.62   // right between the two groups
        let result = CalledBoardClassifier.classify(brightness)
        #expect(result.uncertain.contains(8))
        #expect(result.called.isSuperset(of: [5, 6, 7]))
    }

    @Test func shownCount() {
        #expect(CalledBoardRecognizer.shownCount(in: "BALLS CALLED: 16") == 16)
        #expect(CalledBoardRecognizer.shownCount(in: "Numbers called 7") == 7)
        #expect(CalledBoardRecognizer.shownCount(in: "CARDS IN PLAY: 24") == nil)
        #expect(CalledBoardRecognizer.shownCount(in: "BALLS CALLED:") == nil)
    }
}

/// Uses the async `recognize`, which runs Vision on its own queue: blocking the test runner's
/// shared threads with several Vision reads at once can starve Vision of the threads it needs.
@Suite("Vision recognition of the caller's board")
struct CalledBoardRecognitionTests {
    static let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let grey = CGColor(red: 0.42, green: 0.42, blue: 0.45, alpha: 1)
    static let red = CGColor(red: 0.95, green: 0.25, blue: 0.15, alpha: 1)
    static let green = CGColor(red: 0.35, green: 0.95, blue: 0.2, alpha: 1)

    /// A dark board with every number: `called` in white, `latest` in green, `needed` in red
    /// (the tablets' "1 away" colour — not called), the rest grey.
    static func renderBoard(tall: Bool, called: Set<Int>, latest: Int?, needed: Int?,
                            extraText: [(String, CGFloat, CGFloat)] = []) -> CGImage {
        let width = tall ? 900 : 1600, height = tall ? 1500 : 700
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        func text(_ string: String, size: CGFloat, centerX: CGFloat, centerY: CGFloat, color: CGColor) {
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ]))
            let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
            context.textPosition = CGPoint(x: centerX - lineWidth / 2, y: centerY - size * 0.35)
            CTLineDraw(line, context)
        }

        for n in BingoColumn.validNumbers {
            let letter = CGFloat((n - 1) / 15), step = CGFloat((n - 1) % 15)
            // CoreGraphics y goes up, so count down from the top.
            let x = tall ? 120 + letter * 110 : 160 + step * 95
            let y = tall ? CGFloat(height) - 120 - step * 88 : CGFloat(height) - 150 - letter * 110
            let color = n == latest ? green : n == needed ? red : called.contains(n) ? white : grey
            text("\(n)", size: 46, centerX: x, centerY: y, color: color)
        }
        for (string, x, y) in extraText {
            text(string, size: 40, centerX: x, centerY: y, color: white)
        }
        return context.makeImage()!
    }

    static let called: Set<Int> = [3, 7, 14, 17, 20, 24, 47, 56, 59, 63, 68, 71, 72, 73]

    @Test(arguments: [true, false])
    func readsLitNumbers(tall: Bool) async throws {
        let image = Self.renderBoard(tall: tall, called: Self.called, latest: 49, needed: 54)
        let reading = try #require(try await CalledBoardRecognizer.recognize(image))
        #expect(reading.called == Self.called.union([49]), "Green latest call counts; red '1 away' number doesn't")
        #expect(reading.latest == 49)
        #expect(reading.isVertical == tall)
        #expect(reading.isClear)
    }

    @Test func readsBallsCalledCount() async throws {
        let image = Self.renderBoard(tall: true, called: Self.called, latest: nil, needed: nil,
                                     extraText: [("BALLS CALLED: 14", 700, 300)])
        let reading = try #require(try await CalledBoardRecognizer.recognize(image))
        #expect(reading.shownCount == 14)
        #expect(reading.called == Self.called)
        #expect(reading.latest == nil)
    }

    @Test func aCardPhotoIsNotABoard() async throws {
        #expect(try await CalledBoardRecognizer.recognize(BoardVisionTests.renderCard()) == nil)
    }
}
