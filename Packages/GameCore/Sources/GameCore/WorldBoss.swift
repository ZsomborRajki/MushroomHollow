import Foundation

/// The Hollow Owl: a world boss that comes out once per night.
extension GameSimulation {
    // Swoop: a marked circle, a rise, a dive.
    public static let swoopRadius: Float = 3.2
    static let swoopWindup: Float = 1.3
    static let swoopDive: Float = 0.45
    static let swoopHeight: Float = 8
    static let swoopDamage: Float = 2.4
    // Wing gust: a cone in front, damage plus knockback.
    public static let gustRange: Float = 9
    public static let gustHalfAngle: Float = 0.7
    static let gustWindup: Float = 1.0
    static let gustDamage: Float = 1.2
    static let knockbackSpeed: Float = 14
    static let knockbackSeconds: Float = 0.4
    /// The owl can follow flyers into the air, up to here.
    static let owlCeiling: Float = 20

    /// Which night it is. A night runs dusk to dawn across midnight, so shift by a quarter day.
    var nightIndex: Int {
        Int((Double(startTimeOfDay) + Double(tick) / Double(Self.dayLengthTicks) + 0.25).rounded(.down))
    }

    public var worldBoss: EntityID? { bossID }

    /// Spawns at nightfall (once per night); leaves at dawn unless mid-fight.
    mutating func updateWorldBoss() {
        guard let arena = map.bossArena else { return }
        if let id = bossID {
            guard let boss = entities[id] else {
                bossID = nil // corpse cleared
                return
            }
            if boss.stats.isAlive, !isNight, boss.combat.target == nil {
                events.append(.worldBossDeparted(entity: id))
                removeEntity(id)
                bossID = nil
            }
        } else if isNight, lastBossNight != nightIndex {
            spawnWorldBoss(arena)
        }
    }

    /// Debug / game-master tool: bring the boss out now.
    public mutating func summonWorldBoss() {
        guard bossID == nil, let arena = map.bossArena else { return }
        spawnWorldBoss(arena)
    }

    private mutating func spawnWorldBoss(_ arena: BossArena) {
        let kind = arena.kind
        let spot = map.resolve(arena.perch, radius: kind.radius)
        let id = makeID()
        insert(WorldEntity(
            id: id, kind: .mob(kind),
            position: Vec3(spot.x, 0, spot.y),
            yaw: AngleMath.yaw(facing: arena.center - spot),
            radius: kind.radius, moveSpeed: kind.wanderSpeed,
            stats: kind.stats.combatStats,
            brain: MobBrain(home: arena.center, leashRadius: arena.radius, spawnArea: nil,
                            state: .idle(ticksLeft: Self.ticks(3)), aggressive: true,
                            boss: BossBrain(swoopTimer: Self.ticks(4), gustTimer: Self.ticks(6)))))
        bossID = id
        lastBossNight = nightIndex
        events.append(.worldBossSpawned(entity: id, kind: kind))
    }

    // MARK: - The fight

    /// Runs a boss's scripted moves. Returns true when a move used up this tick.
    mutating func stepBoss(_ mob: inout WorldEntity, brain: inout MobBrain) -> Bool {
        if case .mob(.moldywarp) = mob.kind { return stepWarrenKing(&mob, brain: &brain) }
        return stepOwl(&mob, brain: &brain)
    }

    /// The owl: swoops, wing gusts, and mice.
    private mutating func stepOwl(_ owl: inout WorldEntity, brain: inout MobBrain) -> Bool {
        guard var boss = brain.boss else { return false }
        defer { brain.boss = boss }
        if boss.swoopTimer > 0 { boss.swoopTimer -= 1 }
        if boss.gustTimer > 0 { boss.gustTimer -= 1 }

        switch boss.action {
        case let .swoopWindup(target, ticksLeft):
            move(&owl, velocity: .zero)
            turn(&owl, toward: target - owl.position.xz, rate: Self.mobTurnRate * 2)
            owl.position.y = min(Self.swoopHeight, owl.position.y + Self.swoopHeight / Float(Self.ticks(Self.swoopWindup)))
            boss.action = ticksLeft > 1
                ? .swoopWindup(target: target, ticksLeft: ticksLeft - 1)
                : .swoopDive(from: owl.position.xz, to: target, ticksLeft: Self.ticks(Self.swoopDive))
            return true

        case let .swoopDive(from, to, ticksLeft):
            let total = Float(Self.ticks(Self.swoopDive))
            let progress = 1 - Float(ticksLeft - 1) / total
            owl.position.xz = map.resolve(from + (to - from) * progress, radius: owl.radius, altitude: owl.position.y)
            owl.position.y = Self.swoopHeight * (1 - progress)
            if ticksLeft > 1 {
                boss.action = .swoopDive(from: from, to: to, ticksLeft: ticksLeft - 1)
            } else {
                owl.position.y = 0
                boss.action = .none
                events.append(.mobAbility(entity: owl.id, ability: .swoopImpact))
                for id in players(within: Self.swoopRadius, of: to, below: 3) {
                    dealDamage(from: &owl, to: id, multiplier: Self.swoopDamage, skill: nil)
                }
            }
            return true

        case let .gustWindup(direction, ticksLeft):
            move(&owl, velocity: .zero)
            turn(&owl, toward: direction, rate: Self.mobTurnRate * 3)
            if ticksLeft > 1 {
                boss.action = .gustWindup(direction: direction, ticksLeft: ticksLeft - 1)
            } else {
                boss.action = .none
                for id in players(inConeFrom: owl.position.xz, direction: direction) {
                    dealDamage(from: &owl, to: id, multiplier: Self.gustDamage, skill: nil)
                    knockBack(id, direction: direction)
                }
            }
            return true

        case .none, .burrow:
            break
        }

        // Only plan new moves mid-fight.
        guard case .engaged = brain.state, let preyID = owl.combat.target, let prey = entities[preyID], prey.stats.isAlive
        else {
            owl.position.y = max(0, owl.position.y - 4 * Self.tickDuration) // settle back down
            return false
        }
        let health = Float(owl.stats.hp) / Float(owl.stats.maxHP)

        // Phase 3: call for help (twice) and enrage.
        if (boss.summonsDone == 0 && health < 0.3) || (boss.summonsDone == 1 && health < 0.15) {
            boss.summonsDone += 1
            summonMice(count: boss.summonsDone == 1 ? 4 : 3, around: owl.position.xz, angryAt: preyID)
            events.append(.mobAbility(entity: owl.id, ability: .summon))
            if !boss.enraged {
                boss.enraged = true
                events.append(.mobAbility(entity: owl.id, ability: .enrage))
            }
        }

        let toPrey = prey.position.xz - owl.position.xz
        // Phase 2: wing gust at close range. (Right after a swoop the owl may be standing
        // on its prey; then it gusts the way it's facing.)
        if health < 0.6, boss.gustTimer <= 0, gap(owl, prey) < Self.gustRange - 1 {
            let direction = toPrey.length > 0.1 ? toPrey.normalizedOrZero : AngleMath.direction(forYaw: owl.yaw)
            boss.action = .gustWindup(direction: direction, ticksLeft: Self.ticks(Self.gustWindup))
            boss.gustTimer = Self.ticks(boss.enraged ? 7 : 9)
            events.append(.mobAbility(entity: owl.id, ability: .gust))
            return true
        }
        // Every phase: swoop onto someone. Prefer whoever is furthest away (punishes kiting).
        if boss.swoopTimer <= 0 {
            let victim = boss.damagers
                .compactMap { entities[$0] }
                .filter { $0.stats.isAlive && $0.position.xz.distance(to: owl.position.xz) < 22 }
                .max { $0.position.xz.distance(to: owl.position.xz) < $1.position.xz.distance(to: owl.position.xz) }
                ?? prey
            boss.action = .swoopWindup(target: victim.position.xz, ticksLeft: Self.ticks(Self.swoopWindup))
            boss.swoopTimer = Self.ticks(boss.enraged ? 7 : 10)
            events.append(.mobAbility(entity: owl.id, ability: .swoop))
            return true
        }

        // Follow flyers up (and come back down for walkers).
        let targetHeight = min(prey.position.y, Self.owlCeiling)
        let climb = max(-4 * Self.tickDuration, min(4 * Self.tickDuration, targetHeight - owl.position.y))
        owl.position.y = max(0, owl.position.y + climb)
        return false
    }

    /// When the boss dies, everyone who fought it gets XP, loot, and quest credit.
    mutating func rewardBossParticipants(_ boss: WorldEntity, killer: inout WorldEntity) {
        guard case let .mob(kind) = boss.kind, let damagers = boss.brain?.boss?.damagers else { return }
        let participants = damagers.sorted()
        for id in participants where id != killer.id {
            guard var player = entities[id], player.stats.isAlive else { continue }
            awardXP(to: &player, for: kind)
            recordKill(of: kind, by: &player)
            rollLoot(for: kind, ownedBy: player, at: boss.position.xz)
            entities[id] = player
        }
        events.append(kind.isFieldBoss ? .fieldBossDefeated(entity: boss.id, kind: kind, participants: participants)
                                       : .worldBossDefeated(entity: boss.id, participants: participants))
    }

    // MARK: - Helpers

    private mutating func summonMice(count: Int, around center: Vec2, angryAt target: EntityID) {
        summon(.mouse, count: count, around: center, angryAt: target)
    }

    /// Calls `count` of `kind` to a boss's side, already angry at `target`. They don't respawn.
    mutating func summon(_ kind: MobKind, count: Int, around center: Vec2, angryAt target: EntityID, leash: Float = 16) {
        for i in 0..<count {
            let angle = Float(i) / Float(count) * 2 * .pi + random.float(in: 0...1)
            let spot = map.resolve(center + AngleMath.direction(forYaw: angle) * 4, radius: kind.radius)
            var helper = WorldEntity(
                id: makeID(), kind: .mob(kind),
                position: Vec3(spot.x, 0, spot.y), yaw: angle,
                radius: kind.radius, moveSpeed: kind.wanderSpeed,
                stats: kind.stats.combatStats,
                brain: MobBrain(home: center, leashRadius: leash, spawnArea: nil, state: .engaged, aggressive: true))
            helper.combat.target = target
            helper.combat.engaged = true
            insert(helper)
        }
    }

    func players(within radius: Float, of point: Vec2, below height: Float) -> [EntityID] {
        order.filter { id in
            guard let e = entities[id], e.kind == .player, e.stats.isAlive, e.position.y < height else { return false }
            return e.position.xz.distance(to: point) < radius + e.radius
        }
    }

    private func players(inConeFrom origin: Vec2, direction: Vec2) -> [EntityID] {
        order.filter { id in
            guard let e = entities[id], e.kind == .player, e.stats.isAlive else { return false }
            let offset = e.position.xz - origin
            let distance = offset.length
            guard distance < Self.gustRange + e.radius, distance > 1e-3 else { return distance <= 1e-3 }
            let cosine = ((offset / distance) * direction).sum()
            return cosine >= cos(Self.gustHalfAngle)
        }
    }

    mutating func knockBack(_ id: EntityID, direction: Vec2) {
        guard var player = entities[id] else { return }
        player.knockback = direction * Self.knockbackSpeed
        player.knockbackTicks = Self.ticks(Self.knockbackSeconds)
        player.combat.engaged = false
        player.combat.queuedSkill = nil
        entities[id] = player
        events.append(.knockedBack(entity: id))
    }

    /// Danger markers for every boss mid-move.
    var telegraphSnapshots: [TelegraphSnapshot] {
        order.flatMap { id -> [TelegraphSnapshot] in
            guard let boss = entities[id], let action = boss.brain?.boss?.action else { return [] }
            return telegraphs(of: boss, action)
        }
    }

    private func telegraphs(of owl: WorldEntity, _ action: BossBrain.Action) -> [TelegraphSnapshot] {
        let id = owl.id
        switch action {
        case let .swoopWindup(target, ticksLeft):
            let total = Float(Self.ticks(Self.swoopWindup) + Self.ticks(Self.swoopDive))
            return [TelegraphSnapshot(source: id, position: target, shape: .circle(radius: Self.swoopRadius),
                                      progress: 1 - Float(ticksLeft + Self.ticks(Self.swoopDive)) / total)]
        case let .swoopDive(_, to, ticksLeft):
            let total = Float(Self.ticks(Self.swoopWindup) + Self.ticks(Self.swoopDive))
            return [TelegraphSnapshot(source: id, position: to, shape: .circle(radius: Self.swoopRadius),
                                      progress: 1 - Float(ticksLeft) / total)]
        case let .gustWindup(direction, ticksLeft):
            return [TelegraphSnapshot(source: id, position: owl.position.xz,
                                      shape: .cone(direction: direction, radius: Self.gustRange, halfAngle: Self.gustHalfAngle),
                                      progress: 1 - Float(ticksLeft) / Float(Self.ticks(Self.gustWindup)))]
        case let .burrow(_, to, ticksLeft):
            let total = Float(Self.ticks(Self.burrowSeconds))
            return [TelegraphSnapshot(source: id, position: to, shape: .circle(radius: Self.burrowRadius),
                                      progress: 1 - Float(ticksLeft) / total)]
        case .none:
            return []
        }
    }
}
