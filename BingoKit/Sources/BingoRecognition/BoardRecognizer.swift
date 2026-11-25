import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Vision

/// Photo of a bingo card → 25 numbers, using Vision text recognition plus `BoardGridReader`.
public enum BoardRecognizer {
    /// Photos are shrunk to at most this many pixels on the long side — plenty for card text,
    /// and much faster than a full 12-megapixel photo.
    static let maxDimension: CGFloat = 2400

    public static func read(_ image: CGImage, orientation: CGImagePropertyOrientation = .up) throws -> BoardReading {
        let context = CIContext()
        guard let upright = uprightImage(image, orientation: orientation, context: context) else {
            return .empty
        }

        var best = BoardGridReader.read(try tokens(in: upright))

        // Taken at an angle? Try again after straightening the card, and keep the better result.
        if best.quality < 24, let corrected = try perspectiveCorrected(upright, context: context) {
            let second = BoardGridReader.read(try tokens(in: corrected))
            if second.quality > best.quality { best = second }
        }
        return best
    }

    /// Same as `read`, but off the main thread so the UI stays responsive.
    public static func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation = .up) async throws -> BoardReading {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try read(image, orientation: orientation) })
            }
        }
    }

    /// Every number / FREE word in the image, with its center position (y measured from the top).
    public static func tokens(in image: CGImage) throws -> [NumberToken] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])

        var result: [NumberToken] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let string = candidate.string
            // Vision often returns a whole row ("1 16 31 46 61") as one piece of text;
            // ask for the box of each word separately.
            for word in string.split(whereSeparator: \.isWhitespace) {
                guard let value = NumberToken.value(from: String(word)) else { continue }
                let box = (try? candidate.boundingBox(for: word.startIndex..<word.endIndex))?.boundingBox
                    ?? observation.boundingBox
                result.append(NumberToken(
                    value: value,
                    x: Double(box.midX),
                    y: 1 - Double(box.midY),   // Vision measures from the bottom
                    confidence: Double(candidate.confidence)
                ))
            }
        }
        return result
    }

    /// Applies the photo's orientation flag and shrinks large photos.
    static func uprightImage(_ image: CGImage, orientation: CGImagePropertyOrientation, context: CIContext) -> CGImage? {
        var ciImage = CIImage(cgImage: image).oriented(orientation)
        let longSide = max(ciImage.extent.width, ciImage.extent.height)
        if longSide > maxDimension {
            let scale = maxDimension / longSide
            ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        if orientation == .up && longSide <= maxDimension { return image }
        return context.createCGImage(ciImage, from: ciImage.extent)
    }

    /// Finds the largest rectangle (hopefully the card) and warps it to a flat, straight-on view.
    static func perspectiveCorrected(_ image: CGImage, context: CIContext) throws -> CGImage? {
        let request = VNDetectRectanglesRequest()
        request.minimumSize = 0.3
        request.maximumObservations = 8
        request.minimumAspectRatio = 0.5
        request.maximumAspectRatio = 1.0
        request.quadratureTolerance = 30
        request.minimumConfidence = 0.5
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])

        guard let card = (request.results ?? []).max(by: {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        }) else { return nil }

        let width = CGFloat(image.width), height = CGFloat(image.height)
        func point(_ p: CGPoint) -> CIVector { CIVector(x: p.x * width, y: p.y * height) }

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        filter.setValue(point(card.topLeft), forKey: "inputTopLeft")
        filter.setValue(point(card.topRight), forKey: "inputTopRight")
        filter.setValue(point(card.bottomLeft), forKey: "inputBottomLeft")
        filter.setValue(point(card.bottomRight), forKey: "inputBottomRight")
        guard let output = filter.outputImage else { return nil }
        return context.createCGImage(output, from: output.extent)
    }
}
