import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink(destination: PlatformerView()) {
                    Label("Platformer", systemImage: "gamecontroller.fill")
                }
            }
            .navigationTitle("Minigames")
        }
    }
}
