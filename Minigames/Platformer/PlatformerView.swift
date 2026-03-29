import SwiftUI
import SpriteKit

struct PlatformerView: View {
    private let scene: PlatformerScene = {
        let s = PlatformerScene(size: CGSize(width: 1200, height: 700))
        s.scaleMode = .resizeFill
        return s
    }()

    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SpriteView(scene: scene)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .ignoresSafeArea()

                Color.clear
                    .contentShape(Rectangle())
                    .focusable()
                    .focused($focused)
                    .onKeyPress(
                        keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .space],
                        phases: .all
                    ) { press in
                        switch press.phase {
                        case .down:
                            switch press.key {
                            case .leftArrow:              scene.moveLeft()
                            case .rightArrow:             scene.moveRight()
                            case .upArrow, .downArrow,
                                 .space:                  scene.jump()
                            default: break
                            }
                        case .up:
                            switch press.key {
                            case .leftArrow, .rightArrow: scene.stopHorizontal()
                            default: break
                            }
                        default: break
                        }
                        return .handled
                    }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .onAppear { focused = true }
        .onTapGesture { focused = true }
        .overlay(alignment: .bottom) {
            GameControls(scene: scene)
                .padding(.bottom, 28)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - On-screen controls

struct GameControls: View {
    let scene: PlatformerScene

    var body: some View {
        HStack(spacing: 60) {
            HStack(spacing: 10) {
                GameButton(symbol: "arrow.left") {
                    scene.moveLeft()
                } onRelease: {
                    scene.stopHorizontal()
                }
                GameButton(symbol: "arrow.right") {
                    scene.moveRight()
                } onRelease: {
                    scene.stopHorizontal()
                }
            }
            GameButton(symbol: "arrow.up") {
                scene.jump()
            } onRelease: {}
        }
    }
}

struct GameButton: View {
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
