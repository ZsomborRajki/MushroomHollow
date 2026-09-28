import GameCore
import RealityKit
import UIKit

/// Presents the simulation: owns the RealityKit scene graph, mirrors snapshot entities
/// into models, and interpolates between ticks so 20 Hz simulation looks smooth at 120 Hz.
@MainActor
final class WorldRenderer {
    let root = Entity()
    let camera = PerspectiveCamera()

    private let actorsRoot = Entity()
    private let sky: ModelEntity
    private let spores = Entity()
    private var actors: [EntityID: ActorView] = [:]

    private struct ActorView {
        let entity: Entity
        let model: Entity
        let kind: EntityKind
    }

    init(map: WorldMap) {
        root.addChild(WorldBuilder.build(map))
        root.addChild(actorsRoot)

        sky = ModelEntity(mesh: Meshes.sphere, materials: [Materials.sky])
        sky.scale = .init(repeating: 900)
        sky.components.set(DynamicLightShadowComponent(castsShadow: false))
        root.addChild(sky)

        spores.components.set(Self.makeSporeEmitter())
        root.addChild(spores)

        camera.camera.fieldOfViewInDegrees = 60
        camera.camera.near = 0.1
        camera.camera.far = 2000
        root.addChild(camera)
    }

    /// Interpolated world position of an entity, as last rendered.
    func renderedPosition(of id: EntityID) -> SIMD3<Float>? {
        actors[id]?.entity.position
    }

    func render(host: some WorldHost, time: Double) {
        let alpha = host.interpolationAlpha
        let previous = Dictionary(uniqueKeysWithValues: host.previousSnapshot.entities.map { ($0.id, $0) })
        var seen = Set<EntityID>()

        for current in host.currentSnapshot.entities {
            seen.insert(current.id)
            let view = actors[current.id] ?? makeActor(current)
            let from = previous[current.id] ?? current
            let position = simd_mix(from.position, current.position, SIMD3(repeating: alpha))
            let yaw = AngleMath.lerp(from.yaw, current.yaw, alpha)
            view.entity.transform = Transform(
                scale: .one,
                rotation: simd_quatf(angle: yaw, axis: [0, 1, 0]),
                translation: position)
            animate(view, isMoving: current.isMoving, time: Float(time), seed: Float(current.id.rawValue))
        }

        for (id, view) in actors where !seen.contains(id) {
            view.entity.removeFromParent()
            actors[id] = nil
        }
    }

    func placeCamera(at position: SIMD3<Float>, lookingAt target: SIMD3<Float>) {
        camera.look(at: target, from: position, relativeTo: nil)
        sky.position = position
        spores.position = [target.x, 0, target.z]
    }

    private func makeActor(_ snapshot: EntitySnapshot) -> ActorView {
        let entity = Entity()
        entity.name = "\(snapshot.kind) \(snapshot.id)"
        let model = ActorModels.make(snapshot.kind)
        entity.addChild(model)
        actorsRoot.addChild(entity)
        let view = ActorView(entity: entity, model: model, kind: snapshot.kind)
        actors[snapshot.id] = view
        return view
    }

    /// Cheap procedural motion until we have skeletal animation.
    private func animate(_ view: ActorView, isMoving: Bool, time: Float, seed: Float) {
        switch view.kind {
        case .player:
            let bob: Float = isMoving ? abs(sin(time * 11)) * 0.07 : sin(time * 2 + seed) * 0.01
            view.model.position.y = bob
            view.model.orientation = simd_quatf(angle: isMoving ? 0.12 : 0, axis: [1, 0, 0])
        case .mob(.snail), .mob(.slug):
            // Gastropods creep by rippling, not bouncing.
            let ripple = isMoving ? sin(time * 5 + seed) * 0.07 : sin(time * 1.2 + seed) * 0.015
            view.model.scale = [1 - ripple * 0.3, 1 - ripple * 0.5, 1 + ripple]
        case .mob:
            view.model.position.y = isMoving ? abs(sin(time * 8 + seed)) * 0.05 : 0
        }
    }

    /// Glowing spores drifting around the player.
    private static func makeSporeEmitter() -> ParticleEmitterComponent {
        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .box
        emitter.birthLocation = .volume
        emitter.emitterShapeSize = [36, 7, 36]
        emitter.fieldSimulationSpace = .global
        emitter.particlesInheritTransform = false
        emitter.speed = 0.05
        emitter.speedVariation = 0.04
        emitter.mainEmitter.birthRate = 45
        emitter.mainEmitter.lifeSpan = 7
        emitter.mainEmitter.lifeSpanVariation = 2
        emitter.mainEmitter.size = 0.045
        emitter.mainEmitter.sizeVariation = 0.02
        emitter.mainEmitter.acceleration = [0, 0.02, 0]
        emitter.mainEmitter.noiseStrength = 0.15
        emitter.mainEmitter.noiseScale = 1
        emitter.mainEmitter.noiseAnimationSpeed = 0.3
        emitter.mainEmitter.opacityCurve = .gradualFadeInOut
        emitter.mainEmitter.blendMode = .additive
        emitter.mainEmitter.isLightingEnabled = false
        emitter.mainEmitter.color = .constant(.random(
            a: UIColor(red: 1.0, green: 0.95, blue: 0.6, alpha: 1),
            b: UIColor(red: 0.7, green: 1.0, blue: 0.8, alpha: 1)))
        return emitter
    }
}
