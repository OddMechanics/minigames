import SwiftUI
import SpriteKit

// ─────────────────────────────────────────────────────────────────────────────
// GolfView — SwiftUI wrapper for the professional-quality GolfScene.
//
// Usage:
//   GolfView(mapMode: .short)
//   GolfView(mapMode: .long, onWin: { ... }, onLose: { ... })
//
// All game input (drag-to-aim, release-to-shoot) is handled inside GolfScene
// via SpriteKit touch events; this file is purely the SwiftUI scaffold.
// ─────────────────────────────────────────────────────────────────────────────

struct GolfView: View {

    // MARK: - Configuration
    var mapMode: GolfMapMode   = .short
    var onWin:   (() -> Void)? = nil
    var onLose:  (() -> Void)? = nil

    // MARK: - Scene
    // Stored as a reference so the same instance survives SwiftUI redraws.
    private let scene: GolfScene

    // MARK: - Init
    init(mapMode: GolfMapMode   = .short,
         onWin:   (() -> Void)? = nil,
         onLose:  (() -> Void)? = nil) {
        self.mapMode = mapMode
        self.onWin   = onWin
        self.onLose  = onLose

        let s        = GolfScene(size: CGSize(width: 1200, height: 700))
        s.scaleMode  = .resizeFill
        s.mapMode    = mapMode
        s.onWin      = onWin
        s.onLose     = onLose
        self.scene   = s
    }

    // MARK: - Body
    var body: some View {
        GeometryReader { geo in
            SpriteView(scene: scene, options: [.allowsTransparency])
                .frame(width: geo.size.width, height: geo.size.height)
                .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .statusBar(hidden: true)
    }
}

// MARK: - Preview
#Preview {
    GolfView(mapMode: .short)
}
