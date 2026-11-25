import BingoKit
import SwiftUI

/// The editable choices behind a `WinningRule`, in the shape the settings screen needs.
struct RuleDraft {
    enum Kind: String, CaseIterable, Identifiable {
        case fiveInARow, columns, square2x2, rectangle3x2, tShape, blackout, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .fiveInARow: "Five in a row"
            case .columns: "Column(s)"
            case .square2x2: "2×2 square"
            case .rectangle3x2: "3×2 rectangle"
            case .tShape: "T shape"
            case .blackout: "Blackout"
            case .custom: "Custom pattern"
            }
        }
        var isShape: Bool { ![.fiveInARow, .columns, .blackout].contains(self) }
    }

    enum PlacementKind: String, CaseIterable, Identifiable {
        case anywhere, corners, exactlyAsDrawn
        var id: String { rawValue }
        var title: String {
            switch self {
            case .anywhere: "Anywhere"
            case .corners: "Corners"
            case .exactlyAsDrawn: "As drawn"
            }
        }
    }

    enum OccurrenceKind: String, CaseIterable, Identifiable {
        case any, atLeast, all
        var id: String { rawValue }
        var title: String {
            switch self {
            case .any: "Any one"
            case .atLeast: "At least…"
            case .all: "All"
            }
        }
    }

    var kind: Kind = .fiveInARow
    var includeDiagonals = true
    var columns: Set<BingoColumn> = [.b]
    var customShape = PatternShape([])
    var placementKind: PlacementKind = .anywhere
    var corners: Set<Corner> = Set(Corner.allCases)
    var orientation: Orientation = .rotationsAndReflections
    var occurrenceKind: OccurrenceKind = .any
    var atLeastCount = 2

    var shape: PatternShape {
        switch kind {
        case .square2x2: .square2x2
        case .rectangle3x2: .rectangle3x2
        case .tShape: .tShape
        case .blackout: .fullCard
        default: customShape
        }
    }

    var rule: WinningRule {
        let occurrence: Occurrence = switch occurrenceKind {
        case .any: .any
        case .atLeast: .atLeast(atLeastCount)
        case .all: .all
        }
        switch kind {
        case .fiveInARow:
            return WinningRule(name: kind.title, pattern: .line(includeDiagonals: includeDiagonals), occurrence: occurrence)
        case .columns:
            let letters = columns.sorted().map(\.letter).joined(separator: ", ")
            let name = columns.count == 1 ? "\(letters) column" : "\(letters) columns"
            return WinningRule(name: name, pattern: .columns(columns), occurrence: occurrence)
        case .blackout:
            return .blackout
        case .square2x2, .rectangle3x2, .tShape, .custom:
            let placement: Placement = switch placementKind {
            case .anywhere: .anywhere
            case .corners: .corners(corners)
            case .exactlyAsDrawn: .exactlyAsDrawn
            }
            return WinningRule(
                name: kind.title,
                pattern: .shape(shape, placement: placement, orientation: orientation),
                occurrence: occurrence
            )
        }
    }

    init() {}

    /// Rebuild the editable choices from a saved rule.
    init(rule: WinningRule) {
        switch rule.occurrence {
        case .any: occurrenceKind = .any
        case .atLeast(let n): occurrenceKind = .atLeast; atLeastCount = n
        case .all: occurrenceKind = .all
        }
        switch rule.pattern {
        case .line(let diagonals):
            kind = .fiveInARow
            includeDiagonals = diagonals
        case .columns(let selected):
            kind = .columns
            columns = selected
        case .shape(let shape, let placement, let orientation):
            self.orientation = orientation
            switch placement {
            case .anywhere: placementKind = .anywhere
            case .corners(let selected): placementKind = .corners; corners = selected
            case .exactlyAsDrawn: placementKind = .exactlyAsDrawn
            }
            switch shape {
            case .fullCard where placement == .exactlyAsDrawn: kind = .blackout
            case .square2x2: kind = .square2x2
            case .rectangle3x2: kind = .rectangle3x2
            case .tShape: kind = .tShape
            default: kind = .custom; customShape = shape
            }
        }
    }
}

/// Choose the winning pattern, where it can appear, how many times, and the free center.
struct RuleSetupView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = RuleDraft()
    @State private var freeCenter = true

    var body: some View {
        let rule = draft.rule
        let total = rule.placements.count
        let required = rule.occurrence.requiredCount(outOf: total)

        NavigationStack {
            Form {
                Section {
                    Toggle("Free center square", isOn: $freeCenter)
                } footer: {
                    Text("When on, the center starts marked. When off, it's marked only when its number is called.")
                }

                Section("Pattern") {
                    Picker("Pattern", selection: $draft.kind) {
                        ForEach(RuleDraft.Kind.allCases) { Text($0.title).tag($0) }
                    }
                    patternOptions
                }

                if draft.kind.isShape {
                    placementSection
                }

                if total > 1 || draft.occurrenceKind != .any {
                    occurrenceSection(total: total)
                }

                Section {
                    summary(total: total, required: required)
                }
            }
            .navigationTitle("Winning rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.game.rule = rule
                        store.game.freeCenter = freeCenter
                        dismiss()
                    }
                    .disabled(total == 0 || required > total)
                }
            }
            .onAppear {
                draft = RuleDraft(rule: store.game.rule)
                freeCenter = store.game.freeCenter
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var patternOptions: some View {
        switch draft.kind {
        case .fiveInARow:
            Toggle("Include diagonals", isOn: $draft.includeDiagonals)
        case .columns:
            HStack {
                ForEach(BingoColumn.allCases) { column in
                    let selected = draft.columns.contains(column)
                    Button {
                        if selected { draft.columns.remove(column) } else { draft.columns.insert(column) }
                    } label: {
                        Text(column.letter)
                            .font(.title3.weight(.heavy))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(selected ? Color.accentColor : Color(.tertiarySystemFill)))
                            .foregroundStyle(selected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        case .blackout:
            Text("Every square on the card must be marked.")
                .foregroundStyle(.secondary)
        case .square2x2, .rectangle3x2, .tShape, .custom:
            VStack(alignment: .leading, spacing: 8) {
                PatternEditorGrid(cells: draft.shape.cells) { cell in
                    // Editing a preset turns it into a custom pattern starting from that preset.
                    var shape = draft.shape
                    shape.toggle(cell)
                    draft.customShape = shape
                    draft.kind = .custom
                }
                .frame(maxWidth: 260)
                .frame(maxWidth: .infinity)
                Text(draft.placementKind == .exactlyAsDrawn
                     ? "Tap squares to draw the exact squares needed."
                     : "Tap squares to draw the shape. Its position here doesn't matter.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var placementSection: some View {
        Section("Where it can appear") {
            Picker("Placement", selection: $draft.placementKind) {
                ForEach(RuleDraft.PlacementKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            if draft.placementKind == .corners {
                ForEach(Corner.allCases) { corner in
                    Toggle(corner.title, isOn: Binding(
                        get: { draft.corners.contains(corner) },
                        set: { isOn in
                            if isOn { draft.corners.insert(corner) } else { draft.corners.remove(corner) }
                        }
                    ))
                }
            }

            if draft.placementKind != .exactlyAsDrawn {
                Picker("Orientation", selection: $draft.orientation) {
                    ForEach(Orientation.allCases) { Text($0.title).tag($0) }
                }
            }
        }
    }

    private func occurrenceSection(total: Int) -> some View {
        Section("To win, complete") {
            Picker("Occurrences", selection: $draft.occurrenceKind) {
                ForEach(RuleDraft.OccurrenceKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            if draft.occurrenceKind == .atLeast {
                Stepper("At least \(draft.atLeastCount)", value: $draft.atLeastCount, in: 2...max(2, total))
            }
        }
    }

    @ViewBuilder
    private func summary(total: Int, required: Int) -> some View {
        if total == 0 {
            Label("Nothing to match yet — choose at least one column, corner or square.",
                  systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        } else if required > total {
            Label("Needs \(required) but only \(total) placement\(total == 1 ? " is" : "s are") possible.",
                  systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        } else {
            Text("\(total) possible placement\(total == 1 ? "" : "s") on a card · need \(required) to win")
                .foregroundStyle(.secondary)
        }
    }
}

/// A tappable 5×5 grid for drawing a pattern.
struct PatternEditorGrid: View {
    let cells: Set<Cell>
    let onTap: (Cell) -> Void

    var body: some View {
        FiveByFiveGrid { cell in
            let isOn = cells.contains(cell)
            RoundedRectangle(cornerRadius: 6)
                .fill(isOn ? Color.accentColor : Color(.tertiarySystemFill))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if cell.isCenter && !isOn {
                        Text("★").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { onTap(cell) }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Row \(cell.row + 1), column \(cell.column + 1)\(isOn ? ", selected" : "")")
        }
    }
}

#Preview {
    RuleSetupView()
        .environment(GameStore.preview)
}
