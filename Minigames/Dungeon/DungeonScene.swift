import SpriteKit
import UIKit

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

// MARK: - PixelArt helper

struct PixelArt {

    // Each pixel unit in a 16x16 canvas scaled to `tileSize`
    private static let canvasSize = CGSize(width: 16, height: 16)
    private static let scale: CGFloat = 3   // 16*3 = 48pt

    static func texture(size: CGSize = canvasSize, draw: (CGContext, CGSize) -> Void) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            draw(ctx.cgContext, size)
        }
        let tex = SKTexture(image: img)
        tex.filteringMode = .nearest
        return tex
    }

    // Filled rect helper (flipped coords — UIKit Y is top-down)
    static func fillRect(_ ctx: CGContext, x: Int, y: Int, w: Int, h: Int, color: UIColor) {
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: x, y: y, width: w, height: h))
    }

    // MARK: Floor tile — dark stone with subtle cracks
    static func floorTile() -> SKTexture {
        texture { ctx, size in
            // Base dark gray-blue stone
            fillRect(ctx, x:0, y:0, w:16, h:16, color: UIColor(red:0.14, green:0.13, blue:0.20, alpha:1))
            // Subtle lighter pixel cracks
            let crack = UIColor(red:0.20, green:0.19, blue:0.28, alpha:1)
            fillRect(ctx, x:3, y:5, w:4, h:1, color: crack)
            fillRect(ctx, x:6, y:5, w:1, h:2, color: crack)
            fillRect(ctx, x:10, y:11, w:3, h:1, color: crack)
            fillRect(ctx, x:10, y:12, w:1, h:1, color: crack)
            // Very dark grout lines at edges
            let grout = UIColor(red:0.08, green:0.07, blue:0.12, alpha:1)
            fillRect(ctx, x:0, y:0, w:16, h:1, color: grout)
            fillRect(ctx, x:0, y:0, w:1, h:16, color: grout)
        }
    }

    // MARK: Wall tile — near-black with blue-tinted bricks
    static func wallTile() -> SKTexture {
        texture { ctx, size in
            // Base very dark blue-black
            fillRect(ctx, x:0, y:0, w:16, h:16, color: UIColor(red:0.07, green:0.07, blue:0.14, alpha:1))
            // Brick rows (mortar = dark)
            let brick = UIColor(red:0.13, green:0.13, blue:0.24, alpha:1)
            let brickTop = UIColor(red:0.18, green:0.18, blue:0.30, alpha:1)
            let mortar = UIColor(red:0.04, green:0.04, blue:0.08, alpha:1)
            // Row 1: y=1..4  (bricks offset even row)
            fillRect(ctx, x:1, y:1, w:6, h:3, color: brick)
            fillRect(ctx, x:1, y:1, w:6, h:1, color: brickTop)
            fillRect(ctx, x:9, y:1, w:6, h:3, color: brick)
            fillRect(ctx, x:9, y:1, w:6, h:1, color: brickTop)
            fillRect(ctx, x:0, y:4, w:16, h:1, color: mortar)
            // Row 2: y=5..8  (offset by half)
            fillRect(ctx, x:0, y:5, w:3, h:3, color: brick)
            fillRect(ctx, x:0, y:5, w:3, h:1, color: brickTop)
            fillRect(ctx, x:5, y:5, w:6, h:3, color: brick)
            fillRect(ctx, x:5, y:5, w:6, h:1, color: brickTop)
            fillRect(ctx, x:13, y:5, w:3, h:3, color: brick)
            fillRect(ctx, x:13, y:5, w:3, h:1, color: brickTop)
            fillRect(ctx, x:0, y:8, w:16, h:1, color: mortar)
            // Row 3: y=9..12
            fillRect(ctx, x:1, y:9, w:5, h:3, color: brick)
            fillRect(ctx, x:1, y:9, w:5, h:1, color: brickTop)
            fillRect(ctx, x:8, y:9, w:7, h:3, color: brick)
            fillRect(ctx, x:8, y:9, w:7, h:1, color: brickTop)
            fillRect(ctx, x:0, y:12, w:16, h:1, color: mortar)
            // Row 4: y=13..15
            fillRect(ctx, x:0, y:13, w:4, h:3, color: brick)
            fillRect(ctx, x:0, y:13, w:4, h:1, color: brickTop)
            fillRect(ctx, x:6, y:13, w:4, h:3, color: brick)
            fillRect(ctx, x:6, y:13, w:4, h:1, color: brickTop)
            fillRect(ctx, x:12, y:13, w:4, h:3, color: brick)
            fillRect(ctx, x:12, y:13, w:4, h:1, color: brickTop)
        }
    }

    // MARK: Locked door — brown wood with gold keyhole
    static func doorLockedTile() -> SKTexture {
        texture { ctx, size in
            // Wood body
            fillRect(ctx, x:1, y:0, w:14, h:16, color: UIColor(red:0.42, green:0.22, blue:0.08, alpha:1))
            // Wood grain
            let grain = UIColor(red:0.36, green:0.18, blue:0.06, alpha:1)
            fillRect(ctx, x:3, y:2, w:1, h:12, color: grain)
            fillRect(ctx, x:8, y:2, w:1, h:12, color: grain)
            fillRect(ctx, x:12, y:2, w:1, h:12, color: grain)
            // Gold keyhole ring
            let gold = UIColor(red:0.90, green:0.72, blue:0.10, alpha:1)
            let darkGold = UIColor(red:0.55, green:0.40, blue:0.05, alpha:1)
            fillRect(ctx, x:6, y:5, w:4, h:4, color: gold)
            fillRect(ctx, x:7, y:6, w:2, h:2, color: darkGold)  // hole
            fillRect(ctx, x:7, y:9, w:2, h:3, color: gold)       // slot
            // Metal bands
            let metal = UIColor(red:0.60, green:0.50, blue:0.35, alpha:1)
            fillRect(ctx, x:1, y:3, w:14, h:1, color: metal)
            fillRect(ctx, x:1, y:12, w:14, h:1, color: metal)
        }
    }

    // MARK: Open door — dark opening
    static func doorOpenTile() -> SKTexture {
        texture { ctx, size in
            fillRect(ctx, x:0, y:0, w:16, h:16, color: UIColor(red:0.03, green:0.03, blue:0.06, alpha:1))
            // Slight purple tint depth
            fillRect(ctx, x:2, y:2, w:12, h:12, color: UIColor(red:0.05, green:0.04, blue:0.10, alpha:1))
        }
    }

    // MARK: Key sprite — gold key pixel art
    static func keySprite() -> SKTexture {
        texture { ctx, size in
            let gold = UIColor(red:1.0, green:0.85, blue:0.10, alpha:1)
            let darkGold = UIColor(red:0.70, green:0.55, blue:0.05, alpha:1)
            // Key ring
            fillRect(ctx, x:2, y:3, w:5, h:5, color: gold)
            fillRect(ctx, x:3, y:4, w:3, h:3, color: darkGold)
            // Shaft
            fillRect(ctx, x:6, y:5, w:8, h:2, color: gold)
            // Teeth
            fillRect(ctx, x:10, y:7, w:2, h:2, color: gold)
            fillRect(ctx, x:13, y:7, w:2, h:2, color: gold)
        }
    }

    // MARK: Heart full — red pixel heart
    static func heartFull() -> SKTexture {
        texture(size: CGSize(width:8, height:8)) { ctx, size in
            let red = UIColor(red:0.90, green:0.15, blue:0.15, alpha:1)
            let darkRed = UIColor(red:0.60, green:0.05, blue:0.05, alpha:1)
            fillRect(ctx, x:1, y:2, w:2, h:1, color: red)
            fillRect(ctx, x:5, y:2, w:2, h:1, color: red)
            fillRect(ctx, x:0, y:3, w:3, h:1, color: red)
            fillRect(ctx, x:5, y:3, w:3, h:1, color: red)
            fillRect(ctx, x:0, y:4, w:8, h:1, color: red)
            fillRect(ctx, x:1, y:5, w:6, h:1, color: red)
            fillRect(ctx, x:2, y:6, w:4, h:1, color: red)
            fillRect(ctx, x:3, y:7, w:2, h:1, color: red)
            // Highlight
            fillRect(ctx, x:1, y:3, w:1, h:1, color: UIColor(red:1.0, green:0.55, blue:0.55, alpha:1))
            // Shadow
            fillRect(ctx, x:5, y:5, w:2, h:1, color: darkRed)
        }
    }

    // MARK: Heart empty — dark outline heart
    static func heartEmpty() -> SKTexture {
        texture(size: CGSize(width:8, height:8)) { ctx, size in
            let dark = UIColor(red:0.30, green:0.08, blue:0.08, alpha:1)
            fillRect(ctx, x:1, y:2, w:2, h:1, color: dark)
            fillRect(ctx, x:5, y:2, w:2, h:1, color: dark)
            fillRect(ctx, x:0, y:3, w:3, h:1, color: dark)
            fillRect(ctx, x:5, y:3, w:3, h:1, color: dark)
            fillRect(ctx, x:0, y:4, w:8, h:1, color: dark)
            fillRect(ctx, x:1, y:5, w:6, h:1, color: dark)
            fillRect(ctx, x:2, y:6, w:4, h:1, color: dark)
            fillRect(ctx, x:3, y:7, w:2, h:1, color: dark)
        }
    }

    // MARK: Spikes tile — gray pixel spikes
    static func spikesTile() -> SKTexture {
        texture { ctx, size in
            let base = UIColor(red:0.14, green:0.13, blue:0.20, alpha:1)
            let gray = UIColor(red:0.65, green:0.65, blue:0.70, alpha:1)
            let lightGray = UIColor(red:0.85, green:0.85, blue:0.90, alpha:1)
            fillRect(ctx, x:0, y:0, w:16, h:16, color: base)
            // Three spikes
            // Spike 1
            fillRect(ctx, x:1, y:14, w:4, h:2, color: gray)
            fillRect(ctx, x:2, y:12, w:2, h:2, color: gray)
            fillRect(ctx, x:2, y:10, w:1, h:2, color: gray)
            fillRect(ctx, x:3, y:8,  w:1, h:2, color: lightGray)
            // Spike 2
            fillRect(ctx, x:6, y:14, w:4, h:2, color: gray)
            fillRect(ctx, x:7, y:12, w:2, h:2, color: gray)
            fillRect(ctx, x:7, y:10, w:1, h:2, color: gray)
            fillRect(ctx, x:8, y:8,  w:1, h:2, color: lightGray)
            // Spike 3
            fillRect(ctx, x:11, y:14, w:4, h:2, color: gray)
            fillRect(ctx, x:12, y:12, w:2, h:2, color: gray)
            fillRect(ctx, x:12, y:10, w:1, h:2, color: gray)
            fillRect(ctx, x:13, y:8,  w:1, h:2, color: lightGray)
        }
    }

    // MARK: Lava tile frame A
    static func lavaTileA() -> SKTexture {
        texture { ctx, size in
            let dark = UIColor(red:0.55, green:0.10, blue:0.00, alpha:1)
            let mid  = UIColor(red:0.85, green:0.30, blue:0.00, alpha:1)
            let hot  = UIColor(red:1.00, green:0.65, blue:0.05, alpha:1)
            fillRect(ctx, x:0, y:0, w:16, h:16, color: dark)
            fillRect(ctx, x:1, y:10, w:4, h:3, color: mid)
            fillRect(ctx, x:4, y:9,  w:2, h:1, color: hot)
            fillRect(ctx, x:6, y:12, w:5, h:2, color: mid)
            fillRect(ctx, x:8, y:11, w:2, h:1, color: hot)
            fillRect(ctx, x:11, y:9, w:4, h:4, color: mid)
            fillRect(ctx, x:2, y:13, w:2, h:1, color: hot)
            fillRect(ctx, x:12, y:13, w:3, h:1, color: hot)
            fillRect(ctx, x:0, y:8,  w:3, h:2, color: mid)
        }
    }

    // MARK: Lava tile frame B (alternate)
    static func lavaTileB() -> SKTexture {
        texture { ctx, size in
            let dark = UIColor(red:0.55, green:0.10, blue:0.00, alpha:1)
            let mid  = UIColor(red:0.85, green:0.30, blue:0.00, alpha:1)
            let hot  = UIColor(red:1.00, green:0.65, blue:0.05, alpha:1)
            fillRect(ctx, x:0, y:0, w:16, h:16, color: dark)
            fillRect(ctx, x:2, y:11, w:5, h:3, color: mid)
            fillRect(ctx, x:3, y:10, w:2, h:1, color: hot)
            fillRect(ctx, x:8, y:13, w:4, h:2, color: mid)
            fillRect(ctx, x:9, y:12, w:2, h:1, color: hot)
            fillRect(ctx, x:10, y:8, w:5, h:4, color: mid)
            fillRect(ctx, x:0, y:10, w:3, h:3, color: mid)
            fillRect(ctx, x:11, y:9, w:2, h:1, color: hot)
            fillRect(ctx, x:1, y:12, w:2, h:1, color: hot)
        }
    }

    // MARK: Stairs tile — downward staircase pixel art
    static func stairsTile() -> SKTexture {
        texture { ctx, size in
            let dark  = UIColor(red:0.06, green:0.20, blue:0.08, alpha:1)
            let mid   = UIColor(red:0.15, green:0.50, blue:0.18, alpha:1)
            let light = UIColor(red:0.30, green:0.75, blue:0.35, alpha:1)
            fillRect(ctx, x:0, y:0, w:16, h:16, color: dark)
            for i in 0..<4 {
                let y = 2 + i * 3
                let x = i * 2
                fillRect(ctx, x:x, y:y, w:16 - x, h:2, color: mid)
                fillRect(ctx, x:x, y:y, w:16 - x, h:1, color: light)
            }
        }
    }

    // MARK: Pressure plate — stone with indent
    static func pressurePlateTile() -> SKTexture {
        texture { ctx, size in
            let base  = UIColor(red:0.14, green:0.13, blue:0.20, alpha:1)
            let stone = UIColor(red:0.38, green:0.35, blue:0.28, alpha:1)
            let light = UIColor(red:0.60, green:0.57, blue:0.45, alpha:1)
            let shadow = UIColor(red:0.22, green:0.20, blue:0.14, alpha:1)
            fillRect(ctx, x:0, y:0, w:16, h:16, color: base)
            fillRect(ctx, x:2, y:10, w:12, h:4, color: stone)
            fillRect(ctx, x:2, y:10, w:12, h:1, color: light)
            fillRect(ctx, x:3, y:11, w:10, h:2, color: shadow)
            fillRect(ctx, x:2, y:13, w:12, h:1, color: shadow)
        }
    }

    // MARK: Push block — chiseled gray stone
    static func pushBlockTile() -> SKTexture {
        texture { ctx, size in
            let mid    = UIColor(red:0.38, green:0.38, blue:0.42, alpha:1)
            let light  = UIColor(red:0.55, green:0.55, blue:0.60, alpha:1)
            let dark   = UIColor(red:0.22, green:0.22, blue:0.26, alpha:1)
            let grout  = UIColor(red:0.12, green:0.12, blue:0.16, alpha:1)
            fillRect(ctx, x:0, y:0, w:16, h:16, color: mid)
            // Beveled edges
            fillRect(ctx, x:0, y:0, w:16, h:1, color: light)
            fillRect(ctx, x:0, y:0, w:1, h:16, color: light)
            fillRect(ctx, x:0, y:15, w:16, h:1, color: dark)
            fillRect(ctx, x:15, y:0, w:1, h:16, color: dark)
            // Cross chisel lines
            fillRect(ctx, x:7, y:1, w:2, h:14, color: grout)
            fillRect(ctx, x:1, y:7, w:14, h:2, color: grout)
        }
    }

    // MARK: Exit tile — green staircase down
    static func exitTile() -> SKTexture {
        return stairsTile()
    }

    // MARK: Player — 16x16 green tunic Link-style
    static func playerTile(facing: DungeonDirection, frame: Int) -> SKTexture {
        texture { ctx, size in
            // Skin
            let skin  = UIColor(red:0.96, green:0.82, blue:0.65, alpha:1)
            let hair  = UIColor(red:0.80, green:0.60, blue:0.10, alpha:1)
            let tunic = UIColor(red:0.15, green:0.62, blue:0.20, alpha:1)
            let darkTunic = UIColor(red:0.08, green:0.40, blue:0.12, alpha:1)
            let boots = UIColor(red:0.50, green:0.28, blue:0.10, alpha:1)
            let belt  = UIColor(red:0.65, green:0.40, blue:0.12, alpha:1)

            switch facing {
            case .down:
                // Hat / hair
                fillRect(ctx, x:5, y:0, w:6, h:2, color: hair)
                fillRect(ctx, x:4, y:1, w:8, h:1, color: hair)
                // Face
                fillRect(ctx, x:4, y:2, w:8, h:5, color: skin)
                // Eyes
                fillRect(ctx, x:5, y:4, w:2, h:2, color: UIColor.black)
                fillRect(ctx, x:9, y:4, w:2, h:2, color: UIColor.black)
                // Tunic body
                fillRect(ctx, x:4, y:7, w:8, h:5, color: tunic)
                fillRect(ctx, x:4, y:7, w:8, h:1, color: darkTunic)
                // Belt
                fillRect(ctx, x:4, y:11, w:8, h:1, color: belt)
                // Arms
                fillRect(ctx, x:2, y:7, w:2, h:4, color: tunic)
                fillRect(ctx, x:12, y:7, w:2, h:4, color: tunic)
                // Legs — frame alternates
                if frame == 0 {
                    fillRect(ctx, x:5, y:12, w:2, h:4, color: darkTunic)
                    fillRect(ctx, x:9, y:13, w:2, h:3, color: darkTunic)
                } else {
                    fillRect(ctx, x:5, y:13, w:2, h:3, color: darkTunic)
                    fillRect(ctx, x:9, y:12, w:2, h:4, color: darkTunic)
                }
                fillRect(ctx, x:5, y:15, w:2, h:1, color: boots)
                fillRect(ctx, x:9, y:15, w:2, h:1, color: boots)

            case .up:
                // Back of head / hat
                fillRect(ctx, x:4, y:0, w:8, h:3, color: hair)
                fillRect(ctx, x:3, y:2, w:10, h:3, color: hair)
                // Tunic back
                fillRect(ctx, x:4, y:5, w:8, h:7, color: tunic)
                fillRect(ctx, x:4, y:5, w:8, h:1, color: darkTunic)
                fillRect(ctx, x:4, y:11, w:8, h:1, color: belt)
                // Arms
                fillRect(ctx, x:2, y:5, w:2, h:4, color: tunic)
                fillRect(ctx, x:12, y:5, w:2, h:4, color: tunic)
                // Legs
                if frame == 0 {
                    fillRect(ctx, x:5, y:12, w:2, h:4, color: darkTunic)
                    fillRect(ctx, x:9, y:13, w:2, h:3, color: darkTunic)
                } else {
                    fillRect(ctx, x:5, y:13, w:2, h:3, color: darkTunic)
                    fillRect(ctx, x:9, y:12, w:2, h:4, color: darkTunic)
                }
                fillRect(ctx, x:5, y:15, w:2, h:1, color: boots)
                fillRect(ctx, x:9, y:15, w:2, h:1, color: boots)

            case .right:
                // Hat points right
                fillRect(ctx, x:3, y:0, w:7, h:2, color: hair)
                fillRect(ctx, x:2, y:1, w:9, h:3, color: hair)
                fillRect(ctx, x:9, y:1, w:4, h:2, color: hair) // pointy hat tip
                // Face
                fillRect(ctx, x:3, y:3, w:7, h:5, color: skin)
                // Eye
                fillRect(ctx, x:8, y:5, w:2, h:2, color: UIColor.black)
                // Tunic
                fillRect(ctx, x:3, y:8, w:8, h:5, color: tunic)
                fillRect(ctx, x:3, y:8, w:8, h:1, color: darkTunic)
                fillRect(ctx, x:3, y:12, w:8, h:1, color: belt)
                // Arms
                fillRect(ctx, x:1, y:8, w:2, h:3, color: tunic)
                fillRect(ctx, x:11, y:8, w:3, h:3, color: tunic)
                // Legs
                if frame == 0 {
                    fillRect(ctx, x:4, y:13, w:2, h:3, color: darkTunic)
                    fillRect(ctx, x:8, y:14, w:2, h:2, color: darkTunic)
                } else {
                    fillRect(ctx, x:4, y:14, w:2, h:2, color: darkTunic)
                    fillRect(ctx, x:8, y:13, w:2, h:3, color: darkTunic)
                }

            case .left:
                // Hat points left
                fillRect(ctx, x:6, y:0, w:7, h:2, color: hair)
                fillRect(ctx, x:5, y:1, w:9, h:3, color: hair)
                fillRect(ctx, x:3, y:1, w:4, h:2, color: hair)
                // Face
                fillRect(ctx, x:6, y:3, w:7, h:5, color: skin)
                // Eye
                fillRect(ctx, x:6, y:5, w:2, h:2, color: UIColor.black)
                // Tunic
                fillRect(ctx, x:5, y:8, w:8, h:5, color: tunic)
                fillRect(ctx, x:5, y:8, w:8, h:1, color: darkTunic)
                fillRect(ctx, x:5, y:12, w:8, h:1, color: belt)
                // Arms
                fillRect(ctx, x:2, y:8, w:3, h:3, color: tunic)
                fillRect(ctx, x:13, y:8, w:2, h:3, color: tunic)
                // Legs
                if frame == 0 {
                    fillRect(ctx, x:6, y:13, w:2, h:3, color: darkTunic)
                    fillRect(ctx, x:10, y:14, w:2, h:2, color: darkTunic)
                } else {
                    fillRect(ctx, x:6, y:14, w:2, h:2, color: darkTunic)
                    fillRect(ctx, x:10, y:13, w:2, h:3, color: darkTunic)
                }
            }
        }
    }

    // MARK: Sword — 8x4 pixel silver blade
    static func swordTile() -> SKTexture {
        texture(size: CGSize(width:8, height:4)) { ctx, size in
            let silver = UIColor(red:0.80, green:0.82, blue:0.90, alpha:1)
            let bright = UIColor(red:0.95, green:0.97, blue:1.00, alpha:1)
            let handle = UIColor(red:0.55, green:0.30, blue:0.10, alpha:1)
            fillRect(ctx, x:0, y:1, w:2, h:2, color: handle)
            fillRect(ctx, x:2, y:0, w:1, h:4, color: silver)  // guard
            fillRect(ctx, x:3, y:1, w:5, h:2, color: silver)
            fillRect(ctx, x:3, y:1, w:5, h:1, color: bright)  // edge highlight
        }
    }

    // MARK: Slime monster — 16x12 green blob
    static func slimeTile(frame: Int) -> SKTexture {
        texture { ctx, size in
            let body  = UIColor(red:0.15, green:0.72, blue:0.20, alpha:1)
            let dark  = UIColor(red:0.08, green:0.48, blue:0.12, alpha:1)
            let light = UIColor(red:0.45, green:0.90, blue:0.50, alpha:1)
            let eye   = UIColor.white
            let pupil = UIColor.black

            let yOff = frame == 0 ? 2 : 3  // slight bounce

            // Body blob
            fillRect(ctx, x:2, y:yOff+2, w:12, h:1, color: body)
            fillRect(ctx, x:1, y:yOff+3, w:14, h:6, color: body)
            fillRect(ctx, x:2, y:yOff+9, w:12, h:1, color: dark)
            // Underbelly
            fillRect(ctx, x:3, y:yOff+8, w:10, h:1, color: dark)
            // Highlight
            fillRect(ctx, x:4, y:yOff+3, w:3, h:1, color: light)
            // Eyes
            fillRect(ctx, x:4, y:yOff+4, w:2, h:2, color: eye)
            fillRect(ctx, x:10, y:yOff+4, w:2, h:2, color: eye)
            fillRect(ctx, x:4, y:yOff+5, w:1, h:1, color: pupil)
            fillRect(ctx, x:10, y:yOff+5, w:1, h:1, color: pupil)
            // Tiny slime feet
            fillRect(ctx, x:3, y:yOff+10, w:2, h:1, color: dark)
            fillRect(ctx, x:7, y:yOff+10, w:2, h:1, color: dark)
            fillRect(ctx, x:11, y:yOff+10, w:2, h:1, color: dark)
        }
    }

    // MARK: Skeleton monster
    static func skeletonTile(frame: Int) -> SKTexture {
        texture { ctx, size in
            let bone   = UIColor(red:0.88, green:0.88, blue:0.82, alpha:1)
            let light  = UIColor(red:0.98, green:0.98, blue:0.95, alpha:1)
            let shadow = UIColor(red:0.55, green:0.55, blue:0.50, alpha:1)
            let eyeCol = UIColor.black

            // Skull
            fillRect(ctx, x:4, y:0, w:8, h:1, color: bone)
            fillRect(ctx, x:3, y:1, w:10, h:5, color: bone)
            fillRect(ctx, x:4, y:6, w:8, h:1, color: bone)
            // Eye sockets
            fillRect(ctx, x:4, y:2, w:3, h:3, color: eyeCol)
            fillRect(ctx, x:9, y:2, w:3, h:3, color: eyeCol)
            // Teeth
            fillRect(ctx, x:5, y:6, w:1, h:2, color: light)
            fillRect(ctx, x:7, y:6, w:1, h:2, color: light)
            fillRect(ctx, x:9, y:6, w:1, h:2, color: light)
            // Neck
            fillRect(ctx, x:7, y:8, w:2, h:1, color: bone)
            // Ribcage
            fillRect(ctx, x:3, y:9, w:10, h:5, color: bone)
            fillRect(ctx, x:4, y:9, w:8, h:1, color: light)
            fillRect(ctx, x:4, y:10, w:8, h:1, color: shadow)
            fillRect(ctx, x:4, y:12, w:8, h:1, color: shadow)
            // Arm walk cycle
            let armY = frame == 0 ? 9 : 10
            fillRect(ctx, x:1, y:armY, w:2, h:4, color: bone)
            fillRect(ctx, x:13, y:armY, w:2, h:4, color: bone)
            // Legs
            fillRect(ctx, x:4, y:14, w:3, h:2, color: bone)
            fillRect(ctx, x:9, y:14, w:3, h:2, color: bone)
        }
    }

    // MARK: Demon boss — 32x32 pixel art
    static func demonTile(frame: Int) -> SKTexture {
        texture(size: CGSize(width:32, height:32)) { ctx, size in
            let purple     = UIColor(red:0.42, green:0.05, blue:0.55, alpha:1)
            let darkPurple = UIColor(red:0.25, green:0.02, blue:0.35, alpha:1)
            let lightPur   = UIColor(red:0.65, green:0.20, blue:0.80, alpha:1)
            let hornRed    = UIColor(red:0.70, green:0.05, blue:0.08, alpha:1)
            let eyeOrange  = UIColor(red:1.00, green:0.65, blue:0.00, alpha:1)
            let eyeWhite   = UIColor.white
            let black      = UIColor.black

            // Body
            fillRect(ctx, x:6,  y:8,  w:20, h:20, color: purple)
            fillRect(ctx, x:4,  y:12, w:24, h:12, color: purple)
            fillRect(ctx, x:6,  y:8,  w:20, h:2,  color: lightPur)
            fillRect(ctx, x:4,  y:12, w:24, h:2,  color: lightPur)
            // Shadow bottom
            fillRect(ctx, x:6,  y:26, w:20, h:2,  color: darkPurple)
            // Horns (pixel triangles)
            fillRect(ctx, x:8,  y:2,  w:2,  h:6,  color: hornRed)
            fillRect(ctx, x:7,  y:4,  w:1,  h:4,  color: hornRed)
            fillRect(ctx, x:22, y:2,  w:2,  h:6,  color: hornRed)
            fillRect(ctx, x:24, y:4,  w:1,  h:4,  color: hornRed)
            // Eyes — glow
            let eyeY = frame == 0 ? 14 : 15
            fillRect(ctx, x:9,  y:eyeY, w:4,  h:4, color: eyeWhite)
            fillRect(ctx, x:19, y:eyeY, w:4,  h:4, color: eyeWhite)
            fillRect(ctx, x:10, y:eyeY+1, w:2, h:2, color: eyeOrange)
            fillRect(ctx, x:20, y:eyeY+1, w:2, h:2, color: eyeOrange)
            fillRect(ctx, x:11, y:eyeY+1, w:1, h:1, color: black)
            fillRect(ctx, x:21, y:eyeY+1, w:1, h:1, color: black)
            // Mouth
            fillRect(ctx, x:11, y:21, w:10, h:2, color: black)
            fillRect(ctx, x:12, y:22, w:2,  h:2, color: eyeWhite) // teeth
            fillRect(ctx, x:15, y:22, w:2,  h:2, color: eyeWhite)
            fillRect(ctx, x:18, y:22, w:2,  h:2, color: eyeWhite)
            // Arms
            let armDY = frame == 0 ? 0 : 2
            fillRect(ctx, x:2,  y:14+armDY, w:4, h:8, color: purple)
            fillRect(ctx, x:26, y:14+armDY, w:4, h:8, color: purple)
            // Claws
            fillRect(ctx, x:1,  y:20+armDY, w:2, h:2, color: darkPurple)
            fillRect(ctx, x:3,  y:22+armDY, w:2, h:2, color: darkPurple)
            fillRect(ctx, x:27, y:20+armDY, w:2, h:2, color: darkPurple)
            fillRect(ctx, x:25, y:22+armDY, w:2, h:2, color: darkPurple)
        }
    }

    // MARK: Projectile — purple magic orb
    static func projectileTile() -> SKTexture {
        texture(size: CGSize(width:8, height:8)) { ctx, size in
            let core  = UIColor(red:0.85, green:0.20, blue:1.00, alpha:1)
            let glow  = UIColor(red:0.60, green:0.05, blue:0.80, alpha:1)
            let white = UIColor.white
            fillRect(ctx, x:2, y:2, w:4, h:4, color: glow)
            fillRect(ctx, x:3, y:1, w:2, h:6, color: glow)
            fillRect(ctx, x:1, y:3, w:6, h:2, color: glow)
            fillRect(ctx, x:3, y:3, w:2, h:2, color: core)
            fillRect(ctx, x:2, y:2, w:1, h:1, color: white) // sparkle
        }
    }

    // MARK: Dust poof particle
    static func dustTile() -> SKTexture {
        texture(size: CGSize(width:4, height:4)) { ctx, size in
            let c = UIColor(red:0.70, green:0.65, blue:0.55, alpha:1)
            fillRect(ctx, x:1, y:0, w:2, h:1, color: c)
            fillRect(ctx, x:0, y:1, w:1, h:2, color: c)
            fillRect(ctx, x:3, y:1, w:1, h:2, color: c)
            fillRect(ctx, x:1, y:3, w:2, h:1, color: c)
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
    var node: SKSpriteNode
    var moveTimer: TimeInterval = 0
    var shootTimer: TimeInterval = 0
    var spawnTimer: TimeInterval = 0
    var isDead = false
    var animFrame: Int = 0
    var animTimer: TimeInterval = 0

    init(kind: Kind, coord: TileCoord, node: SKSpriteNode) {
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
        animTimer  = Double.random(in: 0...0.4)
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
    private let moveAnimDuration: TimeInterval = 0.08   // snappy tile-based

    // MARK: Map data
    private var mapData:   [[TileKind]] = []
    private var tileNodes: [[SKNode?]]  = []
    private var rows: Int = 0
    private var cols: Int = 0

    // MARK: Puzzle state
    private var plateConnections: [TileCoord: TileCoord] = [:]
    private var plateActive: [TileCoord: Bool] = [:]
    private var pushBlocks: [TileCoord: SKNode] = [:]
    private var keyNodesByCoord: [TileCoord: SKNode] = [:]
    private var pickedUpKeys: Set<TileCoord> = []
    private var spikeCoords: [TileCoord] = []
    private var spikeNodes: [TileCoord: SKNode] = [:]
    private var spikeActive: Bool = true
    private var spikeTimer: TimeInterval = 0

    // MARK: Player state
    private var playerNode: SKSpriteNode!
    private var swordNode: SKSpriteNode!
    private var playerCoord = TileCoord(col: 1, row: 1)
    private var playerHP: Int = 6
    private let playerMaxHP: Int = 6
    private var playerKeys: Int = 0
    private var playerFacing: DungeonDirection = .down
    private var isMoving = false
    private var invincibleUntil: TimeInterval = 0
    private var isGameOver = false
    private var hasWon = false
    private var playerAnimFrame: Int = 0
    private var playerAnimTimer: TimeInterval = 0
    private var isAttacking = false

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
    private var darkOverlay: SKSpriteNode!

    // MARK: Lava animation
    private var lavaNodes: [SKSpriteNode] = []
    private var lavaTimer: TimeInterval = 0
    private var lavaFrame: Int = 0

    // MARK: Build guard
    private var hasBuilt = false
    private var lastUpdateTime: TimeInterval = 0

    // MARK: - Texture cache
    private lazy var texFloor      = PixelArt.floorTile()
    private lazy var texWall       = PixelArt.wallTile()
    private lazy var texDoorLocked = PixelArt.doorLockedTile()
    private lazy var texPressure   = PixelArt.pressurePlateTile()
    private lazy var texPushBlock  = PixelArt.pushBlockTile()
    private lazy var texSpikes     = PixelArt.spikesTile()
    private lazy var texLavaA      = PixelArt.lavaTileA()
    private lazy var texLavaB      = PixelArt.lavaTileB()
    private lazy var texExit       = PixelArt.exitTile()
    private lazy var texKey        = PixelArt.keySprite()
    private lazy var texSword      = PixelArt.swordTile()
    private lazy var texProj       = PixelArt.projectileTile()

    // MARK: - Setup

    override func didMove(to view: SKView) {
        isPaused = false
        view.ignoresSiblingOrder = true

        guard !hasBuilt else { return }
        hasBuilt = true
        backgroundColor = SKColor(red:0.04, green:0.03, blue:0.08, alpha:1)
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

        // First pass: floor everywhere
        for r in 0..<rows {
            for c in 0..<cols {
                let floor = SKSpriteNode(texture: texFloor)
                floor.size = CGSize(width: tileSize, height: tileSize)
                floor.position = worldPos(TileCoord(col: c, row: r))
                floor.zPosition = 0
                worldLayer.addChild(floor)
            }
        }

        // Second pass: objects
        for (r, line) in lines.enumerated() {
            for (c, ch) in line.enumerated() {
                guard let kind = TileKind(rawValue: ch) else { continue }
                mapData[r][c] = kind
                let coord = TileCoord(col: c, row: r)
                let pos = worldPos(coord)

                switch kind {
                case .wall:
                    let node = wallSprite()
                    node.position = pos; node.zPosition = 1
                    worldLayer.addChild(node)
                    tileNodes[r][c] = node

                case .lockedDoor:
                    let node = lockedDoorSprite()
                    node.position = pos; node.zPosition = 2
                    worldLayer.addChild(node)
                    tileNodes[r][c] = node

                case .openDoor:
                    mapData[r][c] = .openDoor

                case .exit:
                    let node = SKSpriteNode(texture: texExit)
                    node.size = CGSize(width: tileSize, height: tileSize)
                    node.position = pos; node.zPosition = 1
                    worldLayer.addChild(node)
                    tileNodes[r][c] = node
                    // Gentle pulse
                    node.run(SKAction.repeatForever(SKAction.sequence([
                        SKAction.scale(to: 1.04, duration: 0.55),
                        SKAction.scale(to: 0.96, duration: 0.55)
                    ])))

                case .key:
                    mapData[r][c] = .floor
                    let node = keyPickupNode()
                    node.position = pos; node.zPosition = 3
                    worldLayer.addChild(node)
                    keyNodesByCoord[coord] = node

                case .pressurePlate:
                    let node = SKSpriteNode(texture: texPressure)
                    node.size = CGSize(width: tileSize, height: tileSize)
                    node.position = pos; node.zPosition = 1
                    worldLayer.addChild(node)
                    tileNodes[r][c] = node

                case .pushBlock:
                    mapData[r][c] = .floor
                    let node = SKSpriteNode(texture: texPushBlock)
                    node.size = CGSize(width: tileSize, height: tileSize)
                    node.position = pos; node.zPosition = 2
                    worldLayer.addChild(node)
                    pushBlocks[coord] = node

                case .spike:
                    mapData[r][c] = .floor
                    let node = SKSpriteNode(texture: texSpikes)
                    node.size = CGSize(width: tileSize, height: tileSize)
                    node.position = pos; node.zPosition = 2
                    worldLayer.addChild(node)
                    spikeCoords.append(coord)
                    spikeNodes[coord] = node

                case .lava:
                    let node = SKSpriteNode(texture: texLavaA)
                    node.size = CGSize(width: tileSize, height: tileSize)
                    node.position = pos; node.zPosition = 1
                    worldLayer.addChild(node)
                    tileNodes[r][c] = node
                    lavaNodes.append(node)

                case .playerStart:
                    mapData[r][c] = .floor
                    playerCoord = coord

                case .slime:
                    mapData[r][c] = .floor
                    let node = SKSpriteNode(texture: PixelArt.slimeTile(frame:0))
                    node.size = CGSize(width: tileSize, height: tileSize)
                    node.position = pos; node.zPosition = 4
                    worldLayer.addChild(node)
                    monsters.append(DungeonMonster(kind: .slime, coord: coord, node: node))

                case .skeleton:
                    mapData[r][c] = .floor
                    let node = SKSpriteNode(texture: PixelArt.skeletonTile(frame:0))
                    node.size = CGSize(width: tileSize, height: tileSize)
                    node.position = pos; node.zPosition = 4
                    worldLayer.addChild(node)
                    monsters.append(DungeonMonster(kind: .skeleton, coord: coord, node: node))

                case .demon:
                    mapData[r][c] = .floor
                    let node = SKSpriteNode(texture: PixelArt.demonTile(frame:0))
                    node.size = CGSize(width: tileSize * 2, height: tileSize * 2)
                    node.position = pos; node.zPosition = 4
                    worldLayer.addChild(node)
                    monsters.append(DungeonMonster(kind: .demon, coord: coord, node: node))

                case .hiddenWall:
                    let node = wallSprite()
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
        addDarkOverlay()
        snapCameraToPlayer()
    }

    private func wallSprite() -> SKSpriteNode {
        let node = SKSpriteNode(texture: texWall)
        node.size = CGSize(width: tileSize, height: tileSize)
        return node
    }

    private func lockedDoorSprite() -> SKSpriteNode {
        let node = SKSpriteNode(texture: texDoorLocked)
        node.size = CGSize(width: tileSize, height: tileSize)
        return node
    }

    private func keyPickupNode() -> SKNode {
        let node = SKSpriteNode(texture: texKey)
        node.size = CGSize(width: tileSize * 0.75, height: tileSize * 0.75)
        // Float bob animation
        node.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x:0, y:5, duration:0.55),
            SKAction.moveBy(x:0, y:-5, duration:0.55)
        ])))
        return node
    }

    // MARK: - Dark atmosphere overlay (child of camera)

    private func addDarkOverlay() {
        // Full-screen dark vignette — attached to camera so it moves with view
        darkOverlay = SKSpriteNode(color: SKColor(red:0, green:0, blue:0, alpha:0.32), size: CGSize(width:4000, height:4000))
        darkOverlay.zPosition = 50
        cameraNode.addChild(darkOverlay)
    }

    // MARK: - Torch lights

    private func addTorchLights() {
        let positions: [(Int, Int)] = mapMode == .short
            ? [(2, 1), (12, 2), (7, 6), (12, 9)]
            : [(1,1),(9,1),(17,1),(1,9),(9,9),(17,9),(1,16),(9,16),(17,16)]

        for (c, r) in positions {
            guard c < cols, r < rows else { continue }
            let pos = worldPos(TileCoord(col: c, row: r))

            // Wide warm glow
            let glow = SKShapeNode(circleOfRadius: tileSize * 2.2)
            glow.fillColor   = SKColor(red:1.0, green:0.60, blue:0.18, alpha:0.13)
            glow.strokeColor = .clear
            glow.position    = pos
            glow.zPosition   = 0.5
            glow.blendMode   = .add
            worldLayer.addChild(glow)

            // Pulse
            let pulseA = SKAction.customAction(withDuration: 0.3) { n, _ in
                (n as? SKShapeNode)?.fillColor = SKColor(red:1.0, green:0.60, blue:0.18, alpha:0.15)
            }
            let pulseB = SKAction.customAction(withDuration: 0.4) { n, _ in
                (n as? SKShapeNode)?.fillColor = SKColor(red:1.0, green:0.50, blue:0.12, alpha:0.09)
            }
            glow.run(SKAction.repeatForever(SKAction.sequence([pulseA, pulseB])))

            // Inner tight glow
            let inner = SKShapeNode(circleOfRadius: tileSize * 0.9)
            inner.fillColor   = SKColor(red:1.0, green:0.80, blue:0.40, alpha:0.22)
            inner.strokeColor = .clear
            inner.position    = pos
            inner.zPosition   = 0.6
            inner.blendMode   = .add
            worldLayer.addChild(inner)

            // Flame dot
            let flame = SKShapeNode(circleOfRadius: 5)
            flame.fillColor   = SKColor(red:1.0, green:0.80, blue:0.30, alpha:1)
            flame.strokeColor = .clear
            flame.position    = CGPoint(x: pos.x, y: pos.y + 6)
            flame.zPosition   = 2
            flame.blendMode   = .add
            worldLayer.addChild(flame)
            flame.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.scale(to: 1.3, duration: 0.18),
                SKAction.scale(to: 0.7, duration: 0.22)
            ])))
        }
    }

    // MARK: - Pressure plate wiring

    private func wirePressurePlates() {
        let plates = allCoords(of: .pressurePlate)
        let doors  = allCoords(of: .lockedDoor)

        if mapMode == .short {
            if let plate = plates.first, doors.count >= 2 {
                plateConnections[plate] = doors[1]
                plateActive[plate] = false
            } else if let plate = plates.first, let door = doors.last {
                plateConnections[plate] = door
                plateActive[plate] = false
            }
        } else {
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
        playerNode = SKSpriteNode(texture: PixelArt.playerTile(facing: .down, frame: 0))
        playerNode.size = CGSize(width: tileSize, height: tileSize)
        playerNode.zPosition = 10
        playerNode.position = worldPos(playerCoord)
        worldLayer.addChild(playerNode)

        swordNode = SKSpriteNode(texture: texSword)
        swordNode.size = CGSize(width: tileSize * 0.6, height: tileSize * 0.28)
        swordNode.zPosition = 11
        playerNode.addChild(swordNode)
        orientSword(snap: true)
    }

    // MARK: - HUD

    private func buildHUD() {
        hudLayer = SKNode()
        hudLayer.zPosition = 200
        cameraNode.addChild(hudLayer)

        // Dark HUD bar background
        let bar = SKSpriteNode(color: SKColor(red:0, green:0, blue:0, alpha:0.72),
                               size: CGSize(width: size.width + 40, height: 40))
        bar.position = CGPoint(x: 0, y: size.height / 2 - 20)
        bar.zPosition = -1
        hudLayer.addChild(bar)

        refreshHUD()
    }

    private func refreshHUD() {
        // Remove everything except the background bar (zPosition -1)
        for child in hudLayer.children where child.zPosition >= 0 {
            child.removeFromParent()
        }

        let baseY = size.height / 2 - 20
        let leftX = -size.width / 2 + 16

        // Heart sprites
        for i in 0..<playerMaxHP {
            let tex = i < playerHP ? PixelArt.heartFull() : PixelArt.heartEmpty()
            let heart = SKSpriteNode(texture: tex)
            heart.size = CGSize(width: 20, height: 20)
            heart.position = CGPoint(x: leftX + CGFloat(i) * 22 + 10, y: baseY)
            heart.zPosition = 1
            hudLayer.addChild(heart)
        }

        // Key icon + count
        let keyIcon = SKSpriteNode(texture: texKey)
        keyIcon.size = CGSize(width: 20, height: 20)
        keyIcon.position = CGPoint(x: size.width / 2 - 70, y: baseY)
        keyIcon.zPosition = 1
        hudLayer.addChild(keyIcon)

        let keyLabel = SKLabelNode(text: "x\(playerKeys)")
        keyLabel.fontName = "Courier-Bold"
        keyLabel.fontSize = 16
        keyLabel.fontColor = SKColor(red:1.0, green:0.88, blue:0.20, alpha:1)
        keyLabel.verticalAlignmentMode   = .center
        keyLabel.horizontalAlignmentMode = .left
        keyLabel.position = CGPoint(x: size.width / 2 - 56, y: baseY)
        keyLabel.zPosition = 1
        hudLayer.addChild(keyLabel)
    }

    // MARK: - Game loop

    override func update(_ currentTime: TimeInterval) {
        guard !isGameOver, !hasWon else { return }
        let dt = (lastUpdateTime == 0) ? 0.0 : min(currentTime - lastUpdateTime, 0.05)
        lastUpdateTime = currentTime

        updateMonsterAnimations(dt: dt)
        updateSpikes(dt: dt, currentTime: currentTime)
        updateMonsters(dt: dt, currentTime: currentTime)
        updateProjectiles(dt: dt)
        updateLava(dt: dt)
    }

    private func updateLava(dt: TimeInterval) {
        lavaTimer += dt
        if lavaTimer >= 0.45 {
            lavaTimer = 0
            lavaFrame = 1 - lavaFrame
            let tex = lavaFrame == 0 ? texLavaA : texLavaB
            for node in lavaNodes { node.texture = tex }
        }
    }

    private func updateMonsterAnimations(dt: TimeInterval) {
        for monster in monsters where !monster.isDead {
            monster.animTimer += dt
            let interval: TimeInterval = monster.kind == .slime ? 0.4 : 0.35
            if monster.animTimer >= interval {
                monster.animTimer = 0
                monster.animFrame = 1 - monster.animFrame
                switch monster.kind {
                case .slime:
                    monster.node.texture = PixelArt.slimeTile(frame: monster.animFrame)
                case .skeleton:
                    monster.node.texture = PixelArt.skeletonTile(frame: monster.animFrame)
                case .demon:
                    monster.node.texture = PixelArt.demonTile(frame: monster.animFrame)
                }
            }
        }
    }

    // MARK: - Spike logic

    private func updateSpikes(dt: TimeInterval, currentTime: TimeInterval) {
        spikeTimer += dt
        if spikeTimer >= 1.2 {
            spikeTimer = 0
            spikeActive.toggle()
            for (_, node) in spikeNodes {
                node.run(SKAction.scale(to: spikeActive ? 1.0 : 0.2, duration: 0.12))
            }
        }
        if spikeActive && spikeCoords.contains(playerCoord) {
            takeDamage(amount: 1, at: currentTime)
        }
        if mapData[playerCoord.row][playerCoord.col] == .lava {
            takeDamage(amount: playerHP, at: currentTime)
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
            if let dir = ([.up, .down, .left, .right] as [DungeonDirection]).randomElement() {
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
                if !moved, monster.kind == .skeleton {
                    if let dir = ([.up, .down, .left, .right] as [DungeonDirection]).randomElement() {
                        let t = monster.coord.moved(dir)
                        if monsterCanOccupy(t) { animateMonster(monster, to: t) }
                    }
                }
            } else if monster.kind == .skeleton {
                if let dir = ([.up, .down, .left, .right] as [DungeonDirection]).randomElement() {
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
        case .up, .down:    return [.left, .right]
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

    // MARK: - Projectile

    private func fireProjectile(from monster: DungeonMonster) {
        let dx = playerCoord.col - monster.coord.col
        let dy = playerCoord.row - monster.coord.row
        guard dx != 0 || dy != 0 else { return }
        let dir = bestDirection(from: monster.coord, to: playerCoord)
        let startCoord = monster.coord.moved(dir)
        guard isTileWalkable(startCoord) else { return }

        let proj = SKSpriteNode(texture: texProj)
        proj.size = CGSize(width: tileSize * 0.5, height: tileSize * 0.5)
        proj.blendMode = .add
        proj.position = worldPos(monster.coord)
        proj.zPosition = 5
        worldLayer.addChild(proj)
        proj.run(SKAction.move(to: worldPos(startCoord), duration: 0.10))
        projectiles.append(DungeonProjectile(coord: startCoord, direction: dir, node: proj))
    }

    private func spawnSlime(near demon: DungeonMonster) {
        for dir in ([.up, .down, .left, .right] as [DungeonDirection]).shuffled() {
            let c = demon.coord.moved(dir)
            if monsterCanOccupy(c) {
                let node = SKSpriteNode(texture: PixelArt.slimeTile(frame: 0))
                node.size = CGSize(width: tileSize, height: tileSize)
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
                pixelPoof(at: projectiles[i].node.position, color: SKColor(red:0.7, green:0.1, blue:0.9, alpha:1))
                projectiles[i].node.removeFromParent()
                dead.append(i)
                continue
            }
            if next == playerCoord {
                pixelPoof(at: worldPos(next), color: SKColor(red:0.7, green:0.1, blue:0.9, alpha:1))
                projectiles[i].node.removeFromParent()
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

    // MARK: - Pixel poof effect (4 squares scatter)

    private func pixelPoof(at position: CGPoint, color: SKColor) {
        let offsets: [(CGFloat, CGFloat)] = [(8,8),(-8,8),(8,-8),(-8,-8)]
        for (dx, dy) in offsets {
            let sq = SKSpriteNode(texture: PixelArt.dustTile())
            sq.size = CGSize(width: 8, height: 8)
            sq.color = color
            sq.colorBlendFactor = 0.6
            sq.position = position
            sq.zPosition = 20
            worldLayer.addChild(sq)
            sq.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: dx * 1.5, y: dy * 1.5, duration: 0.25),
                    SKAction.fadeOut(withDuration: 0.25)
                ]),
                SKAction.removeFromParent()
            ]))
        }
    }

    // MARK: - Player damage

    private func takeDamage(amount: Int, at time: TimeInterval) {
        guard time > invincibleUntil, !isGameOver else { return }
        playerHP = max(0, playerHP - amount)
        invincibleUntil = time + 1.5

        // Classic 5-flash red/white invincibility
        let flash = SKAction.sequence([
            SKAction.colorize(with: .red, colorBlendFactor: 1.0, duration: 0),
            SKAction.wait(forDuration: 0.08),
            SKAction.colorize(with: .white, colorBlendFactor: 1.0, duration: 0),
            SKAction.wait(forDuration: 0.08)
        ])
        let restore = SKAction.colorize(with: .white, colorBlendFactor: 0, duration: 0)
        playerNode.run(SKAction.sequence([
            SKAction.repeat(flash, count: 5),
            restore
        ]))

        // Brief screen flash
        let screenFlash = SKSpriteNode(color: SKColor(red:1, green:0, blue:0, alpha:0.25),
                                       size: CGSize(width:4000, height:4000))
        screenFlash.zPosition = 150
        cameraNode.addChild(screenFlash)
        screenFlash.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.2),
            SKAction.removeFromParent()
        ]))

        refreshHUD()
        if playerHP <= 0 { triggerLose() }
    }

    // MARK: - Player movement (public API)

    func movePlayer(direction: DungeonDirection) {
        guard !isMoving, !isGameOver, !hasWon else { return }
        playerFacing = direction

        let target = playerCoord.moved(direction)

        // Push block
        if let blockNode = pushBlocks[target] {
            let blockDest = target.moved(direction)
            guard isTileWalkable(blockDest),
                  mapData[blockDest.row][blockDest.col] != .lava else { return }
            pushBlocks.removeValue(forKey: target)
            pushBlocks[blockDest] = blockNode
            blockNode.run(SKAction.move(to: worldPos(blockDest), duration: moveAnimDuration))
            evaluatePlates(blockMovedTo: blockDest, from: target)
        }

        // Locked door
        if mapData[target.row][target.col] == .lockedDoor {
            if playerKeys > 0 {
                playerKeys -= 1
                openDoorWithEffect(at: target)
                refreshHUD()
            }
            return
        }

        // Hidden wall reveal
        if mapData[target.row][target.col] == .hiddenWall {
            mapData[target.row][target.col] = .floor
            if let node = tileNodes[target.row][target.col] {
                node.run(SKAction.sequence([
                    SKAction.fadeOut(withDuration: 0.2),
                    SKAction.removeFromParent()
                ]))
                tileNodes[target.row][target.col] = nil
            }
            return
        }

        guard isTileWalkable(target) else { return }

        isMoving = true
        playerCoord = target

        // Update sprite facing + walk frame
        playerAnimFrame = 1 - playerAnimFrame
        playerNode.texture = PixelArt.playerTile(facing: playerFacing, frame: playerAnimFrame)
        orientSword(snap: false)
        smoothCameraToPlayer()

        // Pixel dust poof on step
        let dustPos = CGPoint(x: playerNode.position.x, y: playerNode.position.y - tileSize * 0.35)
        pixelPoof(at: dustPos, color: SKColor(red:0.7, green:0.65, blue:0.55, alpha:1))

        playerNode.run(SKAction.move(to: worldPos(target), duration: moveAnimDuration)) { [weak self] in
            guard let self else { return }
            self.isMoving = false
            self.evaluatePlates(blockMovedTo: nil, from: nil)
            self.onPlayerLanded()
        }
    }

    private func orientSword(snap: Bool) {
        let offset: CGFloat = tileSize * 0.52
        let halfTile: CGFloat = tileSize * 0.3
        switch playerFacing {
        case .right:
            swordNode.position   = CGPoint(x: offset, y: 0)
            swordNode.zRotation  = 0
            swordNode.xScale     = 1
        case .left:
            swordNode.position   = CGPoint(x: -offset, y: 0)
            swordNode.zRotation  = .pi
            swordNode.xScale     = 1
        case .up:
            swordNode.position   = CGPoint(x: 0, y: halfTile)
            swordNode.zRotation  = .pi / 2
            swordNode.xScale     = 1
        case .down:
            swordNode.position   = CGPoint(x: 0, y: -halfTile)
            swordNode.zRotation  = -.pi / 2
            swordNode.xScale     = 1
        }
    }

    private func onPlayerLanded() {
        // Key pickup — classic Zelda item-get animation
        if let keyNode = keyNodesByCoord[playerCoord], !pickedUpKeys.contains(playerCoord) {
            pickedUpKeys.insert(playerCoord)
            playerKeys += 1
            isMoving = true  // block movement during pickup

            // Player holds key above head
            let holdKey = SKSpriteNode(texture: texKey)
            holdKey.size = CGSize(width: tileSize, height: tileSize)
            holdKey.position = CGPoint(x: 0, y: tileSize * 0.9)
            holdKey.zPosition = 12
            playerNode.addChild(holdKey)

            // "Got a Key!" pixel text popup
            let popup = SKLabelNode(text: "Got a Key!")
            popup.fontName = "Courier-Bold"
            popup.fontSize = 14
            popup.fontColor = SKColor(red:1.0, green:0.88, blue:0.20, alpha:1)
            popup.position = CGPoint(x: playerNode.position.x, y: playerNode.position.y + tileSize * 1.5)
            popup.zPosition = 30
            worldLayer.addChild(popup)

            keyNode.removeFromParent()

            let wait = SKAction.wait(forDuration: 0.5)
            let dismiss = SKAction.run { [weak self] in
                holdKey.removeFromParent()
                popup.removeFromParent()
                self?.isMoving = false
            }
            run(SKAction.sequence([wait, dismiss]))
            refreshHUD()
        }

        // Exit
        if mapData[playerCoord.row][playerCoord.col] == .exit {
            triggerWin()
        }
    }

    // MARK: - Plate evaluation

    private func evaluatePlates(blockMovedTo: TileCoord?, from blockFrom: TileCoord?) {
        for (plateCoord, doorCoord) in plateConnections {
            let blockOnPlate  = pushBlocks[plateCoord] != nil
            let playerOnPlate = playerCoord == plateCoord
            let nowActive     = blockOnPlate || playerOnPlate
            let wasActive     = plateActive[plateCoord] ?? false
            guard nowActive != wasActive else { continue }
            plateActive[plateCoord] = nowActive
            if nowActive { openDoorWithEffect(at: doorCoord) }
            else          { closeDoor(at: doorCoord) }

            // Visual feedback: plate changes color
            if let plateNode = tileNodes[plateCoord.row][plateCoord.col] as? SKSpriteNode {
                if nowActive {
                    plateNode.color = SKColor(red:0.2, green:0.8, blue:0.2, alpha:1)
                    plateNode.colorBlendFactor = 0.7
                } else {
                    plateNode.colorBlendFactor = 0
                }
            }
        }
    }

    private func openDoor(at coord: TileCoord) {
        guard mapData[coord.row][coord.col] == .lockedDoor else { return }
        mapData[coord.row][coord.col] = .openDoor
        if let node = tileNodes[coord.row][coord.col] {
            node.removeFromParent()
            tileNodes[coord.row][coord.col] = nil
        }
    }

    // Door opens with pixel fragment scatter effect
    private func openDoorWithEffect(at coord: TileCoord) {
        guard mapData[coord.row][coord.col] == .lockedDoor else { return }
        mapData[coord.row][coord.col] = .openDoor

        if let node = tileNodes[coord.row][coord.col] {
            let center = node.position
            // Scatter 6 pixel fragments
            for i in 0..<6 {
                let frag = SKSpriteNode(texture: texPushBlock)
                frag.size = CGSize(width: 8, height: 8)
                frag.color = SKColor(red:0.55, green:0.30, blue:0.12, alpha:1)
                frag.colorBlendFactor = 0.5
                frag.position = center
                frag.zPosition = 25
                worldLayer.addChild(frag)
                let angle = CGFloat(i) * (.pi / 3)
                let dist: CGFloat = CGFloat.random(in: 20...50)
                frag.run(SKAction.sequence([
                    SKAction.group([
                        SKAction.moveBy(x: cos(angle)*dist, y: sin(angle)*dist, duration: 0.3),
                        SKAction.rotate(byAngle: .pi * 2, duration: 0.3),
                        SKAction.fadeOut(withDuration: 0.3)
                    ]),
                    SKAction.removeFromParent()
                ]))
            }
            node.removeFromParent()
            tileNodes[coord.row][coord.col] = nil
        }
    }

    private func closeDoor(at coord: TileCoord) {
        guard mapData[coord.row][coord.col] == .openDoor else { return }
        guard playerCoord != coord, pushBlocks[coord] == nil else { return }
        mapData[coord.row][coord.col] = .lockedDoor
        let node = lockedDoorSprite()
        node.position = worldPos(coord)
        node.zPosition = 2
        node.alpha = 0
        worldLayer.addChild(node)
        node.run(SKAction.fadeIn(withDuration: 0.2))
        tileNodes[coord.row][coord.col] = node
    }

    // MARK: - Player attack (public API)

    func playerAttack() {
        guard !isGameOver, !hasWon, !isAttacking else { return }
        isAttacking = true

        // Sword sweep arc
        let sweep: CGFloat = .pi * 0.80
        swordNode.run(SKAction.sequence([
            SKAction.rotate(byAngle: sweep, duration: 0.12),
            SKAction.rotate(byAngle: -sweep, duration: 0.08),
            SKAction.run { [weak self] in self?.isAttacking = false }
        ]))

        // Sword flash
        swordNode.run(SKAction.sequence([
            SKAction.colorize(with: .white, colorBlendFactor: 1.0, duration: 0),
            SKAction.wait(forDuration: 0.12),
            SKAction.colorize(with: .white, colorBlendFactor: 0, duration: 0.08)
        ]))

        let hitCoord = playerCoord.moved(playerFacing)
        for monster in monsters where !monster.isDead && monster.coord == hitCoord {
            damageMonster(monster)
        }
    }

    private func damageMonster(_ monster: DungeonMonster) {
        monster.hp -= 1

        // Classic white-flash 3 times
        let hitFlash = SKAction.sequence([
            SKAction.colorize(with: .white, colorBlendFactor: 1, duration: 0),
            SKAction.wait(forDuration: 0.07),
            SKAction.colorize(with: .white, colorBlendFactor: 0, duration: 0)
        ])
        monster.node.run(SKAction.sequence([
            SKAction.repeat(hitFlash, count: 3)
        ]))

        // Knockback 0.5 tiles
        let knockDir = playerFacing
        let knockCoord = monster.coord.moved(knockDir)
        if monsterCanOccupy(knockCoord) {
            let kPos = CGPoint(
                x: (worldPos(monster.coord).x + worldPos(knockCoord).x) / 2,
                y: (worldPos(monster.coord).y + worldPos(knockCoord).y) / 2
            )
            monster.node.run(SKAction.sequence([
                SKAction.move(to: kPos, duration: 0.06),
                SKAction.move(to: worldPos(monster.coord), duration: 0.06)
            ]))
        }

        if monster.hp <= 0 { killMonster(monster) }
    }

    private func killMonster(_ monster: DungeonMonster) {
        monster.isDead = true

        if monster.kind == .demon {
            // Boss death: 8-frame pixel explosion
            bossDeath(monster)
        } else {
            // Pixel poof — 4 squares scatter
            pixelPoof(at: monster.node.position, color: SKColor(red:0.4, green:0.9, blue:0.4, alpha:1))
            monster.node.run(SKAction.sequence([
                SKAction.group([
                    SKAction.scale(to: 0.1, duration: 0.18),
                    SKAction.fadeOut(withDuration: 0.18)
                ]),
                SKAction.removeFromParent()
            ]))
        }
        if mapMode == .long, monster.kind == .demon {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
                self?.triggerWin()
            }
        }
    }

    private func bossDeath(_ monster: DungeonMonster) {
        let center = monster.node.position
        monster.node.removeFromParent()

        // 8 expanding pixel explosion rings
        for i in 0..<8 {
            let delay = TimeInterval(i) * 0.08
            let ring = SKShapeNode(circleOfRadius: CGFloat(i + 1) * 8)
            ring.fillColor   = SKColor(red:0.8, green:0.2, blue:1.0, alpha:0.7)
            ring.strokeColor = SKColor(red:1.0, green:0.5, blue:1.0, alpha:0.9)
            ring.lineWidth   = 3
            ring.position    = center
            ring.zPosition   = 30
            ring.blendMode   = .add
            ring.alpha        = 0
            worldLayer.addChild(ring)
            ring.run(SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.fadeIn(withDuration: 0.05),
                SKAction.group([
                    SKAction.scale(to: 3.0, duration: 0.35),
                    SKAction.fadeOut(withDuration: 0.35)
                ]),
                SKAction.removeFromParent()
            ]))
        }

        // Pixel debris scatter
        for i in 0..<12 {
            let frag = SKShapeNode(rectOf: CGSize(width: 6, height: 6))
            frag.fillColor = [SKColor(red:0.8,green:0.2,blue:1.0,alpha:1),
                              SKColor(red:1.0,green:0.4,blue:0.4,alpha:1),
                              SKColor(red:1.0,green:0.8,blue:0.0,alpha:1)][i % 3]
            frag.strokeColor = .clear
            frag.position = center
            frag.zPosition = 31
            frag.blendMode = .add
            worldLayer.addChild(frag)
            let angle = CGFloat(i) * (.pi * 2 / 12)
            let dist  = CGFloat.random(in: 40...100)
            frag.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: cos(angle)*dist, y: sin(angle)*dist, duration: 0.6),
                    SKAction.fadeOut(withDuration: 0.6),
                    SKAction.rotate(byAngle: .pi * 3, duration: 0.6)
                ]),
                SKAction.removeFromParent()
            ]))
        }

        // Screen flash
        let flash = SKSpriteNode(color: SKColor(red:0.7, green:0.0, blue:0.9, alpha:0.6),
                                 size: CGSize(width:4000, height:4000))
        flash.zPosition = 150
        cameraNode.addChild(flash)
        flash.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.05),
            SKAction.fadeOut(withDuration: 0.4),
            SKAction.removeFromParent()
        ]))

        // VICTORY text — dramatic pause then display
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            let bg = SKSpriteNode(color: SKColor(red:0.1, green:0.02, blue:0.18, alpha:0.9),
                                  size: CGSize(width:320, height:120))
            bg.zPosition = 300
            self.cameraNode.addChild(bg)

            let title = SKLabelNode(text: "VICTORY!")
            title.fontName = "Courier-Bold"
            title.fontSize = 40
            title.fontColor = SKColor(red:1.0, green:0.88, blue:0.0, alpha:1)
            title.verticalAlignmentMode = .center
            title.position = CGPoint(x: 0, y: 20)
            bg.addChild(title)

            let sub = SKLabelNode(text: "The demon falls!")
            sub.fontName = "Courier"
            sub.fontSize = 16
            sub.fontColor = SKColor(red:0.9, green:0.8, blue:1.0, alpha:1)
            sub.verticalAlignmentMode = .center
            sub.position = CGPoint(x: 0, y: -22)
            bg.addChild(sub)

            // Pixel blink effect on title
            title.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0),
                SKAction.wait(forDuration: 0.15),
                SKAction.fadeIn(withDuration: 0),
                SKAction.wait(forDuration: 0.35)
            ])))
        }
    }

    // MARK: - Win / Lose

    private func triggerWin() {
        guard !hasWon, !isGameOver else { return }
        hasWon = true
        if let cb = onWin { DispatchQueue.main.async { cb() }; return }
        showBanner(title: "YOU WIN!", sub: "Dungeon cleared",
                   color: SKColor(red:0.06, green:0.35, blue:0.10, alpha:0.94))
    }

    private func triggerLose() {
        guard !isGameOver else { return }
        isGameOver = true
        if let cb = onLose { DispatchQueue.main.async { cb() }; return }
        showBanner(title: "YOU DIED", sub: "Tap to try again",
                   color: SKColor(red:0.40, green:0.00, blue:0.00, alpha:0.94))
    }

    private func showBanner(title: String, sub: String, color: SKColor) {
        let bg = SKSpriteNode(color: color, size: CGSize(width: 380, height: 160))
        bg.zPosition = 300
        cameraNode.addChild(bg)

        let border = SKShapeNode(rectOf: CGSize(width: 380, height: 160))
        border.fillColor = .clear
        border.strokeColor = SKColor(white: 0.9, alpha: 0.6)
        border.lineWidth = 2
        border.zPosition = 1
        bg.addChild(border)

        let t = SKLabelNode(text: title)
        t.fontName = "Courier-Bold"
        t.fontSize = 44
        t.fontColor = .white
        t.verticalAlignmentMode = .center
        t.position = CGPoint(x: 0, y: 32)
        bg.addChild(t)

        let s = SKLabelNode(text: sub)
        s.fontName = "Courier"
        s.fontSize = 18
        s.fontColor = SKColor(white: 0.85, alpha: 1)
        s.verticalAlignmentMode = .center
        s.position = CGPoint(x: 0, y: -24)
        bg.addChild(s)

        // Pixel blink the main title
        t.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0),
            SKAction.wait(forDuration: 0.12),
            SKAction.fadeIn(withDuration: 0),
            SKAction.wait(forDuration: 0.40)
        ])))
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
        lavaNodes.removeAll()
        tileNodes = []; mapData = []
        isGameOver = false; hasWon = false
        playerHP = playerMaxHP; playerKeys = 0
        isMoving = false; lastUpdateTime = 0
        spikeTimer = 0; projTimer = 0; lavaTimer = 0; lavaFrame = 0
        playerAnimFrame = 0; isAttacking = false
        hasBuilt = false
        if let v = view { didMove(to: v) }
    }

    // MARK: - Map strings

    private func shortMapString() -> String {
        // 15 cols × 12 rows
        // Flow: push B onto P → opens lower locked door → key room →
        //       use key on upper locked door → fight monsters → exit E
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
        // 20 cols × 20 rows — 5 rooms + corridors + lava moat
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
            "#K..#....LLL...P..X#",
            "#...#....LLL......E#",
            "####################",
        ].joined(separator: "\n")
    }
}
