import CoreGraphics
import RealityKit
import UIKit

/// Sprout's colors. Client-only looks; nothing here touches the simulation.
enum SproutLook {
    static let skin = UIColor(red: 1.0, green: 0.87, blue: 0.78, alpha: 1)
    static let blush = UIColor(red: 1.0, green: 0.52, blue: 0.52, alpha: 1)
    static let hair = UIColor(red: 0.6, green: 0.36, blue: 0.22, alpha: 1)
    static let brow = UIColor(red: 0.42, green: 0.24, blue: 0.15, alpha: 1)
    static let irisDark = UIColor(red: 0.03, green: 0.24, blue: 0.22, alpha: 1)
    static let irisLight = UIColor(red: 0.3, green: 0.82, blue: 0.58, alpha: 1)
    static let irisGlow = UIColor(red: 0.7, green: 1.0, blue: 0.78, alpha: 1)
    static let pupil = UIColor(red: 0.02, green: 0.09, blue: 0.09, alpha: 1)
    static let lash = UIColor(red: 0.18, green: 0.09, blue: 0.07, alpha: 1)
    static let mouth = UIColor(red: 0.55, green: 0.17, blue: 0.15, alpha: 1)
    static let tongue = UIColor(red: 1.0, green: 0.56, blue: 0.56, alpha: 1)
    static let tunic = Palette.tunic
    static let trim = UIColor(red: 0.98, green: 0.94, blue: 0.84, alpha: 1)
    static let scarf = UIColor(red: 0.98, green: 0.74, blue: 0.22, alpha: 1)
    static let boots = Palette.boots
    static let bootCuff = UIColor(red: 0.58, green: 0.4, blue: 0.26, alpha: 1)
    static let belt = Palette.door
    static let gold = UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1)
    static let sproutLeaf = UIColor(red: 0.5, green: 0.82, blue: 0.3, alpha: 1)
}

/// Paints Sprout's anime face into an equirectangular texture for `Meshes.uvSphere`:
/// longitude 0 (the middle of the image) faces +Z, the top row is the crown.
@MainActor
enum FacePainter {
    enum Expression: CaseIterable {
        case open, blink, happy, hurt, fainted
    }

    static let materials: [Expression: any RealityKit.Material] =
        Dictionary(uniqueKeysWithValues: Expression.allCases.map { ($0, makeMaterial($0)) })

    private static let size = CGSize(width: 1024, height: 512)
    /// Texture pixels per radian of longitude or latitude.
    private static let k = size.width / (2 * .pi)

    private static func makeMaterial(_ expression: Expression) -> any RealityKit.Material {
        var material = PhysicallyBasedMaterial()
        material.roughness = 0.7
        material.metallic = .init(floatLiteral: 0)
        guard let painted = texture({ paint(expression, in: $0) }) else {
            material.baseColor = .init(tint: SproutLook.skin)
            return material
        }
        if ArtStyle.isInk, let ink = InkMaterials.textured(painted) { return ink }
        material.baseColor = .init(texture: .init(painted))
        return material
    }

    private static func texture(_ draw: (CGContext) -> Void) -> TextureResource? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        format.preferredRange = .standard // plain 8-bit sRGB
        let image = UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource(image: cgImage, options: .init(semantic: .color))
    }

    /// Texture point for a direction on the head, in radians.
    private static func point(_ longitude: CGFloat, _ latitude: CGFloat) -> CGPoint {
        CGPoint(x: size.width / 2 + longitude * k, y: size.height / 2 - latitude * k)
    }

    private static let eyeWidth = 0.38 * k
    private static let eyeHeight = 0.47 * k
    /// Eye centers; the one on the right of the image first. `outward` points to the outer corner.
    private static let eyes: [(center: CGPoint, outward: CGFloat)] = [
        (point(0.31, -0.1), 1), (point(-0.31, -0.1), -1),
    ]

    private static func paint(_ expression: Expression, in cg: CGContext) {
        // Hair everywhere except the face and neck; the hair meshes add the volume.
        SproutLook.hair.setFill()
        cg.fill(CGRect(origin: .zero, size: size))
        SproutLook.skin.setFill()
        let hairline = point(0, 0.45).y
        let face = CGRect(x: point(-1.25, 0).x, y: hairline, width: 2.5 * k, height: size.height - hairline)
        UIBezierPath(roundedRect: face, cornerRadius: 0.4 * k).fill()
        cg.fill(CGRect(x: 0, y: point(0, -0.85).y, width: size.width, height: size.height))

        for eye in eyes {
            // Soft blush under each eye.
            let blushCenter = point(0.44 * eye.outward, -0.3)
            cg.saveGState()
            cg.translateBy(x: blushCenter.x, y: blushCenter.y)
            cg.scaleBy(x: 1, y: 0.5)
            let blush = CGGradient(colorsSpace: nil, colors: [SproutLook.blush.withAlphaComponent(0.55).cgColor,
                                                              SproutLook.blush.withAlphaComponent(0).cgColor] as CFArray,
                                   locations: [0, 1])!
            cg.drawRadialGradient(blush, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 0.17 * k, options: [])
            cg.restoreGState()

            // Eyebrows (mostly under the bangs).
            let c = eye.center
            let w = eyeWidth, h = eyeHeight
            cg.setLineCap(.round)
            cg.setStrokeColor(SproutLook.brow.cgColor)
            cg.setLineWidth(3)
            cg.move(to: CGPoint(x: c.x - w * 0.3, y: c.y - h * 0.8 + eye.outward * h * 0.03))
            cg.addQuadCurve(to: CGPoint(x: c.x + w * 0.3, y: c.y - h * 0.8 - eye.outward * h * 0.03),
                            control: CGPoint(x: c.x, y: c.y - h * 0.93))
            cg.strokePath()

            switch expression {
            case .open: drawOpenEye(cg, center: c, outward: eye.outward)
            case .blink: drawArcEye(cg, center: c, outward: eye.outward, bulge: 0.2)
            case .happy: drawArcEye(cg, center: c, outward: eye.outward, bulge: -0.3)
            case .hurt: drawSquint(cg, center: c, outward: eye.outward)
            case .fainted: drawSwirl(cg, center: c)
            }
        }
        drawMouth(expression, in: cg)
    }

    private static func drawOpenEye(_ cg: CGContext, center c: CGPoint, outward: CGFloat) {
        let w = eyeWidth, h = eyeHeight
        let eye = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
        cg.saveGState()
        cg.addEllipse(in: eye)
        cg.clip()
        UIColor.white.setFill()
        cg.fill(eye)
        // A big iris, dark at the top and bright at the bottom.
        let iris = CGRect(x: c.x - w * 0.42, y: c.y - h * 0.42, width: w * 0.84, height: h * 0.98)
        cg.saveGState()
        cg.addEllipse(in: iris)
        cg.clip()
        let gradient = CGGradient(colorsSpace: nil, colors: [SproutLook.irisDark.cgColor, SproutLook.irisLight.cgColor] as CFArray,
                                  locations: [0.2, 1])!
        cg.drawLinearGradient(gradient, start: CGPoint(x: c.x, y: iris.minY), end: CGPoint(x: c.x, y: iris.maxY), options: [])
        SproutLook.pupil.setFill()
        cg.fillEllipse(in: CGRect(x: c.x - w * 0.17, y: c.y - h * 0.22, width: w * 0.34, height: h * 0.46))
        SproutLook.irisGlow.withAlphaComponent(0.75).setFill()
        cg.fillEllipse(in: CGRect(x: c.x - w * 0.24, y: c.y + h * 0.26, width: w * 0.48, height: h * 0.2))
        cg.restoreGState()
        SproutLook.irisDark.setStroke()
        cg.setLineWidth(w * 0.035)
        cg.strokeEllipse(in: iris)
        cg.restoreGState()

        // Catchlights, from the same side in both eyes.
        UIColor.white.setFill()
        cg.fillEllipse(in: CGRect(x: c.x - w * 0.3, y: c.y - h * 0.3, width: w * 0.3, height: h * 0.27))
        cg.fillEllipse(in: CGRect(x: c.x + w * 0.1, y: c.y + h * 0.12, width: w * 0.13, height: w * 0.13))

        // Upper lash line, heavier toward the outer corner, with a little flick.
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        cg.setStrokeColor(SproutLook.lash.cgColor)
        strokeEllipseArc(cg, center: c, from: 1.04 * .pi, to: 1.96 * .pi, width: h * 0.08)
        let outer: (CGFloat, CGFloat) = outward > 0 ? (1.5 * .pi, 1.98 * .pi) : (1.02 * .pi, 1.5 * .pi)
        strokeEllipseArc(cg, center: c, from: outer.0, to: outer.1, width: h * 0.14)
        let corner = CGPoint(x: c.x + outward * w * 0.49, y: c.y - h * 0.06)
        cg.move(to: corner)
        cg.addLine(to: CGPoint(x: corner.x + outward * w * 0.14, y: corner.y - h * 0.1))
        cg.setLineWidth(h * 0.07)
        cg.strokePath()
        // A hint of lower lash at the outer corner.
        let lower: (CGFloat, CGFloat) = outward > 0 ? (0.12 * .pi, 0.32 * .pi) : (0.68 * .pi, 0.88 * .pi)
        strokeEllipseArc(cg, center: c, from: lower.0, to: lower.1, width: h * 0.035)
    }

    /// A closed eye: `bulge` > 0 curves down (resting), < 0 curves up (happy ^^).
    private static func drawArcEye(_ cg: CGContext, center c: CGPoint, outward: CGFloat, bulge: CGFloat) {
        let w = eyeWidth, h = eyeHeight
        let y = c.y + h * 0.12
        cg.setLineCap(.round)
        cg.setStrokeColor(SproutLook.lash.cgColor)
        cg.setLineWidth(h * 0.09)
        cg.move(to: CGPoint(x: c.x - w * 0.45, y: y))
        cg.addQuadCurve(to: CGPoint(x: c.x + w * 0.45, y: y), control: CGPoint(x: c.x, y: y + h * bulge * 2))
        cg.strokePath()
        let corner = CGPoint(x: c.x + outward * w * 0.45, y: y)
        cg.move(to: corner)
        cg.addLine(to: CGPoint(x: corner.x + outward * w * 0.12, y: corner.y - h * 0.06))
        cg.setLineWidth(h * 0.06)
        cg.strokePath()
    }

    /// Squeezed shut: > <
    private static func drawSquint(_ cg: CGContext, center c: CGPoint, outward: CGFloat) {
        let w = eyeWidth, h = eyeHeight
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        cg.setStrokeColor(SproutLook.lash.cgColor)
        cg.setLineWidth(h * 0.09)
        cg.move(to: CGPoint(x: c.x + outward * w * 0.32, y: c.y - h * 0.18))
        cg.addLine(to: CGPoint(x: c.x - outward * w * 0.3, y: c.y + h * 0.04))
        cg.addLine(to: CGPoint(x: c.x + outward * w * 0.32, y: c.y + h * 0.26))
        cg.strokePath()
    }

    /// Dizzy spiral eyes for fainting.
    private static func drawSwirl(_ cg: CGContext, center c: CGPoint) {
        let r = eyeWidth * 0.42
        cg.setLineCap(.round)
        cg.setStrokeColor(SproutLook.lash.cgColor)
        cg.setLineWidth(eyeHeight * 0.06)
        for i in 0...60 {
            let s = CGFloat(i) / 60
            let a = s * 2.6 * 2 * .pi
            let p = CGPoint(x: c.x + cos(a) * r * s, y: c.y + eyeHeight * 0.05 + sin(a) * r * s * 1.1)
            if i == 0 { cg.move(to: p) } else { cg.addLine(to: p) }
        }
        cg.strokePath()
    }

    private static func drawMouth(_ expression: Expression, in cg: CGContext) {
        let m = point(0, -0.38)
        let w = 0.13 * k
        cg.setLineCap(.round)
        cg.setStrokeColor(SproutLook.mouth.cgColor)
        cg.setLineWidth(2.5)
        switch expression {
        case .open, .blink:
            cg.move(to: CGPoint(x: m.x - w / 2, y: m.y))
            cg.addQuadCurve(to: CGPoint(x: m.x + w / 2, y: m.y), control: CGPoint(x: m.x, y: m.y + w * 0.4))
            cg.strokePath()
        case .happy:
            // Wide open "D" smile with a tongue.
            let mouth = UIBezierPath()
            mouth.move(to: CGPoint(x: m.x - w * 0.6, y: m.y - w * 0.1))
            mouth.addLine(to: CGPoint(x: m.x + w * 0.6, y: m.y - w * 0.1))
            mouth.addQuadCurve(to: CGPoint(x: m.x - w * 0.6, y: m.y - w * 0.1), controlPoint: CGPoint(x: m.x, y: m.y + w * 0.95))
            mouth.close()
            SproutLook.mouth.setFill()
            mouth.fill()
            cg.saveGState()
            mouth.addClip()
            SproutLook.tongue.setFill()
            cg.fillEllipse(in: CGRect(x: m.x - w * 0.3, y: m.y + w * 0.12, width: w * 0.6, height: w * 0.4))
            cg.restoreGState()
        case .hurt:
            // A wobbly grimace.
            for i in 0...12 {
                let s = CGFloat(i) / 12
                let p = CGPoint(x: m.x - w * 0.55 + s * w * 1.1, y: m.y + sin(s * 3 * .pi) * w * 0.12)
                if i == 0 { cg.move(to: p) } else { cg.addLine(to: p) }
            }
            cg.strokePath()
        case .fainted:
            SproutLook.mouth.setFill()
            cg.fillEllipse(in: CGRect(x: m.x - w * 0.18, y: m.y - w * 0.05, width: w * 0.36, height: w * 0.3))
        }
    }

    private static func strokeEllipseArc(_ cg: CGContext, center c: CGPoint, from start: CGFloat, to end: CGFloat, width: CGFloat) {
        for i in 0...24 {
            let a = start + (end - start) * CGFloat(i) / 24
            let p = CGPoint(x: c.x + cos(a) * eyeWidth / 2, y: c.y + sin(a) * eyeHeight / 2)
            if i == 0 { cg.move(to: p) } else { cg.addLine(to: p) }
        }
        cg.setLineWidth(width)
        cg.strokePath()
    }
}
