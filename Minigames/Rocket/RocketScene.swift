import SpriteKit

// ─────────────────────────────────────────────────────────────────────────────
// Rocket — infinite 2D space game.
// No gravity. Fly in any direction. Dodge rocks, collect ore from planets.
// 20 ore → win.
// ─────────────────────────────────────────────────────────────────────────────

final class RocketScene: SKScene, SKPhysicsContactDelegate {

    private struct Cat {
        static let rocket: UInt32 = 1 << 0
        static let rock:   UInt32 = 1 << 1
        static let planet: UInt32 = 1 << 2
    }

    // MARK: - Callbacks (infinite mode)
    var onWin:  (() -> Void)?
    var onLose: (() -> Void)?

    // MARK: - Constants
    private let oreGoal      = 20
    private let thrustForce: CGFloat = 460
    private let rotateSpeed: CGFloat = 2.2
    private let chunkSize:   CGFloat = 800   // world is divided into 800×800 chunks

    // MARK: - State
    private var rocket: SKSpriteNode!
    private var cameraNode: SKCameraNode!
    private var oreLabel: SKLabelNode!
    private var ore = 0
    private var hasWon       = false
    private var isDead       = false
    private var needsRespawn = false
    private var hasBuilt     = false
    private var thrustOn     = false
    private var rotateDir:   CGFloat = 0
    private var lastUpdateTime: TimeInterval = 0
    private var generatedChunks = Set<String>()

    // MARK: - Setup

    override func didMove(to view: SKView) {
        isPaused = false
        lastUpdateTime = 0
        if hasBuilt { return }
        hasBuilt = true
        backgroundColor = SKColor(red: 0.03, green: 0.02, blue: 0.12, alpha: 1)
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self
        setupCamera()
        setupHUD()
        buildRocket()
        loadChunksAround(rocket.position)
    }

    override func willMove(from view: SKView) {
        isPaused = true
        lastUpdateTime = 0
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
        oreLabel = SKLabelNode(text: "Ore: 0 / \(oreGoal)")
        oreLabel.fontName = "AvenirNext-Bold"
        oreLabel.fontSize = 22
        oreLabel.fontColor = SKColor(red: 0.9, green: 0.85, blue: 0.3, alpha: 1)
        oreLabel.horizontalAlignmentMode = .left
        oreLabel.position = CGPoint(x: -size.width / 2 + 20, y: size.height / 2 - 48)
        oreLabel.zPosition = 100
        cameraNode.addChild(oreLabel)

        let hint = SKLabelNode(text: "Left/Right: rotate  •  Center: thrust")
        hint.fontName = "AvenirNext-Regular"; hint.fontSize = 14
        hint.fontColor = SKColor(white: 0.5, alpha: 1)
        hint.horizontalAlignmentMode = .left
        hint.position = CGPoint(x: -size.width / 2 + 20, y: size.height / 2 - 70)
        hint.zPosition = 100
        cameraNode.addChild(hint)
    }

    private func updateOreLabel() { oreLabel.text = "Ore: \(ore) / \(oreGoal)" }

    // MARK: - Rocket

    private func buildRocket() {
        rocket = SKSpriteNode(color: .clear, size: CGSize(width: 34, height: 130))
        rocket.position = CGPoint(x: size.width / 2, y: size.height / 2)
        rocket.zPosition = 10
        rocket.addChild(makeRocketVisual())

        let pb = SKPhysicsBody(rectangleOf: CGSize(width: 26, height: 115))
        pb.affectedByGravity  = false
        pb.allowsRotation     = true
        pb.linearDamping      = 0.55
        pb.angularDamping     = 4.0
        pb.categoryBitMask    = Cat.rocket
        pb.contactTestBitMask = Cat.rock | Cat.planet
        pb.collisionBitMask   = 0
        rocket.physicsBody    = pb
        addChild(rocket)
    }

    private func makeRocketVisual() -> SKNode {
        let n = SKNode()

        let body = SKShapeNode(rectOf: CGSize(width: 30, height: 130), cornerRadius: 10)
        body.fillColor = SKColor(white: 0.88, alpha: 1)
        body.strokeColor = SKColor(white: 0.5, alpha: 1)
        body.lineWidth = 1.5; body.zPosition = 1; n.addChild(body)

        let np = CGMutablePath()
        np.move(to: CGPoint(x: -15, y: 55)); np.addLine(to: CGPoint(x: 15, y: 55))
        np.addLine(to: CGPoint(x: 0, y: 88)); np.closeSubpath()
        let nose = SKShapeNode(path: np)
        nose.fillColor = SKColor(red: 0.85, green: 0.15, blue: 0.15, alpha: 1)
        nose.strokeColor = .clear; nose.zPosition = 1; n.addChild(nose)

        for side: CGFloat in [-1, 1] {
            let fp = CGMutablePath()
            fp.move(to: CGPoint(x: side * 15, y: -50))
            fp.addLine(to: CGPoint(x: side * 34, y: -85))
            fp.addLine(to: CGPoint(x: side * 15, y: -28))
            fp.closeSubpath()
            let fin = SKShapeNode(path: fp)
            fin.fillColor = SKColor(red: 0.7, green: 0.15, blue: 0.15, alpha: 1)
            fin.strokeColor = .clear; fin.zPosition = 1; n.addChild(fin)
        }

        let flagBg = SKShapeNode(rectOf: CGSize(width: 24, height: 15))
        flagBg.fillColor = SKColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1)
        flagBg.strokeColor = .clear; flagBg.position = CGPoint(x: 0, y: 12); flagBg.zPosition = 2
        n.addChild(flagBg)
        for i in 0..<3 {
            let s = SKShapeNode(rectOf: CGSize(width: 24, height: 2))
            s.fillColor = .white; s.strokeColor = .clear
            s.position = CGPoint(x: 0, y: 10 - CGFloat(i) * 4); s.zPosition = 3; n.addChild(s)
        }
        let canton = SKShapeNode(rectOf: CGSize(width: 10, height: 9))
        canton.fillColor = SKColor(red: 0.1, green: 0.2, blue: 0.7, alpha: 1)
        canton.strokeColor = .clear; canton.position = CGPoint(x: -7, y: 14); canton.zPosition = 3
        n.addChild(canton)

        let badge = SKSpriteNode(imageNamed: "Drawing")
        badge.size = CGSize(width: 14, height: 14)
        badge.position = CGPoint(x: 0, y: -20); badge.zPosition = 2; n.addChild(badge)

        return n
    }

    // MARK: - Chunk system

    private func chunkKey(_ cx: Int, _ cy: Int) -> String { "\(cx),\(cy)" }

    private func currentChunk() -> (Int, Int) {
        (Int(floor(rocket.position.x / chunkSize)),
         Int(floor(rocket.position.y / chunkSize)))
    }

    /// Load all chunks within loadRadius of the rocket. Skip already-generated ones.
    private func loadChunksAround(_ pos: CGPoint) {
        let cx = Int(floor(pos.x / chunkSize))
        let cy = Int(floor(pos.y / chunkSize))
        let loadR = 2
        for dx in -loadR...loadR {
            for dy in -loadR...loadR {
                let key = chunkKey(cx + dx, cy + dy)
                if !generatedChunks.contains(key) {
                    generatedChunks.insert(key)
                    populateChunk(cx: cx + dx, cy: cy + dy, startChunk: (cx, cy))
                }
            }
        }
    }

    private func populateChunk(cx: Int, cy: Int, startChunk: (Int, Int)) {
        let ox = CGFloat(cx) * chunkSize
        let oy = CGFloat(cy) * chunkSize
        let sz = chunkSize

        // Stars in every chunk
        for _ in 0..<28 {
            let s = SKShapeNode(circleOfRadius: CGFloat.random(in: 0.5...2.2))
            s.fillColor = SKColor(white: CGFloat.random(in: 0.6...1),
                                  alpha: CGFloat.random(in: 0.35...1))
            s.strokeColor = .clear
            s.position = CGPoint(x: ox + CGFloat.random(in: 0...sz),
                                 y: oy + CGFloat.random(in: 0...sz))
            s.zPosition = -10; s.name = "star"; addChild(s)
        }

        // Skip obstacles in the starting chunk so player has room to orient
        if cx == startChunk.0 && cy == startChunk.1 { return }

        // Rocks
        let rockCount = Int.random(in: 2...5)
        for _ in 0..<rockCount {
            let margin: CGFloat = 60
            spawnRock(at: CGPoint(x: ox + CGFloat.random(in: margin...(sz - margin)),
                                  y: oy + CGFloat.random(in: margin...(sz - margin))))
        }

        // Planet (60% per chunk — generous so 20 ore is achievable)
        if Double.random(in: 0...1) < 0.60 {
            let radius = CGFloat.random(in: 40...90)
            let oreAmt = max(1, Int(radius / 16))
            let margin = radius + 70
            let range  = sz - 2 * margin
            guard range > 0 else { return }
            spawnPlanet(at: CGPoint(x: ox + margin + CGFloat.random(in: 0...range),
                                   y: oy + margin + CGFloat.random(in: 0...range)),
                        radius: radius, ore: oreAmt)
        }
    }

    private func spawnRock(at pos: CGPoint) {
        let radius = CGFloat.random(in: 12...32)
        let rock = SKShapeNode(circleOfRadius: radius)
        rock.fillColor   = SKColor(red: 0.42, green: 0.38, blue: 0.34, alpha: 1)
        rock.strokeColor = SKColor(red: 0.6,  green: 0.56, blue: 0.50, alpha: 1)
        rock.lineWidth = 2; rock.position = pos; rock.zPosition = 5; rock.name = "rock"
        let pb = SKPhysicsBody(circleOfRadius: radius)
        pb.affectedByGravity  = false
        pb.categoryBitMask    = Cat.rock
        pb.contactTestBitMask = Cat.rocket
        pb.collisionBitMask   = 0
        pb.velocity = CGVector(dx: CGFloat.random(in: -70...70),
                               dy: CGFloat.random(in: -70...70))
        rock.physicsBody = pb
        addChild(rock)
    }

    private func spawnPlanet(at pos: CGPoint, radius: CGFloat, ore oreAmt: Int) {
        let planet = PlanetNode(radius: radius, oreAmount: oreAmt)
        planet.position = pos
        let dx = CGFloat.random(in: 40...80) * (Bool.random() ? 1 : -1)
        let dur = Double.random(in: 3...6)
        planet.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: dx, y: 0, duration: dur),
            SKAction.moveBy(x: -dx, y: 0, duration: dur)
        ])))
        addChild(planet)
    }

    // MARK: - Game loop

    override func update(_ currentTime: TimeInterval) {
        let dt: CGFloat
        if lastUpdateTime == 0 {
            dt = 0.016
        } else {
            dt = CGFloat(min(currentTime - lastUpdateTime, 0.05))
        }
        lastUpdateTime = currentTime

        guard !hasWon, !isDead else { return }

        if let body = rocket.physicsBody {
            body.angularVelocity = -rotateDir * rotateSpeed
            if thrustOn {
                let angle = rocket.zRotation + .pi / 2
                body.applyForce(CGVector(dx: cos(angle) * thrustForce,
                                        dy: sin(angle) * thrustForce))
            }
        }

        // Camera locked exactly to rocket
        cameraNode.position = rocket.position

        // Load new chunks as rocket explores
        loadChunksAround(rocket.position)

        // Cull nodes too far from rocket
        let rp = rocket.position
        let cullDist = chunkSize * 4
        for node in children
            where node.name == "rock" || node is PlanetNode || node.name == "star" {
            if abs(node.position.x - rp.x) > cullDist ||
               abs(node.position.y - rp.y) > cullDist {
                node.removeFromParent()
            }
        }

        // Remove distant chunk keys so those regions regenerate when revisited
        let (rcx, rcy) = currentChunk()
        let unloadR = 5
        let staleKeys = generatedChunks.filter { key in
            let parts = key.split(separator: ",")
            guard parts.count == 2,
                  let cx = Int(parts[0]), let cy = Int(parts[1]) else { return false }
            return abs(cx - rcx) > unloadR || abs(cy - rcy) > unloadR
        }
        generatedChunks.subtract(staleKeys)
    }

    override func didSimulatePhysics() {
        guard needsRespawn else { return }
        needsRespawn = false
        if onLose != nil { DispatchQueue.main.async { self.onLose?() }; return }
        doRespawn()
    }

    // MARK: - Contact

    func didBegin(_ contact: SKPhysicsContact) {
        let m = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if m & Cat.rocket != 0 && m & Cat.rock != 0 {
            guard !isDead, !hasWon else { return }
            isDead = true; needsRespawn = true
        }
        if m & Cat.rocket != 0 && m & Cat.planet != 0 {
            guard !hasWon else { return }
            let pNode = (contact.bodyA.categoryBitMask == Cat.planet
                         ? contact.bodyA.node : contact.bodyB.node) as? PlanetNode
            if let planet = pNode, !planet.collected {
                planet.collected = true
                ore += planet.oreAmount
                updateOreLabel()
                planet.showCollect()
                if ore >= oreGoal { triggerWin() }
            }
        }
    }

    // MARK: - Respawn / Win

    private func doRespawn() {
        isDead = false
        ore = 0
        updateOreLabel()
        rocket.position = CGPoint(x: size.width / 2, y: size.height / 2)
        cameraNode.position = rocket.position
        rocket.zRotation = 0
        rocket.physicsBody?.velocity = .zero
        rocket.physicsBody?.angularVelocity = 0
        for node in children
            where node.name == "rock" || node is PlanetNode || node.name == "star" {
            node.removeFromParent()
        }
        generatedChunks.removeAll()
        loadChunksAround(rocket.position)
    }

    private func triggerWin() {
        guard !hasWon else { return }
        hasWon = true
        rocket.physicsBody?.velocity = .zero
        if onWin != nil { DispatchQueue.main.async { self.onWin?() }; return }

        let bg = SKSpriteNode(color: SKColor(white: 0, alpha: 0.80),
                              size: CGSize(width: 560, height: 230))
        bg.zPosition = 200; bg.name = "winOverlay"
        cameraNode.addChild(bg)

        let title = SKLabelNode(text: "Mission Complete!")
        title.fontName = "AvenirNext-Bold"; title.fontSize = 44; title.fontColor = .yellow
        title.position = CGPoint(x: 0, y: 32); bg.addChild(title)

        let sub = SKLabelNode(text: "Tap to play again")
        sub.fontName = "AvenirNext-Regular"; sub.fontSize = 22; sub.fontColor = .white
        sub.position = CGPoint(x: 0, y: -28); bg.addChild(sub)
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if hasWon {
            cameraNode.children.filter { $0.name == "winOverlay" }.forEach { $0.removeFromParent() }
            hasWon = false; doRespawn(); return
        }
        guard let touch = touches.first else { return }
        // Use camera-local coords so controls work wherever the rocket is
        let cx = touch.location(in: cameraNode).x
        if cx < -size.width / 6      { rotateDir =  1 }
        else if cx > size.width / 6  { rotateDir = -1 }
        else                         { thrustOn  = true }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        rotateDir = 0; thrustOn = false
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        rotateDir = 0; thrustOn = false
    }

    func keyDown(key: String) {
        switch key {
        case "left":        rotateDir =  1
        case "right":       rotateDir = -1
        case "up", "space": thrustOn  = true
        default: break
        }
    }
    func keyUp(key: String) {
        switch key {
        case "left", "right": rotateDir = 0
        case "up", "space":   thrustOn  = false
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
                                            width: radius * 2, height: radius * 2), transform: nil)
        self.path = path
        fillColor = radius > 70
            ? SKColor(red: 0.15, green: 0.35, blue: 0.70, alpha: 1)
            : radius > 50
                ? SKColor(red: 0.18, green: 0.55, blue: 0.30, alpha: 1)
                : SKColor(red: 0.55, green: 0.38, blue: 0.20, alpha: 1)
        strokeColor = SKColor(white: 0.8, alpha: 0.6); lineWidth = 2; zPosition = 3

        let lbl = SKLabelNode(text: "+\(oreAmount) ore")
        lbl.fontName = "AvenirNext-Bold"; lbl.fontSize = 13
        lbl.fontColor = SKColor(red: 1, green: 0.9, blue: 0.3, alpha: 1)
        lbl.verticalAlignmentMode = .center; addChild(lbl)

        let ring = SKShapeNode(circleOfRadius: radius + 20)
        ring.fillColor = .clear; ring.strokeColor = SKColor(white: 1, alpha: 0.10)
        ring.lineWidth = 14; ring.zPosition = -1; addChild(ring)

        let pb = SKPhysicsBody(circleOfRadius: radius + 18)
        pb.isDynamic = false
        pb.categoryBitMask    = 1 << 2
        pb.contactTestBitMask = 1 << 0
        pb.collisionBitMask   = 0
        self.physicsBody = pb
    }

    required init?(coder: NSCoder) { fatalError() }

    func showCollect() {
        let pop = SKLabelNode(text: "+\(oreAmount)!")
        pop.fontName = "AvenirNext-Bold"; pop.fontSize = 20; pop.fontColor = .yellow
        pop.zPosition = 20
        pop.position = CGPoint(x: 0, y: (self.path?.boundingBox.height ?? 60) / 2 + 12)
        pop.run(SKAction.sequence([
            SKAction.group([SKAction.moveBy(x: 0, y: 40, duration: 0.7),
                            SKAction.fadeOut(withDuration: 0.7)]),
            SKAction.removeFromParent()
        ]))
        addChild(pop)
        run(SKAction.sequence([SKAction.scale(to: 1.15, duration: 0.1),
                               SKAction.scale(to: 0.85, duration: 0.15),
                               SKAction.scale(to: 1.0,  duration: 0.1)]))
        fillColor = SKColor(white: 0.5, alpha: 0.4)
        strokeColor = SKColor(white: 0.4, alpha: 0.3)
        if let lbl = children.first(where: { $0 is SKLabelNode }) as? SKLabelNode {
            lbl.text = "collected"; lbl.fontColor = SKColor(white: 0.5, alpha: 0.5)
        }
    }
}
