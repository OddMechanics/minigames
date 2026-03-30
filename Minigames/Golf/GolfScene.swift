import SpriteKit

// ─────────────────────────────────────────────────────────────────────────────
// GolfScene — professional-quality side-scrolling mini-golf.
//
// Architecture:
//   • Multi-hole system with per-hole par, score tracking
//   • Drag-away-from-ball slingshot mechanic with accurate parabolic preview
//   • Rich visuals: gradient sky, animated lava, glowing lasers, bomb explosions
//   • Shoot-only-when-at-rest (speed < 15 pts/s) with READY indicator
//   • Camera smoothly follows ball; fades to black between holes
//
// Physics categories:
//   ball   = 0x01   solid  = 0x02   lava   = 0x04
//   hole   = 0x08   bomb   = 0x10   laser  = 0x20
// ─────────────────────────────────────────────────────────────────────────────

enum GolfMapMode { case short, long }

// ─── Per-hole configuration ──────────────────────────────────────────────────
private struct HoleConfig {
    let par: Int
    let width: CGFloat
    let build: (GolfScene) -> Void
}

final class GolfScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Public API
    var mapMode: GolfMapMode = .short
    var onWin:   (() -> Void)?
    var onLose:  (() -> Void)?

    // MARK: - Physics categories
    private struct Cat {
        static let ball:  UInt32 = 1 << 0
        static let solid: UInt32 = 1 << 1
        static let lava:  UInt32 = 1 << 2
        static let hole:  UInt32 = 1 << 3
        static let bomb:  UInt32 = 1 << 4
        static let laser: UInt32 = 1 << 5
    }

    // MARK: - Tuning constants
    private let gravityDY:    CGFloat = -520      // pts/s² — authoritative gravity
    private let ballRadius:   CGFloat = 13
    private let maxDragDist:  CGFloat = 210
    private let maxImpulse:   CGFloat = 820       // pts/s at full drag
    private let minDragSnap:  CGFloat = 18
    private let touchRadius:  CGFloat = 80
    private let groundY:      CGFloat = 60
    private let wallThick:    CGFloat = 40
    private let readySpeed:   CGFloat = 15        // below this → ready to shoot

    // MARK: - Scene nodes
    private var ball:         SKShapeNode!
    private var cameraNode:   SKCameraNode!
    private var aimContainer: SKNode?
    private var courseRoot:   SKNode!             // holds all per-hole geometry
    private var hudNode:      SKNode!             // lives on camera

    // Ball trail emitter
    private var trailEmitter: SKEmitterNode?
    private var trailTimer:   TimeInterval = 0

    // READY indicator
    private var readyDot: SKShapeNode?
    private var readyGlow: SKShapeNode?

    // HUD labels
    private var holeLabel:   SKLabelNode!
    private var scoreLabel:  SKLabelNode!
    private var parLabel:    SKLabelNode!
    private var msgLabel:    SKLabelNode!
    private var powerBar:    SKSpriteNode!
    private var powerFill:   SKSpriteNode!

    // MARK: - State
    private var hasBuilt       = false
    private var isDead         = false
    private var hasWon         = false
    private var isTransitioning = false
    private var needsRespawn   = false
    private var isMoving       = false            // ball in significant motion

    // Per-hole state
    private var currentHoleIndex = 0
    private var totalStrokes     = 0             // running total across all holes
    private var holeStrokes      = 0             // strokes on current hole
    private var totalParScore    = 0             // cumulative vs par
    private var holes: [HoleConfig] = []

    // Per-ball session
    private var spawnPoint:    CGPoint = .zero
    private var lastSafePoint: CGPoint = .zero
    private var courseWidth:   CGFloat = 0

    // Touch
    private var dragStart:    CGPoint?
    private var isTouchOnBall = false

    // Physics settle
    private var lastUpdateTime: TimeInterval = 0
    private var settleTimer:    TimeInterval = 0
    private var wasMoving       = false

    // MARK: - Scene lifecycle

    override func didMove(to view: SKView) {
        isPaused       = false
        lastUpdateTime = 0
        settleTimer    = 0
        guard !hasBuilt else { return }
        hasBuilt = true

        physicsWorld.gravity         = CGVector(dx: 0, dy: gravityDY)
        physicsWorld.contactDelegate = self
        physicsWorld.speed           = 1.0

        setupCamera()
        buildHoleList()
        setupHUD()
        loadHole(index: 0, animated: false)
    }

    override func willMove(from view: SKView) {
        isPaused = true
    }

    // MARK: - Camera

    private func setupCamera() {
        cameraNode          = SKCameraNode()
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(cameraNode)
        camera = cameraNode
    }

    // MARK: - Hole list

    private func buildHoleList() {
        switch mapMode {
        case .short:
            holes = [
                HoleConfig(par: 3, width: 1500) { $0.buildShortHole1() },
                HoleConfig(par: 4, width: 1600) { $0.buildShortHole2() },
                HoleConfig(par: 3, width: 1700) { $0.buildShortHole3() },
            ]
        case .long:
            holes = [
                HoleConfig(par: 2, width: 1400) { $0.buildLongHole1() },
                HoleConfig(par: 3, width: 1600) { $0.buildLongHole2() },
                HoleConfig(par: 3, width: 1700) { $0.buildLongHole3() },
                HoleConfig(par: 4, width: 1800) { $0.buildLongHole4() },
                HoleConfig(par: 3, width: 1600) { $0.buildLongHole5() },
                HoleConfig(par: 4, width: 1900) { $0.buildLongHole6() },
                HoleConfig(par: 3, width: 1700) { $0.buildLongHole7() },
                HoleConfig(par: 4, width: 2000) { $0.buildLongHole8() },
                HoleConfig(par: 5, width: 2200) { $0.buildLongHole9() },
            ]
        }
    }

    // MARK: - HUD

    private func setupHUD() {
        hudNode = SKNode()
        hudNode.zPosition = 200
        cameraNode.addChild(hudNode)

        // Sky gradient backdrop — large sprite behind everything
        let skyBack = SKSpriteNode(color: SKColor(red: 0.05, green: 0.10, blue: 0.32, alpha: 1),
                                   size: CGSize(width: size.width * 6, height: size.height * 6))
        skyBack.zPosition = -200
        skyBack.position  = .zero
        cameraNode.addChild(skyBack)

        // Top HUD bar (semi-transparent pill)
        let bar = SKSpriteNode(color: SKColor(white: 0, alpha: 0.55),
                               size: CGSize(width: 520, height: 52))
        bar.position  = CGPoint(x: 0, y: size.height / 2 - 42)
        bar.zPosition = 201
        bar.name      = "hudBar"
        hudNode.addChild(bar)
        let barCorner = SKShapeNode(rectOf: CGSize(width: 520, height: 52), cornerRadius: 14)
        barCorner.fillColor   = SKColor(white: 0, alpha: 0)
        barCorner.strokeColor = SKColor(white: 1, alpha: 0.18)
        barCorner.lineWidth   = 1.5
        barCorner.position    = bar.position
        barCorner.zPosition   = 202
        hudNode.addChild(barCorner)

        holeLabel = SKLabelNode(text: "Hole 1 / 3")
        holeLabel.fontName               = "AvenirNext-Bold"
        holeLabel.fontSize               = 17
        holeLabel.fontColor              = SKColor(white: 0.85, alpha: 1)
        holeLabel.horizontalAlignmentMode = .center
        holeLabel.verticalAlignmentMode   = .center
        holeLabel.position               = CGPoint(x: 0, y: size.height / 2 - 36)
        holeLabel.zPosition = 203
        hudNode.addChild(holeLabel)

        scoreLabel = SKLabelNode(text: "0 strokes  •  Par 3")
        scoreLabel.fontName               = "AvenirNext-Bold"
        scoreLabel.fontSize               = 20
        scoreLabel.fontColor              = .white
        scoreLabel.horizontalAlignmentMode = .center
        scoreLabel.verticalAlignmentMode   = .center
        scoreLabel.position               = CGPoint(x: 0, y: size.height / 2 - 56)
        scoreLabel.zPosition = 203
        hudNode.addChild(scoreLabel)

        parLabel = SKLabelNode(text: "E")
        parLabel.fontName               = "AvenirNext-Bold"
        parLabel.fontSize               = 20
        parLabel.fontColor              = SKColor(red: 0.4, green: 1.0, blue: 0.4, alpha: 1)
        parLabel.horizontalAlignmentMode = .right
        parLabel.verticalAlignmentMode   = .center
        parLabel.position               = CGPoint(x: size.width / 2 - 24, y: size.height / 2 - 46)
        parLabel.zPosition = 203
        hudNode.addChild(parLabel)

        msgLabel = SKLabelNode(text: "")
        msgLabel.fontName                = "AvenirNext-Heavy"
        msgLabel.fontSize                = 34
        msgLabel.fontColor               = .white
        msgLabel.horizontalAlignmentMode = .center
        msgLabel.verticalAlignmentMode   = .center
        msgLabel.position                = CGPoint(x: 0, y: -30)
        msgLabel.zPosition               = 210
        msgLabel.alpha                   = 0
        msgLabel.name                    = "msgLabel"
        hudNode.addChild(msgLabel)

        // Power bar (right side, vertical)
        let pbBack = SKSpriteNode(color: SKColor(white: 0, alpha: 0.45),
                                  size: CGSize(width: 18, height: 160))
        pbBack.position  = CGPoint(x: size.width / 2 - 30, y: -10)
        pbBack.zPosition = 205
        pbBack.alpha     = 0
        pbBack.name      = "powerBarBack"
        hudNode.addChild(pbBack)

        let pbBorder = SKShapeNode(rectOf: CGSize(width: 18, height: 160), cornerRadius: 5)
        pbBorder.fillColor   = .clear
        pbBorder.strokeColor = SKColor(white: 1, alpha: 0.35)
        pbBorder.lineWidth   = 1.5
        pbBorder.position    = pbBack.position
        pbBorder.zPosition   = 206
        pbBorder.alpha       = 0
        pbBorder.name        = "powerBarBorder"
        hudNode.addChild(pbBorder)

        powerFill = SKSpriteNode(color: .white, size: CGSize(width: 14, height: 0))
        powerFill.anchorPoint = CGPoint(x: 0.5, y: 0)
        powerFill.position    = CGPoint(x: 0, y: -80)
        powerFill.zPosition   = 207
        pbBack.addChild(powerFill)

        powerBar = pbBack
    }

    private func updateHUD() {
        let holeCount = holes.count
        let par       = holes[currentHoleIndex].par
        holeLabel.text  = "Hole \(currentHoleIndex + 1) / \(holeCount)"
        scoreLabel.text = "\(holeStrokes) stroke\(holeStrokes == 1 ? "" : "s")  •  Par \(par)"

        let runningPar = totalParScore
        if runningPar == 0 {
            parLabel.text      = "E"
            parLabel.fontColor = SKColor(white: 0.85, alpha: 1)
        } else if runningPar < 0 {
            parLabel.text      = "\(runningPar)"
            parLabel.fontColor = SKColor(red: 0.3, green: 1.0, blue: 0.4, alpha: 1)
        } else {
            parLabel.text      = "+\(runningPar)"
            parLabel.fontColor = SKColor(red: 1.0, green: 0.38, blue: 0.25, alpha: 1)
        }
    }

    // MARK: - Hole loading

    private func loadHole(index: Int, animated: Bool) {
        currentHoleIndex = index
        holeStrokes      = 0
        isMoving         = false
        settleTimer      = 0
        isDead           = false
        hasWon           = false
        needsRespawn     = false

        let buildHole: () -> Void = {
            self.courseRoot?.removeFromParent()
            self.courseRoot = SKNode()
            self.addChild(self.courseRoot)

            self.courseWidth = self.holes[index].width
            self.holes[index].build(self)
            self.buildSkyBackground()
            self.placeBall(at: self.spawnPoint)
            self.lastSafePoint = self.spawnPoint

            // Snap camera to spawn
            let cx = max(self.size.width / 2,
                         min(self.spawnPoint.x, self.courseWidth - self.size.width / 2))
            self.cameraNode.position = CGPoint(x: cx, y: self.size.height / 2)
            self.updateHUD()
            self.isTransitioning = false
        }

        if animated {
            isTransitioning = true
            // Fade to black
            let blackout = SKSpriteNode(color: .black,
                                        size: CGSize(width: size.width * 2, height: size.height * 2))
            blackout.zPosition = 500
            blackout.alpha     = 0
            blackout.name      = "blackout"
            cameraNode.addChild(blackout)

            blackout.run(SKAction.sequence([
                SKAction.fadeIn(withDuration: 0.35),
                SKAction.run { buildHole() },
                SKAction.wait(forDuration: 0.25),
                SKAction.fadeOut(withDuration: 0.45),
                SKAction.removeFromParent()
            ]))
        } else {
            buildHole()
        }
    }

    // MARK: - Sky / background (called per hole inside courseRoot context)

    private func buildSkyBackground() {
        let totalW = courseWidth + wallThick * 2
        let h      = size.height * 1.4

        // Deep blue → light blue-green gradient using two overlapping sprites
        let skyTop = SKSpriteNode(color: SKColor(red: 0.06, green: 0.09, blue: 0.30, alpha: 1),
                                  size: CGSize(width: totalW, height: h))
        skyTop.anchorPoint = CGPoint(x: 0.5, y: 0)
        skyTop.position    = CGPoint(x: courseWidth / 2, y: groundY + wallThick / 2)
        skyTop.zPosition   = -90
        courseRoot.addChild(skyTop)

        let skyMid = SKSpriteNode(color: SKColor(red: 0.25, green: 0.55, blue: 0.68, alpha: 0.85),
                                  size: CGSize(width: totalW, height: h * 0.45))
        skyMid.anchorPoint = CGPoint(x: 0.5, y: 0)
        skyMid.position    = CGPoint(x: courseWidth / 2, y: groundY + wallThick / 2)
        skyMid.zPosition   = -89
        courseRoot.addChild(skyMid)

        // Rolling hills silhouette
        addHillSilhouette(totalW: totalW)
    }

    private func addHillSilhouette(totalW: CGFloat) {
        let hillPath = CGMutablePath()
        let baseY    = groundY + wallThick / 2
        hillPath.move(to: CGPoint(x: -wallThick, y: baseY))

        // Procedural rolling hills
        var x: CGFloat = -wallThick
        var toggle     = false
        while x < totalW + wallThick {
            let segW: CGFloat = CGFloat.random(in: 180...320)
            let peakH: CGFloat = toggle
                ? CGFloat.random(in: 60...140)
                : CGFloat.random(in: 30...80)
            hillPath.addCurve(
                to: CGPoint(x: x + segW, y: baseY),
                control1: CGPoint(x: x + segW * 0.3, y: baseY + peakH),
                control2: CGPoint(x: x + segW * 0.7, y: baseY + peakH)
            )
            x      += segW
            toggle  = !toggle
        }
        hillPath.addLine(to: CGPoint(x: x, y: baseY - 60))
        hillPath.addLine(to: CGPoint(x: -wallThick, y: baseY - 60))
        hillPath.closeSubpath()

        let hills = SKShapeNode(path: hillPath)
        hills.fillColor   = SKColor(red: 0.08, green: 0.24, blue: 0.10, alpha: 0.75)
        hills.strokeColor = .clear
        hills.zPosition   = -88
        courseRoot.addChild(hills)
    }

    // MARK: - Common terrain helpers

    private func addFloor(width: CGFloat) {
        let node = SKSpriteNode(color: SKColor(red: 0.15, green: 0.10, blue: 0.06, alpha: 1),
                                size: CGSize(width: width + wallThick * 2, height: wallThick))
        node.position  = CGPoint(x: width / 2, y: groundY)
        node.zPosition = 5
        node.physicsBody = staticBody(size: node.size, cat: Cat.solid)
        courseRoot.addChild(node)

        // Green fairway strip on top of floor
        let fairway = SKSpriteNode(color: SKColor(red: 0.14, green: 0.52, blue: 0.18, alpha: 1),
                                   size: CGSize(width: width + wallThick * 2, height: 12))
        fairway.position  = CGPoint(x: width / 2, y: groundY + wallThick / 2 - 2)
        fairway.zPosition = 6
        courseRoot.addChild(fairway)

        // Grass texture: small vertical lines
        addGrassDetail(width: width)
    }

    private func addGrassDetail(width: CGFloat) {
        let baseY = groundY + wallThick / 2
        var x: CGFloat = 8
        while x < width - 4 {
            let blade = SKSpriteNode(color: SKColor(red: 0.22, green: 0.68, blue: 0.22, alpha: 0.7),
                                     size: CGSize(width: 1.5, height: CGFloat.random(in: 5...9)))
            blade.anchorPoint = CGPoint(x: 0.5, y: 0)
            blade.position    = CGPoint(x: x, y: baseY)
            blade.zPosition   = 7
            courseRoot.addChild(blade)
            x += CGFloat.random(in: 10...18)
        }
    }

    private func addWall(cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat) {
        let node = SKSpriteNode(color: SKColor(red: 0.20, green: 0.14, blue: 0.09, alpha: 1),
                                size: CGSize(width: w, height: h))
        node.position  = CGPoint(x: cx, y: cy)
        node.zPosition = 5
        node.physicsBody = staticBody(size: node.size, cat: Cat.solid)
        courseRoot.addChild(node)

        // Subtle edge highlight
        let edge = SKSpriteNode(color: SKColor(red: 0.35, green: 0.28, blue: 0.18, alpha: 1),
                                size: CGSize(width: w, height: 3))
        edge.anchorPoint = CGPoint(x: 0.5, y: 0)
        edge.position    = CGPoint(x: cx, y: cy + h / 2 - 1)
        edge.zPosition   = 6
        courseRoot.addChild(edge)
    }

    private func addCeiling(cx: CGFloat, cy: CGFloat, width: CGFloat) {
        let node = SKSpriteNode(color: SKColor(red: 0.15, green: 0.10, blue: 0.06, alpha: 1),
                                size: CGSize(width: width + wallThick * 2, height: wallThick))
        node.position    = CGPoint(x: cx, y: cy)
        node.zPosition   = 5
        node.physicsBody = staticBody(size: node.size, cat: Cat.solid)
        courseRoot.addChild(node)
    }

    @discardableResult
    private func addPlatform(cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat,
                              showArrow: Bool = false, arrowDir: CGFloat = 1) -> SKSpriteNode {
        let node = SKSpriteNode(color: SKColor(red: 0.18, green: 0.50, blue: 0.18, alpha: 1),
                                size: CGSize(width: w, height: h))
        node.position  = CGPoint(x: cx, y: cy)
        node.zPosition = 6

        // Gradient effect: lighter top edge
        let topEdge = SKSpriteNode(color: SKColor(red: 0.40, green: 0.80, blue: 0.30, alpha: 1),
                                   size: CGSize(width: w, height: 4))
        topEdge.position = CGPoint(x: 0, y: h / 2 - 2)
        topEdge.zPosition = 1
        node.addChild(topEdge)

        // Drop shadow
        let shadow = SKSpriteNode(color: SKColor(white: 0, alpha: 0.22),
                                  size: CGSize(width: w + 4, height: 6))
        shadow.position  = CGPoint(x: 1, y: -h / 2 - 3)
        shadow.zPosition = -1
        node.addChild(shadow)

        // Direction arrow for moving platforms
        if showArrow {
            let arrowLabel = SKLabelNode(text: arrowDir > 0 ? "▶" : "◀")
            arrowLabel.fontSize   = 10
            arrowLabel.fontColor  = SKColor(white: 1, alpha: 0.6)
            arrowLabel.position   = .zero
            arrowLabel.zPosition  = 2
            arrowLabel.verticalAlignmentMode = .center
            node.addChild(arrowLabel)
        }

        node.physicsBody = staticBody(size: node.size, cat: Cat.solid, friction: 0.4, restitution: 0.20)
        courseRoot.addChild(node)
        return node
    }

    private func addLava(cx: CGFloat, topY: CGFloat, w: CGFloat) {
        let h: CGFloat = wallThick

        // Base dark red
        let base = SKSpriteNode(color: SKColor(red: 0.55, green: 0.05, blue: 0.00, alpha: 1),
                                size: CGSize(width: w, height: h))
        base.position  = CGPoint(x: cx, y: topY - h / 2)
        base.zPosition = 4
        courseRoot.addChild(base)

        // Main lava sprite with animated color cycle
        let node = SKSpriteNode(color: SKColor(red: 1.0, green: 0.35, blue: 0.00, alpha: 1),
                                size: CGSize(width: w, height: h - 4))
        node.position  = CGPoint(x: cx, y: topY - h / 2 + 2)
        node.zPosition = 5
        node.name      = "lava"
        // Animated: alternating bright orange ↔ deep red
        node.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.colorize(with: SKColor(red: 1.0, green: 0.62, blue: 0.08, alpha: 1),
                              colorBlendFactor: 1, duration: 0.35),
            SKAction.colorize(with: SKColor(red: 0.90, green: 0.15, blue: 0.00, alpha: 1),
                              colorBlendFactor: 1, duration: 0.35),
            SKAction.colorize(with: SKColor(red: 1.0, green: 0.40, blue: 0.02, alpha: 1),
                              colorBlendFactor: 1, duration: 0.25)
        ])))

        // Glow halo
        let glow = SKSpriteNode(color: SKColor(red: 1.0, green: 0.45, blue: 0.0, alpha: 0.18),
                                size: CGSize(width: w + 20, height: h + 16))
        glow.position  = .zero
        glow.zPosition = -1
        glow.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.08, duration: 0.5),
            SKAction.fadeAlpha(to: 0.28, duration: 0.5)
        ])))
        node.addChild(glow)

        // Heat shimmer: a series of wavy top-edge lines
        for i in 0..<4 {
            let shimmer = SKSpriteNode(color: SKColor(red: 1.0, green: 0.80, blue: 0.40, alpha: 0.18),
                                       size: CGSize(width: w, height: 3))
            shimmer.position  = CGPoint(x: 0, y: h / 2 - 2)
            shimmer.zPosition = 2
            let offsetX = CGFloat(i) * 6 - 9
            shimmer.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x:  offsetX, y: CGFloat.random(in: 1...3), duration: 0.18),
                SKAction.moveBy(x: -offsetX, y: CGFloat.random(in: -3...1), duration: 0.18)
            ])))
            node.addChild(shimmer)
        }

        let pb = SKPhysicsBody(rectangleOf: node.size)
        pb.isDynamic          = false
        pb.categoryBitMask    = Cat.lava
        pb.contactTestBitMask = Cat.ball
        pb.collisionBitMask   = 0
        node.physicsBody = pb
        courseRoot.addChild(node)
    }

    private func addHole(cx: CGFloat, cy: CGFloat) {
        let innerR: CGFloat = 18
        let outerR: CGFloat = 28

        let cup = SKShapeNode(circleOfRadius: innerR)
        cup.fillColor   = SKColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1)
        cup.strokeColor = SKColor(white: 0.75, alpha: 0.9)
        cup.lineWidth   = 2.5
        cup.position    = CGPoint(x: cx, y: cy + innerR)
        cup.zPosition   = 8
        cup.name        = "holeCup"

        // Outer glow ring
        let ring = SKShapeNode(circleOfRadius: outerR)
        ring.fillColor   = .clear
        ring.strokeColor = SKColor(red: 1.0, green: 0.88, blue: 0.15, alpha: 0.65)
        ring.lineWidth   = 3
        ring.zPosition   = 7
        cup.addChild(ring)
        ring.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.10, duration: 0.6),
            SKAction.fadeAlpha(to: 0.90, duration: 0.6)
        ])))

        // Second soft glow
        let glow2 = SKShapeNode(circleOfRadius: outerR + 8)
        glow2.fillColor   = SKColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 0.08)
        glow2.strokeColor = .clear
        glow2.zPosition   = 6
        cup.addChild(glow2)
        glow2.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.03, duration: 0.7),
            SKAction.fadeAlpha(to: 0.14, duration: 0.7)
        ])))

        // Flag pole — thin 1pt white line
        let polePath = CGMutablePath()
        polePath.move(to: CGPoint(x: innerR - 2, y: 0))
        polePath.addLine(to: CGPoint(x: innerR - 2, y: 72))
        let pole = SKShapeNode(path: polePath)
        pole.strokeColor = SKColor(white: 0.95, alpha: 1)
        pole.lineWidth   = 1.5
        pole.zPosition   = 9
        cup.addChild(pole)

        // Triangular waving flag
        let flagPath = CGMutablePath()
        flagPath.move(to: CGPoint(x: innerR - 2, y: 72))
        flagPath.addLine(to: CGPoint(x: innerR + 26, y: 63))
        flagPath.addLine(to: CGPoint(x: innerR - 2, y: 54))
        flagPath.closeSubpath()
        let flag = SKShapeNode(path: flagPath)
        flag.fillColor   = SKColor(red: 0.95, green: 0.15, blue: 0.10, alpha: 1)
        flag.strokeColor = SKColor(red: 0.70, green: 0.08, blue: 0.05, alpha: 1)
        flag.lineWidth   = 1
        flag.zPosition   = 9
        // Gentle wave animation
        flag.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scaleX(to: 0.60, duration: 0.45),
            SKAction.scaleX(to: 1.00, duration: 0.40),
            SKAction.scaleX(to: 0.80, duration: 0.35),
            SKAction.scaleX(to: 1.00, duration: 0.30)
        ])))
        cup.addChild(flag)

        let pb = SKPhysicsBody(circleOfRadius: innerR - 3)
        pb.isDynamic          = false
        pb.categoryBitMask    = Cat.hole
        pb.contactTestBitMask = Cat.ball
        pb.collisionBitMask   = 0
        cup.physicsBody = pb
        courseRoot.addChild(cup)
    }

    private func addBomb(cx: CGFloat, cy: CGFloat) {
        let r: CGFloat = 14
        let container  = SKNode()
        container.position = CGPoint(x: cx, y: cy)
        container.zPosition = 7
        container.name   = "bomb"

        // Body: dark charcoal sphere with metallic sheen
        let body = SKShapeNode(circleOfRadius: r)
        body.fillColor   = SKColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1)
        body.strokeColor = SKColor(red: 0.50, green: 0.50, blue: 0.55, alpha: 1)
        body.lineWidth   = 2
        body.zPosition   = 1
        container.addChild(body)

        // Shine
        let shine = SKShapeNode(circleOfRadius: 5)
        shine.fillColor   = SKColor(white: 1, alpha: 0.25)
        shine.strokeColor = .clear
        shine.position    = CGPoint(x: -4, y: 5)
        shine.zPosition   = 2
        container.addChild(shine)

        // Fuse wire (curved path)
        let fusePath = CGMutablePath()
        fusePath.move(to: CGPoint(x: 3, y: r))
        fusePath.addCurve(to: CGPoint(x: 6, y: r + 10),
                          control1: CGPoint(x: 9, y: r + 2),
                          control2: CGPoint(x: 1, y: r + 6))
        let fuse = SKShapeNode(path: fusePath)
        fuse.strokeColor = SKColor(red: 0.65, green: 0.48, blue: 0.18, alpha: 1)
        fuse.lineWidth   = 2.5
        fuse.zPosition   = 2
        container.addChild(fuse)

        // Animated spark cluster at tip
        for i in 0..<3 {
            let spark = SKShapeNode(circleOfRadius: CGFloat.random(in: 2...3.5))
            spark.fillColor   = [
                SKColor(red: 1.0, green: 0.90, blue: 0.15, alpha: 1),
                SKColor(red: 1.0, green: 0.55, blue: 0.05, alpha: 1),
                SKColor(red: 1.0, green: 1.00, blue: 0.60, alpha: 1)
            ][i]
            spark.strokeColor = .clear
            spark.position    = CGPoint(x: 5 + CGFloat(i) * 1.5, y: r + 10 + CGFloat(i))
            spark.zPosition   = 3
            let delay = Double(i) * 0.07
            spark.run(SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.repeatForever(SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.05, duration: 0.08),
                    SKAction.fadeAlpha(to: 1.00, duration: 0.08),
                    SKAction.moveBy(x: CGFloat.random(in: -1.5...1.5),
                                   y: CGFloat.random(in: -1...1), duration: 0.06),
                    SKAction.fadeAlpha(to: 0.50, duration: 0.06)
                ]))
            ]))
            container.addChild(spark)
        }

        let pb = SKPhysicsBody(circleOfRadius: r)
        pb.isDynamic          = false
        pb.categoryBitMask    = Cat.bomb
        pb.contactTestBitMask = Cat.ball
        pb.collisionBitMask   = 0
        container.physicsBody = pb
        courseRoot.addChild(container)
    }

    @discardableResult
    private func addLaserBeam(cx: CGFloat, bottomY: CGFloat, length: CGFloat) -> SKNode {
        let container = SKNode()
        container.position = CGPoint(x: cx, y: bottomY)
        container.zPosition = 9
        container.name = "laser"

        let w: CGFloat = 10

        // Core: bright thin beam
        let corePath = CGMutablePath()
        corePath.addRect(CGRect(x: -3, y: 0, width: 6, height: length))
        let core = SKShapeNode(path: corePath)
        core.fillColor   = SKColor(red: 1.0, green: 0.15, blue: 0.20, alpha: 0.95)
        core.strokeColor = .clear
        core.zPosition   = 2
        container.addChild(core)

        // Outer glow halo
        let haloPath = CGMutablePath()
        haloPath.addRect(CGRect(x: -w / 2, y: 0, width: w, height: length))
        let halo = SKShapeNode(path: haloPath)
        halo.fillColor   = SKColor(red: 1.0, green: 0.10, blue: 0.20, alpha: 0.25)
        halo.strokeColor = .clear
        halo.zPosition   = 1
        container.addChild(halo)

        // Pulsing opacity
        container.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.45, duration: 0.18),
            SKAction.fadeAlpha(to: 1.00, duration: 0.18)
        ])))

        // End cap emitter dots
        for sign in [-1.0, 1.0] {
            let cap = SKShapeNode(circleOfRadius: 5)
            cap.fillColor   = SKColor(red: 1.0, green: 0.50, blue: 0.50, alpha: 0.9)
            cap.strokeColor = .clear
            cap.position    = CGPoint(x: 0, y: sign > 0 ? length : 0)
            cap.zPosition   = 3
            cap.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.scale(to: 1.4, duration: 0.3),
                SKAction.scale(to: 0.8, duration: 0.3)
            ])))
            container.addChild(cap)
        }

        // Physics body centered on laser height
        let pb = SKPhysicsBody(rectangleOf: CGSize(width: w, height: length),
                               center: CGPoint(x: 0, y: length / 2))
        pb.isDynamic          = false
        pb.categoryBitMask    = Cat.laser
        pb.contactTestBitMask = Cat.ball
        pb.collisionBitMask   = 0
        container.physicsBody = pb
        courseRoot.addChild(container)
        return container
    }

    private func addRamp(fromX: CGFloat, groundTopY: CGFloat, toX: CGFloat, topY: CGFloat) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: fromX, y: groundTopY))
        path.addLine(to: CGPoint(x: toX,   y: topY))
        path.addLine(to: CGPoint(x: toX,   y: topY - 10))
        path.addLine(to: CGPoint(x: fromX, y: groundTopY - 10))
        path.closeSubpath()

        let ramp = SKShapeNode(path: path)
        ramp.fillColor   = SKColor(red: 0.22, green: 0.52, blue: 0.16, alpha: 1)
        ramp.strokeColor = SKColor(red: 0.40, green: 0.76, blue: 0.28, alpha: 1)
        ramp.lineWidth   = 2
        ramp.zPosition   = 5

        let pb = SKPhysicsBody(polygonFrom: path)
        pb.isDynamic          = false
        pb.friction           = 0.35
        pb.restitution        = 0.22
        pb.categoryBitMask    = Cat.solid
        pb.contactTestBitMask = Cat.ball
        pb.collisionBitMask   = Cat.ball
        ramp.physicsBody = pb
        courseRoot.addChild(ramp)
    }

    private func addAbyss(cx: CGFloat, w: CGFloat) {
        let node = SKSpriteNode(color: .clear, size: CGSize(width: w, height: 40))
        node.position  = CGPoint(x: cx, y: -80)
        node.zPosition = 1
        let pb = SKPhysicsBody(rectangleOf: node.size)
        pb.isDynamic          = false
        pb.categoryBitMask    = Cat.lava
        pb.contactTestBitMask = Cat.ball
        pb.collisionBitMask   = 0
        node.physicsBody = pb
        courseRoot.addChild(node)
    }

    private func addBoundaryWalls(height: CGFloat) {
        // Left
        let lw = SKSpriteNode(color: SKColor(red: 0.15, green: 0.10, blue: 0.06, alpha: 1),
                              size: CGSize(width: wallThick, height: height * 2))
        lw.position  = CGPoint(x: -wallThick / 2, y: height / 2)
        lw.zPosition = 5
        lw.physicsBody = staticBody(size: lw.size, cat: Cat.solid)
        courseRoot.addChild(lw)

        // Right
        let rw = SKSpriteNode(color: SKColor(red: 0.15, green: 0.10, blue: 0.06, alpha: 1),
                              size: CGSize(width: wallThick, height: height * 2))
        rw.position  = CGPoint(x: courseWidth + wallThick / 2, y: height / 2)
        rw.zPosition = 5
        rw.physicsBody = staticBody(size: rw.size, cat: Cat.solid)
        courseRoot.addChild(rw)

        // Ceiling
        let ceil = SKSpriteNode(color: SKColor(red: 0.15, green: 0.10, blue: 0.06, alpha: 1),
                                size: CGSize(width: courseWidth + wallThick * 2, height: wallThick))
        ceil.position  = CGPoint(x: courseWidth / 2, y: height + wallThick / 2)
        ceil.zPosition = 5
        ceil.physicsBody = staticBody(size: ceil.size, cat: Cat.solid)
        courseRoot.addChild(ceil)
    }

    private func staticBody(size: CGSize, cat: UInt32,
                             friction: CGFloat = 0.48,
                             restitution: CGFloat = 0.65) -> SKPhysicsBody {
        let pb = SKPhysicsBody(rectangleOf: size)
        pb.isDynamic          = false
        pb.friction           = friction
        pb.restitution        = restitution
        pb.categoryBitMask    = cat
        pb.contactTestBitMask = Cat.ball
        pb.collisionBitMask   = (cat == Cat.solid) ? Cat.ball : 0
        return pb
    }

    // MARK: - Ball

    private func placeBall(at point: CGPoint) {
        ball?.removeFromParent()
        readyDot?.removeFromParent()
        readyGlow?.removeFromParent()
        readyDot  = nil
        readyGlow = nil

        ball = SKShapeNode(circleOfRadius: ballRadius)
        ball.fillColor   = SKColor(white: 0.97, alpha: 1)
        ball.strokeColor = SKColor(white: 0.55, alpha: 1)
        ball.lineWidth   = 1.5
        ball.position    = point
        ball.zPosition   = 20
        ball.name        = "ball"

        // Shine
        let shine = SKShapeNode(circleOfRadius: 4.5)
        shine.fillColor   = SKColor(white: 1.0, alpha: 0.75)
        shine.strokeColor = .clear
        shine.position    = CGPoint(x: 4, y: 5)
        shine.zPosition   = 1
        ball.addChild(shine)

        // Drop shadow
        let shadow = SKShapeNode(ellipseOf: CGSize(width: ballRadius * 2.0, height: ballRadius * 0.65))
        shadow.fillColor   = SKColor(white: 0, alpha: 0.30)
        shadow.strokeColor = .clear
        shadow.position    = CGPoint(x: 2, y: -ballRadius - 3)
        shadow.zPosition   = -1
        ball.addChild(shadow)

        let pb = SKPhysicsBody(circleOfRadius: ballRadius)
        pb.mass             = 1.0
        pb.restitution      = 0.65
        pb.friction         = 0.38
        pb.linearDamping    = 0.28
        pb.angularDamping   = 0.80
        pb.allowsRotation   = true
        pb.categoryBitMask    = Cat.ball
        pb.contactTestBitMask = Cat.solid | Cat.lava | Cat.hole | Cat.bomb | Cat.laser
        pb.collisionBitMask   = Cat.solid
        ball.physicsBody = pb
        courseRoot.addChild(ball)

        // Drop spawn animation
        ball.setScale(0.1)
        ball.alpha = 0
        ball.run(SKAction.group([
            SKAction.scale(to: 1.0, duration: 0.30),
            SKAction.fadeIn(withDuration: 0.25)
        ]))

        isMoving    = false
        settleTimer = 0
    }

    // MARK: - READY indicator

    private func showReadyIndicator() {
        guard readyDot == nil, let b = ball else { return }

        let dot = SKShapeNode(circleOfRadius: 5)
        dot.fillColor   = SKColor(red: 0.3, green: 1.0, blue: 0.45, alpha: 0.90)
        dot.strokeColor = .clear
        dot.position    = CGPoint(x: b.position.x, y: b.position.y - ballRadius - 10)
        dot.zPosition   = 22
        dot.name        = "readyDot"
        courseRoot.addChild(dot)
        readyDot = dot

        dot.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 1.4, duration: 0.50),
                SKAction.fadeAlpha(to: 0.5, duration: 0.50)
            ]),
            SKAction.group([
                SKAction.scale(to: 1.0, duration: 0.50),
                SKAction.fadeAlpha(to: 0.9, duration: 0.50)
            ])
        ])))

        let glow = SKShapeNode(circleOfRadius: ballRadius + 4)
        glow.fillColor   = .clear
        glow.strokeColor = SKColor(red: 0.3, green: 1.0, blue: 0.45, alpha: 0.35)
        glow.lineWidth   = 2
        glow.position    = b.position
        glow.zPosition   = 19
        glow.name        = "readyGlow"
        courseRoot.addChild(glow)
        readyGlow = glow

        glow.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.10, duration: 0.6),
            SKAction.fadeAlpha(to: 0.55, duration: 0.6)
        ])))
    }

    private func hideReadyIndicator() {
        readyDot?.removeFromParent()
        readyGlow?.removeFromParent()
        readyDot  = nil
        readyGlow = nil
    }

    // MARK: - Game loop

    override func update(_ currentTime: TimeInterval) {
        let dt: CGFloat
        if lastUpdateTime == 0 { dt = 0.016 }
        else { dt = CGFloat(min(currentTime - lastUpdateTime, 0.05)) }
        lastUpdateTime = currentTime

        guard !hasWon, !isDead, !isTransitioning, ball != nil else { return }

        // Smooth camera follow
        let bx   = ball.position.x
        let by   = ball.position.y
        let camX = max(size.width / 2, min(bx, courseWidth - size.width / 2))
        let camY = max(size.height / 2, min(by + 100, size.height * 1.1))
        cameraNode.position.x += (camX - cameraNode.position.x) * 0.12
        cameraNode.position.y += (cameraNode.position.y < camY)
            ? (camY - cameraNode.position.y) * 0.18
            : (camY - cameraNode.position.y) * 0.10

        guard let pb = ball.physicsBody else { return }

        let speed = hypot(pb.velocity.dx, pb.velocity.dy)

        if isMoving {
            if speed < readySpeed {
                settleTimer += Double(dt)
                if settleTimer > 0.55 {
                    // Come to rest
                    pb.velocity        = .zero
                    pb.angularVelocity = 0
                    isMoving    = false
                    settleTimer = 0
                    lastSafePoint = ball.position
                    showReadyIndicator()
                }
            } else {
                settleTimer = 0
            }
        }
    }

    override func didSimulatePhysics() {
        guard needsRespawn else { return }
        needsRespawn = false
        performRespawn()
    }

    // MARK: - Contacts

    func didBegin(_ contact: SKPhysicsContact) {
        let a = contact.bodyA.categoryBitMask
        let b = contact.bodyB.categoryBitMask
        let m = a | b
        guard m & Cat.ball != 0 else { return }

        if m & Cat.lava   != 0 { triggerDeath();  return }
        if m & Cat.laser  != 0 { triggerDeath();  return }
        if m & Cat.bomb   != 0 {
            let bombNode = (a == Cat.bomb ? contact.bodyA.node : contact.bodyB.node)
            triggerBomb(node: bombNode)
            return
        }
        if m & Cat.hole  != 0 { triggerHoleIn(); return }
    }

    // MARK: - Death (lava / laser / abyss)

    private func triggerDeath() {
        guard !isDead, !hasWon else { return }
        isDead       = true
        needsRespawn = true
        holeStrokes += 1
        totalStrokes += 1
        updateHUD()
        showMessage("Out of bounds!  +1 penalty", duration: 1.2)

        if let pb = ball.physicsBody { pb.velocity = .zero }
        ball.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 2.0, duration: 0.18),
                SKAction.fadeOut(withDuration: 0.18)
            ]),
            SKAction.removeFromParent()
        ]))
    }

    private func performRespawn() {
        isDead      = false
        isMoving    = false
        settleTimer = 0
        hideReadyIndicator()
        placeBall(at: lastSafePoint)
        cameraNode.run(SKAction.move(
            to: CGPoint(
                x: max(size.width / 2, min(lastSafePoint.x, courseWidth - size.width / 2)),
                y: max(size.height / 2, lastSafePoint.y + 80)
            ),
            duration: 0.3))
    }

    // MARK: - Bomb explosion

    private func triggerBomb(node: SKNode?) {
        guard let bombNode = node, bombNode.parent != nil else { return }
        bombNode.physicsBody = nil   // disable — won't respawn this hole

        let bombPos = bombNode.position

        // Shockwave ring
        let ringInner = SKShapeNode(circleOfRadius: 10)
        ringInner.fillColor   = SKColor(red: 1.0, green: 0.95, blue: 0.60, alpha: 0.9)
        ringInner.strokeColor = .clear
        ringInner.position    = bombPos
        ringInner.zPosition   = 35
        courseRoot.addChild(ringInner)
        ringInner.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 7.0, duration: 0.32),
                SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.7, duration: 0.10),
                    SKAction.fadeOut(withDuration: 0.22)
                ])
            ]),
            SKAction.removeFromParent()
        ]))

        let ringOuter = SKShapeNode(circleOfRadius: 12)
        ringOuter.fillColor   = .clear
        ringOuter.strokeColor = SKColor(red: 1.0, green: 0.45, blue: 0.0, alpha: 0.85)
        ringOuter.lineWidth   = 4
        ringOuter.position    = bombPos
        ringOuter.zPosition   = 34
        courseRoot.addChild(ringOuter)
        ringOuter.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 9.0, duration: 0.45),
                SKAction.fadeOut(withDuration: 0.45)
            ]),
            SKAction.removeFromParent()
        ]))

        // Debris particles
        for i in 0..<24 {
            let r = CGFloat.random(in: 2...6)
            let particle = SKShapeNode(circleOfRadius: r)
            let hue = CGFloat.random(in: 0...0.10)
            particle.fillColor   = SKColor(hue: hue, saturation: 1.0,
                                           brightness: CGFloat.random(in: 0.8...1.0), alpha: 1)
            particle.strokeColor = .clear
            particle.position    = bombPos
            particle.zPosition   = 33

            let angle = CGFloat(i) * (.pi * 2 / 24) + CGFloat.random(in: -0.2...0.2)
            let speed = CGFloat.random(in: 220...640)
            let ppb   = SKPhysicsBody(circleOfRadius: r)
            ppb.affectedByGravity  = true
            ppb.collisionBitMask   = 0
            ppb.contactTestBitMask = 0
            ppb.velocity = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)
            particle.physicsBody = ppb
            courseRoot.addChild(particle)

            particle.run(SKAction.sequence([
                SKAction.wait(forDuration: Double.random(in: 0.1...0.2)),
                SKAction.group([
                    SKAction.fadeOut(withDuration: Double.random(in: 0.35...0.65)),
                    SKAction.scale(to: 0.1, duration: Double.random(in: 0.35...0.65))
                ]),
                SKAction.removeFromParent()
            ]))
        }

        // Camera shake
        let origPos = cameraNode.position
        cameraNode.run(SKAction.sequence([
            SKAction.moveBy(x: -14, y:  9, duration: 0.04),
            SKAction.moveBy(x:  18, y: -12, duration: 0.04),
            SKAction.moveBy(x: -12, y:  10, duration: 0.04),
            SKAction.moveBy(x:   8, y:  -8, duration: 0.04),
            SKAction.moveBy(x:  -5, y:   4, duration: 0.04),
            SKAction.moveBy(x:   5, y:  -3, duration: 0.04)
        ]))
        _ = origPos  // suppress warning

        // Fling ball
        if let pb = ball?.physicsBody {
            let dx = CGFloat.random(in: -550...550)
            let dy = CGFloat.random(in:  420...880)
            pb.velocity = CGVector(dx: dx, dy: dy)
            isMoving    = true
            settleTimer = 0
            hideReadyIndicator()
        }

        // Remove bomb
        bombNode.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.10),
            SKAction.removeFromParent()
        ]))

        showMessage("BOOM!", duration: 0.85)
    }

    // MARK: - Hole-in

    private func triggerHoleIn() {
        guard !hasWon, !isTransitioning else { return }
        hasWon = true
        removeAimIndicator()
        hideReadyIndicator()
        if let pb = ball.physicsBody {
            pb.velocity        = .zero
            pb.angularVelocity = 0
        }

        // Ball sinks into hole
        let holeCup = courseRoot.childNode(withName: "holeCup")
        let targetPos = holeCup?.position ?? ball.position

        ball.run(SKAction.sequence([
            SKAction.move(to: targetPos, duration: 0.18),
            SKAction.group([
                SKAction.sequence([
                    SKAction.scale(to: 1.15, duration: 0.08),
                    SKAction.scale(to: 0, duration: 0.22)
                ]),
                SKAction.fadeOut(withDuration: 0.30)
            ]),
            SKAction.removeFromParent()
        ]))

        // Screen flash
        let flash = SKSpriteNode(color: .white,
                                 size: CGSize(width: size.width * 2, height: size.height * 2))
        flash.zPosition = 400
        flash.alpha     = 0
        cameraNode.addChild(flash)
        flash.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.75, duration: 0.10),
            SKAction.fadeOut(withDuration: 0.35),
            SKAction.removeFromParent()
        ]))

        // Score text
        let par       = holes[currentHoleIndex].par
        let relToPar  = holeStrokes - par
        let scoreText = scoreString(strokes: holeStrokes, relToPar: relToPar)
        let scoreColor = relToPar < 0
            ? SKColor(red: 0.3, green: 1.0, blue: 0.4, alpha: 1)
            : (relToPar == 0 ? SKColor.white : SKColor(red: 1.0, green: 0.4, blue: 0.3, alpha: 1))

        let bigLabel = SKLabelNode(text: scoreText)
        bigLabel.fontName               = "AvenirNext-Heavy"
        bigLabel.fontSize               = 52
        bigLabel.fontColor              = scoreColor
        bigLabel.horizontalAlignmentMode = .center
        bigLabel.verticalAlignmentMode   = .center
        bigLabel.position               = CGPoint(x: 0, y: 20)
        bigLabel.zPosition              = 410
        bigLabel.setScale(0.2)
        bigLabel.alpha = 0
        cameraNode.addChild(bigLabel)

        bigLabel.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.28),
            SKAction.group([
                SKAction.sequence([
                    SKAction.scale(to: 1.15, duration: 0.22),
                    SKAction.scale(to: 1.0,  duration: 0.10)
                ]),
                SKAction.fadeIn(withDuration: 0.20)
            ])
        ]))

        let subText = "\(holeStrokes) stroke\(holeStrokes == 1 ? "" : "s")  •  Par \(par)"
        let subLabel = SKLabelNode(text: subText)
        subLabel.fontName               = "AvenirNext-Bold"
        subLabel.fontSize               = 22
        subLabel.fontColor              = SKColor(white: 0.88, alpha: 1)
        subLabel.horizontalAlignmentMode = .center
        subLabel.verticalAlignmentMode   = .center
        subLabel.position               = CGPoint(x: 0, y: -30)
        subLabel.zPosition              = 410
        subLabel.alpha                  = 0
        cameraNode.addChild(subLabel)
        subLabel.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.55),
            SKAction.fadeIn(withDuration: 0.25)
        ]))

        // Particle burst
        spawnHoleParticles()

        // Update totals
        totalStrokes += 0   // already tracked per stroke
        totalParScore += relToPar
        updateHUD()

        let nextDelay: TimeInterval = 2.2
        DispatchQueue.main.asyncAfter(deadline: .now() + nextDelay) { [weak self] in
            guard let self else { return }
            bigLabel.removeFromParent()
            subLabel.removeFromParent()
            let next = self.currentHoleIndex + 1
            if next < self.holes.count {
                self.loadHole(index: next, animated: true)
            } else {
                // All holes done
                self.showFinalScoreOverlay()
            }
        }
    }

    private func scoreString(strokes: Int, relToPar: Int) -> String {
        if strokes == 1     { return "HOLE IN ONE! ⭐" }
        if relToPar <= -2   { return "EAGLE!  \(strokes) strokes" }
        if relToPar == -1   { return "BIRDIE!  \(strokes) strokes" }
        if relToPar ==  0   { return "PAR!  \(strokes) strokes" }
        if relToPar ==  1   { return "Bogey  \(strokes) strokes" }
        if relToPar ==  2   { return "Double Bogey" }
        return "Triple Bogey+"
    }

    private func spawnHoleParticles() {
        guard let b = ball else { return }
        let origin = cameraNode.convert(b.position, from: courseRoot)
        for i in 0..<32 {
            let size   = CGFloat.random(in: 3...8)
            let dot    = SKShapeNode(circleOfRadius: size)
            let colors: [SKColor] = [
                SKColor(red: 1.0, green: 0.9,  blue: 0.2, alpha: 1),
                SKColor(red: 0.3, green: 1.0,  blue: 0.5, alpha: 1),
                SKColor(red: 0.5, green: 0.7,  blue: 1.0, alpha: 1),
                SKColor(red: 1.0, green: 0.4,  blue: 0.6, alpha: 1)
            ]
            dot.fillColor   = colors[i % colors.count]
            dot.strokeColor = .clear
            dot.position    = origin
            dot.zPosition   = 420
            cameraNode.addChild(dot)

            let angle = CGFloat(i) * (.pi * 2 / 32)
            let speed = CGFloat.random(in: 100...280)
            dot.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: cos(angle) * speed,
                                   y: sin(angle) * speed,
                                   duration: 0.7),
                    SKAction.sequence([
                        SKAction.wait(forDuration: 0.2),
                        SKAction.fadeOut(withDuration: 0.5)
                    ])
                ]),
                SKAction.removeFromParent()
            ]))
        }
    }

    private func showFinalScoreOverlay() {
        let totalHoles = holes.count
        let totalPar   = holes.reduce(0) { $0 + $1.par }

        let bg = SKSpriteNode(color: SKColor(red: 0.05, green: 0.08, blue: 0.18, alpha: 0.92),
                              size: CGSize(width: 600, height: 380))
        bg.zPosition = 450
        bg.name      = "finalOverlay"
        cameraNode.addChild(bg)

        let border = SKShapeNode(rectOf: CGSize(width: 600, height: 380), cornerRadius: 20)
        border.fillColor   = .clear
        border.strokeColor = SKColor(white: 1, alpha: 0.22)
        border.lineWidth   = 2
        border.zPosition   = 451
        cameraNode.addChild(border)

        let title = SKLabelNode(text: "COURSE COMPLETE")
        title.fontName               = "AvenirNext-Heavy"
        title.fontSize               = 38
        title.fontColor              = SKColor(red: 1.0, green: 0.88, blue: 0.2, alpha: 1)
        title.horizontalAlignmentMode = .center
        title.position               = CGPoint(x: 0, y: 140)
        title.zPosition              = 452
        bg.addChild(title)
        title.setScale(0.3)
        title.run(SKAction.sequence([
            SKAction.scale(to: 1.1, duration: 0.25),
            SKAction.scale(to: 1.0, duration: 0.10)
        ]))

        let holesText = SKLabelNode(text: "\(totalHoles) holes  •  Par \(totalPar)")
        holesText.fontName               = "AvenirNext-Regular"
        holesText.fontSize               = 20
        holesText.fontColor              = SKColor(white: 0.75, alpha: 1)
        holesText.horizontalAlignmentMode = .center
        holesText.position               = CGPoint(x: 0, y: 90)
        holesText.zPosition              = 452
        bg.addChild(holesText)

        let strokesText = SKLabelNode(text: "Total strokes: \(totalStrokes)")
        strokesText.fontName               = "AvenirNext-Bold"
        strokesText.fontSize               = 28
        strokesText.fontColor              = .white
        strokesText.horizontalAlignmentMode = .center
        strokesText.position               = CGPoint(x: 0, y: 40)
        strokesText.zPosition              = 452
        bg.addChild(strokesText)

        let relScore = totalParScore
        let relText  = relScore == 0 ? "Even par" :
                       relScore  < 0 ? "\(relScore) under par" : "+\(relScore) over par"
        let relColor = relScore < 0
            ? SKColor(red: 0.3, green: 1.0, blue: 0.4, alpha: 1)
            : (relScore == 0 ? SKColor.white : SKColor(red: 1.0, green: 0.42, blue: 0.3, alpha: 1))

        let relLabel = SKLabelNode(text: relText)
        relLabel.fontName               = "AvenirNext-Bold"
        relLabel.fontSize               = 26
        relLabel.fontColor              = relColor
        relLabel.horizontalAlignmentMode = .center
        relLabel.position               = CGPoint(x: 0, y: -10)
        relLabel.zPosition              = 452
        bg.addChild(relLabel)

        let tapLabel = SKLabelNode(text: "Tap to play again")
        tapLabel.fontName               = "AvenirNext-Regular"
        tapLabel.fontSize               = 18
        tapLabel.fontColor              = SKColor(white: 0.55, alpha: 1)
        tapLabel.horizontalAlignmentMode = .center
        tapLabel.position               = CGPoint(x: 0, y: -130)
        tapLabel.zPosition              = 452
        bg.addChild(tapLabel)
        tapLabel.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.7),
            SKAction.fadeAlpha(to: 1.0, duration: 0.7)
        ])))

        if let cb = onWin { cb() }
    }

    // MARK: - Shot feedback

    private func launchEffects() {
        guard let b = ball else { return }

        // Whoosh flash
        let flash = SKSpriteNode(color: .white,
                                 size: CGSize(width: size.width * 2, height: size.height * 2))
        flash.zPosition = 300
        flash.alpha     = 0
        cameraNode.addChild(flash)
        flash.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.22, duration: 0.06),
            SKAction.fadeOut(withDuration: 0.18),
            SKAction.removeFromParent()
        ]))

        // Ghost trail: small white dots that fade at the launch position
        for i in 0..<8 {
            let trail = SKShapeNode(circleOfRadius: CGFloat(8 - i) * 0.9 + 1)
            trail.fillColor   = SKColor(white: 1, alpha: CGFloat(8 - i) / 8.0 * 0.7)
            trail.strokeColor = .clear
            trail.position    = b.position
            trail.zPosition   = 19
            courseRoot.addChild(trail)
            trail.run(SKAction.sequence([
                SKAction.wait(forDuration: Double(i) * 0.04),
                SKAction.fadeOut(withDuration: 0.40),
                SKAction.removeFromParent()
            ]))
        }
    }

    // MARK: - Aim indicator

    private func updateAimIndicator(dragPos: CGPoint) {
        guard let b = ball else { return }
        removeAimIndicator()

        let bp   = b.position
        let dx   = dragPos.x - bp.x
        let dy   = dragPos.y - bp.y
        let dist = hypot(dx, dy)
        guard dist > 10 else { return }

        let nx      = -dx / dist
        let ny      = -dy / dist
        let clamped = min(dist, maxDragDist)
        let power   = clamped / maxDragDist * maxImpulse
        let pFrac   = clamped / maxDragDist   // 0 → 1

        let container = SKNode()
        container.zPosition = 50
        courseRoot.addChild(container)
        aimContainer = container

        // Trajectory dots: 18 steps, size fades + color shifts with power
        let dotCount = 18
        let dt: CGFloat = 0.052
        for i in 1...dotCount {
            let t  = CGFloat(i) * dt
            let px = bp.x + nx * power * t
            let py = bp.y + ny * power * t + 0.5 * gravityDY * t * t
            let frac = CGFloat(i) / CGFloat(dotCount)

            // Size: larger near ball, smaller with distance
            let r = max(1.5, 5.5 * (1.0 - frac * 0.70))

            // Color: white → yellow → orange → red based on power
            let dotColor: SKColor
            if pFrac < 0.33 {
                // white → yellow
                let t2 = pFrac / 0.33
                dotColor = SKColor(red: 1.0,
                                   green: 1.0,
                                   blue: max(0, 1.0 - t2 * 1.0),
                                   alpha: 1.0 - frac * 0.80)
            } else if pFrac < 0.66 {
                // yellow → orange
                let t2 = (pFrac - 0.33) / 0.33
                dotColor = SKColor(red: 1.0,
                                   green: max(0.45, 1.0 - t2 * 0.55),
                                   blue: 0,
                                   alpha: 1.0 - frac * 0.80)
            } else {
                // orange → red
                let t2 = (pFrac - 0.66) / 0.34
                dotColor = SKColor(red: 1.0,
                                   green: max(0, 0.45 - t2 * 0.45),
                                   blue: 0,
                                   alpha: 1.0 - frac * 0.80)
            }

            let dot = SKShapeNode(circleOfRadius: r)
            dot.fillColor   = dotColor
            dot.strokeColor = .clear
            dot.position    = CGPoint(x: px, y: py)
            container.addChild(dot)
        }

        // Arrow head at front of arc
        let arrowDist = min(clamped, 65) + 22
        let ap        = CGPoint(x: bp.x + nx * arrowDist, y: bp.y + ny * arrowDist)
        let angle     = atan2(ny, nx)

        let arrowPath = CGMutablePath()
        arrowPath.move(to: .zero)
        arrowPath.addLine(to: CGPoint(x: -22, y:  10))
        arrowPath.addLine(to: CGPoint(x: -14, y:   0))
        arrowPath.addLine(to: CGPoint(x: -22, y: -10))
        arrowPath.closeSubpath()

        let arrowColor: SKColor
        if pFrac < 0.33 {
            arrowColor = .white
        } else if pFrac < 0.66 {
            arrowColor = SKColor(red: 1.0, green: 0.65, blue: 0.0, alpha: 1)
        } else {
            arrowColor = SKColor(red: 1.0, green: 0.18, blue: 0.0, alpha: 1)
        }

        let arrow = SKShapeNode(path: arrowPath)
        arrow.fillColor   = arrowColor
        arrow.strokeColor = .clear
        arrow.position    = ap
        arrow.zRotation   = angle
        container.addChild(arrow)

        // Power percentage label next to arrow tip
        let pct = Int(pFrac * 100)
        let pctLabel = SKLabelNode(text: "\(pct)%")
        pctLabel.fontName               = "AvenirNext-Bold"
        pctLabel.fontSize               = 14
        pctLabel.fontColor              = arrowColor
        pctLabel.horizontalAlignmentMode = .left
        pctLabel.verticalAlignmentMode   = .center
        pctLabel.position               = CGPoint(x: ap.x + nx * 18 + 4, y: ap.y + ny * 18)
        container.addChild(pctLabel)

        // Power bar (right side, in HUD space — update fill height)
        let fillH = 156 * pFrac
        powerFill.size = CGSize(width: 14, height: max(2, fillH))
        // Bar color gradient
        let barR: CGFloat = pFrac < 0.5 ? pFrac * 2 : 1.0
        let barG: CGFloat = pFrac < 0.5 ? 1.0 : max(0, 2.0 - pFrac * 2)
        powerFill.color = SKColor(red: barR, green: barG, blue: 0.05, alpha: 1)

        powerBar.alpha = 1
        cameraNode.childNode(withName: "powerBarBorder")?.alpha = 1
    }

    private func removeAimIndicator() {
        aimContainer?.removeFromParent()
        aimContainer = nil
        powerBar.alpha = 0
        cameraNode.childNode(withName: "powerBarBorder")?.alpha = 0
        powerFill.size = CGSize(width: 14, height: 0)
    }

    // MARK: - Launch

    private func launchBall(dragPos: CGPoint) {
        guard let b = ball else { return }
        let bp   = b.position
        let dx   = dragPos.x - bp.x
        let dy   = dragPos.y - bp.y
        let dist = hypot(dx, dy)
        guard dist >= minDragSnap else { return }

        holeStrokes += 1
        totalStrokes += 1
        updateHUD()
        hideReadyIndicator()

        let clamped = min(dist, maxDragDist)
        let speed   = clamped / maxDragDist * maxImpulse
        let nx      = -dx / dist
        let ny      = -dy / dist

        if let pb = b.physicsBody {
            pb.velocity = CGVector(dx: nx * speed, dy: ny * speed)
        }
        isMoving    = true
        settleTimer = 0

        launchEffects()
    }

    // MARK: - Message helper

    private func showMessage(_ text: String, duration: TimeInterval) {
        msgLabel.text  = text
        msgLabel.alpha = 1
        msgLabel.removeAllActions()
        msgLabel.run(SKAction.sequence([
            SKAction.wait(forDuration: duration),
            SKAction.fadeOut(withDuration: 0.30)
        ]))
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }

        // Final overlay tap → restart
        if cameraNode.childNode(withName: "finalOverlay") != nil {
            restartGame()
            return
        }

        guard !isDead, !isTransitioning, !hasWon, ball != nil else { return }
        guard let pb = ball.physicsBody else { return }
        let speed = hypot(pb.velocity.dx, pb.velocity.dy)
        guard speed < readySpeed else { return }   // must be nearly at rest

        let loc  = touch.location(in: self)
        let dist = hypot(loc.x - ball.position.x, loc.y - ball.position.y)
        if dist <= touchRadius {
            isTouchOnBall = true
            dragStart     = loc
            updateAimIndicator(dragPos: loc)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isTouchOnBall, let touch = touches.first else { return }
        guard !isDead, !isMoving, !hasWon, ball != nil else { return }
        updateAimIndicator(dragPos: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer {
            removeAimIndicator()
            isTouchOnBall = false
            dragStart     = nil
        }
        guard isTouchOnBall, let touch = touches.first else { return }
        guard !isDead, !isMoving, !hasWon else { return }
        launchBall(dragPos: touch.location(in: self))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        removeAimIndicator()
        isTouchOnBall = false
        dragStart     = nil
    }

    // MARK: - Restart

    private func restartGame() {
        for child in children where child !== cameraNode { child.removeFromParent() }
        cameraNode.removeAllChildren()

        ball           = nil
        courseRoot     = nil
        hasBuilt       = false
        hasWon         = false
        isDead         = false
        isMoving       = false
        isTransitioning = false
        needsRespawn   = false
        totalStrokes   = 0
        holeStrokes    = 0
        totalParScore  = 0
        lastUpdateTime = 0
        settleTimer    = 0
        readyDot       = nil
        readyGlow      = nil

        setupCamera()
        buildHoleList()
        setupHUD()
        loadHole(index: 0, animated: false)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - SHORT COURSE HOLES (3 holes)
    // ═══════════════════════════════════════════════════════════════════════════

    // SHORT HOLE 1: Simple curve, one moving platform over a lava pit
    private func buildShortHole1() {
        let wallH: CGFloat = 250
        addFloor(width: courseWidth)
        addBoundaryWalls(height: wallH)
        addAbyss(cx: courseWidth / 2, w: courseWidth + 100)

        let floorTop = groundY + wallThick / 2
        spawnPoint   = CGPoint(x: 100, y: floorTop + ballRadius + 4)

        // Ramp up
        addRamp(fromX: 220, groundTopY: floorTop, toX: 320, topY: floorTop + 70)
        addPlatform(cx: 370, cy: floorTop + 77, w: 100, h: 14)

        // Lava pit
        addLava(cx: 600, topY: floorTop, w: 240)

        // Moving platform bridge over lava — SKAction driven
        let mp = addPlatform(cx: 600, cy: floorTop + 60, w: 120, h: 16, showArrow: true, arrowDir: 1)
        mp.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x:  90, y: 0, duration: 1.5),
            SKAction.moveBy(x: -90, y: 0, duration: 1.5)
        ])))

        // Step up after lava
        addPlatform(cx: 800, cy: floorTop + 45, w: 90, h: 14)
        addRamp(fromX: 850, groundTopY: floorTop, toX: 940, topY: floorTop + 50)

        // Elevated green
        let greenY: CGFloat = floorTop + 80
        addPlatform(cx: 1200, cy: greenY + 8, w: 380, h: 16)
        addRamp(fromX: 1030, groundTopY: floorTop, toX: 1110, topY: greenY + 16)

        // Some small bumpers
        addWall(cx: 960, cy: floorTop + 60, w: 14, h: 100)

        addHole(cx: 1370, cy: greenY + 16)
    }

    // SHORT HOLE 2: Laser beam crosses the fairway, requires timing
    private func buildShortHole2() {
        let wallH: CGFloat = 260
        addFloor(width: courseWidth)
        addBoundaryWalls(height: wallH)
        addAbyss(cx: courseWidth / 2, w: courseWidth + 100)

        let floorTop = groundY + wallThick / 2
        spawnPoint   = CGPoint(x: 100, y: floorTop + ballRadius + 4)

        // Opening section
        addPlatform(cx: 280, cy: floorTop + 65, w: 120, h: 14)
        addRamp(fromX: 180, groundTopY: floorTop, toX: 240, topY: floorTop + 70)

        // Two lasers at different speeds — player must time the shot
        let laser1 = addLaserBeam(cx: 520, bottomY: floorTop, length: wallH - 50)
        laser1.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x:  80, y: 0, duration: 1.10),
            SKAction.moveBy(x: -80, y: 0, duration: 1.10)
        ])))

        let laser2 = addLaserBeam(cx: 780, bottomY: floorTop, length: wallH - 50)
        laser2.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: -65, y: 0, duration: 0.85),
            SKAction.moveBy(x:  65, y: 0, duration: 0.85)
        ])))

        // Elevated safe islands between lasers
        addPlatform(cx: 640, cy: floorTop + 110, w: 110, h: 14)
        addPlatform(cx: 900, cy: floorTop + 90, w: 90, h: 14)

        // Lava patch
        addLava(cx: 1060, topY: floorTop, w: 140)

        // Final approach
        addPlatform(cx: 1100, cy: floorTop + 70, w: 80, h: 14)
        let greenY: CGFloat = floorTop + 90
        addPlatform(cx: 1330, cy: greenY + 8, w: 360, h: 16)
        addRamp(fromX: 1200, groundTopY: floorTop, toX: 1270, topY: greenY + 16)

        addHole(cx: 1480, cy: greenY + 16)
    }

    // SHORT HOLE 3: Two bombs guarding the hole approach
    private func buildShortHole3() {
        let wallH: CGFloat = 260
        addFloor(width: courseWidth)
        addBoundaryWalls(height: wallH)
        addAbyss(cx: courseWidth / 2, w: courseWidth + 100)

        let floorTop = groundY + wallThick / 2
        spawnPoint   = CGPoint(x: 100, y: floorTop + ballRadius + 4)

        // Wide open approach
        addPlatform(cx: 300, cy: floorTop + 55, w: 110, h: 14)
        addPlatform(cx: 500, cy: floorTop + 90, w: 100, h: 14)

        // Narrow corridor with walls
        addWall(cx: 700, cy: floorTop + 75, w: 14, h: 130)
        addWall(cx: 900, cy: floorTop + 75, w: 14, h: 130)

        // Bomb guards — must navigate carefully or trigger them
        addBomb(cx: 790, cy: floorTop + 13)
        addBomb(cx: 830, cy: floorTop + 13)

        // Lava trench after bomb zone
        addLava(cx: 980, topY: floorTop, w: 160)

        // Moving platform over lava
        let mp = addPlatform(cx: 980, cy: floorTop + 55, w: 100, h: 14, showArrow: true, arrowDir: -1)
        mp.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: -70, y: 0, duration: 1.3),
            SKAction.moveBy(x:  70, y: 0, duration: 1.3)
        ])))

        // Elevated green with ramp
        let greenY: CGFloat = floorTop + 100
        addPlatform(cx: 1380, cy: greenY + 8, w: 400, h: 16)
        addRamp(fromX: 1200, groundTopY: floorTop, toX: 1290, topY: greenY + 16)

        // One more bomb guarding the green approach
        addBomb(cx: 1240, cy: floorTop + 13)

        addHole(cx: 1520, cy: greenY + 16)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - LONG COURSE HOLES (9 holes)
    // ═══════════════════════════════════════════════════════════════════════════

    // HOLE 1: Short opener — straight with a gentle ramp, par 2
    private func buildLongHole1() {
        let wallH: CGFloat = 240
        addFloor(width: courseWidth)
        addBoundaryWalls(height: wallH)
        addAbyss(cx: courseWidth / 2, w: courseWidth + 100)
        let ft = groundY + wallThick / 2
        spawnPoint = CGPoint(x: 100, y: ft + ballRadius + 4)

        addRamp(fromX: 350, groundTopY: ft, toX: 450, topY: ft + 60)
        addPlatform(cx: 540, cy: ft + 67, w: 140, h: 14)
        addRamp(fromX: 620, groundTopY: ft + 74, toX: 700, topY: ft + 120)

        let greenY = ft + 120
        addPlatform(cx: 1050, cy: greenY + 8, w: 500, h: 16)
        addHole(cx: 1250, cy: greenY + 16)
    }

    // HOLE 2: Lava crossing with stepping stones, par 3
    private func buildLongHole2() {
        let wallH: CGFloat = 260
        addFloor(width: courseWidth)
        addBoundaryWalls(height: wallH)
        addAbyss(cx: courseWidth / 2, w: courseWidth + 100)
        let ft = groundY + wallThick / 2
        spawnPoint = CGPoint(x: 100, y: ft + ballRadius + 4)

        addLava(cx: 500, topY: ft, w: 320)

        // Static stepping stones
        addPlatform(cx: 420, cy: ft + 70, w: 80, h: 14)
        addPlatform(cx: 580, cy: ft + 120, w: 70, h: 14)
        addPlatform(cx: 740, cy: ft + 70, w: 80, h: 14)

        // Moving bridge
        let mp = addPlatform(cx: 510, cy: ft + 50, w: 90, h: 14, showArrow: true, arrowDir: 1)
        mp.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: 130, y: 0, duration: 1.6),
            SKAction.moveBy(x: -130, y: 0, duration: 1.6)
        ])))

        addPlatform(cx: 950, cy: ft + 45, w: 120, h: 14)
        let greenY = ft + 80
        addPlatform(cx: 1280, cy: greenY + 8, w: 440, h: 16)
        addRamp(fromX: 1100, groundTopY: ft, toX: 1180, topY: greenY + 16)
        addHole(cx: 1450, cy: greenY + 16)
    }

    // HOLE 3: Bomb corridor with baffles, par 3
    private func buildLongHole3() {
        let wallH: CGFloat = 270
        addFloor(width: courseWidth)
        addBoundaryWalls(height: wallH)
        addAbyss(cx: courseWidth / 2, w: courseWidth + 100)
        let ft = groundY + wallThick / 2
        spawnPoint = CGPoint(x: 100, y: ft + ballRadius + 4)

        addWall(cx: 450, cy: ft + 80, w: 14, h: 140)
        addWall(cx: 680, cy: ft + 80, w: 14, h: 140)
        addWall(cx: 900, cy: ft + 80, w: 14, h: 140)

        addBomb(cx: 550, cy: ft + 13)
        addBomb(cx: 770, cy: ft + 13)
        addBomb(cx: 990, cy: ft + 200)

        addPlatform(cx: 340, cy: ft + 70, w: 100, h: 14)
        addPlatform(cx: 580, cy: ft + 120, w: 80, h: 14)

        let greenY = ft + 90
        addPlatform(cx: 1300, cy: greenY + 8, w: 500, h: 16)
        addRamp(fromX: 1100, groundTopY: ft, toX: 1200, topY: greenY + 16)
        addHole(cx: 1480, cy: greenY + 16)
    }

    // HOLE 4: Single sweeping laser with elevated platform escape, par 4
    private func buildLongHole4() {
        let wallH: CGFloat = 280
        addFloor(width: courseWidth)
        addBoundaryWalls(height: wallH)
        addAbyss(cx: courseWidth / 2, w: courseWidth + 100)
        let ft = groundY + wallThick / 2
        spawnPoint = CGPoint(x: 100, y: ft + ballRadius + 4)

        addLava(cx: 500, topY: ft, w: 80)
        addLava(cx: 800, topY: ft, w: 80)
        addLava(cx: 1100, topY: ft, w: 80)

        let l1 = addLaserBeam(cx: 560, bottomY: ft, length: wallH - 60)
        l1.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x:  100, y: 0, duration: 1.2),
            SKAction.moveBy(x: -100, y: 0, duration: 1.2)
        ])))

        let l2 = addLaserBeam(cx: 860, bottomY: ft, length: wallH - 60)
        l2.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: -90, y: 0, duration: 1.0),
            SKAction.moveBy(x:  90, y: 0, duration: 1.0)
        ])))

        addPlatform(cx: 620, cy: ft + 150, w: 100, h: 14)
        addPlatform(cx: 900, cy: ft + 170, w: 100, h: 14)

        let greenY = ft + 100
        addPlatform(cx: 1450, cy: greenY + 8, w: 460, h: 16)
        addRamp(fromX: 1260, groundTopY: ft, toX: 1360, topY: greenY + 16)
        addHole(cx: 1620, cy: greenY + 16)
    }

    // HOLE 5: Vertical moving platforms over long lava river, par 3
    private func buildLongHole5() {
        let wallH: CGFloat = 280
        addFloor(width: courseWidth)
        addBoundaryWalls(height: wallH)
        addAbyss(cx: courseWidth / 2, w: courseWidth + 100)
        let ft = groundY + wallThick / 2
        spawnPoint = CGPoint(x: 100, y: ft + ballRadius + 4)

        addLava(cx: 650, topY: ft, w: 560)

        let mpA = addPlatform(cx: 480, cy: ft + 100, w: 90, h: 14, showArrow: true, arrowDir: 1)
        mpA.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: 0, y:  90, duration: 1.2),
            SKAction.moveBy(x: 0, y: -90, duration: 1.2)
        ])))

        let mpB = addPlatform(cx: 670, cy: ft + 140, w: 85, h: 14, showArrow: true, arrowDir: 1)
        mpB.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: 100, y: 0, duration: 1.4),
            SKAction.moveBy(x: -100, y: 0, duration: 1.4)
        ])))

        let mpC = addPlatform(cx: 880, cy: ft + 100, w: 85, h: 14, showArrow: true, arrowDir: -1)
        mpC.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: 0, y:  80, duration: 1.0),
            SKAction.moveBy(x: 0, y: -80, duration: 1.0)
        ])))

        let greenY = ft + 90
        addPlatform(cx: 1320, cy: greenY + 8, w: 460, h: 16)
        addRamp(fromX: 1140, groundTopY: ft, toX: 1220, topY: greenY + 16)
        addHole(cx: 1490, cy: greenY + 16)
    }

    // HOLE 6: Mixed bomb + laser gauntlet, par 4
    private func buildLongHole6() {
        let wallH: CGFloat = 290
        addFloor(width: courseWidth)
        addBoundaryWalls(height: wallH)
        addAbyss(cx: courseWidth / 2, w: courseWidth + 100)
        let ft = groundY + wallThick / 2
        spawnPoint = CGPoint(x: 100, y: ft + ballRadius + 4)

        addBomb(cx: 400, cy: ft + 13)
        addBomb(cx: 600, cy: ft + 200)
        addBomb(cx: 800, cy: ft + 13)

        let l1 = addLaserBeam(cx: 500, bottomY: ft, length: wallH - 60)
        l1.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x:  110, y: 0, duration: 1.1),
            SKAction.moveBy(x: -110, y: 0, duration: 1.1)
        ])))

        addWall(cx: 700, cy: ft + 90, w: 14, h: 160)
        addPlatform(cx: 650, cy: ft + 130, w: 90, h: 14)

        addLava(cx: 1000, topY: ft, w: 200)
        let mp = addPlatform(cx: 1000, cy: ft + 70, w: 100, h: 14, showArrow: true, arrowDir: 1)
        mp.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x:  80, y: 0, duration: 1.3),
            SKAction.moveBy(x: -80, y: 0, duration: 1.3)
        ])))

        let greenY = ft + 100
        addPlatform(cx: 1490, cy: greenY + 8, w: 520, h: 16)
        addRamp(fromX: 1270, groundTopY: ft, toX: 1370, topY: greenY + 16)
        addHole(cx: 1680, cy: greenY + 16)
    }

    // HOLE 7: Triple laser corridor, par 3
    private func buildLongHole7() {
        let wallH: CGFloat = 280
        addFloor(width: courseWidth)
        addBoundaryWalls(height: wallH)
        addAbyss(cx: courseWidth / 2, w: courseWidth + 100)
        let ft = groundY + wallThick / 2
        spawnPoint = CGPoint(x: 100, y: ft + ballRadius + 4)

        addLava(cx: 470, topY: ft, w: 70)
        addLava(cx: 680, topY: ft, w: 70)
        addLava(cx: 900, topY: ft, w: 70)

        let l1 = addLaserBeam(cx: 445, bottomY: ft, length: wallH - 55)
        l1.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x:  60, y: 0, duration: 0.55),
            SKAction.moveBy(x: -60, y: 0, duration: 0.55)
        ])))

        let l2 = addLaserBeam(cx: 660, bottomY: ft, length: wallH - 55)
        l2.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: -55, y: 0, duration: 0.62),
            SKAction.moveBy(x:  55, y: 0, duration: 0.62)
        ])))

        let l3 = addLaserBeam(cx: 870, bottomY: ft, length: wallH - 55)
        l3.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x:  50, y: 0, duration: 0.48),
            SKAction.moveBy(x: -50, y: 0, duration: 0.48)
        ])))

        addPlatform(cx: 560, cy: ft + 160, w: 100, h: 14)
        addPlatform(cx: 780, cy: ft + 170, w: 90, h: 14)

        let greenY = ft + 100
        addPlatform(cx: 1280, cy: greenY + 8, w: 540, h: 16)
        addRamp(fromX: 1080, groundTopY: ft, toX: 1170, topY: greenY + 16)
        addHole(cx: 1500, cy: greenY + 16)
    }

    // HOLE 8: Long lava river + bomb field finale, par 4
    private func buildLongHole8() {
        let wallH: CGFloat = 300
        addFloor(width: courseWidth)
        addBoundaryWalls(height: wallH)
        addAbyss(cx: courseWidth / 2, w: courseWidth + 100)
        let ft = groundY + wallThick / 2
        spawnPoint = CGPoint(x: 100, y: ft + ballRadius + 4)

        addLava(cx: 700, topY: ft, w: 560)

        let mpA = addPlatform(cx: 560, cy: ft + 80, w: 90, h: 14, showArrow: true, arrowDir: 1)
        mpA.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x:  100, y: 0, duration: 1.3),
            SKAction.moveBy(x: -100, y: 0, duration: 1.3)
        ])))

        let mpB = addPlatform(cx: 740, cy: ft + 130, w: 85, h: 14, showArrow: true, arrowDir: -1)
        mpB.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: -110, y: 0, duration: 1.5),
            SKAction.moveBy(x:  110, y: 0, duration: 1.5)
        ])))

        let mpC = addPlatform(cx: 920, cy: ft + 80, w: 85, h: 14, showArrow: true, arrowDir: 1)
        mpC.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x:  90, y: 0, duration: 1.1),
            SKAction.moveBy(x: -90, y: 0, duration: 1.1)
        ])))

        // Bomb field after lava
        addBomb(cx: 1160, cy: ft + 13)
        addBomb(cx: 1300, cy: ft + 13)
        addBomb(cx: 1440, cy: ft + 200)
        addWall(cx: 1230, cy: ft + 90, w: 14, h: 160)

        let greenY = ft + 110
        addPlatform(cx: 1700, cy: greenY + 8, w: 420, h: 16)
        addRamp(fromX: 1530, groundTopY: ft, toX: 1620, topY: greenY + 16)
        addHole(cx: 1860, cy: greenY + 16)
    }

    // HOLE 9: Epic finale — everything, par 5
    private func buildLongHole9() {
        let wallH: CGFloat = 320
        addFloor(width: courseWidth)
        addBoundaryWalls(height: wallH)
        addAbyss(cx: courseWidth / 2, w: courseWidth + 100)
        let ft = groundY + wallThick / 2
        spawnPoint = CGPoint(x: 100, y: ft + ballRadius + 4)

        // Section 1: ramps
        addRamp(fromX: 200, groundTopY: ft, toX: 320, topY: ft + 80)
        addPlatform(cx: 380, cy: ft + 87, w: 120, h: 14)

        // Section 2: lava + moving bridge
        addLava(cx: 600, topY: ft, w: 220)
        let mpA = addPlatform(cx: 590, cy: ft + 60, w: 100, h: 14, showArrow: true, arrowDir: 1)
        mpA.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x:  80, y: 0, duration: 1.4),
            SKAction.moveBy(x: -80, y: 0, duration: 1.4)
        ])))

        // Section 3: sweeping lasers
        let l1 = addLaserBeam(cx: 900, bottomY: ft, length: wallH - 60)
        l1.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x:  90, y: 0, duration: 1.0),
            SKAction.moveBy(x: -90, y: 0, duration: 1.0)
        ])))
        let l2 = addLaserBeam(cx: 1100, bottomY: ft, length: wallH - 60)
        l2.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: -75, y: 0, duration: 0.85),
            SKAction.moveBy(x:  75, y: 0, duration: 0.85)
        ])))
        addPlatform(cx: 1000, cy: ft + 170, w: 110, h: 14)
        addLava(cx: 1060, topY: ft, w: 80)

        // Section 4: bomb field
        addBomb(cx: 1280, cy: ft + 13)
        addBomb(cx: 1430, cy: ft + 13)
        addWall(cx: 1360, cy: ft + 85, w: 14, h: 150)

        // Section 5: vertical moving platforms over lava
        addLava(cx: 1660, topY: ft, w: 280)
        let mpB = addPlatform(cx: 1620, cy: ft + 110, w: 90, h: 14, showArrow: true, arrowDir: 1)
        mpB.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: 0, y:  90, duration: 1.2),
            SKAction.moveBy(x: 0, y: -90, duration: 1.2)
        ])))
        let mpC = addPlatform(cx: 1800, cy: ft + 130, w: 85, h: 14, showArrow: true, arrowDir: -1)
        mpC.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: 100, y: 0, duration: 1.3),
            SKAction.moveBy(x: -100, y: 0, duration: 1.3)
        ])))

        // Finale green — elevated
        let greenY: CGFloat = ft + 120
        addPlatform(cx: 2000, cy: greenY + 8, w: 400, h: 16)
        addRamp(fromX: 1920, groundTopY: ft, toX: 1960, topY: greenY + 16)

        // Bonus bomb on the green — avoid it!
        addBomb(cx: 2080, cy: greenY + 16 + 13)

        addHole(cx: 2150, cy: greenY + 16)
    }
}
