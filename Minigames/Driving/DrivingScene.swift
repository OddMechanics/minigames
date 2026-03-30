import SpriteKit

// MARK: - Map Mode

enum DrivingMapMode {
    case short   // 3 ramps, 1 gap, ~4000 pts
    case long    // 8 ramps, 2 gaps, ~10000 pts
}

// MARK: - DrivingScene

class DrivingScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Collision Categories
    struct Cat {
        static let car:    UInt32 = 1 << 0
        static let ground: UInt32 = 1 << 1
        static let gap:    UInt32 = 1 << 2
        static let finish: UInt32 = 1 << 3
        static let wheel:  UInt32 = 1 << 4
    }

    // MARK: - Public Config
    var mapMode: DrivingMapMode = .short
    var onWin:  (() -> Void)?
    var onLose: (() -> Void)?

    // MARK: - Physics/Gameplay Constants
    private let maxSpeedH:     CGFloat = 1100          // horizontal cap only
    private let gasForce:      CGFloat = 3500
    private let wheelRadius:   CGFloat = 18
    private let carWidth:      CGFloat = 90
    private let carHeight:     CGFloat = 34
    private let groundY:       CGFloat = 80

    // MARK: - State
    private var hasBuilt           = false
    private var isGasHeld          = false
    private var gasRampT:          CGFloat = 0
    private var lastUpdateTime:    TimeInterval = 0
    private var isDead             = false
    private var hasWon             = false

    // Stuck detection
    private var slowTimer:         TimeInterval = 0
    private let stuckThreshold:    TimeInterval = 3.0

    // Airborne / camera-shake tracking
    private var wasAirborne        = false
    private var wheelContactCount  = 0          // incremented per wheel touching ground

    // MARK: - Nodes
    private var carPhysics:  SKNode!
    private var carBody:     SKShapeNode!
    private var wheelFront:  SKShapeNode!
    private var wheelRear:   SKShapeNode!
    private var cameraNode:  SKCameraNode!
    private var speedLabel:  SKLabelNode!
    private var gasBarBg:    SKShapeNode!
    private var gasBarFill:  SKShapeNode!
    private var overlayBg:   SKSpriteNode?

    // Joints — stored so we can remove & re-add on restart
    private var jointFront:  SKPhysicsJointPin?
    private var jointRear:   SKPhysicsJointPin?

    // MARK: - Terrain
    private struct TerrainPoint { let x: CGFloat; let y: CGFloat }
    private var terrainPoints: [TerrainPoint] = []
    private var gapRanges:    [(CGFloat, CGFloat)] = []   // (startX, endX)
    private var mapWidth:     CGFloat = 0
    private let spawnX:       CGFloat = 150

    // MARK: - didMove

    override func didMove(to view: SKView) {
        isPaused = false
        guard !hasBuilt else { return }
        hasBuilt = true

        physicsWorld.gravity          = CGVector(dx: 0, dy: -900)
        physicsWorld.contactDelegate  = self
        physicsWorld.speed            = 1.0

        setupBackground()
        setupCamera()
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

    // MARK: - Background

    private func setupBackground() {
        // Dark blue gradient sky (two-layer approximation)
        let skyTop = SKSpriteNode(
            color: SKColor(red: 0.08, green: 0.12, blue: 0.28, alpha: 1),
            size: CGSize(width: 20000, height: 2000))
        skyTop.position  = CGPoint(x: 5000, y: 900)
        skyTop.zPosition = -20
        addChild(skyTop)

        let skyBot = SKSpriteNode(
            color: SKColor(red: 0.20, green: 0.45, blue: 0.75, alpha: 1),
            size: CGSize(width: 20000, height: 800))
        skyBot.position  = CGPoint(x: 5000, y: 400)
        skyBot.zPosition = -19
        addChild(skyBot)

        // Clouds
        let cloudXs: [CGFloat] = [200, 700, 1300, 2100, 3000, 4200,
                                   5500, 6800, 7900, 9200, 10500]
        let cloudYs: [CGFloat] = [520, 470, 540, 490, 510, 475,
                                   530, 480, 500, 460, 515]
        for (cx, cy) in zip(cloudXs, cloudYs) {
            addCloud(x: cx, y: cy)
        }
    }

    private func addCloud(x: CGFloat, y: CGFloat) {
        let cloud = SKNode()
        cloud.position  = CGPoint(x: x, y: y)
        cloud.zPosition = -10
        let offsets: [CGPoint] = [.zero, CGPoint(x: 30, y: 8), CGPoint(x: -30, y: 6),
                                   CGPoint(x: 14, y: 18), CGPoint(x: -14, y: 14)]
        for off in offsets {
            let r    = CGFloat.random(in: 18...32)
            let puff = SKShapeNode(circleOfRadius: r)
            puff.fillColor   = SKColor(white: 1.0, alpha: 0.88)
            puff.strokeColor = .clear
            puff.position    = off
            cloud.addChild(puff)
        }
        addChild(cloud)
    }

    // MARK: - Camera

    private func setupCamera() {
        cameraNode          = SKCameraNode()
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(cameraNode)
        camera = cameraNode
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

        if let last = terrainPoints.last {
            placeFinishLine(x: last.x - 80, y: last.y)
        }
    }

    // MARK: Short map — 3 ramps, 1 gap, ~4000 pts total
    private func shortMapSegments() -> [TerrainPoint] {
        var pts: [TerrainPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = groundY

        pts += flat(x: x, y: y, len: 300);  advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: 20, len: 180); advance(&x, &y, pts)
        pts += flat(x: x, y: y, len: 140);  advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: -18, len: 160); x = pts.last!.x; y = groundY

        pts += flat(x: x, y: y, len: 200);  advance(&x, &y, pts)
        // GAP 1 — 160 pts wide
        x += 160
        pts += flat(x: x, y: groundY, len: 180); advance(&x, &y, pts)

        pts += ramp(x: x, y: y, angle: 30, len: 180); advance(&x, &y, pts)
        pts += flat(x: x, y: y, len: 100);  advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: -25, len: 160); x = pts.last!.x; y = groundY

        pts += flat(x: x, y: y, len: 200);  advance(&x, &y, pts)

        pts += ramp(x: x, y: y, angle: 38, len: 200); advance(&x, &y, pts)
        pts += flat(x: x, y: y, len: 120);  advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: -30, len: 170); x = pts.last!.x; y = groundY

        pts += flat(x: x, y: y, len: 400)
        return pts
    }

    // MARK: Long map — 8 ramps, 2 gaps, ~10000 pts total
    private func longMapSegments() -> [TerrainPoint] {
        var pts: [TerrainPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = groundY

        pts += flat(x: x, y: y, len: 300);  advance(&x, &y, pts)

        // Ramp 1 — 15°
        pts += ramp(x: x, y: y, angle: 15, len: 160); advance(&x, &y, pts)
        pts += flat(x: x, y: y, len: 100);  advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: -12, len: 140); x = pts.last!.x; y = groundY
        pts += flat(x: x, y: y, len: 200);  advance(&x, &y, pts)

        // Ramp 2 — 22°
        pts += ramp(x: x, y: y, angle: 22, len: 180); advance(&x, &y, pts)
        pts += flat(x: x, y: y, len: 120);  advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: -18, len: 160); x = pts.last!.x; y = groundY

        // GAP 1 — 180 pts wide
        pts += flat(x: x, y: y, len: 180);  advance(&x, &y, pts)
        x += 180
        pts += flat(x: x, y: groundY, len: 180); advance(&x, &y, pts)

        // Ramp 3 — 28°
        pts += ramp(x: x, y: y, angle: 28, len: 190); advance(&x, &y, pts)
        pts += flat(x: x, y: y, len: 110);  advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: -22, len: 170); x = pts.last!.x; y = groundY
        pts += flat(x: x, y: y, len: 220);  advance(&x, &y, pts)

        // Ramp 4 — 33°
        pts += ramp(x: x, y: y, angle: 33, len: 200); advance(&x, &y, pts)
        pts += flat(x: x, y: y, len: 90);   advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: -28, len: 180); x = pts.last!.x; y = groundY
        pts += flat(x: x, y: y, len: 200);  advance(&x, &y, pts)

        // Ramp 5 — 36°
        pts += ramp(x: x, y: y, angle: 36, len: 200); advance(&x, &y, pts)
        pts += flat(x: x, y: y, len: 100);  advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: -30, len: 180); x = pts.last!.x; y = groundY

        // GAP 2 — 220 pts wide
        pts += flat(x: x, y: y, len: 180);  advance(&x, &y, pts)
        x += 220
        pts += flat(x: x, y: groundY, len: 200); advance(&x, &y, pts)

        // Ramp 6 — 38°
        pts += ramp(x: x, y: y, angle: 38, len: 210); advance(&x, &y, pts)
        pts += flat(x: x, y: y, len: 100);  advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: -32, len: 190); x = pts.last!.x; y = groundY
        pts += flat(x: x, y: y, len: 200);  advance(&x, &y, pts)

        // Ramp 7 — 40°
        pts += ramp(x: x, y: y, angle: 40, len: 220); advance(&x, &y, pts)
        pts += flat(x: x, y: y, len: 80);   advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: -35, len: 200); x = pts.last!.x; y = groundY
        pts += flat(x: x, y: y, len: 180);  advance(&x, &y, pts)

        // Ramp 8 — 38° final big air
        pts += ramp(x: x, y: y, angle: 38, len: 210); advance(&x, &y, pts)
        pts += flat(x: x, y: y, len: 100);  advance(&x, &y, pts)
        pts += ramp(x: x, y: y, angle: -33, len: 190); x = pts.last!.x; y = groundY

        pts += flat(x: x, y: y, len: 500)
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

    /// Advance x,y to the last point of pts (used to chain segments)
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

        // Main green terrain polygon
        let path = CGMutablePath()
        path.move(to: CGPoint(x: pts[0].x, y: pts[0].y))
        for p in pts.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: p.y)) }
        path.addLine(to: CGPoint(x: pts.last!.x, y: -600))
        path.addLine(to: CGPoint(x: pts[0].x, y: -600))
        path.closeSubpath()

        let grass = SKShapeNode(path: path)
        grass.fillColor   = SKColor(red: 0.22, green: 0.52, blue: 0.16, alpha: 1)
        grass.strokeColor = SKColor(red: 0.15, green: 0.40, blue: 0.10, alpha: 1)
        grass.lineWidth   = 4
        grass.zPosition   = 1
        addChild(grass)

        // Brown dirt layer just below surface
        let dirtPath = CGMutablePath()
        dirtPath.move(to: CGPoint(x: pts[0].x, y: pts[0].y - 12))
        for p in pts.dropFirst() { dirtPath.addLine(to: CGPoint(x: p.x, y: p.y - 12)) }
        dirtPath.addLine(to: CGPoint(x: pts.last!.x, y: -600))
        dirtPath.addLine(to: CGPoint(x: pts[0].x, y: -600))
        dirtPath.closeSubpath()

        let dirt = SKShapeNode(path: dirtPath)
        dirt.fillColor   = SKColor(red: 0.52, green: 0.34, blue: 0.16, alpha: 1)
        dirt.strokeColor = .clear
        dirt.zPosition   = 0
        addChild(dirt)
    }

    // MARK: - Gap Visuals (dark void pit)

    private func buildGapVisuals() {
        for (gx0, gx1) in gapRanges {
            let gapW   = gx1 - gx0
            let midX   = (gx0 + gx1) / 2
            let pitH:  CGFloat = 900

            let pitPath = CGMutablePath()
            pitPath.addRect(CGRect(x: gx0, y: groundY - pitH, width: gapW, height: pitH))
            let pit = SKShapeNode(path: pitPath)
            pit.fillColor   = SKColor(red: 0.10, green: 0.0, blue: 0.0, alpha: 1)
            pit.strokeColor = SKColor(red: 0.60, green: 0.0, blue: 0.0, alpha: 0.8)
            pit.lineWidth   = 3
            pit.zPosition   = 10
            addChild(pit)

            // Danger hatching — red glow at rim
            let glowPath = CGMutablePath()
            glowPath.addRect(CGRect(x: gx0 - 10, y: groundY - 60, width: gapW + 20, height: 60))
            let glow = SKShapeNode(path: glowPath)
            glow.fillColor   = SKColor(red: 0.9, green: 0.0, blue: 0.0, alpha: 0.25)
            glow.strokeColor = .clear
            glow.zPosition   = 11
            addChild(glow)

            // "DANGER" label above gap
            let dangerLbl = SKLabelNode(text: "DANGER")
            dangerLbl.fontName  = "AvenirNext-Bold"
            dangerLbl.fontSize  = 20
            dangerLbl.fontColor = SKColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1)
            dangerLbl.position  = CGPoint(x: midX, y: groundY + 30)
            dangerLbl.zPosition = 12
            addChild(dangerLbl)
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
        body.friction           = 0.9
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
            let gapW   = gx1 - gx0
            let midX   = (gx0 + gx1) / 2
            // 800 pts tall, 300 pts wider than the actual gap
            let killW  = gapW + 300
            let killH: CGFloat = 800
            let killY  = groundY - killH / 2 - 20   // extends far below groundY

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

    // MARK: - Finish Line

    private func placeFinishLine(x: CGFloat, y: CGFloat) {
        let pole = SKShapeNode(rectOf: CGSize(width: 8, height: 120))
        pole.fillColor   = SKColor(white: 0.9, alpha: 1)
        pole.strokeColor = .black
        pole.lineWidth   = 1
        pole.position    = CGPoint(x: x, y: y + 60)
        pole.zPosition   = 10
        addChild(pole)

        let flagSize = CGSize(width: 80, height: 50)
        let flag = SKSpriteNode(color: .clear, size: flagSize)
        flag.position  = CGPoint(x: x + 44, y: y + 115)
        flag.zPosition = 10
        let sqSz: CGFloat = 10
        for row in 0..<Int(flagSize.height / sqSz) {
            for col in 0..<Int(flagSize.width / sqSz) {
                let sq = SKSpriteNode(
                    color: (row + col) % 2 == 0 ? .black : .white,
                    size: CGSize(width: sqSz, height: sqSz))
                sq.position = CGPoint(
                    x: CGFloat(col) * sqSz - flagSize.width / 2 + sqSz / 2,
                    y: CGFloat(row) * sqSz - flagSize.height / 2 + sqSz / 2)
                flag.addChild(sq)
            }
        }
        addChild(flag)

        let lbl = SKLabelNode(text: "FINISH")
        lbl.fontName  = "AvenirNext-Bold"
        lbl.fontSize  = 22
        lbl.fontColor = .yellow
        lbl.position  = CGPoint(x: x, y: y + 128)
        lbl.zPosition = 11
        addChild(lbl)

        let trigger = SKNode()
        trigger.position = CGPoint(x: x, y: y + 50)
        trigger.zPosition = 5
        let trigBody = SKPhysicsBody(rectangleOf: CGSize(width: 30, height: 100))
        trigBody.isDynamic          = false
        trigBody.categoryBitMask    = Cat.finish
        trigBody.contactTestBitMask = Cat.car | Cat.wheel
        trigBody.collisionBitMask   = 0
        trigger.physicsBody = trigBody
        addChild(trigger)
    }

    // MARK: - Car Setup

    private func setupCar() {
        let startY = interpolateTerrainY(atX: spawnX) + wheelRadius + carHeight / 2 + 4

        // Physics body (invisible capsule / rectangle)
        carPhysics          = SKNode()
        carPhysics.position = CGPoint(x: spawnX, y: startY)
        carPhysics.zPosition = 10

        let carPB              = SKPhysicsBody(rectangleOf: CGSize(width: carWidth - 8, height: carHeight))
        carPB.mass             = 3.0
        carPB.restitution      = 0.05
        carPB.friction         = 0.7
        carPB.linearDamping    = 0.2
        carPB.angularDamping   = 0.4
        carPB.allowsRotation   = true
        carPB.categoryBitMask    = Cat.car
        carPB.contactTestBitMask = Cat.ground | Cat.gap | Cat.finish
        carPB.collisionBitMask   = Cat.ground
        carPhysics.physicsBody   = carPB
        addChild(carPhysics)

        // Visual
        carBody = buildCarVisual()
        carPhysics.addChild(carBody)

        // Wheel positions
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
            wPB.mass             = 0.8
            wPB.restitution      = 0.3
            wPB.friction         = 0.95
            wPB.linearDamping    = 0.1
            wPB.angularDamping   = 0.1
            wPB.allowsRotation   = true
            wPB.categoryBitMask    = Cat.wheel
            wPB.contactTestBitMask = Cat.ground | Cat.gap | Cat.finish
            wPB.collisionBitMask   = Cat.ground
            wNode?.physicsBody   = wPB
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
        jf.frictionTorque     = 0.0
        jointFront = jf
        physicsWorld.add(jf)

        let jr = SKPhysicsJointPin.joint(
            withBodyA: carPhysics.physicsBody!,
            bodyB:     wheelRear.physicsBody!,
            anchor:    rearAnchor)
        jr.shouldEnableLimits = false
        jr.frictionTorque     = 0.0
        jointRear = jr
        physicsWorld.add(jr)
    }

    // MARK: - Car Visual Builder

    private func buildCarVisual() -> SKShapeNode {
        // White/gray body with rounded corners
        let body = SKShapeNode(rectOf: CGSize(width: carWidth, height: carHeight), cornerRadius: 6)
        body.fillColor   = SKColor(red: 0.88, green: 0.88, blue: 0.88, alpha: 1)
        body.strokeColor = SKColor(red: 0.50, green: 0.50, blue: 0.55, alpha: 1)
        body.lineWidth   = 2
        body.zPosition   = 0

        // Red roof/cabin
        let roof = SKShapeNode(rectOf: CGSize(width: carWidth * 0.52, height: carHeight * 0.72), cornerRadius: 5)
        roof.fillColor   = SKColor(red: 0.85, green: 0.10, blue: 0.10, alpha: 1)
        roof.strokeColor = SKColor(red: 0.50, green: 0.04, blue: 0.04, alpha: 1)
        roof.lineWidth   = 1.5
        roof.position    = CGPoint(x: -4, y: carHeight * 0.56)
        roof.zPosition   = 1
        body.addChild(roof)

        // Dark windshield
        let windshield = SKShapeNode(rectOf: CGSize(width: carWidth * 0.18, height: carHeight * 0.50), cornerRadius: 2)
        windshield.fillColor   = SKColor(red: 0.08, green: 0.08, blue: 0.14, alpha: 0.92)
        windshield.strokeColor = SKColor(white: 0.4, alpha: 0.6)
        windshield.lineWidth   = 1
        windshield.position    = CGPoint(x: carWidth * 0.14, y: carHeight * 0.54)
        windshield.zPosition   = 2
        body.addChild(windshield)

        // Rear window
        let rearWin = SKShapeNode(rectOf: CGSize(width: carWidth * 0.15, height: carHeight * 0.45), cornerRadius: 2)
        rearWin.fillColor   = SKColor(red: 0.08, green: 0.08, blue: 0.14, alpha: 0.85)
        rearWin.strokeColor = SKColor(white: 0.4, alpha: 0.5)
        rearWin.lineWidth   = 1
        rearWin.position    = CGPoint(x: -carWidth * 0.20, y: carHeight * 0.54)
        rearWin.zPosition   = 2
        body.addChild(rearWin)

        // Headlight
        let hl = SKShapeNode(circleOfRadius: 5)
        hl.fillColor   = SKColor(red: 1.0, green: 0.97, blue: 0.70, alpha: 1)
        hl.strokeColor = SKColor(white: 0.7, alpha: 1)
        hl.lineWidth   = 1
        hl.position    = CGPoint(x: carWidth * 0.46, y: 2)
        hl.zPosition   = 2
        body.addChild(hl)

        // Taillight (red)
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
        wheel.strokeColor = SKColor(red: 0.45, green: 0.45, blue: 0.45, alpha: 1)
        wheel.lineWidth   = 2

        // White hubcap dot
        let hub = SKShapeNode(circleOfRadius: wheelRadius * 0.38)
        hub.fillColor   = SKColor(white: 0.90, alpha: 1)
        hub.strokeColor = SKColor(white: 0.5, alpha: 1)
        hub.lineWidth   = 1
        hub.zPosition   = 1
        wheel.addChild(hub)

        return wheel
    }

    // MARK: - HUD Setup

    private func setupHUD() {
        // Speed background pill
        let speedBg = SKShapeNode(rectOf: CGSize(width: 160, height: 38), cornerRadius: 12)
        speedBg.fillColor    = SKColor(white: 0.0, alpha: 0.55)
        speedBg.strokeColor  = SKColor(white: 1.0, alpha: 0.25)
        speedBg.lineWidth    = 1.5
        speedBg.zPosition    = 99
        speedBg.name         = "speedBg"
        cameraNode.addChild(speedBg)

        // Speed label (centered in pill)
        speedLabel = SKLabelNode(text: "0 km/h")
        speedLabel.fontName  = "AvenirNext-Bold"
        speedLabel.fontSize  = 20
        speedLabel.fontColor = .white
        speedLabel.horizontalAlignmentMode = .center
        speedLabel.verticalAlignmentMode   = .center
        speedLabel.zPosition = 100
        speedLabel.name      = "speedLabel"
        cameraNode.addChild(speedLabel)

        // Gas bar background (thin, below speed pill)
        gasBarBg = SKShapeNode(rectOf: CGSize(width: 140, height: 10), cornerRadius: 5)
        gasBarBg.fillColor   = SKColor(white: 0.0, alpha: 0.45)
        gasBarBg.strokeColor = SKColor(white: 1.0, alpha: 0.20)
        gasBarBg.lineWidth   = 1
        gasBarBg.zPosition   = 99
        gasBarBg.name        = "gasBarBg"
        cameraNode.addChild(gasBarBg)

        // Gas bar fill (orange)
        gasBarFill = SKShapeNode(rectOf: CGSize(width: 0, height: 8), cornerRadius: 4)
        gasBarFill.fillColor   = SKColor(red: 1.0, green: 0.50, blue: 0.0, alpha: 1)
        gasBarFill.strokeColor = .clear
        gasBarFill.zPosition   = 100
        gasBarFill.name        = "gasBarFill"
        cameraNode.addChild(gasBarFill)

        layoutHUD()
    }

    private func layoutHUD() {
        guard cameraNode != nil else { return }
        let w = size.width
        let h = size.height

        let bgNode   = cameraNode.childNode(withName: "speedBg")
        let lblNode  = cameraNode.childNode(withName: "speedLabel")
        let barBg    = cameraNode.childNode(withName: "gasBarBg")
        let barFill  = cameraNode.childNode(withName: "gasBarFill")

        let pillX    = -w / 2 + 100
        let pillY    = h / 2 - 40

        bgNode?.position   = CGPoint(x: pillX, y: pillY)
        lblNode?.position  = CGPoint(x: pillX, y: pillY)

        barBg?.position    = CGPoint(x: pillX, y: pillY - 30)
        barFill?.position  = CGPoint(x: pillX - 70, y: pillY - 30)  // anchored left
    }

    // MARK: - Update Gas Bar Fill

    private func updateGasBar() {
        // Rebuild fill shape proportional to gasRampT
        let maxW: CGFloat = 136
        let fillW = max(0, maxW * gasRampT)
        if fillW < 1 {
            gasBarFill?.path = CGMutablePath()
            return
        }
        let path = CGMutablePath()
        path.addRoundedRect(
            in: CGRect(x: 0, y: -4, width: fillW, height: 8),
            cornerWidth: 4, cornerHeight: 4)
        gasBarFill?.path = path
    }

    // MARK: - Terrain Interpolation

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

        // --- Gas ramp ---
        if isGasHeld {
            gasRampT = min(gasRampT + dt * 0.55, 1.0)
        } else {
            gasRampT = max(gasRampT - dt * 0.35, 0.0)
        }

        // --- Rear-wheel drive only via angular velocity torque ---
        if isGasHeld {
            let torque = -gasForce * 0.4 * (0.3 + 0.7 * gasRampT)
            rearPB.applyTorque(torque)
        }

        // --- Self-leveling: keep car body upright when wheels on ground ---
        if wheelContactCount > 0 {
            let levelTorque = -carPhysics.zRotation * 8.0
            carPB.applyTorque(levelTorque)
        }

        // --- Horizontal speed cap (vertical untouched to preserve jumps) ---
        var vel = carPB.velocity
        if vel.dx > maxSpeedH  { vel.dx = maxSpeedH }
        if vel.dx < -maxSpeedH { vel.dx = -maxSpeedH }
        carPB.velocity = vel

        // --- Speed display ---
        let absSpeedH = abs(vel.dx)
        let kmh = Int(absSpeedH * 0.28)
        speedLabel.text = "\(kmh) km/h"
        if kmh > 240 {
            speedLabel.fontColor = SKColor(red: 1, green: 0.30, blue: 0.30, alpha: 1)
        } else if kmh > 140 {
            speedLabel.fontColor = SKColor(red: 1, green: 0.80, blue: 0.20, alpha: 1)
        } else {
            speedLabel.fontColor = .white
        }

        updateGasBar()

        // --- Stuck detection (not in start zone, slow for 3s = lose) ---
        let inStartZone = carPhysics.position.x < spawnX + 250
        if !inStartZone && absSpeedH < 5 {
            slowTimer += Double(dt)
            if slowTimer >= stuckThreshold { triggerLose() }
        } else {
            slowTimer = 0
        }

        // --- Airborne → grounded camera shake ---
        let isAirborne = (wheelContactCount == 0)
        if wasAirborne && !isAirborne {
            // Just landed — shake camera
            cameraShake(amplitude: 4, duration: 0.25)
        }
        wasAirborne = isAirborne

        // --- Camera: follow car with lookahead ---
        let leadX    = carPhysics.position.x + 200
        let clampedX = max(size.width / 2, min(leadX, mapWidth - size.width / 2))
        let targetY  = max(size.height / 2, carPhysics.position.y + size.height * 0.18)
        cameraNode.position.x += (clampedX - cameraNode.position.x) * 0.10
        cameraNode.position.y += (targetY  - cameraNode.position.y) * 0.07
    }

    // MARK: - Camera Shake

    private func cameraShake(amplitude: CGFloat, duration: TimeInterval) {
        let steps  = 6
        let stepT  = duration / Double(steps)
        var actions: [SKAction] = []
        for i in 0..<steps {
            let frac  = CGFloat(steps - i) / CGFloat(steps)
            let dx    = (i % 2 == 0 ? amplitude : -amplitude) * frac
            let dy    = (i % 2 == 0 ? -amplitude : amplitude) * frac * 0.5
            actions.append(.moveBy(x: dx, y: dy, duration: stepT))
        }
        actions.append(.moveBy(x: 0, y: 0, duration: 0))
        cameraNode.run(.sequence(actions))
    }

    // MARK: - Contact

    func didBegin(_ contact: SKPhysicsContact) {
        let m = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        // Wheel-ground contact counter (for airborne detection & self-leveling)
        if m & Cat.ground != 0 && m & Cat.wheel != 0 {
            wheelContactCount += 1
        }

        if m & Cat.finish != 0 && (m & Cat.car != 0 || m & Cat.wheel != 0) {
            triggerWin()
        }
        if m & Cat.gap != 0 && (m & Cat.car != 0 || m & Cat.wheel != 0) {
            triggerLose()
        }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        let m = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if m & Cat.ground != 0 && m & Cat.wheel != 0 {
            wheelContactCount = max(0, wheelContactCount - 1)
        }
    }

    // MARK: - Win / Lose

    private func triggerWin() {
        guard !hasWon, !isDead else { return }
        hasWon = true

        // Freeze all bodies
        carPhysics.physicsBody?.isDynamic  = false
        carPhysics.physicsBody?.velocity   = .zero
        wheelFront.physicsBody?.isDynamic  = false
        wheelFront.physicsBody?.velocity   = .zero
        wheelRear.physicsBody?.isDynamic   = false
        wheelRear.physicsBody?.velocity    = .zero

        if onWin != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.onWin?() }
            return
        }
        showOverlay(title: "YOU WIN!", subtitle: "Great driving!", color: .yellow)
    }

    private func triggerLose() {
        guard !isDead, !hasWon else { return }
        isDead = true

        run(SKAction.wait(forDuration: 0.5)) {
            if self.onLose != nil {
                DispatchQueue.main.async { self.onLose?() }
                return
            }
            self.showOverlay(
                title:    "OH NO!",
                subtitle: "Fell into the gap...",
                color:    SKColor(red: 1, green: 0.3, blue: 0.3, alpha: 1))
        }
    }

    private func showOverlay(title: String, subtitle: String, color: SKColor) {
        overlayBg?.removeFromParent()
        let bg = SKSpriteNode(color: SKColor(white: 0, alpha: 0.76),
                              size: CGSize(width: 520, height: 230))
        bg.zPosition = 200
        cameraNode.addChild(bg)
        overlayBg = bg

        let titleLbl = SKLabelNode(text: title)
        titleLbl.fontName  = "AvenirNext-Bold"
        titleLbl.fontSize  = 52
        titleLbl.fontColor = color
        titleLbl.position  = CGPoint(x: 0, y: 40)
        bg.addChild(titleLbl)

        let subLbl = SKLabelNode(text: subtitle)
        subLbl.fontName  = "AvenirNext-Regular"
        subLbl.fontSize  = 24
        subLbl.fontColor = .white
        subLbl.position  = CGPoint(x: 0, y: -8)
        bg.addChild(subLbl)

        let tapLbl = SKLabelNode(text: "Tap to restart")
        tapLbl.fontName  = "AvenirNext-Regular"
        tapLbl.fontSize  = 19
        tapLbl.fontColor = SKColor(white: 0.75, alpha: 1)
        tapLbl.position  = CGPoint(x: 0, y: -56)
        bg.addChild(tapLbl)
    }

    // MARK: - Touch → Restart

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if hasWon || isDead { restartGame() }
    }

    // MARK: - Restart

    private func restartGame() {
        overlayBg?.removeFromParent()
        overlayBg    = nil
        hasWon       = false
        isDead       = false
        isGasHeld    = false
        gasRampT     = 0
        slowTimer    = 0
        wheelContactCount = 0
        wasAirborne  = false

        // Remove old joints
        if let jf = jointFront { physicsWorld.remove(jf); jointFront = nil }
        if let jr = jointRear  { physicsWorld.remove(jr); jointRear  = nil }

        // Re-enable & reset all bodies
        let startY   = interpolateTerrainY(atX: spawnX) + wheelRadius + carHeight / 2 + 4
        let frontX   = spawnX + carWidth * 0.32
        let rearX    = spawnX - carWidth * 0.32
        let wY       = startY - carHeight / 2 - wheelRadius + 4

        carPhysics.physicsBody?.isDynamic        = true
        carPhysics.physicsBody?.velocity         = .zero
        carPhysics.physicsBody?.angularVelocity  = 0
        carPhysics.position                      = CGPoint(x: spawnX, y: startY)
        carPhysics.zRotation                     = 0

        wheelFront.physicsBody?.isDynamic        = true
        wheelFront.physicsBody?.velocity         = .zero
        wheelFront.physicsBody?.angularVelocity  = 0
        wheelFront.position                      = CGPoint(x: frontX, y: wY)
        wheelFront.zRotation                     = 0

        wheelRear.physicsBody?.isDynamic         = true
        wheelRear.physicsBody?.velocity          = .zero
        wheelRear.physicsBody?.angularVelocity   = 0
        wheelRear.position                       = CGPoint(x: rearX, y: wY)
        wheelRear.zRotation                      = 0

        // Re-attach joints at fresh positions
        attachWheelJoints(
            frontAnchor: CGPoint(x: frontX, y: wY),
            rearAnchor:  CGPoint(x: rearX,  y: wY))

        cameraNode.removeAllActions()
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    // MARK: - Gas Controls (called from DrivingView)

    func gasPressed()  { isGasHeld = true }
    func gasReleased() { isGasHeld = false }
}
