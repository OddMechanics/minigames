import SpriteKit

// MARK: - Types

enum DungeonMapMode { case short, long }

enum TileKind: Character {
    case floor         = "."
    case wall          = "#"
    case lockedDoor    = "D"
    case openDoor      = "d"
    case exit          = "E"
    case key           = "K"
    case pressurePlate = "P"
    case pushBlock     = "B"
    case spike         = "S"
    case lava          = "L"
    case playerStart   = "@"
    case slime         = "M"
    case skeleton      = "k"
    case demon         = "X"
    case hiddenWall    = "H"
}

enum DungeonDirection { case up, down, left, right }

struct TileCoord: Hashable, Equatable {
    var col: Int
    var row: Int
    func moved(_ dir: DungeonDirection) -> TileCoord {
        switch dir {
        case .up:    return TileCoord(col: col,     row: row - 1)
        case .down:  return TileCoord(col: col,     row: row + 1)
        case .left:  return TileCoord(col: col - 1, row: row)
        case .right: return TileCoord(col: col + 1, row: row)
        }
    }
}

// MARK: - Monster

final class DungeonMonster {
    enum Kind { case slime, skeleton, demon }
    let kind: Kind
    var coord: TileCoord
    var hp: Int
    let maxHP: Int
    var node: SKNode
    var moveTimer: TimeInterval = 0
    var shootTimer: TimeInterval = 0
    var spawnTimer: TimeInterval = 0
    var isDead = false

    init(kind: Kind, coord: TileCoord, node: SKNode) {
        self.kind = kind
        self.coord = coord
        self.node = node
        switch kind {
        case .slime:    hp = 1; maxHP = 1
        case .skeleton: hp = 2; maxHP = 2
        case .demon:    hp = 8; maxHP = 8
        }
        moveTimer  = Double.random(in: 0...1.5)
        shootTimer = Double.random(in: 0...2.0)
        spawnTimer = Double.random(in: 0...5.0)
    }

    var damage: Int {
        switch kind {
        case .slime: return 1
        case .skeleton: return 1
        case .demon: return 2
        }
    }
}

// MARK: - DungeonScene

class DungeonScene: SKScene {

    // MARK: Public interface
    var mapMode: DungeonMapMode = .short
    var onWin:  (() -> Void)?
    var onLose: (() -> Void)?

    // MARK: Constants
    private let tileSize: CGFloat = 48
    private let moveAnimDuration: TimeInterval = 0.10

    // MARK: Map data
    private var mapData:   [[TileKind]] = []
    private var tileNodes: [[SKNode?]]  = []
    private var rows: Int = 0
    private var cols: Int = 0

    // MARK: Puzzle state
    private var plateConnections: [TileCoord: TileCoord] = [:]  // plateCoord → doorCoord
    private var plateActive: [TileCoord: Bool] = [:]
    private var pushBlocks: [TileCoord: SKNode] = [:]
    private var keyNodesByCoord: [TileCoord: SKNode] = [:]
    private var pickedUpKeys: Set<TileCoord> = []
    private var spikeCoords: [TileCoord] = []
    private var spikeNodes: [TileCoord: SKNode] = [:]
    private var spikeActive: Bool = true
    private var spikeTimer: TimeInterval = 0

    // MARK: Player state
    private var playerNode: SKNode!
    private var swordNode: SKShapeNode!
    private var playerCoord = TileCoord(col: 1, row: 1)
    private var playerHP: Int = 3
    private let playerMaxHP: Int = 3
    private var playerKeys: Int = 0
    private var playerFacing: DungeonDirection = .right
    private var isMoving = false
    private var invincibleUntil: TimeInterval = 0
    private var isGameOver = false
    private var hasWon = false

    // MARK: Monsters / projectiles
    private var monsters: [DungeonMonster] = []

    private struct DungeonProjectile {
        var coord: TileCoord
        var direction: DungeonDirection
        var node: SKNode
        var travelled: Int = 0
    }
    private var projectiles: [DungeonProjectile] = []
    private var projTimer: TimeInterval = 0

    // MARK: Scene nodes
    private var worldLayer: SKNode!
    private var hudLayer: SKNode!
    private var cameraNode: SKCameraNode!

    // MARK: Build guard
    private var hasBuilt = false
    private var lastUpdateTime: TimeInterval = 0

    // MARK: - Setup

    override func didMove(to view: SKView) {
        isPaused = false
        guard !hasBuilt else { return }
        hasBuilt = true
        backgroundColor = .black
        setupCamera()
        buildMap()
        buildHUD()
    }

    override func willMove(from view: SKView) {
        isPaused = true
    }

    // MARK: - Camera

    private func setupCamera() {
        cameraNode = SKCameraNode()
        addChild(cameraNode)
        camera = cameraNode
    }

    private func snapCameraToPlayer() {
        cameraNode.position = worldPos(playerCoord)
    }

    private func smoothCameraToPlayer() {
        cameraNode.run(SKAction.move(to: worldPos(playerCoord), duration: moveAnimDuration))
    }

    // MARK: - Coordinate helpers

    /// Convert tile coord to world position (SpriteKit Y increases upward).
    private func worldPos(_ coord: TileCoord) -> CGPoint {
        CGPoint(
            x: CGFloat(coord.col) * tileSize + tileSize / 2,
            y: CGFloat(rows - 1 - coord.row) * tileSize + tileSize / 2
        )
    }

    private func isTileWalkable(_ coord: TileCoord, ignoreBlocks: Bool = false) -> Bool {
        guard coord.col >= 0, coord.row >= 0, coord.col < cols, coord.row < rows else { return false }
        let kind = mapData[coord.row][coord.col]
        switch kind {
        case .wall, .lockedDoor, .hiddenWall: return false
        default: break
        }
        if !ignoreBlocks && pushBlocks[coord] != nil { return false }
        return true
    }

    // MARK: - Map building

    private func buildMap() {
        let rawMap = mapMode == .short ? shortMapString() : longMapString()
        let lines = rawMap.split(separator: "\n", omittingEmptySubsequences: true)
        rows = lines.count
        cols = lines.map { $0.count }.max() ?? 0

        mapData   = Array(repeating: Array(repeating: .floor, count: cols), count: rows)
        tileNodes = Array(repeating: Array(repeating: nil,    count: cols), count: rows)

        worldLayer = SKNode()
        worldLayer.zPosition = 0
        addChild(worldLayer)

        // First pass: lay all floor tiles
        for r in 0..<rows {
            for c in 0..<cols {
                let pos = worldPos(TileCoord(col: c, row: r))
                let floor = makeFloorTile()
                floor.position = pos
                floor.zPosition = 0
                worldLayer.addChild(floor)
            }
        }

        // Second pass: parse and place everything else
        for (r, line) in lines.enumerated() {
            for (c, ch) in line.enumerated() {
                guard let kind = TileKind(rawValue: ch) else { continue }
                mapData[r][c] = kind
                let coord = TileCoord(col: c, row: r)
                let pos = worldPos(coord)

                switch kind {
                case .wall:
                    let node = makeWallTile()
                    node.position = pos; node.zPosition = 1
                    worldLayer.addChild(node)
                    tileNodes[r][c] = node

                case .lockedDoor:
                    let node = makeLockedDoor()
                    node.position = pos; node.zPosition = 2
                    worldLayer.addChild(node)
                    tileNodes[r][c] = node

                case .openDoor:
                    mapData[r][c] = .openDoor  // passable, no visual block

                case .exit:
                    let node = makeExitNode()
                    node.position = pos; node.zPosition = 2
                    worldLayer.addChild(node)
                    tileNodes[r][c] = node

                case .key:
                    mapData[r][c] = .floor
                    let node = makeKeyNode()
                    node.position = pos; node.zPosition = 3
                    worldLayer.addChild(node)
                    keyNodesByCoord[coord] = node

                case .pressurePlate:
                    let node = makePressurePlateNode()
                    node.position = pos; node.zPosition = 1
                    worldLayer.addChild(node)
                    tileNodes[r][c] = node

                case .pushBlock:
                    mapData[r][c] = .floor
                    let node = makePushBlockNode()
                    node.position = pos; node.zPosition = 2
                    worldLayer.addChild(node)
                    pushBlocks[coord] = node

                case .spike:
                    mapData[r][c] = .floor
                    let node = makeSpikeNode()
                    node.position = pos; node.zPosition = 2
                    worldLayer.addChild(node)
                    spikeCoords.append(coord)
                    spikeNodes[coord] = node

                case .lava:
                    let node = makeLavaTile()
                    node.position = pos; node.zPosition = 1
                    worldLayer.addChild(node)
                    tileNodes[r][c] = node

                case .playerStart:
                    mapData[r][c] = .floor
                    playerCoord = coord

                case .slime:
                    mapData[r][c] = .floor
                    let node = makeSlimeNode()
                    node.position = pos; node.zPosition = 4
                    worldLayer.addChild(node)
                    monsters.append(DungeonMonster(kind: .slime, coord: coord, node: node))

                case .skeleton:
                    mapData[r][c] = .floor
                    let node = makeSkeletonNode()
                    node.position = pos; node.zPosition = 4
                    worldLayer.addChild(node)
                    monsters.append(DungeonMonster(kind: .skeleton, coord: coord, node: node))

                case .demon:
                    mapData[r][c] = .floor
                    let node = makeDemonNode()
                    node.position = pos; node.zPosition = 4
                    worldLayer.addChild(node)
                    monsters.append(DungeonMonster(kind: .demon, coord: coord, node: node))

                case .hiddenWall:
                    // Looks like a wall; is passable
                    let node = makeWallTile()
                    node.position = pos; node.zPosition = 1
                    worldLayer.addChild(node)
                    tileNodes[r][c] = node

                default: break
                }
            }
        }

        addTorchLights()
        buildPlayer()
        wirePressurePlates()
        snapCameraToPlayer()
    }

    // MARK: - Pressure plate wiring

    private func wirePressurePlates() {
        let plates = allCoords(of: .pressurePlate)
        let doors  = allCoords(of: .lockedDoor)

        if mapMode == .short {
            // Short map: plate (row 10 col 4) opens the lower locked door (row 7 col 5).
            // The upper locked door (row 4 col 5) is opened by the key.
            // doors array is sorted by row: doors[0]=row4(upper), doors[1]=row7(lower).
            if let plate = plates.first, doors.count >= 2 {
                plateConnections[plate] = doors[1]   // connect to lower door
                plateActive[plate] = false
            } else if let plate = plates.first, let door = doors.last {
                plateConnections[plate] = door
                plateActive[plate] = false
            }
        } else {
            // Long map: wire plates to last two locked doors (deeper in the dungeon)
            if plates.count >= 1 && doors.count >= 1 {
                plateConnections[plates[0]] = doors[max(0, doors.count - 1)]
                plateActive[plates[0]] = false
            }
            if plates.count >= 2 && doors.count >= 2 {
                plateConnections[plates[1]] = doors[max(0, doors.count - 2)]
                plateActive[plates[1]] = false
            }
        }
    }

    private func allCoords(of kind: TileKind) -> [TileCoord] {
        var result: [TileCoord] = []
        for r in 0..<rows {
            for c in 0..<cols {
                if mapData[r][c] == kind { result.append(TileCoord(col: c, row: r)) }
            }
        }
        return result
    }

    // MARK: - Player building

    private func buildPlayer() {
        playerNode = SKNode()
        playerNode.zPosition = 10

        // Body
        let body = SKShapeNode(rectOf: CGSize(width: 20, height: 28), cornerRadius: 3)
        body.fillColor   = SKColor(red: 0.20, green: 0.20, blue: 0.50, alpha: 1)
        body.strokeColor = SKColor(red: 0.40, green: 0.40, blue: 0.80, alpha: 1)
        body.lineWidth   = 1.5
        body.position    = CGPoint(x: 0, y: -8)
        body.zPosition   = 0
        playerNode.addChild(body)

        // Face
        let face = SKSpriteNode(imageNamed: "Drawing")
        face.size = CGSize(width: 36, height: 36)
        face.position  = CGPoint(x: 0, y: 10)
        face.zPosition = 1
        face.texture?.filteringMode = .nearest
        playerNode.addChild(face)

        // Sword
        let sword = SKShapeNode(rectOf: CGSize(width: 20, height: 8), cornerRadius: 2)
        sword.fillColor   = SKColor(red: 0.80, green: 0.80, blue: 0.90, alpha: 1)
        sword.strokeColor = SKColor(red: 0.50, green: 0.50, blue: 0.70, alpha: 1)
        sword.lineWidth   = 1
        sword.position    = CGPoint(x: 22, y: 4)
        sword.zPosition   = 2
        playerNode.addChild(sword)
        swordNode = sword

        playerNode.position = worldPos(playerCoord)
        worldLayer.addChild(playerNode)
    }

    // MARK: - HUD

    private func buildHUD() {
        hudLayer = SKNode()
        hudLayer.zPosition = 100
        cameraNode.addChild(hudLayer)
        refreshHUD()
    }

    private func refreshHUD() {
        hudLayer.removeAllChildren()

        // Hearts
        for i in 0..<playerMaxHP {
            let heart = SKShapeNode(path: heartPath(radius: 9))
            heart.fillColor   = i < playerHP
                ? SKColor(red: 0.90, green: 0.15, blue: 0.15, alpha: 1)
                : SKColor(red: 0.25, green: 0.08, blue: 0.08, alpha: 1)
            heart.strokeColor = SKColor(red: 0.80, green: 0.30, blue: 0.30, alpha: 0.8)
            heart.lineWidth   = 1.5
            heart.position    = CGPoint(
                x: -size.width / 2 + 28 + CGFloat(i) * 30,
                y:  size.height / 2 - 28
            )
            hudLayer.addChild(heart)
        }

        // Key icon
        let keyBg = SKShapeNode(circleOfRadius: 9)
        keyBg.fillColor   = SKColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1)
        keyBg.strokeColor = SKColor(red: 0.8, green: 0.6, blue: 0.0, alpha: 1)
        keyBg.lineWidth   = 1.5
        keyBg.position    = CGPoint(x: size.width / 2 - 55, y: size.height / 2 - 28)
        hudLayer.addChild(keyBg)

        let keyLbl = SKLabelNode(text: "x\(playerKeys)")
        keyLbl.fontName  = "AvenirNext-Bold"
        keyLbl.fontSize  = 17
        keyLbl.fontColor = SKColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1)
        keyLbl.verticalAlignmentMode   = .center
        keyLbl.horizontalAlignmentMode = .left
        keyLbl.position = CGPoint(x: size.width / 2 - 42, y: size.height / 2 - 28)
        hudLayer.addChild(keyLbl)
    }

    private func heartPath(radius r: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: -r * 0.9))
        path.addCurve(to: CGPoint(x: -r, y: 0.1 * r),
                      control1: CGPoint(x: -r * 1.3, y: -r * 0.9),
                      control2: CGPoint(x: -r * 1.3, y:  r * 0.5))
        path.addCurve(to: CGPoint(x: 0, y: r),
                      control1: CGPoint(x: -r,  y:  r * 1.2),
                      control2: CGPoint(x: 0,   y:  r * 1.1))
        path.addCurve(to: CGPoint(x: r, y: 0.1 * r),
                      control1: CGPoint(x: 0,   y:  r * 1.1),
                      control2: CGPoint(x: r,   y:  r * 1.2))
        path.addCurve(to: CGPoint(x: 0, y: -r * 0.9),
                      control1: CGPoint(x: r * 1.3, y: r * 0.5),
                      control2: CGPoint(x: r * 1.3, y: -r * 0.9))
        path.closeSubpath()
        return path
    }

    // MARK: - Tile visual builders

    private func makeFloorTile() -> SKShapeNode {
        let node = SKShapeNode(rectOf: CGSize(width: tileSize, height: tileSize))
        node.fillColor   = SKColor(red: 0.163, green: 0.163, blue: 0.228, alpha: 1)
        node.strokeColor = SKColor(red: 0.210, green: 0.210, blue: 0.300, alpha: 1)
        node.lineWidth   = 0.5
        return node
    }

    private func makeWallTile() -> SKShapeNode {
        let outer = SKShapeNode(rectOf: CGSize(width: tileSize, height: tileSize))
        outer.fillColor   = SKColor(red: 0.105, green: 0.105, blue: 0.180, alpha: 1)
        outer.strokeColor = SKColor(red: 0.180, green: 0.180, blue: 0.300, alpha: 1)
        outer.lineWidth   = 1.0
        // Brick details
        let brickData: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (-8, 12, 20, 10), (8, -2, 20, 10), (-6, -16, 18, 10)
        ]
        for (bx, by, bw, bh) in brickData {
            let b = SKShapeNode(rectOf: CGSize(width: bw, height: bh), cornerRadius: 1)
            b.fillColor   = SKColor(red: 0.14, green: 0.14, blue: 0.22, alpha: 1)
            b.strokeColor = SKColor(red: 0.20, green: 0.20, blue: 0.32, alpha: 0.5)
            b.lineWidth   = 0.5
            b.position    = CGPoint(x: bx, y: by)
            outer.addChild(b)
        }
        return outer
    }

    private func makeLockedDoor() -> SKNode {
        let container = SKNode()
        let door = SKShapeNode(rectOf: CGSize(width: 38, height: 44), cornerRadius: 4)
        door.fillColor   = SKColor(red: 0.55, green: 0.30, blue: 0.10, alpha: 1)
        door.strokeColor = SKColor(red: 0.80, green: 0.55, blue: 0.25, alpha: 1)
        door.lineWidth   = 2
        container.addChild(door)
        // Keyhole circle
        let hole = SKShapeNode(circleOfRadius: 6)
        hole.fillColor   = SKColor(red: 0.20, green: 0.10, blue: 0.04, alpha: 1)
        hole.strokeColor = SKColor(red: 0.65, green: 0.45, blue: 0.15, alpha: 1)
        hole.lineWidth   = 1
        hole.position    = CGPoint(x: 0, y: 4)
        container.addChild(hole)
        // Keyhole slot
        let slot = SKShapeNode(rectOf: CGSize(width: 5, height: 9))
        slot.fillColor   = SKColor(red: 0.20, green: 0.10, blue: 0.04, alpha: 1)
        slot.strokeColor = .clear
        slot.position    = CGPoint(x: 0, y: -4)
        container.addChild(slot)
        return container
    }

    private func makeKeyNode() -> SKNode {
        let container = SKNode()
        // Head circle
        let head = SKShapeNode(circleOfRadius: 8)
        head.fillColor   = SKColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1)
        head.strokeColor = SKColor(red: 0.8, green: 0.6, blue: 0.0, alpha: 1)
        head.lineWidth   = 1.5
        head.position    = CGPoint(x: -5, y: 3)
        container.addChild(head)
        // Inner hole
        let innerHole = SKShapeNode(circleOfRadius: 3.5)
        innerHole.fillColor   = SKColor(red: 0.163, green: 0.163, blue: 0.228, alpha: 1)
        innerHole.strokeColor = .clear
        innerHole.position    = CGPoint(x: -5, y: 3)
        container.addChild(innerHole)
        // Shaft
        let shaft = SKShapeNode(rectOf: CGSize(width: 18, height: 4), cornerRadius: 1)
        shaft.fillColor   = SKColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1)
        shaft.strokeColor = SKColor(red: 0.8, green: 0.6, blue: 0.0, alpha: 1)
        shaft.lineWidth   = 1
        shaft.position    = CGPoint(x: 4, y: 3)
        container.addChild(shaft)
        // Teeth
        let teeth: [(CGFloat, CGFloat)] = [(8, 1), (12, 1.5)]
        for (tx, th) in teeth {
            let t = SKShapeNode(rectOf: CGSize(width: 3, height: th * 3 + 3))
            t.fillColor   = SKColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1)
            t.strokeColor = .clear
            t.position    = CGPoint(x: tx, y: 3 - 2)
            container.addChild(t)
        }
        container.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: 0, y: 3, duration: 0.55),
            SKAction.moveBy(x: 0, y: -3, duration: 0.55)
        ])))
        return container
    }

    private func makeExitNode() -> SKNode {
        let container = SKNode()
        let bg = SKShapeNode(rectOf: CGSize(width: 40, height: 40), cornerRadius: 5)
        bg.fillColor   = SKColor(red: 0.08, green: 0.32, blue: 0.12, alpha: 1)
        bg.strokeColor = SKColor(red: 0.20, green: 0.75, blue: 0.30, alpha: 1)
        bg.lineWidth   = 2
        container.addChild(bg)
        for i in 0..<4 {
            let step = SKShapeNode(rectOf: CGSize(width: CGFloat(28 - i * 5), height: 4))
            step.fillColor   = SKColor(red: 0.25, green: 0.90, blue: 0.35, alpha: 1)
            step.strokeColor = .clear
            step.position    = CGPoint(x: 0, y: CGFloat(i) * 5 - 8)
            container.addChild(step)
        }
        container.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scale(to: 1.07, duration: 0.55),
            SKAction.scale(to: 0.93, duration: 0.55)
        ])))
        return container
    }

    private func makePressurePlateNode() -> SKShapeNode {
        let node = SKShapeNode(rectOf: CGSize(width: 32, height: 10), cornerRadius: 3)
        node.fillColor   = SKColor(red: 0.55, green: 0.45, blue: 0.18, alpha: 1)
        node.strokeColor = SKColor(red: 0.90, green: 0.75, blue: 0.35, alpha: 1)
        node.lineWidth   = 1.5
        node.position    = CGPoint(x: 0, y: -10)
        return node
    }

    private func makePushBlockNode() -> SKShapeNode {
        let node = SKShapeNode(rectOf: CGSize(width: 40, height: 40), cornerRadius: 4)
        node.fillColor   = SKColor(red: 0.40, green: 0.40, blue: 0.45, alpha: 1)
        node.strokeColor = SKColor(red: 0.62, green: 0.62, blue: 0.68, alpha: 1)
        node.lineWidth   = 2
        let hBar = SKShapeNode(rectOf: CGSize(width: 30, height: 3))
        hBar.fillColor = SKColor(red: 0.52, green: 0.52, blue: 0.57, alpha: 1)
        hBar.strokeColor = .clear
        node.addChild(hBar)
        let vBar = SKShapeNode(rectOf: CGSize(width: 3, height: 30))
        vBar.fillColor = SKColor(red: 0.52, green: 0.52, blue: 0.57, alpha: 1)
        vBar.strokeColor = .clear
        node.addChild(vBar)
        return node
    }

    private func makeSpikeNode() -> SKNode {
        let container = SKNode()
        for i in 0..<3 {
            let path = CGMutablePath()
            let bx = CGFloat(i) * 14.0 - 14.0
            path.move(to: CGPoint(x: bx,       y: -16))
            path.addLine(to: CGPoint(x: bx + 7,  y: -16))
            path.addLine(to: CGPoint(x: bx + 3.5, y: 14))
            path.closeSubpath()
            let spike = SKShapeNode(path: path)
            spike.fillColor   = SKColor(red: 0.70, green: 0.70, blue: 0.75, alpha: 1)
            spike.strokeColor = SKColor(red: 0.90, green: 0.90, blue: 0.95, alpha: 1)
            spike.lineWidth   = 1
            container.addChild(spike)
        }
        return container
    }

    private func makeLavaTile() -> SKShapeNode {
        let node = SKShapeNode(rectOf: CGSize(width: tileSize, height: tileSize))
        node.fillColor   = SKColor(red: 1.0, green: 0.35, blue: 0.0, alpha: 1)
        node.strokeColor = SKColor(red: 1.0, green: 0.60, blue: 0.1, alpha: 1)
        node.lineWidth   = 1
        node.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.customAction(withDuration: 0.5) { n, _ in
                (n as? SKShapeNode)?.fillColor = SKColor(red: 1.0, green: 0.55, blue: 0.05, alpha: 1)
            },
            SKAction.customAction(withDuration: 0.5) { n, _ in
                (n as? SKShapeNode)?.fillColor = SKColor(red: 0.90, green: 0.18, blue: 0.0, alpha: 1)
            }
        ])))
        return node
    }

    // MARK: - Monster visuals

    private func makeSlimeNode() -> SKShapeNode {
        let body = SKShapeNode(circleOfRadius: 16)
        body.fillColor   = SKColor(red: 0.15, green: 0.75, blue: 0.15, alpha: 1)
        body.strokeColor = SKColor(red: 0.30, green: 1.00, blue: 0.30, alpha: 1)
        body.lineWidth   = 2
        let le = SKShapeNode(circleOfRadius: 3)
        le.fillColor = .black; le.strokeColor = SKColor(white: 1, alpha: 0.5)
        le.lineWidth = 0.5; le.position = CGPoint(x: -6, y: 5)
        body.addChild(le)
        let re = SKShapeNode(circleOfRadius: 3)
        re.fillColor = .black; re.strokeColor = le.strokeColor
        re.lineWidth = 0.5; re.position = CGPoint(x: 6, y: 5)
        body.addChild(re)
        body.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scaleX(to: 1.12, y: 0.88, duration: 0.38),
            SKAction.scaleX(to: 0.88, y: 1.12, duration: 0.38)
        ])))
        return body
    }

    private func makeSkeletonNode() -> SKNode {
        let container = SKNode()
        let torso = SKShapeNode(rectOf: CGSize(width: 22, height: 26), cornerRadius: 2)
        torso.fillColor   = SKColor(red: 0.85, green: 0.85, blue: 0.80, alpha: 1)
        torso.strokeColor = SKColor(red: 0.50, green: 0.50, blue: 0.45, alpha: 1)
        torso.lineWidth   = 1.5; torso.position = CGPoint(x: 0, y: -8)
        container.addChild(torso)
        let skull = SKShapeNode(ellipseOf: CGSize(width: 20, height: 18))
        skull.fillColor   = SKColor(red: 0.92, green: 0.92, blue: 0.88, alpha: 1)
        skull.strokeColor = SKColor(red: 0.50, green: 0.50, blue: 0.45, alpha: 1)
        skull.lineWidth   = 1.5; skull.position = CGPoint(x: 0, y: 12)
        container.addChild(skull)
        let le = SKShapeNode(ellipseOf: CGSize(width: 5, height: 6))
        le.fillColor = .black; le.strokeColor = .clear; le.position = CGPoint(x: -5, y: 13)
        container.addChild(le)
        let re = SKShapeNode(ellipseOf: CGSize(width: 5, height: 6))
        re.fillColor = .black; re.strokeColor = .clear; re.position = CGPoint(x: 5, y: 13)
        container.addChild(re)
        for i in 0..<3 {
            let tooth = SKShapeNode(rectOf: CGSize(width: 4, height: 5))
            tooth.fillColor   = SKColor(red: 0.92, green: 0.92, blue: 0.88, alpha: 1)
            tooth.strokeColor = SKColor(red: 0.40, green: 0.40, blue: 0.35, alpha: 1)
            tooth.lineWidth   = 0.5; tooth.position = CGPoint(x: CGFloat(i) * 6 - 6, y: 5)
            container.addChild(tooth)
        }
        return container
    }

    private func makeDemonNode() -> SKNode {
        let container = SKNode()
        let body = SKShapeNode(ellipseOf: CGSize(width: 38, height: 42))
        body.fillColor   = SKColor(red: 0.50, green: 0.05, blue: 0.60, alpha: 1)
        body.strokeColor = SKColor(red: 0.85, green: 0.30, blue: 0.95, alpha: 1)
        body.lineWidth   = 2.5
        container.addChild(body)

        func makeHorn(flip: Bool) -> SKShapeNode {
            let h = SKShapeNode()
            let p = CGMutablePath()
            let sx: CGFloat = flip ? 1 : -1
            p.move(to:    CGPoint(x: sx * 10, y: 18))
            p.addLine(to: CGPoint(x: sx * 18, y: 33))
            p.addLine(to: CGPoint(x: sx * 4,  y: 22))
            p.closeSubpath()
            h.path = p
            h.fillColor   = SKColor(red: 0.60, green: 0.05, blue: 0.10, alpha: 1)
            h.strokeColor = SKColor(red: 0.90, green: 0.20, blue: 0.20, alpha: 1)
            h.lineWidth   = 1
            return h
        }
        container.addChild(makeHorn(flip: false))
        container.addChild(makeHorn(flip: true))

        for (ex, col) in [(-9, SKColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0)),
                           (9,  SKColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0))] as [(Int, SKColor)] {
            let eye = SKShapeNode(ellipseOf: CGSize(width: 9, height: 8))
            eye.fillColor = col; eye.strokeColor = .clear
            eye.position = CGPoint(x: ex, y: 6)
            container.addChild(eye)
            let pupil = SKShapeNode(circleOfRadius: 3)
            pupil.fillColor = .black; pupil.strokeColor = .clear
            pupil.position = CGPoint(x: ex, y: 6)
            container.addChild(pupil)
        }
        container.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scale(to: 1.06, duration: 0.50),
            SKAction.scale(to: 0.96, duration: 0.50)
        ])))
        return container
    }

    // MARK: - Torch lights

    private func addTorchLights() {
        let positions: [(Int, Int)] = mapMode == .short
            ? [(2, 1), (12, 4), (6, 10), (12, 10)]
            : [(1,1),(9,1),(17,1),(1,9),(9,9),(17,9),(1,16),(9,16),(17,16)]
        for (c, r) in positions {
            guard c < cols, r < rows else { continue }
            let pos = worldPos(TileCoord(col: c, row: r))
            // Glow
            let glow = SKShapeNode(circleOfRadius: tileSize * 2.5)
            glow.fillColor   = SKColor(red: 1.0, green: 0.55, blue: 0.15, alpha: 0.07)
            glow.strokeColor = .clear
            glow.position    = pos
            glow.zPosition   = 0.5
            glow.blendMode   = .add
            worldLayer.addChild(glow)
            glow.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.customAction(withDuration: 0.35) { n, _ in
                    (n as? SKShapeNode)?.fillColor = SKColor(red: 1.0, green: 0.55, blue: 0.15, alpha: 0.09)
                },
                SKAction.customAction(withDuration: 0.35) { n, _ in
                    (n as? SKShapeNode)?.fillColor = SKColor(red: 1.0, green: 0.45, blue: 0.10, alpha: 0.05)
                }
            ])))
            // Flame dot
            let flame = SKShapeNode(circleOfRadius: 4)
            flame.fillColor   = SKColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 1)
            flame.strokeColor = .clear
            flame.position    = pos
            flame.zPosition   = 2
            flame.blendMode   = .add
            worldLayer.addChild(flame)
        }
    }

    // MARK: - Game loop

    override func update(_ currentTime: TimeInterval) {
        guard !isGameOver, !hasWon else { return }
        let dt = (lastUpdateTime == 0) ? 0.0 : min(currentTime - lastUpdateTime, 0.05)
        lastUpdateTime = currentTime

        updateSpikes(dt: dt, currentTime: currentTime)
        updateMonsters(dt: dt, currentTime: currentTime)
        updateProjectiles(dt: dt)
    }

    // MARK: - Spike logic

    private func updateSpikes(dt: TimeInterval, currentTime: TimeInterval) {
        spikeTimer += dt
        if spikeTimer >= 1.2 {
            spikeTimer = 0
            spikeActive.toggle()
            for (_, node) in spikeNodes {
                node.run(SKAction.scale(to: spikeActive ? 1.0 : 0.25, duration: 0.15))
            }
        }
        if spikeActive && spikeCoords.contains(playerCoord) {
            takeDamage(amount: 1, at: currentTime)
        }
        if mapData[playerCoord.row][playerCoord.col] == .lava {
            takeDamage(amount: playerHP, at: currentTime)  // instant kill
        }
    }

    // MARK: - Monster AI

    private func updateMonsters(dt: TimeInterval, currentTime: TimeInterval) {
        for monster in monsters where !monster.isDead {
            monster.moveTimer += dt
            let moveInterval: Double
            switch monster.kind {
            case .slime:    moveInterval = 1.5
            case .skeleton: moveInterval = 0.80
            case .demon:    moveInterval = 1.20
            }
            if monster.moveTimer >= moveInterval {
                monster.moveTimer = 0
                performMonsterMove(monster)
            }
            if monster.kind == .demon {
                monster.shootTimer += dt
                if monster.shootTimer >= 2.0 {
                    monster.shootTimer = 0
                    fireProjectile(from: monster)
                }
                monster.spawnTimer += dt
                if monster.spawnTimer >= 5.0 {
                    monster.spawnTimer = 0
                    spawnSlime(near: monster)
                }
            }
            if monster.coord == playerCoord {
                takeDamage(amount: monster.damage, at: currentTime)
            }
        }
    }

    private func performMonsterMove(_ monster: DungeonMonster) {
        switch monster.kind {
        case .slime:
            let dirs: [DungeonDirection] = [.up, .down, .left, .right]
            if let dir = dirs.randomElement() {
                let t = monster.coord.moved(dir)
                if monsterCanOccupy(t) { animateMonster(monster, to: t) }
            }
        case .skeleton, .demon:
            let dx = playerCoord.col - monster.coord.col
            let dy = playerCoord.row - monster.coord.row
            let dist = abs(dx) + abs(dy)
            let chaseRange = monster.kind == .demon ? 999 : 6
            if dist > 0 && dist <= chaseRange {
                let preferred = bestDirection(from: monster.coord, to: playerCoord)
                var moved = false
                for dir in [preferred, perpDirs(preferred)[0], perpDirs(preferred)[1], opposite(preferred)] {
                    let t = monster.coord.moved(dir)
                    if monsterCanOccupy(t) { animateMonster(monster, to: t); moved = true; break }
                }
                if !moved && monster.kind == .skeleton {
                    // wander
                    let dirs: [DungeonDirection] = [.up, .down, .left, .right]
                    if let dir = dirs.randomElement() {
                        let t = monster.coord.moved(dir)
                        if monsterCanOccupy(t) { animateMonster(monster, to: t) }
                    }
                }
            } else if monster.kind == .skeleton {
                let dirs: [DungeonDirection] = [.up, .down, .left, .right]
                if let dir = dirs.randomElement() {
                    let t = monster.coord.moved(dir)
                    if monsterCanOccupy(t) { animateMonster(monster, to: t) }
                }
            }
        }
    }

    private func bestDirection(from: TileCoord, to: TileCoord) -> DungeonDirection {
        let dx = to.col - from.col
        let dy = to.row - from.row
        if abs(dx) >= abs(dy) { return dx > 0 ? .right : .left }
        else { return dy > 0 ? .down : .up }
    }

    private func perpDirs(_ dir: DungeonDirection) -> [DungeonDirection] {
        switch dir {
        case .up, .down:   return [.left, .right]
        case .left, .right: return [.up, .down]
        }
    }

    private func opposite(_ dir: DungeonDirection) -> DungeonDirection {
        switch dir {
        case .up: return .down; case .down: return .up
        case .left: return .right; case .right: return .left
        }
    }

    private func monsterCanOccupy(_ coord: TileCoord) -> Bool {
        guard coord.col >= 0, coord.row >= 0, coord.col < cols, coord.row < rows else { return false }
        let kind = mapData[coord.row][coord.col]
        switch kind {
        case .wall, .lockedDoor, .hiddenWall, .lava: return false
        default: break
        }
        if pushBlocks[coord] != nil { return false }
        for m in monsters where !m.isDead && m.coord == coord { return false }
        return true
    }

    private func animateMonster(_ monster: DungeonMonster, to coord: TileCoord) {
        monster.coord = coord
        monster.node.run(SKAction.move(to: worldPos(coord), duration: 0.15))
    }

    private func fireProjectile(from monster: DungeonMonster) {
        let dx = playerCoord.col - monster.coord.col
        let dy = playerCoord.row - monster.coord.row
        guard dx != 0 || dy != 0 else { return }
        let dir = bestDirection(from: monster.coord, to: playerCoord)
        let startCoord = monster.coord.moved(dir)
        guard isTileWalkable(startCoord) else { return }

        let proj = SKShapeNode(circleOfRadius: 6)
        proj.fillColor   = SKColor(red: 0.8, green: 0.2, blue: 1.0, alpha: 1)
        proj.strokeColor = SKColor(red: 1.0, green: 0.5, blue: 1.0, alpha: 1)
        proj.lineWidth   = 1.5
        proj.blendMode   = .add
        proj.position    = worldPos(monster.coord)
        proj.zPosition   = 5
        worldLayer.addChild(proj)
        proj.run(SKAction.move(to: worldPos(startCoord), duration: 0.10))

        projectiles.append(DungeonProjectile(coord: startCoord, direction: dir, node: proj))
    }

    private func spawnSlime(near demon: DungeonMonster) {
        for dir in ([.up, .down, .left, .right] as [DungeonDirection]).shuffled() {
            let c = demon.coord.moved(dir)
            if monsterCanOccupy(c) {
                let node = makeSlimeNode()
                node.position = worldPos(c)
                node.zPosition = 4
                worldLayer.addChild(node)
                monsters.append(DungeonMonster(kind: .slime, coord: c, node: node))
                return
            }
        }
    }

    // MARK: - Projectile update

    private func updateProjectiles(dt: TimeInterval) {
        projTimer += dt
        guard projTimer >= 0.12 else { return }
        projTimer = 0

        var dead: [Int] = []
        for i in projectiles.indices {
            let next = projectiles[i].coord.moved(projectiles[i].direction)
            if !isTileWalkable(next) || projectiles[i].travelled >= 8 {
                poofProjectile(projectiles[i].node)
                dead.append(i)
                continue
            }
            if next == playerCoord {
                poofProjectile(projectiles[i].node)
                takeDamage(amount: 2, at: lastUpdateTime)
                dead.append(i)
                continue
            }
            projectiles[i].coord = next
            projectiles[i].travelled += 1
            projectiles[i].node.run(SKAction.move(to: worldPos(next), duration: 0.10))
        }
        for idx in dead.reversed() { projectiles.remove(at: idx) }
    }

    private func poofProjectile(_ node: SKNode) {
        node.run(SKAction.sequence([
            SKAction.group([SKAction.scale(to: 0.01, duration: 0.1), SKAction.fadeOut(withDuration: 0.1)]),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Player damage

    private func takeDamage(amount: Int, at time: TimeInterval) {
        guard time > invincibleUntil, !isGameOver else { return }
        playerHP = max(0, playerHP - amount)
        invincibleUntil = time + 0.75
        // Flash red
        playerNode.run(SKAction.sequence([
            SKAction.colorize(with: .red, colorBlendFactor: 0.9, duration: 0),
            SKAction.wait(forDuration: 0.15),
            SKAction.colorize(with: .red, colorBlendFactor: 0, duration: 0.15)
        ]))
        refreshHUD()
        if playerHP <= 0 { triggerLose() }
    }

    // MARK: - Player movement (public API)

    func movePlayer(direction: DungeonDirection) {
        guard !isMoving, !isGameOver, !hasWon else { return }
        playerFacing = direction
        orientSword()

        let target = playerCoord.moved(direction)

        // Push block interaction
        if let blockNode = pushBlocks[target] {
            let blockDest = target.moved(direction)
            guard isTileWalkable(blockDest),
                  mapData[blockDest.row][blockDest.col] != .lava else { return }
            pushBlocks.removeValue(forKey: target)
            pushBlocks[blockDest] = blockNode
            blockNode.run(SKAction.move(to: worldPos(blockDest), duration: moveAnimDuration))
            evaluatePlates(blockMovedTo: blockDest, from: target)
        }

        // Locked door: need key
        if mapData[target.row][target.col] == .lockedDoor {
            if playerKeys > 0 {
                playerKeys -= 1
                openDoor(at: target)
                refreshHUD()
            }
            return
        }

        // Hidden wall: reveal passage
        if mapData[target.row][target.col] == .hiddenWall {
            mapData[target.row][target.col] = .floor
            if let node = tileNodes[target.row][target.col] {
                node.run(SKAction.sequence([
                    SKAction.fadeOut(withDuration: 0.25),
                    SKAction.removeFromParent()
                ]))
                tileNodes[target.row][target.col] = nil
            }
            return
        }

        guard isTileWalkable(target) else { return }

        isMoving = true
        playerCoord = target
        smoothCameraToPlayer()

        playerNode.run(SKAction.move(to: worldPos(target), duration: moveAnimDuration)) { [weak self] in
            guard let self else { return }
            self.isMoving = false
            self.evaluatePlates(blockMovedTo: nil, from: nil)
            self.onPlayerLanded()
        }
    }

    private func orientSword() {
        switch playerFacing {
        case .right: swordNode.position = CGPoint(x: 22, y:  4); swordNode.zRotation = 0
        case .left:  swordNode.position = CGPoint(x: -22, y: 4); swordNode.zRotation = 0
        case .up:    swordNode.position = CGPoint(x:  4, y: 22); swordNode.zRotation = .pi / 2
        case .down:  swordNode.position = CGPoint(x:  4, y: -22); swordNode.zRotation = .pi / 2
        }
    }

    private func onPlayerLanded() {
        // Key pickup
        if let keyNode = keyNodesByCoord[playerCoord], !pickedUpKeys.contains(playerCoord) {
            pickedUpKeys.insert(playerCoord)
            playerKeys += 1
            keyNode.run(SKAction.sequence([
                SKAction.group([
                    SKAction.scale(to: 2.2, duration: 0.22),
                    SKAction.fadeOut(withDuration: 0.22)
                ]),
                SKAction.removeFromParent()
            ]))
            refreshHUD()
        }
        // Exit
        if mapData[playerCoord.row][playerCoord.col] == .exit {
            triggerWin()
        }
        // Long map: win when demon dead and no exit (boss defeated trigger)
    }

    // MARK: - Plate evaluation

    private func evaluatePlates(blockMovedTo: TileCoord?, from blockFrom: TileCoord?) {
        for (plateCoord, doorCoord) in plateConnections {
            let blockOnPlate = pushBlocks[plateCoord] != nil
            let playerOnPlate = playerCoord == plateCoord
            let nowActive = blockOnPlate || playerOnPlate
            let wasActive = plateActive[plateCoord] ?? false
            guard nowActive != wasActive else { continue }
            plateActive[plateCoord] = nowActive
            if nowActive { openDoor(at: doorCoord, animated: true) }
            else          { closeDoor(at: doorCoord) }
            // Visual feedback on plate
            if let plateNode = tileNodes[plateCoord.row][plateCoord.col] as? SKShapeNode {
                plateNode.run(SKAction.customAction(withDuration: 0) { _, _ in
                    plateNode.fillColor = nowActive
                        ? SKColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1)
                        : SKColor(red: 0.55, green: 0.45, blue: 0.18, alpha: 1)
                })
            }
        }
    }

    private func openDoor(at coord: TileCoord, animated: Bool = false) {
        guard mapData[coord.row][coord.col] == .lockedDoor else { return }
        mapData[coord.row][coord.col] = .openDoor
        if let node = tileNodes[coord.row][coord.col] {
            if animated {
                node.run(SKAction.sequence([
                    SKAction.group([
                        SKAction.scale(to: 0.05, duration: 0.22),
                        SKAction.fadeOut(withDuration: 0.22)
                    ]),
                    SKAction.removeFromParent()
                ]))
            } else {
                node.removeFromParent()
            }
            tileNodes[coord.row][coord.col] = nil
        }
    }

    private func closeDoor(at coord: TileCoord) {
        guard mapData[coord.row][coord.col] == .openDoor else { return }
        guard playerCoord != coord, pushBlocks[coord] == nil else { return }
        mapData[coord.row][coord.col] = .lockedDoor
        let node = makeLockedDoor()
        node.position = worldPos(coord)
        node.zPosition = 2
        node.alpha = 0
        worldLayer.addChild(node)
        node.run(SKAction.fadeIn(withDuration: 0.2))
        tileNodes[coord.row][coord.col] = node
    }

    // MARK: - Player attack (public API)

    func playerAttack() {
        guard !isGameOver, !hasWon else { return }
        let sweep: CGFloat = .pi * 0.75
        swordNode.run(SKAction.sequence([
            SKAction.rotate(byAngle: sweep, duration: 0.14),
            SKAction.rotate(byAngle: -sweep, duration: 0.10)
        ]))
        let hitCoord = playerCoord.moved(playerFacing)
        for monster in monsters where !monster.isDead && monster.coord == hitCoord {
            damageMonster(monster)
        }
    }

    private func damageMonster(_ monster: DungeonMonster) {
        monster.hp -= 1
        monster.node.run(SKAction.sequence([
            SKAction.colorize(with: .white, colorBlendFactor: 1, duration: 0),
            SKAction.wait(forDuration: 0.10),
            SKAction.colorize(with: .white, colorBlendFactor: 0, duration: 0.10)
        ]))
        if monster.hp <= 0 { killMonster(monster) }
    }

    private func killMonster(_ monster: DungeonMonster) {
        monster.isDead = true
        monster.node.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 1.6, duration: 0.20),
                SKAction.fadeOut(withDuration: 0.20)
            ]),
            SKAction.removeFromParent()
        ]))
        if mapMode == .long, monster.kind == .demon {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.triggerWin()
            }
        }
    }

    // MARK: - Win / Lose

    private func triggerWin() {
        guard !hasWon, !isGameOver else { return }
        hasWon = true
        if let cb = onWin { DispatchQueue.main.async { cb() }; return }
        showBanner(title: "YOU WIN!", sub: "Dungeon cleared", color: SKColor(red: 0.08, green: 0.50, blue: 0.10, alpha: 0.93))
    }

    private func triggerLose() {
        guard !isGameOver else { return }
        isGameOver = true
        if let cb = onLose { DispatchQueue.main.async { cb() }; return }
        showBanner(title: "YOU DIED", sub: "Tap to try again", color: SKColor(red: 0.45, green: 0.0, blue: 0.0, alpha: 0.93))
    }

    private func showBanner(title: String, sub: String, color: SKColor) {
        let bg = SKShapeNode(rectOf: CGSize(width: 440, height: 200), cornerRadius: 18)
        bg.fillColor   = color
        bg.strokeColor = SKColor(white: 1, alpha: 0.6)
        bg.lineWidth   = 2
        bg.zPosition   = 200
        cameraNode.addChild(bg)

        let t = SKLabelNode(text: title)
        t.fontName = "AvenirNext-Bold"; t.fontSize = 50; t.fontColor = .white
        t.verticalAlignmentMode = .center; t.position = CGPoint(x: 0, y: 38)
        bg.addChild(t)

        let s = SKLabelNode(text: sub)
        s.fontName = "AvenirNext-Regular"; s.fontSize = 21
        s.fontColor = SKColor(white: 0.88, alpha: 1)
        s.verticalAlignmentMode = .center; s.position = CGPoint(x: 0, y: -26)
        bg.addChild(s)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isGameOver, onLose == nil else { return }
        restartGame()
    }

    private func restartGame() {
        removeAllChildren()
        monsters.removeAll(); projectiles.removeAll()
        pushBlocks.removeAll(); plateConnections.removeAll(); plateActive.removeAll()
        spikeCoords.removeAll(); spikeNodes.removeAll()
        keyNodesByCoord.removeAll(); pickedUpKeys.removeAll()
        tileNodes = []; mapData = []
        isGameOver = false; hasWon = false
        playerHP = playerMaxHP; playerKeys = 0
        isMoving = false; lastUpdateTime = 0
        spikeTimer = 0; projTimer = 0
        hasBuilt = false
        if let v = view { didMove(to: v) }
    }

    // MARK: - Map strings

    private func shortMapString() -> String {
        // 15 cols × 12 rows — each row exactly 15 chars
        // Puzzle flow:
        //   1. Player (@) starts at row 10 col 1
        //   2. Block (B) at row 10 col 2; plate (P) at row 10 col 4
        //      Push block right→right → lands on plate → opens lower locked door (row 7 col 5)
        //   3. Walk through now-open door into key alcove → pick up key (K at row 8 col 8)
        //   4. Return, use key on upper locked door (row 4 col 5)
        //   5. Fight monsters in right half → reach exit (E at row 10 col 13)
        return [
            "###############",
            "#.....#.......#",
            "#.....#...M...#",
            "#.....#.......#",
            "#.....D.......#",
            "#.....#...k...#",
            "#.....#.......#",
            "#.....D...K...#",
            "#.....#.......#",
            "#.....#.......#",
            "#@B.P.#......E#",
            "###############",
        ].joined(separator: "\n")
    }

    private func longMapString() -> String {
        // 20 cols × 18 rows  (uses H = hidden wall passage)
        return [
            "####################",
            "#@..#....#...#.....#",
            "#...#....#...#.....#",
            "#...D....D...#..k..#",
            "#...#....#...######.",
            "###.######...#.....#",
            "#K..#........D.....#",
            "#...#........#.....#",
            "##D##....#...#..M..#",
            "#...........##.....#",
            "#.P.#....#...#.....#",
            "#...#....#...##D####",
            "###.#....#......K..#",
            "#.B.####.######....#",
            "#...#..S.S.S.#.....#",
            "#...#........#..k..#",
            "##D##....###.#.....#",
            "#K..........B..P..X#",
            "#.................E#",
            "####################",
        ].joined(separator: "\n")
    }
}
