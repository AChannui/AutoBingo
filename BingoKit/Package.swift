// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BingoKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BingoKit", targets: ["BingoKit"]),
        .library(name: "BingoRecognition", targets: ["BingoRecognition"]),
        .executable(name: "bingo-ocr", targets: ["bingo-ocr"]),
    ],
    targets: [
        // Pure bingo rules: boards, patterns, calls, win checks. No UI, no camera.
        .target(name: "BingoKit"),
        // Reading bingo numbers out of photos with Apple's Vision framework.
        .target(name: "BingoRecognition", dependencies: ["BingoKit"]),
        // Command-line tool: `swift run bingo-ocr photo.jpg` shows what the app would read.
        .executableTarget(name: "bingo-ocr", dependencies: ["BingoRecognition"]),
        .testTarget(name: "BingoKitTests", dependencies: ["BingoKit"]),
        .testTarget(name: "BingoRecognitionTests", dependencies: ["BingoRecognition"]),
    ]
)
