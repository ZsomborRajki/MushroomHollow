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

    /// A cast shadow drawn the cartoon way: a pale wash, a scribbled rim, and diagonal hatching,
    /// denser toward the middle. Transparent everywhere else.
    static func blobShadow() -> TextureResource? {
        let size = CGSize(width: 256, height: 256)
        var random = InkRandom(seed: 0xB10B)
        let ink = UIColor(red: 0.1, green: 0.1, blue: 0.16, alpha: 1)
        let image = render(size) { cg in
            let center = CGPoint(x: 128, y: 128)
            let radius: CGFloat = 104
            let blob = CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius * 0.92,
                                                width: 2 * radius, height: 2 * radius * 0.92), transform: nil)
            cg.addPath(blob)
            cg.setFillColor(ink.withAlphaComponent(0.34).cgColor)
            cg.fillPath()

            // Hatching, clipped to a slightly smaller blob so the strokes stop short of the rim.
            cg.saveGState()
            cg.addEllipse(in: CGRect(x: center.x - radius * 0.86, y: center.y - radius * 0.8,
                                     width: 2 * radius * 0.86, height: 2 * radius * 0.8))
            cg.clip()
            cg.setLineCap(.round)
            var offset: CGFloat = -260
            while offset < 260 {
                let from = CGPoint(x: center.x + offset - 140 + random.jitter(6), y: center.y + 140 + random.jitter(6))
                let to = CGPoint(x: center.x + offset + 140 + random.jitter(6), y: center.y - 140 + random.jitter(6))
                stroke(cg, from: from, to: to, width: 3.5 + random.jitter(1.5), color: ink.withAlphaComponent(0.55), random: &random)
                offset += 15 + random.jitter(3)
            }
            cg.restoreGState()

            // A scribbled rim: two loose, overlapping passes around the edge.
            for pass in 0..<2 {
                let path = CGMutablePath()
                let steps = 48
                let start = random.unit() * 2 * .pi
                for i in 0...steps + 4 {
                    let a = start + CGFloat(i) / CGFloat(steps) * 2 * .pi
                    let r = radius * (0.97 + 0.04 * CGFloat(pass)) + random.jitter(2.5)
                    let point = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r * 0.92)
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                cg.addPath(path)
                cg.setLineWidth(3 + CGFloat(pass))
                cg.setLineJoin(.round)
                cg.setStrokeColor(ink.withAlphaComponent(0.45).cgColor)
                cg.strokePath()
            }
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource(image: cgImage, options: .init(semantic: .color))
    }

    /// A stroke that bows slightly and swells in the middle, like a pen line.
    private static func stroke(_ cg: CGContext, from: CGPoint, to: CGPoint, width: CGFloat, color: UIColor, random: inout InkRandom) {
        let mid = CGPoint(x: (from.x + to.x) / 2 + random.jitter(4), y: (from.y + to.y) / 2 + random.jitter(4))
        cg.setStrokeColor(color.cgColor)
        for (w, a, b) in [(width * 0.6, from, mid), (width, mid, to)] {
            cg.setLineWidth(w)
            cg.move(to: a)
            cg.addQuadCurve(to: b, control: CGPoint(x: (a.x + b.x) / 2 + random.jitter(3), y: (a.y + b.y) / 2 + random.jitter(3)))
            cg.strokePath()
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
