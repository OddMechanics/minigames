import SwiftUI
import SpriteKit

struct PingPongView: View {
    private let scene: PingPongScene = {
        let s = PingPongScene(size: CGSize(width: 1200, height: 700))
        s.scaleMode = .resizeFill
        return s
    }()

    @FocusState private var focused: Bool

    var body: some View {
        SpriteView(scene: scene)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            // Keyboard overlay sits behind touches (allowsHitTesting false)
            // so the SpriteView receives all touch input directly.
            .overlay {
                Color.clear
                    .contentShape(Rectangle())
                    .focusable()
                    .focused($focused)
                    .allowsHitTesting(false)   // don't block scene touches
                    .onKeyPress(keys: [.leftArrow, .rightArrow], phases: .all) { press in
                        let key = press.key == .leftArrow ? "left" : "right"
                        if press.phase == .down { scene.keyDown(key: key) }
                        else if press.phase == .up { scene.keyUp(key: key) }
                        return .handled
                    }
            }
            .onAppear { focused = true }
            .toolbar(.hidden, for: .navigationBar)
    }
}
