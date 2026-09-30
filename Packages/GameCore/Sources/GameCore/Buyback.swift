/// Something sold to a shop, kept for a while so a mistake can be bought back.
public struct SoldStack: Codable, Sendable, Equatable {
    public let gear: Gear
    public var count: Int
    /// Caps per item: exactly what the shop paid, so buying back costs nothing extra.
    public let price: Int

    public var total: Int { price * count }
}

/// Every shopkeeper keeps the same buyback list for you (newest first). It isn't saved:
/// like most MMOs, it empties when you leave the game.
public enum Buyback {
    /// How many sales are remembered; the oldest falls off.
    public static let capacity = 12

    /// Selling the same thing again (one at a time from a stack) grows the newest entry.
    static func record(_ gear: Gear, count: Int, price: Int, in list: inout [SoldStack]) {
        if let newest = list.first, newest.gear == gear, newest.price == price {
            list[0].count += count
        } else {
            list.insert(SoldStack(gear: gear, count: count, price: price), at: 0)
            if list.count > capacity { list.removeLast(list.count - capacity) }
        }
    }
}

extension GameSimulation {
    /// Buys back the newest sale of `gear`, the whole pile at once.
    mutating func buyBack(_ gear: Gear, from npc: NPCID, player: inout WorldEntity) -> ActionFailure? {
        guard var data = player.player else { return .notAvailable }
        guard isNear(npc, player) else { return .tooFar }
        guard npc.definition.isShopkeeper else { return .notAvailable }
        guard let index = data.buyback.firstIndex(where: { $0.gear == gear }) else { return .missingItem }
        let sold = data.buyback[index]
        guard data.caps >= sold.total else { return .notEnoughCaps }
        guard data.inventory.canAdd(gear, count: sold.count) else { return .inventoryFull }

        data.inventory.add(gear, count: sold.count)
        data.caps -= sold.total
        data.buyback.remove(at: index)
        player.player = data
        events.append(.capsChanged(player: player.id, delta: -sold.total))
        events.append(.itemReceived(player: player.id, item: gear.item, count: sold.count))
        reportCollectProgress(for: &player)
        return nil
    }
}
