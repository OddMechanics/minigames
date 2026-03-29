import SpriteKit

// ─────────────────────────────────────────────────────────────────────────────
// Ping Pong: player (bottom) vs AI opponent with Drawing.png face (top).
// First to 5 points wins. AI is beatable.
// ─────────────────────────────────────────────────────────────────────────────

final class PingPongScene: SKScene, SKPhysicsContactDelegate {

    private struct Cat {
        static let ball:   UInt32 = 1 << 0
        static let paddle: UInt32 = 1 << 1
        static let wall:   UInt32 = 1 << 2
    }

    // MARK: - Marathon callbacks
    var onWin:  (() -> Void)?
    var onLose: (() -> Void)?

    // MARK: - Constants
    private let paddleW:    CGFloat = 130
    private let paddleH:    CGFloat = 18
    private let ballRadius: CGFloat = 11
    private let ballSpeed:  CGFloat = 500
    private let paddleSpeed: CGFloat = 520
    private let aiSpeed:    CGFloat = 255   // beatable AI
    private let winScore    = 5

    private let tableMinX: CGFloat = 0.10   // fraction of width
    private let tableMaxX: CGFloat = 0.90
    private let playerY_f: CGFloat = 0.11   // fraction of height
    private let aiY_f:     CGFloat = 0.89

    // MARK: - State
    private var playerPaddle: SKSpriteNode!
    private var aiPaddle: SKSpriteNode!
    private var ball: SKShapeNode!
    private var playerScore = 0
    private var aiScore = 0
    private var playerScoreLbl: SKLabelNode!
    private var aiScoreLbl: SKLabelNode!
    private var hasWon = false
    private var hasBuilt = false
    private var serving = false

    // Touch drag
    private var activeTouchPaddleOffset: CGFloat = 0
    private var activeTouch: UITouch?

    // Keyboard
    var moveDir: CGFloat = 0

    // MARK: - Setup

    override func didMove(to view: SKView) {
        guard !hasBuilt else { isPaused = false; return }
        hasBuilt = true
        isPaused = false
        backgroundColor = SKColor(red: 0.04, green: 0.14, blue: 0.06, alpha: 1)
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self
        physicsWorld.speed = 1.0
        setupTable()
        setupPaddles()
        setupBall()
        setupHUD()
        launchBall(delay: 0.6)
    }

    override func willMove(from view: SKView) { isPaused = true }

    // MARK: - Table

    private func setupTable() {
        let minX = size.width  * tableMinX
        let maxX = size.width  * tableMaxX
        let minY = size.height * 0.04
        let maxY = size.height * 0.96
        let w = maxX - minX
        let h = maxY - minY

        let tableRect = CGRect(x: minX, y: minY, width: w, height: h)
        let table = SKShapeNode(rect: tableRect, cornerRadius: 4)
        table.fillColor   = SKColor(red: 0.07, green: 0.22, blue: 0.07, alpha: 1)
        table.strokeColor = SKColor(white: 0.75, alpha: 0.9)
        table.lineWidth   = 3; table.zPosition = -5
        addChild(table)

        // Center dashed line
        let midY = size.height / 2
        let dash = SKShapeNode()
        let lp = CGMutablePath()
        lp.move(to: CGPoint(x: minX, y: midY))
        lp.addLine(to: CGPoint(x: maxX, y: midY))
        dash.path = lp
        dash.strokeColor = SKColor(white: 1, alpha: 0.18)
        dash.lineWidth = 2; dash.zPosition = -4
        addChild(dash)

        // Side walls
        addChild(wallNode(x: minX, y: size.height / 2, w: 6, h: h))
        addChild(wallNode(x: maxX, y: size.height / 2, w: 6, h: h))
    }

    private func wallNode(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> SKNode {
        let n = SKSpriteNode(color: .clear, size: CGSize(width: w, height: h))
        n.position = CGPoint(x: x, y: y)
        let pb = SKPhysicsBody(rectangleOf: n.size)
        pb.isDynamic = false; pb.restitution = 1; pb.friction = 0
        pb.categoryBitMask    = Cat.wall
        pb.contactTestBitMask = Cat.ball
        pb.collisionBitMask   = Cat.ball
        n.physicsBody = pb
        return n
    }

    // MARK: - Paddles

    private func setupPaddles() {
        playerPaddle = makePaddle(y: size.height * playerY_f,
                                  color: SKColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1))
        aiPaddle     = makePaddle(y: size.height * aiY_f,
                                  color: SKColor(red: 1.0, green: 0.4, blue: 0.3, alpha: 1))

        // Drawing.png face above AI paddle
        let face = SKSpriteNode(imageNamed: "Drawing")
        face.size = CGSize(width: 52, height: 52)
        face.position  = CGPoint(x: 0, y: 30)
        face.zPosition = 3
        aiPaddle.addChild(face)

        // "YOU" label below player paddle
        let youLbl = SKLabelNode(text: "YOU")
        youLbl.fontName = "AvenirNext-Bold"; youLbl.fontSize = 13
        youLbl.fontColor = SKColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 0.8)
        youLbl.position = CGPoint(x: 0, y: -20); youLbl.zPosition = 3
        playerPaddle.addChild(youLbl)

        addChild(playerPaddle)
        addChild(aiPaddle)
    }

    private func makePaddle(y: CGFloat, color: SKColor) -> SKSpriteNode {
        let n = SKSpriteNode(color: color, size: CGSize(width: paddleW, height: paddleH))
        n.position = CGPoint(x: size.width / 2, y: y)
        n.zPosition = 5
        let pb = SKPhysicsBody(rectangleOf: n.size)
        pb.isDynamic = false; pb.restitution = 1.05; pb.friction = 0
        pb.categoryBitMask    = Cat.paddle
        pb.contactTestBitMask = Cat.ball
        pb.collisionBitMask   = Cat.ball
        n.physicsBody = pb
        return n
    }

    // MARK: - Ball

    private func setupBall() {
        ball = SKShapeNode(circleOfRadius: ballRadius)
        ball.fillColor = .white
        ball.strokeColor = SKColor(white: 0.7, alpha: 1); ball.lineWidth = 1.5
        ball.position = CGPoint(x: size.width / 2, y: size.height / 2)
        ball.zPosition = 10
        let pb = SKPhysicsBody(circleOfRadius: ballRadius)
        pb.affectedByGravity = false; pb.allowsRotation = false
        pb.restitution = 1.0; pb.friction = 0; pb.linearDamping = 0; pb.angularDamping = 0
        pb.categoryBitMask    = Cat.ball
        pb.contactTestBitMask = Cat.paddle | Cat.wall
        pb.collisionBitMask   = Cat.paddle | Cat.wall
        ball.physicsBody = pb
        addChild(ball)
    }

    private func launchBall(delay: Double = 0) {
        serving = true
        ball.physicsBody?.velocity = .zero
        ball.position = CGPoint(x: size.width / 2, y: size.height / 2)
        run(SKAction.sequence([
            SKAction.wait(forDuration: delay),
            SKAction.run {
                self.serving = false
                let angle = CGFloat.random(in: 0.3...0.7) * (Bool.random() ? 1 : -1)
                let dir: CGFloat = Bool.random() ? 1 : -1
                self.ball.physicsBody?.velocity = CGVector(
                    dx: sin(angle) * self.ballSpeed,
                    dy: dir * cos(angle) * self.ballSpeed
                )
            }
        ]))
    }

    // MARK: - HUD

    private func setupHUD() {
        playerScoreLbl = makeScoreLbl(x: size.width * 0.92, y: size.height * playerY_f)
        aiScoreLbl     = makeScoreLbl(x: size.width * 0.92, y: size.height * aiY_f)
        addChild(playerScoreLbl)
        addChild(aiScoreLbl)
    }

    private func makeScoreLbl(x: CGFloat, y: CGFloat) -> SKLabelNode {
        let lbl = SKLabelNode(text: "0")
        lbl.fontName = "AvenirNext-Bold"; lbl.fontSize = 34; lbl.fontColor = .white
        lbl.horizontalAlignmentMode = .center; lbl.verticalAlignmentMode = .center
        lbl.position = CGPoint(x: x, y: y); lbl.zPosition = 50
        return lbl
    }

    // MARK: - Game loop

    override func update(_ currentTime: TimeInterval) {
        guard !hasWon, !serving else { return }

        // Player keyboard movement
        if moveDir != 0 {
            let nx = playerPaddle.position.x + moveDir * paddleSpeed / 60.0
            playerPaddle.position.x = clampPaddle(nx)
        }

        // AI tracks ball with imperfect speed
        let noise = CGFloat.random(in: -18...18)
        let target = ball.position.x + noise
        let diff = target - aiPaddle.position.x
        let step = min(abs(diff), aiSpeed / 60.0) * (diff < 0 ? -1 : 1)
        aiPaddle.position.x = clampPaddle(aiPaddle.position.x + step)

        // Score: ball out of bounds top/bottom
        let ballY = ball.position.y
        if ballY < size.height * 0.03 {          // AI scores
            aiScore += 1; aiScoreLbl.text = "\(aiScore)"
            if aiScore >= winScore { endGame(playerWon: false); return }
            launchBall(delay: 0.7)
        } else if ballY > size.height * 0.97 {   // Player scores
            playerScore += 1; playerScoreLbl.text = "\(playerScore)"
            if playerScore >= winScore { endGame(playerWon: true); return }
            launchBall(delay: 0.7)
        }

        // Keep ball speed constant (physics restitution can drift it)
        if let v = ball.physicsBody?.velocity {
            let speed = hypot(v.dx, v.dy)
            if speed > 10 {
                let scale = ballSpeed / speed
                ball.physicsBody?.velocity = CGVector(dx: v.dx * scale, dy: v.dy * scale)
            }
        }
    }

    private func clampPaddle(_ x: CGFloat) -> CGFloat {
        let half = paddleW / 2
        return max(size.width * tableMinX + half, min(size.width * tableMaxX - half, x))
    }

    // MARK: - End game

    private func endGame(playerWon: Bool) {
        hasWon = true
        ball.physicsBody?.velocity = .zero

        if playerWon, onWin != nil  { DispatchQueue.main.async { self.onWin?()  }; return }
        if !playerWon, onLose != nil { DispatchQueue.main.async { self.onLose?() }; return }

        let msg   = playerWon ? "You Win! 🏓" : "You Lose!"
        let color: SKColor = playerWon
            ? SKColor(red: 1, green: 0.9, blue: 0.2, alpha: 1)
            : SKColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)

        let overlay = SKSpriteNode(color: SKColor(white: 0, alpha: 0.78),
                                   size: CGSize(width: 500, height: 200))
        overlay.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.zPosition = 200; overlay.name = "overlay"

        let title = SKLabelNode(text: msg)
        title.fontName = "AvenirNext-Bold"; title.fontSize = 50; title.fontColor = color
        title.position = CGPoint(x: 0, y: 22); overlay.addChild(title)

        let sub = SKLabelNode(text: "Tap to play again")
        sub.fontName = "AvenirNext-Regular"; sub.fontSize = 22; sub.fontColor = .white
        sub.position = CGPoint(x: 0, y: -30); overlay.addChild(sub)

        addChild(overlay)
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if hasWon {
            childNode(withName: "overlay")?.removeFromParent()
            playerScore = 0; aiScore = 0
            playerScoreLbl.text = "0"; aiScoreLbl.text = "0"
            hasWon = false; launchBall(delay: 0.4); return
        }
        guard let touch = touches.first, activeTouch == nil else { return }
        activeTouch = touch
        activeTouchPaddleOffset = playerPaddle.position.x - touch.location(in: self).x
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first(where: { $0 == activeTouch }) else { return }
        playerPaddle.position.x = clampPaddle(touch.location(in: self).x + activeTouchPaddleOffset)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { activeTouch = nil }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { activeTouch = nil }

    // MARK: - Keyboard

    func keyDown(key: String) {
        if key == "left"  { moveDir = -1 }
        if key == "right" { moveDir =  1 }
    }
    func keyUp(key: String) {
        if key == "left" || key == "right" { moveDir = 0 }
    }
}
