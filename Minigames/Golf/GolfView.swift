import SwiftUI
import SpriteKit

// ─────────────────────────────────────────────────────────────────────────────
// GolfView — SwiftUI wrapper for GolfScene.
//
// All game input is handled inside GolfScene via SpriteKit touch events —
// drag away from the ball to aim, release to shoot.
// ─────────────────────────────────────────────────────────────────────────────

struct GolfView: View {

    // MARK: - Configuration
    var mapMode: GolfMapMode   = .short
    var onWin:   (() -> Void)? = nil
    var onLose:  (() -> Void)? = nil

    // MARK: - Scene
    // Stored as a reference type inside the struct; mapMode / callbacks are
    // injected in init() so they are available before didMove(to:) fires.
    private let scene: GolfScene

    // MARK: - Init
    init(mapMode: GolfMapMode   = .short,
         onWin:   (() -> Void)? = nil,
         onLose:  (() -> Void)? = nil) {
        self.mapMode = mapMode
        self.onWin   = onWin
        self.onLose  = onLose

        let s = GolfScene(size: CGSize(width: 1200, height: 700))
        s.scaleMode = .resizeFill
        s.mapMode   = mapMode
        s.onWin     = onWin
        s.onLose    = onLose
        self.scene  = s
    }

    // MARK: - Body
    var body: some View {
        GeometryReader { geo in
            SpriteView(scene: scene)
                .frame(width: geo.size.width, height: geo.size.height)
                .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Preview
#Preview {
    GolfView(mapMode: .short)
}
