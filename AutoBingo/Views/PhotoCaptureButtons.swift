import PhotosUI
import SwiftUI

/// "Take a photo" + "choose a photo" buttons. After a photo is taken or picked, the person can crop
/// it to just the part that matters (or keep it whole); `onPhoto` then gets the result, along with
/// the original photo and crop so the caller can offer to re-crop it later.
/// On the simulator (no camera) only the photo-library button is shown, full width.
struct PhotoCaptureButtons: View {
    let cameraTitle: String
    let libraryTitle: String
    let onPhoto: (CroppedPhoto) -> Void

    @State private var showingCamera = false
    @State private var capturedImage: UIImage?
    @State private var libraryItem: PhotosPickerItem?
    @State private var photoToCrop: PendingCrop?
    @State private var finishedPhoto: CroppedPhoto?
    private let cameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)

    var body: some View {
        HStack(spacing: 10) {
            if cameraAvailable {
                Button {
                    showingCamera = true
                } label: {
                    Label(cameraTitle, systemImage: "camera.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            PhotosPicker(selection: $libraryItem, matching: .images) {
                if cameraAvailable {
                    Image(systemName: "photo.on.rectangle")
                        .font(.headline)
                        .accessibilityLabel(libraryTitle)
                } else {
                    Label(libraryTitle, systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .fullScreenCover(isPresented: $showingCamera, onDismiss: {
            // Hand the photo over only once the camera has fully closed, so a sheet can open next.
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
                // Hand the photo over only once the crop screen has fully closed, so a sheet can open next.
                if let photo = finishedPhoto {
                    finishedPhoto = nil
                    onPhoto(photo)
                }
            }) { pending in
                PhotoCropView(image: pending.image) { result in
                    finishedPhoto = result
                    photoToCrop = nil
                }
            }
        }
        .onAppear {
            if let demo = DemoLaunch.takeCropImage() { photoToCrop = PendingCrop(image: demo) }
        }
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    photoToCrop = PendingCrop(image: image)
                }
                libraryItem = nil
            }
        }
    }
}

private struct PendingCrop: Identifiable {
    let id = UUID()
    let image: UIImage
}
