import CoreGraphics
import GameCore
import UIKit

/// Paints the forest floor into one big top-down image: moss that yellows on hilltops and
/// darkens in hollows, each hunting ground's own ground cover, dirt roads, the lake's beach,
/// and soft contact shadows under every rock and stalk. The terrain wears it as a texture,
/// and the map screen reuses it.
///
/// Image space: x runs with world x, y with world z (north, -Z, at the top), covering ±`extent`.
@MainActor
enum GroundPainter {
    static let extent: Float = 336

    static func paint(_ map: WorldMap, size: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let pixels = CGFloat(size)
        return UIGraphicsImageRenderer(size: CGSize(width: pixels, height: pixels), format: format).image { context in
            let cg = context.cgContext
            let scale = pixels / CGFloat(2 * extent)
            // Draw in world meters from here on.
            cg.scaleBy(x: scale, y: scale)
            cg.translateBy(x: CGFloat(extent), y: CGFloat(extent))
            paintHeights(map, in: cg)
            var random = SeededRandom(seed: 0x6A0_0D)
            paintMottling(map, in: cg, random: &random)
            paintBiomes(map, in: cg, random: &random)
            paintLake(map, in: cg)
            paintRoads(map, in: cg)
            paintShadows(map, in: cg)
        }
    }

    /// Ground color from height: lush in the dips, drier on the hills, dark and wooded up the rim.
    private static func paintHeights(_ map: WorldMap, in cg: CGContext) {
        let n = 168
        var bytes = [UInt8](repeating: 255, count: n * n * 4)
        let low = SIMD3<Float>(0.16, 0.27, 0.12), mid = SIMD3<Float>(0.25, 0.37, 0.16)
        let dry = SIMD3<Float>(0.4, 0.43, 0.2), rim = SIMD3<Float>(0.15, 0.22, 0.13)
        for row in 0..<n {
            for column in 0..<n {
                let p = Vec2(-extent + (Float(column) + 0.5) / Float(n) * 2 * extent,
                             -extent + (Float(row) + 0.5) / Float(n) * 2 * extent)
                let h = map.groundHeight(at: p)
                var c = mid
                c = mix(c, dry, smooth(1.5, 8, h))
                c = mix(c, low, smooth(0, -2, h))
                c = mix(c, rim, smooth(10, 26, h))
                let i = (row * n + column) * 4
                bytes[i] = UInt8(c.x * 255)
                bytes[i + 1] = UInt8(c.y * 255)
                bytes[i + 2] = UInt8(c.z * 255)
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return }
        cg.saveGState()
        cg.interpolationQuality = .high
        // CGContext.draw puts row 0 at the top of an unflipped rect; flip so it lands at -Z (the top).
        let e = CGFloat(extent)
        cg.scaleBy(x: 1, y: -1)
        cg.draw(image, in: CGRect(x: -e, y: -e, width: 2 * e, height: 2 * e))
        cg.restoreGState()
    }

    /// Soft blotches of darker moss, pale moss, bare earth, and leaf litter.
    private static func paintMottling(_ map: WorldMap, in cg: CGContext, random: inout SeededRandom) {
        let tones = [
            UIColor(red: 0.15, green: 0.25, blue: 0.1, alpha: 0.55),
            UIColor(red: 0.33, green: 0.45, blue: 0.2, alpha: 0.4),
            UIColor(red: 0.36, green: 0.28, blue: 0.18, alpha: 0.35),
            UIColor(red: 0.5, green: 0.36, blue: 0.18, alpha: 0.3),
        ]
        for i in 0..<1800 {
            let p = random.point(inDiscAt: .zero, radius: extent)
            blot(cg, at: p, radius: random.float(in: 2...11), color: tones[i % tones.count])
        }
    }

    private static func paintBiomes(_ map: WorldMap, in cg: CGContext, random: inout SeededRandom) {
        for zone in map.zones {
            let tint: UIColor?
            switch zone.name {
            case "Dewleaf Glade": tint = UIColor(red: 0.36, green: 0.52, blue: 0.2, alpha: 0.5)
            case "Root Maze": tint = UIColor(red: 0.15, green: 0.24, blue: 0.12, alpha: 0.45)
            case "Barkfall Hollow": tint = UIColor(red: 0.4, green: 0.3, blue: 0.2, alpha: 0.55)
            case "Spore Fen": tint = UIColor(red: 0.28, green: 0.2, blue: 0.3, alpha: 0.75)
            case "The Great Bough": tint = UIColor(red: 0.3, green: 0.32, blue: 0.3, alpha: 0.6)
            case "Buttercup Meadow": tint = UIColor(red: 0.45, green: 0.52, blue: 0.2, alpha: 0.5)
            case "Mossback Creek": tint = UIColor(red: 0.32, green: 0.36, blue: 0.22, alpha: 0.35)
            case "Silkshade Thicket": tint = UIColor(red: 0.13, green: 0.17, blue: 0.13, alpha: 0.6)
            case "Pinecone Rise": tint = UIColor(red: 0.5, green: 0.33, blue: 0.18, alpha: 0.55)
            case "Briar Tangle": tint = UIColor(red: 0.42, green: 0.26, blue: 0.2, alpha: 0.55)
            case "Stagshade Grove": tint = UIColor(red: 0.14, green: 0.18, blue: 0.11, alpha: 0.6)
            default: tint = nil
            }
            guard let tint else { continue }
            // A soft wash over the whole ground, plus patchy extra blots so the edge isn't a circle.
            blot(cg, at: zone.center, radius: zone.radius * 1.15, color: tint.withAlphaComponent(tint.cgColor.alpha * 0.8))
            for _ in 0..<Int(zone.radius / 2) {
                let p = random.point(inDiscAt: zone.center, radius: zone.radius)
                blot(cg, at: p, radius: random.float(in: 3...9), color: tint)
            }
        }
        // Mossback Creek's sandy bed.
        let sand = UIColor(red: 0.66, green: 0.58, blue: 0.43, alpha: 1)
        for hill in map.terrain.hills where hill.height < 0 && hill.radius < 10 {
            blot(cg, at: hill.center, radius: hill.radius * 0.9, color: sand.withAlphaComponent(0.8))
        }
        // Packed dirt in the village, bare earth around the trunk's feet.
        let dirt = UIColor(red: 0.42, green: 0.33, blue: 0.22, alpha: 0.95)
        blot(cg, at: map.villageCenter, radius: map.villageRadius * 1.05, color: dirt)
        blot(cg, at: .zero, radius: map.trunkCollisionRadius + 9, color: UIColor(red: 0.2, green: 0.16, blue: 0.11, alpha: 0.8))
        if let arena = map.bossArena {
            blot(cg, at: arena.center, radius: arena.radius * 1.2, color: UIColor(red: 0.3, green: 0.32, blue: 0.3, alpha: 0.85))
        }
    }

    private static func paintLake(_ map: WorldMap, in cg: CGContext) {
        for lake in map.terrain.lakes {
            func fillDiscs(grow: Float, _ color: UIColor) {
                color.setFill()
                for disc in lake.discs {
                    let r = CGFloat(disc.radius + grow)
                    cg.fillEllipse(in: CGRect(x: CGFloat(disc.center.x) - r, y: CGFloat(disc.center.y) - r, width: 2 * r, height: 2 * r))
                }
            }
            fillDiscs(grow: Lake.shoreWidth + 1.5, UIColor(red: 0.5, green: 0.47, blue: 0.3, alpha: 0.5))
            fillDiscs(grow: Lake.shoreWidth - 0.5, UIColor(red: 0.7, green: 0.63, blue: 0.46, alpha: 1))
            fillDiscs(grow: 0.8, UIColor(red: 0.45, green: 0.38, blue: 0.27, alpha: 1))
            fillDiscs(grow: -2, UIColor(red: 0.28, green: 0.3, blue: 0.22, alpha: 1))
            fillDiscs(grow: -6, UIColor(red: 0.15, green: 0.2, blue: 0.18, alpha: 1))
        }
    }

    private static func paintRoads(_ map: WorldMap, in cg: CGContext) {
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        for (width, color) in [(1.9, UIColor(red: 0.38, green: 0.32, blue: 0.2, alpha: 0.35)),
                               (1.0, UIColor(red: 0.47, green: 0.37, blue: 0.24, alpha: 0.95)),
                               (0.45, UIColor(red: 0.53, green: 0.43, blue: 0.29, alpha: 0.6))] as [(CGFloat, UIColor)] {
            cg.setStrokeColor(color.cgColor)
            for trail in map.trails {
                cg.setLineWidth(CGFloat(trail.width) * width)
                let path = CGMutablePath()
                path.addLines(between: trail.points.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
                if trail.closed { path.closeSubpath() }
                cg.addPath(path)
                cg.strokePath()
            }
        }
    }

    /// Just the contact shadows, white on black, for the ink style to fill with hatching.
    static func paintShadowMask(_ map: WorldMap, size: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let pixels = CGFloat(size)
        return UIGraphicsImageRenderer(size: CGSize(width: pixels, height: pixels), format: format).image { context in
            let cg = context.cgContext
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
            let scale = pixels / CGFloat(2 * extent)
            cg.scaleBy(x: scale, y: scale)
            cg.translateBy(x: CGFloat(extent), y: CGFloat(extent))
            paintShadows(map, in: cg, color: UIColor(white: 1, alpha: 0.9))
        }
    }

    /// Dark soft pools under everything standing on the ground.
    private static func paintShadows(_ map: WorldMap, in cg: CGContext,
                                     color shadow: UIColor = UIColor(red: 0.06, green: 0.1, blue: 0.04, alpha: 0.5)) {
        for boulder in map.boulders {
            blot(cg, at: boulder.position, radius: boulder.radius * 1.5, color: shadow)
        }
        for plant in map.plants where plant.kind != .lilyPad && plant.kind != .clover {
            blot(cg, at: plant.position, radius: max(0.8, plant.collisionRadius * 3), color: shadow.withAlphaComponent(0.35))
        }
        cg.setLineCap(.round)
        cg.setStrokeColor(shadow.withAlphaComponent(0.3).cgColor)
        for twig in map.twigs {
            cg.setLineWidth(CGFloat(twig.radius * 5))
            cg.move(to: CGPoint(x: CGFloat(twig.from.x), y: CGFloat(twig.from.y)))
            cg.addLine(to: CGPoint(x: CGFloat(twig.to.x), y: CGFloat(twig.to.y)))
            cg.strokePath()
        }
        for root in map.roots {
            for (point, radius) in zip(root.points, root.radii) {
                blot(cg, at: point, radius: radius * 2.2, color: shadow.withAlphaComponent(0.4))
            }
        }
    }

    /// A soft round blotch fading out at the edge.
    private static func blot(_ cg: CGContext, at p: Vec2, radius: Float, color: UIColor) {
        let clear = color.withAlphaComponent(0)
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [color.cgColor, color.cgColor, clear.cgColor] as CFArray,
                                        locations: [0, 0.45, 1]) else { return }
        let center = CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
        cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: CGFloat(radius), options: [])
    }

    private static func smooth(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        a + (b - a) * t
    }
}
