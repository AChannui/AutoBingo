import SwiftUI

@main
struct AutoBingoApp: App {
    @State private var store = GameStore()

    var body: some Scene {
        WindowGroup {
            GameView()
                .environment(store)
        }
    }
}
