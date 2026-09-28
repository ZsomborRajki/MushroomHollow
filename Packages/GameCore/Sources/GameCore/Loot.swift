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
        case .owl: 500...800
        }
    }

    var drops: [DropEntry] {
        switch self {
        case .snail:
            [DropEntry(item: .snailShell, chance: 0.6, count: 1...1),
             DropEntry(item: .dewPotion, chance: 0.08, count: 1...1),
             DropEntry(item: .mossBoots, chance: 0.02, count: 1...1),
             DropEntry(item: .twigSword, chance: 0.02, count: 1...1)]
        case .slug:
            [DropEntry(item: .slugSlime, chance: 0.55, count: 1...2),
             DropEntry(item: .dewPotion, chance: 0.1, count: 1...1),
             DropEntry(item: .nectarVial, chance: 0.08, count: 1...1),
             DropEntry(item: .acornCap, chance: 0.03, count: 1...1)]
        case .beetle:
            [DropEntry(item: .beetleHorn, chance: 0.5, count: 1...1),
             DropEntry(item: .dewPotion, chance: 0.12, count: 1...2),
             DropEntry(item: .beetleHelm, chance: 0.03, count: 1...1),
             DropEntry(item: .thornRapier, chance: 0.03, count: 1...1)]
        case .sporeBeast:
            [DropEntry(item: .sporeSac, chance: 0.55, count: 1...2),
             DropEntry(item: .nectarVial, chance: 0.15, count: 1...2),
             DropEntry(item: .beetleBlade, chance: 0.03, count: 1...1),
             DropEntry(item: .barkMail, chance: 0.02, count: 1...1)]
        case .sporeling:
            [DropEntry(item: .sporeSac, chance: 0.1, count: 1...1)]
        case .owl:
            []
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
            let count = random.int(in: drop.count)
            let leftover = data.inventory.add(drop.item, count: count)
            if leftover < count {
                events.append(.itemReceived(player: player.id, item: drop.item, count: count - leftover))
            }
            if leftover > 0 {
                events.append(.actionFailed(player: player.id, reason: .inventoryFull))
            }
        }
        player.player = data
        reportCollectProgress(for: &player)
    }
}
