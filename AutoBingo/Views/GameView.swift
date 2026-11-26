import BingoKit
import SwiftUI

/// The main screen: current rule, call entry, and the boards in play.
struct GameView: View {
    @Environment(GameStore.self) private var store
    @State private var showingRules = false
    @State private var showingBoards = false
    @State private var showingHistory = false
    @State private var confirmingNewGame = false

    private var game: BingoGame { store.game }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ruleSummary

                    if game.activeBoards.allSatisfy(\.isEmpty) {
                        setupPrompt
                    } else {
                        CallEntryView()
                        winnerBanner
                    }

                    ForEach(game.activeBoards) { board in
                        BoardCardView(
                            board: board,
                            marked: game.markedCells(on: board),
                            progress: game.progress(for: board),
                            lastCall: game.lastCall
                        )
                    }
                }
                .padding()
                .animation(.default, value: game.calls)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Cruise Bingo")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(game.boards.isEmpty ? "Boards" : "Boards (\(game.activeBoards.count)/\(game.boards.count))") {
                        showingBoards = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Call history", systemImage: "list.number") { showingHistory = true }
                        Button("Winning rule", systemImage: "square.grid.3x3") { showingRules = true }
                        Divider()
                        Button("New game…", systemImage: "arrow.clockwise") { confirmingNewGame = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingRules) { RuleSetupView() }
            .sheet(isPresented: $showingBoards) { BoardSetupView() }
            .sheet(isPresented: $showingHistory) { CallHistoryView() }
            .task {
                if DemoLaunch.boardImage != nil || !DemoLaunch.bulkBoardImages.isEmpty { showingBoards = true }
            }
            .confirmationDialog("Start a new game?", isPresented: $confirmingNewGame, titleVisibility: .visible) {
                Button("New game, keep these boards") {
                    store.game.startNewGame(keepActiveBoards: true)
                }
                Button("New game, pick other boards") {
                    store.game.startNewGame(keepActiveBoards: false)
                    showingBoards = true
                }
            } message: {
                Text("This clears the \(game.calls.count) called numbers.")
            }
        }
    }

    private var ruleSummary: some View {
        Button { showingRules = true } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.rule.name)
                        .font(.headline)
                    Text([game.rule.detail, game.freeCenter ? "free center" : "no free center"]
                        .filter { !$0.isEmpty }
                        .joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
    }

    private var setupPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
            Text(game.boards.isEmpty ? "Scan your boards to start" : "Pick which boards to play")
                .font(.headline)
            if !game.boards.isEmpty {
                Text("You have \(game.boards.count) saved board\(game.boards.count == 1 ? "" : "s").")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button(game.boards.isEmpty ? "Set up boards" : "Choose boards") { showingBoards = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    @ViewBuilder
    private var winnerBanner: some View {
        let winners = game.winningBoards
        if !winners.isEmpty {
            HStack {
                Image(systemName: "star.fill")
                Text("BINGO on \(winners.map(\.name).joined(separator: " & "))!")
            }
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.green))
            .transition(.scale.combined(with: .opacity))
        }
    }
}

#Preview {
    GameView()
        .environment(GameStore.preview)
}
