extension GameSimulation {
    static let criticalMultiplier: Float = 1.6

    /// Rolls and applies one hit. Handles aggro, death, and XP for the attacker.
    /// Only `blockable` hits (plain mob attacks, not charges or boss moves) can land on a shield.
    mutating func dealDamage(from attacker: inout WorldEntity, to targetID: EntityID, multiplier: Float, skill: SkillID?,
                             blockable: Bool = false) {
        guard var target = entities[targetID], target.stats.isAlive else { return }

        if blockable, target.stats.blockChance > 0, random.unit() < target.stats.blockChance {
            attacker.combat.lastCombatTick = tick
            target.combat.lastCombatTick = tick
            entities[targetID] = target
            events.append(.blocked(source: attacker.id, target: targetID))
            return
        }

        // A snail in its shell (or a curled-up pill bug) is very hard to hurt.
        var defense = Float(target.pose == .hiding ? target.stats.defense * 4 + 6 : target.stats.defense)
        defense *= Self.buffMultiplier(target) { if case let .defense(m) = $0 { m } else { nil } }
        let attack = Float(attacker.stats.attack) * Self.buffMultiplier(attacker) { if case let .attack(m) = $0 { m } else { nil } }
        var raw = attack * multiplier * random.float(in: 0.85...1.15) - defense * 0.6
        let isCritical = random.unit() < attacker.stats.critChance
        if isCritical { raw *= Self.criticalMultiplier }
        let amount = max(1, Int(raw.rounded()))

        target.stats.hp = max(0, target.stats.hp - amount)
        attacker.combat.lastCombatTick = tick
        target.combat.lastCombatTick = tick
        events.append(.damage(source: attacker.id, target: targetID, amount: amount, isCritical: isCritical, skill: skill))

        if attacker.kind == .player { target.brain?.boss?.damagers.insert(attacker.id) }
        if target.stats.isAlive {
            provoke(&target, by: attacker.id)
        } else {
            kill(&target, killer: attacker.id)
            if case let .mob(kind) = target.kind {
                if attacker.kind == .player {
                    let giant = target.brain?.isGiant == true
                    awardXP(to: &attacker, for: kind, giant: giant)
                    recordKill(of: kind, by: &attacker)
                    rollLoot(for: kind, giant: giant, ownedBy: attacker, at: target.position.xz)
                    if target.brain?.boss != nil { rewardBossParticipants(target, killer: &attacker) }
                }
                if let offspring = kind.splitsInto {
                    split(targetID, into: offspring, at: target.position.xz, angryAt: attacker.id)
                }
            }
        }
        entities[targetID] = target
    }

    /// Product of all active buff multipliers of one kind.
    static func buffMultiplier(_ entity: WorldEntity, _ pick: (BuffEffect) -> Float?) -> Float {
        (entity.player?.buffs ?? []).reduce(1) { $0 * (pick($1.effect) ?? 1) }
    }

    /// A mob that gets hit fights back (unless it's already busy with someone).
    func provoke(_ mob: inout WorldEntity, by attacker: EntityID) {
        guard var brain = mob.brain else { return }
        switch brain.state {
        case .idle, .wander, .returning: break
        case .engaged where mob.combat.target == nil: break
        default: return
        }
        mob.combat.target = attacker
        mob.combat.engaged = true
        brain.state = .engaged
        mob.brain = brain
    }

    mutating func kill(_ entity: inout WorldEntity, killer: EntityID?) {
        entity.stats.hp = 0
        entity.position.y = 0
        entity.isFlying = false
        entity.player?.buffs = []
        entity.velocity = .zero
        entity.moveIntent = .zero
        entity.combat = CombatState()
        entity.deathTicks = 0
        events.append(.died(entity: entity.id, killer: killer))
        if var data = entity.player {
            let lost = Progression.deathPenalty(level: entity.stats.level, xp: data.xp)
            if lost > 0 {
                data.xp -= lost
                entity.player = data
                events.append(.xpLost(player: entity.id, amount: lost))
            }
        }
    }

    mutating func awardXP(to player: inout WorldEntity, for kind: MobKind, giant: Bool = false) {
        let stats = kind.stats
        let amount = Progression.xpReward(baseXP: giant ? stats.xp * Giant.xpMultiplier : stats.xp,
                                          mobLevel: stats.level + (giant ? Giant.levelBonus : 0),
                                          playerLevel: player.stats.level)
        awardXP(to: &player, amount: amount)
    }

    mutating func awardXP(to player: inout WorldEntity, amount: Int) {
        guard var data = player.player else { return }
        data.xp += amount
        events.append(.xpGained(player: player.id, amount: amount))

        while player.stats.level < Progression.maxLevel, data.xp >= Progression.xpToNextLevel(player.stats.level) {
            data.xp -= Progression.xpToNextLevel(player.stats.level)
            player.stats = Self.playerStats(level: player.stats.level + 1, data: data)
            events.append(.levelUp(player: player.id, level: player.stats.level))
        }
        if player.stats.level >= Progression.maxLevel { data.xp = 0 }
        player.player = data
    }

    func castFailure(_ skill: SkillID, by caster: WorldEntity, on targetID: EntityID?) -> SkillFailure? {
        let definition = skill.definition
        if let required = definition.playerClass, caster.player?.playerClass != required { return .locked }
        if caster.stats.level < definition.requiredLevel { return .locked }
        if isAirborne(caster) { return .airborne }
        if (caster.player?.cooldowns[skill] ?? 0) > 0 { return .cooldown }
        if caster.stats.mp < definition.manaCost { return .notEnoughMana }
        if definition.needsTarget {
            guard let targetID, let target = entities[targetID], target.kind.isMob, target.stats.isAlive else {
                return .noTarget
            }
        }
        return nil
    }

    @discardableResult
    mutating func tryCast(_ skill: SkillID, by caster: inout WorldEntity, on targetID: EntityID?) -> Bool {
        if let failure = castFailure(skill, by: caster, on: targetID) {
            events.append(.skillFailed(caster: caster.id, skill: skill, reason: failure))
            return false
        }
        let definition = skill.definition
        caster.stats.mp -= definition.manaCost
        caster.player?.cooldowns[skill] = Self.ticks(definition.cooldown)
        caster.combat.attackTimer = max(caster.combat.attackTimer, Self.ticks(caster.stats.attackInterval * 0.5))
        events.append(.skillCast(caster: caster.id, skill: skill, target: targetID))
        // Intelligence makes every skill hit (and heal) harder.
        let power = caster.stats.skillPower

        switch definition.effect {
        case let .strike(multiplier):
            if let targetID {
                dealDamage(from: &caster, to: targetID, multiplier: multiplier * power, skill: skill)
            }

        case let .burst(radius, multiplier):
            for id in mobs(near: caster.position.xz, within: radius) {
                dealDamage(from: &caster, to: id, multiplier: multiplier * power, skill: skill)
            }
            caster.combat.lastCombatTick = tick

        case let .blast(radius, multiplier):
            guard let targetID, let center = entities[targetID]?.position.xz else { break }
            for id in mobs(near: center, within: radius) {
                dealDamage(from: &caster, to: id, multiplier: multiplier * power, skill: skill)
            }

        case let .volley(multiplier, extraTargets, radius):
            guard let targetID, let center = entities[targetID]?.position.xz else { break }
            let others = mobs(near: center, within: radius)
                .filter { $0 != targetID }
                .sorted { entities[$0]!.position.xz.distance(to: center) < entities[$1]!.position.xz.distance(to: center) }
            for id in [targetID] + others.prefix(extraTargets) {
                dealDamage(from: &caster, to: id, multiplier: multiplier * power, skill: skill)
            }

        case let .buff(effect, seconds):
            let ticks = Self.ticks(seconds)
            caster.player?.buffs.removeAll { $0.skill == skill }
            caster.player?.buffs.append(ActiveBuff(skill: skill, effect: effect, totalTicks: ticks, ticksLeft: ticks))

        case let .heal(fraction):
            let amount = min(caster.stats.maxHP - caster.stats.hp, Int(Float(caster.stats.maxHP) * fraction * power))
            caster.stats.hp += amount
            events.append(.heal(target: caster.id, amount: amount, skill: skill))
        }
        return true
    }

    /// Spore beasts burst into two angry sporelings when they die (puffweeds into pufflings).
    mutating func split(_ parent: EntityID, into kind: MobKind, at position: Vec2, angryAt attacker: EntityID) {
        events.append(.mobAbility(entity: parent, ability: .split))
        for side: Float in [-1, 1] {
            let spot = map.resolve(position + Vec2(side * 0.9, 0), radius: kind.radius)
            var offspring = WorldEntity(
                id: makeID(), kind: .mob(kind),
                position: Vec3(spot.x, 0, spot.y), yaw: random.float(in: -.pi...(.pi)),
                radius: kind.radius, moveSpeed: kind.wanderSpeed,
                stats: kind.stats.combatStats,
                brain: MobBrain(home: position, leashRadius: 10, spawnArea: nil, state: .engaged, aggressive: true))
            offspring.combat.target = attacker
            offspring.combat.engaged = true
            offspring.combat.attackTimer = Self.ticks(0.6)
            insert(offspring)
        }
    }

    /// Living mobs whose edge is within `radius` of `center`, in ID order.
    func mobs(near center: Vec2, within radius: Float) -> [EntityID] {
        order.filter { id in
            guard let e = entities[id], e.kind.isMob, e.stats.isAlive else { return false }
            return e.position.xz.distance(to: center) - e.radius <= radius
        }
    }
}
