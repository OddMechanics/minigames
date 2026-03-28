import SpriteKit

// ─────────────────────────────────────────────────────────────────────────────
// Physics note:
//   SpriteKit gravity is in m/s²; velocity is in pts/s; scale ≈ 150 pts/m.
//   gravity = -20  →  effective -3 000 pts/s²
//   jumpVelocity = 1 000 pts/s
//   → time-to-apex: 1000/3000 ≈ 0.33 s
//   → max jump height: 1000² / (2·3000) ≈ 167 pts
//   → max horizontal at playerSpeed 380: 2·0.33·380 ≈ 251 pts
//
//   groundTop = 44.  All platform heights & gaps are verified below.
// ─────────────────────────────────────────────────────────────────────────────

class PlatformerScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Categories
    struct Cat {
        static let player: UInt32 = 1 << 0
        static let solid:  UInt32 = 1 << 1
        static let hazard: UInt32 = 1 << 2
        static let goal:   UInt32 = 1 << 3
    }

    // MARK: - Constants
    // groundCenterY=22, groundHeight=44 → groundTop=44
    private let gndCY:  CGFloat = 22
    private let gndH:   CGFloat = 44
    private var gndTop: CGFloat { gndCY + gndH / 2 }   // 44

    private let playerSpeed:  CGFloat = 380
    private let jumpVelocity: CGFloat = 1_000
    private let spawnPoint = CGPoint(x: 110, y: 140)

    // MARK: - State
    private var player: SKSpriteNode!
    private var cameraNode: SKCameraNode!
    private var moveDirection: CGFloat = 0
    private var groundContacts = 0
    private var isDead = false
    private var hasWon = false

    // MARK: - Setup

    override func didMove(to view: SKView) {
        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self
        backgroundColor = SKColor(red: 0.09, green: 0.08, blue: 0.18, alpha: 1)
        setupCamera()
        setupPlayer()
        buildLevel()
    }

    private func setupCamera() {
        cameraNode = SKCameraNode()
        addChild(cameraNode)
        camera = cameraNode
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private func setupPlayer() {
        let sz = CGSize(width: 54, height: 54)
        player = SKSpriteNode(color: .white, size: sz)

        let drawing = SKSpriteNode(imageNamed: "Drawing")
        drawing.size = sz
        drawing.zPosition = 1
        player.addChild(drawing)

        player.position = spawnPoint
        player.zPosition = 10

        let body = SKPhysicsBody(rectangleOf: sz)
        body.allowsRotation     = false
        body.restitution        = 0
        body.friction           = 0
        body.linearDamping      = 0
        body.categoryBitMask    = Cat.player
        body.contactTestBitMask = Cat.solid | Cat.hazard | Cat.goal
        body.collisionBitMask   = Cat.solid
        player.physicsBody = body
        addChild(player)
    }

    // MARK: - Level
    //
    // Verified jump budget: max height ≈ 167 pts above takeoff surface.
    // Platform-to-platform height delta ≤ 70 pts (comfortable margin).
    // Horizontal edge-to-edge gap ≤ 120 pts.
    //
    // Legend: G=ground-top(44), P(y)=platform-top=y+9
    //
    private func buildLevel() {

        // ══ SECTION 1: Tutorial (x 0–820) ════════════════════════════════════
        // Ground covers x 0–820
        ground(x: 410, w: 820)
        // Spike near start forces player right
        spike(x: 220, surfaceY: gndTop)
        // Step up → step up → step down — introduces platform hopping
        // Plat A: top=99  Δ from G=55  ✓  horiz gap from ground edge: 0 (walk up)
        platform(x: 430, y: 90, w: 160)   // top 99
        // Plat B: top=139  Δ=40 ✓
        platform(x: 630, y: 130, w: 140)  // top 139
        // Plat C: top=99  Δ=40 ✓
        platform(x: 790, y: 90, w: 130)   // top 99

        // ══ SECTION 2: First spike field (x 820–1 380) ════════════════════════
        // Ground covers x 820–1 380
        ground(x: 1100, w: 560)
        // 3 spikes on ground — must jump to platform route above
        spike(x: 870, surfaceY: gndTop)
        spike(x: 930, surfaceY: gndTop)
        spike(x: 990, surfaceY: gndTop)
        // Platform route (walk/jump up over spikes):
        // Plat D: top=99  reachable from ground ✓  sits above spikes
        platform(x: 880, y: 90, w: 120)   // top 99
        // Plat E: top=139  Δ=40 ✓
        platform(x: 1050, y: 130, w: 110) // top 139
        // Plat F: top=89  Δ=50 down ✓
        platform(x: 1210, y: 80, w: 120)  // top 89  (near ground level)
        // First moving spike: horizontal patrol on ground, range 120
        // Player waits then dashes or jumps over; window ≥ 0.75 s
        movingSpike(x: 1310, y: gndTop + 28, range: 120, horizontal: true)

        // ══ SECTION 3: Lava pit 1 (x 1 380–1 960) ════════════════════════════
        // Lava covers x 1 410–1 910  (center 1660, w 500)
        lava(x: 1660, w: 500)
        // Ground resumes x 1 910–2 100  (center 2005, w 190)
        ground(x: 2005, w: 190)
        // Platform stepping-stones — all same height, evenly spaced
        // Each platform top = 99  Δ from adjacent = 0
        // Edge-to-edge horizontal gaps ≈ 60 pts  ✓
        // Plat 1 left edge 1377, right edge 1433; gap from gnd right(1300)=77 ✓
        platform(x: 1430, y: 90, w: 110)  // top 99; edge 1375–1485
        platform(x: 1580, y: 130, w: 100) // top 139; edge 1530–1630; gap 45 ✓; Δ=40 ✓
        platform(x: 1720, y: 90, w: 100)  // top 99;  edge 1670–1770; gap 40 ✓; Δ=40 ✓
        platform(x: 1860, y: 130, w: 100) // top 139; edge 1810–1910; gap 40 ✓; Δ=40 ✓
        platform(x: 1990, y: 90, w: 100)  // top 99;  edge 1940–2040; gap 30 ✓; Δ=40 ✓
        // Vertical moving spike crosses the second gap — timing challenge
        // Moves y 110–210, player is at ~y 116 on those platforms → dodge it
        movingSpike(x: 1720, y: 110, range: 90, horizontal: false)

        // ══ SECTION 4: Moving-spike gauntlet (x 2 100–2 840) ═════════════════
        // Ground covers x 2 100–2 840
        ground(x: 2470, w: 740)
        // Three horizontal moving spikes on ground — player can use upper route
        // or time dashes. Range 130–150, window ≈ 0.8 s each ✓
        movingSpike(x: 2200, y: gndTop + 28, range: 130, horizontal: true)
        movingSpike(x: 2500, y: gndTop + 28, range: 120, horizontal: true)
        movingSpike(x: 2730, y: gndTop + 28, range: 100, horizontal: true)
        // Upper route: three platforms the player can hop along above the spikes
        // All reachable from ground (Δ ≤ 75 pts) ✓
        platform(x: 2230, y: 110, w: 130)  // top 119; Δ from G=75 ✓
        platform(x: 2450, y: 150, w: 110)  // top 159; Δ=40 ✓
        platform(x: 2680, y: 110, w: 130)  // top 119; Δ=40 ✓
        // Spike ON one platform to prevent camping
        spike(x: 2450, surfaceY: 150 + 9)  // sits on platform top at y=159

        // ══ SECTION 5: Lava pit 2 — harder (x 2 840–3 640) ══════════════════
        // Lava covers x 2 870–3 590  (center 3230, w 720)
        lava(x: 3230, w: 720)
        // Ground resumes x 3 590–3 760  (center 3675, w 170)
        ground(x: 3675, w: 170)
        // Narrower platforms, alternating heights — no room to hesitate
        // Edge-to-edge gaps ≈ 50–70 pts ✓   Height deltas = 40 pts ✓
        platform(x: 2900, y: 100, w: 100)  // top 109; edge 2850–2950
        platform(x: 3040, y: 140, w:  90)  // top 149; edge 2995–3085; gap 45 ✓
        platform(x: 3170, y: 100, w:  90)  // top 109; edge 3125–3215; gap 40 ✓
        platform(x: 3300, y: 140, w:  90)  // top 149; edge 3255–3345; gap 40 ✓
        platform(x: 3430, y: 100, w:  90)  // top 109; edge 3385–3475; gap 40 ✓
        platform(x: 3560, y: 140, w: 100)  // top 149; edge 3510–3610; gap 35 ✓
        // Two vertical moving spikes in the middle gaps
        movingSpike(x: 3100, y: 110, range: 80, horizontal: false)
        movingSpike(x: 3370, y: 110, range: 80, horizontal: false)

        // ══ SECTION 6: Final gauntlet (x 3 760–4 360) ════════════════════════
        // Ground covers x 3 760–4 360
        ground(x: 4060, w: 600)
        // Dense spikes + two crossing moving spikes — must use platforms
        spike(x: 3830, surfaceY: gndTop)
        spike(x: 3890, surfaceY: gndTop)
        spike(x: 4100, surfaceY: gndTop)
        spike(x: 4160, surfaceY: gndTop)
        movingSpike(x: 3970, y: gndTop + 28, range: 150, horizontal: true)
        movingSpike(x: 4250, y: gndTop + 28, range: 110, horizontal: true)
        // Upper platform route
        platform(x: 3880, y: 110, w: 120)  // top 119; Δ from G=75 ✓
        platform(x: 4080, y: 150, w: 110)  // top 159; Δ=40 ✓
        platform(x: 4270, y: 110, w: 110)  // top 119; Δ=40 ✓
        // Vertical moving spike to block easy camping on the second platform
        movingSpike(x: 4080, y: 160, range: 80, horizontal: false)

        // ══ GOAL ══════════════════════════════════════════════════════════════
        // Safe landing pad, then the exit portal
        ground(x: 4560, w: 200)
        goal(x: 4560, y: gndTop + 46)

        // ══ ABYSS: lava floor beneath all gaps ════════════════════════════════
        // Sensor-only (hazard, no solid) so player falls through and dies
        addNode(abyssLava(x: 2500, y: -50, w: 5000, h: 60))
    }

    // MARK: - Builders

    private func ground(x: CGFloat, w: CGFloat) {
        let fill   = SKColor(red: 0.28, green: 0.22, blue: 0.44, alpha: 1)
        let stripe = SKColor(red: 0.50, green: 0.40, blue: 0.74, alpha: 1)
        addSolid(x: x, y: gndCY, w: w, h: gndH, fill: fill, topStripe: stripe)
    }

    private func platform(x: CGFloat, y: CGFloat, w: CGFloat) {
        let fill   = SKColor(red: 0.22, green: 0.34, blue: 0.54, alpha: 1)
        let stripe = SKColor(red: 0.42, green: 0.60, blue: 0.86, alpha: 1)
        addSolid(x: x, y: y, w: w, h: 18, fill: fill, topStripe: stripe)
    }

    private func addSolid(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                           fill: SKColor, topStripe: SKColor) {
        let node = SKSpriteNode(color: fill, size: CGSize(width: w, height: h))
        node.position = CGPoint(x: x, y: y)

        let top = SKSpriteNode(color: topStripe, size: CGSize(width: w, height: 4))
        top.position = CGPoint(x: 0, y: h / 2 - 2)
        node.addChild(top)

        let body = SKPhysicsBody(rectangleOf: node.size)
        body.isDynamic          = false
        body.friction           = 1.0
        body.categoryBitMask    = Cat.solid
        body.contactTestBitMask = Cat.player
        body.collisionBitMask   = Cat.player
        node.physicsBody = body
        addChild(node)
    }

    /// Static spike. `surfaceY` is the y of the surface it sits on (e.g. gndTop or platform top).
    private func spike(x: CGFloat, surfaceY: CGFloat) {
        let path = spikePath(halfBase: 15, height: 30)
        let node = SKShapeNode(path: path)
        node.fillColor   = SKColor(red: 0.95, green: 0.18, blue: 0.18, alpha: 1)
        node.strokeColor = SKColor(red: 1.0,  green: 0.50, blue: 0.50, alpha: 1)
        node.lineWidth   = 1.5
        node.position    = CGPoint(x: x, y: surfaceY)
        node.zPosition   = 5

        let body = SKPhysicsBody(polygonFrom: path)
        body.isDynamic          = false
        body.categoryBitMask    = Cat.hazard
        body.contactTestBitMask = Cat.player
        body.collisionBitMask   = 0
        node.physicsBody = body
        addChild(node)
    }

    private func movingSpike(x: CGFloat, y: CGFloat, range: CGFloat, horizontal: Bool) {
        let path: CGPath
        if horizontal {
            path = spikePath(halfBase: 15, height: 30)
        } else {
            // Sideways-pointing for vertical mover
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -14, y: -14))
            p.addLine(to: CGPoint(x:  14, y: -14))
            p.addLine(to: CGPoint(x:   0, y:  16))
            p.closeSubpath()
            path = p
        }

        let node = SKShapeNode(path: path)
        node.fillColor   = SKColor(red: 1.0, green: 0.45, blue: 0.0, alpha: 1)
        node.strokeColor = SKColor(red: 1.0, green: 0.75, blue: 0.3, alpha: 1)
        node.lineWidth   = 1.5
        node.position    = CGPoint(x: x, y: y)
        node.zPosition   = 5

        let body = SKPhysicsBody(circleOfRadius: 13)
        body.isDynamic          = false
        body.categoryBitMask    = Cat.hazard
        body.contactTestBitMask = Cat.player
        body.collisionBitMask   = 0
        node.physicsBody = body

        let seconds = Double(range) / (horizontal ? 155 : 105)
        let delta: CGVector = horizontal ? CGVector(dx: range, dy: 0) : CGVector(dx: 0, dy: range)
        let go   = SKAction.moveBy(x: delta.dx, y: delta.dy, duration: seconds)
        node.run(SKAction.repeatForever(SKAction.sequence([go, go.reversed()])))

        addChild(node)
    }

    private func lava(x: CGFloat, w: CGFloat) {
        let node = SKSpriteNode(color: SKColor(red: 1.0, green: 0.28, blue: 0.0, alpha: 1),
                                size: CGSize(width: w, height: gndH))
        node.position = CGPoint(x: x, y: gndCY)
        node.zPosition = 2
        node.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.colorize(with: SKColor(red: 1.0, green: 0.55, blue: 0.05, alpha: 1),
                              colorBlendFactor: 1, duration: 0.45),
            SKAction.colorize(with: SKColor(red: 0.85, green: 0.12, blue: 0.0, alpha: 1),
                              colorBlendFactor: 1, duration: 0.45)
        ])))
        let body = SKPhysicsBody(rectangleOf: node.size)
        body.isDynamic          = false
        body.categoryBitMask    = Cat.hazard | Cat.solid
        body.contactTestBitMask = Cat.player
        body.collisionBitMask   = Cat.player
        node.physicsBody = body
        addChild(node)
    }

    private func abyssLava(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> SKSpriteNode {
        let node = SKSpriteNode(color: SKColor(red: 0.8, green: 0.1, blue: 0.0, alpha: 1),
                                size: CGSize(width: w, height: h))
        node.position = CGPoint(x: x, y: y)
        node.zPosition = 1
        let body = SKPhysicsBody(rectangleOf: node.size)
        body.isDynamic          = false
        body.categoryBitMask    = Cat.hazard
        body.contactTestBitMask = Cat.player
        body.collisionBitMask   = 0   // sensor — player falls through, contact fires
        node.physicsBody = body
        return node
    }

    private func addNode(_ node: SKNode) { addChild(node) }

    private func goal(x: CGFloat, y: CGFloat) {
        let node = SKSpriteNode(color: SKColor(red: 1.0, green: 0.85, blue: 0.1, alpha: 1),
                                size: CGSize(width: 38, height: 72))
        node.position = CGPoint(x: x, y: y)
        node.zPosition = 5
        node.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scale(to: 1.12, duration: 0.45),
            SKAction.scale(to: 0.90, duration: 0.45)
        ])))
        let lbl = SKLabelNode(text: "EXIT")
        lbl.fontName = "AvenirNext-Bold"
        lbl.fontSize = 13
        lbl.fontColor = .black
        lbl.verticalAlignmentMode = .center
        node.addChild(lbl)
        let body = SKPhysicsBody(rectangleOf: node.size)
        body.isDynamic          = false
        body.categoryBitMask    = Cat.goal
        body.contactTestBitMask = Cat.player
        body.collisionBitMask   = 0
        node.physicsBody = body
        addChild(node)
    }

    // Convex upward-pointing triangle with base at y=0
    private func spikePath(halfBase: CGFloat, height: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -halfBase, y: 0))
        p.addLine(to: CGPoint(x:  halfBase, y: 0))
        p.addLine(to: CGPoint(x:  0, y: height))
        p.closeSubpath()
        return p
    }

    // MARK: - Game loop

    override func update(_ currentTime: TimeInterval) {
        guard !isDead, !hasWon, let body = player.physicsBody else { return }

        body.velocity.dx = moveDirection * playerSpeed

        // Camera: slight lead ahead, clamped to level
        let leadX  = player.position.x + moveDirection * 90
        let targetX = max(size.width / 2, min(leadX, 4710))
        let targetY = max(size.height / 2, player.position.y + 60)
        cameraNode.position.x += (targetX - cameraNode.position.x) * 0.10
        cameraNode.position.y += (targetY - cameraNode.position.y) * 0.10
    }

    // MARK: - Contact

    func didBegin(_ contact: SKPhysicsContact) {
        let m = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if m & Cat.player != 0 && m & Cat.solid  != 0 { groundContacts += 1 }
        if m & Cat.player != 0 && m & Cat.hazard != 0 { killPlayer() }
        if m & Cat.player != 0 && m & Cat.goal   != 0 { triggerWin() }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        let m = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if m & Cat.player != 0 && m & Cat.solid != 0 {
            groundContacts = max(0, groundContacts - 1)
        }
    }

    private var isOnGround: Bool { groundContacts > 0 }

    // MARK: - Death & Win

    private func killPlayer() {
        guard !isDead else { return }
        isDead = true
        player.physicsBody?.velocity = .zero
        player.run(SKAction.sequence([
            SKAction.colorize(with: .red, colorBlendFactor: 0.9, duration: 0.06),
            SKAction.wait(forDuration: 0.28),
            SKAction.run { [weak self] in self?.respawn() }
        ]))
    }

    private func respawn() {
        isDead = false
        groundContacts = 0
        moveDirection  = 0
        player.colorBlendFactor = 0
        player.position = spawnPoint
        player.physicsBody?.velocity = .zero
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private func triggerWin() {
        guard !hasWon else { return }
        hasWon = true
        player.physicsBody?.velocity = .zero
        player.physicsBody = nil

        let bg = SKSpriteNode(color: SKColor(white: 0, alpha: 0.75),
                              size: CGSize(width: 520, height: 220))
        bg.zPosition = 100
        cameraNode.addChild(bg)

        let title = SKLabelNode(text: "YOU WIN!")
        title.fontName = "AvenirNext-Bold"
        title.fontSize = 52
        title.fontColor = .yellow
        title.position = CGPoint(x: 0, y: 32)
        bg.addChild(title)

        let sub = SKLabelNode(text: "Tap to play again")
        sub.fontName = "AvenirNext-Regular"
        sub.fontSize = 24
        sub.fontColor = .white
        sub.position = CGPoint(x: 0, y: -28)
        bg.addChild(sub)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if hasWon { restartGame() }
    }

    private func restartGame() {
        cameraNode.removeAllChildren()
        hasWon = false
        let sz   = CGSize(width: 54, height: 54)
        let body = SKPhysicsBody(rectangleOf: sz)
        body.allowsRotation     = false
        body.restitution        = 0
        body.friction           = 0
        body.linearDamping      = 0
        body.categoryBitMask    = Cat.player
        body.contactTestBitMask = Cat.solid | Cat.hazard | Cat.goal
        body.collisionBitMask   = Cat.solid
        player.physicsBody = body
        respawn()
    }

    // MARK: - Controls

    func moveLeft()       { guard !hasWon else { return }; moveDirection = -1 }
    func moveRight()      { guard !hasWon else { return }; moveDirection =  1 }
    func stopHorizontal() { moveDirection = 0 }

    func jump() {
        guard isOnGround, !isDead, !hasWon else { return }
        player.physicsBody?.velocity.dy = jumpVelocity
        groundContacts = 0
    }
}
