import SwiftUI
import SpriteKit

struct JigsawPuzzleView: View {
    private let scene: JigsawPuzzleScene = {
        let s = JigsawPuzzleScene(size: CGSize(width: 1200, height: 700))
        s.scaleMode = .resizeFill
        return s
    }()

    var body: some View {
        SpriteView(scene: scene)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .toolbar(.hidden, for: .navigationBar)
    }
}
