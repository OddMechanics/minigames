import SwiftUI
import SpriteKit

// MARK: - DrivingView

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
                .onKeyPress(keys: [.upArrow, .space], phases: .all) { press in
                    switch press.phase {
                    case .down: scene.gasPressed()
                    case .up:   scene.gasReleased()
                    default:    break
                    }
                    return .handled
                }
                .onKeyPress(keys: [.downArrow], phases: .all) { press in
                    switch press.phase {
                    case .down: scene.brakePressed()
                    case .up:   scene.brakeReleased()
                    default:    break
                    }
                    return .handled
                }
                .onKeyPress(keys: [.leftArrow], phases: .all) { press in
                    switch press.phase {
                    case .down: scene.leanLeftPressed()
                    case .up:   scene.leanLeftReleased()
                    default:    break
                    }
                    return .handled
                }
                .onKeyPress(keys: [.rightArrow], phases: .all) { press in
                    switch press.phase {
                    case .down: scene.leanRightPressed()
                    case .up:   scene.leanRightReleased()
                    default:    break
                    }
                    return .handled
                }
                .onKeyPress(keys: ["r"], phases: .down) { _ in
                    scene.restartPressed()
                    return .handled
                }
                // LEFT SIDE: LEAN LEFT | BRAKE | LEAN RIGHT
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 12) {
                        ControlButton(
                            label: "←",
                            sublabel: "LEAN",
                            accentColor: Color(red: 0.15, green: 0.55, blue: 0.95),
                            onPress:   { scene.leanLeftPressed()  },
                            onRelease: { scene.leanLeftReleased() }
                        )
                        ControlButton(
                            label: "▼",
                            sublabel: "BRAKE",
                            accentColor: Color(red: 0.90, green: 0.20, blue: 0.20),
                            onPress:   { scene.brakePressed()  },
                            onRelease: { scene.brakeReleased() }
                        )
                        ControlButton(
                            label: "→",
                            sublabel: "LEAN",
                            accentColor: Color(red: 0.15, green: 0.55, blue: 0.95),
                            onPress:   { scene.leanRightPressed()  },
                            onRelease: { scene.leanRightReleased() }
                        )
                    }
                    .padding(.leading, 28)
                    .padding(.bottom, 32)
                }
                // RIGHT SIDE: GAS (with gas bar handled in SpriteKit HUD)
                .overlay(alignment: .bottomTrailing) {
                    GasButton(
                        onPress:   { scene.gasPressed()   },
                        onRelease: { scene.gasReleased() }
                    )
                    .padding(.trailing, 28)
                    .padding(.bottom, 32)
                }
        }
        .ignoresSafeArea()
        .onAppear { focused = true }
        .onTapGesture { focused = true }
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Control Button (lean / brake)

struct ControlButton: View {
    let label:       String
    let sublabel:    String
    let accentColor: Color
    let onPress:     () -> Void
    let onRelease:   () -> Void

    @State private var isPressed = false

    var body: some View {
        ZStack {
            // Glow halo
            if isPressed {
                RoundedRectangle(cornerRadius: 18)
                    .fill(accentColor.opacity(0.35))
                    .frame(width: 92, height: 92)
                    .blur(radius: 10)
            }

            // Button face
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    isPressed
                        ? accentColor.opacity(0.85)
                        : Color(white: 0.12).opacity(0.82)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            accentColor.opacity(isPressed ? 0.9 : 0.45),
                            lineWidth: 2
                        )
                )
                .frame(width: 78, height: 78)
                .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 3)
                .scaleEffect(isPressed ? 0.91 : 1.0)
                .animation(.easeInOut(duration: 0.06), value: isPressed)

            // Icon + label
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 24, weight: .black))
                Text(sublabel)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.5)
            }
            .foregroundStyle(.white)
            .shadow(radius: 2)
        }
        .frame(width: 92, height: 92)
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

// MARK: - Gas Button

struct GasButton: View {
    let onPress:   () -> Void
    let onRelease: () -> Void

    @State private var isPressed = false

    var body: some View {
        ZStack {
            // Glow halo
            if isPressed {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.5, blue: 0.0, opacity: 0.55),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 30,
                            endRadius: 72
                        )
                    )
                    .frame(width: 144, height: 144)
            }

            // Button body
            Circle()
                .fill(
                    isPressed
                        ? Color(red: 1.0, green: 0.48, blue: 0.00)
                        : Color(red: 0.88, green: 0.22, blue: 0.04)
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            Color(white: isPressed ? 1.0 : 0.7, opacity: 0.4),
                            lineWidth: 3
                        )
                )
                .frame(width: 100, height: 100)
                .shadow(color: Color.black.opacity(0.45), radius: 10, x: 0, y: 4)
                .scaleEffect(isPressed ? 0.92 : 1.0)
                .animation(.easeInOut(duration: 0.06), value: isPressed)

            // Icon + label
            VStack(spacing: 2) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 22, weight: .black))
                Text("GAS")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .tracking(1)
            }
            .foregroundStyle(.white)
            .shadow(radius: 3)
        }
        .frame(width: 144, height: 144)
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
