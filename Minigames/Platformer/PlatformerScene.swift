import SpriteKit

// Physics note (SpriteKit scale ≈ 150 pts/m):
//   gravity -20 → -3 000 pts/s² effective
//   jumpVelocity 1 000 pts/s → apex ≈ 167 pts, range ≈ 251 pts
//   All platform height Δ ≤ 70 pts, horizontal gaps ≤ 120 pts (verified)

class PlatformerScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Categories
    struct Cat {
        static let player: UInt32 = 1 << 0
        static let solid:  UInt32 = 1 << 1
        static let hazard: UInt32 = 1 << 2
        static let goal:   UInt32 = 1 << 3
    }

    // MARK: - Constants
    private let gndCY:  CGFloat = 22
    private let gndH:   CGFloat = 44
    private var gndTop: CGFloat { gndCY + gndH / 2 }   // 44

    private let playerSpeed:  CGFloat = 380
    private let jumpVelocity: CGFloat = 1_000
    private let spawnPoint = CGPoint(x: 110, y: 140)
    private let coyoteTime: Double = 0.10   // seconds after leaving ground, jump still allowed

    // MARK: - Marathon callbacks (optional; used by MarathonView)
    var onWin:  (() -> Void)?
    var onLose: (() -> Void)?
    /// Deaths allowed before onLose fires (0 = disabled)
    var marathonLives: Int = 0

    // MARK: - State
    private var player: SKSpriteNode!
    private var cameraNode: SKCameraNode!
    private var moveDirection: CGFloat = 0
    private var groundContacts = 0
    private var lastGroundedTime: Double = -1
    private var lastUpdateTime:   Double = 0
    private var invincibleUntil:  Double = 0
    private var isDead = false
    private var hasWon = false
    private var hasBuiltLevel = false   // build level exactly once per scene instance
    private var needsRespawn  = false   // deferred to didSimulatePhysics so physics can't undo the teleport
    private var deathCount    = 0

    // MARK: - Computed ground check (with coyote time)
    private var isOnGround: Bool {
        groundContacts > 0 || (lastUpdateTime - lastGroundedTime < coyoteTime)
    }

    // MARK: - Setup

    override func didMove(to view: SKView) {
        isPaused = false
        guard !hasBuiltLevel else { return }
        hasBuiltLevel = true
        physicsWorld.gravity = CGVector(dx: 0, dy: -20)
        physicsWorld.contactDelegate = self
        backgroundColor = SKColor(red: 0.09, green: 0.08, blue: 0.18, alpha: 1)
        setupCamera()
        setupPlayer()
        buildLevel()
    }

    override func willMove(from view: SKView) {
        isPaused = true
    }

    private func setupCamera() {
        cameraNode = SKCameraNode()
        addChild(cameraNode)
        camera = cameraNode
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private func setupPlayer() {
        let sz = CGSize(width: 54, height: 54)
        // Clear sprite carries physics; visual is a rounded-rect shape child
        player = SKSpriteNode(color: .clear, size: sz)

        let bg = SKShapeNode(rectOf: sz, cornerRadius: 10)
        bg.fillColor   = .white
        bg.strokeColor = .black
        bg.lineWidth   = 4
        bg.zPosition   = 0
        player.addChild(bg)

        let drawing = SKSpriteNode(imageNamed: "Drawing")
        drawing.size      = CGSize(width: 46, height: 46)
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
    private func buildLevel() {

        // ══ SECTION 1: Tutorial (x 0–820) ════════════════════════════════════
        ground(x: 410, w: 820)
        spike(x: 220, surfaceY: gndTop)
        platform(x: 430, y: 90, w: 160)
        platform(x: 630, y: 130, w: 140)
        platform(x: 790, y: 90, w: 130)

        // ══ SECTION 2: First spike field (x 820–1 380) ════════════════════════
        ground(x: 1100, w: 560)
        spike(x: 870, surfaceY: gndTop)
        spike(x: 930, surfaceY: gndTop)
        spike(x: 990, surfaceY: gndTop)
        platform(x: 880, y: 90, w: 120)
        platform(x: 1050, y: 130, w: 110)
        platform(x: 1210, y: 80, w: 120)
        movingSpike(x: 1310, y: gndTop + 28, range: 120, horizontal: true)

        // ══ SECTION 3: Lava pit 1 (x 1 380–1 960) ════════════════════════════
        lava(x: 1660, w: 500)
        ground(x: 2005, w: 190)
        platform(x: 1430, y: 90, w: 110)
        platform(x: 1580, y: 130, w: 100)
        platform(x: 1720, y: 90, w: 100)
        platform(x: 1860, y: 130, w: 100)
        platform(x: 1990, y: 90, w: 100)
        movingSpike(x: 1720, y: 110, range: 90, horizontal: false)

        // ══ SECTION 4: Moving-spike gauntlet (x 2 100–2 840) ═════════════════
        ground(x: 2470, w: 740)
        movingSpike(x: 2200, y: gndTop + 28, range: 130, horizontal: true)
        movingSpike(x: 2500, y: gndTop + 28, range: 120, horizontal: true)
        movingSpike(x: 2730, y: gndTop + 28, range: 100, horizontal: true)
        platform(x: 2230, y: 110, w: 130)
        platform(x: 2450, y: 150, w: 110)
        platform(x: 2680, y: 110, w: 130)
        spike(x: 2450, surfaceY: 150 + 9)

        // ══ SECTION 5: Lava pit 2 — harder (x 2 840–3 640) ══════════════════
        lava(x: 3230, w: 720)
        ground(x: 3675, w: 170)
        platform(x: 2900, y: 100, w: 100)
        platform(x: 3040, y: 140, w:  90)
        platform(x: 3170, y: 100, w:  90)
        platform(x: 3300, y: 140, w:  90)
        platform(x: 3430, y: 100, w:  90)
        platform(x: 3560, y: 140, w: 100)
        movingSpike(x: 3100, y: 110, range: 80, horizontal: false)
        movingSpike(x: 3370, y: 110, range: 80, horizontal: false)

        // ══ SECTION 6: Final gauntlet (x 3 760–4 360) ════════════════════════
        ground(x: 4060, w: 600)
        spike(x: 3830, surfaceY: gndTop)
        spike(x: 3890, surfaceY: gndTop)
        spike(x: 4100, surfaceY: gndTop)
        spike(x: 4160, surfaceY: gndTop)
        movingSpike(x: 3970, y: gndTop + 28, range: 150, horizontal: true)
        movingSpike(x: 4250, y: gndTop + 28, range: 110, horizontal: true)
        platform(x: 3880, y: 110, w: 120)
        platform(x: 4080, y: 150, w: 110)
        platform(x: 4270, y: 110, w: 110)
        movingSpike(x: 4080, y: 160, range: 80, horizontal: false)

        // ══ GOAL ══════════════════════════════════════════════════════════════
        ground(x: 4560, w: 200)
        goal(x: 4560, y: gndTop + 46)

        // ══ ABYSS ═════════════════════════════════════════════════════════════
        let abyss = SKSpriteNode(color: SKColor(red: 0.8, green: 0.1, blue: 0.0, alpha: 1),
                                 size: CGSize(width: 5000, height: 60))
        abyss.position = CGPoint(x: 2500, y: -50)
        abyss.zPosition = 1
        let ab = SKPhysicsBody(rectangleOf: abyss.size)
        ab.isDynamic = false
        ab.categoryBitMask    = Cat.hazard
        ab.contactTestBitMask = Cat.player
        ab.collisionBitMask   = 0
        abyss.physicsBody = ab
        addChild(abyss)
    }

    // MARK: - Builders

    private func ground(x: CGFloat, w: CGFloat) {
        addSolid(x: x, y: gndCY, w: w, h: gndH,
                 fill:   SKColor(red: 0.28, green: 0.22, blue: 0.44, alpha: 1),
                 stripe: SKColor(red: 0.50, green: 0.40, blue: 0.74, alpha: 1))
    }

    private func platform(x: CGFloat, y: CGFloat, w: CGFloat) {
        addSolid(x: x, y: y, w: w, h: 18,
                 fill:   SKColor(red: 0.22, green: 0.34, blue: 0.54, alpha: 1),
                 stripe: SKColor(red: 0.42, green: 0.60, blue: 0.86, alpha: 1))
    }

    private func addSolid(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                           fill: SKColor, stripe: SKColor) {
        let node = SKSpriteNode(color: fill, size: CGSize(width: w, height: h))
        node.position = CGPoint(x: x, y: y)
        let top = SKSpriteNode(color: stripe, size: CGSize(width: w, height: 4))
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
        let go = SKAction.moveBy(x: delta.dx, y: delta.dy, duration: seconds)
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
        lbl.fontName = "AvenirNext-Bold"; lbl.fontSize = 13
        lbl.fontColor = .black; lbl.verticalAlignmentMode = .center
        node.addChild(lbl)
        let body = SKPhysicsBody(rectangleOf: node.size)
        body.isDynamic = false
        body.categoryBitMask    = Cat.goal
        body.contactTestBitMask = Cat.player
        body.collisionBitMask   = 0
        node.physicsBody = body
        addChild(node)
    }

    private func spikePath(halfBase: CGFloat, height: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -halfBase, y: 0))
        p.addLine(to: CGPoint(x: halfBase, y: 0))
        p.addLine(to: CGPoint(x: 0, y: height))
        p.closeSubpath()
        return p
    }

    // MARK: - Game loop

    override func update(_ currentTime: TimeInterval) {
        lastUpdateTime = currentTime
        if groundContacts > 0 { lastGroundedTime = currentTime }

        guard !isDead, !hasWon, let body = player.physicsBody else { return }
        body.velocity.dx = moveDirection * playerSpeed

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
        if m & Cat.player != 0 && m & Cat.hazard != 0 {
            guard !isDead, !hasWon, lastUpdateTime > invincibleUntil else { return }
            isDead = true
            needsRespawn = true   // actual teleport deferred to didSimulatePhysics
        }
        if m & Cat.player != 0 && m & Cat.goal   != 0 { triggerWin() }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        let m = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if m & Cat.player != 0 && m & Cat.solid != 0 {
            groundContacts = max(0, groundContacts - 1)
        }
    }

    // MARK: - Death & Win

    // Called after physics simulation has finished syncing body positions to nodes.
    // Safe to teleport the player here — the physics engine won't override it this frame.
    override func didSimulatePhysics() {
        guard needsRespawn else { return }
        needsRespawn = false
        player.physicsBody?.velocity = .zero
        respawn()
        // Flash the shape child (the clear sprite itself can't colorize visually)
        if let bg = player.children.first(where: { $0 is SKShapeNode }) as? SKShapeNode {
            bg.run(SKAction.sequence([
                SKAction.run { bg.fillColor = SKColor(red: 1, green: 0.2, blue: 0.2, alpha: 1) },
                SKAction.wait(forDuration: 0.15),
                SKAction.run { bg.fillColor = .white }
            ]))
        }
        // Marathon lose condition
        if marathonLives > 0 {
            deathCount += 1
            if deathCount >= marathonLives {
                DispatchQueue.main.async { self.onLose?() }
            }
        }
    }

    private func respawn() {
        isDead = false
        groundContacts = 0
        lastGroundedTime = -1
        moveDirection    = 0
        player.position  = spawnPoint
        player.physicsBody?.velocity = .zero
        invincibleUntil  = lastUpdateTime + 0.25   // brief invincibility
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private func triggerWin() {
        guard !hasWon else { return }
        hasWon = true
        player.physicsBody?.velocity = .zero
        player.physicsBody = nil

        if onWin != nil {
            DispatchQueue.main.async { self.onWin?() }
            return
        }

        let bg = SKSpriteNode(color: SKColor(white: 0, alpha: 0.75),
                              size: CGSize(width: 520, height: 220))
        bg.zPosition = 100
        cameraNode.addChild(bg)

        let title = SKLabelNode(text: "YOU WIN!")
        title.fontName = "AvenirNext-Bold"; title.fontSize = 52
        title.fontColor = .yellow; title.position = CGPoint(x: 0, y: 32)
        bg.addChild(title)

        let sub = SKLabelNode(text: "Tap to play again")
        sub.fontName = "AvenirNext-Regular"; sub.fontSize = 24
        sub.fontColor = .white; sub.position = CGPoint(x: 0, y: -28)
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
        body.restitution        = 0; body.friction = 0; body.linearDamping = 0
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
        groundContacts   = 0
        lastGroundedTime = -1   // consume coyote time
    }
}
