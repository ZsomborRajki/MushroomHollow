import RealityKit
import UIKit

/// Short-lived visual effects: particle bursts and expanding shockwave rings.
/// Finished effects are disabled and pooled by kind rather than destroyed, since combat
/// fires several per second and building entities (and particle systems) isn't free.
@MainActor
final class EffectsPlayer {
    let root = Entity()
    private var transients: [Transient] = []
    private var idle: [Kind: [Entity]] = [:]
    private var ringMaterials: [UIColor: UnlitMaterial] = [:]
    private static let maxIdlePerKind = 32

    private enum Kind { case burst, ring, bolt, arrow, pillar }

    private struct Transient {
        let entity: Entity
        let kind: Kind
        let start: Double
        let duration: Double
        let update: ((Entity, Float) -> Void)?
    }

    /// A one-shot spray of glowing particles.
    func burst(
        at position: SIMD3<Float>,
        color: UIColor,
        count: Int,
        speed: Float = 1.5,
        size: Float = 0.06,
        lifetime: Float = 0.6,
        rise: Float = 0,
        spread: Float = 0.15,
        time: Double
    ) {
        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .sphere
        emitter.birthLocation = .surface
        emitter.birthDirection = .normal
        emitter.emitterShapeSize = SIMD3(repeating: spread)
        emitter.speed = speed
        emitter.speedVariation = speed * 0.4
        emitter.fieldSimulationSpace = .global
        emitter.mainEmitter.birthRate = 0
        emitter.mainEmitter.lifeSpan = Double(lifetime)
        emitter.mainEmitter.lifeSpanVariation = Double(lifetime) * 0.3
        emitter.mainEmitter.size = size
        emitter.mainEmitter.sizeVariation = size * 0.4
        emitter.mainEmitter.sizeMultiplierAtEndOfLifespan = 0.2
        emitter.mainEmitter.dampingFactor = 2.5
        emitter.mainEmitter.acceleration = [0, rise, 0]
        emitter.mainEmitter.opacityCurve = .quickFadeInOut
        emitter.mainEmitter.blendMode = .additive
        emitter.mainEmitter.isLightingEnabled = false
        emitter.mainEmitter.color = .constant(.single(color))
        emitter.burstCount = count
        emitter.isEmitting = false
        emitter.burst()

        let entity = reuse(.burst) { Entity() }
        entity.position = position
        entity.components.set(emitter)
        add(entity, kind: .burst, time: time, duration: Double(lifetime) * 1.5 + 0.2, update: nil)
    }

    /// A flat ring that expands to `radius` and fades out, `delay` seconds from now.
    func shockwave(at position: SIMD3<Float>, radius: Float, color: UIColor, duration: Double = 0.45, delay: Double = 0, time: Double) {
        let ring = reuse(.ring) {
            let ring = ModelEntity(mesh: Meshes.ring, materials: [])
            ring.components.set(DynamicLightShadowComponent(castsShadow: false))
            return ring
        }
        (ring as? ModelEntity)?.model?.materials = [ringMaterial(color)]
        ring.position = position + [0, 0.06, 0]
        ring.isEnabled = delay <= 0
        add(ring, kind: .ring, time: time + delay, duration: duration) { entity, t in
            let eased = 1 - (1 - t) * (1 - t)
            entity.scale = SIMD3(repeating: 0.2 + (radius - 0.2) * eased)
            entity.components.set(OpacityComponent(opacity: 1 - t))
        }
    }

    /// Flyff's level-up: a column of light that shoots up around the player, then thins and fades.
    func pillar(at position: SIMD3<Float>, color: UIColor, height: Float = 7, radius: Float = 0.8, duration: Double = 1.6, time: Double) {
        let pillar = reuse(.pillar) {
            let pillar = ModelEntity(mesh: Meshes.cylinder, materials: [])
            pillar.components.set(DynamicLightShadowComponent(castsShadow: false))
            return pillar
        }
        var material = UnlitMaterial(color: color)
        material.faceCulling = .none
        material.blending = .transparent(opacity: .init(floatLiteral: 0.5))
        (pillar as? ModelEntity)?.model?.materials = [material]
        add(pillar, kind: .pillar, time: time, duration: duration) { entity, t in
            let rise = min(1, t / 0.15)
            let thin = t < 0.5 ? 1 : 1 - (t - 0.5) / 0.5
            entity.scale = [radius * (0.4 + 0.6 * thin), height * rise, radius * (0.4 + 0.6 * thin)]
            entity.position = position + [0, height * rise / 2, 0]
            entity.components.set(OpacityComponent(opacity: t < 0.6 ? 1 : 1 - (t - 0.6) / 0.4))
        }
    }

    /// A glowing bolt flying from `from` to `to` (ranged attacks and spells).
    func projectile(from: SIMD3<Float>, to: SIMD3<Float>, color: UIColor, size: Float = 0.1, time: Double) {
        let bolt = reuse(.bolt) {
            let bolt = ModelEntity(mesh: Meshes.sphere, materials: [])
            bolt.components.set(DynamicLightShadowComponent(castsShadow: false))
            return bolt
        }
        (bolt as? ModelEntity)?.model?.materials = [Materials.glow(color)]
        bolt.scale = SIMD3(repeating: size)
        add(bolt, kind: .bolt, time: time, duration: 0.18) { entity, t in
            // A slight arc, like a thrown thorn.
            entity.position = from + (to - from) * t + [0, sin(t * .pi) * 0.4, 0]
        }
    }

    /// An arrow arcing from `from` to `to`, nose along its flight.
    func arrow(from: SIMD3<Float>, to: SIMD3<Float>, time: Double) {
        let arrow = reuse(.arrow) {
            let arrow = Entity()
            arrow.addRod(Materials.matte(Palette.stem), from: [0, 0, -0.4], to: .zero, radius: 0.012)
            arrow.addPart(Meshes.cone, Materials.glossy(Palette.shelfFungus), at: [0, 0, 0.03], scale: [0.025, 0.08, 0.025],
                          rotation: simd_quatf(from: [0, 1, 0], to: [0, 0, 1]))
            for side: Float in [-1, 1] {
                arrow.addPart(Meshes.teardrop, Materials.matte(Palette.leaf), at: [side * 0.022, 0, -0.36], scale: [0.022, 0.05, 0.005],
                              rotation: simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]))
            }
            arrow.components.set(DynamicLightShadowComponent(castsShadow: false))
            return arrow
        }
        let lift: Float = 0.25
        add(arrow, kind: .arrow, time: time, duration: 0.2) { entity, t in
            entity.position = from + (to - from) * t + [0, sin(t * .pi) * lift, 0]
            let velocity = (to - from) + [0, cos(t * .pi) * .pi * lift, 0]
            entity.orientation = simd_quatf(from: [0, 0, 1], to: simd_normalize(velocity))
        }
    }

    func update(time: Double) {
        transients.removeAll { transient in
            let t = Float((time - transient.start) / transient.duration)
            if t >= 1 {
                recycle(transient.entity, kind: transient.kind)
                return true
            }
            // Delayed effects wait hidden.
            if transient.entity.isEnabled != (t >= 0) { transient.entity.isEnabled = t >= 0 }
            transient.update?(transient.entity, max(0, t))
            return false
        }
    }

    private func add(_ entity: Entity, kind: Kind, time: Double, duration: Double, update: ((Entity, Float) -> Void)?) {
        update?(entity, 0)
        transients.append(Transient(entity: entity, kind: kind, start: time, duration: duration, update: update))
    }

    /// A finished effect of this kind (re-enabled), or a new one added to the scene.
    private func reuse(_ kind: Kind, orMake make: () -> Entity) -> Entity {
        if let entity = idle[kind]?.popLast() {
            entity.isEnabled = true
            return entity
        }
        let entity = make()
        root.addChild(entity)
        return entity
    }

    private func recycle(_ entity: Entity, kind: Kind) {
        guard idle[kind, default: []].count < Self.maxIdlePerKind else {
            entity.removeFromParent()
            return
        }
        entity.isEnabled = false
        // Each burst sets a fresh emitter; don't keep the spent one simulating.
        if kind == .burst { entity.components.remove(ParticleEmitterComponent.self) }
        idle[kind, default: []].append(entity)
    }

    private func ringMaterial(_ color: UIColor) -> UnlitMaterial {
        if let cached = ringMaterials[color] { return cached }
        var material = UnlitMaterial(color: color)
        material.faceCulling = .none
        material.blending = .transparent(opacity: .init(floatLiteral: 0.9))
        ringMaterials[color] = material
        return material
    }
}
