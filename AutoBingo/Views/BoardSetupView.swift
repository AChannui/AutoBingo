import BingoKit
import BingoRecognition
import SwiftUI

/// Every saved board, split into the ones in play and the ones put aside.
/// Scan a whole stack of cards at once, then switch boards in and out of play whenever you like.
struct BoardSetupView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var path: [UUID] = []
    @State private var boardToDelete: BingoBoard?

    private var game: BingoGame { store.game }

    var body: some View {
        @Bindable var store = store

        NavigationStack(path: $path) {
            List {
                Section {
                    BulkScanButtons { photos in store.addBoards(from: photos) }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } footer: {
                    Text("Scan cards one after another, or pick several photos at once. New boards are saved here — tap the circle to play one.")
                }

                Section {
                    if game.activeBoards.isEmpty {
                        Text("No boards in play. Tap the circle next to a saved board to play it.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(game.activeBoards) { row(for: $0) }
                } header: {
                    HStack {
                        Text("Playing (\(game.activeBoards.count))")
                        Spacer()
                        if !game.activeBoards.isEmpty {
                            Button("Put all aside") { store.game.setActiveBoards([]) }
                                .font(.footnote)
                                .textCase(nil)
                        }
                    }
                }

                if !game.inactiveBoards.isEmpty {
                    Section {
                        ForEach(game.inactiveBoards) { row(for: $0) }
                    } header: {
                        HStack {
                            Text("Saved (\(game.inactiveBoards.count))")
                            Spacer()
                            Button("Play all") {
                                store.game.setActiveBoards(game.activeBoardIDs + game.inactiveBoards.map(\.id))
                            }
                            .font(.footnote)
                            .textCase(nil)
                        }
                    }
                }
            }
            .navigationTitle("Boards")
            .navigationDestination(for: UUID.self) { id in
                if let index = store.game.boards.firstIndex(where: { $0.id == id }) {
                    BoardEditorView(board: $store.game.boards[index])
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Type in a board", systemImage: "plus") {
                        let board = BingoBoard(name: store.game.nextBoardName())
                        store.game.addBoard(board)
                        path = [board.id]
                    }
                }
            }
            .confirmationDialog(
                "Delete \(boardToDelete?.name ?? "board")?",
                isPresented: Binding(get: { boardToDelete != nil }, set: { if !$0 { boardToDelete = nil } }),
                titleVisibility: .visible,
                presenting: boardToDelete
            ) { board in
                Button("Delete board", role: .destructive) { store.removeBoard(id: board.id) }
            } message: { _ in
                Text("Its numbers and photo will be removed from the phone.")
            }
            .task {
                BoardPhotoStore.removePhotos(except: store.game.boards.map(\.id))
                let demoPhotos = DemoLaunch.takeBulkBoardImages()
                if !demoPhotos.isEmpty { store.addBoards(from: demoPhotos.map { CroppedPhoto(original: $0) }) }
                if DemoLaunch.shouldOpenDemoBoard() {
                    if store.game.boards.isEmpty { store.game.addBoard(BingoBoard(name: "Board 1"), active: true) }
                    if let first = store.game.boards.first { path = [first.id] }
                }
            }
        }
    }

    private func row(for board: BingoBoard) -> some View {
        let isActive = game.isActive(board.id)
        return HStack(spacing: 12) {
            Button {
                withAnimation { store.game.setActive(!isActive, boardID: board.id) }
            } label: {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isActive ? "Stop playing \(board.name)" : "Play \(board.name)")

            NavigationLink(value: board.id) {
                HStack {
                    Text(board.name)
                    Spacer()
                    status(for: board)
                }
            }
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) { boardToDelete = board }
        }
    }

    @ViewBuilder
    private func status(for board: BingoBoard) -> some View {
        if store.scanningBoardIDs.contains(board.id) {
            HStack(spacing: 6) {
                ProgressView()
                Text("Reading…")
            }
            .foregroundStyle(.secondary)
        } else if board.isEmpty {
            Text("Empty").foregroundStyle(.secondary)
        } else if board.isReadyToPlay {
            Label("Ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            let count = board.issues.count
            Label("\(count) issue\(count == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

/// Scan or type one card's 25 numbers, with problems and doubtful scans highlighted.
struct BoardEditorView: View {
    @Binding var board: BingoBoard
    @Environment(GameStore.self) private var store
    @FocusState private var focusedCell: Cell?
    @State private var confirmingClear = false

    // Scanning
    @State private var isScanning = false
    /// The last photo scanned into this board (saved, so it comes back when the board is reopened).
    @State private var scannedPhoto: CroppedPhoto?
    @State private var showingFullPhoto = false
    @State private var recropping: CroppedPhoto?
    @State private var scanMessage: String?
    /// Kept in the store so squares flagged by a bulk scan are still highlighted here.
    private var uncertainCells: Set<Cell> {
        get { store.uncertainCells[board.id] ?? [] }
        nonmutating set { store.uncertainCells[board.id] = newValue.isEmpty ? nil : newValue }
    }
    @State private var numbersBeforeScan: [Int?]?

    /// Bingo cards are easiest to type column by column (B 1–15, then I 16–30, …).
    private let entryOrder: [Cell] = (0..<Cell.gridSize).flatMap { column in
        (0..<Cell.gridSize).map { row in Cell(row, column) }
    }

    var body: some View {
        let issues = board.issues
        let problemCells = Set(issues.flatMap(\.cells))

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TextField("Board name", text: $board.name)
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.roundedBorder)

                Toggle("Playing this board", isOn: Binding(
                    get: { store.game.isActive(board.id) },
                    set: { store.game.setActive($0, boardID: board.id) }
                ))

                scanSection

                FiveByFiveGrid(spacing: 6) { cell in
                    numberField(for: cell,
                                hasProblem: problemCells.contains(cell),
                                isUncertain: uncertainCells.contains(cell))
                }
                .disabled(isScanning)
                .opacity(isScanning ? 0.4 : 1)

                if board.isEmpty {
                    Text("Scan the card above, or tap a square to type. Leave the center blank if it's a FREE space.")
                        .foregroundStyle(.secondary)
                } else if issues.isEmpty {
                    Label("Looks good", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(issues, id: \.self) { issue in
                            Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.subheadline)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(board.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear", role: .destructive) { confirmingClear = true }
                    .disabled(board.isEmpty)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Next") { moveFocus() }
                Button("Done") { focusedCell = nil }
            }
        }
        .confirmationDialog("Clear all numbers on \(board.name)?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear board", role: .destructive) {
                board.clear()
                uncertainCells = []
            }
        }
        .fullScreenCover(isPresented: $showingFullPhoto) {
            if let scannedPhoto { FullPhotoView(image: scannedPhoto.image) }
        }
        .fullScreenCover(item: $recropping) { photo in
            PhotoCropView(image: photo.original, initialCrop: photo.crop) { result in
                recropping = nil
                if let result { scan(result) }
            }
        }
        .task {
            if let image = DemoLaunch.takeBoardImage() {
                scan(CroppedPhoto(original: image))
            } else if scannedPhoto == nil {
                scannedPhoto = await BoardPhotoStore.load(for: board.id)
            }
        }
    }

    // MARK: Scanning

    @ViewBuilder
    private var scanSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isScanning {
                ProgressView("Reading the card…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                PhotoCaptureButtons(
                    cameraTitle: board.isEmpty ? "Scan card" : "Rescan card",
                    libraryTitle: "Choose a photo of the card",
                    onPhoto: scan
                )
            }

            if let scannedPhoto, !isScanning {
                HStack(alignment: .top, spacing: 12) {
                    Button { showingFullPhoto = true } label: {
                        Image(uiImage: scannedPhoto.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 84, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .accessibilityLabel("View scanned photo")

                    VStack(alignment: .leading, spacing: 6) {
                        if let scanMessage {
                            Text(scanMessage)
                                .font(.subheadline)
                        } else {
                            Text("Last scanned photo")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if !uncertainCells.isEmpty {
                            Label("Check the yellow squares", systemImage: "eye")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        }
                        Button("Adjust crop & rescan", systemImage: "crop") {
                            recropping = scannedPhoto
                        }
                        .font(.subheadline)
                        if numbersBeforeScan != nil {
                            Button("Undo scan", systemImage: "arrow.uturn.backward") {
                                if let previous = numbersBeforeScan { board.replaceNumbers(with: previous) }
                                numbersBeforeScan = nil
                                uncertainCells = []
                                scanMessage = nil
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
        }
    }

    private func scan(_ photo: CroppedPhoto) {
        let image = photo.image
        // Keep the photo even if reading fails — that's exactly when a re-crop helps.
        scannedPhoto = photo
        BoardPhotoStore.save(photo, for: board.id)
        guard let cgImage = image.cgImageForVision else {
            scanMessage = "Couldn't read this image."
            return
        }
        focusedCell = nil
        isScanning = true
        scanMessage = nil

        Task {
            defer { isScanning = false }
            do {
                let reading = try await BoardRecognizer.recognize(cgImage, orientation: image.visionOrientation)
                guard reading.filledCount > 0 else {
                    scanMessage = "Couldn't find the card's numbers. Try adjusting the crop, or a closer, straight-on photo in good light."
                    return
                }
                numbersBeforeScan = board.numbers
                board.replaceNumbers(with: reading.numbers)
                uncertainCells = reading.uncertainCells
                let expected = reading.numbers[Cell.center.index] == nil ? 24 : 25
                scanMessage = reading.filledCount >= expected
                    ? "Read all \(reading.filledCount) numbers. Compare them with your card (tap the photo to zoom)."
                    : "Read \(reading.filledCount) of \(expected) numbers — fill in the empty squares."
            } catch {
                scanMessage = "Scanning failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Typing

    private func numberField(for cell: Cell, hasProblem: Bool, isUncertain: Bool) -> some View {
        ZStack {
            // The text field only responds to taps on its line of text, so the square
            // behind it focuses the field when tapped anywhere else.
            RoundedRectangle(cornerRadius: 8)
                .fill(background(for: cell, isUncertain: isUncertain))
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture { focusedCell = cell }
            DigitsField(
                placeholder: cell.isCenter ? "FREE" : "",
                number: $board[cell],
                focus: $focusedCell,
                cell: cell,
                onEdit: { digitCount in
                    uncertainCells.remove(cell)   // the person has looked at this square now
                    // Jump to the next square once two digits are typed (use "Next" after 1–9).
                    if digitCount == 2 { moveFocus() }
                }
            )
            .padding(.horizontal, 4)
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(hasProblem ? Color.orange : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func background(for cell: Cell, isUncertain: Bool) -> Color {
        if focusedCell == cell { return Color.accentColor.opacity(0.15) }
        if isUncertain { return Color.yellow.opacity(0.45) }
        return Color(.secondarySystemFill)
    }

    private func moveFocus() {
        guard let current = focusedCell, let index = entryOrder.firstIndex(of: current) else {
            focusedCell = entryOrder.first
            return
        }
        let nextIndex = entryOrder.index(after: index)
        focusedCell = nextIndex < entryOrder.endIndex ? entryOrder[nextIndex] : nil
    }
}

/// One square's text field. Accepts at most two digits: anything else (letters from a
/// hardware keyboard, pasted text) is stripped out of the field as soon as it appears.
private struct DigitsField: View {
    let placeholder: String
    @Binding var number: Int?
    var focus: FocusState<Cell?>.Binding
    let cell: Cell
    /// Called after the person changes the number, with how many digits are now in the square.
    let onEdit: (Int) -> Void

    @State private var text = ""

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.numberPad)
            .autocorrectionDisabled()
            .multilineTextAlignment(.center)
            .font(.title3.monospacedDigit().weight(.semibold))
            .focused(focus, equals: cell)
            .onAppear { text = Self.display(number) }
            // The board changed from outside (scan, undo, clear): show the new number.
            .onChange(of: number) { _, newNumber in
                if Int(text) != newNumber { text = Self.display(newNumber) }
            }
            .onChange(of: text) { _, newText in
                let digits = String(newText.filter(\.isASCII).filter(\.isNumber).prefix(2))
                if digits != newText {
                    text = digits   // runs this handler again with the cleaned text
                    return
                }
                let value = Int(digits)
                guard value != number else { return }
                number = value
                if focus.wrappedValue == cell { onEdit(digits.count) }
            }
    }

    private static func display(_ number: Int?) -> String {
        number.map(String.init) ?? ""
    }
}

extension CroppedPhoto: Identifiable {
    var id: ObjectIdentifier { ObjectIdentifier(original) }
}

/// The scanned photo, full screen, pinch to zoom — for comparing against the typed grid.
struct FullPhotoView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        NavigationStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale * pinch)
                .gesture(
                    MagnifyGesture()
                        .updating($pinch) { value, state, _ in state = value.magnification }
                        .onEnded { value in scale = min(5, max(1, scale * value.magnification)) }
                )
                .onTapGesture(count: 2) { withAnimation { scale = scale > 1 ? 1 : 2.5 } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

#Preview {
    BoardSetupView()
        .environment(GameStore.preview)
}
