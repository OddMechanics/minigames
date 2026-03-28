import SpriteKit

class PlatformerScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Physics categories

    private enum Category: UInt32 {
        case player   = 0b001
        case ground   = 0b010
        case platform = 0b100
    }

    private let surfaceMask: UInt32 = 0b110   // ground | platform

    // MARK: - State

    private var player: SKSpriteNode!
    private var cameraNode: SKCameraNode!
    private var moveDirection: CGFloat = 0
    private var groundContacts = 0

    private let playerSpeed: CGFloat  = 380
    private let jumpVelocity: CGFloat = 720

    // MARK: - Setup

    override func didMove(to view: SKView) {
        physicsWorld.gravity = CGVector(dx: 0, dy: -28)
        physicsWorld.contactDelegate = self

        setupBackground()
        setupCamera()
        setupPlayer()
        buildLevel()
    }

    private func setupBackground() {
        backgroundColor = SKColor(red: 0.44, green: 0.76, blue: 0.97, alpha: 1)

        // Distant sky gradient strip
        let sky = SKSpriteNode(color: SKColor(red: 0.3, green: 0.6, blue: 0.95, alpha: 1),
                               size: CGSize(width: 8000, height: size.height * 0.5))
        sky.position = CGPoint(x: 4000, y: size.height * 0.75)
        sky.zPosition = -20
        addChild(sky)
    }

    private func setupCamera() {
        cameraNode = SKCameraNode()
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(cameraNode)
        camera = cameraNode
    }

    private func setupPlayer() {
        let texture = SKTexture(imageNamed: "Drawing")
        player = SKSpriteNode(texture: texture, size: CGSize(width: 72, height: 72))
        player.position = CGPoint(x: 200, y: 220)
        player.zPosition = 10

        let body = SKPhysicsBody(rectangleOf: player.size)
        body.allowsRotation  = false
        body.restitution     = 0
        body.friction        = 0
        body.linearDamping   = 0
        body.categoryBitMask    = Category.player.rawValue
        body.contactTestBitMask = surfaceMask
        body.collisionBitMask   = surfaceMask
        player.physicsBody = body

        addChild(player)
    }

    private func buildLevel() {
        // Long ground
        addSurface(x: 4000, y: 20, w: 8000, h: 40, color: SKColor(red: 0.55, green: 0.35, blue: 0.15, alpha: 1), isGround: true)

        // Platforms (x, y, width)
        let plats: [(CGFloat, CGFloat, CGFloat)] = [
            (450,  230, 210), (750,  320, 190), (1060, 210, 200),
            (1350, 370, 170), (1650, 270, 210), (1960, 420, 180),
            (2260, 230, 220), (2560, 340, 170), (2860, 260, 200),
            (3160, 390, 190), (3450, 210, 210), (3760, 310, 200),
            (4060, 160, 180), (4360, 360, 210), (4660, 260, 170),
            (4960, 430, 190), (5260, 200, 220), (5560, 340, 180),
        ]
        for (x, y, w) in plats {
            addSurface(x: x, y: y, w: w, h: 22,
                       color: SKColor(red: 0.24, green: 0.62, blue: 0.20, alpha: 1),
                       isGround: false)
        }

        addDecorations()
    }

    private func addSurface(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                             color: SKColor, isGround: Bool) {
        let node = SKSpriteNode(color: color, size: CGSize(width: w, height: h))
        node.position = CGPoint(x: x, y: y)

        let body = SKPhysicsBody(rectangleOf: node.size)
        body.isDynamic             = false
        body.friction              = 1.0
        body.categoryBitMask       = isGround ? Category.ground.rawValue : Category.platform.rawValue
        body.contactTestBitMask    = Category.player.rawValue
        body.collisionBitMask      = Category.player.rawValue
        node.physicsBody = body

        addChild(node)
    }

    private func addDecorations() {
        let trunkColor  = SKColor(red: 0.42, green: 0.26, blue: 0.10, alpha: 1)
        let leavesColor = SKColor(red: 0.18, green: 0.55, blue: 0.12, alpha: 1)

        for x: CGFloat in stride(from: 300, through: 5800, by: 380) {
            let trunk = SKSpriteNode(color: trunkColor, size: CGSize(width: 18, height: 52))
            trunk.position = CGPoint(x: x, y: 66)
            trunk.zPosition = -1
            addChild(trunk)

            let leaves = SKSpriteNode(color: leavesColor, size: CGSize(width: 58, height: 58))
            leaves.position = CGPoint(x: x, y: 118)
            leaves.zPosition = -1
            addChild(leaves)
        }
    }

    // MARK: - Game loop

    override func update(_ currentTime: TimeInterval) {
        guard let body = player.physicsBody else { return }

        // Horizontal movement — vertical velocity preserved
        body.velocity.dx = moveDirection * playerSpeed

        // Smooth camera follow
        let targetX = max(size.width / 2, player.position.x)
        let targetY = max(size.height / 2, player.position.y)
        let smooth: CGFloat = 0.12
        cameraNode.position.x += (targetX - cameraNode.position.x) * smooth
        cameraNode.position.y += (targetY - cameraNode.position.y) * smooth

        // Respawn if fallen off
        if player.position.y < -300 { respawn() }
    }

    private func respawn() {
        player.position = CGPoint(x: 200, y: 220)
        player.physicsBody?.velocity = .zero
        groundContacts = 0
    }

    // MARK: - Contact detection

    func didBegin(_ contact: SKPhysicsContact) {
        let combined = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if combined & Category.player.rawValue != 0 && combined & surfaceMask != 0 {
            groundContacts += 1
        }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        let combined = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if combined & Category.player.rawValue != 0 && combined & surfaceMask != 0 {
            groundContacts = max(0, groundContacts - 1)
        }
    }

    private var isOnGround: Bool { groundContacts > 0 }

    // MARK: - Controls (called from PlatformerView)

    func moveLeft()       { moveDirection = -1 }
    func moveRight()      { moveDirection =  1 }
    func stopHorizontal() { moveDirection =  0 }

    func jump() {
        guard isOnGround else { return }
        player.physicsBody?.velocity.dy = jumpVelocity
        groundContacts = 0
    }
}
