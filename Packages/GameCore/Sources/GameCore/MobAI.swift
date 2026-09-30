extension GameSimulation {
    /// How far past its leash radius a mob will chase before giving up.
    static let leashSlack: Float = 12

    // Charge tuning (beetles, frogs, hedgehogs...).
    static let chargeWindup: Float = 0.8
    public static let chargeDuration: Float = 0.9
    public static let chargeSpeed: Float = 13
    static let chargeRange: ClosedRange<Float> = 2.5...10
    static let chargeDamageMultiplier: Float = 2.2

    mutating func stepMob(_ mob: inout WorldEntity) {
        guard mob.stats.isAlive else {
            mob.deathTicks += 1
            mob.velocity = .zero
            return
        }
        guard var brain = mob.brain, case let .mob(kind) = mob.kind else { return }
        let stats = kind.stats
        if mob.combat.attackTimer > 0 { mob.combat.attackTimer -= 1 }
        if brain.abilityTimer > 0 { brain.abilityTimer -= 1 }
        if brain.boss != nil, stepBoss(&mob, brain: &brain) {
            mob.brain = brain
            return
        }

        // Aggressive mobs notice players that wander too close.
        switch brain.state {
        case .idle, .wander:
            if brain.aggressive || brain.boss != nil,
               let prey = findPrey(for: mob, brain: brain, radius: stats.aggroRadius, reachesFlyers: brain.boss != nil) {
                mob.combat.target = prey
                mob.combat.engaged = true
                brain.state = .engaged
            }
        default:
            break
        }

        switch brain.state {
        case let .idle(ticksLeft):
            brain.state = ticksLeft > 0
                ? .idle(ticksLeft: ticksLeft - 1)
                : .wander(target: pickWanderTarget(for: mob, brain: brain), stuckTicks: 0)
            move(&mob, velocity: .zero)

        case let .wander(target, stuckTicks):
            let toTarget = target - mob.position.xz
            if toTarget.length < 0.3 || stuckTicks > Self.tickRate {
                brain.state = .idle(ticksLeft: random.int(in: Self.ticks(2)...Self.ticks(6)))
                move(&mob, velocity: .zero)
            } else {
                let direction = toTarget.normalizedOrZero
                turn(&mob, toward: direction, rate: Self.mobTurnRate)
                let before = mob.position.xz
                move(&mob, velocity: direction * mob.moveSpeed)
                let stuck = mob.position.xz.distance(to: before) < mob.moveSpeed * Self.tickDuration * 0.3
                brain.state = .wander(target: target, stuckTicks: stuck ? stuckTicks + 1 : 0)
            }

        case .engaged:
            stepEngaged(&mob, brain: &brain, kind: kind)

        case let .hiding(ticksLeft):
            move(&mob, velocity: .zero)
            brain.state = ticksLeft > 1 ? .hiding(ticksLeft: ticksLeft - 1) : .engaged

        case let .windingUp(direction, ticksLeft):
            move(&mob, velocity: .zero)
            turn(&mob, toward: direction, rate: Self.mobTurnRate * 3)
            brain.state = ticksLeft > 1
                ? .windingUp(direction: direction, ticksLeft: ticksLeft - 1)
                : .charging(direction: direction, ticksLeft: Self.ticks(Self.chargeDuration))

        case let .charging(direction, ticksLeft):
            let before = mob.position.xz
            move(&mob, velocity: direction * Self.chargeSpeed)
            let blocked = mob.position.xz.distance(to: before) < Self.chargeSpeed * Self.tickDuration * 0.25
            var hitSomeone = false
            for id in order {
                guard let player = entities[id], player.kind == .player, player.stats.isAlive,
                      player.position.y <= Self.reachableAltitude, gap(mob, player) < 0.3 else { continue }
                dealDamage(from: &mob, to: id, multiplier: Self.chargeDamageMultiplier, skill: nil)
                hitSomeone = true
                break
            }
            brain.state = (ticksLeft <= 1 || blocked || hitSomeone)
                ? .engaged
                : .charging(direction: direction, ticksLeft: ticksLeft - 1)

        case .returning:
            let toHome = brain.home - mob.position.xz
            if toHome.length < 1 {
                mob.stats.hp = mob.stats.maxHP
                brain.hasHidden = false
                if brain.boss != nil {
                    // A reset boss fight starts over.
                    brain.boss = kind.isFieldBoss ? BossBrain(burrowTimer: Self.ticks(Self.burrowFirstDelay))
                        : BossBrain(swoopTimer: Self.ticks(4), gustTimer: Self.ticks(6))
                }
                brain.state = .idle(ticksLeft: Self.ticks(2))
                move(&mob, velocity: .zero)
            } else {
                let direction = toHome.normalizedOrZero
                turn(&mob, toward: direction, rate: Self.mobTurnRate * 2)
                let before = mob.position.xz
                move(&mob, velocity: direction * stats.chaseSpeed * 1.2)
                // Wedged against a root on the way home: give up and reset where we are.
                if mob.position.xz.distance(to: before) < 0.01 {
                    brain.home = mob.position.xz
                }
            }
        }

        // Slugs leave slime wherever they crawl; newts and spiders only while chasing someone.
        if let trail = kind.trail, mob.isMoving, brain.abilityTimer <= 0,
           trail == .slime || mob.combat.engaged {
            spawnHazard(trail, from: mob)
            brain.abilityTimer = Self.ticks(1)
        }

        mob.brain = brain
    }

    /// Chasing and fighting, plus each mob's special move.
    private mutating func stepEngaged(_ mob: inout WorldEntity, brain: inout MobBrain, kind: MobKind) {
        let stats = kind.stats
        guard let preyID = mob.combat.target,
              let prey = entities[preyID], prey.stats.isAlive,
              brain.boss != nil || prey.position.y <= Self.reachableAltitude,
              mob.position.xz.distance(to: brain.home) <= brain.leashRadius + Self.leashSlack
        else {
            mob.combat = CombatState()
            brain.state = .returning
            move(&mob, velocity: .zero)
            return
        }
        let distance = gap(mob, prey)
        let direction = (prey.position.xz - mob.position.xz).normalizedOrZero

        if kind.hidesWhenHurt, !brain.hasHidden, mob.stats.hp * 10 < mob.stats.maxHP * 3 {
            brain.hasHidden = true
            brain.state = .hiding(ticksLeft: Self.ticks(3))
            events.append(.mobAbility(entity: mob.id, ability: .hide))
            move(&mob, velocity: .zero)
            return
        }
        if kind.charges, brain.abilityTimer <= 0, Self.chargeRange.contains(distance) {
            brain.state = .windingUp(direction: direction, ticksLeft: Self.ticks(Self.chargeWindup))
            brain.abilityTimer = Self.ticks(6)
            events.append(.mobAbility(entity: mob.id, ability: .charge))
            move(&mob, velocity: .zero)
            return
        }
        if let cloud = kind.cloud, brain.abilityTimer <= 0, distance < 4 {
            spawnHazard(cloud, from: mob)
            brain.abilityTimer = Self.ticks(7)
            events.append(.mobAbility(entity: mob.id, ability: .cloud))
        }

        turn(&mob, toward: direction, rate: Self.mobTurnRate * 2)
        if distance > stats.reach {
            move(&mob, velocity: direction * stats.chaseSpeed)
        } else {
            move(&mob, velocity: .zero)
            if mob.combat.attackTimer <= 0 {
                let enraged = brain.boss?.enraged == true
                mob.combat.attackTimer = Self.ticks(stats.attackInterval * (enraged ? 0.7 : 1))
                dealDamage(from: &mob, to: preyID, multiplier: 1, skill: nil, blockable: true, canMiss: true)
            }
        }
    }

    private func findPrey(for mob: WorldEntity, brain: MobBrain, radius: Float, reachesFlyers: Bool = false) -> EntityID? {
        guard radius > 0 else { return nil }
        var best: (id: EntityID, distance: Float)?
        for id in order {
            guard let e = entities[id], e.kind == .player, e.stats.isAlive,
                  reachesFlyers || e.position.y <= Self.reachableAltitude else { continue }
            let distance = gap(mob, e)
            guard distance <= radius,
                  e.position.xz.distance(to: brain.home) <= brain.leashRadius + Self.leashSlack
            else { continue }
            if best == nil || distance < best!.distance { best = (id, distance) }
        }
        return best?.id
    }

    private mutating func pickWanderTarget(for mob: WorldEntity, brain: MobBrain) -> Vec2 {
        let radius = brain.wanderRadius > 0 ? brain.wanderRadius : brain.leashRadius
        // Hunting-ground mobs stay inside their area, so each species keeps to its half.
        let area = brain.spawnArea.map { map.mobSpawns[$0] }
        for _ in 0..<6 {
            let candidate = random.point(inDiscAt: brain.home, radius: radius)
            if let area, candidate.distance(to: area.center) > area.radius { continue }
            if !map.isBlocked(candidate, radius: mob.radius) {
                return candidate
            }
        }
        return brain.home
    }
}

// MARK: - Mob traits

extension MobKind {
    /// Pulls into its shell (or curls up) once when badly hurt: much harder to hurt for a few seconds.
    public var hidesWhenHurt: Bool {
        switch self {
        case .snail, .pillBug, .mossTurtle, .coneKnight, .delverMole: true
        default: false
        }
    }

    /// Lowers its head, then charges (or leaps) in a straight line. Step aside!
    public var charges: Bool {
        switch self {
        case .beetle, .bogFrog, .hedgehog, .mantis, .stagBeetle, .rootcrawler: true
        default: false
        }
    }

    /// Left behind as it moves.
    public var trail: HazardKind? {
        switch self {
        case .slug: .slime
        case .emberNewt: .embers
        case .weaverSpider: .web
        default: nil
        }
    }

    /// Released around itself when a player comes close.
    public var cloud: HazardKind? {
        switch self {
        case .sporeBeast, .grumblecap: .sporeCloud
        case .thornrose: .pollen
        case .duskMoth: .mothDust
        default: nil
        }
    }

    /// Bursts into two of these, angry at the killer, when it dies.
    public var splitsInto: MobKind? {
        switch self {
        case .sporeBeast: .sporeling
        case .puffweed: .puffling
        default: nil
        }
    }
}
