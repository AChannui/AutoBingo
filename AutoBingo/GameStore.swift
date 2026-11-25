import BingoKit
import Foundation
import Observation

/// Holds the current game for the whole app and saves it to the phone after every change,
/// so nothing is lost if the app is closed mid-game.
@MainActor
@Observable
final class GameStore {
    var game: BingoGame {
        didSet { save() }
    }

    private let fileURL: URL

    init(fileURL: URL = URL.documentsDirectory.appending(path: "current-game.json")) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode(BingoGame.self, from: data) {
            game = saved
        } else {
            game = BingoGame()
        }
    }

    /// The message shown under the call box after a call is applied (not saved to disk).
    var callFeedback: CallFeedback?

    /// The last photo of the bingo screen, so it can be re-cropped without retaking it.
    /// Kept only while the app is open — each call is a new photo, so older ones aren't useful.
    var lastCallPhoto: CroppedPhoto?

    /// Applies a call — typed or read from a photo — and sets a message saying what happened.
    @discardableResult
    func applyCall(_ number: Int) -> BingoGame.CallResult {
        let label = BingoColumn.label(for: number)
        let result = game.call(number)
        switch result {
        case .added:
            let hits = game.boards(containing: number).map(\.name)
            callFeedback = CallFeedback(
                message: hits.isEmpty ? "\(label) — not on your boards" : "\(label) — on \(hits.joined(separator: ", "))",
                isWarning: false
            )
        case .duplicate:
            callFeedback = CallFeedback(message: "\(label) was already called", isWarning: true)
        case .invalid:
            callFeedback = CallFeedback(message: "That isn't a valid bingo number", isWarning: true)
        }
        return result
    }

    func undoLastCall() {
        if let undone = game.undoLastCall() {
            callFeedback = CallFeedback(message: "Removed \(BingoColumn.label(for: undone))", isWarning: false)
        }
    }

    private func save() {
        do {
            try JSONEncoder().encode(game).write(to: fileURL, options: .atomic)
        } catch {
            print("Couldn't save game: \(error)")
        }
    }
}

struct CallFeedback: Equatable {
    let message: String
    let isWarning: Bool
}

extension GameStore {
    /// A store pre-filled with sample boards, for SwiftUI previews.
    static var preview: GameStore {
        let store = GameStore(fileURL: URL.temporaryDirectory.appending(path: "preview-game.json"))
        var boards: [BingoBoard] = []
        for index in 0..<BingoGame.boardCount {
            var board = BingoBoard(name: "Board \(index + 1)")
            for cell in Cell.all where !cell.isCenter {
                board[cell] = cell.column * 15 + ((cell.row * 3 + index * 2) % 15) + 1
            }
            boards.append(board)
        }
        store.game = BingoGame(boards: boards, calls: [1, 16, 47, 61, 9, 22])
        return store
    }
}
