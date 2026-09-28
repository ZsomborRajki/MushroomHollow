import GameCore
import RealityKit
import UIKit

/// Day/night: sun and moon, sky colors, lantern glow, fireflies, and the color grade.
/// Everything is driven by the simulation's `timeOfDay`, so online players share one sky.
@MainActor
final class Atmosphere {
    let root = Entity()
    let grade = GradeSettings()

    private let sun = DirectionalLight()
    private let lantern = PointLight()
    private let fireflies = Entity()
    private weak var sky: ModelEntity?
    private var lastApplied: Float = -1
    private var fireflyRate: Float = -1

    /// 0 at noon, 1 at midnight, smooth in between.
    private(set) var nightFactor: Float = 0

    init(map: WorldMap, sky: ModelEntity) {
        self.sky = sky

        var shadow = DirectionalLightComponent.Shadow(shadowProjection: .automatic(maximumDistance: 45), depthBias: 1.5)
        shadow.cascades = .automatic
        sun.shadow = shadow
        root.addChild(sun)

        lantern.light.color = Palette.windowGlow
        lantern.light.attenuationRadius = 20
        lantern.position = [map.villageCenter.x, 4, map.villageCenter.y]
        root.addChild(lantern)

        root.addChild(fireflies)
    }

    /// Call every frame; does real work only when the time has moved noticeably.
    func update(timeOfDay: Float, focus: SIMD3<Float>) {
        fireflies.position = [focus.x, focus.y - 1.3, focus.z]
        guard abs(timeOfDay - lastApplied) > 0.0005 else { return }
        lastApplied = timeOfDay

        // Sun angle: 0 at dawn (0.25), up at noon, down at dusk (0.75).
        let angle = (timeOfDay - 0.25) * 2 * .pi
        let elevation = sin(angle)
        let daylight = smoothstep(-0.05, 0.25, elevation)
        let dusk = max(0, 1 - abs(elevation) / 0.3) // near the horizon, either side
        nightFactor = 1 - smoothstep(-0.2, 0.05, elevation)

        // One directional light plays the sun by day and the moon by night.
        if elevation > -0.02 {
            let horizontal = cos(angle)
            sun.look(at: .zero, from: [horizontal * 70, max(elevation, 0.05) * 90 + 8, 45], relativeTo: nil)
            let warm = smoothstep(0, 0.5, elevation)
            sun.light.color = UIColor(red: 1, green: CGFloat(0.62 + 0.3 * warm), blue: CGFloat(0.38 + 0.36 * warm), alpha: 1)
            sun.light.intensity = 2800 * daylight + 150
        } else {
            let moonAngle = angle + .pi
            sun.look(at: .zero, from: [cos(moonAngle) * 70, max(sin(moonAngle), 0.1) * 90 + 8, -40], relativeTo: nil)
            sun.light.color = UIColor(red: 0.55, green: 0.65, blue: 1, alpha: 1)
            sun.light.intensity = 500 * nightFactor + 150
        }

        lantern.light.intensity = 12000 + 30000 * nightFactor

        if let sky, var material = sky.model?.materials.first as? CustomMaterial {
            let dayWeight = max(0, daylight - dusk * 0.6)
            material.custom.value = [dayWeight, dusk, nightFactor, 0]
            sky.model?.materials = [material]
        }

        // Grading: warm dusk, cool dark night with glowing highlights preserved.
        let day = SIMD3<Float>(1, 1, 1), duskTint = SIMD3<Float>(1.08, 0.88, 0.72), night = SIMD3<Float>(0.32, 0.4, 0.66)
        var tint = mix(day, duskTint, dusk * (1 - nightFactor))
        tint = mix(tint, night, nightFactor)
        let fogDay = SIMD3<Float>(0.6, 0.68, 0.5), fogDusk = SIMD3<Float>(0.75, 0.52, 0.38), fogNight = SIMD3<Float>(0.05, 0.07, 0.13)
        var fog = mix(fogDay, fogDusk, dusk * (1 - nightFactor))
        fog = mix(fog, fogNight, nightFactor)
        grade.set(GradeUniforms(
            tint: SIMD4(tint, 1.05 - 0.35 * nightFactor),
            fog: SIMD4(fog, 0.012 + 0.008 * nightFactor),
            settings: [0.22 + 0.2 * nightFactor, 0.85 * nightFactor, 0, 0]))

        let rate = (nightFactor * 30).rounded()
        if rate != fireflyRate {
            fireflyRate = rate
            fireflies.components.set(Self.makeFireflies(birthRate: rate))
        }
    }

    private static func makeFireflies(birthRate: Float) -> ParticleEmitterComponent {
        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .box
        emitter.birthLocation = .volume
        emitter.emitterShapeSize = [30, 3, 30]
        emitter.fieldSimulationSpace = .global
        emitter.speed = 0.2
        emitter.speedVariation = 0.15
        emitter.mainEmitter.birthRate = birthRate
        emitter.mainEmitter.lifeSpan = 5
        emitter.mainEmitter.lifeSpanVariation = 2
        emitter.mainEmitter.size = 0.06
        emitter.mainEmitter.noiseStrength = 0.6
        emitter.mainEmitter.noiseScale = 0.5
        emitter.mainEmitter.noiseAnimationSpeed = 0.5
        emitter.mainEmitter.opacityCurve = .gradualFadeInOut
        emitter.mainEmitter.blendMode = .additive
        emitter.mainEmitter.isLightingEnabled = false
        emitter.mainEmitter.color = .constant(.random(
            a: UIColor(red: 0.85, green: 1, blue: 0.4, alpha: 1),
            b: UIColor(red: 1, green: 0.85, blue: 0.35, alpha: 1)))
        emitter.isEmitting = birthRate > 0
        return emitter
    }
}

private func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}

private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
    a + (b - a) * t
}
