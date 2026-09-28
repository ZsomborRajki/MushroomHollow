import GameCore
import RealityKit
import UIKit

/// Links a RealityKit entity back to the simulation entity it shows (for tap targeting).
struct SimEntityComponent: Component {
    let id: EntityID
}

/// Links a tappable world reward to its authoritative drop ID.
struct GroundDropComponent: Component {
    let id: UInt32
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
    let sounds = SoundBank()
    let atmosphere: Atmosphere

    private let actorsRoot = Entity()
    private let hazardsRoot = Entity()
    private let telegraphsRoot = Entity()
    private let dropsRoot = Entity()
    private var telegraphs: [String: (outline: ModelEntity, fill: ModelEntity)] = [:]
    private let sky: ModelEntity
    private let spores = Entity()
    private let selectionRing: ModelEntity
    private let selectedMaterial: UnlitMaterial
    private let engagedMaterial: UnlitMaterial
    private var actors: [EntityID: ActorView] = [:]
    private var npcActors: [NPCID: ActorView] = [:]
    private var hazards: [UInt32: Entity] = [:]
    private var drops: [UInt32: Entity] = [:]
    /// Pets out in the world, by owner.
    private var pets: [EntityID: PetView] = [:]
    private var markers: [NPCID: (kind: QuestMarker?, entity: Entity)] = [:]
    private var time: Double = 0
    private var timeOfDay: Float = 0.4
    private let map: WorldMap
    private let culler: SceneryCuller
    private var viewFrustum: CameraFrustum?
    var viewportAspect: Float = 16 / 9
    /// The painted forest floor, for the map screen.
    let groundPainting: UIImage

    /// Per-entity presentation state. Animation timestamps are in renderer time.
    private final class ActorView {
        let entity: Entity
        let model: Entity
        let kind: EntityKind
        var gear: [ItemID] = []
        var playerClass: PlayerClass?
        var rig: PlayerRig?
        var glider: Entity?
        var wings: [Entity] = []
        var telegraph: Entity?
        /// The ink style's drawn shadow; it stays on the ground under hovering and flying actors.
        var shadow: Entity?
        var shadowRadius: Float = 0
        var lungeStart: Double?
        var hitStart: Double?
        var deathStart: Double?

        init(entity: Entity, model: Entity, kind: EntityKind) {
            self.entity = entity
            self.model = model
            self.kind = kind
        }
    }

    private final class PetView {
        let entity = Entity()
        let rig: PetRig

        init(kind: PetKind) {
            rig = PetRig(kind)
            entity.name = "Pet \(kind)"
            entity.addChild(rig.root)
        }
    }

    /// Beyond this, mobs aren't drawn (the world is 600 m across; a critter here is ~3 px tall).
    private static let mobDrawDistance: Float = 120

    init(map: WorldMap) {
        SimEntityComponent.registerComponent()
        GroundDropComponent.registerComponent()

        self.map = map
        let world = WorldBuilder.build(map)
        culler = world.culler
        groundPainting = world.groundPainting
        root.addChild(world.root)
        root.addChild(actorsRoot)
        root.addChild(hazardsRoot)
        root.addChild(telegraphsRoot)
        root.addChild(dropsRoot)
        root.addChild(effects.root)

        sky = ModelEntity(mesh: Meshes.sphere, materials: [Materials.sky])
        sky.scale = .init(repeating: 900)
        sky.components.set(DynamicLightShadowComponent(castsShadow: false))
        root.addChild(sky)

        spores.components.set(Self.makeSporeEmitter())
        root.addChild(spores)

        atmosphere = Atmosphere(map: map, sky: sky)
        root.addChild(atmosphere.root)
        root.addChild(sounds.root)

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
        timeOfDay = host.currentSnapshot.timeOfDay
        let alpha = host.interpolationAlpha
        let previous = Dictionary(uniqueKeysWithValues: host.previousSnapshot.entities.map { ($0.id, $0) })
        var seen = Set<EntityID>()

        for current in host.currentSnapshot.entities {
            seen.insert(current.id)
            let from = previous[current.id] ?? current
            let position = simd_mix(from.position, current.position, SIMD3(repeating: alpha))
            // Tiny mobs beyond the haze are cheaper to skip before any terrain or view work.
            let isDistant = current.kind.isMob && current.kind != .mob(.owl)
                && simd_distance_squared(position, camera.position) > Self.mobDrawDistance * Self.mobDrawDistance
            if isDistant {
                actors[current.id]?.entity.isEnabled = false
                continue
            }
            let ground = standingHeight(at: position.xz)
            let worldPosition = position + SIMD3<Float>(0, ground, 0)
            let visible = current.kind == .player || viewFrustum?.contains(
                center: worldPosition + SIMD3<Float>(0, current.kind.headHeight * 0.5, 0),
                radius: Self.actorRadius(current.kind)) != false
            guard let view = actors[current.id] ?? (visible ? makeActor(current) : nil) else { continue }
            let shouldDraw = visible
            if view.entity.isEnabled != shouldDraw { view.entity.isEnabled = shouldDraw }
            let yaw = AngleMath.lerp(from.yaw, current.yaw, alpha)
            // The simulation's y is height above the ground: stand on the terrain (or wade in the shallows).
            var rotation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            if case let .mob(kind) = current.kind, !kind.hovers, kind != .owl, current.isAlive, position.y < 0.05 {
                // Critters hug the slope they're walking on.
                let normal = map.terrain.normal(at: position.xz, step: max(0.4, kind.radius))
                rotation = simd_quatf(from: [0, 1, 0], to: normal) * rotation
            }
            view.entity.transform = Transform(scale: .one, rotation: rotation, translation: worldPosition)
            if let shadow = view.shadow {
                let lift = max(0, position.y)
                shadow.position.y = 0.04 - lift
                shadow.scale = SIMD3(repeating: view.shadowRadius * max(0.4, 1 - lift / 14))
                if shadow.isEnabled != current.isAlive { shadow.isEnabled = current.isAlive }
            }

            if !current.isAlive, view.deathStart == nil {
                view.deathStart = time
                view.entity.components.remove(InputTargetComponent.self)
            } else if current.isAlive, view.deathStart != nil {
                view.deathStart = nil
                if current.kind.isMob { view.entity.components.set(InputTargetComponent()) }
            }
            if current.gear != view.gear || current.playerClass != view.playerClass {
                updateGear(view, current.gear, playerClass: current.playerClass)
            }
            if current.kind == .player { updateGlider(view, airborne: current.isFlying || current.position.y > 0.05) }
            if shouldDraw { animate(view, snapshot: current, time: time) }
        }

        for (id, view) in actors where !seen.contains(id) {
            view.entity.removeFromParent()
            actors[id] = nil
        }

        renderHazards(host.currentSnapshot.hazards)
        renderTelegraphs(host.currentSnapshot.telegraphs)
        renderDrops(host.currentSnapshot.drops)
        renderPets(host: host, alpha: alpha, time: time)
        animateMarkers(time: time)
        updateSelection(host.currentSnapshot.viewer, time: time)
        effects.update(time: time)
    }

    func placeCamera(at position: SIMD3<Float>, lookingAt target: SIMD3<Float>) {
        camera.look(at: target, from: position, relativeTo: nil)
        sky.position = position
        spores.position = [target.x, target.y - 1.3, target.z]
        atmosphere.update(timeOfDay: timeOfDay, focus: target)
        let frustum = CameraFrustum(position: position, target: target,
                                    verticalFOV: Float(camera.camera.fieldOfViewInDegrees), aspect: viewportAspect,
                                    near: Float(camera.camera.near), far: Float(camera.camera.far))
        viewFrustum = frustum
        culler.update(frustum: frustum)
        for view in actors.values {
            let center = view.entity.position + SIMD3<Float>(0, view.kind.headHeight * 0.5, 0)
            let visible = view.kind == .player || frustum.contains(center: center, radius: Self.actorRadius(view.kind))
            let distant = view.kind.isMob && view.kind != .mob(.owl)
                && simd_distance_squared(view.entity.position, position) > Self.mobDrawDistance * Self.mobDrawDistance
            let shouldDraw = visible && !distant
            if view.entity.isEnabled != shouldDraw { view.entity.isEnabled = shouldDraw }
        }
        if selectionRing.isEnabled && !frustum.contains(center: selectionRing.position, radius: 1) {
            selectionRing.isEnabled = false
        }
    }

    private static func actorRadius(_ kind: EntityKind) -> Float {
        switch kind {
        case .player: 2.2
        case let .mob(mob): max(mob.radius * 2, mob.headHeight)
        case .npc: 2.5
        }
    }

    /// What something standing at `point` stands on: the ground, or knee-deep in a lake's shallows.
    func standingHeight(at point: SIMD2<Float>) -> Float {
        let ground = map.groundHeight(at: point)
        guard let lake = map.terrain.lake(at: point) else { return ground }
        return max(ground, lake.waterLevel - 0.3)
    }

    /// The scene entity showing a simulation entity (for spatial sounds).
    func entity(for id: EntityID) -> Entity? {
        actors[id]?.entity
    }

    func playerClass(of id: EntityID) -> PlayerClass? {
        actors[id]?.playerClass
    }

    /// The weapon family an entity fights with, and whether its auto-attacks fly as projectiles.
    func attackStyle(of id: EntityID) -> (weapon: WeaponType?, ranged: Bool) {
        guard let view = actors[id] else { return (nil, false) }
        let weapon = view.gear.lazy.compactMap(\.definition.weaponType).first
        return (weapon, view.kind == .player && Progression.reach(weapon: weapon, playerClass: view.playerClass) > 2)
    }

    /// Where a player's shots leave from (bow string, wand tip, staff droplet), if anywhere special.
    func muzzle(of id: EntityID) -> SIMD3<Float>? {
        actors[id]?.rig?.muzzlePosition
    }

    // MARK: - Combat presentation

    func playAttack(source: EntityID, target: EntityID, time: Double) {
        actors[source]?.lungeStart = time
        actors[source]?.rig?.playSwing(at: time)
        actors[target]?.hitStart = time
        actors[target]?.rig?.playHurt(at: time)
    }

    /// The attacker lunges and the defender catches it on the shield.
    func playBlock(source: EntityID, target: EntityID, time: Double) {
        actors[source]?.lungeStart = time
        actors[source]?.rig?.playSwing(at: time)
        actors[target]?.rig?.playBlock(at: time)
    }

    #if DEBUG
    func debugAttack(_ id: EntityID, block: Bool, time: Double) {
        if block { actors[id]?.rig?.playBlock(at: time) } else { actors[id]?.rig?.playSwing(at: time) }
    }
    #endif

    /// Arms raised to cast a skill (players only).
    func playCast(caster: EntityID, time: Double) {
        actors[caster]?.rig?.playCast(at: time)
    }

    /// A happy hop for level ups and finished quests (players only).
    func playCheer(_ id: EntityID, time: Double) {
        actors[id]?.rig?.playCheer(at: time)
    }

    /// World point just above an entity's head.
    func headPosition(of id: EntityID) -> SIMD3<Float>? {
        guard let view = actors[id] else { return nil }
        return view.entity.position + [0, view.kind.headHeight, 0]
    }

    // MARK: - Quest markers

    /// Floating "!" over quest givers (yellow: new quest, green: ready to turn in),
    /// a spinning coin over shopkeepers, and an amber gem over the blacksmith.
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
            } else if npc.definition.upgradesGear {
                // An amber gem: bring shards here.
                let amber = Materials.glow(UIColor(red: 1, green: 0.62, blue: 0.18, alpha: 1))
                marker.addPart(Meshes.cone, amber, at: [0, 0.1, 0], scale: [0.16, 0.2, 0.16])
                marker.addPart(Meshes.cone, amber, at: [0, -0.1, 0], scale: [0.16, 0.2, 0.16],
                               rotation: simd_quatf(angle: .pi, axis: [1, 0, 0]))
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

        let rig = snapshot.kind == .player ? PlayerRig() : nil
        let model = rig?.root ?? ActorModels.make(snapshot.kind)
        entity.addChild(model)
        actorsRoot.addChild(entity)
        let view = ActorView(entity: entity, model: model, kind: snapshot.kind)
        view.rig = rig
        view.wings = ActorModels.wingNames.compactMap { model.findEntity(named: $0) }
        if ArtStyle.isInk {
            model.addInkHulls(width: InkStyle.hullWidth(for: snapshot.kind))
            if let shadow = Entity.makeBlobShadow(radius: InkStyle.shadowRadius(for: snapshot.kind)) {
                entity.addChild(shadow)
                view.shadow = shadow
                view.shadowRadius = InkStyle.shadowRadius(for: snapshot.kind)
            }
        }

        if case let .mob(kind) = snapshot.kind, kind.charges {
            // Red strip on the ground showing where the charge will go.
            let length = GameSimulation.chargeSpeed * GameSimulation.chargeDuration
            let strip = ModelEntity(mesh: Meshes.box, materials: [Self.translucent(.systemRed, opacity: 0.45)])
            strip.transform = Transform(scale: [kind.radius * 1.7, 0.02, length], rotation: simd_quatf(angle: 0, axis: [0, 1, 0]),
                                        translation: [0, 0.03, length / 2 + kind.radius])
            strip.components.set(DynamicLightShadowComponent(castsShadow: false))
            strip.isEnabled = false
            entity.addChild(strip)
            view.telegraph = strip
        }
        if case let .npc(npc) = snapshot.kind { npcActors[npc] = view }

        actors[snapshot.id] = view
        return view
    }

    private func updateGear(_ view: ActorView, _ gear: [ItemID], playerClass: PlayerClass?) {
        view.rig?.dress(gear, playerClass: playerClass)
        view.model.addInkHulls(width: InkStyle.hullWidth(for: view.kind))
        view.gear = gear
        view.playerClass = playerClass
    }

    private func updateGlider(_ view: ActorView, airborne: Bool) {
        // Parented to the model so the seed sways and leans with the hand holding it.
        if airborne, view.glider == nil {
            let glider = ActorModels.makeGlider(grip: PlayerRig.gliderGrip)
            glider.components.set(Self.makePollenTrail())
            glider.addInkHulls(width: InkStyle.hullWidth(for: view.kind))
            view.model.addChild(glider)
            view.glider = glider
        } else if !airborne, let glider = view.glider {
            glider.removeFromParent()
            view.glider = nil
        }
    }

    private func updateSelection(_ viewer: PlayerStatus?, time: Double) {
        guard let targetID = viewer?.target, let target = actors[targetID], target.deathStart == nil,
              target.entity.isEnabled else {
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
        case .player where view.glider != nil:
            // Dangling from the seed: legs swing, body sways with the glider.
            rotation = simd_quatf(angle: sin(t * 1.6) * 0.08, axis: [0, 0, 1])
                * simd_quatf(angle: isMoving ? 0.25 : 0.05, axis: [1, 0, 0])
        case .player:
            offset.y = isMoving ? abs(sin(t * 11)) * 0.07 : sin(t * 2 + seed) * 0.01
            rotation = simd_quatf(angle: isMoving ? 0.12 : 0, axis: [1, 0, 0])
        case .mob(.snail), .mob(.slug):
            // Gastropods creep by rippling, not bouncing.
            let ripple = isMoving ? sin(t * 5 + seed) * 0.07 : sin(t * 1.2 + seed) * 0.015
            scale = [1 - ripple * 0.3, 1 - ripple * 0.5, 1 + ripple]
        case .mob(.owl):
            animateOwl(view, snapshot: snapshot, time: t)
        case let .mob(kind) where kind.hovers:
            // Bees, moths, and seeds bob in the air and beat their wings.
            offset.y = sin(t * 3 + seed) * 0.08
            rotation = simd_quatf(angle: sin(t * 1.7 + seed) * 0.06, axis: [0, 0, 1])
            for (index, wing) in view.wings.enumerated() {
                let side: Float = index == 0 ? -1 : 1
                wing.orientation = simd_quatf(angle: -side * (0.15 + sin(t * kind.flapRate + seed) * 0.55), axis: [0, 0, 1])
            }
        case .mob(.puffweed), .mob(.thornrose):
            // Rooted-looking plants sway on their stems and shuffle when they walk.
            rotation = simd_quatf(angle: sin(t * (isMoving ? 7 : 1.4) + seed) * (isMoving ? 0.1 : 0.05), axis: [0, 0, 1])
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
        case .soaring:
            rotation = simd_quatf(angle: -0.15, axis: [1, 0, 0]) * rotation
        case .diving:
            rotation = simd_quatf(angle: 0.55, axis: [1, 0, 0]) * rotation
        case .spreadingWings:
            offset.x += sin(t * 40) * 0.05
            scale *= [1.05, 1.05, 1.05]
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
        view.rig?.animate(PlayerRig.Motion(moving: isMoving, airborne: view.glider != nil, fainted: view.deathStart != nil,
                                            engaged: snapshot.target != nil),
                          time: time, seed: seed)
    }

    /// Wings fold at rest, beat while airborne, and flare wide before a gust.
    private func animateOwl(_ view: ActorView, snapshot: EntitySnapshot, time t: Float) {
        let airborne = snapshot.position.y > 0.2 || snapshot.pose == .soaring || snapshot.pose == .diving
        for (index, wing) in view.wings.enumerated() {
            let side: Float = index == 0 ? -1 : 1
            let angle: Float = switch snapshot.pose {
            case .spreadingWings: 1.35 + sin(t * 30) * 0.05
            case .diving: 0.5
            default: airborne ? 0.7 + sin(t * 9) * 0.6 : (snapshot.isMoving ? 0.25 + sin(t * 6) * 0.1 : 0.08)
            }
            wing.orientation = simd_quatf(angle: -side * angle, axis: [0, 0, 1])
        }
    }

    // MARK: - Telegraphs

    /// Danger markers on the ground: an outline plus a fill that grows until it goes off.
    private func renderTelegraphs(_ snapshots: [TelegraphSnapshot]) {
        var seen = Set<String>()
        for telegraph in snapshots {
            let key: String
            switch telegraph.shape {
            case .circle: key = "circle-\(telegraph.source.rawValue)"
            case .cone: key = "cone-\(telegraph.source.rawValue)"
            }
            seen.insert(key)
            let radius: Float = switch telegraph.shape {
            case let .circle(radius): radius
            case let .cone(_, radius, _): radius
            }
            let ground = standingHeight(at: telegraph.position)
            let center = SIMD3<Float>(telegraph.position.x, ground, telegraph.position.y)
            let visible = viewFrustum?.contains(center: center, radius: radius * 1.5) != false
            if !visible, telegraphs[key] == nil { continue }
            let parts = telegraphs[key] ?? makeTelegraph(key, shape: telegraph.shape)
            parts.outline.isEnabled = visible
            parts.fill.isEnabled = visible
            if !visible { continue }
            let pulse = 0.55 + 0.25 * sin(Float(time) * 14)
            switch telegraph.shape {
            case let .circle(radius):
                let position = SIMD3<Float>(telegraph.position.x, standingHeight(at: telegraph.position) + 0.05, telegraph.position.y)
                parts.outline.position = position
                parts.outline.scale = SIMD3(repeating: radius)
                parts.fill.position = position + [0, 0.01, 0]
                parts.fill.scale = SIMD3(repeating: max(0.05, radius * telegraph.progress))
            case let .cone(direction, radius, _):
                let transform = Transform(scale: SIMD3(repeating: radius),
                                          rotation: simd_quatf(angle: AngleMath.yaw(facing: direction), axis: [0, 1, 0]),
                                          translation: [telegraph.position.x, standingHeight(at: telegraph.position) + 0.05, telegraph.position.y])
                parts.outline.transform = transform
                var fill = transform
                fill.scale = SIMD3(repeating: max(0.05, radius * telegraph.progress))
                fill.translation.y += 0.01
                parts.fill.transform = fill
            }
            parts.outline.components.set(OpacityComponent(opacity: pulse))
        }
        for (key, parts) in telegraphs where !seen.contains(key) {
            parts.outline.removeFromParent()
            parts.fill.removeFromParent()
            telegraphs[key] = nil
        }
    }

    private func makeTelegraph(_ key: String, shape: TelegraphSnapshot.Shape) -> (outline: ModelEntity, fill: ModelEntity) {
        let mesh: MeshResource
        switch shape {
        case .circle: mesh = Meshes.disc
        case let .cone(_, _, halfAngle): mesh = Meshes.fan(halfAngle: halfAngle)
        }
        let outline = ModelEntity(mesh: mesh, materials: [Self.translucent(UIColor(red: 1, green: 0.25, blue: 0.15, alpha: 1), opacity: 0.35)])
        let fill = ModelEntity(mesh: mesh, materials: [Self.translucent(UIColor(red: 1, green: 0.55, blue: 0.2, alpha: 1), opacity: 0.5)])
        for part in [outline, fill] {
            part.components.set(DynamicLightShadowComponent(castsShadow: false))
            telegraphsRoot.addChild(part)
        }
        telegraphs[key] = (outline, fill)
        return (outline, fill)
    }

    // MARK: - Hazards

    private func renderHazards(_ snapshots: [HazardSnapshot]) {
        var seen = Set<UInt32>()
        for hazard in snapshots {
            seen.insert(hazard.id)
            let ground = standingHeight(at: hazard.position)
            let center = SIMD3<Float>(hazard.position.x, ground + 0.4, hazard.position.y)
            let visible = viewFrustum?.contains(center: center, radius: hazard.radius * 1.5) != false
            if !visible, hazards[hazard.id] == nil { continue }
            let entity = hazards[hazard.id] ?? makeHazard(hazard)
            entity.isEnabled = visible
            if !visible { continue }
            // Fade in quickly, fade out over the last third of its life.
            let opacity = min(1, hazard.remaining * 3)
            entity.components.set(OpacityComponent(opacity: opacity))
            if hazard.kind.isCloud {
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
        entity.position = [hazard.position.x, standingHeight(at: hazard.position), hazard.position.y]
        let color = hazard.kind.color
        if hazard.kind.isCloud {
            let cloud = ModelEntity(mesh: Meshes.sphere, materials: [Self.translucent(color, opacity: 0.3)])
            cloud.transform = Transform(scale: [hazard.radius, hazard.radius * 0.45, hazard.radius],
                                        rotation: simd_quatf(angle: 0, axis: [0, 1, 0]), translation: [0, 0.4, 0])
            entity.addChild(cloud)
            entity.components.set(Self.makeCloudEmitter(radius: hazard.radius, colors: hazard.kind.particleColors))
        } else {
            // A puddle: slime, a web, or smouldering embers.
            let material: any RealityKit.Material = switch hazard.kind {
            case .embers: Self.translucent(color, opacity: 0.7)
            case .web: Materials.translucent(color, opacity: 0.5)
            default: Materials.translucent(color, opacity: 0.55)
            }
            let puddle = ModelEntity(mesh: Meshes.cylinder, materials: [material])
            puddle.transform = Transform(scale: [hazard.radius, 0.01, hazard.radius * 0.8],
                                         rotation: simd_quatf(angle: Float(hazard.id), axis: [0, 1, 0]),
                                         translation: [0, 0.02, 0])
            entity.addChild(puddle)
            if hazard.kind == .web {
                // Rings of silk.
                for fraction: Float in [0.45, 0.8] {
                    let ring = ModelEntity(mesh: Meshes.ring, materials: [Self.translucent(.white, opacity: 0.8)])
                    ring.transform = Transform(scale: SIMD3(repeating: hazard.radius * fraction), translation: [0, 0.035, 0])
                    entity.addChild(ring)
                }
            }
        }
        entity.components.set(DynamicLightShadowComponent(castsShadow: false))
        hazardsRoot.addChild(entity)
        hazards[hazard.id] = entity
        return entity
    }

    // MARK: - Ground rewards

    private func renderDrops(_ snapshots: [GroundDropSnapshot]) {
        var seen = Set<UInt32>()
        for drop in snapshots {
            seen.insert(drop.id)
            let position = SIMD3<Float>(drop.position.x, standingHeight(at: drop.position), drop.position.y)
            let visible = simd_distance_squared(position, camera.position) < 120 * 120
                && viewFrustum?.contains(center: position + [0, 0.25, 0], radius: 0.7) != false
            if !visible, drops[drop.id] == nil { continue }
            let entity = drops[drop.id] ?? makeDrop(drop, at: position)
            entity.isEnabled = visible
        }
        for (id, entity) in drops where !seen.contains(id) {
            entity.removeFromParent()
            drops[id] = nil
        }
    }

    // MARK: - Pets

    /// Pets pop in with a puff when summoned (or when you land) and pop out when they leave.
    private func renderPets(host: some WorldHost, alpha: Float, time: Double) {
        let previous = Dictionary(uniqueKeysWithValues: host.previousSnapshot.pets.map { ($0.id, $0) })
        var seen = Set<EntityID>()
        for current in host.currentSnapshot.pets {
            seen.insert(current.id)
            let from = previous[current.id] ?? current
            let position = simd_mix(from.position, current.position, SIMD3(repeating: alpha))
            let visible = simd_distance_squared(position, camera.position) < Self.mobDrawDistance * Self.mobDrawDistance
            let view = pets[current.id] ?? makePet(current, at: position)
            if view.entity.isEnabled != visible { view.entity.isEnabled = visible }
            guard visible else { continue }
            let normal = map.terrain.normal(at: position.xz, step: 0.4)
            let rotation = simd_quatf(from: [0, 1, 0], to: normal)
                * simd_quatf(angle: AngleMath.lerp(from.yaw, current.yaw, alpha), axis: [0, 1, 0])
            view.entity.transform = Transform(scale: .one, rotation: rotation,
                                              translation: position + [0, standingHeight(at: position.xz), 0])
            view.rig.animate(PetRig.Motion(moving: current.isMoving, hungry: current.isHungry, fetching: current.isFetching),
                             time: time, seed: Float(current.id.rawValue))
        }
        for (id, view) in pets where !seen.contains(id) {
            if view.entity.isEnabled { puff(at: view.entity.position, time: time) }
            view.entity.removeFromParent()
            pets[id] = nil
        }
    }

    private func makePet(_ pet: PetSnapshot, at position: SIMD3<Float>) -> PetView {
        let view = PetView(kind: pet.kind)
        if ArtStyle.isInk {
            view.rig.root.addInkHulls(width: 0.012, minimumSize: 0.03)
            if let shadow = Entity.makeBlobShadow(radius: 0.24) { view.entity.addChild(shadow) }
        }
        actorsRoot.addChild(view.entity)
        pets[pet.id] = view
        puff(at: position + [0, standingHeight(at: position.xz), 0], time: time)
        return view
    }

    private func puff(at position: SIMD3<Float>, time: Double) {
        effects.burst(at: position + [0, 0.25, 0], color: UIColor(red: 1, green: 0.95, blue: 0.85, alpha: 1), count: 16,
                      speed: 1.1, size: 0.07, lifetime: 0.5, rise: 0.6, spread: 0.12, time: time)
    }

    /// The pet hops and sparkles after fetching a drop for `owner`.
    func playPetFetch(owner: EntityID, time: Double) {
        guard let view = pets[owner] else { return }
        view.rig.playHop(at: time)
        effects.burst(at: view.entity.position + [0, 0.45, 0], color: PetRig.tint, count: 8, speed: 0.8, size: 0.05,
                      lifetime: 0.45, rise: 0.8, time: time)
    }

    /// Where a player's pet is drawn, if it's out.
    func petPosition(of owner: EntityID) -> SIMD3<Float>? {
        pets[owner]?.entity.position
    }

    private func makeDrop(_ drop: GroundDropSnapshot, at position: SIMD3<Float>) -> Entity {
        let entity = Entity()
        entity.name = "Ground drop \(drop.id)"
        entity.position = position
        entity.components.set(GroundDropComponent(id: drop.id))
        entity.components.set(CollisionComponent(shapes: [
            .generateSphere(radius: 0.42).offsetBy(translation: [0, 0.25, 0]),
        ]))
        entity.components.set(InputTargetComponent())
        entity.addChild(DropModels.make(drop.kind))
        dropsRoot.addChild(entity)
        drops[drop.id] = entity
        return entity
    }

    // MARK: - Materials and emitters

    private static func translucent(_ color: UIColor, opacity: Float) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        material.faceCulling = .none
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return material
    }

    private static func makeCloudEmitter(radius: Float, colors: (UIColor, UIColor)) -> ParticleEmitterComponent {
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
        emitter.mainEmitter.color = .constant(.random(a: colors.0, b: colors.1))
        return emitter
    }

    /// Pollen drifting off the dandelion seed while flying.
    private static func makePollenTrail() -> ParticleEmitterComponent {
        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .sphere
        emitter.emitterShapeSize = [0.6, 0.3, 0.6]
        emitter.fieldSimulationSpace = .global
        emitter.speed = 0.1
        emitter.mainEmitter.birthRate = 25
        emitter.mainEmitter.lifeSpan = 2
        emitter.mainEmitter.size = 0.035
        emitter.mainEmitter.acceleration = [0, -0.3, 0]
        emitter.mainEmitter.noiseStrength = 0.3
        emitter.mainEmitter.opacityCurve = .gradualFadeInOut
        emitter.mainEmitter.blendMode = .additive
        emitter.mainEmitter.isLightingEnabled = false
        emitter.mainEmitter.color = .constant(.single(UIColor(red: 1, green: 0.97, blue: 0.8, alpha: 1)))
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

extension HazardKind {
    /// The cloud or puddle's own color.
    fileprivate var color: UIColor {
        switch self {
        case .slime: UIColor(red: 0.75, green: 0.8, blue: 0.3, alpha: 1)
        case .web: UIColor(red: 0.92, green: 0.92, blue: 0.96, alpha: 1)
        case .embers: UIColor(red: 1, green: 0.45, blue: 0.12, alpha: 1)
        case .sporeCloud: UIColor(red: 0.6, green: 0.3, blue: 0.8, alpha: 1)
        case .pollen: UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)
        case .mothDust: UIColor(red: 0.75, green: 0.7, blue: 0.95, alpha: 1)
        }
    }

    /// The motes drifting up out of a cloud.
    fileprivate var particleColors: (UIColor, UIColor) {
        switch self {
        case .pollen: (UIColor(red: 1, green: 0.9, blue: 0.35, alpha: 1), UIColor(red: 1, green: 0.6, blue: 0.75, alpha: 1))
        case .mothDust: (UIColor(red: 0.8, green: 0.75, blue: 1, alpha: 1), UIColor(red: 0.55, green: 0.9, blue: 1, alpha: 1))
        default: (UIColor(red: 0.7, green: 0.3, blue: 0.9, alpha: 1), UIColor(red: 0.55, green: 0.9, blue: 0.4, alpha: 1))
        }
    }
}
