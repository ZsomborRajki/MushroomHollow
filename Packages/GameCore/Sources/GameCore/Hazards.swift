public enum HazardKind: String, Codable, Sendable {
    /// Left behind by slugs; slows players who walk through it.
    case slime
    /// Spun by weaver spiders as they chase; slows like slime.
    case web
    /// Dropped by ember newts as they chase; burns.
    case embers
    /// Released by spore beasts and grumblecaps; poisons players inside.
    case sporeCloud
    /// Shaken loose by thornroses; stings.
    case pollen
    /// Beaten off a dusk moth's wings; stings.
    case mothDust

    /// Walking through it halves your speed.
    public var slows: Bool {
        switch self {
        case .slime, .web: true
        case .embers, .sporeCloud, .pollen, .mothDust: false
        }
    }

    /// Clouds billow around their mob; the rest lie flat on the ground.
    public var isCloud: Bool {
        switch self {
        case .sporeCloud, .pollen, .mothDust: true
        case .slime, .web, .embers: false
        }
    }

    var radius: Float {
        switch self {
        case .slime: 0.9
        case .web: 1.1
        case .embers: 0.8
        case .sporeCloud: 2.8
        case .pollen: 3
        case .mothDust: 2.6
        }
    }

    var seconds: Float {
        switch self {
        case .slime: 6
        case .web: 7
        case .embers: 3
        case .sporeCloud, .pollen: 5
        case .mothDust: 4
        }
    }

    /// Damage per second inside it, as a fraction of its owner's attack.
    var damageFraction: Float {
        switch self {
        case .slime, .web: 0
        case .embers: 0.25
        case .pollen: 0.35
        case .sporeCloud: 0.4
        case .mothDust: 0.45
        }
    }
}

struct Hazard: Codable, Sendable {
    let id: UInt32
    let kind: HazardKind
    let position: Vec2
    let radius: Float
    let totalTicks: Int
    var ticksLeft: Int
    let owner: EntityID
    let damagePerSecond: Int
}

public struct HazardSnapshot: Codable, Sendable, Equatable, Identifiable {
    public let id: UInt32
    public let kind: HazardKind
    public let position: Vec2
    public let radius: Float
    /// 1 when fresh, 0 when about to vanish.
    public let remaining: Float
}

extension GameSimulation {
    static let slimeSlowFactor: Float = 0.5

    mutating func spawnHazard(_ kind: HazardKind, at position: Vec2, radius: Float, seconds: Float, owner: EntityID, damagePerSecond: Int = 0) {
        nextHazardID += 1
        let ticks = Self.ticks(seconds)
        hazards.append(Hazard(id: nextHazardID, kind: kind, position: position, radius: radius,
                              totalTicks: ticks, ticksLeft: ticks, owner: owner, damagePerSecond: damagePerSecond))
    }

    /// Leaves a hazard of `kind` at `owner`'s feet, sized and timed by the kind.
    mutating func spawnHazard(_ kind: HazardKind, from owner: WorldEntity) {
        spawnHazard(kind, at: owner.position.xz, radius: kind.radius, seconds: kind.seconds, owner: owner.id,
                    damagePerSecond: Int(Float(owner.stats.attack) * kind.damageFraction))
    }

    /// Wading through slime or webs.
    func isSlowed(_ entity: WorldEntity) -> Bool {
        entity.position.y < 0.5
            && hazards.contains { $0.kind.slows && $0.position.distance(to: entity.position.xz) < $0.radius + entity.radius * 0.5 }
    }

    mutating func stepHazards() {
        guard !hazards.isEmpty else { return }
        for i in hazards.indices {
            hazards[i].ticksLeft -= 1
            let hazard = hazards[i]
            // Poison pulses once a second.
            guard hazard.damagePerSecond > 0, hazard.ticksLeft % Self.tickRate == 0 else { continue }
            for id in order {
                guard var target = entities[id], target.kind == .player, target.stats.isAlive,
                      target.position.y < 1.5,
                      hazard.position.distance(to: target.position.xz) < hazard.radius + target.radius
                else { continue }
                let amount = max(1, hazard.damagePerSecond - target.stats.defense / 3)
                target.stats.hp = max(0, target.stats.hp - amount)
                target.combat.lastCombatTick = tick
                events.append(.damage(source: hazard.owner, target: id, amount: amount, isCritical: false, skill: nil))
                if !target.stats.isAlive { kill(&target, killer: hazard.owner) }
                entities[id] = target
            }
        }
        hazards.removeAll { $0.ticksLeft <= 0 }
    }

    var hazardSnapshots: [HazardSnapshot] {
        hazards.map {
            HazardSnapshot(id: $0.id, kind: $0.kind, position: $0.position, radius: $0.radius,
                           remaining: Float($0.ticksLeft) / Float(max(1, $0.totalTicks)))
        }
    }
}
