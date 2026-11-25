import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Reads text from an image using Apple's on-device Vision text recognition.
public enum TextReader {
    public static func observations(
        in image: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) throws -> [TextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false   // "G54" isn't an English word; don't "fix" it
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
        try handler.perform([request])

        return (request.results ?? []).flatMap { observation in
            // Keep Vision's runner-up readings too; they become "did you mean" suggestions.
            observation.topCandidates(3).map { candidate in
                TextObservation(
                    text: candidate.string,
                    confidence: Double(candidate.confidence),
                    height: Double(observation.boundingBox.height)
                )
            }
        }
    }
}

/// Photo of the bingo screen → ranked guesses for the called number.
public enum CallRecognizer {
    public static func candidates(
        in image: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) throws -> [CallCandidate] {
        CallTextInterpreter.candidates(from: try TextReader.observations(in: image, orientation: orientation))
    }

    /// Same as above, but runs off the main thread so the UI stays responsive.
    public static func recognize(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) async throws -> [CallCandidate] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try candidates(in: image, orientation: orientation) })
            }
        }
    }
}
