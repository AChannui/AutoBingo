import BingoKit
import SwiftUI

/// Every number called this game, newest first. Swipe to remove a mistaken call.
struct CallHistoryView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if store.game.calls.isEmpty {
                    Text("No numbers called yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(store.game.calls.enumerated().reversed()), id: \.element) { position, number in
                    HStack {
                        Text("\(position + 1).")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 32, alignment: .trailing)
                        Text(BingoColumn.label(for: number))
                            .font(.headline.monospacedDigit())
                        Spacer()
                        let hits = store.game.boards(containing: number).map(\.name)
                        Text(hits.isEmpty ? "—" : hits.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) {
                            store.game.removeCall(number)
                        }
                    }
                }
            }
            .navigationTitle("Called numbers")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
