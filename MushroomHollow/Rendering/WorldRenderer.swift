import GameCore
import RealityKit
import UIKit

/// Links a RealityKit entity back to the simulation entity it shows (for tap targeting).
struct SimEntityComponent: Component {
    let id: EntityID
}

enum QuestMarker: Equatable {
    case available
    case turnIn
}

/// Presents the simulation: owns the RealityKit scene graph, mirrors snapshot entities
/// into models, and interpolates between ticks so 20 Hz simulation looks smooth at 120 Hz.
@MainActor
final class WorldRenderer {
    let root = Entity()
    let camera = PerspectiveCamera()
    let effects = EffectsPlayer()

    private let actorsRoot = Entity()
    private let hazardsRoot = Entity()
    private let sky: ModelEntity
    private let spores = Entity()
    private let selectionRing: ModelEntity
    private let selectedMaterial: UnlitMaterial
    private let engagedMaterial: UnlitMaterial
    private var actors: [EntityID: ActorView] = [:]
    private var npcActors: [NPCID: ActorView] = [:]
    private var hazards: [UInt32: Entity] = [:]
    private var markers: [NPCID: (kind: QuestMarker?, entity: Entity)] = [:]
    private var time: Double = 0

    /// Per-entity presentation state. Animation timestamps are in renderer time.
    private final class ActorView {
        let entity: Entity
        let model: Entity
        let kind: EntityKind
        var gear: [ItemID] = []
        var gearEntity: Entity?
        var telegraph: Entity?
        var lungeStart: Double?
        var hitStart: Double?
        var deathStart: Double?

        init(entity: Entity, model: Entity, kind: EntityKind) {
            self.entity = entity
            self.model = model
            self.kind = kind
        }
    }

    init(map: WorldMap) {
        SimEntityComponent.registerComponent()

        root.addChild(WorldBuilder.build(map))
        root.addChild(actorsRoot)
        root.addChild(hazardsRoot)
        root.addChild(effects.root)

        sky = ModelEntity(mesh: Meshes.sphere, materials: [Materials.sky])
        sky.scale = .init(repeating: 900)
        sky.components.set(DynamicLightShadowComponent(castsShadow: false))
        root.addChild(sky)

        spores.components.set(Self.makeSporeEmitter())
        root.addChild(spores)

        selectedMaterial = Self.translucent(UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1), opacity: 0.85)
        engagedMaterial = Self.translucent(UIColor(red: 1, green: 0.3, blue: 0.2, alpha: 1), opacity: 0.85)
        selectionRing = ModelEntity(mesh: Meshes.ring, materials: [selectedMaterial])
        selectionRing.components.set(DynamicLightShadowComponent(castsShadow: false))
        selectionRing.isEnabled = false
        root.addChild(selectionRing)

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
        self.time = time
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

            if !current.isAlive, view.deathStart == nil {
                view.deathStart = time
                view.entity.components.remove(InputTargetComponent.self)
            } else if current.isAlive, view.deathStart != nil {
                view.deathStart = nil
                if current.kind.isMob { view.entity.components.set(InputTargetComponent()) }
            }
            if current.gear != view.gear { updateGear(view, current.gear) }
            animate(view, snapshot: current, time: time)
        }

        for (id, view) in actors where !seen.contains(id) {
            view.entity.removeFromParent()
            actors[id] = nil
        }

        renderHazards(host.currentSnapshot.hazards)
        animateMarkers(time: time)
        updateSelection(host.currentSnapshot.viewer, time: time)
        effects.update(time: time)
    }

    func placeCamera(at position: SIMD3<Float>, lookingAt target: SIMD3<Float>) {
        camera.look(at: target, from: position, relativeTo: nil)
        sky.position = position
        spores.position = [target.x, 0, target.z]
    }

    // MARK: - Combat presentation

    func playAttack(source: EntityID, target: EntityID, time: Double) {
        actors[source]?.lungeStart = time
        actors[target]?.hitStart = time
    }

    /// World point just above an entity's head.
    func headPosition(of id: EntityID) -> SIMD3<Float>? {
        guard let view = actors[id] else { return nil }
        return view.entity.position + [0, view.kind.headHeight, 0]
    }

    // MARK: - Quest markers

    /// Floating "!" over quest givers (yellow: new quest, green: ready to turn in),
    /// and a spinning coin over shopkeepers.
    func updateQuestMarkers(_ wanted: [NPCID: QuestMarker]) {
        for (npc, view) in npcActors {
            let kind = wanted[npc]
            if let existing = markers[npc], existing.kind == kind { continue }
            markers[npc]?.entity.removeFromParent()
            let marker = Entity()
            if let kind {
                let color = kind == .available ? UIColor.systemYellow : UIColor.systemGreen
                let glow = Materials.glow(color)
                marker.addPart(Meshes.roundedBox, glow, at: [0, 0.22, 0], scale: [0.1, 0.34, 0.1])
                marker.addSphere(glow, at: [0, -0.06, 0], radius: 0.065)
            } else if npc.definition.isShopkeeper {
                let gold = Materials.glossy(UIColor(red: 1, green: 0.8, blue: 0.25, alpha: 1))
                marker.addCylinder(gold, at: .zero, radius: 0.2, height: 0.05, rotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))
            }
            marker.position = [0, view.kind.headHeight + 0.5, 0]
            marker.components.set(DynamicLightShadowComponent(castsShadow: false))
            view.entity.addChild(marker)
            markers[npc] = (kind, marker)
        }
    }

    private func animateMarkers(time: Double) {
        let t = Float(time)
        for (npc, marker) in markers {
            guard let view = npcActors[npc] else { continue }
            marker.entity.position.y = view.kind.headHeight + 0.5 + sin(t * 2.5) * 0.08
            marker.entity.orientation = simd_quatf(angle: t * 1.8, axis: [0, 1, 0])
        }
    }

    // MARK: - Actors

    private func makeActor(_ snapshot: EntitySnapshot) -> ActorView {
        let entity = Entity()
        entity.name = "\(snapshot.kind) \(snapshot.id)"
        entity.components.set(SimEntityComponent(id: snapshot.id))

        let tapSize: SIMD3<Float>? = switch snapshot.kind {
        case let .mob(kind): SIMD3(kind.radius * 2.6, kind.headHeight + 0.3, kind.radius * 3)
        case .npc: SIMD3(1.2, 2.4, 1.2)
        case .player: nil
        }
        if let size = tapSize {
            // Generous tap target: easier to hit a snail with a thumb.
            entity.components.set(CollisionComponent(shapes: [
                .generateBox(size: size).offsetBy(translation: [0, size.y / 2, 0]),
            ]))
            entity.components.set(InputTargetComponent())
        }

        let model = ActorModels.make(snapshot.kind)
        entity.addChild(model)
        actorsRoot.addChild(entity)
        let view = ActorView(entity: entity, model: model, kind: snapshot.kind)

        if snapshot.kind == .mob(.beetle) {
            // Red strip on the ground showing where the charge will go.
            let length = GameSimulation.chargeSpeed * GameSimulation.chargeDuration
            let strip = ModelEntity(mesh: Meshes.box, materials: [Self.translucent(.systemRed, opacity: 0.45)])
            strip.transform = Transform(scale: [1.2, 0.02, length], rotation: simd_quatf(angle: 0, axis: [0, 1, 0]),
                                        translation: [0, 0.03, length / 2 + 0.5])
            strip.components.set(DynamicLightShadowComponent(castsShadow: false))
            strip.isEnabled = false
            entity.addChild(strip)
            view.telegraph = strip
        }
        if case let .npc(npc) = snapshot.kind { npcActors[npc] = view }

        actors[snapshot.id] = view
        return view
    }

    private func updateGear(_ view: ActorView, _ gear: [ItemID]) {
        view.gearEntity?.removeFromParent()
        let entity = ActorModels.makeGear(gear)
        view.model.addChild(entity)
        view.gearEntity = entity
        view.gear = gear
    }

    private func updateSelection(_ viewer: PlayerStatus?, time: Double) {
        guard let targetID = viewer?.target, let target = actors[targetID], target.deathStart == nil else {
            selectionRing.isEnabled = false
            return
        }
        let radius: Float = if case let .mob(kind) = target.kind { kind.radius * 1.5 } else { 0.8 }
        let pulse = 1 + sin(Float(time) * 5) * 0.05
        selectionRing.isEnabled = true
        selectionRing.position = target.entity.position + [0, 0.04, 0]
        selectionRing.scale = SIMD3(repeating: radius * pulse)
        selectionRing.orientation = simd_quatf(angle: Float(time) * 0.8, axis: [0, 1, 0])
        selectionRing.model?.materials = [viewer?.isEngaged == true ? engagedMaterial : selectedMaterial]
    }

    /// Cheap procedural motion until we have skeletal animation.
    private func animate(_ view: ActorView, snapshot: EntitySnapshot, time: Double) {
        let t = Float(time)
        let seed = Float(snapshot.id.rawValue)
        let isMoving = snapshot.isMoving
        var offset = SIMD3<Float>.zero
        var scale = SIMD3<Float>.one
        var rotation = simd_quatf(angle: 0, axis: [0, 1, 0])

        switch view.kind {
        case .player:
            offset.y = isMoving ? abs(sin(t * 11)) * 0.07 : sin(t * 2 + seed) * 0.01
            rotation = simd_quatf(angle: isMoving ? 0.12 : 0, axis: [1, 0, 0])
        case .mob(.snail), .mob(.slug):
            // Gastropods creep by rippling, not bouncing.
            let ripple = isMoving ? sin(t * 5 + seed) * 0.07 : sin(t * 1.2 + seed) * 0.015
            scale = [1 - ripple * 0.3, 1 - ripple * 0.5, 1 + ripple]
        case .mob:
            offset.y = isMoving ? abs(sin(t * 8 + seed)) * 0.05 : 0
        case .npc:
            // Gentle idle sway.
            rotation = simd_quatf(angle: sin(t * 1.3 + seed) * 0.04, axis: [0, 0, 1])
        }

        switch snapshot.pose {
        case .normal:
            break
        case .hiding:
            scale *= [1.05, 0.72, 0.8]
            offset.y -= 0.04
        case .windingUp:
            offset.x += sin(t * 60) * 0.04
            scale *= [1.05, 0.85, 1]
            rotation = simd_quatf(angle: 0.22, axis: [1, 0, 0]) * rotation
        case .charging:
            rotation = simd_quatf(angle: 0.15, axis: [1, 0, 0]) * rotation
            offset.y += abs(sin(t * 22)) * 0.08
        }
        if let telegraph = view.telegraph {
            telegraph.isEnabled = snapshot.pose == .windingUp
            if telegraph.isEnabled {
                telegraph.components.set(OpacityComponent(opacity: 0.55 + sin(t * 18) * 0.35))
            }
        }

        // Attack lunge: a quick hop toward the target (models face +Z).
        if let start = view.lungeStart {
            let p = Float((time - start) / 0.28)
            if p < 1 { offset.z += sin(p * .pi) * 0.35 } else { view.lungeStart = nil }
        }
        // Hit reaction: a squash-and-pop.
        if let start = view.hitStart {
            let p = Float((time - start) / 0.22)
            if p < 1 {
                let pop = sin(p * .pi) * 0.14
                scale *= [1 + pop, 1 - pop, 1 + pop]
                offset.z -= sin(p * .pi) * 0.1
            } else {
                view.hitStart = nil
            }
        }
        // Death: tip over, shrink, and sink into the moss.
        if let start = view.deathStart {
            let p = min(1, Float((time - start) / 1.2))
            let eased = 1 - (1 - p) * (1 - p)
            rotation = simd_quatf(angle: eased * .pi / 2, axis: [0, 0, 1]) * rotation
            if view.kind.isMob {
                scale *= SIMD3(repeating: 1 - 0.5 * p)
                offset.y -= 0.3 * p
            }
        }

        view.model.transform = Transform(scale: scale, rotation: rotation, translation: offset)
    }

    // MARK: - Hazards

    private func renderHazards(_ snapshots: [HazardSnapshot]) {
        var seen = Set<UInt32>()
        for hazard in snapshots {
            seen.insert(hazard.id)
            let entity = hazards[hazard.id] ?? makeHazard(hazard)
            // Fade in quickly, fade out over the last third of its life.
            let opacity = min(1, hazard.remaining * 3)
            entity.components.set(OpacityComponent(opacity: opacity))
            if hazard.kind == .sporeCloud {
                entity.scale = SIMD3(repeating: 0.85 + sin(Float(time) * 3 + Float(hazard.id)) * 0.05)
            }
        }
        for (id, entity) in hazards where !seen.contains(id) {
            entity.removeFromParent()
            hazards[id] = nil
        }
    }

    private func makeHazard(_ hazard: HazardSnapshot) -> Entity {
        let entity = Entity()
        entity.position = [hazard.position.x, 0, hazard.position.y]
        switch hazard.kind {
        case .slime:
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: UIColor(red: 0.75, green: 0.8, blue: 0.3, alpha: 1))
            material.roughness = 0.1
            material.blending = .transparent(opacity: .init(floatLiteral: 0.55))
            let puddle = ModelEntity(mesh: Meshes.cylinder, materials: [material])
            puddle.transform = Transform(scale: [hazard.radius, 0.01, hazard.radius * 0.8],
                                         rotation: simd_quatf(angle: Float(hazard.id), axis: [0, 1, 0]),
                                         translation: [0, 0.02, 0])
            entity.addChild(puddle)
        case .sporeCloud:
            let cloud = ModelEntity(mesh: Meshes.sphere, materials: [Self.translucent(UIColor(red: 0.6, green: 0.3, blue: 0.8, alpha: 1), opacity: 0.3)])
            cloud.transform = Transform(scale: [hazard.radius, hazard.radius * 0.45, hazard.radius],
                                        rotation: simd_quatf(angle: 0, axis: [0, 1, 0]), translation: [0, 0.4, 0])
            entity.addChild(cloud)
            entity.components.set(Self.makeCloudEmitter(radius: hazard.radius))
        }
        entity.components.set(DynamicLightShadowComponent(castsShadow: false))
        hazardsRoot.addChild(entity)
        hazards[hazard.id] = entity
        return entity
    }

    // MARK: - Materials and emitters

    private static func translucent(_ color: UIColor, opacity: Float) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        material.faceCulling = .none
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return material
    }

    private static func makeCloudEmitter(radius: Float) -> ParticleEmitterComponent {
        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .cylinder
        emitter.birthLocation = .volume
        emitter.emitterShapeSize = [radius * 2, 1.2, radius * 2]
        emitter.speed = 0.15
        emitter.mainEmitter.birthRate = 60
        emitter.mainEmitter.lifeSpan = 1.6
        emitter.mainEmitter.size = 0.12
        emitter.mainEmitter.sizeVariation = 0.06
        emitter.mainEmitter.acceleration = [0, 0.25, 0]
        emitter.mainEmitter.opacityCurve = .gradualFadeInOut
        emitter.mainEmitter.blendMode = .additive
        emitter.mainEmitter.isLightingEnabled = false
        emitter.mainEmitter.color = .constant(.random(
            a: UIColor(red: 0.7, green: 0.3, blue: 0.9, alpha: 1),
            b: UIColor(red: 0.55, green: 0.9, blue: 0.4, alpha: 1)))
        return emitter
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
