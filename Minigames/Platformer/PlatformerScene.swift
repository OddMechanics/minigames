import SpriteKit

class PlatformerScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Physics categories
    struct Cat {
        static let player: UInt32 = 1 << 0   // 1
        static let solid:  UInt32 = 1 << 1   // 2
        static let hazard: UInt32 = 1 << 2   // 4
        static let goal:   UInt32 = 1 << 3   // 8
    }

    // MARK: - State
    private var player: SKSpriteNode!
    private var cameraNode: SKCameraNode!

    private var moveDirection: CGFloat = 0
    private var groundContacts = 0
    private var isDead = false
    private var hasWon = false

    private let spawnPoint = CGPoint(x: 110, y: 130)
    private let playerSpeed:  CGFloat = 360
    private let jumpVelocity: CGFloat = 660

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        physicsWorld.gravity = CGVector(dx: 0, dy: -26)
        physicsWorld.contactDelegate = self
        backgroundColor = SKColor(red: 0.09, green: 0.08, blue: 0.18, alpha: 1)
        setupCamera()
        setupPlayer()
        buildLevel()
    }

    // MARK: - Setup

    private func setupCamera() {
        cameraNode = SKCameraNode()
        addChild(cameraNode)
        camera = cameraNode
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private func setupPlayer() {
        let sz = CGSize(width: 54, height: 54)

        // White square base
        player = SKSpriteNode(color: .white, size: sz)

        // Drawing.png on top
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

    private func buildLevel() {
        // ── Section 1: Tutorial (x 0–900) ─────────────────────────────────────
        ground(x: 350,  w: 700)
        platform(x: 420, y: 140, w: 160)
        platform(x: 600, y: 210, w: 140)
        platform(x: 770, y: 150, w: 140)
        spike(x: 280, onGround: true)

        // ── Section 2: Spike field (x 900–1550) ───────────────────────────────
        ground(x: 1200, w: 700)
        spike(x: 940,  onGround: true)
        spike(x: 1000, onGround: true)
        spike(x: 1060, onGround: true)
        spike(x: 1120, onGround: true)
        // Step-up platforms to navigate spikes
        platform(x: 920,  y: 145, w: 110)
        platform(x: 1060, y: 210, w: 110)
        platform(x: 1190, y: 150, w: 110)
        // First moving spike
        movingSpike(x: 1360, y: groundTop + 28, range: 200, horizontal: true)
        spike(x: 1480, onGround: true)
        spike(x: 1530, onGround: true)

        // ── Section 3: Lava pit 1 (x 1550–2200) ──────────────────────────────
        lava(x: 1875, w: 660)
        // Platforms to hop across
        platform(x: 1620, y: 175, w: 110)
        platform(x: 1750, y: 240, w: 100)
        platform(x: 1880, y: 185, w: 110)
        platform(x: 2020, y: 250, w: 110)
        platform(x: 2150, y: 175, w: 120)
        // Moving spike mid-lava
        movingSpike(x: 1870, y: 195, range: 110, horizontal: false) // vertical
        ground(x: 2380, w: 400)

        // ── Section 4: Moving spikes on ground (x 2200–3000) ─────────────────
        ground(x: 2680, w: 800)
        movingSpike(x: 2350, y: groundTop + 28, range: 180, horizontal: true)
        movingSpike(x: 2600, y: groundTop + 28, range: 160, horizontal: true)
        movingSpike(x: 2850, y: groundTop + 28, range: 140, horizontal: true)
        // Upper platform route
        platform(x: 2310, y: 200, w: 120)
        spike(x: 2310, onPlatformAt: 200)
        platform(x: 2500, y: 270, w: 120)
        platform(x: 2700, y: 200, w: 120)
        platform(x: 2880, y: 270, w: 120)
        spike(x: 2880, onPlatformAt: 270)

        // ── Section 5: Lava pit 2 – harder (x 3000–3900) ─────────────────────
        lava(x: 3380, w: 760)
        // Narrower platforms, vertical moving spikes
        platform(x: 3060, y: 160, w: 100)
        platform(x: 3190, y: 230, w:  90)
        platform(x: 3310, y: 170, w:  90)
        platform(x: 3440, y: 250, w:  90)
        platform(x: 3570, y: 170, w:  90)
        platform(x: 3700, y: 240, w: 100)
        platform(x: 3820, y: 170, w: 110)
        movingSpike(x: 3250, y: 190, range: 120, horizontal: false)
        movingSpike(x: 3510, y: 220, range: 140, horizontal: false)
        movingSpike(x: 3760, y: 195, range: 100, horizontal: false)
        ground(x: 3960, w: 240)

        // ── Section 6: Final gauntlet (x 3900–4600) ───────────────────────────
        ground(x: 4250, w: 700)
        spike(x: 4060, onGround: true)
        spike(x: 4120, onGround: true)
        spike(x: 4300, onGround: true)
        spike(x: 4360, onGround: true)
        movingSpike(x: 4180, y: groundTop + 28, range: 160, horizontal: true)
        movingSpike(x: 4450, y: groundTop + 28, range: 130, horizontal: true)
        platform(x: 4110, y: 180, w: 120)
        platform(x: 4310, y: 250, w: 120)
        platform(x: 4500, y: 190, w: 120)
        movingSpike(x: 4310, y: 270, range: 100, horizontal: false)

        // ── Goal ──────────────────────────────────────────────────────────────
        ground(x: 4750, w: 200)
        goal(x: 4750, y: groundTop + 50)

        // ── Lava abyss below everything ───────────────────────────────────────
        addAbyssLava(x: 2500, y: -55, w: 5000, h: 50)
    }

    // ── Convenience ground Y ──────────────────────────────────────────────────
    private let groundCenterY: CGFloat = 22
    private let groundHeight:  CGFloat = 44
    private var groundTop: CGFloat { groundCenterY + groundHeight / 2 }

    // MARK: - Builders

    private func ground(x: CGFloat, w: CGFloat) {
        addSolid(x: x, y: groundCenterY, w: w, h: groundHeight,
                 fill: SKColor(red: 0.28, green: 0.22, blue: 0.42, alpha: 1),
                 top:  SKColor(red: 0.50, green: 0.40, blue: 0.72, alpha: 1))
    }

    private func platform(x: CGFloat, y: CGFloat, w: CGFloat) {
        addSolid(x: x, y: y, w: w, h: 18,
                 fill: SKColor(red: 0.25, green: 0.35, blue: 0.55, alpha: 1),
                 top:  SKColor(red: 0.45, green: 0.60, blue: 0.85, alpha: 1))
    }

    private func addSolid(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                          fill: SKColor, top: SKColor) {
        let node = SKSpriteNode(color: fill, size: CGSize(width: w, height: h))
        node.position = CGPoint(x: x, y: y)

        let stripe = SKSpriteNode(color: top, size: CGSize(width: w, height: 4))
        stripe.position = CGPoint(x: 0, y: h / 2 - 2)
        node.addChild(stripe)

        let body = SKPhysicsBody(rectangleOf: node.size)
        body.isDynamic          = false
        body.friction           = 1.0
        body.categoryBitMask    = Cat.solid
        body.contactTestBitMask = Cat.player
        body.collisionBitMask   = Cat.player
        node.physicsBody = body
        addChild(node)
    }

    /// Spike sitting on the ground.
    private func spike(x: CGFloat, onGround: Bool) {
        makeSpikeNode(
            at: CGPoint(x: x, y: groundTop),
            color: SKColor(red: 0.95, green: 0.18, blue: 0.18, alpha: 1),
            stroke: SKColor(red: 1.0, green: 0.5, blue: 0.5, alpha: 1))
    }

    /// Spike sitting on an elevated platform (specified by platform center y).
    private func spike(x: CGFloat, onPlatformAt platformCenterY: CGFloat) {
        let top = platformCenterY + 9   // half of 18-pt platform height
        makeSpikeNode(
            at: CGPoint(x: x, y: top),
            color: SKColor(red: 0.95, green: 0.18, blue: 0.18, alpha: 1),
            stroke: SKColor(red: 1.0, green: 0.5, blue: 0.5, alpha: 1))
    }

    private func makeSpikeNode(at position: CGPoint, color: SKColor, stroke: SKColor) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -15, y: 0))
        path.addLine(to: CGPoint(x:  15, y: 0))
        path.addLine(to: CGPoint(x:   0, y: 30))
        path.closeSubpath()

        let node = SKShapeNode(path: path)
        node.fillColor   = color
        node.strokeColor = stroke
        node.lineWidth   = 1.5
        node.position    = position
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
        let path = CGMutablePath()
        if horizontal {
            path.move(to: CGPoint(x: -15, y: 0))
            path.addLine(to: CGPoint(x:  15, y: 0))
            path.addLine(to: CGPoint(x:   0, y: 30))
        } else {
            // Sideways spike for vertical movement
            path.move(to: CGPoint(x: -14, y: -14))
            path.addLine(to: CGPoint(x:  14, y: -14))
            path.addLine(to: CGPoint(x:   0, y:  16))
        }
        path.closeSubpath()

        let node = SKShapeNode(path: path)
        node.fillColor   = SKColor(red: 1.0, green: 0.45, blue: 0.0, alpha: 1)
        node.strokeColor = SKColor(red: 1.0, green: 0.75, blue: 0.3, alpha: 1)
        node.lineWidth   = 1.5
        node.position    = CGPoint(x: x, y: y)
        node.zPosition   = 5

        // Use circle body — reliable for moving hazards
        let body = SKPhysicsBody(circleOfRadius: 14)
        body.isDynamic          = false
        body.categoryBitMask    = Cat.hazard
        body.contactTestBitMask = Cat.player
        body.collisionBitMask   = 0
        node.physicsBody = body

        let speed: Double = horizontal ? Double(range) / 160.0 : Double(range) / 110.0
        let delta = horizontal ? CGVector(dx: range, dy: 0) : CGVector(dx: 0, dy: range)
        let go  = SKAction.moveBy(x: delta.dx, y: delta.dy, duration: speed)
        let back = go.reversed()
        node.run(SKAction.repeatForever(SKAction.sequence([go, back])))

        addChild(node)
    }

    private func addAbyssLava(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        lava(x: x, w: w, h: h, overrideY: y)
    }

    private func lava(x: CGFloat, w: CGFloat, h: CGFloat = 44, overrideY: CGFloat? = nil) {
        let y = overrideY ?? groundCenterY
        let node = SKSpriteNode(color: SKColor(red: 1.0, green: 0.28, blue: 0.0, alpha: 1),
                                size: CGSize(width: w, height: h))
        node.position = CGPoint(x: x, y: y)
        node.zPosition = 2

        // Pulsing glow
        let pulse = SKAction.sequence([
            SKAction.colorize(with: SKColor(red: 1.0, green: 0.55, blue: 0.05, alpha: 1),
                              colorBlendFactor: 1, duration: 0.45),
            SKAction.colorize(with: SKColor(red: 0.85, green: 0.12, blue: 0.0, alpha: 1),
                              colorBlendFactor: 1, duration: 0.45)
        ])
        node.run(SKAction.repeatForever(pulse))

        // Solid + deadly
        let body = SKPhysicsBody(rectangleOf: node.size)
        body.isDynamic          = false
        body.categoryBitMask    = Cat.hazard | Cat.solid
        body.contactTestBitMask = Cat.player
        body.collisionBitMask   = Cat.player
        node.physicsBody = body
        addChild(node)
    }

    private func goal(x: CGFloat, y: CGFloat) {
        // Tall golden portal
        let node = SKSpriteNode(color: SKColor(red: 1.0, green: 0.85, blue: 0.1, alpha: 1),
                                size: CGSize(width: 36, height: 72))
        node.position = CGPoint(x: x, y: y)
        node.zPosition = 5

        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.12, duration: 0.5),
            SKAction.scale(to: 0.90, duration: 0.5)
        ])
        node.run(SKAction.repeatForever(pulse))

        let label = SKLabelNode(text: "EXIT")
        label.fontName = "AvenirNext-Bold"
        label.fontSize = 14
        label.fontColor = .black
        label.verticalAlignmentMode = .center
        node.addChild(label)

        let body = SKPhysicsBody(rectangleOf: node.size)
        body.isDynamic          = false
        body.categoryBitMask    = Cat.goal
        body.contactTestBitMask = Cat.player
        body.collisionBitMask   = 0
        node.physicsBody = body
        addChild(node)
    }

    // MARK: - Game loop

    override func update(_ currentTime: TimeInterval) {
        guard !isDead, !hasWon, let body = player.physicsBody else { return }

        body.velocity.dx = moveDirection * playerSpeed

        // Camera: lead slightly ahead of player, clamp to level bounds
        let leadX = player.position.x + moveDirection * 80
        let targetX = max(size.width / 2, min(leadX, 4900))
        let targetY = max(size.height / 2, player.position.y + 60)
        cameraNode.position.x += (targetX - cameraNode.position.x) * 0.10
        cameraNode.position.y += (targetY - cameraNode.position.y) * 0.10
    }

    // MARK: - Contact

    func didBegin(_ contact: SKPhysicsContact) {
        let m = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if m & Cat.player != 0 && m & Cat.solid != 0  { groundContacts += 1 }
        if m & Cat.player != 0 && m & Cat.hazard != 0 { killPlayer() }
        if m & Cat.player != 0 && m & Cat.goal != 0   { triggerWin() }
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

        let flash = SKAction.sequence([
            SKAction.colorize(with: .red, colorBlendFactor: 0.9, duration: 0.06),
            SKAction.wait(forDuration: 0.28),
            SKAction.run { [weak self] in self?.respawn() }
        ])
        player.run(flash)
    }

    private func respawn() {
        isDead = false
        groundContacts = 0
        moveDirection = 0
        player.colorBlendFactor = 0
        player.position = spawnPoint
        player.physicsBody?.velocity = .zero

        // Snap camera back
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
        title.position = CGPoint(x: 0, y: 30)
        bg.addChild(title)

        let sub = SKLabelNode(text: "Tap to play again")
        sub.fontName = "AvenirNext-Regular"
        sub.fontSize = 24
        sub.fontColor = .white
        sub.position = CGPoint(x: 0, y: -32)
        bg.addChild(sub)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if hasWon { restartGame() }
    }

    private func restartGame() {
        cameraNode.removeAllChildren()
        hasWon = false

        let sz = CGSize(width: 54, height: 54)
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

    // MARK: - Controls (called from PlatformerView)

    func moveLeft()       { guard !hasWon else { return }; moveDirection = -1 }
    func moveRight()      { guard !hasWon else { return }; moveDirection =  1 }
    func stopHorizontal() { moveDirection =  0 }

    func jump() {
        guard isOnGround, !isDead, !hasWon else { return }
        player.physicsBody?.velocity.dy = jumpVelocity
        groundContacts = 0
    }
}
