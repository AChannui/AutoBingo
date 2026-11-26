import BingoKit
import BingoRecognition
import Foundation
import Observation
import UIKit

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

    // MARK: Adding boards from photos

    /// Boards whose photo is still being read (shown as "Reading…" in the board list).
    private(set) var scanningBoardIDs: Set<UUID> = []

    /// Squares the scanner wasn't sure about, per board, so the editor can highlight them
    /// even for boards scanned in bulk. Cleared as the person checks each square.
    var uncertainCells: [UUID: Set<Cell>] = [:]

    /// Saves a new board for each photo right away and reads the numbers in the background,
    /// so a whole stack of cards can be added at once. New boards are saved but not in play.
    func addBoards(from photos: [CroppedPhoto]) {
        for photo in photos {
            let board = BingoBoard(name: game.nextBoardName())
            game.addBoard(board)
            BoardPhotoStore.save(photo, for: board.id)
            scanningBoardIDs.insert(board.id)
            // One at a time, in order: reading a card is heavy, and a stack of 20 at once would stall the phone.
            let previous = lastScan
            lastScan = Task {
                await previous?.value
                await read(photo, into: board.id)
            }
        }
    }

    private var lastScan: Task<Void, Never>?

    private func read(_ photo: CroppedPhoto, into boardID: UUID) async {
        defer { scanningBoardIDs.remove(boardID) }
        let image = photo.image
        guard let cgImage = image.cgImageForVision,
              let reading = try? await BoardRecognizer.recognize(cgImage, orientation: image.visionOrientation),
              let index = game.boards.firstIndex(where: { $0.id == boardID })  // may have been deleted meanwhile
        else { return }
        game.boards[index].replaceNumbers(with: reading.numbers)
        uncertainCells[boardID] = reading.uncertainCells
    }

    /// Deletes a saved board and its photo.
    func removeBoard(id: UUID) {
        game.removeBoard(id: id)
        uncertainCells[id] = nil
        BoardPhotoStore.removePhotos(except: game.boards.map(\.id))
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
        for index in 0..<5 {
            var board = BingoBoard(name: "Board \(index + 1)")
            for cell in Cell.all where !cell.isCenter {
                board[cell] = cell.column * 15 + ((cell.row * 3 + index * 2) % 15) + 1
            }
            boards.append(board)
        }
        store.game = BingoGame(boards: boards, activeBoardIDs: boards.prefix(3).map(\.id),
                               calls: [1, 16, 47, 61, 9, 22])
        return store
    }
}
