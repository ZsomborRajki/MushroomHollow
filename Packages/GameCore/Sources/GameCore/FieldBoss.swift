import Foundation

/// Moldywarp, the Warren King: a field boss at the bottom of the Sunken Warren (Flyff's dungeon
/// bosses). It's always home and comes back ten minutes after it falls. It digs down and bursts
/// up under whoever is furthest away (a marked circle: step out of it), calls the warren's moles
/// at 60% and 30%, and fights faster once it has called twice. It can't be hurt underground.
extension GameSimulation {
    static let burrowFirstDelay: Float = 7
    public static let burrowRadius: Float = 3.5
    /// Sinking out of sight, before it starts to tunnel.
    static let burrowSinkSeconds: Float = 0.6
    /// Everything from digging down to bursting up.
    static let burrowSeconds: Float = 2.4
    static let burrowDamage: Float = 2.4
    static let burrowCooldown: Float = 11
    static let enragedBurrowCooldown: Float = 8

    mutating func stepWarrenKing(_ king: inout WorldEntity, brain: inout MobBrain) -> Bool {
        guard var boss = brain.boss else { return false }
        defer { brain.boss = boss }
        if boss.burrowTimer > 0 { boss.burrowTimer -= 1 }

        if case let .burrow(from, to, ticksLeft) = boss.action {
            let total = Self.ticks(Self.burrowSeconds), sink = Self.ticks(Self.burrowSinkSeconds)
            let elapsed = total - ticksLeft + 1
            if elapsed > sink {
                let progress = min(1, Float(elapsed - sink) / Float(max(1, total - sink)))
                king.position.xz = from + (to - from) * progress
            }
            king.velocity = .zero
            if ticksLeft > 1 {
                boss.action = .burrow(from: from, to: to, ticksLeft: ticksLeft - 1)
            } else {
                boss.action = .none
                king.position.xz = map.resolve(to, radius: king.radius)
                events.append(.mobAbility(entity: king.id, ability: .erupt))
                for id in players(within: Self.burrowRadius, of: to, below: 3) {
                    guard let victim = entities[id] else { continue }
                    dealDamage(from: &king, to: id, multiplier: Self.burrowDamage, skill: nil)
                    let away = victim.position.xz - to
                    knockBack(id, direction: away.length > 0.1 ? away.normalizedOrZero : AngleMath.direction(forYaw: king.yaw))
                }
            }
            return true
        }

        guard case .engaged = brain.state, let preyID = king.combat.target, let prey = entities[preyID], prey.stats.isAlive
        else { return false }
        let health = Float(king.stats.hp) / Float(king.stats.maxHP)

        // Calls the warren's moles twice, and fights faster after the second call.
        if (boss.summonsDone == 0 && health < 0.6) || (boss.summonsDone == 1 && health < 0.3) {
            boss.summonsDone += 1
            summon(.delverMole, count: boss.summonsDone == 1 ? 2 : 3, around: king.position.xz, angryAt: preyID, leash: 20)
            events.append(.mobAbility(entity: king.id, ability: .summon))
            if boss.summonsDone == 2, !boss.enraged {
                boss.enraged = true
                events.append(.mobAbility(entity: king.id, ability: .enrage))
            }
        }

        // Dig down and come up under whoever is furthest away (punishes standing back), inside the lair.
        if boss.burrowTimer <= 0 {
            let here = king.position.xz
            let victim = boss.damagers
                .compactMap { entities[$0] }
                .filter { $0.stats.isAlive && $0.position.y <= Self.reachableAltitude && $0.position.xz.distance(to: here) < 22 }
                .max { $0.position.xz.distance(to: here) < $1.position.xz.distance(to: here) }
                ?? prey
            var spot = victim.position.xz
            let fromHome = spot - brain.home
            if fromHome.length > brain.leashRadius { spot = brain.home + fromHome.normalizedOrZero * brain.leashRadius }
            boss.action = .burrow(from: here, to: map.resolve(spot, radius: king.radius), ticksLeft: Self.ticks(Self.burrowSeconds))
            boss.burrowTimer = Self.ticks((boss.enraged ? Self.enragedBurrowCooldown : Self.burrowCooldown) + Self.burrowSeconds)
            king.velocity = .zero
            events.append(.mobAbility(entity: king.id, ability: .burrow))
            return true
        }
        return false
    }
}
