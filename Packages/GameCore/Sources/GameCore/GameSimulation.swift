import Foundation

/// The authoritative, fixed-timestep game world. Deterministic for a given seed and
/// command stream. Offline it runs inside the app; online it will run on the server.
public struct GameSimulation: Sendable {
    public static let tickRate = 20
    public static let tickDuration: Float = 1 / Float(tickRate)

    public static let playerRadius: Float = 0.35
    public static let playerSpeed: Float = 5.0
    static let playerTurnRate: Float = 14 // rad/s
    static let mobTurnRate: Float = 5

    public let map: WorldMap
    public private(set) var tick: UInt64 = 0

    private var entities: [EntityID: WorldEntity] = [:]
    /// Sorted IDs, so iteration order is deterministic (dictionary order is not).
    private var order: [EntityID] = []
    private var nextID: UInt32 = 1
    private var random: SeededRandom
    private var pendingCommands: [(EntityID, PlayerCommand)] = []

    public init(map: WorldMap = .mushroomHollow, seed: UInt64) {
        self.map = map
        self.random = SeededRandom(seed: seed)
        for area in map.mobSpawns {
            for _ in 0..<area.count {
                spawnMob(area.kind, in: area)
            }
        }
    }

    // MARK: - Queries

    public func entity(_ id: EntityID) -> WorldEntity? { entities[id] }

    public var entityCount: Int { order.count }

    public func snapshot() -> WorldSnapshot {
        WorldSnapshot(
            tick: tick,
            entities: order.compactMap { id in
                guard let e = entities[id] else { return nil }
                return EntitySnapshot(id: id, kind: e.kind, position: e.position, yaw: e.yaw, isMoving: e.isMoving)
            }
        )
    }

    // MARK: - Mutations

    @discardableResult
    public mutating func spawnPlayer() -> EntityID {
        let id = makeID()
        let spawn = map.resolve(map.playerSpawn, radius: Self.playerRadius)
        insert(WorldEntity(
            id: id,
            kind: .player,
            position: Vec3(spawn.x, 0, spawn.y),
            yaw: AngleMath.yaw(facing: -spawn), // face the trunk
            radius: Self.playerRadius,
            moveSpeed: Self.playerSpeed
        ))
        return id
    }

    public mutating func removeEntity(_ id: EntityID) {
        entities[id] = nil
        order.removeAll { $0 == id }
    }

    /// Commands are applied at the start of the next tick, in arrival order.
    public mutating func enqueue(_ command: PlayerCommand, from player: EntityID) {
        pendingCommands.append((player, command))
    }

    public mutating func step() {
        tick += 1
        applyCommands()
        let dt = Self.tickDuration
        for id in order {
            guard var entity = entities[id] else { continue }
            switch entity.kind {
            case .player:
                stepPlayer(&entity, dt: dt)
            case .mob:
                stepMob(&entity, dt: dt)
            }
            entities[id] = entity
        }
    }

    // MARK: - Internals

    private mutating func makeID() -> EntityID {
        defer { nextID += 1 }
        return EntityID(nextID)
    }

    private mutating func insert(_ entity: WorldEntity) {
        entities[entity.id] = entity
        order.append(entity.id)
        order.sort()
    }

    private mutating func spawnMob(_ kind: MobKind, in area: MobSpawnArea) {
        var spot = area.center
        for _ in 0..<16 {
            let candidate = random.point(inDiscAt: area.center, radius: area.radius)
            if !map.isBlocked(candidate, radius: kind.radius) {
                spot = candidate
                break
            }
        }
        spot = map.resolve(spot, radius: kind.radius)
        insert(WorldEntity(
            id: makeID(),
            kind: .mob(kind),
            position: Vec3(spot.x, 0, spot.y),
            yaw: random.float(in: -.pi...(.pi)),
            radius: kind.radius,
            moveSpeed: kind.wanderSpeed,
            brain: MobBrain(
                home: area.center,
                leashRadius: area.radius,
                state: .idle(ticksLeft: random.int(in: 0...(Self.tickRate * 4)))
            )
        ))
    }

    private mutating func applyCommands() {
        for (id, command) in pendingCommands {
            guard var entity = entities[id], entity.kind == .player else { continue }
            switch command {
            case let .move(direction):
                entity.moveIntent = direction.clampedLength(1)
            }
            entities[id] = entity
        }
        pendingCommands.removeAll(keepingCapacity: true)
    }

    private func stepPlayer(_ entity: inout WorldEntity, dt: Float) {
        let intent = entity.moveIntent
        let velocity = intent * entity.moveSpeed
        if intent.length > 0.05 {
            entity.yaw = AngleMath.moveToward(
                entity.yaw, AngleMath.yaw(facing: intent), maxDelta: Self.playerTurnRate * dt)
        }
        move(&entity, velocity: velocity, dt: dt)
    }

    private mutating func stepMob(_ entity: inout WorldEntity, dt: Float) {
        guard var brain = entity.brain else { return }
        var velocity = Vec2.zero

        switch brain.state {
        case let .idle(ticksLeft):
            if ticksLeft > 0 {
                brain.state = .idle(ticksLeft: ticksLeft - 1)
            } else {
                brain.state = .wander(target: pickWanderTarget(for: entity, brain: brain), stuckTicks: 0)
            }

        case let .wander(target, stuckTicks):
            let toTarget = target - entity.position.xz
            if toTarget.length < 0.3 || stuckTicks > Self.tickRate {
                brain.state = .idle(ticksLeft: random.int(in: (Self.tickRate * 2)...(Self.tickRate * 6)))
            } else {
                let direction = toTarget.normalizedOrZero
                velocity = direction * entity.moveSpeed
                entity.yaw = AngleMath.moveToward(
                    entity.yaw, AngleMath.yaw(facing: direction), maxDelta: Self.mobTurnRate * dt)
                let before = entity.position.xz
                move(&entity, velocity: velocity, dt: dt)
                let progress = entity.position.xz.distance(to: before)
                let stuck = progress < entity.moveSpeed * dt * 0.3
                brain.state = .wander(target: target, stuckTicks: stuck ? stuckTicks + 1 : 0)
                entity.brain = brain
                return
            }
        }

        entity.brain = brain
        move(&entity, velocity: velocity, dt: dt)
    }

    private mutating func pickWanderTarget(for entity: WorldEntity, brain: MobBrain) -> Vec2 {
        for _ in 0..<6 {
            let candidate = random.point(inDiscAt: brain.home, radius: brain.leashRadius)
            if !map.isBlocked(candidate, radius: entity.radius) {
                return candidate
            }
        }
        return brain.home
    }

    private func move(_ entity: inout WorldEntity, velocity: Vec2, dt: Float) {
        let start = entity.position.xz
        let resolved = map.resolve(start + velocity * dt, radius: entity.radius)
        entity.position.xz = resolved
        let actual = (resolved - start) / dt
        entity.velocity = Vec3(actual.x, 0, actual.y)
    }
}
