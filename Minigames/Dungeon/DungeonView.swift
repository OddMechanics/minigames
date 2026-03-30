import SwiftUI
import SpriteKit

// MARK: - DungeonView

struct DungeonView: View {
    var mapMode: DungeonMapMode = .short
    var onWin:  (() -> Void)? = nil
    var onLose: (() -> Void)? = nil

    @State private var scene: DungeonScene? = nil
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                if let scene {
                    SpriteView(scene: scene)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .ignoresSafeArea()
                } else {
                    Color.black
                        .frame(width: geo.size.width, height: geo.size.height)
                        .ignoresSafeArea()
                }

                // Keyboard capture layer
                Color.clear
                    .contentShape(Rectangle())
                    .focusable()
                    .focused($focused)
                    .onKeyPress(
                        keys: [.leftArrow, .rightArrow, .upArrow, .downArrow,
                               KeyEquivalent("z"), KeyEquivalent(" ")],
                        phases: .down
                    ) { press in
                        guard let scene else { return .ignored }
                        switch press.key {
                        case .leftArrow:         scene.movePlayer(direction: .left)
                        case .rightArrow:        scene.movePlayer(direction: .right)
                        case .upArrow:           scene.movePlayer(direction: .up)
                        case .downArrow:         scene.movePlayer(direction: .down)
                        case KeyEquivalent("z"),
                             KeyEquivalent(" "): scene.playerAttack()
                        default: break
                        }
                        return .handled
                    }

                // On-screen controls
                if let scene {
                    DungeonControls(scene: scene)
                        .padding(.bottom, 24)
                        .padding(.horizontal, 20)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear {
                if scene == nil {
                    let s = DungeonScene(size: geo.size)
                    s.scaleMode = .resizeFill
                    s.mapMode   = mapMode
                    s.onWin     = onWin
                    s.onLose    = onLose
                    scene = s
                }
                focused = true
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .onTapGesture { focused = true }
    }
}

// MARK: - On-screen D-pad + attack button

struct DungeonControls: View {
    let scene: DungeonScene

    var body: some View {
        HStack {
            // D-pad
            VStack(spacing: 4) {
                DungeonButton(symbol: "arrow.up") { scene.movePlayer(direction: .up) }
                HStack(spacing: 4) {
                    DungeonButton(symbol: "arrow.left")  { scene.movePlayer(direction: .left) }
                    // Center pad spacer
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(white: 1, opacity: 0.08))
                        .frame(width: 54, height: 54)
                    DungeonButton(symbol: "arrow.right") { scene.movePlayer(direction: .right) }
                }
                DungeonButton(symbol: "arrow.down") { scene.movePlayer(direction: .down) }
            }

            Spacer()

            // Attack button
            DungeonButton(symbol: "scope", size: 62, fontSize: 28) {
                scene.playerAttack()
            }
        }
    }
}

struct DungeonButton: View {
    let symbol: String
    var size: CGFloat = 54
    var fontSize: CGFloat = 22
    let action: () -> Void

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            // DragGesture with minimumDistance: 0 fires immediately on touch-down
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in action() }
            )
    }
}
