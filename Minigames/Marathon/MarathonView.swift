import SwiftUI
import SpriteKit

// ─────────────────────────────────────────────────────────────────────────────
// Infinite Mode: play random minigames back-to-back until you lose.
// Lose conditions: Platformer = 1 death, Rocket = 1 hit, PingPong = lose match,
//                  Jigsaw = must complete to advance (no lose).
// ─────────────────────────────────────────────────────────────────────────────

enum MiniGame: CaseIterable, Equatable, Identifiable {
    case platformer, jigsaw, rocket, pingPong
    var id: Self { self }
    var displayName: String {
        switch self {
        case .platformer: return "Platformer"
        case .jigsaw:     return "Jigsaw Puzzle"
        case .rocket:     return "Rocket"
        case .pingPong:   return "Ping Pong"
        }
    }
}

// InfiniteView manages the full infinite-mode lifecycle.
// ContentView uses this as its root.
struct InfiniteView: View {
    enum State { case home, browsing, playing, standalone(MiniGame), dead(gamesCompleted: Int, lostOn: MiniGame) }

    @SwiftUI.State private var state: State = .home
    @SwiftUI.State private var currentGame: MiniGame = .platformer
    @SwiftUI.State private var excludedGame: MiniGame? = nil
    @SwiftUI.State private var gamesPlayed = 0
    @SwiftUI.State private var sessionID   = UUID()

    var body: some View {
        switch state {
        case .home:                        homeView
        case .browsing:                    browsingView
        case .playing:                     playingView
        case .standalone(let game):        standaloneView(game: game)
        case .dead(let n, let game):       deathView(gamesCompleted: n, lostOn: game)
        }
    }

    // MARK: - Home

    private var homeView: some View {
        ZStack(alignment: .bottom) {
            Color(red: 0.03, green: 0.02, blue: 0.12).ignoresSafeArea()

            // Stars decoration
            Canvas { ctx, size in
                for i in 0..<120 {
                    let x = Double((i * 97 + 31) % Int(size.width))
                    let y = Double((i * 61 + 17) % Int(size.height))
                    let r = Double((i % 3) + 1) * 0.7
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r*2, height: r*2)),
                             with: .color(.white.opacity(0.5 + Double(i % 5) * 0.1)))
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()
                Text("∞ Infinite Mode")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("Play random minigames until you lose")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Color(white: 0.65))
                Button {
                    startPlaying(excluding: nil)
                } label: {
                    Text("Play")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 220, height: 60)
                        .background(Color.yellow)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.top, 10)
                Spacer()
            }

            Button {
                state = .browsing
            } label: {
                Text("View Minigames")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 13)
                    .background(Color(white: 1, opacity: 0.12), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.bottom, 32)
        }
    }

    // MARK: - Browsing

    private var browsingView: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.03, green: 0.02, blue: 0.12).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Minigames")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.top, 60)
                ForEach(MiniGame.allCases) { game in
                    Button { state = .standalone(game) } label: {
                        Text(game.displayName)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: 300, minHeight: 56)
                            .background(Color(white: 1, opacity: 0.12), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                Spacer()
            }
            Button { state = .home } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.top, 52)
            .padding(.leading, 16)
        }
    }

    // MARK: - Standalone game

    private func standaloneView(game: MiniGame) -> some View {
        ZStack(alignment: .topLeading) {
            switch game {
            case .platformer: PlatformerView()
            case .jigsaw:     JigsawPuzzleView()
            case .rocket:     RocketView()
            case .pingPong:   PingPongView()
            }
            Button { state = .browsing } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.top, 52)
            .padding(.leading, 16)
        }
    }

    // MARK: - Playing

    private var playingView: some View {
        ZStack(alignment: .topLeading) {
            InfiniteGameView(
                game: currentGame,
                onWin:  handleWin,
                onLose: handleLose
            )
            .id(sessionID)

            Button { state = .home } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.top, 52)
            .padding(.leading, 16)
        }
    }

    private func startPlaying(excluding: MiniGame?) {
        excludedGame = excluding
        gamesPlayed  = 0
        currentGame  = randomGame(excluding: excluding)
        sessionID    = UUID()
        state        = .playing
    }

    private func handleWin() {
        gamesPlayed += 1
        currentGame  = randomGame(excluding: excludedGame)
        sessionID    = UUID()
    }

    private func handleLose() {
        state = .dead(gamesCompleted: gamesPlayed, lostOn: currentGame)
    }

    private func randomGame(excluding ex: MiniGame?) -> MiniGame {
        var pool = MiniGame.allCases
        if let ex { pool.removeAll { $0 == ex } }
        return pool.randomElement() ?? .platformer
    }

    // MARK: - Death screen (blue)

    private func deathView(gamesCompleted: Int, lostOn: MiniGame) -> some View {
        ZStack {
            Color(red: 0.04, green: 0.18, blue: 0.46).ignoresSafeArea()
            VStack(spacing: 22) {
                Text("Game Over")
                    .font(.system(size: 54, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("You completed \(gamesCompleted) \(gamesCompleted == 1 ? "game" : "games")")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(Color(white: 0.90))
                Text("Lost on: \(lostOn.displayName)")
                    .font(.system(size: 18))
                    .foregroundColor(Color(white: 0.70))

                HStack(spacing: 20) {
                    Button {
                        startPlaying(excluding: lostOn)
                    } label: {
                        Text("Play Again")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 170, height: 52)
                            .background(Color.yellow)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    Button {
                        state = .home
                    } label: {
                        Text("Home")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 130, height: 52)
                            .background(Color(white: 1, opacity: 0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Per-game view router
// ─────────────────────────────────────────────────────────────────────────────

struct InfiniteGameView: View {
    let game:   MiniGame
    let onWin:  () -> Void
    let onLose: () -> Void

    var body: some View {
        switch game {
        case .platformer: InfPlatView(onWin: onWin, onLose: onLose)
        case .jigsaw:     InfJigView(onWin: onWin)
        case .rocket:     InfRktView(onWin: onWin, onLose: onLose)
        case .pingPong:   InfPingView(onWin: onWin, onLose: onLose)
        }
    }
}

// MARK: - Platformer (1 death = lose)

struct InfPlatView: View {
    let onWin: () -> Void
    let onLose: () -> Void

    @SwiftUI.State private var scene: PlatformerScene = {
        let s = PlatformerScene(size: CGSize(width: 1200, height: 700))
        s.scaleMode = .resizeFill
        return s
    }()
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            SpriteView(scene: scene)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
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
                        if press.key == .leftArrow || press.key == .rightArrow { scene.stopHorizontal() }
                    default: break
                    }
                    return .handled
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            focused = true
            scene.onWin  = onWin
            scene.onLose = onLose
            scene.marathonLives = 1
        }
        .overlay(alignment: .bottom) { GameControls(scene: scene).padding(.bottom, 28) }
    }
}

// MARK: - Jigsaw

struct InfJigView: View {
    let onWin: () -> Void

    @SwiftUI.State private var scene: JigsawPuzzleScene = {
        let s = JigsawPuzzleScene(size: CGSize(width: 1200, height: 700))
        s.scaleMode = .resizeFill
        return s
    }()

    var body: some View {
        SpriteView(scene: scene)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .onAppear { scene.onWin = onWin }
    }
}

// MARK: - Rocket

struct InfRktView: View {
    let onWin:  () -> Void
    let onLose: () -> Void

    @SwiftUI.State private var scene: RocketScene = {
        let s = RocketScene(size: CGSize(width: 1200, height: 700))
        s.scaleMode = .resizeFill
        return s
    }()
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            SpriteView(scene: scene)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            focused = true
            scene.onWin  = onWin
            scene.onLose = onLose
        }
    }
}

// MARK: - Ping Pong

struct InfPingView: View {
    let onWin:  () -> Void
    let onLose: () -> Void

    @SwiftUI.State private var scene: PingPongScene = {
        let s = PingPongScene(size: CGSize(width: 1200, height: 700))
        s.scaleMode = .resizeFill
        return s
    }()
    @FocusState private var focused: Bool

    var body: some View {
        SpriteView(scene: scene)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .overlay {
                Color.clear
                    .contentShape(Rectangle()).focusable().focused($focused)
                    .allowsHitTesting(false)
                    .onKeyPress(keys: [.leftArrow, .rightArrow], phases: .all) { press in
                        let key = press.key == .leftArrow ? "left" : "right"
                        if press.phase == .down { scene.keyDown(key: key) }
                        else if press.phase == .up { scene.keyUp(key: key) }
                        return .handled
                    }
            }
            .onAppear {
                focused = true
                scene.onWin  = onWin
                scene.onLose = onLose
            }
    }
}

