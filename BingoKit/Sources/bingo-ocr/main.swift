// Shows what the app would read from photos.
//
//   swift run bingo-ocr screen.jpg            what called number is on this bingo screen?
//   swift run bingo-ocr --board card.jpg      what 5×5 numbers are on this card?
//
// (Or use ./dev.sh ocr / ./dev.sh ocr-board from the project folder.)

import BingoKit
import BingoRecognition
import Foundation
import ImageIO

var arguments = Array(CommandLine.arguments.dropFirst())
let boardMode = arguments.contains("--board")
arguments.removeAll { $0 == "--board" }

if arguments.isEmpty {
    print("Usage: bingo-ocr [--board] <image> [image ...]")
    exit(1)
}

func load(_ path: String) -> (CGImage, CGImagePropertyOrientation)? {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    // Camera photos store "which way is up" separately from the pixels.
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let raw = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
    return (image, CGImagePropertyOrientation(rawValue: raw) ?? .up)
}

func padded(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

func readCall(_ image: CGImage, _ orientation: CGImagePropertyOrientation) throws {
    let observations = try TextReader.observations(in: image, orientation: orientation)
    print("   Text found (\(image.width)×\(image.height)):")
    for observation in observations {
        print("     \(padded("\"\(observation.text)\"", 28)) confidence \(String(format: "%.2f", observation.confidence))  height \(String(format: "%.3f", observation.height))")
    }
    let candidates = CallTextInterpreter.candidates(from: observations)
    if candidates.isEmpty {
        print("   No bingo number found.")
    } else {
        print("   Best guesses:")
        for (rank, candidate) in candidates.prefix(5).enumerated() {
            print("     \(rank + 1). \(padded(candidate.label, 5)) score \(String(format: "%.2f", candidate.score))  (from \"\(candidate.source)\")")
        }
    }
}

func readBoard(_ image: CGImage, _ orientation: CGImagePropertyOrientation) throws {
    let reading = try BoardRecognizer.read(image, orientation: orientation)
    print("   Read \(reading.filledCount) numbers (\(reading.quality) in the right column). [brackets] = please check")
    print("      B     I     N     G     O")
    for row in 0..<5 {
        var line = "   "
        for column in 0..<5 {
            let cell = Cell(row, column)
            let value = reading.numbers[cell.index].map(String.init) ?? (cell.isCenter ? "FREE" : "?")
            let shown = reading.uncertainCells.contains(cell) ? "[\(value)]" : " \(value) "
            line += padded(shown, 6)
        }
        print(line)
    }
    var board = BingoBoard(name: "scan")
    board.replaceNumbers(with: reading.numbers)
    for issue in board.issues {
        print("   ! \(issue.message)")
    }
}

var failed = false
for path in arguments {
    print("== \(path)")
    guard let (image, orientation) = load(path) else {
        print("   Couldn't open image")
        failed = true
        continue
    }
    do {
        if boardMode { try readBoard(image, orientation) } else { try readCall(image, orientation) }
    } catch {
        print("   Recognition failed: \(error)")
        failed = true
    }
}
exit(failed ? 1 : 0)
