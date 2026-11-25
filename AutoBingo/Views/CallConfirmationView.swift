import BingoKit
import BingoRecognition
import SwiftUI

/// Shows what was read from a photo of the bingo screen and lets the player
/// confirm or correct it before it's applied to the boards.
struct CallConfirmationView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var photo: CroppedPhoto
    @State private var recropping = false
    /// Bumped after a re-crop so the photo is read again.
    @State private var readCount = 0
    @State private var phase: Phase = .reading
    @State private var text = ""
    @FocusState private var editing: Bool

    private enum Phase {
        case reading
        case finished([CallCandidate])
        case failed(String)
    }

    init(photo: CroppedPhoto) {
        _photo = State(initialValue: photo)
    }

    private var image: UIImage { photo.image }
    private var parsed: Int? { CallParser.parse(text) }
    private var alreadyCalled: Bool { parsed.map(store.game.calledNumbers.contains) ?? false }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Button("Adjust crop & read again", systemImage: "crop") { recropping = true }
                        .font(.subheadline)
                        .disabled(isReading)

                    switch phase {
                    case .reading:
                        ProgressView("Reading the number…")
                            .padding()
                    case .finished(let candidates):
                        result(candidates)
                    case .failed(let message):
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        manualEntry
                    }
                }
                .padding()
            }
            .navigationTitle("Confirm call")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editing = false }
                }
            }
            .safeAreaInset(edge: .bottom) { applyButton }
            .task(id: readCount) { await recognize() }
            .fullScreenCover(isPresented: $recropping) {
                PhotoCropView(image: photo.original, initialCrop: photo.crop) { result in
                    recropping = false
                    guard let result else { return }
                    photo = result
                    store.lastCallPhoto = result
                    text = ""
                    phase = .reading
                    readCount += 1
                }
            }
        }
    }

    @ViewBuilder
    private func result(_ candidates: [CallCandidate]) -> some View {
        if candidates.isEmpty {
            Label("Couldn't find a bingo number in this photo. Try adjusting the crop, type it below, or cancel and retake.",
                  systemImage: "questionmark.circle")
                .foregroundStyle(.orange)
        }

        VStack(spacing: 4) {
            Text(parsed.map(BingoColumn.label(for:)) ?? "—")
                .font(.system(size: 72, weight: .heavy, design: .rounded))
                .monospacedDigit()
            if let top = candidates.first, parsed == top.number, isUncertain(candidates) {
                Label("Not sure — please check against the screen", systemImage: "eye")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        }

        // Only suggest readings that scored reasonably close to the best one — tiny text elsewhere
        // on the screen (a board of all 75 numbers, prize amounts) shouldn't show up here.
        let topScore = candidates.first?.score ?? 0
        let alternatives = candidates
            .filter { $0.number != parsed && $0.score >= max(0.1, topScore * 0.3) }
            .prefix(4)
        if !alternatives.isEmpty {
            VStack(spacing: 8) {
                Text("Or did it say…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    ForEach(alternatives) { candidate in
                        Button(candidate.label) { text = "\(candidate.number)" }
                            .buttonStyle(.bordered)
                            .monospacedDigit()
                    }
                }
            }
        }

        manualEntry
    }

    private var manualEntry: some View {
        TextField("Correct the number", text: $text)
            .keyboardType(.numberPad)
            .focused($editing)
            .multilineTextAlignment(.center)
            .font(.title3.monospacedDigit())
            .padding(.vertical, 10)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            .frame(maxWidth: 240)
    }

    private var applyButton: some View {
        VStack(spacing: 8) {
            if alreadyCalled, let parsed {
                Label("\(BingoColumn.label(for: parsed)) was already called", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
            Button {
                if let parsed {
                    store.applyCall(parsed)
                    dismiss()
                }
            } label: {
                Text(parsed.map { "Apply \(BingoColumn.label(for: $0))" } ?? "Apply")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(parsed == nil || alreadyCalled)
        }
        .padding()
        .background(.bar)
    }

    private var isReading: Bool {
        if case .reading = phase { return true }
        return false
    }

    /// Low score, or a runner-up that's nearly as likely.
    private func isUncertain(_ candidates: [CallCandidate]) -> Bool {
        guard let top = candidates.first else { return true }
        if top.score < 0.5 { return true }
        if candidates.count > 1, candidates[1].score > top.score * 0.75 { return true }
        return false
    }

    private func recognize() async {
        guard let cgImage = image.cgImageForVision else {
            phase = .failed("Couldn't read this image.")
            return
        }
        do {
            let candidates = try await CallRecognizer.recognize(cgImage, orientation: image.visionOrientation)
            if let top = candidates.first { text = "\(top.number)" }
            phase = .finished(candidates)
        } catch {
            phase = .failed("Text recognition failed: \(error.localizedDescription)")
        }
    }
}
