import SpriteKit

// ─────────────────────────────────────────────────────────────────────────────
// Rocket game:
//   • Steer a rocket (tilt / arrow keys) through space
//   • Avoid randomly spawning rocks
//   • Land on moving planets to collect ore (bigger planet = more ore)
//   • 20 ore → win
// ─────────────────────────────────────────────────────────────────────────────

final class RocketScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Categories
    private struct Cat {
        static let rocket: UInt32 = 1 << 0
        static let rock:   UInt32 = 1 << 1
        static let planet: UInt32 = 1 << 2
    }

    // MARK: - Constants
    private let oreGoal = 20
    private let thrustForce: CGFloat  = 380
    private let rotateSpeed: CGFloat  = 2.2   // rad/s

    // MARK: - Marathon callbacks
    var onWin:  (() -> Void)?
    var onLose: (() -> Void)?

    // MARK: - State
    private var rocket: SKSpriteNode!
    private var exhaustEmitter: SKEmitterNode?
    private var ore = 0
    private var hasWon = false
    private var isDead = false
    private var needsRespawn = false
    private var hasBuilt = false
    private var thrustOn = false
    private var rotateDir: CGFloat = 0   // -1 left, 0 none, +1 right
    private var oreLabel: SKLabelNode!
    private var winOverlay: SKNode?
    private var lastRockSpawn: TimeInterval = 0

    // MARK: - Setup

    override func didMove(to view: SKView) {
        isPaused = false
        guard !hasBuilt else { return }
        hasBuilt = true
        backgroundColor = SKColor(red: 0.03, green: 0.02, blue: 0.12, alpha: 1)
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        addStars()
        setupHUD()
        buildRocket()
        spawnPlanet(x: size.width * 0.35, y: size.height * 0.22, radius: 60, ore: 5)
        spawnPlanet(x: size.width * 0.70, y: size.height * 0.65, radius: 90, ore: 8)
        spawnPlanet(x: size.width * 0.15, y: size.height * 0.75, radius: 45, ore: 3)
    }

    override func willMove(from view: SKView) {
        isPaused = true
    }

    // MARK: - Stars background

    private func addStars() {
        for _ in 0..<140 {
            let s = SKShapeNode(circleOfRadius: CGFloat.random(in: 0.5...2))
            s.fillColor = SKColor(white: CGFloat.random(in: 0.6...1), alpha: CGFloat.random(in: 0.4...1))
            s.strokeColor = .clear
            s.position = CGPoint(x: CGFloat.random(in: 0...size.width),
                                 y: CGFloat.random(in: 0...size.height))
            s.zPosition = -10
            addChild(s)
        }
    }

    // MARK: - HUD

    private func setupHUD() {
        oreLabel = SKLabelNode(text: "Ore: 0 / \(oreGoal)")
        oreLabel.fontName = "AvenirNext-Bold"
        oreLabel.fontSize = 22
        oreLabel.fontColor = SKColor(red: 0.9, green: 0.85, blue: 0.3, alpha: 1)
        oreLabel.horizontalAlignmentMode = .left
        oreLabel.position = CGPoint(x: 20, y: size.height - 48)
        oreLabel.zPosition = 100
        addChild(oreLabel)

        let hint = SKLabelNode(text: "Land on planets to collect ore")
        hint.fontName = "AvenirNext-Regular"
        hint.fontSize = 14
        hint.fontColor = SKColor(white: 0.6, alpha: 1)
        hint.horizontalAlignmentMode = .left
        hint.position = CGPoint(x: 20, y: size.height - 70)
        hint.zPosition = 100
        addChild(hint)
    }

    private func updateOreLabel() {
        oreLabel.text = "Ore: \(ore) / \(oreGoal)"
    }

    // MARK: - Rocket construction

    private func buildRocket() {
        let rocketNode = SKNode()
        rocketNode.position = CGPoint(x: size.width / 2, y: size.height * 0.4)
        rocketNode.zPosition = 10

        // Body
        let body = SKShapeNode(rectOf: CGSize(width: 22, height: 50), cornerRadius: 8)
        body.fillColor   = SKColor(white: 0.88, alpha: 1)
        body.strokeColor = SKColor(white: 0.5, alpha: 1)
        body.lineWidth   = 1.5
        addTo(rocketNode, body)

        // Nose cone
        let nosePath = CGMutablePath()
        nosePath.move(to: CGPoint(x: -11, y: 20))
        nosePath.addLine(to: CGPoint(x:  11, y: 20))
        nosePath.addLine(to: CGPoint(x:   0, y: 38))
        nosePath.closeSubpath()
        let nose = SKShapeNode(path: nosePath)
        nose.fillColor   = SKColor(red: 0.85, green: 0.15, blue: 0.15, alpha: 1)
        nose.strokeColor = .clear
        addTo(rocketNode, nose)

        // Left fin
        let lfPath = CGMutablePath()
        lfPath.move(to: CGPoint(x: -11, y: -20))
        lfPath.addLine(to: CGPoint(x: -22, y: -36))
        lfPath.addLine(to: CGPoint(x: -11, y: -12))
        lfPath.closeSubpath()
        let lf = SKShapeNode(path: lfPath)
        lf.fillColor   = SKColor(red: 0.7, green: 0.15, blue: 0.15, alpha: 1)
        lf.strokeColor = .clear
        addTo(rocketNode, lf)

        // Right fin
        let rfPath = CGMutablePath()
        rfPath.move(to: CGPoint(x: 11, y: -20))
        rfPath.addLine(to: CGPoint(x: 22, y: -36))
        rfPath.addLine(to: CGPoint(x: 11, y: -12))
        rfPath.closeSubpath()
        let rf = SKShapeNode(path: rfPath)
        rf.fillColor   = SKColor(red: 0.7, green: 0.15, blue: 0.15, alpha: 1)
        rf.strokeColor = .clear
        addTo(rocketNode, rf)

        // American flag stripe (red/white/blue mini flag on side)
        let flagBg = SKShapeNode(rectOf: CGSize(width: 18, height: 11))
        flagBg.fillColor   = SKColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1)
        flagBg.strokeColor = .clear
        flagBg.position    = CGPoint(x: 0, y: 5)
        addTo(rocketNode, flagBg)
        for i in 0..<3 {
            let stripe = SKShapeNode(rectOf: CGSize(width: 18, height: 1.5))
            stripe.fillColor   = .white
            stripe.strokeColor = .clear
            stripe.position    = CGPoint(x: 0, y: 3 - CGFloat(i) * 3)
            addTo(rocketNode, stripe)
        }
        let canton = SKShapeNode(rectOf: CGSize(width: 7, height: 6))
        canton.fillColor   = SKColor(red: 0.1, green: 0.2, blue: 0.7, alpha: 1)
        canton.strokeColor = .clear
        canton.position    = CGPoint(x: -5.5, y: 7)
        addTo(rocketNode, canton)

        // Drawing.png badge
        let badge = SKSpriteNode(imageNamed: "Drawing")
        badge.size     = CGSize(width: 18, height: 18)
        badge.position = CGPoint(x: 0, y: -8)
        badge.zPosition = 2
        rocketNode.addChild(badge)

        // Physics on a sprite that matches the rocket shape
        rocket = SKSpriteNode(color: .clear, size: CGSize(width: 24, height: 80))
        rocket.position = rocketNode.position
        rocket.zPosition = 10
        let pb = SKPhysicsBody(rectangleOf: CGSize(width: 20, height: 70))
        pb.affectedByGravity  = false
        pb.allowsRotation     = true
        pb.linearDamping      = 0.6
        pb.angularDamping     = 4.0
        pb.categoryBitMask    = Cat.rocket
        pb.contactTestBitMask = Cat.rock | Cat.planet
        pb.collisionBitMask   = 0
        rocket.physicsBody    = pb
        addChild(rocket)

        // Attach visual rocketNode as child of physics sprite
        rocket.addChild(rocketNode)
        rocketNode.position = .zero
    }

    private func addTo(_ parent: SKNode, _ child: SKNode) {
        child.zPosition = 1
        parent.addChild(child)
    }

    // MARK: - Planets

    private func spawnPlanet(x: CGFloat, y: CGFloat, radius: CGFloat, ore oreAmt: Int) {
        let planet = PlanetNode(radius: radius, oreAmount: oreAmt)
        planet.position = CGPoint(x: x, y: y)

        // Moving orbit
        let dx = CGFloat.random(in: 50...120) * (Bool.random() ? 1 : -1)
        let dy = CGFloat.random(in: 30...80)  * (Bool.random() ? 1 : -1)
        let dur = Double.random(in: 3.0...6.0)
        planet.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: dx, y: dy, duration: dur),
            SKAction.moveBy(x: -dx, y: -dy, duration: dur)
        ])))

        addChild(planet)
    }

    // MARK: - Rock spawning

    private func spawnRock() {
        let edge = Int.random(in: 0...3)
        var pos: CGPoint
        switch edge {
        case 0: pos = CGPoint(x: CGFloat.random(in: 0...size.width), y: size.height + 30)
        case 1: pos = CGPoint(x: CGFloat.random(in: 0...size.width), y: -30)
        case 2: pos = CGPoint(x: -30, y: CGFloat.random(in: 0...size.height))
        default: pos = CGPoint(x: size.width + 30, y: CGFloat.random(in: 0...size.height))
        }

        let radius = CGFloat.random(in: 10...28)
        let rock = SKShapeNode(circleOfRadius: radius)
        rock.fillColor   = SKColor(red: 0.42, green: 0.38, blue: 0.34, alpha: 1)
        rock.strokeColor = SKColor(red: 0.6, green: 0.56, blue: 0.50, alpha: 1)
        rock.lineWidth   = 1.5
        rock.position    = pos
        rock.zPosition   = 5
        rock.name        = "rock"

        let pb = SKPhysicsBody(circleOfRadius: radius)
        pb.affectedByGravity   = false
        pb.categoryBitMask     = Cat.rock
        pb.contactTestBitMask  = Cat.rocket
        pb.collisionBitMask    = 0
        let vel = CGFloat.random(in: 60...130)
        let angle = CGFloat.random(in: 0...(2 * .pi))
        pb.velocity = CGVector(dx: cos(angle) * vel, dy: sin(angle) * vel)
        rock.physicsBody = pb

        addChild(rock)

        // Remove when far off screen
        rock.run(SKAction.sequence([
            SKAction.wait(forDuration: 12),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Game loop

    override func update(_ currentTime: TimeInterval) {
        guard !hasWon, !isDead else { return }

        // Spawn rocks every ~2 s
        if currentTime - lastRockSpawn > 2.0 {
            lastRockSpawn = currentTime
            spawnRock()
        }

        guard let body = rocket.physicsBody else { return }

        // Rotation
        body.angularVelocity = -rotateDir * rotateSpeed

        // Thrust along rocket's up axis
        if thrustOn {
            let angle = rocket.zRotation + .pi / 2
            let force = CGVector(dx: cos(angle) * thrustForce,
                                 dy: sin(angle) * thrustForce)
            body.applyForce(force)
        }

        // Wrap around screen edges
        var p = rocket.position
        if p.x < -40  { p.x = size.width  + 40 }
        if p.x > size.width  + 40 { p.x = -40 }
        if p.y < -40  { p.y = size.height + 40 }
        if p.y > size.height + 40 { p.y = -40 }
        rocket.position = p
    }

    override func didSimulatePhysics() {
        guard needsRespawn else { return }
        needsRespawn = false
        if onLose != nil {
            DispatchQueue.main.async { self.onLose?() }
            return
        }
        respawn()
    }

    // MARK: - Contact

    func didBegin(_ contact: SKPhysicsContact) {
        let a = contact.bodyA, b = contact.bodyB
        let m = a.categoryBitMask | b.categoryBitMask

        if m & Cat.rocket != 0 && m & Cat.rock != 0 {
            guard !isDead, !hasWon else { return }
            isDead = true
            needsRespawn = true
        }

        if m & Cat.rocket != 0 && m & Cat.planet != 0 {
            guard !hasWon else { return }
            let planetNode = (a.categoryBitMask == Cat.planet ? a.node : b.node) as? PlanetNode
            if let planet = planetNode, !planet.collected {
                planet.collected = true
                ore += planet.oreAmount
                updateOreLabel()
                planet.showCollect()
                if ore >= oreGoal { triggerWin() }
            }
        }
    }

    // MARK: - Death / Win

    private func respawn() {
        isDead = false
        ore = 0
        updateOreLabel()
        rocket.position = CGPoint(x: size.width / 2, y: size.height * 0.4)
        rocket.zRotation = 0
        rocket.physicsBody?.velocity = .zero
        rocket.physicsBody?.angularVelocity = 0
        // Flash all shape children of the rocket visual node
        if let rn = rocket.children.first(where: { !($0 is SKSpriteNode) }) {
            let shapes = rn.children.compactMap { $0 as? SKShapeNode }
            for s in shapes {
                let orig = s.fillColor
                s.run(SKAction.sequence([
                    SKAction.run { s.fillColor = SKColor(red: 1, green: 0.2, blue: 0.2, alpha: 1) },
                    SKAction.wait(forDuration: 0.18),
                    SKAction.run { s.fillColor = orig }
                ]))
            }
        }
    }

    private func triggerWin() {
        guard !hasWon else { return }
        hasWon = true
        rocket.physicsBody?.velocity = .zero

        if onWin != nil { DispatchQueue.main.async { self.onWin?() }; return }

        let overlay = SKNode()
        overlay.zPosition = 200
        winOverlay = overlay

        let bg = SKSpriteNode(color: SKColor(white: 0, alpha: 0.80),
                              size: CGSize(width: 560, height: 230))
        bg.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.addChild(bg)

        let title = SKLabelNode(text: "Mission Complete!")
        title.fontName = "AvenirNext-Bold"; title.fontSize = 44
        title.fontColor = .yellow
        title.position = CGPoint(x: size.width / 2, y: size.height / 2 + 32)
        overlay.addChild(title)

        let sub = SKLabelNode(text: "Tap to play again")
        sub.fontName = "AvenirNext-Regular"; sub.fontSize = 22
        sub.fontColor = .white
        sub.position = CGPoint(x: size.width / 2, y: size.height / 2 - 26)
        overlay.addChild(sub)

        addChild(overlay)
    }

    private func restartGame() {
        winOverlay?.removeFromParent(); winOverlay = nil
        hasWon = false
        respawn()
    }

    // MARK: - Touch controls

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if hasWon { restartGame(); return }
        guard let touch = touches.first else { return }
        let x = touch.location(in: self).x
        if x < size.width / 3 {
            rotateDir = 1
        } else if x > size.width * 2 / 3 {
            rotateDir = -1
        } else {
            thrustOn = true
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        rotateDir = 0; thrustOn = false
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        rotateDir = 0; thrustOn = false
    }

    // MARK: - Keyboard (Mac)

    func keyDown(key: String) {
        switch key {
        case "left":  rotateDir =  1
        case "right": rotateDir = -1
        case "up", "space": thrustOn = true
        default: break
        }
    }

    func keyUp(key: String) {
        switch key {
        case "left", "right": rotateDir = 0
        case "up", "space":   thrustOn = false
        default: break
        }
    }
}

// MARK: - PlanetNode

final class PlanetNode: SKShapeNode {
    let oreAmount: Int
    var collected = false

    init(radius: CGFloat, oreAmount: Int) {
        self.oreAmount = oreAmount
        super.init()

        let path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius,
                                            width: radius*2, height: radius*2),
                          transform: nil)
        self.path = path

        // Color by size: big=blue, medium=green, small=brown
        if radius > 70 {
            fillColor = SKColor(red: 0.15, green: 0.35, blue: 0.70, alpha: 1)
        } else if radius > 50 {
            fillColor = SKColor(red: 0.18, green: 0.55, blue: 0.30, alpha: 1)
        } else {
            fillColor = SKColor(red: 0.55, green: 0.38, blue: 0.20, alpha: 1)
        }
        strokeColor = SKColor(white: 0.8, alpha: 0.6)
        lineWidth   = 2
        zPosition   = 3

        // Ore label
        let lbl = SKLabelNode(text: "+\(oreAmount) ore")
        lbl.fontName = "AvenirNext-Bold"; lbl.fontSize = 13
        lbl.fontColor = SKColor(red: 1, green: 0.9, blue: 0.3, alpha: 1)
        lbl.verticalAlignmentMode = .center
        lbl.position = .zero
        addChild(lbl)

        // Gravity ring visual
        let ring = SKShapeNode(circleOfRadius: radius + 20)
        ring.fillColor   = .clear
        ring.strokeColor = SKColor(white: 1, alpha: 0.10)
        ring.lineWidth   = 14
        ring.zPosition   = -1
        addChild(ring)

        let pb = SKPhysicsBody(circleOfRadius: radius + 18)
        pb.isDynamic          = false
        pb.categoryBitMask    = 1 << 2   // Cat.planet
        pb.contactTestBitMask = 1 << 0   // Cat.rocket
        pb.collisionBitMask   = 0
        self.physicsBody = pb
    }

    required init?(coder: NSCoder) { fatalError() }

    func showCollect() {
        let pop = SKLabelNode(text: "+\(oreAmount)!")
        pop.fontName = "AvenirNext-Bold"; pop.fontSize = 20
        pop.fontColor = .yellow; pop.zPosition = 20
        pop.position = CGPoint(x: 0, y: (self.path?.boundingBox.height ?? 60) / 2 + 12)

        pop.run(SKAction.sequence([
            SKAction.group([
                SKAction.moveBy(x: 0, y: 40, duration: 0.7),
                SKAction.fadeOut(withDuration: 0.7)
            ]),
            SKAction.removeFromParent()
        ]))
        addChild(pop)

        run(SKAction.sequence([
            SKAction.scale(to: 1.15, duration: 0.1),
            SKAction.scale(to: 0.85, duration: 0.15),
            SKAction.scale(to: 1.0,  duration: 0.1)
        ]))

        fillColor = SKColor(white: 0.5, alpha: 0.4)
        strokeColor = SKColor(white: 0.4, alpha: 0.3)
        if let lbl = children.first(where: { $0 is SKLabelNode }) as? SKLabelNode {
            lbl.text = "collected"
            lbl.fontColor = SKColor(white: 0.5, alpha: 0.5)
        }
    }
}

