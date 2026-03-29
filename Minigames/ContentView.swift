import SwiftUI

struct ContentView: View {
    var body: some View {
        GeometryReader { geo in
            InfiniteView()
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }
}
