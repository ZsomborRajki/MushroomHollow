import CoreGraphics
import RealityKit
import UIKit

/// Hand-drawn ink textures, painted with CoreGraphics at launch (a sibling of `FacePainter`).
/// Strokes get jittered ends and uneven widths from a fixed seed, so they look drawn, not generated,
/// yet come out the same every launch. Presentation only: never GameCore's `SeededRandom` stream.
@MainActor
enum InkPainter {
    /// A flat square in the XZ plane, 2 × 2 (so a scale of r gives radius r), facing up, with UVs.
    static let shadowPlane = MeshResource.generatePlane(width: 2, depth: 2)

    /// A cast shadow colored in with a marker: one flat, cool tone with a slightly uneven edge,
    /// no hatching, no soft falloff. Transparent everywhere else.
    static func blobShadow() -> TextureResource? {
        let size = CGSize(width: 256, height: 256)
        var random = InkRandom(seed: 0xB10B)
        let tone = UIColor(red: 0.3, green: 0.32, blue: 0.46, alpha: 0.3)
        let image = render(size) { cg in
            let center = CGPoint(x: 128, y: 128)
            let radius: CGFloat = 104
            let path = CGMutablePath()
            let steps = 40
            for i in 0...steps {
                let a = CGFloat(i) / CGFloat(steps) * 2 * .pi
                let r = radius + random.jitter(2)
                let point = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r * 0.9)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            cg.addPath(path)
            cg.setFillColor(tone.cgColor)
            cg.fillPath()
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource(image: cgImage, options: .init(semantic: .color))
    }

    /// A drifting seed mote, drawn: a pale dot inside a wobbly ink ring, with a fleck of shine.
    /// The ink style's ambient spores use it instead of soft additive glows, which read as smoke
    /// over the light, paper-like colors.
    static func mote() -> TextureResource? {
        let size = CGSize(width: 64, height: 64)
        var random = InkRandom(seed: 0x5EED)
        let ink = UIColor(red: 0.16, green: 0.13, blue: 0.1, alpha: 0.9)
        let image = render(size) { cg in
            let center = CGPoint(x: 32, y: 32)
            let path = CGMutablePath()
            let steps = 18
            for i in 0...steps {
                let a = CGFloat(i) / CGFloat(steps) * 2 * .pi
                let r = 17 + random.jitter(1.6)
                let point = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            cg.addPath(path)
            cg.setFillColor(UIColor(red: 1, green: 0.97, blue: 0.82, alpha: 1).cgColor)
            cg.fillPath()
            cg.addPath(path)
            cg.setLineWidth(5)
            cg.setLineJoin(.round)
            cg.setStrokeColor(ink.cgColor)
            cg.strokePath()
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillEllipse(in: CGRect(x: 36, y: 21, width: 7, height: 6))
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource(image: cgImage, options: .init(semantic: .color))
    }

    // MARK: - Ground tiles

    /// Pixels on a side of one ground tile (`inkGround`'s `kTile` meters across).
    static let groundTileSize = 512

    /// The forest floor's repeating detail, after PureBDCraft's cartoon textures: chunky light
    /// shapes, darker flecks, and a few inked bits. One channel per ground cover (r grass, g dirt,
    /// b sand), each coded in levels the shader turns into tones of whatever color is painted
    /// underneath: 0.5 leaves it alone, above lightens (1 = brightest), 0.2...0.5 darkens, below 0.2
    /// is ink. The tile wraps: shapes running off one edge come back in on the other, so it repeats
    /// without seams (and without a block grid).
    static func groundDetail() -> TextureResource? {
        let n = groundTileSize
        let channels: [[UInt8]] = [
            grayTile(n, seed: 0x6A55, draw: drawGrassTile),
            grayTile(n, seed: 0xD127, draw: drawDirtTile),
            grayTile(n, seed: 0x5A2D, draw: drawSandTile),
        ]
        var bytes = [UInt8](repeating: 255, count: n * n * 4)
        for i in 0..<(n * n) {
            bytes[i * 4] = channels[0][i]
            bytes[i * 4 + 1] = channels[1][i]
            bytes[i * 4 + 2] = channels[2][i]
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return try? TextureResource(image: image, options: .init(semantic: .raw))
    }

    /// Detail levels (see `groundDetail`).
    private enum Level {
        static let ink: CGFloat = 0.02
        static let dark: CGFloat = 0.3
        static let shade: CGFloat = 0.4
        static let light: CGFloat = 0.72
        static let bright: CGFloat = 0.92
    }

    private static func grayTile(_ n: Int, seed: UInt64, draw: (CGContext, CGFloat, inout InkRandom) -> Void) -> [UInt8] {
        var bytes = [UInt8](repeating: 128, count: n * n)
        bytes.withUnsafeMutableBytes { buffer in
            guard let cg = CGContext(data: buffer.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n,
                                     space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return }
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            // The same drawing nine times over, shifted a tile each way, so it wraps at the edges.
            let size = CGFloat(n)
            for dy in -1...1 {
                for dx in -1...1 {
                    var random = InkRandom(seed: seed)
                    cg.saveGState()
                    cg.translateBy(x: CGFloat(dx) * size, y: CGFloat(dy) * size)
                    draw(cg, size, &random)
                    cg.restoreGState()
                }
            }
        }
        return bytes
    }

    /// Spots spread over the tile (a jittered grid, so they don't clump).
    private static func spots(_ count: Int, size: CGFloat, random: inout InkRandom) -> [CGPoint] {
        let side = Int(ceil(sqrt(Double(count))))
        let cell = size / CGFloat(side)
        var cells = Array(0..<(side * side))
        for i in cells.indices.reversed() {
            cells.swapAt(i, Int(random.next() % UInt64(i + 1)))
        }
        return cells.prefix(count).map { index in
            CGPoint(x: (CGFloat(index % side) + 0.15 + 0.7 * random.unit()) * cell,
                    y: (CGFloat(index / side) + 0.15 + 0.7 * random.unit()) * cell)
        }
    }

    /// A lumpy closed blob around `center`.
    private static func blob(_ center: CGPoint, radius: CGFloat, squash: CGFloat = 1, lumps: Int = 7,
                             random: inout InkRandom) -> CGPath {
        let path = CGMutablePath()
        let turn = random.unit() * 2 * .pi
        for i in 0..<lumps {
            let a = CGFloat(i) / CGFloat(lumps) * 2 * .pi
            let r = radius * (0.8 + 0.35 * random.unit())
            let point = CGPoint(x: center.x + cos(a + turn) * r, y: center.y + sin(a + turn) * r * squash)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private static func fill(_ cg: CGContext, _ path: CGPath, _ level: CGFloat) {
        cg.addPath(path)
        cg.setFillColor(gray: level, alpha: 1)
        cg.fillPath()
    }

    private static func stroke(_ cg: CGContext, _ path: CGPath, _ level: CGFloat, width: CGFloat) {
        cg.addPath(path)
        cg.setStrokeColor(gray: level, alpha: 1)
        cg.setLineWidth(width)
        cg.strokePath()
    }

    /// PureBDCraft's little four-point sparkle stud.
    private static func sparkle(_ cg: CGContext, at c: CGPoint, radius r: CGFloat, level: CGFloat) {
        let path = CGMutablePath()
        let waist = r * 0.28
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addLine(to: CGPoint(x: c.x + waist, y: c.y - waist))
        path.addLine(to: CGPoint(x: c.x + r, y: c.y))
        path.addLine(to: CGPoint(x: c.x + waist, y: c.y + waist))
        path.addLine(to: CGPoint(x: c.x, y: c.y + r))
        path.addLine(to: CGPoint(x: c.x - waist, y: c.y + waist))
        path.addLine(to: CGPoint(x: c.x - r, y: c.y))
        path.addLine(to: CGPoint(x: c.x - waist, y: c.y - waist))
        path.closeSubpath()
        fill(cg, path, level)
    }

    /// Grass: dark flecks, pale clumps, tufts of pointed blades fanned out and inked, a clover or two,
    /// and a sparkle.
    private static func drawGrassTile(_ cg: CGContext, _ size: CGFloat, _ random: inout InkRandom) {
        let unit = size / 512 * 1.3
        for p in spots(10, size: size, random: &random) {
            let r = (7 + 7 * random.unit()) * unit
            fill(cg, blob(p, radius: r, squash: 0.6, lumps: 5, random: &random), Level.shade)
        }
        for p in spots(6, size: size, random: &random) {
            fill(cg, blob(p, radius: (16 + 12 * random.unit()) * unit, squash: 0.75, random: &random), Level.light)
        }
        // Tufts: blades fanning up from a shared root, filled bright, inked round the outside.
        for p in spots(4, size: size, random: &random) {
            let blades = 3 + Int(random.next() % 3)
            let height = (34 + 22 * random.unit()) * unit
            let path = CGMutablePath()
            for b in 0..<blades {
                let spread = (CGFloat(b) / CGFloat(blades - 1) - 0.5) * 1.5 + random.jitter(0.12)
                let length = height * (b == blades / 2 ? 1 : 0.7 + 0.2 * random.unit())
                let tip = CGPoint(x: p.x + sin(spread) * length, y: p.y - cos(spread) * length)
                let base = 7 * unit
                path.move(to: CGPoint(x: p.x - base + CGFloat(b) * 3 * unit, y: p.y))
                path.addQuadCurve(to: tip, control: CGPoint(x: p.x + sin(spread) * length * 0.3 - base, y: p.y - length * 0.5))
                path.addQuadCurve(to: CGPoint(x: p.x + base + CGFloat(b) * 3 * unit, y: p.y),
                                  control: CGPoint(x: p.x + sin(spread) * length * 0.3 + base, y: p.y - length * 0.5))
                path.closeSubpath()
            }
            stroke(cg, path, Level.ink, width: 6 * unit)
            fill(cg, path, Level.bright)
            // A shade line down the middle blade.
            let mid = CGMutablePath()
            mid.move(to: CGPoint(x: p.x + 2 * unit, y: p.y - 3 * unit))
            mid.addLine(to: CGPoint(x: p.x + 2 * unit, y: p.y - height * 0.55))
            stroke(cg, mid, Level.light, width: 3 * unit)
        }
        // Clover: three round leaves, inked.
        for p in spots(2, size: size, random: &random) {
            let r = (10 + 3 * random.unit()) * unit
            let turn = random.unit() * 2 * .pi
            let leaves = CGMutablePath()
            for i in 0..<3 {
                let a = turn + CGFloat(i) * 2 * .pi / 3
                leaves.addEllipse(in: CGRect(x: p.x + cos(a) * r - r, y: p.y + sin(a) * r - r, width: 2 * r, height: 2 * r))
            }
            stroke(cg, leaves, Level.ink, width: 5 * unit)
            fill(cg, leaves, Level.light)
            fill(cg, CGPath(ellipseIn: CGRect(x: p.x - 3 * unit, y: p.y - 3 * unit, width: 6 * unit, height: 6 * unit), transform: nil), Level.shade)
        }
        for p in spots(2, size: size, random: &random) {
            sparkle(cg, at: p, radius: (9 + 5 * random.unit()) * unit, level: Level.bright)
        }
    }

    /// Dirt: pale clods, dark speckles, inked cracks, and pebbles with a shaded underside.
    private static func drawDirtTile(_ cg: CGContext, _ size: CGFloat, _ random: inout InkRandom) {
        let unit = size / 512 * 1.3
        for p in spots(5, size: size, random: &random) {
            fill(cg, blob(p, radius: (18 + 14 * random.unit()) * unit, squash: 0.7, lumps: 6, random: &random), Level.light)
        }
        for p in spots(12, size: size, random: &random) {
            let r = (3 + 4 * random.unit()) * unit
            fill(cg, CGPath(ellipseIn: CGRect(x: p.x - r, y: p.y - r * 0.7, width: 2 * r, height: 1.4 * r), transform: nil), Level.dark)
        }
        // Cracks: short jagged lines with a branch, in a dark tone (inked, they read as scribbles).
        for p in spots(1, size: size, random: &random) {
            let path = CGMutablePath()
            var point = p
            var heading = random.unit() * 2 * .pi
            path.move(to: point)
            for step in 0..<5 {
                heading += random.jitter(0.9)
                point = CGPoint(x: point.x + cos(heading) * 18 * unit, y: point.y + sin(heading) * 18 * unit)
                path.addLine(to: point)
                if step == 2 {
                    let branch = heading + (random.unit() < 0.5 ? 1 : -1) * 0.9
                    path.addLine(to: CGPoint(x: point.x + cos(branch) * 20 * unit, y: point.y + sin(branch) * 20 * unit))
                    path.move(to: point)
                }
            }
            stroke(cg, path, Level.dark, width: 6 * unit)
        }
        // Pebbles: a pale top, a shaded lower lip, a dark outline (inked, a floor of them reads as rings).
        for p in spots(3, size: size, random: &random) {
            let r = (16 + 12 * random.unit()) * unit
            let pebble = blob(p, radius: r, squash: 0.72, lumps: 9, random: &random)
            fill(cg, pebble, Level.shade)
            fill(cg, blob(CGPoint(x: p.x - r * 0.12, y: p.y - r * 0.15), radius: r * 0.72, squash: 0.62, lumps: 8, random: &random), Level.bright)
            stroke(cg, pebble, Level.dark, width: 5 * unit)
        }
    }

    /// Sand: pale ripple arcs, fine dark grains, and a little inked shell.
    private static func drawSandTile(_ cg: CGContext, _ size: CGFloat, _ random: inout InkRandom) {
        let unit = size / 512 * 1.3
        for p in spots(5, size: size, random: &random) {
            let path = CGMutablePath()
            let width = (50 + 30 * random.unit()) * unit
            path.move(to: CGPoint(x: p.x - width / 2, y: p.y))
            path.addQuadCurve(to: CGPoint(x: p.x + width / 2, y: p.y + random.jitter(6) * unit),
                              control: CGPoint(x: p.x, y: p.y - 16 * unit))
            stroke(cg, path, Level.light, width: 7 * unit)
        }
        for p in spots(20, size: size, random: &random) {
            let r = (2.5 + 2.5 * random.unit()) * unit
            fill(cg, CGPath(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r), transform: nil),
                 random.unit() < 0.7 ? Level.dark : Level.bright)
        }
        for p in spots(1, size: size, random: &random) {
            // A scallop shell: a fan with ribs.
            let r = 20 * unit
            let shell = CGMutablePath()
            shell.move(to: CGPoint(x: p.x, y: p.y + r * 0.6))
            shell.addArc(center: p, radius: r, startAngle: .pi * 1.1, endAngle: .pi * 1.9, clockwise: false)
            shell.closeSubpath()
            fill(cg, shell, Level.bright)
            let ribs = CGMutablePath()
            for i in 1..<4 {
                let a = CGFloat.pi * (1.1 + 0.8 * CGFloat(i) / 4)
                ribs.move(to: CGPoint(x: p.x, y: p.y + r * 0.6))
                ribs.addLine(to: CGPoint(x: p.x + cos(a) * r * 0.9, y: p.y + sin(a) * r * 0.9))
            }
            stroke(cg, ribs, Level.shade, width: 3 * unit)
            stroke(cg, shell, Level.ink, width: 5 * unit)
        }
    }

    private static func render(_ size: CGSize, _ draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
    }
}

/// Small deterministic generator for presentation-only randomness (xorshift).
struct InkRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    /// 0 ..< 1
    mutating func unit() -> CGFloat {
        CGFloat(next() >> 11) / CGFloat(1 << 53)
    }

    /// -amount ... amount
    mutating func jitter(_ amount: CGFloat) -> CGFloat {
        (unit() * 2 - 1) * amount
    }
}
