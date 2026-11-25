import ImageIO
import UIKit

extension UIImage {
    /// The pixels, rendering the image first if it isn't backed by a CGImage.
    var cgImageForVision: CGImage? {
        if let cgImage { return cgImage }
        return UIGraphicsImageRenderer(size: size).image { _ in draw(at: .zero) }.cgImage
    }

    /// Camera photos are stored sideways with a "rotate me" flag; Vision needs that flag too.
    var visionOrientation: CGImagePropertyOrientation {
        guard cgImage != nil else { return .up }   // a re-rendered image is already upright
        switch imageOrientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
