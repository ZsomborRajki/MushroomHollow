public enum HazardKind: String, Codable, Sendable {
    /// Left behind by slugs; slows players who walk through it.
    case slime
    /// Released by spore beasts; poisons players inside.
    case sporeCloud
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

    func isInSlime(_ entity: WorldEntity) -> Bool {
        entity.position.y < 0.5
            && hazards.contains { $0.kind == .slime && $0.position.distance(to: entity.position.xz) < $0.radius + entity.radius * 0.5 }
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
