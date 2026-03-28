import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink(destination: PlatformerView()) {
                    Label("Platformer", systemImage: "gamecontroller.fill")
                }
                NavigationLink(destination: JigsawPuzzleView()) {
                    Label("Jigsaw Puzzle", systemImage: "puzzlepiece.fill")
                }
                NavigationLink(destination: RocketView()) {
                    Label("Rocket", systemImage: "airplane")
                }
                NavigationLink(destination: MarathonView()) {
                    Label("Marathon", systemImage: "bolt.fill")
                }
            }
            .navigationTitle("Minigames")
        }
    }
}
