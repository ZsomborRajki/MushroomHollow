extension GameSimulation {
    static let itemCooldownSeconds: Float = 1.5
    /// Sitting down multiplies HP and MP recovery (as in Flyff).
    public static let sitRegenMultiplier: Float = 2.5

    // Flight tuning.
    public static let flightSpeed: Float = 8
    public static let climbSpeed: Float = 5
    public static let glideDescentSpeed: Float = 6
    public static let maxAltitude: Float = 40
    /// Above this height, ground mobs can't reach you (and you can't fight them).
    public static let reachableAltitude: Float = 2.5

    mutating func apply(_ command: PlayerCommand, to player: inout WorldEntity) {
        switch command {
        case let .move(direction):
            player.moveIntent = player.stats.isAlive ? direction.clampedLength(1) : .zero

        case let .target(id, engage):
            guard player.stats.isAlive else { return }
            guard let id, let target = entities[id], target.kind.isMob, target.stats.isAlive else {
                player.combat.target = nil
                player.combat.engaged = false
                player.combat.queuedSkill = nil
                return
            }
            if player.combat.target != id { player.combat.queuedSkill = nil }
            player.combat.target = id
            player.combat.engaged = !isAirborne(player) && (engage || (player.combat.engaged && player.combat.target == id))
            if player.combat.engaged { player.isSitting = false }

        case let .useSkill(skill):
            guard player.stats.isAlive else { return }
            if let failure = castFailure(skill, by: player, on: player.combat.target) {
                events.append(.skillFailed(caster: player.id, skill: skill, reason: failure))
            } else {
                player.combat.queuedSkill = skill
            }

        case .respawn:
            guard !player.stats.isAlive else { return }
            let spawn = map.resolve(map.playerSpawn, radius: player.radius)
            player.position = Vec3(spawn.x, 0, spawn.y)
            player.stats = baseStats(for: player)
            player.combat = CombatState()
            player.moveIntent = .zero
            player.velocity = .zero
            player.isFlying = false
            player.isSitting = false
            player.player?.buffs = []
            events.append(.respawned(entity: player.id))

        case .toggleSit:
            if player.isSitting {
                player.isSitting = false
            } else {
                guard player.stats.isAlive, !isAirborne(player), player.knockbackTicks == 0 else { return fail(.notUsable, player) }
                player.isSitting = true
                player.combat.engaged = false
                player.combat.queuedSkill = nil
                player.moveIntent = .zero
                move(&player, velocity: .zero)
            }

        case let .useItem(item):
            if let failure = useItem(item, player: &player) { fail(failure, player) }

        case let .pickupDrop(id):
            if let failure = collectDrop(id, for: &player) { fail(failure, player) }

        case let .equip(item, upgrade, element):
            if let failure = equip(Gear(item, upgrade: upgrade, element: element), player: &player) { fail(failure, player) }

        case let .unequip(slot):
            guard var data = player.player, let gear = data.equipment[slot] else { return }
            guard data.inventory.add(gear, count: 1) == 0 else { return fail(.inventoryFull, player) }
            data.equipment[slot] = nil
            player.player = data
            refreshStats(&player)
            events.append(.equipmentChanged(player: player.id))

        case let .buy(item, npc):
            if let failure = buy(item, from: npc, player: &player) { fail(failure, player) }

        case let .sell(item, count, upgrade, element, npc):
            if let failure = sell(Gear(item, upgrade: upgrade, element: element), count: count, to: npc, player: &player) {
                fail(failure, player)
            }

        case let .buyBack(item, upgrade, element, npc):
            if let failure = buyBack(Gear(item, upgrade: upgrade, element: element), from: npc, player: &player) { fail(failure, player) }

        case let .upgrade(location, protect):
            if let failure = upgrade(location, protect: protect, player: &player) { fail(failure, player) }

        case let .infuseElement(location, element, protect):
            if let failure = infuseElement(location, element: element, protect: protect, player: &player) { fail(failure, player) }

        case let .removeElement(location):
            if let failure = removeElement(location, player: &player) { fail(failure, player) }

        case let .convertElement(location, element):
            if let failure = convertElement(location, to: element, player: &player) { fail(failure, player) }

        case let .acceptQuest(quest):
            if let failure = acceptQuest(quest, player: &player) { fail(failure, player) }

        case let .completeQuest(quest):
            if let failure = completeQuest(quest, player: &player) { fail(failure, player) }

        case let .chooseClass(playerClass):
            if let failure = chooseClass(playerClass, player: &player) { fail(failure, player) }

        case .toggleFlight:
            if let failure = toggleFlight(&player) { fail(failure, player) }

        case let .climb(amount):
            player.climbIntent = player.isFlying ? max(-1, min(1, amount)) : 0

        case let .slotPet(item):
            if let failure = slotPet(item, player: &player) { fail(failure, player) }

        case .unslotPet:
            if let failure = unslotPet(player: &player) { fail(failure, player) }

        case .summonPet:
            if let failure = summonPet(player: &player) { fail(failure, player) }

        case .dismissPet:
            if let failure = dismissPet(player: &player) { fail(failure, player) }

        case let .makePetFood(item, count, npc):
            if let failure = makePetFood(item, count: count, at: npc, player: &player) { fail(failure, player) }

        case let .spendStatPoints(points):
            if let failure = spendStatPoints(points, player: &player) { fail(failure, player) }

        case let .tradeMaterials(item, count, npc):
            if let failure = tradeMaterials(item, count: count, at: npc, player: &player) { fail(failure, player) }
        }
    }

    mutating func stepPlayer(_ player: inout WorldEntity) {
        guard player.stats.isAlive else {
            player.velocity = .zero
            return
        }
        tickTimers(&player)
        regenerate(&player)
        recordVisits(&player)

        if player.isSitting {
            // Moving, attacking, casting, or being shoved gets you back on your feet.
            if player.moveIntent.length > 0.05 || player.combat.engaged || player.combat.queuedSkill != nil
                || isAirborne(player) || player.knockbackTicks > 0 {
                player.isSitting = false
            } else {
                move(&player, velocity: .zero)
                return
            }
        }

        // Being shoved: no control until it wears off.
        if player.knockbackTicks > 0 {
            player.knockbackTicks -= 1
            move(&player, velocity: player.knockback)
            return
        }

        if isAirborne(player) {
            stepFlight(&player)
            return
        }
        let speed = player.moveSpeed * (isSlowed(player) ? Self.slimeSlowFactor : 1)

        // Untargeted skills go off immediately, even while moving.
        if let skill = player.combat.queuedSkill, !skill.definition.needsTarget {
            player.combat.queuedSkill = nil
            tryCast(skill, by: &player, on: nil)
        }

        // Moving always wins and cancels auto-attack (the target stays selected).
        if player.moveIntent.length > 0.05 {
            player.combat.engaged = false
            player.combat.queuedSkill = nil
            turn(&player, toward: player.moveIntent, rate: Self.playerTurnRate)
            move(&player, velocity: player.moveIntent * speed)
            return
        }

        guard let targetID = player.combat.target, let target = entities[targetID], target.stats.isAlive else {
            player.combat.target = nil
            player.combat.engaged = false
            player.combat.queuedSkill = nil
            move(&player, velocity: .zero)
            return
        }
        guard player.combat.engaged || player.combat.queuedSkill != nil else {
            move(&player, velocity: .zero)
            return
        }

        let range = player.combat.queuedSkill?.definition.range ?? player.stats.reach
        let direction = (target.position.xz - player.position.xz).normalizedOrZero
        turn(&player, toward: direction, rate: Self.playerTurnRate)
        if gap(player, target) > range {
            move(&player, velocity: direction * speed)
            return
        }
        move(&player, velocity: .zero)

        if let skill = player.combat.queuedSkill {
            player.combat.queuedSkill = nil
            player.combat.engaged = true // a targeted skill starts the fight
            if tryCast(skill, by: &player, on: targetID) { return }
        }
        if player.combat.engaged, player.combat.attackTimer <= 0 {
            player.combat.attackTimer = Self.ticks(player.stats.attackInterval)
            dealDamage(from: &player, to: targetID, multiplier: 1, skill: nil, canMiss: true)
        }
    }

    // MARK: - Flight

    func isAirborne(_ entity: WorldEntity) -> Bool {
        entity.isFlying || entity.position.y > 0
    }

    /// Flying, or gliding back down after landing was requested. No fighting up here.
    private func stepFlight(_ player: inout WorldEntity) {
        let dt = Self.tickDuration
        let vertical = player.isFlying ? player.climbIntent * Self.climbSpeed : -Self.glideDescentSpeed
        // Over deep water the seed skims the surface instead of setting you down in it.
        let floor = map.isOverDeepWater(player.position.xz) ? WorldMap.waterHoverAltitude : 0
        player.position.y = max(floor, min(Self.maxAltitude, player.position.y + vertical * dt))
        player.combat.engaged = false
        player.combat.queuedSkill = nil

        let speed = player.isFlying ? Self.flightSpeed : player.moveSpeed
        if player.moveIntent.length > 0.05 {
            turn(&player, toward: player.moveIntent, rate: Self.playerTurnRate)
            move(&player, velocity: player.moveIntent * speed)
        } else {
            move(&player, velocity: .zero)
        }
        if !player.isFlying, player.position.y == 0 {
            // Touched down: make sure we're not standing inside a root or a house.
            player.position.xz = map.resolve(player.position.xz, radius: player.radius)
        }
    }

    private mutating func toggleFlight(_ player: inout WorldEntity) -> ActionFailure? {
        guard player.stats.isAlive, let data = player.player else { return .notUsable }
        if player.isFlying {
            player.isFlying = false
            player.climbIntent = 0
            events.append(.flightChanged(player: player.id, isFlying: false))
            return nil
        }
        guard data.inventory.count(of: .dandelionSeed) > 0 else { return .missingItem }
        guard player.stats.level >= ItemID.dandelionSeed.definition.requiredLevel else { return .levelTooLow }
        player.isFlying = true
        player.isSitting = false
        player.combat.engaged = false
        player.combat.queuedSkill = nil
        events.append(.flightChanged(player: player.id, isFlying: true))
        return nil
    }

    // MARK: - Class

    private mutating func chooseClass(_ playerClass: PlayerClass, player: inout WorldEntity) -> ActionFailure? {
        guard var data = player.player else { return .notAvailable }
        guard data.playerClass == nil else { return .notAvailable }
        guard player.stats.level >= PlayerClass.requiredLevel else { return .levelTooLow }
        // As in Flyff, the job change comes after a trial.
        guard data.completedQuests.contains(.trialOfThePath) else { return .trialFirst }
        guard isNear(.elderMorel, player) else { return .tooFar }
        data.playerClass = playerClass
        player.player = data
        refreshStats(&player)
        player.stats.hp = player.stats.maxHP
        player.stats.mp = player.stats.maxMP
        events.append(.classChosen(player: player.id, playerClass: playerClass))
        return nil
    }

    // MARK: - Stats

    /// Full-health stats for the player's level, class, and gear.
    func baseStats(for player: WorldEntity) -> CombatStats {
        Self.playerStats(level: player.stats.level, data: player.player ?? PlayerData())
    }

    /// Recomputes stats after a gear change, keeping current HP/MP (clamped).
    func refreshStats(_ player: inout WorldEntity) {
        var stats = baseStats(for: player)
        stats.hp = min(player.stats.hp, stats.maxHP)
        stats.mp = min(player.stats.mp, stats.maxMP)
        player.stats = stats
    }

    private func tickTimers(_ player: inout WorldEntity) {
        if player.combat.attackTimer > 0 { player.combat.attackTimer -= 1 }
        if let cooldowns = player.player?.cooldowns, !cooldowns.isEmpty {
            player.player?.cooldowns = cooldowns.compactMapValues { $0 > 1 ? $0 - 1 : nil }
        }
        if let itemCooldown = player.player?.itemCooldown, itemCooldown > 0 {
            player.player?.itemCooldown = itemCooldown - 1
        }
        if let buffs = player.player?.buffs, !buffs.isEmpty {
            player.player?.buffs = buffs.compactMap { buff in
                var buff = buff
                buff.ticksLeft -= 1
                return buff.ticksLeft > 0 ? buff : nil
            }
        }
    }

    /// Fast regeneration out of combat, a trickle during it.
    private func regenerate(_ player: inout WorldEntity) {
        guard var data = player.player else { return }
        let outOfCombat = tick - player.combat.lastCombatTick > UInt64(Self.ticks(5)) || player.combat.lastCombatTick == 0
        let buffRegen = data.buffs.reduce(Float(0)) { total, buff in
            if case let .regen(fraction) = buff.effect { return total + fraction }
            return total
        }
        let rest = player.isSitting ? Self.sitRegenMultiplier : 1
        let hpPerSecond = Float(player.stats.maxHP) * ((outOfCombat ? 0.04 : 0.005) * rest + buffRegen)
        let mpPerSecond = Float(player.stats.maxMP) * (outOfCombat ? 0.05 : 0.01) * rest
        data.hpRegen += hpPerSecond * Self.tickDuration
        data.mpRegen += mpPerSecond * Self.tickDuration
        let hpGain = Int(data.hpRegen), mpGain = Int(data.mpRegen)
        data.hpRegen -= Float(hpGain)
        data.mpRegen -= Float(mpGain)
        player.stats.hp = min(player.stats.maxHP, player.stats.hp + hpGain)
        player.stats.mp = min(player.stats.maxMP, player.stats.mp + mpGain)
        player.player = data
    }

    // MARK: - Items

    /// Hit or hitting something in the last few seconds.
    func isInCombat(_ player: WorldEntity) -> Bool {
        player.combat.engaged || (player.combat.lastCombatTick > 0 && tick - player.combat.lastCombatTick < UInt64(Self.ticks(4)))
    }

    mutating func fail(_ reason: ActionFailure, _ player: WorldEntity) {
        events.append(.actionFailed(player: player.id, reason: reason))
    }

    private mutating func useItem(_ item: ItemID, player: inout WorldEntity) -> ActionFailure? {
        if case .petFood = item.definition.kind { return feedPet(player: &player) }
        guard player.stats.isAlive, var data = player.player else { return .notUsable }
        guard case let .consumable(effect) = item.definition.kind else { return .notUsable }
        guard data.inventory.count(of: item) > 0 else { return .missingItem }
        guard data.itemCooldown <= 0 else { return .itemCooldown }
        if case .returnToTown = effect, isInCombat(player) { return .inCombat }

        data.inventory.remove(item, count: 1)
        data.itemCooldown = Self.ticks(Self.itemCooldownSeconds)
        player.player = data
        switch effect {
        case let .restoreHP(amount):
            let healed = min(amount, player.stats.maxHP - player.stats.hp)
            player.stats.hp += healed
            events.append(.heal(target: player.id, amount: healed, skill: nil))
        case let .restoreMP(amount):
            let restored = min(amount, player.stats.maxMP - player.stats.mp)
            player.stats.mp += restored
            events.append(.manaRestored(target: player.id, amount: restored))
        case .returnToTown:
            let home = map.resolve(map.playerSpawn, radius: player.radius)
            player.position = Vec3(home.x, 0, home.y)
            player.isFlying = false
            player.isSitting = false
            player.climbIntent = 0
            player.combat = CombatState()
            player.moveIntent = .zero
            player.velocity = .zero
            events.append(.blinked(player: player.id))
        }
        events.append(.itemUsed(player: player.id, item: item))
        reportCollectProgress(for: &player)
        return nil
    }

    private mutating func equip(_ gear: Gear, player: inout WorldEntity) -> ActionFailure? {
        let definition = gear.definition
        guard var data = player.player, let slot = definition.equipSlot else { return .notUsable }
        guard data.inventory.count(of: gear) > 0 else { return .missingItem }
        guard player.stats.level >= definition.requiredLevel else { return .levelTooLow }
        if let required = definition.requiredClass, data.playerClass != required { return .wrongClass }

        // Two-handed weapons and shields push each other off.
        var freed: [EquipSlot] = [slot]
        if definition.weaponType?.isTwoHanded == true { freed.append(.shield) }
        if slot == .shield, data.equipment[.weapon]?.definition.weaponType?.isTwoHanded == true { freed.append(.weapon) }

        data.inventory.remove(gear, count: 1)
        for freedSlot in freed {
            guard let previous = data.equipment[freedSlot] else { continue }
            guard data.inventory.add(previous, count: 1) == 0 else { return .inventoryFull }
            data.equipment[freedSlot] = nil
        }
        data.equipment[slot] = gear
        player.player = data
        refreshStats(&player)
        events.append(.equipmentChanged(player: player.id))
        return nil
    }

    // MARK: - NPCs

    func isNear(_ npc: NPCID, _ player: WorldEntity) -> Bool {
        guard let placement = map.placement(of: npc) else { return false }
        return placement.position.distance(to: player.position.xz) <= NPCID.interactionRange
    }

    private mutating func buy(_ item: ItemID, from npc: NPCID, player: inout WorldEntity) -> ActionFailure? {
        guard var data = player.player else { return .notAvailable }
        guard isNear(npc, player) else { return .tooFar }
        guard npc.definition.shopStock.contains(item), let price = item.definition.buyPrice else { return .notAvailable }
        guard data.caps >= price else { return .notEnoughCaps }
        guard data.inventory.add(item, count: 1) == 0 else { return .inventoryFull }

        data.caps -= price
        player.player = data
        events.append(.capsChanged(player: player.id, delta: -price))
        events.append(.itemReceived(player: player.id, item: item, count: 1))
        reportCollectProgress(for: &player)
        return nil
    }

    private mutating func sell(_ gear: Gear, count: Int, to npc: NPCID, player: inout WorldEntity) -> ActionFailure? {
        guard var data = player.player, count > 0 else { return .notAvailable }
        guard isNear(npc, player) else { return .tooFar }
        guard npc.definition.isShopkeeper else { return .notAvailable }
        // Pets and Kibble aren't for sale.
        guard gear.definition.sellPrice > 0 else { return .notAvailable }
        guard data.inventory.remove(gear, count: count) else { return .missingItem }

        let earned = gear.sellPrice * count
        data.caps += earned
        Buyback.record(gear, count: count, price: gear.sellPrice, in: &data.buyback)
        player.player = data
        events.append(.capsChanged(player: player.id, delta: earned))
        return nil
    }

    // MARK: - Quests

    func questState(_ quest: QuestID, for player: WorldEntity) -> QuestState {
        guard let data = player.player else { return .hidden }
        let definition = quest.definition
        if data.completedQuests.contains(quest) { return .completed }
        if let kills = data.activeQuests[quest] {
            let progress: Int = switch definition.objective {
            case .defeat, .defeatGiant: kills
            case let .collect(item, _): data.inventory.count(of: item)
            case .explore: kills.nonzeroBitCount // a bitmask of the places visited
            }
            let goal = definition.objective.goal
            return progress >= goal ? .readyToTurnIn : .active(progress: progress, goal: goal)
        }
        if let prerequisite = definition.prerequisite, !data.completedQuests.contains(prerequisite) { return .hidden }
        // Characters who chose a class before the trial existed never need it.
        if quest == .trialOfThePath, data.playerClass != nil { return .hidden }
        if let maxLevel = definition.maxLevel, player.stats.level > maxLevel { return .hidden }
        if player.stats.level < definition.requiredLevel { return .tooLowLevel(required: definition.requiredLevel) }
        return .available
    }

    private mutating func acceptQuest(_ quest: QuestID, player: inout WorldEntity) -> ActionFailure? {
        guard isNear(quest.definition.giver, player) else { return .tooFar }
        switch questState(quest, for: player) {
        case .available: break
        case .tooLowLevel: return .levelTooLow
        default: return .notAvailable
        }
        player.player?.activeQuests[quest] = 0
        events.append(.questAccepted(player: player.id, quest: quest))
        reportCollectProgress(for: &player)
        return nil
    }

    private mutating func completeQuest(_ quest: QuestID, player: inout WorldEntity) -> ActionFailure? {
        guard var data = player.player else { return .notAvailable }
        let definition = quest.definition
        guard isNear(definition.giver, player) else { return .tooFar }
        guard questState(quest, for: player) == .readyToTurnIn else { return .notAvailable }

        if case let .collect(item, count) = definition.objective {
            data.inventory.remove(item, count: count)
        }
        var bag = data.inventory
        for reward in definition.rewardItems where bag.add(reward.item, count: reward.count) > 0 {
            return .inventoryFull
        }
        data.inventory = bag
        data.caps += definition.rewardCaps
        data.activeQuests[quest] = nil
        // Hunting requests go straight back on the board.
        if !definition.isRepeatable { data.completedQuests.insert(quest) }
        player.player = data

        events.append(.questCompleted(player: player.id, quest: quest))
        events.append(.capsChanged(player: player.id, delta: definition.rewardCaps))
        for reward in definition.rewardItems {
            events.append(.itemReceived(player: player.id, item: reward.item, count: reward.count))
        }
        awardXP(to: &player, amount: definition.rewardXP)
        return nil
    }

    /// Kill quests count kills of the right mob (and Giant trials, Giants of the right level).
    mutating func recordKill(of kind: MobKind, giant: Bool = false, by player: inout WorldEntity) {
        guard var data = player.player else { return }
        for quest in QuestID.allCases {
            guard let kills = data.activeQuests[quest] else { continue }
            let goal: Int
            switch quest.definition.objective {
            case let .defeat(target, count) where target == kind: goal = count
            case let .defeatGiant(minLevel, count) where giant && kind.stats.level + Giant.levelBonus >= minLevel: goal = count
            default: continue
            }
            guard kills < goal else { continue }
            data.activeQuests[quest] = kills + 1
            events.append(.questProgress(player: player.id, quest: quest, progress: kills + 1, goal: goal))
        }
        player.player = data
    }

    /// Collect quests follow the bag; report whenever it may have changed.
    mutating func reportCollectProgress(for player: inout WorldEntity) {
        guard let data = player.player else { return }
        for quest in QuestID.allCases where data.activeQuests[quest] != nil {
            guard case let .collect(item, goal) = quest.definition.objective else { continue }
            let progress = min(goal, data.inventory.count(of: item))
            if data.activeQuests[quest] != progress {
                player.player?.activeQuests[quest] = progress
                events.append(.questProgress(player: player.id, quest: quest, progress: progress, goal: goal))
            }
        }
    }
}
