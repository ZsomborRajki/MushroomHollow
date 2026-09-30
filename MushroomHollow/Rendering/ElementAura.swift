import GameCore
import RealityKit
import UIKit

/// The element showing on an infused weapon from +3 (`ElementForge.visibleLevel`): fire licks up the
/// blade, water drips off it, wind curls around it, earth sheds grit, electricity crackles. Every level
/// past +3 adds more and bigger particles, up to a roaring +10. Particles live in world space, so a
/// swing leaves a wake. In the ink style each element has its own drawn sprite (a flame, a drop, a
/// curl, a pebble, a spark: white fill in a marker outline, tinted per particle) instead of a soft glow.
@MainActor
enum ElementAura {
    static let name = "elementAura"

    /// Builds the aura for `upgrade` and hangs it on `held` (a weapon of family `weapon`); nil when
    /// the element is too weak to show.
    @discardableResult
    static func attach(_ upgrade: ElementUpgrade, to held: WeaponModels.Held, weapon: WeaponType) -> Entity? {
        let strength = ElementForge.effectStrength(level: upgrade.level)
        guard strength > 0 else { return nil }
        let aura = Entity()
        aura.name = name
        var emitter = emitter(upgrade.element, strength: strength)
        switch weapon {
        case .sword, .axe, .maul:
            // Along the business end of the blade (or haft and head).
            let reach = held.trail?.reach ?? 0.5
            let length = max(0.2, reach - 0.12)
            aura.position = WeaponModels.bladeDirection * (reach - length / 2)
            aura.orientation = simd_quatf(from: [0, 1, 0], to: WeaponModels.bladeDirection)
            emitter.emitterShape = .box
            emitter.emitterShapeSize = [0.035, length, 0.035]
            held.entity.addChild(aura)
        case .bow:
            // Up and down both limbs.
            emitter.emitterShape = .box
            emitter.emitterShapeSize = [0.03, 0.72, 0.08]
            aura.position = [0, 0, 0.02]
            held.entity.addChild(aura)
        case .wand, .staff:
            // Around the orb or droplet at the tip.
            emitter.emitterShape = .sphere
            emitter.emitterShapeSize = SIMD3(repeating: 0.05 + 0.03 * strength)
            (held.muzzle ?? held.entity).addChild(aura)
        }
        aura.components.set(emitter)
        return aura
    }

    private static func emitter(_ element: Element, strength s: Float) -> ParticleEmitterComponent {
        var emitter = ParticleEmitterComponent()
        emitter.birthLocation = .volume
        emitter.fieldSimulationSpace = .global
        emitter.speed = 0.04
        emitter.speedVariation = 0.03
        emitter.mainEmitter.isLightingEnabled = false
        emitter.mainEmitter.opacityCurve = .gradualFadeInOut
        emitter.mainEmitter.blendMode = .additive

        let tint = element.tint
        switch element {
        case .fire:
            emitter.mainEmitter.birthRate = 18 + 100 * s
            emitter.mainEmitter.lifeSpan = Double(0.3 + 0.25 * s)
            emitter.mainEmitter.lifeSpanVariation = 0.1
            emitter.mainEmitter.size = 0.03 + 0.035 * s
            emitter.mainEmitter.sizeVariation = 0.01
            emitter.mainEmitter.sizeMultiplierAtEndOfLifespan = 0.25
            emitter.mainEmitter.acceleration = [0, 0.8 + 1.2 * s, 0]
            emitter.mainEmitter.noiseStrength = 0.1 + 0.2 * s
            emitter.mainEmitter.opacityCurve = .quickFadeInOut
            emitter.mainEmitter.color = .evolving(
                start: .single(UIColor(red: 1, green: 0.88, blue: 0.35, alpha: 1)),
                end: .single(tint))
        case .water:
            emitter.mainEmitter.birthRate = 5 + 32 * s
            emitter.mainEmitter.lifeSpan = 0.75
            emitter.mainEmitter.lifeSpanVariation = 0.2
            emitter.mainEmitter.size = 0.022 + 0.022 * s
            emitter.mainEmitter.sizeVariation = 0.008
            emitter.mainEmitter.sizeMultiplierAtEndOfLifespan = 0.8
            emitter.mainEmitter.acceleration = [0, -4.5, 0]
            emitter.mainEmitter.opacityCurve = .linearFadeOut
            emitter.mainEmitter.color = .constant(.random(a: tint, b: UIColor(red: 0.65, green: 0.88, blue: 1, alpha: 1)))
        case .wind:
            emitter.speed = 0.12 + 0.15 * s
            emitter.birthDirection = .normal
            emitter.mainEmitter.birthRate = 8 + 36 * s
            emitter.mainEmitter.lifeSpan = Double(0.6 + 0.3 * s)
            emitter.mainEmitter.size = 0.025 + 0.025 * s
            emitter.mainEmitter.sizeVariation = 0.01
            emitter.mainEmitter.sizeMultiplierAtEndOfLifespan = 1.4
            emitter.mainEmitter.acceleration = [0, 0.35, 0]
            emitter.mainEmitter.noiseStrength = 0.4 + 0.6 * s
            emitter.mainEmitter.noiseScale = 2
            emitter.mainEmitter.noiseAnimationSpeed = 1
            emitter.mainEmitter.angularSpeed = 4
            emitter.mainEmitter.angularSpeedVariation = 2
            emitter.mainEmitter.color = .constant(.random(a: tint, b: UIColor(red: 0.88, green: 1, blue: 0.95, alpha: 1)))
        case .earth:
            emitter.mainEmitter.birthRate = 5 + 28 * s
            emitter.mainEmitter.lifeSpan = 0.9
            emitter.mainEmitter.lifeSpanVariation = 0.25
            emitter.mainEmitter.size = 0.02 + 0.028 * s
            emitter.mainEmitter.sizeVariation = 0.01
            emitter.mainEmitter.acceleration = [0, -2.2, 0]
            emitter.mainEmitter.dampingFactor = 0.6
            emitter.mainEmitter.angularSpeed = 3
            emitter.mainEmitter.angularSpeedVariation = 3
            emitter.mainEmitter.opacityCurve = .linearFadeOut
            emitter.mainEmitter.color = .constant(.random(a: tint, b: UIColor(red: 0.9, green: 0.76, blue: 0.42, alpha: 1)))
        case .electric:
            emitter.speed = 0.3 + 0.4 * s
            emitter.speedVariation = 0.3
            emitter.birthDirection = .normal
            emitter.mainEmitter.birthRate = 24 + 170 * s
            emitter.mainEmitter.lifeSpan = Double(0.12 + 0.12 * s)
            emitter.mainEmitter.lifeSpanVariation = 0.04
            emitter.mainEmitter.size = 0.018 + 0.03 * s
            emitter.mainEmitter.sizeVariation = 0.01
            emitter.mainEmitter.dampingFactor = 4
            emitter.mainEmitter.angularSpeedVariation = 20
            emitter.mainEmitter.opacityCurve = .quickFadeInOut
            emitter.mainEmitter.color = .constant(.random(a: tint, b: UIColor(red: 0.85, green: 0.97, blue: 1, alpha: 1)))
        }

        if ArtStyle.isInk, let sprite = sprite(element) {
            // Drawn sprites, fewer and a touch bigger: additive glows wash out over the ink style's pale colors.
            emitter.mainEmitter.image = sprite
            emitter.mainEmitter.blendMode = .alpha
            emitter.mainEmitter.birthRate *= 0.6
            emitter.mainEmitter.size *= 1.4
        }
        return emitter
    }

    // MARK: - Ink sprites

    private static var sprites: [Element: TextureResource] = [:]

    /// A white shape in a wobbly-free marker outline; the particle color tints the fill.
    private static func sprite(_ element: Element) -> TextureResource? {
        if let cached = sprites[element] { return cached }
        let size = CGSize(width: 64, height: 64)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let ink = UIColor(red: 0.1, green: 0.08, blue: 0.06, alpha: 0.95)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let path = UIBezierPath()
            var strokeOnly = false
            switch element {
            case .fire:
                // A flame licking upward (UIKit's y runs down).
                path.move(to: CGPoint(x: 32, y: 6))
                path.addCurve(to: CGPoint(x: 50, y: 42), controlPoint1: CGPoint(x: 38, y: 18), controlPoint2: CGPoint(x: 52, y: 26))
                path.addCurve(to: CGPoint(x: 14, y: 42), controlPoint1: CGPoint(x: 48, y: 62), controlPoint2: CGPoint(x: 16, y: 62))
                path.addCurve(to: CGPoint(x: 32, y: 6), controlPoint1: CGPoint(x: 12, y: 28), controlPoint2: CGPoint(x: 26, y: 20))
            case .water:
                // A falling drop, point up.
                path.move(to: CGPoint(x: 32, y: 6))
                path.addCurve(to: CGPoint(x: 48, y: 40), controlPoint1: CGPoint(x: 36, y: 16), controlPoint2: CGPoint(x: 48, y: 26))
                path.addArc(withCenter: CGPoint(x: 32, y: 40), radius: 16, startAngle: 0, endAngle: .pi, clockwise: true)
                path.addCurve(to: CGPoint(x: 32, y: 6), controlPoint1: CGPoint(x: 16, y: 26), controlPoint2: CGPoint(x: 28, y: 16))
            case .wind:
                // A curl of breeze.
                strokeOnly = true
                path.move(to: CGPoint(x: 8, y: 40))
                path.addCurve(to: CGPoint(x: 46, y: 36), controlPoint1: CGPoint(x: 20, y: 50), controlPoint2: CGPoint(x: 40, y: 50))
                path.addCurve(to: CGPoint(x: 34, y: 20), controlPoint1: CGPoint(x: 52, y: 22), controlPoint2: CGPoint(x: 40, y: 14))
                path.addCurve(to: CGPoint(x: 36, y: 32), controlPoint1: CGPoint(x: 28, y: 24), controlPoint2: CGPoint(x: 30, y: 32))
            case .earth:
                // A chipped pebble.
                let corners: [CGPoint] = [[18, 14], [40, 10], [54, 26], [50, 48], [28, 54], [12, 40]].map { CGPoint(x: $0[0], y: $0[1]) }
                path.move(to: corners[0])
                for corner in corners.dropFirst() { path.addLine(to: corner) }
                path.close()
            case .electric:
                // A zigzag bolt.
                let points: [CGPoint] = [[38, 4], [16, 36], [30, 36], [24, 60], [48, 26], [34, 26]].map { CGPoint(x: $0[0], y: $0[1]) }
                path.move(to: points[0])
                for point in points.dropFirst() { path.addLine(to: point) }
                path.close()
            }
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            if strokeOnly {
                // Thick white stroke inside a thicker ink one, so it tints like the filled shapes.
                cg.setStrokeColor(ink.cgColor)
                path.lineWidth = 13
                path.stroke()
                cg.setStrokeColor(UIColor.white.cgColor)
                path.lineWidth = 6
                path.stroke()
            } else {
                cg.setFillColor(UIColor.white.cgColor)
                path.fill()
                cg.setStrokeColor(ink.cgColor)
                path.lineWidth = 5
                path.stroke()
            }
        }
        guard let cgImage = image.cgImage,
              let texture = try? TextureResource(image: cgImage, options: .init(semantic: .color)) else { return nil }
        sprites[element] = texture
        return texture
    }
}
