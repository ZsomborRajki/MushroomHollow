public enum EquipSlot: String, Codable, Sendable, CaseIterable {
    case weapon, hat, body, boots
}

public struct StatBonus: Codable, Sendable, Equatable {
    public var attack = 0
    public var defense = 0
    public var maxHP = 0
    public var maxMP = 0

    public init(attack: Int = 0, defense: Int = 0, maxHP: Int = 0, maxMP: Int = 0) {
        self.attack = attack
        self.defense = defense
        self.maxHP = maxHP
        self.maxMP = maxMP
    }

    public static func + (a: StatBonus, b: StatBonus) -> StatBonus {
        StatBonus(attack: a.attack + b.attack, defense: a.defense + b.defense,
                  maxHP: a.maxHP + b.maxHP, maxMP: a.maxMP + b.maxMP)
    }
}

public enum ItemID: String, Codable, Sendable, CaseIterable {
    // Consumables
    case dewPotion, nectarVial
    // Materials
    case snailShell, slugSlime, beetleHorn, sporeSac
    // Weapons
    case twigSword, thornRapier, beetleBlade
    // Hats
    case acornCap, beetleHelm
    // Body
    case leafTunic, barkMail
    // Boots
    case mossBoots
    // Key items
    case dandelionSeed
}

public struct ItemDefinition: Sendable {
    public enum Kind: Sendable {
        case consumable(ConsumableEffect)
        case material
        case equipment(EquipSlot, StatBonus)
        /// Owning one lets you fly.
        case glider
    }

    public enum ConsumableEffect: Sendable {
        case restoreHP(Int)
        case restoreMP(Int)
    }

    public let id: ItemID
    public let name: String
    public let description: String
    public let kind: Kind
    public let requiredLevel: Int
    /// nil = not sold in shops.
    public let buyPrice: Int?
    public let sellPrice: Int
    public let maxStack: Int

    public var equipSlot: EquipSlot? {
        if case let .equipment(slot, _) = kind { return slot }
        return nil
    }

    public var bonus: StatBonus {
        if case let .equipment(_, bonus) = kind { return bonus }
        return StatBonus()
    }
}

extension ItemID {
    public var definition: ItemDefinition {
        switch self {
        case .dewPotion:
            item("Dew Potion", "Morning dew, bottled. Restores 60 HP.", .consumable(.restoreHP(60)), buy: 12, sell: 3, stack: 20)
        case .nectarVial:
            item("Nectar Vial", "Sweet and fizzy. Restores 40 MP.", .consumable(.restoreMP(40)), buy: 15, sell: 4, stack: 20)
        case .snailShell:
            item("Snail Shell Shard", "Still faintly spiral.", .material, sell: 3, stack: 50)
        case .slugSlime:
            item("Slug Slime", "Surprisingly useful. Surprisingly sticky.", .material, sell: 5, stack: 50)
        case .beetleHorn:
            item("Beetle Horn", "Hard as bark, twice as pointy.", .material, sell: 12, stack: 50)
        case .sporeSac:
            item("Spore Sac", "Do not squeeze.", .material, sell: 18, stack: 50)
        case .twigSword:
            item("Twig Sword", "Every hero starts somewhere.", .equipment(.weapon, StatBonus(attack: 4)),
                 level: 1, buy: 40, sell: 10)
        case .thornRapier:
            item("Thorn Rapier", "A bramble thorn with a leather grip.", .equipment(.weapon, StatBonus(attack: 9)),
                 level: 5, buy: 180, sell: 45)
        case .beetleBlade:
            item("Beetle-Horn Blade", "Glossy, sharp, and smug about it.", .equipment(.weapon, StatBonus(attack: 16, maxMP: 10)),
                 level: 9, sell: 120)
        case .acornCap:
            item("Acorn Cap", "Fits snugly over a mushroom hat.", .equipment(.hat, StatBonus(defense: 2, maxHP: 10)),
                 level: 2, buy: 60, sell: 15)
        case .beetleHelm:
            item("Beetle Helm", "Shiny blue and very hard.", .equipment(.hat, StatBonus(defense: 5, maxHP: 25)),
                 level: 7, sell: 90)
        case .leafTunic:
            item("Leaf Tunic", "Stitched from a single oak leaf.", .equipment(.body, StatBonus(defense: 3, maxHP: 15)),
                 level: 3, buy: 90, sell: 22)
        case .barkMail:
            item("Bark Mail", "Overlapping scales of old bark.", .equipment(.body, StatBonus(defense: 7, maxHP: 40)),
                 level: 8, buy: 320, sell: 80)
        case .mossBoots:
            item("Moss Boots", "Soft, quiet, a little damp.", .equipment(.boots, StatBonus(defense: 1, maxHP: 5, maxMP: 10)),
                 level: 1, buy: 35, sell: 8)
        case .dandelionSeed:
            item("Dandelion Seed", "Hold on tight and let the breeze do the rest. Lets you fly.", .glider,
                 level: 10, buy: 300, sell: 75)
        }
    }

    private func item(_ name: String, _ description: String, _ kind: ItemDefinition.Kind,
                      level: Int = 1, buy: Int? = nil, sell: Int, stack: Int = 1) -> ItemDefinition {
        ItemDefinition(id: self, name: name, description: description, kind: kind, requiredLevel: level,
                       buyPrice: buy, sellPrice: sell, maxStack: stack)
    }
}

public struct ItemStack: Codable, Sendable, Equatable {
    public let item: ItemID
    public var count: Int
}

/// A bag of stacks with a fixed number of slots.
public struct Inventory: Codable, Sendable, Equatable {
    public static let capacity = 24

    public private(set) var stacks: [ItemStack] = []

    public init() {}

    public func count(of item: ItemID) -> Int {
        stacks.reduce(0) { $0 + ($1.item == item ? $1.count : 0) }
    }

    public func canAdd(_ item: ItemID, count: Int) -> Bool {
        var probe = self
        return probe.add(item, count: count) == 0
    }

    /// Adds as much as fits; returns how many didn't.
    @discardableResult
    public mutating func add(_ item: ItemID, count: Int) -> Int {
        let maxStack = item.definition.maxStack
        var remaining = count
        for i in stacks.indices where stacks[i].item == item && remaining > 0 {
            let room = maxStack - stacks[i].count
            let moved = min(room, remaining)
            stacks[i].count += moved
            remaining -= moved
        }
        while remaining > 0, stacks.count < Self.capacity {
            let moved = min(maxStack, remaining)
            stacks.append(ItemStack(item: item, count: moved))
            remaining -= moved
        }
        return remaining
    }

    /// Removes exactly `count` or nothing.
    @discardableResult
    public mutating func remove(_ item: ItemID, count: Int) -> Bool {
        guard count > 0, self.count(of: item) >= count else { return false }
        var remaining = count
        for i in stacks.indices.reversed() where stacks[i].item == item && remaining > 0 {
            let taken = min(stacks[i].count, remaining)
            stacks[i].count -= taken
            remaining -= taken
        }
        stacks.removeAll { $0.count == 0 }
        return true
    }
}
