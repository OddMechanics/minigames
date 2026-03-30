import SwiftUI
import SpriteKit

struct DrivingView: View {

    // MARK: - Configuration
    var mapMode: DrivingMapMode = .short
    var onWin:   (() -> Void)?  = nil
    var onLose:  (() -> Void)?  = nil

    // MARK: - Scene
    private let scene: DrivingScene = {
        let s = DrivingScene(size: CGSize(width: 1194, height: 768))
        s.scaleMode = .resizeFill
        return s
    }()

    @FocusState private var focused: Bool

    // MARK: - Init

    init(mapMode: DrivingMapMode = .short,
         onWin:  (() -> Void)?  = nil,
         onLose: (() -> Void)?  = nil) {
        self.mapMode = mapMode
        self.onWin   = onWin
        self.onLose  = onLose
        scene.mapMode = mapMode
        scene.onWin   = onWin
        scene.onLose  = onLose
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            SpriteView(scene: scene)
                .frame(width: geo.size.width, height: geo.size.height)
                .ignoresSafeArea()
                // Keyboard capture
                .focusable()
                .focused($focused)
                .onKeyPress(
                    keys: [.upArrow, .space],
                    phases: .all
                ) { press in
                    switch press.phase {
                    case .down: scene.gasPressed()
                    case .up:   scene.gasReleased()
                    default:    break
                    }
                    return .handled
                }
                // Gas button pinned to bottom-trailing corner
                .overlay(alignment: .bottomTrailing) {
                    GasButton(
                        onPress:   { scene.gasPressed()   },
                        onRelease: { scene.gasReleased() }
                    )
                    .padding(36)
                }
        }
        .ignoresSafeArea()
        .onAppear { focused = true }
        .onTapGesture { focused = true }
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - GAS Button

struct GasButton: View {
    let onPress:   () -> Void
    let onRelease: () -> Void

    @State private var isPressed = false

    var body: some View {
        ZStack {
            // Glow halo when pressed
            if isPressed {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.5, blue: 0.0, opacity: 0.5),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 28,
                            endRadius: 68
                        )
                    )
                    .frame(width: 136, height: 136)
            }

            // Button body
            Circle()
                .fill(
                    isPressed
                        ? Color(red: 1.0, green: 0.45, blue: 0.00)
                        : Color(red: 0.9,  green: 0.25, blue: 0.05)
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            Color(white: isPressed ? 1.0 : 0.7, opacity: 0.4),
                            lineWidth: 3
                        )
                )
                .frame(width: 96, height: 96)
                .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
                .scaleEffect(isPressed ? 0.93 : 1.0)
                .animation(.easeInOut(duration: 0.06), value: isPressed)

            // Label
            VStack(spacing: 2) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 20, weight: .black))
                Text("GAS")
                    .font(.system(size: 14, weight: .black, design: .rounded))
            }
            .foregroundStyle(.white)
            .shadow(radius: 2)
        }
        .frame(width: 136, height: 136)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        onPress()
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    onRelease()
                }
        )
    }
}

// MARK: - Preview

#Preview {
    DrivingView(mapMode: .short)
}
