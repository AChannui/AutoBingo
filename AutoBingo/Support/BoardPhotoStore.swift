import UIKit

/// A photo as it was taken or picked, plus the part of it the person chose to keep.
/// Keeping the original means the crop can be adjusted later without finding the photo again.
struct CroppedPhoto {
    let original: UIImage
    /// The kept area, as fractions of the upright photo's width and height (0...1).
    let crop: CGRect
    /// What gets read: the original cut down to `crop`.
    let image: UIImage

    static let fullFrame = CGRect(x: 0, y: 0, width: 1, height: 1)

    init(original: UIImage, crop: CGRect = CroppedPhoto.fullFrame) {
        self.original = original
        self.crop = crop
        self.image = crop == Self.fullFrame ? original : original.cropped(toFraction: crop)
    }
}

/// Keeps the last photo scanned into each board on the phone (one per board), so it can be
/// re-cropped and rescanned later — even after leaving the board or restarting the app.
enum BoardPhotoStore {
    private static var folder: URL {
        URL.documentsDirectory.appending(path: "board-photos", directoryHint: .isDirectory)
    }

    private static func imageURL(_ id: UUID) -> URL { folder.appending(path: "\(id.uuidString).jpg") }
    private static func cropURL(_ id: UUID) -> URL { folder.appending(path: "\(id.uuidString).json") }

    /// Saves in the background; the photo is written upright so the crop lines up when reloaded.
    static func save(_ photo: CroppedPhoto, for boardID: UUID) {
        let original = photo.original
        let crop = photo.crop
        Task.detached(priority: .utility) {
            guard let data = original.uprightForSaving().jpegData(compressionQuality: 0.9) else { return }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: imageURL(boardID), options: .atomic)
                try JSONEncoder().encode(crop).write(to: cropURL(boardID), options: .atomic)
            } catch {
                print("Couldn't save board photo: \(error)")
            }
        }
    }

    /// The saved photo for this board, if there is one. Decodes off the main thread.
    static func load(for boardID: UUID) async -> CroppedPhoto? {
        await Task.detached(priority: .userInitiated) { () -> CroppedPhoto? in
            guard let data = try? Data(contentsOf: imageURL(boardID)),
                  let image = UIImage(data: data) else { return nil }
            let crop = (try? Data(contentsOf: cropURL(boardID)))
                .flatMap { try? JSONDecoder().decode(CGRect.self, from: $0) } ?? CroppedPhoto.fullFrame
            return CroppedPhoto(original: image, crop: crop)
        }.value
    }

    /// Deletes photos for boards that no longer exist (e.g. after starting fresh with new boards).
    static func removePhotos(except boardIDs: [UUID]) {
        let keep = Set(boardIDs.map(\.uuidString))
        Task.detached(priority: .utility) {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where !keep.contains(file.deletingPathExtension().lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}

private extension UIImage {
    /// Camera photos are stored sideways with a rotation flag; bake the rotation in.
    func uprightForSaving() -> UIImage {
        guard imageOrientation != .up || cgImage == nil else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
