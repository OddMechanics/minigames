import SpriteKit

// ─────────────────────────────────────────────────────────────────────────────
// 3×3 jigsaw puzzle using Drawing.png.
// Layout: board on the right half of the scene, scattered pieces on the left.
// Drag pieces with touch/mouse; pieces snap when released within snapDist pts.
// ─────────────────────────────────────────────────────────────────────────────

final class JigsawPuzzleScene: SKScene {

    // MARK: - Constants
    private let n        = 3
    private let tileSize: CGFloat = 160
    private let snapDist: CGFloat = 36

    // Board bottom-left corner in scene space
    private var boardOrigin: CGPoint = .zero

    // MARK: - Edge tables
    // hTabs[r][c] = true → piece(r,c) has tab going DOWN; piece(r+1,c) has blank going UP
    private var hTabs: [[Bool]] = []
    // vTabs[r][c] = true → piece(r,c) has tab going RIGHT; piece(r,c+1) has blank going LEFT
    private var vTabs: [[Bool]] = []

    // MARK: - Marathon callback
    var onWin: (() -> Void)?

    // MARK: - State
    private var hasBuiltLevel = false
    private var pieces: [JigsawPiece] = []
    private var snappedCount = 0
    private var dragging: JigsawPiece?
    private var dragOffset: CGPoint = .zero
    private var counterLabel: SKLabelNode!
    private var winOverlay: SKNode?

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        guard !hasBuiltLevel else { return }
        hasBuiltLevel = true
        backgroundColor = SKColor(red: 0.85, green: 0.82, blue: 0.78, alpha: 1)

        let boardSize = tileSize * CGFloat(n)
        // Board sits on the right, centred vertically
        boardOrigin = CGPoint(
            x: size.width - boardSize - 20,
            y: (size.height - boardSize) / 2
        )

        setupHUD()
        addBoardOutline()
        generateEdges()
        buildPieces()
        scatterPieces()
    }

    // MARK: - HUD

    private func setupHUD() {
        counterLabel = SKLabelNode(text: "0 / \(n*n) placed")
        counterLabel.fontName = "AvenirNext-Bold"
        counterLabel.fontSize = 20
        counterLabel.fontColor = SKColor(white: 0.25, alpha: 1)
        counterLabel.horizontalAlignmentMode = .center
        counterLabel.position = CGPoint(x: boardOrigin.x + tileSize * CGFloat(n) / 2,
                                         y: boardOrigin.y - 36)
        counterLabel.zPosition = 50
        addChild(counterLabel)
    }

    private func updateCounter() {
        counterLabel.text = "\(snappedCount) / \(n*n) placed"
    }

    // MARK: - Edge generation

    private func generateEdges() {
        hTabs = (0..<(n-1)).map { _ in (0..<n).map { _ in Bool.random() } }
        vTabs = (0..<n).map   { _ in (0..<(n-1)).map { _ in Bool.random() } }
    }

    // MARK: - Board outline (shows where pieces belong, no image)

    private func addBoardOutline() {
        let boardSize = tileSize * CGFloat(n)
        let center = CGPoint(x: boardOrigin.x + boardSize / 2,
                              y: boardOrigin.y + boardSize / 2)

        let bg = SKShapeNode(rectOf: CGSize(width: boardSize, height: boardSize))
        bg.fillColor   = SKColor(white: 0.95, alpha: 0.6)
        bg.strokeColor = SKColor(white: 0.55, alpha: 1)
        bg.lineWidth   = 2
        bg.position    = center
        bg.zPosition   = -10
        addChild(bg)
    }

    // MARK: - (unused) Hint image

    private func addHintImage() {
        let boardSize = tileSize * CGFloat(n)
        let center = CGPoint(x: boardOrigin.x + boardSize / 2,
                              y: boardOrigin.y + boardSize / 2)

        let hint = SKSpriteNode(imageNamed: "Drawing")
        hint.size   = CGSize(width: boardSize, height: boardSize)
        hint.position  = center
        hint.alpha     = 0.18
        hint.zPosition = -10
        addChild(hint)

        let border = SKShapeNode(rectOf: CGSize(width: boardSize + 2, height: boardSize + 2))
        border.strokeColor = SKColor(white: 0.35, alpha: 1)
        border.lineWidth   = 1.5
        border.fillColor   = .clear
        border.position    = center
        border.zPosition   = -9
        addChild(border)
    }

    // MARK: - Piece construction

    private func buildPieces() {
        let boardSize = tileSize * CGFloat(n)

        for row in 0..<n {
            for col in 0..<n {
                let piece = makePiece(row: row, col: col, boardSize: boardSize)
                addChild(piece)
                pieces.append(piece)
            }
        }
    }

    private func makePiece(row: Int, col: Int, boardSize: CGFloat) -> JigsawPiece {
        // Which edge style does this piece have on each side?
        let topS    = edgeStyle(row: row,   col: col,   side: .top)
        let rightS  = edgeStyle(row: row,   col: col,   side: .right)
        let bottomS = edgeStyle(row: row,   col: col,   side: .bottom)
        let leftS   = edgeStyle(row: row,   col: col,   side: .left)

        let path = makeJigsawPath(ts: tileSize,
                                   top: topS, right: rightS,
                                   bottom: bottomS, left: leftS)

        // Image offset: full image positioned inside crop node so correct tile shows
        // Derivation: imageOffset = ((n-1)/2 - col, row - (n-1)/2) * tileSize
        let halfN = CGFloat(n - 1) / 2.0
        let imgOffset = CGPoint(
            x: (halfN - CGFloat(col)) * tileSize,
            y: (CGFloat(row) - halfN) * tileSize
        )

        // Solution position (scene space): centre of tile (row, col)
        //   x = boardOrigin.x + (col + 0.5) * tileSize
        //   y = boardOrigin.y + (n - 1 - row + 0.5) * tileSize   [row 0 = top = highest y]
        let solPos = CGPoint(
            x: boardOrigin.x + (CGFloat(col) + 0.5) * tileSize,
            y: boardOrigin.y + (CGFloat(n - 1 - row) + 0.5) * tileSize
        )

        return JigsawPiece(row: row, col: col,
                            shapePath: path,
                            imageSize: CGSize(width: boardSize, height: boardSize),
                            imageOffset: imgOffset,
                            solutionPos: solPos)
    }

    // MARK: - Edge style helpers

    private enum Side { case top, right, bottom, left }
    private enum EdgeStyle { case flat, tabOut, blankIn }

    private func edgeStyle(row: Int, col: Int, side: Side) -> EdgeStyle {
        switch side {
        case .top:
            guard row > 0 else { return .flat }
            return hTabs[row-1][col] ? .blankIn : .tabOut
        case .bottom:
            guard row < n-1 else { return .flat }
            return hTabs[row][col] ? .tabOut : .blankIn
        case .left:
            guard col > 0 else { return .flat }
            return vTabs[row][col-1] ? .blankIn : .tabOut
        case .right:
            guard col < n-1 else { return .flat }
            return vTabs[row][col] ? .tabOut : .blankIn
        }
    }

    // MARK: - Jigsaw path

    private func makeJigsawPath(ts: CGFloat,
                                 top: EdgeStyle, right: EdgeStyle,
                                 bottom: EdgeStyle, left: EdgeStyle) -> CGPath {
        let h = ts / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -h, y: h))                      // top-left

        addEdge(path, from: CGPoint(x: -h, y:  h),
                      to:   CGPoint(x:  h, y:  h), style: top)   // → top-right
        addEdge(path, from: CGPoint(x:  h, y:  h),
                      to:   CGPoint(x:  h, y: -h), style: right) // ↓ bottom-right
        addEdge(path, from: CGPoint(x:  h, y: -h),
                      to:   CGPoint(x: -h, y: -h), style: bottom)// ← bottom-left
        addEdge(path, from: CGPoint(x: -h, y: -h),
                      to:   CGPoint(x: -h, y:  h), style: left)  // ↑ top-left
        path.closeSubpath()
        return path
    }

    // Draws one edge of the jigsaw piece.
    // The tab protrudes in the CCW-perpendicular direction from (a→b).
    // For clockwise drawing order: top→right: the CCW-perp of (+x) is (+y) = outward ✓
    private func addEdge(_ path: CGMutablePath,
                          from a: CGPoint, to b: CGPoint,
                          style: EdgeStyle) {
        guard style != .flat else { path.addLine(to: b); return }

        let sign: CGFloat = style == .tabOut ? 1 : -1
        let dx = b.x - a.x,  dy = b.y - a.y
        let len = sqrt(dx*dx + dy*dy)
        let ex = dx/len, ey = dy/len
        // CCW perpendicular, scaled by tab direction
        let px = -ey * sign, py = ex * sign
        let bump = len * 0.28    // bump height

        // Helper: point t-fraction along edge + d units perpendicular
        func e(_ t: CGFloat, _ d: CGFloat = 0) -> CGPoint {
            CGPoint(x: a.x + ex*len*t + px*d,
                    y: a.y + ey*len*t + py*d)
        }

        path.addLine(to: e(0.28))
        // Rise to peak
        path.addCurve(to: e(0.50, bump),
                      control1: e(0.28, bump * 0.18),
                      control2: e(0.38, bump))
        // Return from peak
        path.addCurve(to: e(0.72),
                      control1: e(0.62, bump),
                      control2: e(0.72, bump * 0.18))
        path.addLine(to: b)
    }

    // MARK: - Scatter pieces

    private func scatterPieces() {
        // Left half of scene: x in [tileSize*0.6 … boardOrigin.x - tileSize*0.6]
        let margin = tileSize * 0.65
        let xMin = margin, xMax = boardOrigin.x - margin
        let yMin = margin, yMax = size.height - margin

        var positions: [CGPoint] = []
        // Generate a rough grid so pieces don't all stack
        let cols = 3, rows = 3
        let cellW = (xMax - xMin) / CGFloat(cols)
        let cellH = (yMax - yMin) / CGFloat(rows)
        for r in 0..<rows {
            for c in 0..<cols {
                let bx = xMin + CGFloat(c) * cellW
                let by = yMin + CGFloat(r) * cellH
                let jx = CGFloat.random(in: bx+margin*0.3 ... bx+cellW-margin*0.3)
                let jy = CGFloat.random(in: by+margin*0.3 ... by+cellH-margin*0.3)
                positions.append(CGPoint(x: jx, y: jy))
            }
        }
        positions.shuffle()

        for (i, piece) in pieces.enumerated() {
            piece.position = positions[i]
            piece.zPosition = CGFloat(i) + 1
        }
    }

    // MARK: - Touch / drag

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard dragging == nil, let touch = touches.first else { return }
        guard winOverlay == nil else { restartGame(); return }

        let loc = touch.location(in: self)
        // Pick the topmost piece whose shape contains the touch
        let hit = pieces
            .filter { !$0.isSnapped }
            .filter { piece in
                let local = convert(loc, to: piece)
                return UIBezierPath(cgPath: piece.shapePath).contains(local)
            }
            .max(by: { $0.zPosition < $1.zPosition })

        if let piece = hit {
            dragging   = piece
            dragOffset = CGPoint(x: piece.position.x - loc.x,
                                  y: piece.position.y - loc.y)
            piece.zPosition = 100
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let piece = dragging, let touch = touches.first else { return }
        let loc = touch.location(in: self)
        piece.position = CGPoint(x: loc.x + dragOffset.x,
                                  y: loc.y + dragOffset.y)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseDragging()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseDragging()
    }

    private func releaseDragging() {
        guard let piece = dragging else { return }
        dragging = nil

        let dist = hypot(piece.position.x - piece.solutionPos.x,
                          piece.position.y - piece.solutionPos.y)
        if dist < snapDist {
            snapPiece(piece)
        } else {
            // Restore reasonable z so it doesn't float above everything
            piece.zPosition = CGFloat(pieces.firstIndex(of: piece) ?? 0) + 1
        }
    }

    private func snapPiece(_ piece: JigsawPiece) {
        piece.isSnapped   = true
        piece.zPosition   = -1   // sits under unplaced pieces
        snappedCount     += 1
        updateCounter()

        piece.run(SKAction.sequence([
            SKAction.move(to: piece.solutionPos, duration: 0.12),
            SKAction.scale(to: 1.04, duration: 0.06),
            SKAction.scale(to: 1.00, duration: 0.06)
        ]))

        if snappedCount == n * n { showWin() }
    }

    // MARK: - Win

    private func showWin() {
        if onWin != nil { DispatchQueue.main.async { self.onWin?() }; return }
        let overlay = SKNode()
        overlay.zPosition = 200

        let bg = SKSpriteNode(color: SKColor(white: 0, alpha: 0.75),
                               size: CGSize(width: 560, height: 230))
        bg.position = CGPoint(x: size.width/2, y: size.height/2)
        overlay.addChild(bg)

        let title = SKLabelNode(text: "Puzzle Complete!")
        title.fontName = "AvenirNext-Bold"
        title.fontSize = 48
        title.fontColor = .yellow
        title.position  = CGPoint(x: size.width/2, y: size.height/2 + 30)
        overlay.addChild(title)

        let sub = SKLabelNode(text: "Tap to play again")
        sub.fontName = "AvenirNext-Regular"
        sub.fontSize  = 22
        sub.fontColor = .white
        sub.position  = CGPoint(x: size.width/2, y: size.height/2 - 26)
        overlay.addChild(sub)

        addChild(overlay)
        winOverlay = overlay
    }

    private func restartGame() {
        winOverlay?.removeFromParent()
        winOverlay = nil
        pieces.forEach { $0.removeFromParent() }
        pieces.removeAll()
        snappedCount = 0

        generateEdges()
        buildPieces()
        scatterPieces()
        updateCounter()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - JigsawPiece (SKCropNode subclass)
// ─────────────────────────────────────────────────────────────────────────────

final class JigsawPiece: SKCropNode {

    let row:         Int
    let col:         Int
    let shapePath:   CGPath
    let solutionPos: CGPoint
    var isSnapped    = false

    init(row: Int, col: Int,
         shapePath: CGPath,
         imageSize: CGSize,
         imageOffset: CGPoint,
         solutionPos: CGPoint) {
        self.row         = row
        self.col         = col
        self.shapePath   = shapePath
        self.solutionPos = solutionPos
        super.init()

        // White background so the transparent parts of Drawing.png show as white
        let bg = SKShapeNode(path: shapePath)
        bg.fillColor   = .white
        bg.strokeColor = .clear
        bg.zPosition   = -1
        addChild(bg)

        // Full Drawing.png image — correct region shows through the mask
        let img = SKSpriteNode(imageNamed: "Drawing")
        img.size     = imageSize
        img.position = imageOffset
        addChild(img)

        // Crop mask: white = visible
        let mask = SKShapeNode(path: shapePath)
        mask.fillColor   = .white
        mask.strokeColor = .clear
        maskNode = mask

        // Visible border drawn on top
        let border = SKShapeNode(path: shapePath)
        border.fillColor   = .clear
        border.strokeColor = SKColor(white: 0.45, alpha: 0.9)
        border.lineWidth   = 1.5
        border.zPosition   = 20
        addChild(border)
    }

    required init?(coder: NSCoder) { fatalError() }
}
