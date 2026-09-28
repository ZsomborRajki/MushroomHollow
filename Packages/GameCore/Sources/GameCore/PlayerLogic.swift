extension GameSimulation {
    static let itemCooldownSeconds: Float = 1.5

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
            player.combat.engaged = engage || (player.combat.engaged && player.combat.target == id)

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
            player.stats = Progression.playerStats(level: player.stats.level, bonus: bonus(of: player))
            player.combat = CombatState()
            player.moveIntent = .zero
            player.velocity = .zero
            events.append(.respawned(entity: player.id))

        case let .useItem(item):
            if let failure = useItem(item, player: &player) { fail(failure, player) }

        case let .equip(item):
            if let failure = equip(item, player: &player) { fail(failure, player) }

        case let .unequip(slot):
            guard var data = player.player, let item = data.equipment[slot] else { return }
            guard data.inventory.add(item, count: 1) == 0 else { return fail(.inventoryFull, player) }
            data.equipment[slot] = nil
            player.player = data
            refreshStats(&player)
            events.append(.equipmentChanged(player: player.id))

        case let .buy(item, npc):
            if let failure = buy(item, from: npc, player: &player) { fail(failure, player) }

        case let .sell(item, count, npc):
            if let failure = sell(item, count: count, to: npc, player: &player) { fail(failure, player) }

        case let .acceptQuest(quest):
            if let failure = acceptQuest(quest, player: &player) { fail(failure, player) }

        case let .completeQuest(quest):
            if let failure = completeQuest(quest, player: &player) { fail(failure, player) }
        }
    }

    mutating func stepPlayer(_ player: inout WorldEntity) {
        guard player.stats.isAlive else {
            player.velocity = .zero
            return
        }
        tickTimers(&player)
        regenerate(&player)
        let speed = player.moveSpeed * (isInSlime(player) ? Self.slimeSlowFactor : 1)

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
            dealDamage(from: &player, to: targetID, multiplier: 1, skill: nil)
        }
    }

    // MARK: - Stats

    func bonus(of player: WorldEntity) -> StatBonus {
        Self.equipmentBonus(player.player?.equipment ?? [:])
    }

    /// Recomputes stats after a gear change, keeping current HP/MP (clamped).
    func refreshStats(_ player: inout WorldEntity) {
        var stats = Progression.playerStats(level: player.stats.level, bonus: bonus(of: player))
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
    }

    /// Fast regeneration out of combat, a trickle during it.
    private func regenerate(_ player: inout WorldEntity) {
        guard var data = player.player else { return }
        let outOfCombat = tick - player.combat.lastCombatTick > UInt64(Self.ticks(5)) || player.combat.lastCombatTick == 0
        let hpPerSecond = Float(player.stats.maxHP) * (outOfCombat ? 0.04 : 0.005)
        let mpPerSecond = Float(player.stats.maxMP) * (outOfCombat ? 0.05 : 0.01)
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

    private mutating func fail(_ reason: ActionFailure, _ player: WorldEntity) {
        events.append(.actionFailed(player: player.id, reason: reason))
    }

    private mutating func useItem(_ item: ItemID, player: inout WorldEntity) -> ActionFailure? {
        guard player.stats.isAlive, var data = player.player else { return .notUsable }
        guard case let .consumable(effect) = item.definition.kind else { return .notUsable }
        guard data.inventory.count(of: item) > 0 else { return .missingItem }
        guard data.itemCooldown <= 0 else { return .itemCooldown }

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
        }
        events.append(.itemUsed(player: player.id, item: item))
        reportCollectProgress(for: &player)
        return nil
    }

    private mutating func equip(_ item: ItemID, player: inout WorldEntity) -> ActionFailure? {
        guard var data = player.player, let slot = item.definition.equipSlot else { return .notUsable }
        guard data.inventory.count(of: item) > 0 else { return .missingItem }
        guard player.stats.level >= item.definition.requiredLevel else { return .levelTooLow }

        data.inventory.remove(item, count: 1)
        if let previous = data.equipment[slot] {
            data.inventory.add(previous, count: 1) // the slot we just freed guarantees room
        }
        data.equipment[slot] = item
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

    private mutating func sell(_ item: ItemID, count: Int, to npc: NPCID, player: inout WorldEntity) -> ActionFailure? {
        guard var data = player.player, count > 0 else { return .notAvailable }
        guard isNear(npc, player) else { return .tooFar }
        guard npc.definition.isShopkeeper else { return .notAvailable }
        guard data.inventory.remove(item, count: count) else { return .missingItem }

        let earned = item.definition.sellPrice * count
        data.caps += earned
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
            case .defeat: kills
            case let .collect(item, _): data.inventory.count(of: item)
            }
            let goal = definition.objective.goal
            return progress >= goal ? .readyToTurnIn : .active(progress: progress, goal: goal)
        }
        if let prerequisite = definition.prerequisite, !data.completedQuests.contains(prerequisite) { return .hidden }
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
        data.completedQuests.insert(quest)
        player.player = data

        events.append(.questCompleted(player: player.id, quest: quest))
        events.append(.capsChanged(player: player.id, delta: definition.rewardCaps))
        for reward in definition.rewardItems {
            events.append(.itemReceived(player: player.id, item: reward.item, count: reward.count))
        }
        awardXP(to: &player, amount: definition.rewardXP)
        return nil
    }

    /// Kill quests count kills of the right mob.
    mutating func recordKill(of kind: MobKind, by player: inout WorldEntity) {
        guard var data = player.player else { return }
        for quest in QuestID.allCases {
            guard let kills = data.activeQuests[quest],
                  case let .defeat(target, goal) = quest.definition.objective, target == kind, kills < goal
            else { continue }
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
