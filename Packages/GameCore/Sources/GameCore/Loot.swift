struct DropEntry: Sendable {
    let item: ItemID
    let chance: Float
    let count: ClosedRange<Int>
}

extension MobKind {
    var capsDrop: ClosedRange<Int> {
        switch self {
        case .snail: 1...3
        case .slug: 3...6
        case .beetle: 8...14
        case .sporeBeast: 14...22
        case .sporeling: 2...4
        case .mouse: 3...6
        case .owl: 500...800
        }
    }

    /// Standard gear drops from mobs of its level (as in early Flyff). Set pieces are very rare:
    /// the Dewleaf set is spread over the zones from level 1 to 15, one piece per zone.
    var drops: [DropEntry] {
        switch self {
        case .snail:
            [DropEntry(item: .snailShell, chance: 0.6, count: 1...1),
             DropEntry(item: .dewPotion, chance: 0.08, count: 1...1),
             DropEntry(item: .mossBoots, chance: 0.02, count: 1...1),
             DropEntry(item: .twigSword, chance: 0.02, count: 1...1),
             DropEntry(item: .barkBuckler, chance: 0.02, count: 1...1),
             DropEntry(item: .grassMitts, chance: 0.02, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.03, count: 1...1),
             DropEntry(item: .dewleafSlippers, chance: 0.01, count: 1...1)]
        case .slug:
            [DropEntry(item: .slugSlime, chance: 0.55, count: 1...2),
             DropEntry(item: .dewPotion, chance: 0.1, count: 1...1),
             DropEntry(item: .nectarVial, chance: 0.08, count: 1...1),
             DropEntry(item: .acornCap, chance: 0.03, count: 1...1),
             DropEntry(item: .pebbleHatchet, chance: 0.02, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.04, count: 1...1),
             DropEntry(item: .dewleafCap, chance: 0.01, count: 1...1)]
        case .beetle:
            [DropEntry(item: .beetleHorn, chance: 0.5, count: 1...1),
             DropEntry(item: .dewPotion, chance: 0.12, count: 1...2),
             DropEntry(item: .beetleHelm, chance: 0.03, count: 1...1),
             DropEntry(item: .thornRapier, chance: 0.03, count: 1...1),
             DropEntry(item: .hornCleaver, chance: 0.03, count: 1...1),
             DropEntry(item: .beetleAegis, chance: 0.02, count: 1...1),
             DropEntry(item: .chitinGauntlets, chance: 0.03, count: 1...1),
             DropEntry(item: .barkTreads, chance: 0.02, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.06, count: 1...1),
             DropEntry(item: .wardCharm, chance: 0.002, count: 1...1),
             DropEntry(item: .dewleafGloves, chance: 0.01, count: 1...1)]
        case .sporeBeast:
            [DropEntry(item: .sporeSac, chance: 0.55, count: 1...2),
             DropEntry(item: .nectarVial, chance: 0.15, count: 1...2),
             DropEntry(item: .beetleBlade, chance: 0.03, count: 1...1),
             DropEntry(item: .barkMail, chance: 0.02, count: 1...1),
             DropEntry(item: .toadstoolChopper, chance: 0.03, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.08, count: 1...2),
             DropEntry(item: .wardCharm, chance: 0.004, count: 1...1),
             DropEntry(item: .dewleafVest, chance: 0.01, count: 1...1)]
        case .sporeling:
            [DropEntry(item: .sporeSac, chance: 0.1, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.02, count: 1...1)]
        case .mouse:
            [DropEntry(item: .dewPotion, chance: 0.15, count: 1...1),
             DropEntry(item: .amberShard, chance: 0.03, count: 1...1)]
        case .owl:
            [DropEntry(item: .owlFeather, chance: 1, count: 2...4),
             DropEntry(item: .moonTalon, chance: 0.35, count: 1...1),
             DropEntry(item: .featherCloak, chance: 0.35, count: 1...1),
             DropEntry(item: .boughHammer, chance: 0.12, count: 1...1),
             DropEntry(item: .owlboneBow, chance: 0.12, count: 1...1),
             DropEntry(item: .glowcapScepter, chance: 0.12, count: 1...1),
             DropEntry(item: .raincallerStaff, chance: 0.12, count: 1...1),
             DropEntry(item: .amberShard, chance: 1, count: 3...6),
             DropEntry(item: .wardCharm, chance: 0.3, count: 1...1),
             DropEntry(item: .nectarVial, chance: 1, count: 3...5)]
        }
    }

    /// Chance to drop one random piece of the killer's class set (classed players only).
    var classSetChance: Float {
        switch self {
        case .owl: 0.3
        case .sporeBeast: 0.004
        case .mouse: 0.003
        case .snail, .slug, .beetle, .sporeling: 0
        }
    }
}

extension GameSimulation {
    /// Rolls a mob's loot straight into the killer's bag (auto-loot: controller friendly).
    mutating func rollLoot(for kind: MobKind, into player: inout WorldEntity) {
        guard var data = player.player else { return }
        let caps = random.int(in: kind.capsDrop)
        data.caps += caps
        events.append(.capsChanged(player: player.id, delta: caps))

        for drop in kind.drops where random.unit() < drop.chance {
            give(drop.item, count: random.int(in: drop.count), to: player.id, &data)
        }
        if let job = data.playerClass, let set = ItemSet.forClass(job), kind.classSetChance > 0,
           random.unit() < kind.classSetChance {
            let pieces = set.definition.pieces
            give(pieces[random.int(in: 0...(pieces.count - 1))], count: 1, to: player.id, &data)
        }
        player.player = data
        reportCollectProgress(for: &player)
    }

    private mutating func give(_ item: ItemID, count: Int, to player: EntityID, _ data: inout PlayerData) {
        let leftover = data.inventory.add(item, count: count)
        if leftover < count {
            events.append(.itemReceived(player: player, item: item, count: count - leftover))
        }
        if leftover > 0 {
            events.append(.actionFailed(player: player, reason: .inventoryFull))
        }
    }
}
