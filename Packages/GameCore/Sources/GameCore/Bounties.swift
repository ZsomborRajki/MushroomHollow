/// What a naturalist pays for one mob material: its shop price in caps, plus a share of the source
/// mob's XP (scaled by level difference like a kill, so hoarded snail shells don't level anyone at 30).
public struct MaterialBounty: Sendable, Equatable {
    /// The mob this material comes from.
    public let source: MobKind
    public let caps: Int
    /// XP per item before the level-difference scaling.
    public let baseXP: Int

    /// XP one item is worth to a player of `level`.
    public func xp(forPlayerLevel level: Int) -> Int {
        Progression.xpReward(baseXP: baseXP, mobLevel: source.stats.level, playerLevel: level)
    }
}

extension ItemID {
    /// The mob whose signature material this is (its most common drop), if any.
    public var specimenOf: MobKind? {
        guard case .material = definition.kind else { return nil }
        return MobKind.allCases.first { $0.drops.first?.item == self }
    }

    /// Every mob's own material can be traded in; amber, charms, and everything else can't.
    public var bounty: MaterialBounty? {
        guard let source = specimenOf else { return nil }
        return MaterialBounty(source: source, caps: definition.sellPrice,
                              baseXP: max(1, source.stats.xp / Self.bountyXPDivisor))
    }

    /// One material is worth this fraction of a kill's XP.
    static let bountyXPDivisor = 3
}

extension GameSimulation {
    /// At a naturalist: hand in `count` of one mob material for caps and XP.
    mutating func tradeMaterials(_ item: ItemID, count: Int, at npc: NPCID, player: inout WorldEntity) -> ActionFailure? {
        guard var data = player.player, count > 0 else { return .notAvailable }
        guard isNear(npc, player) else { return .tooFar }
        guard npc.definition.buysMaterials else { return .notAvailable }
        guard let bounty = item.bounty else { return .notUsable }
        guard data.inventory.remove(item, count: count) else { return .missingItem }

        let caps = bounty.caps * count
        let xp = bounty.xp(forPlayerLevel: player.stats.level) * count
        data.caps += caps
        player.player = data
        events.append(.materialsTraded(player: player.id, item: item, count: count, xp: xp, caps: caps))
        events.append(.capsChanged(player: player.id, delta: caps))
        awardXP(to: &player, amount: xp)
        reportCollectProgress(for: &player)
        return nil
    }
}
