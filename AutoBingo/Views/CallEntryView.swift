import BingoKit
import SwiftUI

/// Photograph the big screen (or type the number), confirm it, and see recent calls.
struct CallEntryView: View {
    @Environment(GameStore.self) private var store
    @State private var text = ""
    @FocusState private var isFocused: Bool
    @State private var photoToConfirm: PendingPhoto?
    @State private var recroppingLast: PendingPhoto?
    @State private var recropResult: CroppedPhoto?

    private var parsed: Int? { CallParser.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PhotoCaptureButtons(cameraTitle: "Photograph the screen", libraryTitle: "Choose a photo of the screen") { photo in
                store.lastCallPhoto = photo
                photoToConfirm = PendingPhoto(photo: photo)
            }
            if let last = store.lastCallPhoto {
                Button {
                    recroppingLast = PendingPhoto(photo: last)
                } label: {
                    HStack(spacing: 8) {
                        Image(uiImage: last.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Label("Re-crop last photo", systemImage: "crop")
                    }
                    .font(.subheadline)
                }
            }
            typedEntry

            if let feedback = store.callFeedback {
                Label(feedback.message, systemImage: feedback.isWarning ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(feedback.isWarning ? .orange : .secondary)
            } else if !text.isEmpty && parsed == nil {
                Text("Enter a number from 1 to 75")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !store.game.calls.isEmpty {
                recentCalls
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Call") { submitTyped() }
                    .disabled(parsed == nil)
                Button("Done") { isFocused = false }
            }
        }
        .sheet(item: $photoToConfirm) { pending in
            CallConfirmationView(photo: pending.photo)
        }
        .background {
            // Kept on its own view so it doesn't clash with the confirmation sheet.
            Color.clear.fullScreenCover(item: $recroppingLast, onDismiss: {
                // Open "Confirm call" only once the crop screen has fully closed.
                if let photo = recropResult {
                    recropResult = nil
                    store.lastCallPhoto = photo
                    photoToConfirm = PendingPhoto(photo: photo)
                }
            }) { pending in
                PhotoCropView(image: pending.photo.original, initialCrop: pending.photo.crop) { result in
                    recropResult = result
                    recroppingLast = nil
                }
            }
        }
        .task {
            if let image = DemoLaunch.callImage {
                let photo = CroppedPhoto(original: image)
                store.lastCallPhoto = photo
                photoToConfirm = PendingPhoto(photo: photo)
            }
        }
    }

    private var typedEntry: some View {
        HStack(spacing: 10) {
            TextField("Or type the number", text: $text)
                .keyboardType(.numberPad)
                .focused($isFocused)
                .font(.title3.monospacedDigit())
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                .onChange(of: text) { store.callFeedback = nil }

            Button(action: submitTyped) {
                Text(parsed.map { "Call \(BingoColumn.label(for: $0))" } ?? "Call")
                    .font(.headline)
                    .frame(minWidth: 80)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(parsed == nil)
        }
    }

    private var recentCalls: some View {
        HStack(spacing: 8) {
            Text("\(store.game.calls.count) called")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.game.calls.reversed(), id: \.self) { number in
                        Text(BingoColumn.label(for: number))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(number == store.game.lastCall ? Color.accentColor : Color(.tertiarySystemFill))
                            )
                            .foregroundStyle(number == store.game.lastCall ? Color.white : Color.primary)
                    }
                }
            }
            Button {
                store.undoLastCall()
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.title3)
            }
            .accessibilityLabel("Undo last call")
        }
    }

    private func submitTyped() {
        guard let number = parsed else { return }
        if store.applyCall(number) != .invalid { text = "" }
    }
}

struct PendingPhoto: Identifiable {
    let id = UUID()
    let photo: CroppedPhoto
}
