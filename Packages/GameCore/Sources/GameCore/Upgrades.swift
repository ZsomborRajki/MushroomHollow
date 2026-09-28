/// Flyff-style gear upgrades, +1 to +10, done at a blacksmith. Every attempt costs Amber Shards
/// (mob drops only) and caps. Low upgrades are safe; from +4 a failure costs a level, and from +6
/// it destroys the item unless a Ward Charm is spent. So +5 is a mid-game goal, +10 an endgame one.
public enum Upgrade {
    public static let maxLevel = 10

    /// What a failed attempt costs, beyond the materials.
    public enum Risk: Sendable {
        case none
        /// The item drops one level.
        case downgrade
        /// The item is destroyed.
        case destroy
    }

    /// Chance that an attempt to reach `level` succeeds.
    public static func chance(toReach level: Int) -> Float {
        let table: [Float] = [1, 0.9, 0.8, 0.65, 0.5, 0.35, 0.25, 0.15, 0.1, 0.05]
        return table[max(1, min(level, maxLevel)) - 1]
    }

    public static func risk(toReach level: Int) -> Risk {
        switch level {
        case ...3: .none
        case 4...5: .downgrade
        default: .destroy
        }
    }

    /// Amber Shards per attempt.
    public static func amberCost(toReach level: Int) -> Int {
        let table = [1, 1, 1, 2, 2, 3, 3, 4, 5, 6]
        return table[max(1, min(level, maxLevel)) - 1]
    }

    /// Caps per attempt: pricier for higher-level gear and higher upgrades.
    public static func capsCost(of item: ItemID, toReach level: Int) -> Int {
        (item.definition.requiredLevel + 4) * level * 6
    }

    /// How much an upgrade boosts the item's main stat (index = upgrade level).
    static let boost: [Float] = [0, 0.1, 0.2, 0.32, 0.45, 0.6, 0.78, 1, 1.25, 1.55, 2]

    /// `base` stats at `level`: weapons gain attack; armor and shields gain defense and HP.
    /// Every level adds at least a little, so even starter gear grows.
    public static func bonus(_ base: StatBonus, slot: EquipSlot, level: Int) -> StatBonus {
        let level = max(0, min(level, maxLevel))
        guard level > 0 else { return base }
        let boost = Self.boost[level]
        func grown(_ value: Int) -> Int { Int((Float(value) * boost).rounded()) }
        var result = base
        if slot == .weapon {
            result.attack += max(level, grown(base.attack))
        } else {
            result.defense += max(level, grown(base.defense))
            result.maxHP += grown(base.maxHP)
        }
        return result
    }
}

/// Which piece of gear to upgrade: something worn, or something in the bag.
public enum GearLocation: Codable, Sendable, Hashable {
    case equipped(EquipSlot)
    case bag(Gear)
}

public enum UpgradeResult: Codable, Sendable, Equatable {
    case succeeded(level: Int)
    /// Nothing lost but the materials.
    case failed(level: Int)
    /// Failed, but the Ward Charm kept the item as it was.
    case protected(level: Int)
    case downgraded(level: Int)
    case destroyed
}

extension GameSimulation {
    mutating func upgrade(_ location: GearLocation, protect: Bool, player: inout WorldEntity) -> ActionFailure? {
        guard var data = player.player, player.stats.isAlive else { return .notAvailable }
        guard NPCID.allCases.contains(where: { $0.definition.upgradesGear && isNear($0, player) }) else { return .tooFar }

        let gear: Gear
        switch location {
        case let .equipped(slot):
            guard let worn = data.equipment[slot] else { return .missingItem }
            gear = worn
        case let .bag(carried):
            guard data.inventory.count(of: carried.item, upgrade: carried.upgrade) > 0 else { return .missingItem }
            gear = carried
        }
        guard gear.definition.isUpgradable else { return .notUsable }
        let target = gear.upgrade + 1
        guard target <= Upgrade.maxLevel else { return .maxUpgrade }

        let amber = Upgrade.amberCost(toReach: target)
        let caps = Upgrade.capsCost(of: gear.item, toReach: target)
        let risk = Upgrade.risk(toReach: target)
        let useCharm = protect && risk != .none
        guard data.inventory.count(of: .amberShard) >= amber else { return .missingMaterials }
        if useCharm, data.inventory.count(of: .wardCharm) == 0 { return .missingMaterials }
        guard data.caps >= caps else { return .notEnoughCaps }

        data.inventory.remove(.amberShard, count: amber)
        if useCharm { data.inventory.remove(.wardCharm, count: 1) }
        data.caps -= caps
        events.append(.capsChanged(player: player.id, delta: -caps))

        let result: UpgradeResult
        if random.unit() < Upgrade.chance(toReach: target) {
            result = .succeeded(level: target)
        } else if useCharm {
            result = .protected(level: gear.upgrade)
        } else {
            switch risk {
            case .none: result = .failed(level: gear.upgrade)
            case .downgrade: result = .downgraded(level: gear.upgrade - 1)
            case .destroy: result = .destroyed
            }
        }

        let newLevel: Int? = switch result {
        case let .succeeded(level), let .failed(level), let .protected(level), let .downgraded(level): level
        case .destroyed: nil
        }
        switch location {
        case let .equipped(slot):
            data.equipment[slot] = newLevel.map { Gear(gear.item, upgrade: $0) }
        case .bag:
            data.inventory.remove(gear.item, count: 1, upgrade: gear.upgrade)
            // Gear doesn't stack, so the slot just freed takes it back.
            if let newLevel { data.inventory.add(gear.item, count: 1, upgrade: newLevel) }
        }
        player.player = data
        if case .equipped = location {
            refreshStats(&player)
            events.append(.equipmentChanged(player: player.id))
        }
        events.append(.upgradeAttempted(player: player.id, item: gear.item, result: result))
        reportCollectProgress(for: &player)
        return nil
    }
}
