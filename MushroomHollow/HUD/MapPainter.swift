import GameCore
import simd
import UIKit

/// The map screen's background: the painted forest floor with hill shading, water, the great
/// tree and its roots, and a dot for every big plant and rock, like an illustrated field map.
/// Same image space as `GroundPainter` (north up, ±`GroundPainter.extent` meters).
@MainActor
enum MapPainter {
    static func paint(_ map: WorldMap, ground: UIImage, size: Int = 1400) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let pixels = CGFloat(size)
        let extent = CGFloat(GroundPainter.extent)
        let shading = hillShade(map, resolution: 256)
        return UIGraphicsImageRenderer(size: CGSize(width: pixels, height: pixels), format: format).image { context in
            let cg = context.cgContext
            ground.draw(in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
            if let shading {
                cg.saveGState()
                cg.interpolationQuality = .high
                // UIImage.draw ignores the context's blend mode; pass it explicitly.
                shading.draw(in: CGRect(x: 0, y: 0, width: pixels, height: pixels), blendMode: .multiply, alpha: 1)
                cg.restoreGState()
            }

            cg.scaleBy(x: pixels / (2 * extent), y: pixels / (2 * extent))
            cg.translateBy(x: extent, y: extent)
            func circle(_ p: Vec2, _ r: Float, _ color: UIColor) {
                color.setFill()
                let r = CGFloat(r)
                cg.fillEllipse(in: CGRect(x: CGFloat(p.x) - r, y: CGFloat(p.y) - r, width: 2 * r, height: 2 * r))
            }

            // Water.
            for lake in map.terrain.lakes {
                for disc in lake.discs { circle(disc.center, disc.radius, UIColor(red: 0.32, green: 0.55, blue: 0.62, alpha: 1)) }
                for disc in lake.discs where disc.radius > 5 {
                    circle(disc.center, disc.radius - 5, UIColor(red: 0.22, green: 0.44, blue: 0.56, alpha: 1))
                }
            }
            // Cliffs: a hatched rim round each mesa and basin, with a gap at each ramp.
            cg.setLineCap(.round)
            for plateau in map.terrain.plateaus {
                cg.setStrokeColor(UIColor(red: 0.3, green: 0.26, blue: 0.22, alpha: 0.95).cgColor)
                cg.setLineWidth(1.6)
                let count = 90
                var drawing = false
                for i in 0...count {
                    let yaw = Float(i) / Float(count) * 2 * .pi
                    let p = plateau.center + AngleMath.direction(forYaw: yaw) * (plateau.rimRadius(atYaw: yaw) + plateau.cliffWidth * 0.3)
                    let point = CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
                    if plateau.rampWeight(at: p) > 0.4 {
                        if drawing { cg.strokePath() }
                        drawing = false
                    } else if drawing {
                        cg.addLine(to: point)
                    } else {
                        cg.move(to: point)
                        drawing = true
                    }
                }
                if drawing { cg.strokePath() }
            }

            // Scenery as little marks.
            for boulder in map.boulders { circle(boulder.position, max(1.2, boulder.radius), UIColor(white: 0.55, alpha: 0.9)) }
            for plant in map.plants {
                let color: UIColor = switch plant.kind {
                case .daisy, .dandelionClock: UIColor(white: 0.95, alpha: 1)
                case .tulip, .poppy: UIColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1)
                case .bluebell, .foxglove: UIColor(red: 0.6, green: 0.45, blue: 0.9, alpha: 1)
                case .dandelion, .buttercup: UIColor(red: 1, green: 0.82, blue: 0.2, alpha: 1)
                case .toadstool: UIColor(red: 0.8, green: 0.25, blue: 0.2, alpha: 1)
                case .glowcap: UIColor(red: 0.5, green: 0.95, blue: 0.85, alpha: 1)
                case .lilyPad: UIColor(red: 0.3, green: 0.55, blue: 0.25, alpha: 1)
                case .fern, .bush, .bramble, .sapling, .clover, .cattail: UIColor(red: 0.16, green: 0.34, blue: 0.14, alpha: 0.9)
                }
                circle(plant.position, plant.kind == .bush || plant.kind == .bramble ? 2 : 1.1, color)
            }
            cg.setLineCap(.round)
            cg.setStrokeColor(UIColor(red: 0.35, green: 0.26, blue: 0.17, alpha: 1).cgColor)
            for twig in map.twigs {
                cg.setLineWidth(1.2)
                cg.move(to: CGPoint(x: CGFloat(twig.from.x), y: CGFloat(twig.from.y)))
                cg.addLine(to: CGPoint(x: CGFloat(twig.to.x), y: CGFloat(twig.to.y)))
                cg.strokePath()
            }

            // The great tree, its roots, and the village.
            let bark = UIColor(red: 0.36, green: 0.25, blue: 0.16, alpha: 1)
            cg.setStrokeColor(bark.cgColor)
            for root in map.roots {
                for i in 0..<(root.points.count - 1) {
                    cg.setLineWidth(CGFloat(root.radii[i] + root.radii[i + 1]))
                    cg.move(to: CGPoint(x: CGFloat(root.points[i].x), y: CGFloat(root.points[i].y)))
                    cg.addLine(to: CGPoint(x: CGFloat(root.points[i + 1].x), y: CGFloat(root.points[i + 1].y)))
                    cg.strokePath()
                }
            }
            circle(.zero, map.trunkRadius + 2, UIColor(red: 0.28, green: 0.19, blue: 0.12, alpha: 1))
            circle(.zero, map.trunkRadius - 1, UIColor(red: 0.42, green: 0.3, blue: 0.19, alpha: 1))
            for ring in stride(from: Float(3), to: map.trunkRadius - 2, by: 3) {
                cg.setStrokeColor(UIColor(red: 0.34, green: 0.23, blue: 0.14, alpha: 1).cgColor)
                cg.setLineWidth(0.6)
                cg.strokeEllipse(in: CGRect(x: CGFloat(-ring), y: CGFloat(-ring), width: CGFloat(2 * ring), height: CGFloat(2 * ring)))
            }
            for house in map.houses {
                circle(house.position, house.capRadius, UIColor(red: 0.8, green: 0.22, blue: 0.17, alpha: 1))
                circle(house.position, house.capRadius * 0.3, UIColor(white: 0.97, alpha: 1))
            }

            // Beyond the rim: parchment.
            let edge = CGFloat(map.boundaryRadius)
            let outside = CGMutablePath()
            outside.addRect(CGRect(x: -extent, y: -extent, width: 2 * extent, height: 2 * extent))
            outside.addEllipse(in: CGRect(x: -edge, y: -edge, width: 2 * edge, height: 2 * edge))
            cg.addPath(outside)
            UIColor(red: 0.2, green: 0.17, blue: 0.12, alpha: 0.82).setFill()
            cg.fillPath(using: .evenOdd)
            cg.setStrokeColor(UIColor(red: 0.75, green: 0.65, blue: 0.45, alpha: 1).cgColor)
            cg.setLineWidth(1.6)
            cg.strokeEllipse(in: CGRect(x: -edge, y: -edge, width: 2 * edge, height: 2 * edge))
        }
    }

    /// Grey light-from-the-northwest shading of the terrain, to multiply over the colors.
    private static func hillShade(_ map: WorldMap, resolution n: Int) -> UIImage? {
        let extent = GroundPainter.extent
        let light = simd_normalize(SIMD3<Float>(-0.6, 0.9, -0.6))
        var bytes = [UInt8](repeating: 255, count: n * n * 4)
        let step = 2 * extent / Float(n)
        for row in 0..<n {
            for column in 0..<n {
                let p = Vec2(-extent + (Float(column) + 0.5) * step, -extent + (Float(row) + 0.5) * step)
                // Exaggerate the relief so gentle hills still read on a flat map.
                var normal = map.terrain.normal(at: p, step: step)
                normal = simd_normalize(SIMD3(normal.x * 3, normal.y, normal.z * 3))
                let shade = 0.62 + 0.38 * max(0, simd_dot(normal, light)) / light.y
                let v = UInt8(max(0, min(255, shade * 255)))
                let i = (row * n + column) * 4
                bytes[i] = v
                bytes[i + 1] = v
                bytes[i + 2] = v
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: image)
    }
}
