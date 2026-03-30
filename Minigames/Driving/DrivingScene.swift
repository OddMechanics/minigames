import SpriteKit
import GameplayKit

// MARK: - Map Mode

enum DrivingMapMode {
    case short   // 3 ramps, 1 gap, ~4000 pts
    case long    // themed sections, big air moment, ~11000 pts
}

// MARK: - DrivingScene

class DrivingScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Collision Categories
    struct Cat {
        static let car:        UInt32 = 1 << 0
        static let ground:     UInt32 = 1 << 1
        static let gap:        UInt32 = 1 << 2
        static let finish:     UInt32 = 1 << 3
        static let wheel:      UInt32 = 1 << 4
        static let checkpoint: UInt32 = 1 << 5
    }

    // MARK: - Public Config
    var mapMode: DrivingMapMode = .short
    var onWin:  (() -> Void)?
    var onLose: (() -> Void)?

    // MARK: - Physics/Gameplay Constants
    private let maxSpeedH:      CGFloat = 1100
    private let gasForce:       CGFloat = 3500
    private let wheelRadius:    CGFloat = 18
    private let carWidth:       CGFloat = 90
    private let carHeight:      CGFloat = 34
    private let groundY:        CGFloat = 80
    private let leanTorque:     CGFloat = 420

    // MARK: - Input State
    private var isGasHeld       = false
    private var isBrakeHeld     = false
    private var isLeanLeft      = false
    private var isLeanRight     = false

    // MARK: - Gameplay State
    private var hasBuilt            = false
    private var gasRampT:           CGFloat = 0
    private var lastUpdateTime:     TimeInterval = 0
    private var isDead              = false
    private var hasWon              = false
    private var isOverlayVisible    = false

    // Stuck detection
    private var slowTimer:          TimeInterval = 0
    private let stuckThreshold:     TimeInterval = 3.5

    // Airborne tracking
    private var wasAirborne         = false
    private var wheelContactCount   = 0
    private var maxAirborneY:       CGFloat = 0
    private var airborneStartY:     CGFloat = 0

    // Timer
    private var raceStartTime:      TimeInterval = 0
    private var raceElapsed:        TimeInterval = 0
    private var timerRunning        = false
    private var bestTime:           TimeInterval = 0

    // Checkpoint
    private var checkpointX:        CGFloat = 0
    private var hasPassedCheckpoint = false

    // Dust
    private var dustTimer:          CGFloat = 0

    // MARK: - Nodes
    private var carPhysics:     SKNode!
    private var carBody:        SKShapeNode!
    private var wheelFront:     SKShapeNode!
    private var wheelRear:      SKShapeNode!
    private var cameraNode:     SKCameraNode!
    private var overlayBg:      SKSpriteNode?

    // HUD nodes
    private var speedLabel:     SKLabelNode!
    private var timerLabel:     SKLabelNode!
    private var bestTimeLabel:  SKLabelNode!
    private var airLabel:       SKLabelNode!
    private var progressBarBg:  SKShapeNode!
    private var progressBarFill: SKSpriteNode!
    private var gasBarBgNode:   SKShapeNode!
    private var gasBarFillNode: SKSpriteNode!

    // Parallax layers (world-space anchors, moved relative to camera)
    private var parallaxMountains:  [SKShapeNode] = []
    private var parallaxHills:      [SKShapeNode] = []
    private var parallaxClouds:     [SKNode] = []

    // Joints
    private var jointFront:     SKPhysicsJointPin?
    private var jointRear:      SKPhysicsJointPin?

    // MARK: - Terrain
    private struct TerrainPoint { let x: CGFloat; let y: CGFloat }
    private var terrainPoints:  [TerrainPoint] = []
    private var gapRanges:      [(CGFloat, CGFloat)] = []
    private var mapWidth:       CGFloat = 0
    private var spawnX:         CGFloat = 150

    // MARK: - didMove

    override func didMove(to view: SKView) {
        isPaused = false
        guard !hasBuilt else { return }
        hasBuilt = true

        physicsWorld.gravity         = CGVector(dx: 0, dy: -900)
        physicsWorld.contactDelegate = self
        physicsWorld.speed           = 1.0

        // Load best time from UserDefaults
        let key = "drivingBestTime_\(mapMode == .short ? "short" : "long")"
        let stored = UserDefaults.standard.double(forKey: key)
        bestTime = stored > 0 ? stored : 0

        setupSkyGradient()
        setupCamera()
        setupParallaxLayers()
        buildTerrain()
        setupCar()
        setupHUD()
    }

    override func willMove(from view: SKView) {
        isPaused = true
    }

    override func didChangeSize(_ oldSize: CGSize) {
        layoutHUD()
    }

    // MARK: - Sky Gradient (3 layered rects, no seam)

    private func setupSkyGradient() {
        // Deep blue top
        let skyTop = SKSpriteNode(
            color: SKColor(red: 0.04, green: 0.07, blue: 0.22, alpha: 1),
            size: CGSize(width: 25000, height: 1200))
        skyTop.position  = CGPoint(x: 5000, y: 1100)
        skyTop.zPosition = -30
        addChild(skyTop)

        // Mid blue
        let skyMid = SKSpriteNode(
            color: SKColor(red: 0.14, green: 0.32, blue: 0.62, alpha: 1),
            size: CGSize(width: 25000, height: 800))
        skyMid.position  = CGPoint(x: 5000, y: 550)
        skyMid.zPosition = -29
        addChild(skyMid)

        // Horizon — lighter blue
        let skyHorizon = SKSpriteNode(
            color: SKColor(red: 0.35, green: 0.58, blue: 0.82, alpha: 1),
            size: CGSize(width: 25000, height: 400))
        skyHorizon.position  = CGPoint(x: 5000, y: 180)
        skyHorizon.zPosition = -28
        addChild(skyHorizon)
    }

    // MARK: - Camera

    private func setupCamera() {
        cameraNode          = SKCameraNode()
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(cameraNode)
        camera = cameraNode
    }

    // MARK: - Parallax Layers

    private func setupParallaxLayers() {
        // Far mountains (scroll at 0.15x) — dark silhouettes
        let mountainColors: [SKColor] = [
            SKColor(red: 0.18, green: 0.22, blue: 0.35, alpha: 1),
            SKColor(red: 0.22, green: 0.27, blue: 0.42, alpha: 1)
        ]
        let mountainPeaks: [(CGFloat, CGFloat, CGFloat)] = [
            // x,  peakY, width
            (300,  420,  260), (600,  380,  220), (950,  440,  280),
            (1300, 400,  250), (1700, 460,  300), (2100, 390,  240),
            (2500, 430,  270), (3000, 410,  260), (3500, 450,  290),
            (4000, 400,  250), (4600, 440,  280), (5200, 420,  265),
            (5800, 390,  240), (6400, 460,  300), (7000, 430,  275),
            (7700, 400,  255), (8400, 450,  285), (9100, 420,  270)
        ]
        for (mx, my, mw) in mountainPeaks {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: mx - mw / 2, y: 130))
            path.addLine(to: CGPoint(x: mx, y: my))
            path.addLine(to: CGPoint(x: mx + mw / 2, y: 130))
            path.closeSubpath()
            let shape = SKShapeNode(path: path)
            shape.fillColor   = mountainColors[Int(mx) % 2]
            shape.strokeColor = .clear
            shape.zPosition   = -22
            addChild(shape)
            parallaxMountains.append(shape)
        }

        // Mid hills (scroll at 0.35x) — green-ish hills
        let hillData: [(CGFloat, CGFloat, CGFloat)] = [
            (150,  200, 180), (420,  180, 160), (700,  210, 190),
            (1000, 195, 175), (1350, 215, 200), (1750, 185, 165),
            (2150, 205, 185), (2600, 195, 178), (3100, 210, 192),
            (3650, 200, 182), (4200, 215, 195), (4800, 190, 172),
            (5400, 205, 188), (6000, 195, 175), (6700, 212, 194),
            (7400, 200, 180), (8100, 208, 190), (8900, 196, 176)
        ]
        for (hx, hy, hr) in hillData {
            let hill = SKShapeNode(circleOfRadius: hr)
            hill.fillColor   = SKColor(red: 0.20, green: 0.38, blue: 0.22, alpha: 1)
            hill.strokeColor = .clear
            hill.position    = CGPoint(x: hx, y: hy - hr + 60)
            hill.zPosition   = -18
            addChild(hill)
            parallaxHills.append(hill)
        }

        // Near clouds (scroll at 0.6x)
        let cloudPositions: [(CGFloat, CGFloat)] = [
            (200, 500), (600, 480), (1100, 520), (1700, 495),
            (2400, 510), (3200, 488), (4100, 515), (5000, 500),
            (5900, 490), (6800, 510), (7700, 498), (8700, 508)
        ]
        for (cx, cy) in cloudPositions {
            let cloud = makeCloud(x: cx, y: cy)
            parallaxClouds.append(cloud)
        }
    }

    private func makeCloud(x: CGFloat, y: CGFloat) -> SKNode {
        let cloud = SKNode()
        cloud.position  = CGPoint(x: x, y: y)
        cloud.zPosition = -12
        let offsets: [CGPoint] = [
            .zero,
            CGPoint(x: 28, y: 8), CGPoint(x: -28, y: 6),
            CGPoint(x: 12, y: 18), CGPoint(x: -12, y: 14),
            CGPoint(x: 48, y: 2), CGPoint(x: -48, y: 3)
        ]
        for off in offsets {
            let r    = CGFloat.random(in: 16...30)
            let puff = SKShapeNode(circleOfRadius: r)
            puff.fillColor   = SKColor(white: 1.0, alpha: 0.82)
            puff.strokeColor = .clear
            puff.position    = off
            cloud.addChild(puff)
        }
        addChild(cloud)
        return cloud
    }

    // MARK: - Terrain Generation

    private func buildTerrain() {
        let segments = mapMode == .short ? shortMapSegments() : longMapSegments()
        terrainPoints = segments
        mapWidth = (terrainPoints.last?.x ?? 2000) + 500

        detectGaps()
        drawTerrainVisual()
        buildTerrainPhysics()
        buildGapKillZones()
        buildGapVisuals()
        placeCheckpoints()

        if let last = terrainPoints.last {
            placeFinishLine(x: last.x - 80, y: last.y)
        }
    }

    // MARK: Short map — 3 ramps, 1 gap, downhill speed section, valley
    private func shortMapSegments() -> [TerrainPoint] {
        var pts: [TerrainPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = groundY

        // START: flat launch pad
        pts += flat(x: x, y: y, len: 280);   advance(&x, &y, pts)

        // Ramp 1 — gentle warm-up
        pts += ramp(x: x, y: y, angle: 18, len: 170); advance(&x, &y, pts)
        pts += flat(x: x, y: y, len: 100);   advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: -16, len: 155); x = pts.last!.x; y = groundY

        // Valley dip — speed builder
        pts += flat(x: x, y: y, len: 80);    advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: -14, len: 130); advance(&x, &y, pts)  // downhill
        let valleyY = pts.last!.y
        pts += flat(x: pts.last!.x, y: valleyY, len: 120); advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: 14, len: 130);  x = pts.last!.x; y = groundY  // back up

        // GAP 1 — 155 pts wide
        pts += flat(x: x, y: y, len: 160);   advance(&x, &y, pts)
        x += 155
        pts += flat(x: x, y: groundY, len: 170); advance(&x, &y, pts)

        // Downhill section → builds speed for big ramp
        pts += ramp(x: x, y: y, angle: -10, len: 200); advance(&x, &y, pts)
        let fastY = pts.last!.y
        pts += flat(x: pts.last!.x, y: fastY, len: 100); advance(&x, &y, pts)

        // Ramp 2 — medium
        pts += ramp(x: x, y: y, angle: 30, len: 185); advance(&x, &y, pts)
        pts += flat(x: x, y: y, len: 95);    advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: -26, len: 165); x = pts.last!.x; y = groundY
        pts += flat(x: x, y: y, len: 180);   advance(&x, &y, pts)

        // Ramp 3 — BIG AIR moment
        pts += ramp(x: x, y: y, angle: 40, len: 210); advance(&x, &y, pts)
        pts += flat(x: x, y: y, len: 100);   advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: -34, len: 185); x = pts.last!.x; y = groundY

        // FINISH stretch
        pts += flat(x: x, y: y, len: 420)
        return pts
    }

    // MARK: Long map — themed sections: rocky start, uphill climb, dramatic peak, downhill rush, gap crossing, finish
    private func longMapSegments() -> [TerrainPoint] {
        var pts: [TerrainPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = groundY

        // === SECTION 1: Rocky Start ===
        pts += flat(x: x, y: y, len: 250);   advance(&x, &y, pts)

        // Small ramp 1 — learning curve
        pts += ramp(x: x, y: y, angle: 14, len: 145); advance(&x, &y, pts)
        pts += flat(x: x, y: y, len: 80);    advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: -12, len: 130); x = pts.last!.x; y = groundY
        pts += flat(x: x, y: y, len: 150);   advance(&x, &y, pts)

        // Small ramp 2 — building confidence
        pts += ramp(x: x, y: y, angle: 20, len: 160); advance(&x, &y, pts)
        pts += flat(x: x, y: y, len: 90);    advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: -17, len: 148); x = pts.last!.x; y = groundY

        // === SECTION 2: Uphill Climb ===
        // Gradual rise over 600 units
        pts += flat(x: x, y: y, len: 120);   advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: 8, len: 300); advance(&x, &y, pts)  // gentle uphill
        let hillTopY = pts.last!.y
        pts += flat(x: pts.last!.x, y: hillTopY, len: 100); advance(&x, &y, pts)

        // GAP 1 — First gap at altitude
        pts += flat(x: x, y: y, len: 140);   advance(&x, &y, pts)
        x += 175
        pts += flat(x: x, y: hillTopY, len: 130); advance(&x, &y, pts)

        // Continue uphill
        pts += ramp(x: x, y: y, angle: 10, len: 250); advance(&x, &y, pts)

        // === SECTION 3: Dramatic Peak — BIG AIR MOMENT ===
        let peakY = pts.last!.y
        // Wind-up flat
        pts += flat(x: pts.last!.x, y: peakY, len: 80); advance(&x, &y, pts)

        // MEGA RAMP — the centerpiece
        pts += ramp(x: x, y: y, angle: 42, len: 230); advance(&x, &y, pts)
        pts += flat(x: x, y: y, len: 80);    advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: -38, len: 210); advance(&x, &y, pts)
        let afterPeakY = pts.last!.y

        // === SECTION 4: Downhill Rush ===
        pts += flat(x: pts.last!.x, y: afterPeakY, len: 100); advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: -12, len: 350); advance(&x, &y, pts)  // big downhill
        let rushY = pts.last!.y
        pts += flat(x: pts.last!.x, y: rushY, len: 120); advance(&x, &y, pts)

        // Medium ramp mid-downhill
        pts += ramp(x: x, y: y, angle: 28, len: 185); advance(&x, &y, pts)
        pts += flat(x: x, y: y, len: 80);    advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: -24, len: 170); x = pts.last!.x; y = pts.last!.y

        pts += flat(x: x, y: y, len: 100);   advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: -8, len: 200); advance(&x, &y, pts)  // continuing down
        x = pts.last!.x; y = max(pts.last!.y, groundY)

        // === SECTION 5: Valley ===
        let valleyFloorY = y
        pts += flat(x: x, y: valleyFloorY, len: 180); advance(&x, &y, pts)

        // Ramp out of valley
        pts += ramp(x: x, y: y, angle: 22, len: 175); advance(&x, &y, pts)
        pts += flat(x: x, y: y, len: 70);    advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: -19, len: 160); x = pts.last!.x; y = groundY

        // === SECTION 6: Gap Crossing ===
        pts += flat(x: x, y: y, len: 200);   advance(&x, &y, pts)

        // GAP 2 — Dramatic chasm
        x += 220
        pts += flat(x: x, y: groundY, len: 160); advance(&x, &y, pts)

        // Large ramp after gap
        pts += ramp(x: x, y: y, angle: 36, len: 205); advance(&x, &y, pts)
        pts += flat(x: x, y: y, len: 90);    advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: -31, len: 190); x = pts.last!.x; y = groundY
        pts += flat(x: x, y: y, len: 180);   advance(&x, &y, pts)

        // Final ramp before finish
        pts += ramp(x: x, y: y, angle: 38, len: 215); advance(&x, &y, pts)
        pts += flat(x: x, y: y, len: 100);   advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: -33, len: 195); x = pts.last!.x; y = groundY

        // === SECTION 7: FINISH ===
        pts += flat(x: x, y: y, len: 550)
        return pts
    }

    // MARK: Segment helpers

    private func flat(x: CGFloat, y: CGFloat, len: CGFloat) -> [TerrainPoint] {
        [TerrainPoint(x: x, y: y), TerrainPoint(x: x + len, y: y)]
    }

    private func ramp(x: CGFloat, y: CGFloat, angle: CGFloat, len: CGFloat) -> [TerrainPoint] {
        let rad = angle * .pi / 180
        return [TerrainPoint(x: x, y: y),
                TerrainPoint(x: x + cos(rad) * len, y: y + sin(rad) * len)]
    }

    private func advance(_ x: inout CGFloat, _ y: inout CGFloat, _ pts: [TerrainPoint]) {
        x = pts.last!.x; y = pts.last!.y
    }

    // MARK: - Gap Detection

    private func detectGaps() {
        gapRanges.removeAll()
        let pts = deduped(terrainPoints)
        for i in 1..<pts.count {
            let dx = pts[i].x - pts[i-1].x
            let dy = abs(pts[i].y - pts[i-1].y)
            if dx > 80 && dy < 5 {
                gapRanges.append((pts[i-1].x, pts[i].x))
            }
        }
    }

    // MARK: - Terrain Visual

    private func drawTerrainVisual() {
        guard terrainPoints.count >= 2 else { return }
        let pts = deduped(terrainPoints)

        // Brown dirt base layer
        let dirtPath = CGMutablePath()
        dirtPath.move(to: CGPoint(x: pts[0].x, y: pts[0].y - 10))
        for p in pts.dropFirst() { dirtPath.addLine(to: CGPoint(x: p.x, y: p.y - 10)) }
        dirtPath.addLine(to: CGPoint(x: pts.last!.x, y: -800))
        dirtPath.addLine(to: CGPoint(x: pts[0].x, y: -800))
        dirtPath.closeSubpath()

        let dirt = SKShapeNode(path: dirtPath)
        dirt.fillColor   = SKColor(red: 0.48, green: 0.30, blue: 0.14, alpha: 1)
        dirt.strokeColor = .clear
        dirt.zPosition   = 0
        addChild(dirt)

        // Green terrain surface
        let path = CGMutablePath()
        path.move(to: CGPoint(x: pts[0].x, y: pts[0].y))
        for p in pts.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: p.y)) }
        path.addLine(to: CGPoint(x: pts.last!.x, y: -800))
        path.addLine(to: CGPoint(x: pts[0].x, y: -800))
        path.closeSubpath()

        let grass = SKShapeNode(path: path)
        grass.fillColor   = SKColor(red: 0.20, green: 0.50, blue: 0.14, alpha: 1)
        grass.strokeColor = SKColor(red: 0.12, green: 0.38, blue: 0.08, alpha: 1)
        grass.lineWidth   = 4
        grass.zPosition   = 1
        addChild(grass)
    }

    // MARK: - Gap Visuals (pulsing red glow, no text)

    private func buildGapVisuals() {
        for (gx0, gx1) in gapRanges {
            let gapW  = gx1 - gx0
            let pitH: CGFloat = 900

            // Dark void pit
            let pitPath = CGMutablePath()
            pitPath.addRect(CGRect(x: gx0, y: groundY - pitH, width: gapW, height: pitH))
            let pit = SKShapeNode(path: pitPath)
            pit.fillColor   = SKColor(red: 0.06, green: 0.0, blue: 0.0, alpha: 1)
            pit.strokeColor = .clear
            pit.zPosition   = 10
            addChild(pit)

            // Pulsing red glow at rim — no text
            let rimPath = CGMutablePath()
            rimPath.addRect(CGRect(x: gx0 - 8, y: groundY - 55, width: gapW + 16, height: 55))
            let glow = SKShapeNode(path: rimPath)
            glow.fillColor   = SKColor(red: 0.95, green: 0.0, blue: 0.0, alpha: 0.35)
            glow.strokeColor = .clear
            glow.zPosition   = 11
            addChild(glow)

            // Pulse animation
            let pulse = SKAction.sequence([
                SKAction.fadeAlpha(to: 0.08, duration: 0.6),
                SKAction.fadeAlpha(to: 0.80, duration: 0.6)
            ])
            glow.run(SKAction.repeatForever(pulse))

            // Outer glow strips on edges
            for edgeX in [gx0 - 4, gx1] {
                let edgePath = CGMutablePath()
                edgePath.addRect(CGRect(x: edgeX, y: groundY - 200, width: 12, height: 200))
                let edge = SKShapeNode(path: edgePath)
                edge.fillColor   = SKColor(red: 1.0, green: 0.15, blue: 0.0, alpha: 0.55)
                edge.strokeColor = .clear
                edge.zPosition   = 12
                addChild(edge)
                edge.run(SKAction.repeatForever(pulse.reversed()))
            }
        }
    }

    // MARK: - Terrain Physics

    private func buildTerrainPhysics() {
        let pts = deduped(terrainPoints)
        var chainStart = 0
        for i in 1..<pts.count {
            let dx = pts[i].x - pts[i-1].x
            let dy = abs(pts[i].y - pts[i-1].y)
            if dx > 80 && dy < 5 {
                emitGroundChain(Array(pts[chainStart..<i]))
                chainStart = i
            }
        }
        emitGroundChain(Array(pts[chainStart...]))
    }

    private func emitGroundChain(_ points: [TerrainPoint]) {
        guard points.count >= 2 else { return }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: points[0].x, y: points[0].y))
        for p in points.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: p.y)) }

        let node = SKNode()
        node.zPosition = 2
        let body = SKPhysicsBody(edgeChainFrom: path)
        body.isDynamic          = false
        body.friction           = 0.90
        body.restitution        = 0.03
        body.categoryBitMask    = Cat.ground
        body.contactTestBitMask = Cat.car | Cat.wheel
        body.collisionBitMask   = Cat.car | Cat.wheel
        node.physicsBody = body
        addChild(node)
    }

    // MARK: - Gap Kill Zones

    private func buildGapKillZones() {
        for (gx0, gx1) in gapRanges {
            let gapW  = gx1 - gx0
            let midX  = (gx0 + gx1) / 2
            let killW = gapW + 300
            let killH: CGFloat = 800
            let killY = groundY - killH / 2 - 20

            let killNode = SKNode()
            killNode.position = CGPoint(x: midX, y: killY)
            let body = SKPhysicsBody(rectangleOf: CGSize(width: killW, height: killH))
            body.isDynamic          = false
            body.categoryBitMask    = Cat.gap
            body.contactTestBitMask = Cat.car | Cat.wheel
            body.collisionBitMask   = 0
            killNode.physicsBody = body
            addChild(killNode)
        }
    }

    // MARK: - Checkpoints

    private func placeCheckpoints() {
        // For short map: checkpoint after ramp 2 (roughly 60% through)
        // For long map: checkpoint after the peak mega-ramp (roughly 50%)
        // We detect the position by scanning terrainPoints
        let pts = deduped(terrainPoints)
        let targetFraction: CGFloat = mapMode == .short ? 0.55 : 0.50

        if let last = pts.last {
            checkpointX = last.x * targetFraction
        }

        let cpY = interpolateTerrainY(atX: checkpointX)
        let cpNode = SKNode()
        cpNode.position = CGPoint(x: checkpointX, y: cpY + 40)
        cpNode.name = "checkpoint"
        let cpBody = SKPhysicsBody(rectangleOf: CGSize(width: 20, height: 80))
        cpBody.isDynamic          = false
        cpBody.categoryBitMask    = Cat.checkpoint
        cpBody.contactTestBitMask = Cat.car
        cpBody.collisionBitMask   = 0
        cpNode.physicsBody = cpBody
        addChild(cpNode)

        // Visual: cyan checkpoint flag
        let pole = SKShapeNode(rectOf: CGSize(width: 5, height: 90))
        pole.fillColor   = SKColor(red: 0.0, green: 0.85, blue: 0.95, alpha: 1)
        pole.strokeColor = .clear
        pole.position    = CGPoint(x: checkpointX, y: cpY + 45)
        pole.zPosition   = 10
        addChild(pole)

        let flagPath = CGMutablePath()
        flagPath.addRect(CGRect(x: 0, y: 0, width: 44, height: 26))
        let flagNode = SKShapeNode(path: flagPath)
        flagNode.fillColor   = SKColor(red: 0.0, green: 0.85, blue: 0.95, alpha: 0.85)
        flagNode.strokeColor = .clear
        flagNode.position    = CGPoint(x: checkpointX + 2, y: cpY + 76)
        flagNode.zPosition   = 10
        addChild(flagNode)

        let cpLbl = SKLabelNode(text: "CP")
        cpLbl.fontName  = "AvenirNext-Bold"
        cpLbl.fontSize  = 14
        cpLbl.fontColor = .white
        cpLbl.position  = CGPoint(x: checkpointX + 24, y: cpY + 82)
        cpLbl.zPosition = 11
        addChild(cpLbl)
    }

    // MARK: - Finish Line

    private func placeFinishLine(x: CGFloat, y: CGFloat) {
        // Pole
        let pole = SKShapeNode(rectOf: CGSize(width: 8, height: 130))
        pole.fillColor   = SKColor(white: 0.92, alpha: 1)
        pole.strokeColor = SKColor(white: 0.2, alpha: 1)
        pole.lineWidth   = 1
        pole.position    = CGPoint(x: x, y: y + 65)
        pole.zPosition   = 10
        addChild(pole)

        // Checkered flag
        let flagSize = CGSize(width: 80, height: 50)
        let flag = SKNode()
        flag.position  = CGPoint(x: x + 4, y: y + 105)
        flag.zPosition = 10
        let sqSz: CGFloat = 10
        for row in 0..<Int(flagSize.height / sqSz) {
            for col in 0..<Int(flagSize.width / sqSz) {
                let sq = SKSpriteNode(
                    color: (row + col) % 2 == 0 ? .black : .white,
                    size: CGSize(width: sqSz, height: sqSz))
                sq.position = CGPoint(
                    x: CGFloat(col) * sqSz + sqSz / 2,
                    y: CGFloat(row) * sqSz + sqSz / 2)
                flag.addChild(sq)
            }
        }
        addChild(flag)

        // Wave animation on flag
        let waveLeft  = SKAction.rotate(byAngle: 0.12, duration: 0.5)
        let waveRight = SKAction.rotate(byAngle: -0.12, duration: 0.5)
        flag.run(SKAction.repeatForever(SKAction.sequence([waveLeft, waveRight])))

        // Trigger zone — car body only (fix: not wheel)
        let trigger = SKNode()
        trigger.position = CGPoint(x: x, y: y + 50)
        trigger.zPosition = 5
        let trigBody = SKPhysicsBody(rectangleOf: CGSize(width: 30, height: 100))
        trigBody.isDynamic          = false
        trigBody.categoryBitMask    = Cat.finish
        trigBody.contactTestBitMask = Cat.car       // car body only, not wheels
        trigBody.collisionBitMask   = 0
        trigger.physicsBody = trigBody
        addChild(trigger)
    }

    // MARK: - Car Setup

    private func setupCar() {
        let startY = interpolateTerrainY(atX: spawnX) + wheelRadius + carHeight / 2 + 4

        carPhysics          = SKNode()
        carPhysics.position = CGPoint(x: spawnX, y: startY)
        carPhysics.zPosition = 10

        let carPB              = SKPhysicsBody(rectangleOf: CGSize(width: carWidth - 8, height: carHeight))
        carPB.mass             = 3.0
        carPB.restitution      = 0.05
        carPB.friction         = 0.7
        carPB.linearDamping    = 0.2
        carPB.angularDamping   = 0.5
        carPB.allowsRotation   = true
        carPB.categoryBitMask    = Cat.car
        carPB.contactTestBitMask = Cat.ground | Cat.gap | Cat.finish | Cat.checkpoint
        carPB.collisionBitMask   = Cat.ground
        carPhysics.physicsBody   = carPB
        addChild(carPhysics)

        carBody = buildCarVisual()
        carPhysics.addChild(carBody)

        let frontWheelX = spawnX + carWidth * 0.32
        let rearWheelX  = spawnX - carWidth * 0.32
        let wheelY      = startY - carHeight / 2 - wheelRadius + 4

        wheelFront = buildWheel()
        wheelFront.position  = CGPoint(x: frontWheelX, y: wheelY)
        wheelFront.zPosition = 9
        addChild(wheelFront)

        wheelRear = buildWheel()
        wheelRear.position   = CGPoint(x: rearWheelX, y: wheelY)
        wheelRear.zPosition  = 9
        addChild(wheelRear)

        for wNode in [wheelFront, wheelRear] {
            let wPB              = SKPhysicsBody(circleOfRadius: wheelRadius)
            wPB.mass             = 0.3          // reduced from 0.8
            wPB.restitution      = 0.25
            wPB.friction         = 0.95
            wPB.linearDamping    = 0.1
            wPB.angularDamping   = 0.15
            wPB.allowsRotation   = true
            wPB.categoryBitMask    = Cat.wheel
            wPB.contactTestBitMask = Cat.ground | Cat.gap
            wPB.collisionBitMask   = Cat.ground
            wNode?.physicsBody = wPB
        }

        attachWheelJoints(
            frontAnchor: CGPoint(x: frontWheelX, y: wheelY),
            rearAnchor:  CGPoint(x: rearWheelX,  y: wheelY))
    }

    private func attachWheelJoints(frontAnchor: CGPoint, rearAnchor: CGPoint) {
        let jf = SKPhysicsJointPin.joint(
            withBodyA: carPhysics.physicsBody!,
            bodyB:     wheelFront.physicsBody!,
            anchor:    frontAnchor)
        jf.shouldEnableLimits = false
        jf.frictionTorque     = 8.0             // added friction torque
        jointFront = jf
        physicsWorld.add(jf)

        let jr = SKPhysicsJointPin.joint(
            withBodyA: carPhysics.physicsBody!,
            bodyB:     wheelRear.physicsBody!,
            anchor:    rearAnchor)
        jr.shouldEnableLimits = false
        jr.frictionTorque     = 8.0             // added friction torque
        jointRear = jr
        physicsWorld.add(jr)
    }

    // MARK: - Car Visual

    private func buildCarVisual() -> SKShapeNode {
        let body = SKShapeNode(rectOf: CGSize(width: carWidth, height: carHeight), cornerRadius: 6)
        body.fillColor   = SKColor(red: 0.88, green: 0.88, blue: 0.88, alpha: 1)
        body.strokeColor = SKColor(red: 0.50, green: 0.50, blue: 0.55, alpha: 1)
        body.lineWidth   = 2
        body.zPosition   = 0

        let roof = SKShapeNode(rectOf: CGSize(width: carWidth * 0.52, height: carHeight * 0.72), cornerRadius: 5)
        roof.fillColor   = SKColor(red: 0.85, green: 0.10, blue: 0.10, alpha: 1)
        roof.strokeColor = SKColor(red: 0.50, green: 0.04, blue: 0.04, alpha: 1)
        roof.lineWidth   = 1.5
        roof.position    = CGPoint(x: -4, y: carHeight * 0.56)
        roof.zPosition   = 1
        body.addChild(roof)

        let windshield = SKShapeNode(rectOf: CGSize(width: carWidth * 0.18, height: carHeight * 0.50), cornerRadius: 2)
        windshield.fillColor   = SKColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 0.92)
        windshield.strokeColor = SKColor(white: 0.4, alpha: 0.5)
        windshield.lineWidth   = 1
        windshield.position    = CGPoint(x: carWidth * 0.14, y: carHeight * 0.54)
        windshield.zPosition   = 2
        body.addChild(windshield)

        let rearWin = SKShapeNode(rectOf: CGSize(width: carWidth * 0.15, height: carHeight * 0.45), cornerRadius: 2)
        rearWin.fillColor   = SKColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 0.85)
        rearWin.strokeColor = SKColor(white: 0.4, alpha: 0.4)
        rearWin.lineWidth   = 1
        rearWin.position    = CGPoint(x: -carWidth * 0.20, y: carHeight * 0.54)
        rearWin.zPosition   = 2
        body.addChild(rearWin)

        let hl = SKShapeNode(circleOfRadius: 5)
        hl.fillColor   = SKColor(red: 1.0, green: 0.97, blue: 0.70, alpha: 1)
        hl.strokeColor = SKColor(white: 0.7, alpha: 1)
        hl.lineWidth   = 1
        hl.position    = CGPoint(x: carWidth * 0.46, y: 2)
        hl.zPosition   = 2
        body.addChild(hl)

        let tl = SKShapeNode(circleOfRadius: 4)
        tl.fillColor   = SKColor(red: 1.0, green: 0.10, blue: 0.10, alpha: 1)
        tl.strokeColor = SKColor(red: 0.55, green: 0, blue: 0, alpha: 1)
        tl.lineWidth   = 1
        tl.position    = CGPoint(x: -carWidth * 0.46, y: 2)
        tl.zPosition   = 2
        body.addChild(tl)

        return body
    }

    private func buildWheel() -> SKShapeNode {
        let wheel = SKShapeNode(circleOfRadius: wheelRadius)
        wheel.fillColor   = SKColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1)
        wheel.strokeColor = SKColor(red: 0.50, green: 0.50, blue: 0.50, alpha: 1)
        wheel.lineWidth   = 2.5

        // 4 spokes instead of hub dot
        let spokePath = CGMutablePath()
        for i in 0..<4 {
            let angle = CGFloat(i) * .pi / 2
            let innerR: CGFloat = 3
            let outerR = wheelRadius - 3
            spokePath.move(to: CGPoint(x: cos(angle) * innerR, y: sin(angle) * innerR))
            spokePath.addLine(to: CGPoint(x: cos(angle) * outerR, y: sin(angle) * outerR))
        }
        let spokes = SKShapeNode(path: spokePath)
        spokes.strokeColor = SKColor(white: 0.75, alpha: 1)
        spokes.lineWidth   = 2.5
        spokes.lineCap     = .round
        spokes.zPosition   = 1
        wheel.addChild(spokes)

        // Small center hub
        let hub = SKShapeNode(circleOfRadius: 4)
        hub.fillColor   = SKColor(white: 0.82, alpha: 1)
        hub.strokeColor = .clear
        hub.zPosition   = 2
        wheel.addChild(hub)

        return wheel
    }

    // MARK: - HUD Setup

    private func setupHUD() {
        // Progress bar background (top of screen)
        progressBarBg = SKShapeNode(rectOf: CGSize(width: 600, height: 10), cornerRadius: 5)
        progressBarBg.fillColor   = SKColor(white: 0.0, alpha: 0.55)
        progressBarBg.strokeColor = SKColor(white: 1.0, alpha: 0.25)
        progressBarBg.lineWidth   = 1
        progressBarBg.zPosition   = 99
        progressBarBg.name        = "progressBarBg"
        cameraNode.addChild(progressBarBg)

        // Progress bar fill — use xScale on sprite
        progressBarFill = SKSpriteNode(
            color: SKColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1),
            size: CGSize(width: 596, height: 8))
        progressBarFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        progressBarFill.xScale      = 0
        progressBarFill.zPosition   = 100
        progressBarFill.name        = "progressBarFill"
        cameraNode.addChild(progressBarFill)

        // Speed label
        let speedBg = SKShapeNode(rectOf: CGSize(width: 150, height: 36), cornerRadius: 10)
        speedBg.fillColor    = SKColor(white: 0.0, alpha: 0.55)
        speedBg.strokeColor  = SKColor(white: 1.0, alpha: 0.22)
        speedBg.lineWidth    = 1.5
        speedBg.zPosition    = 99
        speedBg.name         = "speedBg"
        cameraNode.addChild(speedBg)

        speedLabel = SKLabelNode(text: "0 km/h")
        speedLabel.fontName  = "AvenirNext-Bold"
        speedLabel.fontSize  = 19
        speedLabel.fontColor = .white
        speedLabel.horizontalAlignmentMode = .center
        speedLabel.verticalAlignmentMode   = .center
        speedLabel.zPosition = 100
        speedLabel.name      = "speedLabel"
        cameraNode.addChild(speedLabel)

        // Timer display (center top)
        timerLabel = SKLabelNode(text: "00:00.000")
        timerLabel.fontName  = "Courier-Bold"
        timerLabel.fontSize  = 28
        timerLabel.fontColor = .white
        timerLabel.horizontalAlignmentMode = .center
        timerLabel.verticalAlignmentMode   = .top
        timerLabel.zPosition = 100
        timerLabel.name      = "timerLabel"
        cameraNode.addChild(timerLabel)

        // Best time label
        bestTimeLabel = SKLabelNode(text: "")
        bestTimeLabel.fontName  = "AvenirNext-Regular"
        bestTimeLabel.fontSize  = 15
        bestTimeLabel.fontColor = SKColor(red: 1.0, green: 0.85, blue: 0.20, alpha: 1)
        bestTimeLabel.horizontalAlignmentMode = .center
        bestTimeLabel.verticalAlignmentMode   = .top
        bestTimeLabel.zPosition = 100
        bestTimeLabel.name      = "bestTimeLabel"
        cameraNode.addChild(bestTimeLabel)

        if bestTime > 0 {
            bestTimeLabel.text = "BEST: \(formatTime(bestTime))"
        }

        // Gas bar background (above gas button — bottom-right)
        gasBarBgNode = SKShapeNode(rectOf: CGSize(width: 96, height: 10), cornerRadius: 5)
        gasBarBgNode.fillColor   = SKColor(white: 0.0, alpha: 0.50)
        gasBarBgNode.strokeColor = SKColor(white: 1.0, alpha: 0.20)
        gasBarBgNode.lineWidth   = 1
        gasBarBgNode.zPosition   = 99
        gasBarBgNode.name        = "gasBarBg"
        cameraNode.addChild(gasBarBgNode)

        // Gas bar fill — xScale sprite
        gasBarFillNode = SKSpriteNode(
            color: SKColor(red: 1.0, green: 0.50, blue: 0.0, alpha: 1),
            size: CGSize(width: 92, height: 8))
        gasBarFillNode.anchorPoint = CGPoint(x: 0, y: 0.5)
        gasBarFillNode.xScale      = 0
        gasBarFillNode.zPosition   = 100
        gasBarFillNode.name        = "gasBarFill"
        cameraNode.addChild(gasBarFillNode)

        // AIR label (center, shown when airborne)
        airLabel = SKLabelNode(text: "AIR")
        airLabel.fontName  = "AvenirNext-Heavy"
        airLabel.fontSize  = 32
        airLabel.fontColor = SKColor(red: 0.3, green: 0.9, blue: 1.0, alpha: 1)
        airLabel.horizontalAlignmentMode = .center
        airLabel.verticalAlignmentMode   = .center
        airLabel.zPosition = 100
        airLabel.alpha     = 0
        airLabel.name      = "airLabel"
        cameraNode.addChild(airLabel)

        layoutHUD()
    }

    private func layoutHUD() {
        guard cameraNode != nil else { return }
        let w = size.width
        let h = size.height

        // Progress bar — top center
        let progressW: CGFloat = min(w - 80, 600)
        cameraNode.childNode(withName: "progressBarBg")?.position = CGPoint(x: 0, y: h / 2 - 22)
        if let fill = cameraNode.childNode(withName: "progressBarFill") as? SKSpriteNode {
            fill.size     = CGSize(width: progressW - 4, height: 8)
            fill.position = CGPoint(x: -progressW / 2 + 2, y: h / 2 - 22)
        }
        if let bg = cameraNode.childNode(withName: "progressBarBg") as? SKShapeNode {
            bg.path = CGPath(roundedRect: CGRect(x: -progressW / 2, y: -5, width: progressW, height: 10),
                             cornerWidth: 5, cornerHeight: 5, transform: nil)
        }

        // Timer — top center below progress bar
        timerLabel?.position    = CGPoint(x: 0, y: h / 2 - 38)
        bestTimeLabel?.position = CGPoint(x: 0, y: h / 2 - 72)

        // Speed — top left
        cameraNode.childNode(withName: "speedBg")?.position    = CGPoint(x: -w / 2 + 88, y: h / 2 - 42)
        cameraNode.childNode(withName: "speedLabel")?.position = CGPoint(x: -w / 2 + 88, y: h / 2 - 42)

        // Gas bar — bottom right, above the GAS button area (button is at ~padding 36 + 48 = 84 from edge)
        let gasBarCenterX = w / 2 - 88
        let gasBarCenterY = -h / 2 + 148    // sits above the GAS button
        cameraNode.childNode(withName: "gasBarBg")?.position  = CGPoint(x: gasBarCenterX, y: gasBarCenterY)
        if let fill = cameraNode.childNode(withName: "gasBarFill") as? SKSpriteNode {
            fill.position = CGPoint(x: gasBarCenterX - 48, y: gasBarCenterY)
        }

        // AIR label — center
        airLabel?.position = CGPoint(x: 0, y: -h * 0.12)
    }

    // MARK: - Game Loop

    override func update(_ currentTime: TimeInterval) {
        let dt: CGFloat = lastUpdateTime == 0
            ? 0.016
            : CGFloat(min(currentTime - lastUpdateTime, 0.05))
        lastUpdateTime = currentTime

        guard !isDead, !hasWon else { return }
        guard carPhysics?.physicsBody != nil else { return }

        let carPB  = carPhysics.physicsBody!
        let rearPB = wheelRear.physicsBody!
        let isAirborne = (wheelContactCount == 0)

        // === Start timer on first movement ===
        if !timerRunning && isGasHeld {
            timerRunning  = true
            raceStartTime = currentTime
        }
        if timerRunning && !hasWon {
            raceElapsed = currentTime - raceStartTime
            timerLabel.text = formatTime(raceElapsed)
        }

        // === Gas ramp ===
        if isGasHeld {
            gasRampT = min(gasRampT + dt * 0.55, 1.0)
        } else {
            gasRampT = max(gasRampT - dt * 0.40, 0.0)
        }

        // === Rear-wheel drive torque ===
        if isGasHeld {
            let torque = -gasForce * 0.4 * (0.3 + 0.7 * gasRampT)
            rearPB.applyTorque(torque)
        }

        // === Brake — reverse torque on rear wheel ===
        if isBrakeHeld && !isAirborne {
            let brakeTorque = gasForce * 0.25
            rearPB.applyTorque(brakeTorque)
            // Also apply drag to slow down
            var bVel = carPB.velocity
            bVel.dx *= 0.97
            carPB.velocity = bVel
        }

        // === Backward rolling prevention when gas released on ramp ===
        if !isGasHeld && !isBrakeHeld && !isAirborne {
            let rearVel = rearPB.angularVelocity
            if rearVel > 2.0 {  // rolling backward (positive = backward for our direction)
                rearPB.applyTorque(-rearVel * 3.0)
            }
        }

        // === Air lean control ===
        if isAirborne {
            if isLeanLeft {
                carPB.applyTorque(leanTorque)
            }
            if isLeanRight {
                carPB.applyTorque(-leanTorque)
            }
        }

        // === Self-leveling — ONLY small corrections when grounded ===
        if !isAirborne {
            let rot = carPhysics.zRotation
            if abs(rot) < 0.15 {
                // Gentle correction on nearly-flat ground
                let levelTorque = -rot * 4.0
                carPB.applyTorque(levelTorque)
            }
            // No large leveling torque on steep angles — let physics handle it
        }

        // === Horizontal speed cap ===
        var vel = carPB.velocity
        // Allow brief spikes during ramp launches, cap after stabilization
        let effectiveCap = isAirborne ? maxSpeedH * 1.25 : maxSpeedH
        if vel.dx > effectiveCap  { vel.dx = effectiveCap }
        if vel.dx < -effectiveCap { vel.dx = -effectiveCap }
        carPB.velocity = vel

        // === Speed display ===
        let absSpeedH = abs(vel.dx)
        let kmh = Int(absSpeedH * 0.28)
        speedLabel.text = "\(kmh) km/h"
        speedLabel.fontColor = kmh > 240 ? SKColor(red: 1, green: 0.30, blue: 0.30, alpha: 1)
                             : kmh > 140 ? SKColor(red: 1, green: 0.80, blue: 0.20, alpha: 1)
                             : .white

        // === Gas bar using xScale ===
        gasBarFillNode.xScale = gasRampT

        // === Progress bar ===
        let progress = max(0, min(carPhysics.position.x / mapWidth, 1.0))
        progressBarFill.xScale = CGFloat(progress)

        // === Stuck detection ===
        let inStartZone = carPhysics.position.x < spawnX + 250
        if !inStartZone && absSpeedH < 5 && !isBrakeHeld {
            slowTimer += Double(dt)
            if slowTimer >= stuckThreshold { triggerLose() }
        } else {
            slowTimer = 0
        }

        // === Airborne tracking ===
        if isAirborne {
            if !wasAirborne {
                airborneStartY = carPhysics.position.y
                maxAirborneY   = carPhysics.position.y
            }
            maxAirborneY = max(maxAirborneY, carPhysics.position.y)
        }

        // === Airborne → grounded transition ===
        if wasAirborne && !isAirborne {
            let dropHeight = maxAirborneY - carPhysics.position.y
            let impactEnergy = max(0, dropHeight)
            let shakeAmt = min(2 + impactEnergy * 0.015, 16)
            cameraShake(amplitude: shakeAmt, duration: 0.3)
            spawnLandingDust(at: wheelRear.position, energy: impactEnergy)

            // THUD flash label
            if impactEnergy > 80 {
                showThudLabel(energy: impactEnergy)
            }
        }
        wasAirborne = isAirborne

        // === AIR label ===
        airLabel.alpha = isAirborne ? 1.0 : 0.0

        // === Dust particles ===
        if !isAirborne && absSpeedH > 200 {
            dustTimer += dt
            if dustTimer > 0.06 {
                dustTimer = 0
                spawnDust(at: wheelRear.position)
            }
        } else {
            dustTimer = 0
        }

        // === Parallax update ===
        let camX = cameraNode.position.x
        for shape in parallaxMountains {
            let baseX = shape.userData?["baseX"] as? CGFloat ?? shape.position.x
            if shape.userData == nil {
                shape.userData = NSMutableDictionary()
                shape.userData?["baseX"] = shape.position.x
            }
            _ = baseX // stored on first pass below
        }
        updateParallax(camX: camX)

        // === Camera follow ===
        let leadX    = carPhysics.position.x + 220
        let clampedX = max(size.width / 2, min(leadX, mapWidth - size.width / 2))
        let targetY  = max(size.height / 2, carPhysics.position.y + size.height * 0.20)
        cameraNode.position.x += (clampedX - cameraNode.position.x) * 0.10
        cameraNode.position.y += (targetY  - cameraNode.position.y) * 0.07
    }

    // MARK: - Parallax Update

    private func updateParallax(camX: CGFloat) {
        for shape in parallaxMountains {
            guard let base = shape.userData?["baseX"] as? CGFloat else {
                shape.userData = NSMutableDictionary()
                shape.userData?["baseX"] = shape.position.x
                continue
            }
            let offset = (camX - size.width / 2) * 0.15
            shape.position.x = base - offset
        }
        for shape in parallaxHills {
            guard let base = shape.userData?["baseX"] as? CGFloat else {
                shape.userData = NSMutableDictionary()
                shape.userData?["baseX"] = shape.position.x
                continue
            }
            let offset = (camX - size.width / 2) * 0.35
            shape.position.x = base - offset
        }
        for node in parallaxClouds {
            guard let base = node.userData?["baseX"] as? CGFloat else {
                node.userData = NSMutableDictionary()
                node.userData?["baseX"] = node.position.x
                continue
            }
            let offset = (camX - size.width / 2) * 0.60
            node.position.x = base - offset
        }
    }

    // MARK: - Dust Particles

    private func spawnDust(at pos: CGPoint) {
        let count = 3
        for _ in 0..<count {
            let r = CGFloat.random(in: 4...10)
            let dust = SKShapeNode(circleOfRadius: r)
            dust.fillColor   = SKColor(red: 0.72, green: 0.58, blue: 0.38, alpha: 0.75)
            dust.strokeColor = .clear
            dust.position    = CGPoint(x: pos.x + CGFloat.random(in: -12...4),
                                       y: pos.y + CGFloat.random(in: 0...8))
            dust.zPosition   = 8
            addChild(dust)

            let dx = CGFloat.random(in: -80...(-20))
            let dy = CGFloat.random(in: 10...50)
            let move   = SKAction.move(by: CGVector(dx: dx, dy: dy), duration: 0.5)
            let fade   = SKAction.fadeOut(withDuration: 0.45)
            let scale  = SKAction.scale(to: 0.1, duration: 0.5)
            let group  = SKAction.group([move, fade, scale])
            let remove = SKAction.removeFromParent()
            dust.run(SKAction.sequence([group, remove]))
        }
    }

    private func spawnLandingDust(at pos: CGPoint, energy: CGFloat) {
        let count = max(6, min(Int(energy / 15), 20))
        for i in 0..<count {
            let r = CGFloat.random(in: 5...14)
            let dust = SKShapeNode(circleOfRadius: r)
            dust.fillColor   = SKColor(red: 0.68, green: 0.55, blue: 0.35, alpha: 0.85)
            dust.strokeColor = .clear
            dust.position    = CGPoint(x: pos.x + CGFloat.random(in: -30...30),
                                       y: pos.y + CGFloat.random(in: 0...12))
            dust.zPosition   = 14
            addChild(dust)

            let angle   = CGFloat(i) / CGFloat(count) * .pi + CGFloat.random(in: -0.4...0.4)
            let speed   = cgRandom(60, 160) * (1 + energy * 0.002)
            let dx      = cos(angle) * speed
            let dy      = sin(angle) * speed + 20
            let move    = SKAction.move(by: CGVector(dx: dx, dy: dy), duration: 0.7)
            let fade    = SKAction.fadeOut(withDuration: 0.65)
            let scl     = SKAction.scale(to: 0.2, duration: 0.7)
            let group   = SKAction.group([move, fade, scl])
            let remove  = SKAction.removeFromParent()
            dust.run(SKAction.sequence([group, remove]))
        }
    }

    private func showThudLabel(energy: CGFloat) {
        let lbl = SKLabelNode(text: energy > 200 ? "SLAM!" : "THUD")
        lbl.fontName  = "AvenirNext-Heavy"
        lbl.fontSize  = min(24 + energy * 0.08, 52)
        lbl.fontColor = SKColor(red: 1.0, green: 0.7, blue: 0.1, alpha: 1)
        lbl.position  = CGPoint(x: carPhysics.position.x, y: carPhysics.position.y + 60)
        lbl.zPosition = 50
        addChild(lbl)

        let up     = SKAction.moveBy(x: 0, y: 40, duration: 0.4)
        let fade   = SKAction.sequence([SKAction.wait(forDuration: 0.2), SKAction.fadeOut(withDuration: 0.35)])
        let remove = SKAction.removeFromParent()
        lbl.run(SKAction.group([up, SKAction.sequence([fade, remove])]))
    }

    // MARK: - Camera Shake

    private func cameraShake(amplitude: CGFloat, duration: TimeInterval) {
        let steps  = 8
        let stepT  = duration / Double(steps)
        var actions: [SKAction] = []
        for i in 0..<steps {
            let frac = CGFloat(steps - i) / CGFloat(steps)
            let dx   = (i % 2 == 0 ? amplitude : -amplitude) * frac
            let dy   = (i % 2 == 0 ? -amplitude * 0.5 : amplitude * 0.5) * frac
            actions.append(.moveBy(x: dx, y: dy, duration: stepT))
        }
        actions.append(.moveBy(x: 0, y: 0, duration: 0))
        cameraNode.run(.sequence(actions))
    }

    // MARK: - Terrain Helpers

    private func interpolateTerrainY(atX x: CGFloat) -> CGFloat {
        let pts = deduped(terrainPoints)
        guard pts.count >= 2 else { return groundY }
        for i in 1..<pts.count {
            if pts[i].x >= x {
                let t = (x - pts[i-1].x) / (pts[i].x - pts[i-1].x)
                return pts[i-1].y + t * (pts[i].y - pts[i-1].y)
            }
        }
        return pts.last?.y ?? groundY
    }

    private func deduped(_ points: [TerrainPoint]) -> [TerrainPoint] {
        var result: [TerrainPoint] = []
        for p in points {
            if let last = result.last,
               abs(last.x - p.x) < 0.1,
               abs(last.y - p.y) < 0.1 { continue }
            result.append(p)
        }
        return result
    }

    // MARK: - Timer Format

    private func formatTime(_ t: TimeInterval) -> String {
        let mins = Int(t) / 60
        let secs = Int(t) % 60
        let ms   = Int((t - floor(t)) * 1000)
        return String(format: "%02d:%02d.%03d", mins, secs, ms)
    }

    // MARK: - Contact Delegate

    func didBegin(_ contact: SKPhysicsContact) {
        let m = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        // Wheel-ground contact counter — capped at 2
        if m & Cat.ground != 0 && m & Cat.wheel != 0 {
            wheelContactCount = min(wheelContactCount + 1, 2)
        }

        // Finish — car body only
        if m & Cat.finish != 0 && m & Cat.car != 0 {
            triggerWin()
        }

        // Gap — car or wheel
        if m & Cat.gap != 0 && (m & Cat.car != 0 || m & Cat.wheel != 0) {
            triggerLose()
        }

        // Checkpoint
        if m & Cat.checkpoint != 0 && m & Cat.car != 0 {
            if !hasPassedCheckpoint {
                hasPassedCheckpoint = true
                showCheckpointFlash()
            }
        }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        let m = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if m & Cat.ground != 0 && m & Cat.wheel != 0 {
            wheelContactCount = max(0, wheelContactCount - 1)
        }
    }

    private func showCheckpointFlash() {
        let lbl = SKLabelNode(text: "CHECKPOINT!")
        lbl.fontName  = "AvenirNext-Heavy"
        lbl.fontSize  = 36
        lbl.fontColor = SKColor(red: 0.0, green: 0.95, blue: 1.0, alpha: 1)
        lbl.position  = CGPoint(x: 0, y: 60)
        lbl.zPosition = 150
        cameraNode.addChild(lbl)

        let scaleUp  = SKAction.scale(to: 1.15, duration: 0.12)
        let scaleNorm = SKAction.scale(to: 1.0, duration: 0.08)
        let wait     = SKAction.wait(forDuration: 1.0)
        let fade     = SKAction.fadeOut(withDuration: 0.4)
        let remove   = SKAction.removeFromParent()
        lbl.run(SKAction.sequence([scaleUp, scaleNorm, wait, fade, remove]))
    }

    // MARK: - Win / Lose

    private func triggerWin() {
        guard !hasWon, !isDead else { return }
        hasWon = true
        timerRunning = false

        // Save best time
        let key = "drivingBestTime_\(mapMode == .short ? "short" : "long")"
        if bestTime == 0 || raceElapsed < bestTime {
            bestTime = raceElapsed
            UserDefaults.standard.set(bestTime, forKey: key)
        }

        // Freeze
        carPhysics.physicsBody?.isDynamic = false
        carPhysics.physicsBody?.velocity  = .zero
        wheelFront.physicsBody?.isDynamic = false
        wheelFront.physicsBody?.velocity  = .zero
        wheelRear.physicsBody?.isDynamic  = false
        wheelRear.physicsBody?.velocity   = .zero

        if onWin != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.onWin?() }
            return
        }

        let newBest = (bestTime == raceElapsed)
        let sub = newBest ? "New best! \(formatTime(raceElapsed))" : "Time: \(formatTime(raceElapsed))"
        showOverlay(title: "YOU WIN!", subtitle: sub, color: .yellow, isWin: true)
    }

    private func triggerLose() {
        guard !isDead, !hasWon else { return }
        isDead = true
        timerRunning = false

        run(SKAction.wait(forDuration: 0.5)) {
            if self.onLose != nil {
                DispatchQueue.main.async { self.onLose?() }
                return
            }
            self.showOverlay(
                title:    "OH NO!",
                subtitle: "Fell into the gap!",
                color:    SKColor(red: 1, green: 0.3, blue: 0.3, alpha: 1),
                isWin:    false)
        }
    }

    private func showOverlay(title: String, subtitle: String, color: SKColor, isWin: Bool) {
        overlayBg?.removeFromParent()
        isOverlayVisible = true

        let bg = SKSpriteNode(color: SKColor(white: 0, alpha: 0.82),
                              size: CGSize(width: 560, height: isWin ? 280 : 240))
        bg.zPosition = 200
        bg.setScale(0.5)
        cameraNode.addChild(bg)
        overlayBg = bg

        // Scale-in animation
        bg.run(SKAction.scale(to: 1.0, duration: 0.2))

        let titleLbl = SKLabelNode(text: title)
        titleLbl.fontName  = "AvenirNext-Heavy"
        titleLbl.fontSize  = 54
        titleLbl.fontColor = color
        titleLbl.position  = CGPoint(x: 0, y: isWin ? 70 : 50)
        bg.addChild(titleLbl)

        let subLbl = SKLabelNode(text: subtitle)
        subLbl.fontName  = "AvenirNext-Bold"
        subLbl.fontSize  = 22
        subLbl.fontColor = .white
        subLbl.position  = CGPoint(x: 0, y: isWin ? 18 : 0)
        bg.addChild(subLbl)

        if isWin && bestTime > 0 && !(bestTime == raceElapsed) {
            let bestLbl = SKLabelNode(text: "BEST: \(formatTime(bestTime))")
            bestLbl.fontName  = "AvenirNext-Regular"
            bestLbl.fontSize  = 17
            bestLbl.fontColor = SKColor(red: 1.0, green: 0.85, blue: 0.20, alpha: 1)
            bestLbl.position  = CGPoint(x: 0, y: -16)
            bg.addChild(bestLbl)
        }

        let tapLbl = SKLabelNode(text: "Tap or press R to restart")
        tapLbl.fontName  = "AvenirNext-Regular"
        tapLbl.fontSize  = 18
        tapLbl.fontColor = SKColor(white: 0.70, alpha: 1)
        tapLbl.position  = CGPoint(x: 0, y: isWin ? -68 : -60)
        bg.addChild(tapLbl)

        // Confetti on win
        if isWin { spawnConfetti() }
    }

    private func spawnConfetti() {
        let colors: [SKColor] = [
            .yellow, SKColor(red: 1, green: 0.3, blue: 0.3, alpha: 1),
            .cyan, .green, SKColor(red: 1, green: 0.6, blue: 0, alpha: 1), .white
        ]
        for i in 0..<20 {
            let sq = SKSpriteNode(
                color: colors[i % colors.count],
                size: CGSize(width: CGFloat.random(in: 8...16), height: CGFloat.random(in: 8...16)))
            sq.position  = .zero
            sq.zPosition = 201
            cameraNode.addChild(sq)

            let angle = CGFloat(i) / 20.0 * .pi * 2 + CGFloat.random(in: -0.3...0.3)
            let speed = cgRandom(140, 340)
            let dx    = cos(angle) * speed
            let dy    = sin(angle) * speed + 80
            let move  = SKAction.move(by: CGVector(dx: dx, dy: dy), duration: 1.1)
            let rot   = SKAction.rotate(byAngle: CGFloat.random(in: -4...4), duration: 1.1)
            let fade  = SKAction.sequence([SKAction.wait(forDuration: 0.5), SKAction.fadeOut(withDuration: 0.6)])
            let remove = SKAction.removeFromParent()
            sq.run(SKAction.group([move, rot, SKAction.sequence([fade, remove])]))
        }
    }

    // MARK: - Touch → Restart

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isOverlayVisible else { return }
        restartGame()
    }

    // MARK: - Restart

    private func restartGame() {
        guard isOverlayVisible else { return }
        overlayBg?.removeFromParent()
        overlayBg    = nil
        isOverlayVisible   = false
        hasWon       = false
        isDead       = false
        isGasHeld    = false
        isBrakeHeld  = false
        isLeanLeft   = false
        isLeanRight  = false
        gasRampT     = 0
        slowTimer    = 0
        wheelContactCount  = 0
        wasAirborne  = false
        timerRunning = false
        raceElapsed  = 0
        timerLabel?.text  = "00:00.000"

        // Decide respawn point
        let respawnX: CGFloat = hasPassedCheckpoint ? checkpointX : spawnX

        if let jf = jointFront { physicsWorld.remove(jf); jointFront = nil }
        if let jr = jointRear  { physicsWorld.remove(jr); jointRear  = nil }

        // Re-enable & reset
        let startY  = interpolateTerrainY(atX: respawnX) + wheelRadius + carHeight / 2 + 4
        let frontX  = respawnX + carWidth * 0.32
        let rearX   = respawnX - carWidth * 0.32
        let wY      = startY - carHeight / 2 - wheelRadius + 4

        carPhysics.physicsBody?.isDynamic       = true
        carPhysics.physicsBody?.velocity        = .zero
        carPhysics.physicsBody?.angularVelocity = 0
        carPhysics.position  = CGPoint(x: respawnX, y: startY)
        carPhysics.zRotation = 0

        wheelFront.physicsBody?.isDynamic       = true
        wheelFront.physicsBody?.velocity        = .zero
        wheelFront.physicsBody?.angularVelocity = 0
        wheelFront.position  = CGPoint(x: frontX, y: wY)
        wheelFront.zRotation = 0

        wheelRear.physicsBody?.isDynamic        = true
        wheelRear.physicsBody?.velocity         = .zero
        wheelRear.physicsBody?.angularVelocity  = 0
        wheelRear.position   = CGPoint(x: rearX, y: wY)
        wheelRear.zRotation  = 0

        attachWheelJoints(
            frontAnchor: CGPoint(x: frontX, y: wY),
            rearAnchor:  CGPoint(x: rearX,  y: wY))

        // Camera reset to correct terrain height
        cameraNode.removeAllActions()
        let camStartY = max(size.height / 2, startY + size.height * 0.20)
        cameraNode.position = CGPoint(x: respawnX + size.width / 2, y: camStartY)

        // Update progress fill reset
        progressBarFill.xScale = 0

        // Don't reset checkpoint on restart (keep it earned)
        // hasPassedCheckpoint stays as is
    }

    // MARK: - Controls (called from DrivingView)

    func gasPressed()       { isGasHeld    = true  }
    func gasReleased()      { isGasHeld    = false }
    func brakePressed()     { isBrakeHeld  = true  }
    func brakeReleased()    { isBrakeHeld  = false }
    func leanLeftPressed()  { isLeanLeft   = true  }
    func leanLeftReleased() { isLeanLeft   = false }
    func leanRightPressed() { isLeanRight  = true  }
    func leanRightReleased(){ isLeanRight  = false }

    func restartPressed() {
        if isOverlayVisible { restartGame() }
    }
}

// MARK: - CGFloat random helper (convenience overloads)

private func cgRandom(in range: ClosedRange<CGFloat>) -> CGFloat {
    CGFloat(Double.random(in: Double(range.lowerBound)...Double(range.upperBound)))
}

private func cgRandom(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
    cgRandom(in: lo...hi)
}
