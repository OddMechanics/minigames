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
        ZStack {
            SpriteView(scene: scene).ignoresSafeArea()
            Color.clear
                .contentShape(Rectangle()).focusable().focused($focused)
                .onKeyPress(keys: [.leftArrow, .rightArrow], phases: .all) { press in
                    let key = press.key == .leftArrow ? "left" : "right"
                    if press.phase == .down { scene.keyDown(key: key) }
                    else if press.phase == .up { scene.keyUp(key: key) }
                    return .handled
                }
        }
        .onAppear { focused = true }
        .onTapGesture { focused = true }
        .navigationBarTitleDisplayMode(.inline)
    }
}
