import UIKit

/// Debug-only launch switches so the photo flows can be checked from the command line
/// (see `./dev.sh demo-call` and `./dev.sh demo-board`). Always nil in release builds.
@MainActor
enum DemoLaunch {
    /// `-demoCallImage /path.png` — open "Confirm call" with this photo.
    static var callImage: UIImage? { image(forKey: "demoCallImage") }

    /// `-demoBoardImage /path.jpg` — open Board 1's editor and scan this photo.
    static var boardImage: UIImage? { image(forKey: "demoBoardImage") }

    /// `-demoCropImage /path.jpg` — open the crop screen with this photo.
    static var cropImage: UIImage? { image(forKey: "demoCropImage") }

    private static var usedBoardImage = false
    private static var openedDemoBoard = false
    private static var usedCropImage = false

    /// Hands out the demo crop photo once.
    static func takeCropImage() -> UIImage? {
        guard !usedCropImage, let image = cropImage else { return nil }
        usedCropImage = true
        return image
    }

    /// True only the first time it's asked during a `-demoBoardImage` launch, so the
    /// Boards sheet jumps into Board 1 once instead of every time it's opened.
    static func shouldOpenDemoBoard() -> Bool {
        guard !openedDemoBoard, boardImage != nil else { return false }
        openedDemoBoard = true
        return true
    }

    /// Hands out the demo board photo once, so it isn't rescanned every time the editor appears.
    static func takeBoardImage() -> UIImage? {
        guard !usedBoardImage, let image = boardImage else { return nil }
        usedBoardImage = true
        return image
    }

    private static func image(forKey key: String) -> UIImage? {
        #if DEBUG
        if let path = UserDefaults.standard.string(forKey: key) {
            return UIImage(contentsOfFile: path)
        }
        #endif
        return nil
    }
}
