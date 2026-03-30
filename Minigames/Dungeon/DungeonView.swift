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
                // Game scene
                if let scene {
                    SpriteView(
                        scene: scene,
                        options: [.shouldCullNonVisibleNodes]
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                    .ignoresSafeArea()
                } else {
                    Color.black
                        .frame(width: geo.size.width, height: geo.size.height)
                        .ignoresSafeArea()
                }

                // Invisible keyboard capture layer
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

                // On-screen pixel-art controls
                if let scene {
                    PixelDungeonControls(scene: scene)
                        .padding(.bottom, 28)
                        .padding(.horizontal, 24)
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

// MARK: - Pixel-art styled on-screen controls

struct PixelDungeonControls: View {
    let scene: DungeonScene

    var body: some View {
        HStack(alignment: .bottom) {
            // D-pad: pixel art style cross
            PixelDPad(scene: scene)
            Spacer()
            // Attack button: sword icon, larger
            PixelAttackButton { scene.playerAttack() }
        }
    }
}

// MARK: - D-pad

struct PixelDPad: View {
    let scene: DungeonScene
    private let btnSize: CGFloat = 52

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer().frame(width: btnSize)
                PixelDirButton(symbol: "▲", size: btnSize) { scene.movePlayer(direction: .up) }
                Spacer().frame(width: btnSize)
            }
            HStack(spacing: 0) {
                PixelDirButton(symbol: "◀", size: btnSize) { scene.movePlayer(direction: .left) }
                // Center piece — dark inset square
                ZStack {
                    Rectangle()
                        .fill(Color(red: 0.06, green: 0.05, blue: 0.14))
                        .frame(width: btnSize, height: btnSize)
                    Rectangle()
                        .fill(Color(red: 0.12, green: 0.10, blue: 0.22))
                        .frame(width: btnSize - 8, height: btnSize - 8)
                }
                PixelDirButton(symbol: "▶", size: btnSize) { scene.movePlayer(direction: .right) }
            }
            HStack(spacing: 0) {
                Spacer().frame(width: btnSize)
                PixelDirButton(symbol: "▼", size: btnSize) { scene.movePlayer(direction: .down) }
                Spacer().frame(width: btnSize)
            }
        }
    }
}

// MARK: - Directional button (pixel-art flat style)

struct PixelDirButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Text(symbol)
            .font(.system(size: 18, weight: .heavy, design: .monospaced))
            .foregroundColor(pressed ? Color(red: 0.9, green: 0.85, blue: 0.3) : Color(white: 0.80))
            .frame(width: size, height: size)
            .background(
                ZStack {
                    // Pixel-style dark background with hard bevel
                    Rectangle()
                        .fill(Color(red: 0.06, green: 0.05, blue: 0.14))
                    // Top/left light edge
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color(white: pressed ? 0.08 : 0.22))
                            .frame(height: 2)
                        Spacer()
                    }
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color(white: pressed ? 0.08 : 0.22))
                            .frame(width: 2)
                        Spacer()
                    }
                    // Bottom/right dark edge
                    VStack(spacing: 0) {
                        Spacer()
                        Rectangle()
                            .fill(Color(white: pressed ? 0.22 : 0.04))
                            .frame(height: 2)
                    }
                    HStack(spacing: 0) {
                        Spacer()
                        Rectangle()
                            .fill(Color(white: pressed ? 0.22 : 0.04))
                            .frame(width: 2)
                    }
                    // Inset fill when pressed
                    if pressed {
                        Rectangle()
                            .fill(Color(red: 0.12, green: 0.10, blue: 0.25))
                            .padding(2)
                    }
                }
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressed {
                            pressed = true
                            action()
                        }
                    }
                    .onEnded { _ in pressed = false }
            )
    }
}

// MARK: - Attack button (pixel art sword)

struct PixelAttackButton: View {
    let action: () -> Void

    @State private var pressed = false
    private let size: CGFloat = 68

    var body: some View {
        ZStack {
            // Outer dark frame
            Rectangle()
                .fill(Color(red: 0.06, green: 0.05, blue: 0.14))
                .frame(width: size, height: size)

            // Bevel top/left
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color(white: pressed ? 0.06 : 0.24))
                    .frame(height: 3)
                Spacer()
            }
            .frame(width: size, height: size)
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color(white: pressed ? 0.06 : 0.24))
                    .frame(width: 3)
                Spacer()
            }
            .frame(width: size, height: size)

            // Bevel bottom/right
            VStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(Color(white: pressed ? 0.24 : 0.04))
                    .frame(height: 3)
            }
            .frame(width: size, height: size)
            HStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(Color(white: pressed ? 0.24 : 0.04))
                    .frame(width: 3)
            }
            .frame(width: size, height: size)

            // Inner button fill
            Rectangle()
                .fill(pressed
                      ? Color(red: 0.14, green: 0.12, blue: 0.30)
                      : Color(red: 0.10, green: 0.08, blue: 0.22))
                .frame(width: size - 6, height: size - 6)

            // Sword icon + label
            VStack(spacing: 3) {
                Text("⚔")
                    .font(.system(size: 24))
                    .foregroundColor(pressed
                                     ? Color(red: 1.0, green: 0.88, blue: 0.3)
                                     : Color(red: 0.85, green: 0.85, blue: 0.95))
                Text("ATK")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.55))
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed {
                        pressed = true
                        action()
                    }
                }
                .onEnded { _ in pressed = false }
        )
    }
}
