import PhotosUI
import SwiftUI

/// Adds many boards in one go:
/// - **Scan cards**: the camera reopens after each card is cropped, so a whole stack can be scanned
///   back to back. Cancel the camera (or the crop) to stop.
/// - **Choose photos**: pick any number of card photos at once; each becomes a board (uncropped —
///   it can be re-cropped later from the board's editor).
/// On the simulator (no camera) only the photo-library button is shown.
struct BulkScanButtons: View {
    let onPhotos: ([CroppedPhoto]) -> Void

    @State private var showingCamera = false
    @State private var capturedImage: UIImage?
    @State private var photoToCrop: PendingCrop?
    @State private var finishedPhoto: CroppedPhoto?
    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var isLoadingLibrary = false
    private let cameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if cameraAvailable {
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Scan cards", systemImage: "camera.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                PhotosPicker(selection: $libraryItems, maxSelectionCount: nil,
                             selectionBehavior: .ordered, matching: .images) {
                    Label(cameraAvailable ? "Photos" : "Choose card photos", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: cameraAvailable ? nil : .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isLoadingLibrary)
            }

            if isLoadingLibrary {
                ProgressView("Loading photos…")
            }
        }
        .fullScreenCover(isPresented: $showingCamera, onDismiss: {
            // Hand the photo over only once the camera has fully closed, so the crop screen can open next.
            if let image = capturedImage {
                capturedImage = nil
                photoToCrop = PendingCrop(image: image)
            }
        }) {
            CameraPicker { image in capturedImage = image }
                .ignoresSafeArea()
        }
        .background {
            // Kept on its own view so it doesn't clash with the camera's cover.
            Color.clear.fullScreenCover(item: $photoToCrop, onDismiss: {
                guard let photo = finishedPhoto else { return }   // crop cancelled: stop scanning
                finishedPhoto = nil
                onPhotos([photo])
                showingCamera = true   // straight on to the next card
            }) { pending in
                PhotoCropView(image: pending.image) { result in
                    finishedPhoto = result
                    photoToCrop = nil
                }
            }
        }
        .onChange(of: libraryItems) { _, items in
            guard !items.isEmpty else { return }
            isLoadingLibrary = true
            Task {
                var photos: [CroppedPhoto] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        photos.append(CroppedPhoto(original: image))
                    }
                }
                libraryItems = []
                isLoadingLibrary = false
                onPhotos(photos)
            }
        }
    }
}

private struct PendingCrop: Identifiable {
    let id = UUID()
    let image: UIImage
}
