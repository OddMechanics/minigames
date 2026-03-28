import SwiftUI
import SpriteKit

struct RocketView: View {
    private let scene: RocketScene = {
        let s = RocketScene(size: CGSize(width: 1200, height: 700))
        s.scaleMode = .resizeFill
        return s
    }()

    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            SpriteView(scene: scene).ignoresSafeArea()

            Color.clear
                .contentShape(Rectangle())
                .focusable()
                .focused($focused)
                .onKeyPress(
                    keys: [.leftArrow, .rightArrow, .upArrow, .space],
                    phases: .all
                ) { press in
                    let key: String
                    switch press.key {
                    case .leftArrow:  key = "left"
                    case .rightArrow: key = "right"
                    case .upArrow:    key = "up"
                    default:          key = "space"
                    }
                    if press.phase == .down { scene.keyDown(key: key) }
                    else if press.phase == .up { scene.keyUp(key: key) }
                    return .handled
                }

            // On-screen controls overlay
            VStack {
                Spacer()
                HStack(spacing: 50) {
                    RocketButton(symbol: "rotate.left") { scene.keyDown(key: "left") }
                        onRelease: { scene.keyUp(key: "left") }
                    RocketButton(symbol: "flame.fill") { scene.keyDown(key: "up") }
                        onRelease: { scene.keyUp(key: "up") }
                    RocketButton(symbol: "rotate.right") { scene.keyDown(key: "right") }
                        onRelease: { scene.keyUp(key: "right") }
                }
                .padding(.bottom, 28)
            }
        }
        .onAppear { focused = true }
        .onTapGesture  { focused = true }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RocketButton: View {
    let symbol: String
    let onPress: () -> Void
    let onRelease: () -> Void

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 66, height: 66)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onPress() }
                    .onEnded   { _ in onRelease() }
            )
    }
}
