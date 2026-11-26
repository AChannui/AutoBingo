import BingoKit
import SwiftUI

/// Name a group, choose which saved boards are in it, scan new cards straight into it,
/// and put the whole group into (or out of) play.
struct GroupEditorView: View {
    @Binding var group: BoardGroup
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false

    var body: some View {
        let game = store.game
        let state = game.playState(of: group)
        let members = game.boards(in: group)
        let others = game.boards.filter { !group.contains($0.id) }

        List {
            Section {
                TextField("Group name", text: $group.name)
                    .font(.title3.weight(.semibold))
            }

            Section {
                playButtons(state: state, isEmpty: members.isEmpty)
            } footer: {
                Text(footer(for: state))
            }

            Section {
                BulkScanButtons { photos in store.addBoards(from: photos, toGroup: group.id) }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } footer: {
                Text("New cards scanned here are saved and added to \(group.name).")
            }

            Section("In this group (\(members.count))") {
                if members.isEmpty {
                    Text("Tap a board below to add it.")
                        .foregroundStyle(.secondary)
                }
                ForEach(members) { memberRow($0, included: true) }
            }

            if !others.isEmpty {
                Section("Other saved boards") {
                    ForEach(others) { memberRow($0, included: false) }
                }
            }

            Section {
                Button("Delete group", role: .destructive) { confirmingDelete = true }
            } footer: {
                Text("Deleting a group keeps its boards.")
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete \(group.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete group", role: .destructive) {
                let id = group.id
                dismiss()
                // Remove after leaving, so this screen's binding never points at a missing group.
                Task { store.game.removeGroup(id: id) }
            }
        } message: {
            Text("Its boards stay saved.")
        }
    }

    @ViewBuilder
    private func playButtons(state: BingoGame.GroupPlayState, isEmpty: Bool) -> some View {
        if state == .playing {
            stopButton(systemImage: "stop.fill")
        } else {
            Button("Play only this group", systemImage: "play.fill") {
                store.game.playGroup(id: group.id)
            }
            .disabled(isEmpty)
            if state != .playingWithOthers {
                Button("Add to boards playing", systemImage: "plus.circle") {
                    store.game.playGroup(id: group.id, replacingActive: false)
                }
                .disabled(isEmpty)
            }
            if state != .notPlaying {
                stopButton(systemImage: "stop")
            }
        }
    }

    private func stopButton(systemImage: String) -> some View {
        Button(role: .destructive) {
            store.game.stopPlayingGroup(id: group.id)
        } label: {
            Label("Stop playing this group", systemImage: systemImage)
                .foregroundStyle(.red)
        }
    }

    private func footer(for state: BingoGame.GroupPlayState) -> String {
        switch state {
        case .notPlaying: "None of these boards are playing."
        case .partlyPlaying: "Some of these boards are playing."
        case .playingWithOthers: "All of these boards are playing, along with others."
        case .playing: "Exactly this group is playing."
        }
    }

    private func memberRow(_ board: BingoBoard, included: Bool) -> some View {
        Button {
            withAnimation { store.game.setBoard(board.id, inGroup: group.id, !included) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: included ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(included ? Color.accentColor : .secondary)
                Text(board.name)
                    .foregroundStyle(.primary)
                if store.game.isActive(board.id) {
                    Image(systemName: "play.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .accessibilityLabel("Playing")
                }
                Spacer()
                BoardStatusLabel(board: board)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(included ? "Remove \(board.name) from group" : "Add \(board.name) to group")
    }
}
