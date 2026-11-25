import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import BingoRecognition

@Suite("Interpreting OCR text")
struct InterpreterTests {
    func best(_ observations: [TextObservation]) -> Int? {
        CallTextInterpreter.candidates(from: observations).first?.number
    }

    @Test(arguments: [("G-54", 54), ("G 54", 54), ("g54", 54), ("B 7", 7), ("N—31", 31), ("O 75", 75), ("54", 54)])
    func readsCommonFormats(text: String, expected: Int) {
        #expect(best([TextObservation(text: text, confidence: 1, height: 0.3)]) == expected)
    }

    @Test(arguments: [
        ("0 63", 63),   // O read as zero
        ("6 54", 54),   // G read as six
        ("654", 54),    // G read as six, no space
        ("G 5A", nil),  // not a number
        ("O 6S", 65),   // 5 read as S
        ("BINGO", nil), // the title isn't B-1
    ] as [(String, Int?)])
    func handlesLookalikes(text: String, expected: Int?) {
        #expect(best([TextObservation(text: text, confidence: 1, height: 0.3)]) == expected)
    }

    @Test func biggerTextWins() {
        let observations = [
            TextObservation(text: "Game 3", confidence: 1, height: 0.04),
            TextObservation(text: "12", confidence: 1, height: 0.05),
            TextObservation(text: "G 54", confidence: 0.9, height: 0.35),
        ]
        #expect(best(observations) == 54)
    }

    @Test func contradictoryLetterKeepsNumberAsLowScoringGuess() {
        // 54 is a G number, so "B 54" is a misread somewhere. Offer 54, but with low confidence.
        let candidates = CallTextInterpreter.candidates(from: [TextObservation(text: "B 54", confidence: 1, height: 0.3)])
        #expect(candidates.map(\.number) == [54])
        #expect(candidates[0].score < 0.3)
    }

    @Test func letterAndNumberBeatsBareNumberOfSimilarSize() {
        let observations = [
            TextObservation(text: "18", confidence: 1, height: 0.3),
            TextObservation(text: "N 41", confidence: 1, height: 0.3),
        ]
        #expect(best(observations) == 41)
    }

    @Test func ignoresYearsPricesAndOutOfRange() {
        let observations = [TextObservation(text: "2026 Jackpot $500 99", confidence: 1, height: 0.3)]
        #expect(CallTextInterpreter.candidates(from: observations).isEmpty)
    }

    @Test func runnerUpReadingsBecomeAlternatives() {
        let observations = [
            TextObservation(text: "G 54", confidence: 0.6, height: 0.3),
            TextObservation(text: "G 34", confidence: 0.3, height: 0.3), // 34 isn't a G number — ranked last
            TextObservation(text: "G 59", confidence: 0.3, height: 0.3),
        ]
        #expect(CallTextInterpreter.candidates(from: observations).map(\.number) == [54, 59, 34])
    }
}

/// These run the real Vision text recognizer on images drawn in code.
@Suite("Vision recognition on rendered images")
struct VisionTests {
    struct TextLine {
        let text: String
        let fontSize: CGFloat
        let x: CGFloat
        let y: CGFloat   // from the bottom
    }

    func render(_ lines: [TextLine], width: Int = 1200, height: Int = 900, darkScreen: Bool = false) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(darkScreen ? CGColor(red: 0.05, green: 0.1, blue: 0.3, alpha: 1) : .white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let textColor: CGColor = darkScreen ? .white : .black
        for line in lines {
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, line.fontSize, nil)
            let attributed = NSAttributedString(string: line.text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): textColor,
            ])
            context.textPosition = CGPoint(x: line.x, y: line.y)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        return context.makeImage()!
    }

    @Test func readsBigCallOnDarkScreenWithClutter() throws {
        let image = render([
            TextLine(text: "BINGO", fontSize: 60, x: 480, y: 800),
            TextLine(text: "G 54", fontSize: 300, x: 260, y: 330),
            TextLine(text: "Game 3   Prize $500", fontSize: 40, x: 380, y: 120),
            TextLine(text: "Last: B 12", fontSize: 40, x: 40, y: 40),
        ], darkScreen: true)
        let candidates = try CallRecognizer.candidates(in: image)
        #expect(candidates.first?.number == 54, "Got \(candidates.map(\.label))")
    }

    @Test func readsNumberWithoutLetter() throws {
        let image = render([TextLine(text: "71", fontSize: 360, x: 380, y: 300)])
        #expect(try CallRecognizer.candidates(in: image).first?.number == 71)
    }

    @Test func emptyImageHasNoCandidates() throws {
        #expect(try CallRecognizer.candidates(in: render([])).isEmpty)
    }
}
