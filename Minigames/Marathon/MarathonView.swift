import SwiftUI
import SpriteKit

// ─────────────────────────────────────────────────────────────────────────────
// Marathon mode: play random minigames back-to-back.
// Lose condition per game:
//   Platformer — 3 deaths
//   Jigsaw     — no lose (must complete to advance)
//   Rocket     — 1 hit
// ─────────────────────────────────────────────────────────────────────────────

enum MiniGame: CaseIterable, Equatable {
    case platformer, jigsaw, rocket
    var displayName: String {
        switch self {
        case .platformer: return "Platformer"
        case .jigsaw:     return "Jigsaw Puzzle"
        case .rocket:     return "Rocket"
        }
    }
}

struct MarathonView: View {
    @State private var gamesPlayed    = 0
    @State private var currentGame: MiniGame = .platformer
    @State private var showDeath      = false
    @State private var excludedGame: MiniGame? = nil
    @State private var sessionID      = UUID()

    var body: some View {
        ZStack {
            if showDeath {
                deathScreen
            } else {
                MarathonGameView(
                    game: currentGame,
                    onWin:  handleWin,
                    onLose: handleLose
                )
                .id(sessionID)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Marathon – Game \(gamesPlayed + 1)")
        .onAppear(perform: newSession)
    }

    // MARK: - Session management

    private func newSession() {
        showDeath   = false
        gamesPlayed = 0
        pick(excluding: excludedGame)
        sessionID   = UUID()
    }

    private func pick(excluding: MiniGame?) {
        var pool = MiniGame.allCases
        if let ex = excluding { pool.removeAll { $0 == ex } }
        currentGame = pool.randomElement() ?? .platformer
    }

    private func handleWin() {
        gamesPlayed += 1
        pick(excluding: excludedGame)
        sessionID = UUID()
    }

    private func handleLose() {
        showDeath = true
    }

    // MARK: - Death screen

    private var deathScreen: some View {
        ZStack {
            Color(red: 0.05, green: 0.04, blue: 0.14).ignoresSafeArea()
            VStack(spacing: 22) {
                Text("Game Over")
                    .font(.system(size: 54, weight: .black, design: .rounded))
                    .foregroundColor(.yellow)
                Text("You completed \(gamesPlayed) \(gamesPlayed == 1 ? "game" : "games")")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
                Text("Lost on: \(currentGame.displayName)")
                    .font(.system(size: 18))
                    .foregroundColor(Color(white: 0.6))
                Button {
                    excludedGame = currentGame
                    newSession()
                } label: {
                    Text("Play Again")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 200, height: 54)
                        .background(Color.yellow)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.top, 8)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Per-game view (creates a fresh scene each time via .id)
// ─────────────────────────────────────────────────────────────────────────────

struct MarathonGameView: View {
    let game:   MiniGame
    let onWin:  () -> Void
    let onLose: () -> Void

    var body: some View {
        switch game {
        case .platformer: MarathonPlatView(onWin: onWin, onLose: onLose)
        case .jigsaw:     MarathonJigView(onWin: onWin)
        case .rocket:     MarathonRktView(onWin: onWin, onLose: onLose)
        }
    }
}

// MARK: - Platformer

struct MarathonPlatView: View {
    let onWin: () -> Void
    let onLose: () -> Void

    @State private var scene: PlatformerScene = {
        let s = PlatformerScene(size: CGSize(width: 1200, height: 700))
        s.scaleMode = .resizeFill
        return s
    }()
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            SpriteView(scene: scene).ignoresSafeArea()
            Color.clear
                .contentShape(Rectangle()).focusable().focused($focused)
                .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .space],
                             phases: .all) { press in
                    switch press.phase {
                    case .down:
                        switch press.key {
                        case .leftArrow: scene.moveLeft()
                        case .rightArrow: scene.moveRight()
                        default: scene.jump()
                        }
                    case .up:
                        if press.key == .leftArrow || press.key == .rightArrow {
                            scene.stopHorizontal()
                        }
                    default: break
                    }
                    return .handled
                }
        }
        .onAppear {
            focused = true
            scene.onWin  = onWin
            scene.onLose = onLose
            scene.marathonLives = 3
        }
        .overlay(alignment: .bottom) {
            GameControls(scene: scene).padding(.bottom, 28)
        }
    }
}

// MARK: - Jigsaw

struct MarathonJigView: View {
    let onWin: () -> Void

    @State private var scene: JigsawPuzzleScene = {
        let s = JigsawPuzzleScene(size: CGSize(width: 1200, height: 700))
        s.scaleMode = .resizeFill
        return s
    }()

    var body: some View {
        SpriteView(scene: scene)
            .ignoresSafeArea()
            .onAppear { scene.onWin = onWin }
    }
}

// MARK: - Rocket

struct MarathonRktView: View {
    let onWin:  () -> Void
    let onLose: () -> Void

    @State private var scene: RocketScene = {
        let s = RocketScene(size: CGSize(width: 1200, height: 700))
        s.scaleMode = .resizeFill
        return s
    }()
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            SpriteView(scene: scene).ignoresSafeArea()
            Color.clear
                .contentShape(Rectangle()).focusable().focused($focused)
                .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .space], phases: .all) { press in
                    let key: String
                    switch press.key {
                    case .leftArrow:  key = "left"
                    case .rightArrow: key = "right"
                    default:          key = "up"
                    }
                    if press.phase == .down { scene.keyDown(key: key) }
                    else if press.phase == .up { scene.keyUp(key: key) }
                    return .handled
                }
            VStack {
                Spacer()
                HStack(spacing: 50) {
                    RocketButton(symbol: "rotate.left")  { scene.keyDown(key: "left") }  onRelease: { scene.keyUp(key: "left") }
                    RocketButton(symbol: "flame.fill")   { scene.keyDown(key: "up") }    onRelease: { scene.keyUp(key: "up") }
                    RocketButton(symbol: "rotate.right") { scene.keyDown(key: "right") } onRelease: { scene.keyUp(key: "right") }
                }
                .padding(.bottom, 28)
            }
        }
        .onAppear {
            focused = true
            scene.onWin  = onWin
            scene.onLose = onLose
        }
    }
}
