import SpriteKit

// ─────────────────────────────────────────────────────────────────────────────
// GolfScene — side-scrolling mini-golf with drag-to-launch (slingshot style).
//
// Coordinate system:
//   x grows rightward, y grows upward.
//   physicsWorld.gravity = CGVector(dx:0, dy:-500)  (pts/s²)
//
// Drag mechanic (spec-compliant):
//   Drag AWAY from ball to aim.  The launch direction is the vector from the
//   drag point back toward the ball (opposite of drag offset).
//   power = min(dragDist, 200) / 200.0 * maxImpulse   (maxImpulse = 800)
//   The dotted trajectory arc uses the same gravity for an accurate preview.
//
// Physics categories
//   ball   = 0x01
//   solid  = 0x02
//   lava   = 0x04
//   hole   = 0x08
//   bomb   = 0x10
//   laser  = 0x20
// ─────────────────────────────────────────────────────────────────────────────

// Top-level so MarathonView can reference it without qualification.
enum GolfMapMode { case short, long }

final class GolfScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Public API
    var mapMode: GolfMapMode = .short
    var onWin:   (() -> Void)?
    var onLose:  (() -> Void)?   // included for protocol parity; not used in golf

    // MARK: - Physics categories
    private struct Cat {
        static let ball:  UInt32 = 1 << 0
        static let solid: UInt32 = 1 << 1
        static let lava:  UInt32 = 1 << 2
        static let hole:  UInt32 = 1 << 3
        static let bomb:  UInt32 = 1 << 4
        static let laser: UInt32 = 1 << 5
    }

    // MARK: - Physics / tuning constants
    private let gravity:      CGFloat = -500      // pts/s² — must match physicsWorld.gravity.dy
    private let ballRadius:   CGFloat = 14
    private let maxDragDist:  CGFloat = 200       // cap for aim indicator and power calculation
    private let maxImpulse:   CGFloat = 800       // pts/s at full drag
    private let minDragSnap:  CGFloat = 20        // minimum drag distance to register a shot
    private let touchRadius:  CGFloat = 70        // how close finger must be to ball to begin drag

    // MARK: - State
    private var ball:         SKShapeNode!
    private var cameraNode:   SKCameraNode!
    private var aimContainer: SKNode?

    private var hasBuilt     = false
    private var isDead       = false
    private var hasWon       = false
    private var needsRespawn = false
    private var isRolling    = false              // ball is in motion; block shooting

    private var strokeCount  = 0
    private var strokeLabel: SKLabelNode!
    private var msgLabel:    SKLabelNode!

    private var spawnPoint    = CGPoint.zero
    private var lastSafePoint = CGPoint.zero
    private var dragStart:    CGPoint?            // touch start in scene coords
    private var isTouchOnBall = false

    private var lastUpdateTime: TimeInterval = 0
    private var settleTimer:    TimeInterval = 0
    private var courseWidth:    CGFloat      = 0

    // ── Collision counting for settle detection ────────────────────────────
    // Tracking contacts lets us quickly know when ball is grounded.
    private var solidContacts = 0

    // ── Shared geometry ────────────────────────────────────────────────────
    private let groundY:   CGFloat = 60     // center-y of the floor slab
    private let wallThick: CGFloat = 40

    // MARK: - Scene lifecycle

    override func didMove(to view: SKView) {
        isPaused = false
        lastUpdateTime = 0
        settleTimer    = 0
        guard !hasBuilt else { return }
        hasBuilt = true

        physicsWorld.gravity         = CGVector(dx: 0, dy: gravity)
        physicsWorld.contactDelegate = self

        setupCamera()
        buildCourse()
        setupHUD()
    }

    override func willMove(from view: SKView) {
        isPaused = true
    }

    // MARK: - Camera

    private func setupCamera() {
        cameraNode = SKCameraNode()
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(cameraNode)
        camera = cameraNode
    }

    // MARK: - HUD

    private func setupHUD() {
        // Sky gradient backdrop (drawn in camera space so it always fills view)
        let sky = SKSpriteNode(color: SKColor(red: 0.38, green: 0.60, blue: 0.90, alpha: 1),
                               size: CGSize(width: size.width * 4, height: size.height * 4))
        sky.zPosition = -100
        sky.position  = .zero
        cameraNode.addChild(sky)

        strokeLabel = SKLabelNode(text: "Strokes: 0")
        strokeLabel.fontName               = "AvenirNext-Bold"
        strokeLabel.fontSize               = 22
        strokeLabel.fontColor              = .white
        strokeLabel.horizontalAlignmentMode = .left
        strokeLabel.position               = CGPoint(x: -size.width / 2 + 20,
                                                      y:  size.height / 2 - 54)
        strokeLabel.zPosition = 200
        cameraNode.addChild(strokeLabel)

        let hint = SKLabelNode(text: "Drag away from ball to aim, release to shoot")
        hint.fontName               = "AvenirNext-Regular"
        hint.fontSize               = 13
        hint.fontColor              = SKColor(white: 1, alpha: 0.75)
        hint.horizontalAlignmentMode = .left
        hint.position               = CGPoint(x: -size.width / 2 + 20,
                                              y:  size.height / 2 - 76)
        hint.zPosition = 200
        hint.name      = "hintLabel"
        cameraNode.addChild(hint)

        msgLabel = SKLabelNode(text: "")
        msgLabel.fontName              = "AvenirNext-Bold"
        msgLabel.fontSize              = 30
        msgLabel.fontColor             = .white
        msgLabel.horizontalAlignmentMode = .center
        msgLabel.verticalAlignmentMode  = .center
        msgLabel.position   = CGPoint(x: 0, y: -40)
        msgLabel.zPosition  = 210
        msgLabel.alpha      = 0
        cameraNode.addChild(msgLabel)
    }

    private func updateStrokeLabel() {
        strokeLabel.text = "Strokes: \(strokeCount)"
    }

    // MARK: - Course builder

    private func buildCourse() {
        switch mapMode {
        case .short: buildShortCourse()
        case .long:  buildLongCourse()
        }
        placeBall(at: spawnPoint)
        lastSafePoint = spawnPoint
    }

    // ── Short course ── 3 unique obstacles, reachable in 5-8 shots ───────────

    private func buildShortCourse() {
        courseWidth = 1600
        let wallH:  CGFloat = 240

        backgroundColor = SKColor(red: 0.20, green: 0.50, blue: 0.20, alpha: 1)

        // ── Boundaries ────────────────────────────────────────────────────
        addFloor(width: courseWidth)
        addWall(cx: -wallThick / 2,             cy: wallH / 2,      w: wallThick, h: wallH * 2)   // left
        addWall(cx: courseWidth + wallThick / 2, cy: wallH / 2,      w: wallThick, h: wallH * 2)   // right
        addCeiling(cx: courseWidth / 2, cy: wallH + wallThick / 2,  width: courseWidth)

        // ── Grass decoration ──────────────────────────────────────────────
        for i in stride(from: 0, through: courseWidth, by: 90) {
            addGrassStrip(x: i, groundTopY: groundY + wallThick / 2)
        }

        spawnPoint = CGPoint(x: 100, y: groundY + wallThick / 2 + ballRadius + 4)

        // ── Obstacle 1: Lava pit with a moving platform bridge ─────────────
        addLava(cx: 380, topY: groundY + wallThick / 2, w: 200)
        // Moving platform over the lava — oscillates horizontally
        let mp1 = addPlatform(cx: 380, cy: 140, w: 110, h: 16)
        mp1.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x:  60, y: 0, duration: 1.4),
            SKAction.moveBy(x: -60, y: 0, duration: 1.4)
        ])))
        // Update its physics body position via action — the body is kinematic
        // (isDynamic=false) so we manually drive it. SKAction moves the node
        // and the physics engine reads the updated position each step.

        // Wall step so ball can get up there
        addPlatform(cx: 260, cy: 95, w: 80, h: 14)

        // ── Obstacle 2: Sweeping laser corridor ───────────────────────────
        let laserX: CGFloat = 760
        let laser1 = addLaserBeam(cx: laserX, bottomY: groundY + wallThick / 2, length: wallH - 30)
        laser1.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x:  70, y: 0, duration: 1.0),
            SKAction.moveBy(x: -70, y: 0, duration: 1.0)
        ])))
        // Elevated platform so player can fly over or under laser window
        addPlatform(cx: 820, cy: 170, w: 90, h: 14)
        addPlatform(cx: 700, cy: 170, w: 90, h: 14)

        // ── Obstacle 3: Bomb cluster ──────────────────────────────────────
        addBomb(cx: 1100, cy: groundY + wallThick / 2 + 13)
        addBomb(cx: 1180, cy: groundY + wallThick / 2 + 13)
        // Small dividing wall to channel the ball through the bomb zone
        addWall(cx: 1140, cy: groundY + wallThick / 2 + 55, w: 16, h: 90)

        // ── Elevated green + ramp at the end ──────────────────────────────
        let greenY: CGFloat = groundY + wallThick / 2 + 70
        addPlatform(cx: 1380, cy: greenY + 8, w: 330, h: 16)
        addRamp(fromX: 1260, groundTopY: groundY + wallThick / 2,
                toX: 1365, topY: greenY + 16)

        // ── Hole (cup) on the green ───────────────────────────────────────
        addHole(cx: 1500, cy: greenY + 16)

        // Right-side abyss sensor (fell off the right)
        addAbyss(cx: courseWidth / 2, w: courseWidth + 100)
    }

    // ── Long course ── 12+ obstacles, all types, creative layout ─────────────

    private func buildLongCourse() {
        courseWidth = 5400
        let wallH:  CGFloat = 360

        backgroundColor = SKColor(red: 0.15, green: 0.38, blue: 0.16, alpha: 1)

        // ── Boundaries ────────────────────────────────────────────────────
        addFloor(width: courseWidth)
        addWall(cx: -wallThick / 2,             cy: wallH / 2, w: wallThick, h: wallH * 2)
        addWall(cx: courseWidth + wallThick / 2, cy: wallH / 2, w: wallThick, h: wallH * 2)
        addCeiling(cx: courseWidth / 2, cy: wallH + wallThick / 2, width: courseWidth)

        for i in stride(from: 0, through: courseWidth, by: 90) {
            addGrassStrip(x: i, groundTopY: groundY + wallThick / 2)
        }

        spawnPoint = CGPoint(x: 130, y: groundY + wallThick / 2 + ballRadius + 4)

        let floorTop = groundY + wallThick / 2   // top surface y of floor

        // ══ SECTION 1: Tutorial ramps (x 0 – 600) ════════════════════════
        addPlatform(cx: 300, cy: floorTop + 55, w: 130, h: 16)
        addPlatform(cx: 480, cy: floorTop + 100, w: 110, h: 16)
        addPlatform(cx: 610, cy: floorTop + 60, w: 100, h: 16)

        // ══ SECTION 2: First lava crossing (x 600 – 1100) ════════════════
        addLava(cx: 800, topY: floorTop, w: 280)
        // Static stepping stones
        addPlatform(cx: 680, cy: floorTop + 80, w: 90, h: 14)
        addPlatform(cx: 820, cy: floorTop + 140, w: 80, h: 14)
        addPlatform(cx: 960, cy: floorTop + 80,  w: 90, h: 14)
        // Moving platform over lava
        let mpA = addPlatform(cx: 760, cy: floorTop + 50, w: 75, h: 14)
        mpA.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: 110, y: 0, duration: 1.6),
            SKAction.moveBy(x: -110, y: 0, duration: 1.6)
        ])))

        // ══ SECTION 3: Bomb alley with wall baffles (x 1100 – 1600) ══════
        addWall(cx: 1200, cy: floorTop + 70, w: 16, h: 120)
        addWall(cx: 1360, cy: floorTop + 90, w: 16, h: 150)
        addWall(cx: 1510, cy: floorTop + 70, w: 16, h: 120)
        addBomb(cx: 1140, cy: floorTop + 13)
        addBomb(cx: 1280, cy: floorTop + 13)
        addBomb(cx: 1430, cy: floorTop + 13)
        addBomb(cx: 1570, cy: floorTop + 13)

        // ══ SECTION 4: Laser gauntlet with lava floors (x 1600 – 2100) ══
        addLava(cx: 1680, topY: floorTop, w: 80)
        addLava(cx: 1840, topY: floorTop, w: 80)
        addLava(cx: 2000, topY: floorTop, w: 80)
        // Three sweeping lasers at different speeds / phases
        let l1 = addLaserBeam(cx: 1660, bottomY: floorTop, length: wallH - 70)
        l1.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x:  85, y: 0, duration: 0.9),
            SKAction.moveBy(x: -85, y: 0, duration: 0.9)
        ])))
        let l2 = addLaserBeam(cx: 1820, bottomY: floorTop, length: wallH - 70)
        l2.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: -75, y: 0, duration: 1.1),
            SKAction.moveBy(x:  75, y: 0, duration: 1.1)
        ])))
        let l3 = addLaserBeam(cx: 1990, bottomY: floorTop, length: wallH - 70)
        l3.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x:  55, y: 0, duration: 0.7),
            SKAction.moveBy(x: -55, y: 0, duration: 0.7)
        ])))
        // Safe elevated platforms to fly over lower laser windows
        addPlatform(cx: 1700, cy: floorTop + 170, w: 80, h: 14)
        addPlatform(cx: 1870, cy: floorTop + 200, w: 80, h: 14)
        addPlatform(cx: 2040, cy: floorTop + 170, w: 80, h: 14)

        // ══ SECTION 5: Moving platform maze over lava (x 2100 – 2700) ════
        addLava(cx: 2250, topY: floorTop, w: 180)
        addLava(cx: 2520, topY: floorTop, w: 160)
        let mpB = addPlatform(cx: 2200, cy: floorTop + 90, w: 100, h: 16)
        mpB.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: 0, y:  80, duration: 1.2),
            SKAction.moveBy(x: 0, y: -80, duration: 1.2)
        ])))
        let mpC = addPlatform(cx: 2380, cy: floorTop + 130, w: 90, h: 16)
        mpC.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: 100, y: 0, duration: 1.4),
            SKAction.moveBy(x: -100, y: 0, duration: 1.4)
        ])))
        let mpD = addPlatform(cx: 2560, cy: floorTop + 90, w: 95, h: 16)
        mpD.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: 0, y:  70, duration: 1.0),
            SKAction.moveBy(x: 0, y: -70, duration: 1.0)
        ])))
        addPlatform(cx: 2670, cy: floorTop + 55, w: 110, h: 14)

        // ══ SECTION 6: Mixed bomb + laser (x 2700 – 3300) ════════════════
        addBomb(cx: 2800, cy: floorTop + 13)
        addBomb(cx: 2950, cy: floorTop + 180)
        addBomb(cx: 3100, cy: floorTop + 13)
        let l4 = addLaserBeam(cx: 2870, bottomY: floorTop, length: wallH - 60)
        l4.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x:  90, y: 0, duration: 1.0),
            SKAction.moveBy(x: -90, y: 0, duration: 1.0)
        ])))
        addWall(cx: 3050, cy: floorTop + 90, w: 16, h: 160)   // baffle

        // ══ SECTION 7: Long lava river + moving bridges (x 3300 – 4000) ══
        addLava(cx: 3650, topY: floorTop, w: 600)
        let mpE = addPlatform(cx: 3380, cy: floorTop + 100, w: 85, h: 14)
        mpE.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x:  80, y: 0, duration: 1.1),
            SKAction.moveBy(x: -80, y: 0, duration: 1.1)
        ])))
        let mpF = addPlatform(cx: 3580, cy: floorTop + 150, w: 80, h: 14)
        mpF.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: -90, y: 0, duration: 1.3),
            SKAction.moveBy(x:  90, y: 0, duration: 1.3)
        ])))
        let mpG = addPlatform(cx: 3780, cy: floorTop + 100, w: 80, h: 14)
        mpG.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x:  70, y: 0, duration: 0.9),
            SKAction.moveBy(x: -70, y: 0, duration: 0.9)
        ])))
        addBomb(cx: 3930, cy: floorTop + 13)

        // ══ SECTION 8: Tight laser corridor (x 4000 – 4500) ══════════════
        addLava(cx: 4070, topY: floorTop, w: 60)
        addLava(cx: 4190, topY: floorTop, w: 60)
        addLava(cx: 4310, topY: floorTop, w: 60)
        let l5 = addLaserBeam(cx: 4040, bottomY: floorTop, length: wallH - 50)
        l5.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x:  50, y: 0, duration: 0.5),
            SKAction.moveBy(x: -50, y: 0, duration: 0.5)
        ])))
        let l6 = addLaserBeam(cx: 4165, bottomY: floorTop, length: wallH - 50)
        l6.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: -50, y: 0, duration: 0.55),
            SKAction.moveBy(x:  50, y: 0, duration: 0.55)
        ])))
        let l7 = addLaserBeam(cx: 4290, bottomY: floorTop, length: wallH - 50)
        l7.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x:  40, y: 0, duration: 0.45),
            SKAction.moveBy(x: -40, y: 0, duration: 0.45)
        ])))

        // ══ SECTION 9: Final bomb field (x 4500 – 5000) ══════════════════
        addBomb(cx: 4580, cy: floorTop + 13)
        addBomb(cx: 4700, cy: floorTop + 200)
        addBomb(cx: 4820, cy: floorTop + 13)
        addBomb(cx: 4940, cy: floorTop + 13)
        let l8 = addLaserBeam(cx: 4760, bottomY: floorTop, length: wallH - 50)
        l8.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x:  100, y: 0, duration: 1.2),
            SKAction.moveBy(x: -100, y: 0, duration: 1.2)
        ])))

        // ══ Elevated green with ramp (x 5000 – 5400) ═════════════════════
        let greenY: CGFloat = floorTop + 100
        addPlatform(cx: 5200, cy: greenY + 8, w: 400, h: 16)
        addRamp(fromX: 5030, groundTopY: floorTop, toX: 5100, topY: greenY + 16)
        addHole(cx: 5270, cy: greenY + 16)

        addAbyss(cx: courseWidth / 2, w: courseWidth + 100)
    }

    // MARK: - Node builders

    // Floor slab
    private func addFloor(width: CGFloat) {
        let node = SKSpriteNode(color: SKColor(red: 0.20, green: 0.14, blue: 0.08, alpha: 1),
                                size: CGSize(width: width + wallThick * 2, height: wallThick))
        node.position  = CGPoint(x: width / 2, y: groundY)
        node.zPosition = 5
        node.physicsBody = staticBody(size: node.size, cat: Cat.solid)
        addChild(node)
    }

    // Ceiling slab
    private func addCeiling(cx: CGFloat, cy: CGFloat, width: CGFloat) {
        let node = SKSpriteNode(color: SKColor(red: 0.18, green: 0.14, blue: 0.08, alpha: 1),
                                size: CGSize(width: width + wallThick * 2, height: wallThick))
        node.position  = CGPoint(x: cx, y: cy)
        node.zPosition = 5
        node.physicsBody = staticBody(size: node.size, cat: Cat.solid)
        addChild(node)
    }

    // Side wall
    private func addWall(cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat) {
        let node = SKSpriteNode(color: SKColor(red: 0.24, green: 0.18, blue: 0.12, alpha: 1),
                                size: CGSize(width: w, height: h))
        node.position  = CGPoint(x: cx, y: cy)
        node.zPosition = 5
        node.physicsBody = staticBody(size: node.size, cat: Cat.solid)
        addChild(node)
    }

    // Decorative grass strip on the floor surface
    private func addGrassStrip(x: CGFloat, groundTopY: CGFloat) {
        let node = SKSpriteNode(color: SKColor(red: 0.20, green: 0.62, blue: 0.15, alpha: 1),
                                size: CGSize(width: 82, height: 6))
        node.position  = CGPoint(x: x + 41, y: groundTopY - 3)
        node.zPosition = 6
        addChild(node)
    }

    // Green platform (returns node so caller can attach SKAction)
    @discardableResult
    private func addPlatform(cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat) -> SKSpriteNode {
        let node = SKSpriteNode(color: SKColor(red: 0.28, green: 0.52, blue: 0.20, alpha: 1),
                                size: CGSize(width: w, height: h))
        node.position  = CGPoint(x: cx, y: cy)
        node.zPosition = 6

        let topEdge = SKSpriteNode(color: SKColor(red: 0.50, green: 0.80, blue: 0.28, alpha: 1),
                                   size: CGSize(width: w, height: 4))
        topEdge.position = CGPoint(x: 0, y: h / 2 - 2)
        node.addChild(topEdge)

        node.physicsBody = staticBody(size: node.size, cat: Cat.solid, friction: 0.35, restitution: 0.25)
        addChild(node)
        return node
    }

    // Lava hazard (topY = the y of the surface the lava sits on)
    private func addLava(cx: CGFloat, topY: CGFloat, w: CGFloat) {
        let h: CGFloat = wallThick
        let node = SKSpriteNode(color: SKColor(red: 1.0, green: 0.28, blue: 0.0, alpha: 1),
                                size: CGSize(width: w, height: h))
        node.position  = CGPoint(x: cx, y: topY - h / 2)
        node.zPosition = 4
        node.name      = "lava"
        // Animated pulsing color
        node.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.colorize(with: SKColor(red: 1.0, green: 0.58, blue: 0.05, alpha: 1),
                              colorBlendFactor: 1, duration: 0.45),
            SKAction.colorize(with: SKColor(red: 0.85, green: 0.08, blue: 0.00, alpha: 1),
                              colorBlendFactor: 1, duration: 0.45)
        ])))
        let pb = SKPhysicsBody(rectangleOf: node.size)
        pb.isDynamic          = false
        pb.categoryBitMask    = Cat.lava
        pb.contactTestBitMask = Cat.ball
        pb.collisionBitMask   = 0
        node.physicsBody = pb
        addChild(node)
    }

    // Hole / cup + flag
    private func addHole(cx: CGFloat, cy: CGFloat) {
        let innerR: CGFloat = 18
        let outerR: CGFloat = 26

        let cup = SKShapeNode(circleOfRadius: innerR)
        cup.fillColor   = SKColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1)
        cup.strokeColor = SKColor(white: 0.9, alpha: 0.8)
        cup.lineWidth   = 3
        cup.position    = CGPoint(x: cx, y: cy + innerR)
        cup.zPosition   = 8

        // Pulsing glow ring
        let ring = SKShapeNode(circleOfRadius: outerR)
        ring.fillColor   = .clear
        ring.strokeColor = SKColor(red: 1.0, green: 0.90, blue: 0.20, alpha: 0.6)
        ring.lineWidth   = 3
        ring.zPosition   = 7
        cup.addChild(ring)
        ring.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.12, duration: 0.55),
            SKAction.fadeAlpha(to: 0.90, duration: 0.55)
        ])))

        // Flag pole
        let pole = SKSpriteNode(color: .white, size: CGSize(width: 3, height: 60))
        pole.position = CGPoint(x: innerR - 1, y: 34)
        pole.zPosition = 9
        cup.addChild(pole)

        // Waving flag
        let flag = SKShapeNode(rectOf: CGSize(width: 24, height: 16), cornerRadius: 3)
        flag.fillColor   = SKColor(red: 0.90, green: 0.10, blue: 0.10, alpha: 1)
        flag.strokeColor = .clear
        flag.position    = CGPoint(x: innerR + 11, y: 60)
        flag.zPosition   = 9
        flag.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scaleX(to: 1.00, duration: 0.40),
            SKAction.scaleX(to: 0.65, duration: 0.40)
        ])))
        cup.addChild(flag)

        let pb = SKPhysicsBody(circleOfRadius: innerR - 2)
        pb.isDynamic          = false
        pb.categoryBitMask    = Cat.hole
        pb.contactTestBitMask = Cat.ball
        pb.collisionBitMask   = 0
        cup.physicsBody = pb
        addChild(cup)
    }

    // Bomb with fuse
    private func addBomb(cx: CGFloat, cy: CGFloat) {
        let r: CGFloat = 13
        let bomb = SKShapeNode(circleOfRadius: r)
        bomb.fillColor   = SKColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1)
        bomb.strokeColor = SKColor(red: 0.65, green: 0.60, blue: 0.55, alpha: 1)
        bomb.lineWidth   = 2
        bomb.position    = CGPoint(x: cx, y: cy)
        bomb.zPosition   = 7
        bomb.name        = "bomb"

        // Fuse wire
        let fusePath = CGMutablePath()
        fusePath.move(to: CGPoint(x: 4, y: r))
        fusePath.addCurve(to: CGPoint(x: 5, y: r + 7),
                          control1: CGPoint(x: 8, y: r + 2),
                          control2: CGPoint(x: 2, y: r + 5))
        let fuse = SKShapeNode(path: fusePath)
        fuse.strokeColor = SKColor(red: 0.70, green: 0.50, blue: 0.20, alpha: 1)
        fuse.lineWidth   = 2
        bomb.addChild(fuse)

        // Flickering spark
        let spark = SKShapeNode(circleOfRadius: 3)
        spark.fillColor   = SKColor(red: 1.0, green: 0.85, blue: 0.10, alpha: 1)
        spark.strokeColor = .clear
        spark.position    = CGPoint(x: 5, y: r + 8)
        spark.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.05, duration: 0.10),
            SKAction.fadeAlpha(to: 1.00, duration: 0.10),
            SKAction.fadeAlpha(to: 0.40, duration: 0.07),
            SKAction.fadeAlpha(to: 1.00, duration: 0.07)
        ])))
        bomb.addChild(spark)

        let pb = SKPhysicsBody(circleOfRadius: r)
        pb.isDynamic          = false
        pb.categoryBitMask    = Cat.bomb
        pb.contactTestBitMask = Cat.ball
        pb.collisionBitMask   = 0
        bomb.physicsBody = pb
        addChild(bomb)
    }

    // Laser beam (vertical, sweeps horizontally via SKAction from caller)
    @discardableResult
    private func addLaserBeam(cx: CGFloat, bottomY: CGFloat, length: CGFloat) -> SKShapeNode {
        let path = CGMutablePath()
        path.addRect(CGRect(x: -5, y: 0, width: 10, height: length))

        let beam = SKShapeNode(path: path)
        beam.fillColor   = SKColor(red: 1.0, green: 0.08, blue: 0.08, alpha: 0.88)
        beam.strokeColor = SKColor(red: 1.0, green: 0.55, blue: 0.55, alpha: 0.55)
        beam.lineWidth   = 1.5
        beam.position    = CGPoint(x: cx, y: bottomY)
        beam.zPosition   = 9
        beam.name        = "laser"
        // Pulsing glow
        beam.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.40, duration: 0.22),
            SKAction.fadeAlpha(to: 1.00, duration: 0.22)
        ])))
        let pb = SKPhysicsBody(rectangleOf: CGSize(width: 10, height: length),
                               center: CGPoint(x: 0, y: length / 2))
        pb.isDynamic          = false
        pb.categoryBitMask    = Cat.laser
        pb.contactTestBitMask = Cat.ball
        pb.collisionBitMask   = 0
        beam.physicsBody = pb
        addChild(beam)
        return beam
    }

    // Ramp (diagonal solid surface)
    private func addRamp(fromX: CGFloat, groundTopY: CGFloat, toX: CGFloat, topY: CGFloat) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: fromX, y: groundTopY))
        path.addLine(to: CGPoint(x: toX,  y: topY))
        path.addLine(to: CGPoint(x: toX,  y: topY - 8))
        path.addLine(to: CGPoint(x: fromX, y: groundTopY - 8))
        path.closeSubpath()

        let ramp = SKShapeNode(path: path)
        ramp.fillColor   = SKColor(red: 0.28, green: 0.50, blue: 0.18, alpha: 1)
        ramp.strokeColor = .clear
        ramp.zPosition   = 5

        let pb = SKPhysicsBody(polygonFrom: path)
        pb.isDynamic          = false
        pb.friction           = 0.30
        pb.restitution        = 0.20
        pb.categoryBitMask    = Cat.solid
        pb.contactTestBitMask = Cat.ball
        pb.collisionBitMask   = Cat.ball
        ramp.physicsBody = pb
        addChild(ramp)
    }

    // Invisible abyss sensor (ball fell below map)
    private func addAbyss(cx: CGFloat, w: CGFloat) {
        let node = SKSpriteNode(color: .clear, size: CGSize(width: w, height: 40))
        node.position  = CGPoint(x: cx, y: -60)
        node.zPosition = 1
        let pb = SKPhysicsBody(rectangleOf: node.size)
        pb.isDynamic          = false
        pb.categoryBitMask    = Cat.lava   // treated same as lava → respawn
        pb.contactTestBitMask = Cat.ball
        pb.collisionBitMask   = 0
        node.physicsBody = pb
        addChild(node)
    }

    // Helper: static physics body with standard golf course friction/restitution
    private func staticBody(size: CGSize, cat: UInt32,
                             friction: CGFloat = 0.50,
                             restitution: CGFloat = 0.35) -> SKPhysicsBody {
        let pb = SKPhysicsBody(rectangleOf: size)
        pb.isDynamic          = false
        pb.friction           = friction
        pb.restitution        = restitution
        pb.categoryBitMask    = cat
        pb.contactTestBitMask = Cat.ball
        pb.collisionBitMask   = (cat == Cat.solid) ? Cat.ball : 0
        return pb
    }

    // MARK: - Ball placement

    private func placeBall(at point: CGPoint) {
        ball?.removeFromParent()

        ball = SKShapeNode(circleOfRadius: ballRadius)
        ball.fillColor   = SKColor(white: 0.97, alpha: 1)
        ball.strokeColor = SKColor(white: 0.60, alpha: 1)
        ball.lineWidth   = 2
        ball.position    = point
        ball.zPosition   = 20
        ball.name        = "ball"

        // Subtle shine highlight
        let shine = SKShapeNode(circleOfRadius: 4)
        shine.fillColor   = SKColor(white: 1, alpha: 0.70)
        shine.strokeColor = .clear
        shine.position    = CGPoint(x: 4, y: 5)
        ball.addChild(shine)

        // Faint drop shadow
        let shadow = SKShapeNode(ellipseOf: CGSize(width: ballRadius * 1.8, height: ballRadius * 0.6))
        shadow.fillColor   = SKColor(white: 0, alpha: 0.25)
        shadow.strokeColor = .clear
        shadow.position    = CGPoint(x: 2, y: -ballRadius - 2)
        shadow.zPosition   = -1
        ball.addChild(shadow)

        let pb = SKPhysicsBody(circleOfRadius: ballRadius)
        pb.mass             = 1.0
        pb.restitution      = 0.60
        pb.friction         = 0.40
        pb.linearDamping    = 0.30
        pb.angularDamping   = 0.55
        pb.allowsRotation   = true
        pb.categoryBitMask    = Cat.ball
        pb.contactTestBitMask = Cat.solid | Cat.lava | Cat.hole | Cat.bomb | Cat.laser
        pb.collisionBitMask   = Cat.solid
        ball.physicsBody = pb
        addChild(ball)

        isRolling   = false
        settleTimer = 0
        solidContacts = 0
    }

    // MARK: - Game loop

    override func update(_ currentTime: TimeInterval) {
        let dt: CGFloat
        if lastUpdateTime == 0 { dt = 0.016 }
        else { dt = CGFloat(min(currentTime - lastUpdateTime, 0.05)) }
        lastUpdateTime = currentTime

        guard !hasWon, !isDead, ball != nil else { return }

        // Camera smoothly follows ball
        let bx = ball.position.x
        let by = ball.position.y
        let camX = max(size.width  / 2, min(bx, courseWidth - size.width  / 2))
        let camY = max(size.height / 2, by + 80)
        cameraNode.position.x += (camX - cameraNode.position.x) * 0.14
        cameraNode.position.y += (camY - cameraNode.position.y) * 0.14

        // Settle detection: once the ball is moving, wait until it slows down.
        guard let pb = ball.physicsBody else { return }
        if isRolling {
            let speed = hypot(pb.velocity.dx, pb.velocity.dy)
            if speed < 20 {
                settleTimer += Double(dt)
                if settleTimer > 0.6 {
                    // Snap to rest
                    pb.velocity        = .zero
                    pb.angularVelocity = 0
                    isRolling   = false
                    settleTimer = 0
                    // Only update safe point if not hovering above lava / hazard
                    lastSafePoint = ball.position
                    showRestingHint()
                }
            } else {
                settleTimer = 0
            }
        }
    }

    private func showRestingHint() {
        // Brief dim-pulse on ball to signal "ready to shoot"
        ball.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.6, duration: 0.12),
            SKAction.fadeAlpha(to: 1.0, duration: 0.12)
        ]))
    }

    override func didSimulatePhysics() {
        guard needsRespawn else { return }
        needsRespawn = false
        performRespawn()
    }

    // MARK: - Contact delegate

    func didBegin(_ contact: SKPhysicsContact) {
        let a = contact.bodyA.categoryBitMask
        let b = contact.bodyB.categoryBitMask
        let m = a | b
        guard m & Cat.ball != 0 else { return }

        if m & Cat.solid != 0 { solidContacts += 1 }
        if m & Cat.lava  != 0 { triggerDeath(); return }
        if m & Cat.laser != 0 { triggerDeath(); return }
        if m & Cat.bomb  != 0 {
            let bombNode = (a == Cat.bomb ? contact.bodyA.node : contact.bodyB.node)
            triggerBomb(node: bombNode)
            return
        }
        if m & Cat.hole != 0 { triggerWin(); return }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        let m = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if m & Cat.ball != 0 && m & Cat.solid != 0 {
            solidContacts = max(0, solidContacts - 1)
        }
    }

    // MARK: - Hazard death (lava / laser / abyss)

    private func triggerDeath() {
        guard !isDead, !hasWon else { return }
        isDead = true
        needsRespawn = true
        strokeCount += 1      // penalty stroke
        updateStrokeLabel()
        showMessage("Out of bounds! +1 penalty", duration: 1.4)

        // Explode ball off screen
        if let pb = ball.physicsBody { pb.velocity = .zero }
        ball.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 2.2, duration: 0.20),
                SKAction.fadeOut(withDuration: 0.20)
            ]),
            SKAction.removeFromParent()
        ]))
    }

    private func performRespawn() {
        isDead      = false
        isRolling   = false
        settleTimer = 0
        solidContacts = 0
        placeBall(at: lastSafePoint)
        // Snap camera to respawn position
        cameraNode.position = CGPoint(
            x: max(size.width  / 2, min(lastSafePoint.x, courseWidth - size.width  / 2)),
            y: max(size.height / 2, lastSafePoint.y + 80)
        )
    }

    // MARK: - Bomb explosion

    private func triggerBomb(node: SKNode?) {
        guard let bombNode = node, bombNode.parent != nil else { return }
        bombNode.physicsBody = nil   // disable further contacts

        // Particle burst
        for _ in 0..<20 {
            let particle = SKShapeNode(circleOfRadius: CGFloat.random(in: 2...6))
            particle.fillColor   = SKColor(hue: CGFloat.random(in: 0...0.12),
                                           saturation: 1, brightness: 1, alpha: 1)
            particle.strokeColor = .clear
            particle.position    = bombNode.position
            particle.zPosition   = 30
            addChild(particle)

            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: 250...600)
            let ppb = SKPhysicsBody(circleOfRadius: 3)
            ppb.affectedByGravity  = true
            ppb.collisionBitMask   = 0
            ppb.contactTestBitMask = 0
            ppb.velocity = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)
            particle.physicsBody = ppb
            particle.run(SKAction.sequence([
                SKAction.group([
                    SKAction.fadeOut(withDuration: 0.60),
                    SKAction.scale(to: 0.1, duration: 0.60)
                ]),
                SKAction.removeFromParent()
            ]))
        }

        // White flash ring
        let ring = SKShapeNode(circleOfRadius: 8)
        ring.fillColor = SKColor(white: 1, alpha: 0.9)
        ring.strokeColor = .clear
        ring.position  = bombNode.position
        ring.zPosition = 31
        addChild(ring)
        ring.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 6.0, duration: 0.28),
                SKAction.fadeOut(withDuration: 0.28)
            ]),
            SKAction.removeFromParent()
        ]))

        // Camera shake
        cameraNode.run(SKAction.sequence([
            SKAction.moveBy(x: -12, y:  7, duration: 0.04),
            SKAction.moveBy(x:  16, y: -10, duration: 0.04),
            SKAction.moveBy(x: -10, y:  8, duration: 0.04),
            SKAction.moveBy(x:   7, y: -6, duration: 0.04),
            SKAction.moveBy(x:  -4, y:  3, duration: 0.04),
            SKAction.moveBy(x:   3, y: -2, duration: 0.04)
        ]))

        // Fling ball with large random impulse (spec: dx random(-600,600), dy random(400,900))
        if let pb = ball.physicsBody {
            let dx = CGFloat.random(in: -600...600)
            let dy = CGFloat.random(in:  400...900)
            pb.velocity = CGVector(dx: dx, dy: dy)
            isRolling   = true
            settleTimer = 0
        }

        // Fade out bomb visual
        bombNode.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.12),
            SKAction.removeFromParent()
        ]))

        showMessage("BOOM!", duration: 0.9)
    }

    // MARK: - Win

    private func triggerWin() {
        guard !hasWon else { return }
        hasWon = true
        removeAimIndicator()
        if let pb = ball.physicsBody { pb.velocity = .zero }

        // Suck ball into hole
        ball.run(SKAction.group([
            SKAction.scale(to: 0.05, duration: 0.38),
            SKAction.fadeOut(withDuration: 0.38)
        ]))

        let delay = 0.45
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            if let cb = self.onWin { cb(); return }
            self.showWinOverlay()
        }
    }

    private func showWinOverlay() {
        let bg = SKSpriteNode(color: SKColor(white: 0, alpha: 0.82),
                              size: CGSize(width: 560, height: 280))
        bg.zPosition = 300
        bg.name      = "winOverlay"
        cameraNode.addChild(bg)

        let par = mapMode == .short ? 6 : 18
        let underPar = strokeCount <= par

        let title = SKLabelNode(text: underPar ? "HOLE IN \(strokeCount)! ★" : "HOLE COMPLETE!")
        title.fontName  = "AvenirNext-Bold"
        title.fontSize  = underPar ? 46 : 42
        title.fontColor = underPar ? .yellow : .white
        title.position  = CGPoint(x: 0, y: 75)
        bg.addChild(title)
        title.setScale(0.4)
        title.run(SKAction.sequence([
            SKAction.scale(to: 1.1, duration: 0.25),
            SKAction.scale(to: 1.0, duration: 0.10)
        ]))

        let sub = SKLabelNode(text: "\(strokeCount) stroke\(strokeCount == 1 ? "" : "s")  •  par \(par)")
        sub.fontName  = "AvenirNext-Regular"
        sub.fontSize  = 24
        sub.fontColor = .white
        sub.position  = CGPoint(x: 0, y: 20)
        bg.addChild(sub)

        if underPar {
            for i in -1...1 {
                let star = SKLabelNode(text: "★")
                star.fontSize  = 42
                star.fontColor = .yellow
                star.position  = CGPoint(x: CGFloat(i) * 64, y: -40)
                bg.addChild(star)
                star.setScale(0)
                star.alpha = 0
                star.run(SKAction.sequence([
                    SKAction.wait(forDuration: Double(i + 1) * 0.13),
                    SKAction.group([
                        SKAction.scale(to: 1.25, duration: 0.22),
                        SKAction.fadeIn(withDuration: 0.22)
                    ]),
                    SKAction.scale(to: 1.0, duration: 0.10)
                ]))
            }
        }

        let replay = SKLabelNode(text: "Tap to play again")
        replay.fontName  = "AvenirNext-Regular"
        replay.fontSize  = 20
        replay.fontColor = SKColor(white: 0.65, alpha: 1)
        replay.position  = CGPoint(x: 0, y: underPar ? -100 : -60)
        bg.addChild(replay)
    }

    private func showMessage(_ text: String, duration: TimeInterval) {
        msgLabel.text  = text
        msgLabel.alpha = 1
        msgLabel.removeAllActions()
        msgLabel.run(SKAction.sequence([
            SKAction.wait(forDuration: duration),
            SKAction.fadeOut(withDuration: 0.35)
        ]))
    }

    // MARK: - Aim indicator

    private func updateAimIndicator(dragPos: CGPoint) {
        guard let ballNode = ball else { return }
        removeAimIndicator()

        let ballPos = ballNode.position
        let dx   = dragPos.x - ballPos.x
        let dy   = dragPos.y - ballPos.y
        let dist = hypot(dx, dy)
        guard dist > 8 else { return }

        // Launch direction: opposite of drag vector
        let nx   = -dx / dist
        let ny   = -dy / dist
        let clamped = min(dist, maxDragDist)
        let power   = clamped / maxDragDist * maxImpulse   // pts/s

        let container = SKNode()
        container.zPosition = 50
        addChild(container)
        aimContainer = container

        // Dotted trajectory arc using accurate projectile physics:
        //   px(t) = ballPos.x + nx * power * t
        //   py(t) = ballPos.y + ny * power * t + 0.5 * gravity * t²
        // Step time scaled so dots spread nicely regardless of power level.
        let dotCount = 14
        let timeStep: CGFloat = 0.055         // seconds per dot interval
        for i in 1...dotCount {
            let t   = CGFloat(i) * timeStep
            let px  = ballPos.x + nx * power * t
            let py  = ballPos.y + ny * power * t + 0.5 * gravity * t * t
            let frac = CGFloat(i) / CGFloat(dotCount)  // 0→1
            let alpha = 1.0 - frac * 0.85
            let r = 4.0 * (1.0 - frac * 0.65)

            let dot = SKShapeNode(circleOfRadius: r)
            dot.fillColor   = SKColor(red: 1.0, green: 0.92, blue: 0.20, alpha: alpha)
            dot.strokeColor = .clear
            dot.position    = CGPoint(x: px, y: py)
            container.addChild(dot)
        }

        // Arrow head pointing in launch direction
        let arrowDist = min(clamped, 60) + 20
        let arrowPos  = CGPoint(x: ballPos.x + nx * arrowDist,
                                y: ballPos.y + ny * arrowDist)
        let arrowAngle = atan2(ny, nx)
        let arrow = SKShapeNode()
        let ap = CGMutablePath()
        ap.move(to: .zero)
        ap.addLine(to: CGPoint(x: -20, y:  9))
        ap.addLine(to: CGPoint(x: -12, y:  0))
        ap.addLine(to: CGPoint(x: -20, y: -9))
        ap.closeSubpath()
        arrow.path        = ap
        arrow.fillColor   = SKColor(red: 1.0, green: 0.92, blue: 0.20, alpha: 0.92)
        arrow.strokeColor = .clear
        arrow.position    = arrowPos
        arrow.zRotation   = arrowAngle
        container.addChild(arrow)

        // Power bar: line from ball back toward drag point, color shifts green→red
        let powerFrac = clamped / maxDragDist
        let barColor  = SKColor(
            red:   0.20 + 0.80 * powerFrac,
            green: 0.90 - 0.85 * powerFrac,
            blue:  0.10,
            alpha: 0.80
        )
        let barDist = clamped * 0.6
        let barPath = CGMutablePath()
        barPath.move(to: ballPos)
        barPath.addLine(to: CGPoint(x: ballPos.x - nx * barDist,
                                    y: ballPos.y - ny * barDist))
        let bar = SKShapeNode(path: barPath)
        bar.strokeColor = barColor
        bar.lineWidth   = 5
        container.addChild(bar)
    }

    private func removeAimIndicator() {
        aimContainer?.removeFromParent()
        aimContainer = nil
    }

    // MARK: - Launch

    private func launchBall(dragPos: CGPoint) {
        guard let ballNode = ball else { return }
        let ballPos = ballNode.position
        let dx   = dragPos.x - ballPos.x
        let dy   = dragPos.y - ballPos.y
        let dist = hypot(dx, dy)
        guard dist >= minDragSnap else { return }   // too small — ignore

        strokeCount += 1
        updateStrokeLabel()

        // Fade out the hint after the first shot
        if strokeCount == 1 {
            if let hint = cameraNode.childNode(withName: "hintLabel") {
                hint.run(SKAction.sequence([
                    SKAction.wait(forDuration: 2.5),
                    SKAction.fadeOut(withDuration: 0.6)
                ]))
            }
        }

        let clamped = min(dist, maxDragDist)
        let speed   = clamped / maxDragDist * maxImpulse   // pts/s
        let nx      = -dx / dist
        let ny      = -dy / dist

        if let pb = ballNode.physicsBody {
            // Apply as velocity (equivalent to impulse / mass with mass=1)
            pb.velocity = CGVector(dx: nx * speed, dy: ny * speed)
        }
        isRolling   = true
        settleTimer = 0
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }

        // Win screen tap → restart
        if hasWon {
            cameraNode.childNode(withName: "winOverlay")?.removeFromParent()
            restartGame()
            return
        }

        guard !isDead, !isRolling, ball != nil else { return }

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
        guard !isDead, !isRolling, !hasWon, ball != nil else { return }
        updateAimIndicator(dragPos: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer {
            removeAimIndicator()
            isTouchOnBall = false
            dragStart     = nil
        }
        guard isTouchOnBall, let touch = touches.first else { return }
        guard !isDead, !isRolling, !hasWon else { return }
        launchBall(dragPos: touch.location(in: self))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        removeAimIndicator()
        isTouchOnBall = false
        dragStart     = nil
    }

    // MARK: - Restart

    private func restartGame() {
        // Remove everything except the camera node
        for child in children where child !== cameraNode {
            child.removeFromParent()
        }
        cameraNode.removeAllChildren()

        hasWon        = false
        isDead        = false
        isRolling     = false
        strokeCount   = 0
        solidContacts = 0
        lastUpdateTime = 0
        settleTimer    = 0
        ball           = nil

        buildCourse()
        setupHUD()

        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }
}
