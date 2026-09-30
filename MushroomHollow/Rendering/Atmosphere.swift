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
    private var skyWeights = SIMD4<Float>(repeating: -1)

    /// 0 at noon, 1 at midnight, smooth in between.
    private(set) var nightFactor: Float = 0

    init(map: WorldMap, sky: ModelEntity) {
        self.sky = sky

        // Ink-style surfaces are unlit (ToonLighting shades them) and actors get drawn blob
        // shadows, so lights (and their shadow maps) would only cost time.
        if !ArtStyle.isInk {
            var shadow = DirectionalLightComponent.Shadow(shadowProjection: .automatic(maximumDistance: 45), depthBias: 1.5)
            shadow.cascades = .automatic
            sun.shadow = shadow
            root.addChild(sun)

            lantern.light.color = Palette.windowGlow
            lantern.light.attenuationRadius = 20
            lantern.position = [map.villageCenter.x, 4, map.villageCenter.y]
            root.addChild(lantern)
        }

        fireflies.components.set(Self.makeFireflies())
        root.addChild(fireflies)
    }

    /// Call every frame; does real work only when the time has moved noticeably.
    func update(timeOfDay: Float, focus: SIMD3<Float>) {
        fireflies.position = [focus.x, focus.y - 1.3, focus.z]
        // 0.001 of a day is under a second: the sky still turns smoothly.
        guard abs(timeOfDay - lastApplied) > 0.001 else { return }
        lastApplied = timeOfDay

        // Sun angle: 0 at dawn (0.25), up at noon, down at dusk (0.75).
        let angle = (timeOfDay - 0.25) * 2 * .pi
        let elevation = sin(angle)
        let daylight = smoothstep(-0.05, 0.25, elevation)
        let dusk = max(0, 1 - abs(elevation) / 0.3) // near the horizon, either side
        nightFactor = 1 - smoothstep(-0.2, 0.05, elevation)

        // One directional light plays the sun by day and the moon by night (the classic style).
        if ArtStyle.isInk {
            // Unlit: ToonLighting does the sun's job.
        } else if elevation > -0.02 {
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

        if !ArtStyle.isInk { lantern.light.intensity = 12000 + 30000 * nightFactor }

        let weights = SIMD4<Float>(max(0, daylight - dusk * 0.6), dusk, nightFactor, 0)
        if let sky, simd_reduce_max(abs(weights - skyWeights)) > 0.004,
           var material = sky.model?.materials.first as? CustomMaterial {
            skyWeights = weights
            material.custom.value = weights
            sky.model?.materials = [material]
        }

        // Grading: warm dusk, cool dark night with glowing highlights preserved.
        let day = SIMD3<Float>(1, 1, 1), duskTint = SIMD3<Float>(1.08, 0.88, 0.72), night = SIMD3<Float>(0.32, 0.4, 0.66)
        var tint = mix(day, duskTint, dusk * (1 - nightFactor))
        tint = mix(tint, night, nightFactor)
        let fogDay = SIMD3<Float>(0.6, 0.68, 0.5), fogDusk = SIMD3<Float>(0.75, 0.52, 0.38), fogNight = SIMD3<Float>(0.05, 0.07, 0.13)
        var fog = mix(fogDay, fogDusk, dusk * (1 - nightFactor))
        fog = mix(fog, fogNight, nightFactor)
        var uniforms = GradeUniforms(
            tint: SIMD4(tint, 1.05 - 0.35 * nightFactor),
            fog: SIMD4(fog, 0.012 + 0.008 * nightFactor),
            settings: [0.22 + 0.2 * nightFactor, 0.85 * nightFactor, 0, 0])
        if ArtStyle.isInk {
            applyInk(to: &uniforms, dusk: dusk * (1 - nightFactor))
        }
        grade.set(uniforms)

        // Change the rate in place: a fresh emitter would drop the fireflies already out.
        let rate = (nightFactor * 30).rounded()
        if rate != fireflyRate, var emitter = fireflies.components[ParticleEmitterComponent.self] {
            fireflyRate = rate
            emitter.mainEmitter.birthRate = rate
            emitter.isEmitting = rate > 0
            fireflies.components.set(emitter)
        }
    }

    /// The ink style's day and night, like a drawing colored in with markers: bright paper by day
    /// with one gentle shadow tone, warm by dusk, and a moonlit blue night where the fills dim but
    /// the lines stay dark. Distance fades to paper, not green haze, like an unfinished sketch.
    private func applyInk(to uniforms: inout GradeUniforms, dusk: Float) {
        let night = nightFactor
        var key = mix([1, 1, 1], [1.04, 0.9, 0.8], dusk)
        key = mix(key, [0.44, 0.5, 0.84], night)
        var shadow = mix([0.8, 0.75, 0.88], [0.72, 0.58, 0.7], dusk)
        shadow = mix(shadow, [0.3, 0.33, 0.6], night)
        // Shader colors are linear: 0.008 is a marker black on screen (0.07 read as dark grey).
        let ink = mix([0.008, 0.007, 0.007], [0.005, 0.006, 0.014], night)
        ToonLighting.shared.set(.init(key: key, shadow: shadow, ink: ink,
                                      direction: simd_normalize(SIMD3<Float>(0.45, 0.8, 0.4))))

        // The materials already carry the time of day: grade barely at all.
        uniforms.tint = SIMD4(mix([1, 1, 1], [0.86, 0.9, 1], night), 1)
        uniforms.settings.x = 0.16 * night
        uniforms.settings.y = 0.5 * night
        var paper = mix([0.97, 0.96, 0.9], [1, 0.86, 0.74], dusk)
        paper = mix(paper, [0.16, 0.19, 0.3], night)
        uniforms.fog = SIMD4(paper, 0.012 + 0.002 * night)
        uniforms.ink = [0, 1.05, 0.45, 0.035]
        uniforms.inkColor = SIMD4(ink, 1)
        uniforms.inkShape = [0, 60, 150, 1]
    }

    private static func makeFireflies() -> ParticleEmitterComponent {
        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .box
        emitter.birthLocation = .volume
        emitter.emitterShapeSize = [30, 3, 30]
        emitter.fieldSimulationSpace = .global
        emitter.speed = 0.2
        emitter.speedVariation = 0.15
        emitter.mainEmitter.birthRate = 0
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
        emitter.isEmitting = false
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
