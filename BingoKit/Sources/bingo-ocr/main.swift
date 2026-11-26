// Shows what the app would read from photos.
//
//   swift run bingo-ocr screen.jpg            what called number is on this bingo screen?
//   swift run bingo-ocr --board card.jpg      what 5×5 numbers are on this card?
//   swift run bingo-ocr --called screen.jpg   which numbers are lit on the caller's board?
//
// (Or use ./dev.sh ocr / ocr-board / ocr-called from the project folder.)

import BingoKit
import BingoRecognition
import CoreImage
import Foundation
import ImageIO

var arguments = Array(CommandLine.arguments.dropFirst())
let boardMode = arguments.contains("--board")
let calledMode = arguments.contains("--called")
arguments.removeAll { $0 == "--board" || $0 == "--called" }

if arguments.isEmpty {
    print("Usage: bingo-ocr [--board | --called] <image> [image ...]")
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

func readCalledBoard(_ image: CGImage, _ orientation: CGImagePropertyOrientation) throws {
    guard let reading = try CalledBoardRecognizer.read(image, orientation: orientation) else {
        print("   No caller's board found (fewer than \(CalledBoardLayout.minimumFound) numbers in a board pattern).")
        return
    }
    print("   \(reading.isVertical ? "Tall columns" : "Long rows"); text found for \(reading.foundCount) of 75 numbers.")
    print("   \(reading.called.count) lit\(reading.shownCount.map { " (screen says \($0) called)" } ?? "")"
          + "\(reading.isClear ? "" : " — NOT a clear split, treat as a guess")"
          + "\(reading.latest.map { "; latest \(BingoColumn.label(for: $0))" } ?? "")")
    print("   *n* = lit, [n] = please check, value = measured brightness")
    for letter in BingoColumn.allCases {
        var line = "   \(letter.letter) "
        for number in letter.range {
            let lit = reading.called.contains(number)
            let mark = reading.uncertain.contains(number) ? ("[", "]") : lit ? ("*", "*") : (" ", " ")
            line += padded("\(mark.0)\(number)\(mark.1)", 5)
        }
        print(line)
        var values = "     "
        for number in letter.range {
            values += padded(String(format: "%.2f", reading.brightness[number] ?? 0), 5)
        }
        print(values)
    }
    if let overlay = ProcessInfo.processInfo.environment["OVERLAY"] {
        drawOverlay(reading, on: image, orientation, to: overlay)
    }
    print("   Called: \(reading.called.sorted().map(BingoColumn.label(for:)).joined(separator: " "))")
}

/// Debug picture: the photo with a box where each number was measured
/// (green = lit, red = not, solid = text was read, thin = placed from the pattern).
func drawOverlay(_ reading: CalledBoardReading, on image: CGImage, _ orientation: CGImagePropertyOrientation, to path: String) {
    let context = CIContext()
    var upright = CIImage(cgImage: image).oriented(orientation)
    let longSide = max(upright.extent.width, upright.extent.height)
    if longSide > 2400 { upright = upright.transformed(by: CGAffineTransform(scaleX: 2400 / longSide, y: 2400 / longSide)) }
    guard let base = context.createCGImage(upright, from: upright.extent) else { return }
    let width = base.width, height = base.height
    guard let canvas = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return }
    canvas.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
    for (number, box) in reading.boxes {
        let rect = CGRect(x: box.minX * Double(width), y: (1 - box.maxY) * Double(height),
                          width: box.width * Double(width), height: box.height * Double(height))
        canvas.setStrokeColor(reading.called.contains(number) ? CGColor(red: 0, green: 1, blue: 0, alpha: 1)
                                                             : CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        canvas.setLineWidth(reading.found.contains(number) ? 2 : 1)
        canvas.stroke(rect)
    }
    guard let output = canvas.makeImage(),
          let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(destination, output, nil)
    CGImageDestinationFinalize(destination)
    print("   Overlay saved to \(path)")
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
        if boardMode {
            try readBoard(image, orientation)
        } else if calledMode {
            try readCalledBoard(image, orientation)
        } else {
            try readCall(image, orientation)
        }
    } catch {
        print("   Recognition failed: \(error)")
        failed = true
    }
}
exit(failed ? 1 : 0)
