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
        GeometryReader { geo in
            SpriteView(scene: scene)
                .frame(width: geo.size.width, height: geo.size.height)
                .ignoresSafeArea()
                .overlay {
                    Color.clear
                        .contentShape(Rectangle())
                        .focusable()
                        .focused($focused)
                        .allowsHitTesting(false)
                        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: .all) { press in
                            let key = press.key == .leftArrow ? "left" : "right"
                            if press.phase == .down { scene.keyDown(key: key) }
                            else if press.phase == .up { scene.keyUp(key: key) }
                            return .handled
                        }
                }
        }
        .ignoresSafeArea()
        .onAppear { focused = true }
        .toolbar(.hidden, for: .navigationBar)
    }
}
