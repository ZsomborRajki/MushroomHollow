import Foundation

/// The authoritative, fixed-timestep game world. Deterministic for a given seed and
/// command stream. Offline it runs inside the app; online it will run on the server.
///
/// Behaviour lives in extensions: `PlayerLogic`, `MobAI`, `Combat`.
public struct GameSimulation: Sendable {
    public static let tickRate = 20
    public static let tickDuration: Float = 1 / Float(tickRate)

    public static let playerRadius: Float = 0.35
    public static let playerSpeed: Float = 5.0
    static let playerTurnRate: Float = 14 // rad/s
    static let mobTurnRate: Float = 6
    /// How long a dead mob's body stays before despawning.
    static let corpseTicks = ticks(1.5)

    /// A full day/night cycle, in ticks (12 real minutes).
    public static let dayLengthTicks: UInt64 = 12 * 60 * UInt64(tickRate)

    public let map: WorldMap
    public internal(set) var tick: UInt64 = 0
    /// Time of day when the world started (0 = midnight, 0.5 = noon).
    public let startTimeOfDay: Float

    var entities: [EntityID: WorldEntity] = [:]
    /// Sorted IDs, so iteration order is deterministic (dictionary order is not).
    var order: [EntityID] = []
    var nextID: UInt32 = 1
    var random: SeededRandom
    var pendingCommands: [(EntityID, PlayerCommand)] = []
    var respawnQueue: [PendingRespawn] = []
    var hazards: [Hazard] = []
    var nextHazardID: UInt32 = 0
    var drops: [GroundDrop] = []
    var nextDropID: UInt32 = 0
    var bossID: EntityID?
    var lastBossNight: Int?
    /// Events produced by the tick in progress.
    var events: [WorldEvent] = []

    struct PendingRespawn: Sendable {
        let areaIndex: Int
        var ticksLeft: Int
        var giant = false
    }

    public init(map: WorldMap = .mushroomHollow, seed: UInt64, startTimeOfDay: Float = 0.32) {
        self.map = map
        self.startTimeOfDay = startTimeOfDay
        self.random = SeededRandom(seed: seed)
        for placement in map.npcs {
            insert(WorldEntity(
                id: makeID(), kind: .npc(placement.id),
                position: Vec3(placement.position.x, 0, placement.position.y), yaw: placement.yaw,
                radius: 0.45, moveSpeed: 0,
                stats: CombatStats(level: 0, maxHP: 1, hp: 1, maxMP: 0, mp: 0, attack: 0, defense: 0,
                                   attackInterval: 1, reach: 0)))
        }
        for (index, area) in map.mobSpawns.enumerated() {
            for _ in 0..<area.count {
                spawnMob(areaIndex: index)
            }
            if area.kind.hasGiant { spawnMob(areaIndex: index, giant: true) }
        }
    }

    static func ticks(_ seconds: Float) -> Int {
        Int((seconds * Float(tickRate)).rounded())
    }

    // MARK: - Queries

    public func entity(_ id: EntityID) -> WorldEntity? { entities[id] }

    public var entityCount: Int { order.count }

    /// 0 = midnight, 0.25 = dawn, 0.5 = noon, 0.75 = dusk. Driven by ticks, so every client agrees.
    public var timeOfDay: Float {
        let progress = Double(tick % Self.dayLengthTicks) / Double(Self.dayLengthTicks)
        return Float((Double(startTimeOfDay) + progress).truncatingRemainder(dividingBy: 1))
    }

    public var isNight: Bool { timeOfDay < 0.22 || timeOfDay > 0.8 }

    public func snapshot(for viewer: EntityID? = nil) -> WorldSnapshot {
        WorldSnapshot(
            tick: tick,
            entities: order.compactMap { id in
                guard let e = entities[id] else { return nil }
                return EntitySnapshot(
                    id: id, kind: e.kind, position: e.position, yaw: e.yaw, isMoving: e.isMoving,
                    pose: e.pose, level: e.stats.level, hp: e.stats.hp, maxHP: e.stats.maxHP,
                    target: e.combat.engaged ? e.combat.target : nil,
                    gear: EquipSlot.allCases.compactMap { e.player?.equipment[$0]?.item },
                    playerClass: e.player?.playerClass, isFlying: e.isFlying,
                    isAggressive: e.brain?.aggressive ?? false,
                    isGiant: e.brain?.isGiant ?? false)
            },
            hazards: hazardSnapshots,
            drops: drops.filter { viewer == nil || $0.owner == viewer }.map {
                GroundDropSnapshot(id: $0.id, position: $0.position, kind: $0.kind)
            },
            viewer: viewer.flatMap(playerStatus),
            timeOfDay: timeOfDay,
            telegraphs: telegraphSnapshots,
            pets: petSnapshots
        )
    }

    public func playerStatus(_ id: EntityID) -> PlayerStatus? {
        guard let e = entities[id], let data = e.player else { return nil }
        let skills = availableSkills(for: e).map { skill in
            let definition = skill.definition
            return SkillStatus(
                id: skill,
                isUnlocked: e.stats.level >= definition.requiredLevel,
                canAfford: e.stats.mp >= definition.manaCost,
                cooldownRemaining: Float(data.cooldowns[skill] ?? 0) * Self.tickDuration,
                cooldownTotal: definition.cooldown)
        }
        return PlayerStatus(
            id: id, stats: e.stats, xp: data.xp,
            xpToNextLevel: Progression.xpToNextLevel(e.stats.level),
            target: e.combat.target, isEngaged: e.combat.engaged, skills: skills,
            caps: data.caps, inventory: data.inventory, equipment: data.equipment,
            quests: QuestID.allCases.map { QuestStatus(id: $0, state: questState($0, for: e)) },
            itemCooldown: Float(data.itemCooldown) * Self.tickDuration,
            isSlowed: isSlowed(e),
            playerClass: data.playerClass,
            buffs: data.buffs.map {
                BuffStatus(skill: $0.skill, remaining: Float($0.ticksLeft) * Self.tickDuration,
                           total: Float($0.totalTicks) * Self.tickDuration)
            },
            canFly: data.inventory.count(of: .dandelionSeed) > 0 && e.stats.level >= ItemID.dandelionSeed.definition.requiredLevel,
            isFlying: e.isFlying,
            altitude: e.position.y,
            pet: petStatus(data.pet),
            attributes: data.attributes,
            unspentStatPoints: data.attributes.unspent(atLevel: e.stats.level))
    }

    /// The three base skills, plus the class's two once a class is chosen.
    func availableSkills(for player: WorldEntity) -> [SkillID] {
        SkillID.baseSkills + (player.player?.playerClass?.definition.skills ?? [])
    }

    // MARK: - Mutations

    public mutating func removeEntity(_ id: EntityID) {
        entities[id] = nil
        order.removeAll { $0 == id }
    }

    /// Commands are applied at the start of the next tick, in arrival order.
    public mutating func enqueue(_ command: PlayerCommand, from player: EntityID) {
        pendingCommands.append((player, command))
    }

    /// Advances one tick and returns what happened during it.
    @discardableResult
    public mutating func step() -> [WorldEvent] {
        tick += 1
        events.removeAll(keepingCapacity: true)
        applyCommands()
        for id in order {
            guard var entity = entities[id] else { continue }
            switch entity.kind {
            case .player: stepPlayer(&entity)
            case .mob: stepMob(&entity)
            case .npc: continue
            }
            entities[id] = entity
        }
        separateMobs()
        stepPets()
        stepHazards()
        stepDrops()
        removeCorpses()
        processRespawns()
        updateWorldBoss()
        return events
    }

    // MARK: - Internals

    mutating func makeID() -> EntityID {
        defer { nextID += 1 }
        return EntityID(nextID)
    }

    mutating func insert(_ entity: WorldEntity) {
        entities[entity.id] = entity
        order.append(entity.id)
        order.sort()
    }

    /// Debug / game-master tool: instantly moves an entity (collision-resolved).
    public mutating func teleport(_ id: EntityID, to point: Vec2) {
        guard let radius = entities[id]?.radius else { return }
        entities[id]?.position.xz = map.resolve(point, radius: radius)
    }

    /// How far a hunting-ground mob chases from its own spot before giving up (plus `leashSlack`).
    static let mobLeashRadius: Float = 12
    /// How far it strolls from its spot when nobody's around.
    static let mobWanderRadius: Float = 5
    /// Roughly one mob in this many comes after players on its own; the rest only fight back.
    static let aggressiveShare = 5

    /// Spawns a mob somewhere in its area, as far from everyone else as a few tries can find,
    /// so hunting grounds stay spread out and fights are usually one on one.
    /// Only about one in `aggressiveShare` of an area's mobs is aggressive (never its Giant).
    mutating func spawnMob(areaIndex: Int, giant: Bool = false) {
        let area = map.mobSpawns[areaIndex]
        let kind = area.kind
        let radius = kind.radius * (giant ? Giant.sizeScale : 1)
        var best: (spot: Vec2, room: Float)?
        for _ in 0..<12 {
            let candidate = random.point(inDiscAt: area.center, radius: area.radius)
            guard !map.isBlocked(candidate, radius: radius + 0.3) else { continue }
            let room = distanceToNearestCreature(from: candidate)
            if best == nil || room > best!.room { best = (candidate, room) }
        }
        let spot = map.resolve(best?.spot ?? area.center, radius: radius)
        // Each pack keeps its quota of aggressive mobs: when one dies, the next to respawn takes its place.
        let quota = kind.stats.aggroRadius > 0 && !giant ? max(1, area.count / Self.aggressiveShare) : 0
        let aggressiveNow = order.count { id in
            guard let e = entities[id], e.stats.isAlive, let brain = e.brain else { return false }
            return brain.spawnArea == areaIndex && brain.aggressive
        }
        insert(WorldEntity(
            id: makeID(),
            kind: .mob(kind),
            position: Vec3(spot.x, 0, spot.y),
            yaw: random.float(in: -.pi...(.pi)),
            radius: radius,
            moveSpeed: kind.wanderSpeed,
            stats: giant ? Giant.stats(for: kind) : kind.stats.combatStats,
            brain: MobBrain(
                home: spot,
                leashRadius: Self.mobLeashRadius,
                wanderRadius: Self.mobWanderRadius,
                spawnArea: areaIndex,
                state: .idle(ticksLeft: random.int(in: 0...(Self.tickRate * 4))),
                aggressive: aggressiveNow < quota,
                isGiant: giant
            )
        ))
    }

    /// Distance to the closest living mob or player.
    private func distanceToNearestCreature(from point: Vec2) -> Float {
        var nearest = Float.greatestFiniteMagnitude
        for id in order {
            guard let e = entities[id], e.stats.isAlive else { continue }
            if case .npc = e.kind { continue }
            nearest = min(nearest, e.position.xz.distance(to: point))
        }
        return nearest
    }

    private mutating func applyCommands() {
        for (id, command) in pendingCommands {
            guard var entity = entities[id], entity.kind == .player else { continue }
            apply(command, to: &entity)
            entities[id] = entity
        }
        pendingCommands.removeAll(keepingCapacity: true)
    }

    private mutating func removeCorpses() {
        let expired = order.filter { id in
            guard let e = entities[id] else { return false }
            return e.kind.isMob && !e.stats.isAlive && e.deathTicks >= Self.corpseTicks
        }
        for id in expired {
            if let brain = entities[id]?.brain, let area = brain.spawnArea, case let .mob(kind) = entities[id]?.kind {
                let seconds = brain.isGiant ? Giant.respawnSeconds : kind.stats.respawnSeconds
                respawnQueue.append(PendingRespawn(areaIndex: area, ticksLeft: Self.ticks(seconds), giant: brain.isGiant))
            }
            removeEntity(id)
        }
    }

    private mutating func processRespawns() {
        guard !respawnQueue.isEmpty else { return }
        for i in respawnQueue.indices { respawnQueue[i].ticksLeft -= 1 }
        let ready = respawnQueue.filter { $0.ticksLeft <= 0 }
        respawnQueue.removeAll { $0.ticksLeft <= 0 }
        for respawn in ready { spawnMob(areaIndex: respawn.areaIndex, giant: respawn.giant) }
    }

    /// Mobs shouldn't stack on top of each other: push overlapping pairs apart.
    private mutating func separateMobs() {
        // The owl is too big to shove around.
        let mobs = order.filter { entities[$0].map { $0.kind.isMob && $0.stats.isAlive && $0.kind != .mob(.owl) } ?? false }
        guard mobs.count > 1 else { return }
        var positions = mobs.map { entities[$0]!.position.xz }
        let radii = mobs.map { entities[$0]!.radius }
        var moved = Set<Int>()
        for i in 0..<mobs.count {
            for j in (i + 1)..<mobs.count {
                let offset = positions[j] - positions[i]
                let distance = offset.length
                let minimum = (radii[i] + radii[j]) * 0.9
                guard distance < minimum else { continue }
                // Coincident mobs split along a direction derived from their IDs (deterministic).
                let normal = distance > 1e-4 ? offset / distance : AngleMath.direction(forYaw: Float(mobs[i].rawValue))
                let push = normal * (minimum - distance) * 0.5
                positions[i] -= push
                positions[j] += push
                moved.insert(i)
                moved.insert(j)
            }
        }
        for i in moved {
            entities[mobs[i]]?.position.xz = map.resolve(positions[i], radius: radii[i])
        }
    }

    /// Moves along the ground, sliding around colliders, and records the actual velocity.
    func move(_ entity: inout WorldEntity, velocity: Vec2) {
        let dt = Self.tickDuration
        let start = entity.position.xz
        let resolved = velocity == .zero ? start : map.resolve(start + velocity * dt, radius: entity.radius, altitude: entity.position.y)
        entity.position.xz = resolved
        let actual = (resolved - start) / dt
        entity.velocity = Vec3(actual.x, 0, actual.y)
    }

    func turn(_ entity: inout WorldEntity, toward direction: Vec2, rate: Float) {
        guard direction.length > 1e-4 else { return }
        entity.yaw = AngleMath.moveToward(entity.yaw, AngleMath.yaw(facing: direction), maxDelta: rate * Self.tickDuration)
    }

    /// Edge-to-edge distance on the ground plane.
    func gap(_ a: WorldEntity, _ b: WorldEntity) -> Float {
        a.position.xz.distance(to: b.position.xz) - a.radius - b.radius
    }
}
