public enum EquipSlot: String, Codable, Sendable, CaseIterable {
    case weapon, shield, hat, body, boots
}

/// Flyff-style weapon families. Each one sets how fast and how far its wielder attacks
/// (and the client gives each its own attack animation).
public enum WeaponType: String, Codable, Sendable, CaseIterable {
    // Anyone
    case sword, axe
    // Class weapons
    case maul, bow, wand, staff

    /// Only this class may wield it; nil = anyone.
    public var playerClass: PlayerClass? {
        switch self {
        case .sword, .axe: nil
        case .maul: .guardian
        case .bow: .thornshot
        case .wand: .sporecaster
        case .staff: .dewkeeper
        }
    }

    /// Needs both hands, so no shield.
    public var isTwoHanded: Bool {
        switch self {
        case .maul, .bow, .staff: true
        case .sword, .axe, .wand: false
        }
    }

    /// Auto-attack reach in meters, edge to edge.
    public var reach: Float {
        switch self {
        case .sword, .axe: 0.9
        case .maul: 1.1
        case .bow: 7
        case .wand, .staff: 6
        }
    }

    /// Seconds between auto-attacks: heavier weapons hit harder but slower.
    public var attackInterval: Float {
        switch self {
        case .sword: 0.9
        case .axe: 1.05
        case .maul: 1.3
        case .bow, .staff: 1
        case .wand: 1.1
        }
    }

    public var isRanged: Bool { reach > 2 }
}

public struct StatBonus: Codable, Sendable, Equatable {
    public var attack = 0
    public var defense = 0
    public var maxHP = 0
    public var maxMP = 0
    /// Chance (0...1) to block a mob's attack outright. Shields only.
    public var block: Float = 0

    public init(attack: Int = 0, defense: Int = 0, maxHP: Int = 0, maxMP: Int = 0, block: Float = 0) {
        self.attack = attack
        self.defense = defense
        self.maxHP = maxHP
        self.maxMP = maxMP
        self.block = block
    }

    public static func + (a: StatBonus, b: StatBonus) -> StatBonus {
        StatBonus(attack: a.attack + b.attack, defense: a.defense + b.defense,
                  maxHP: a.maxHP + b.maxHP, maxMP: a.maxMP + b.maxMP, block: a.block + b.block)
    }
}

public enum ItemID: String, Codable, Sendable, CaseIterable {
    // Consumables
    case dewPotion, nectarVial
    // Materials
    case snailShell, slugSlime, beetleHorn, sporeSac, owlFeather
    // Swords
    case twigSword, thornRapier, beetleBlade, moonTalon
    // Axes
    case pebbleHatchet, hornCleaver, toadstoolChopper
    // Shields
    case barkBuckler, shellShield, beetleAegis
    // Class weapons: Guard mauls, Thornshot bows, Sporecaster wands, Dewkeeper staves
    case toadstoolMaul, boughHammer
    case reedBow, owlboneBow
    case puffballWand, glowcapScepter
    case dewdropStaff, raincallerStaff
    // Hats
    case acornCap, beetleHelm
    // Body
    case leafTunic, barkMail, featherCloak
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
    /// Weapons only.
    public let weaponType: WeaponType?

    /// Only this class may equip it; nil = anyone.
    public var requiredClass: PlayerClass? { weaponType?.playerClass }

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
        case .owlFeather:
            item("Hollow Owl Feather", "Soft as moonlight. Proof you survived the night.", .material, sell: 150, stack: 50)
        case .twigSword:
            weapon("Twig Sword", "Every hero starts somewhere.", .sword, StatBonus(attack: 4),
                   level: 1, buy: 40, sell: 10)
        case .thornRapier:
            weapon("Thorn Rapier", "A bramble thorn with a leather grip.", .sword, StatBonus(attack: 9),
                   level: 5, buy: 180, sell: 45)
        case .beetleBlade:
            weapon("Beetle-Horn Blade", "Glossy, sharp, and smug about it.", .sword, StatBonus(attack: 16, maxMP: 10),
                   level: 9, sell: 120)
        case .moonTalon:
            weapon("Moonlit Talon", "Still cold from the night sky.", .sword, StatBonus(attack: 26, maxMP: 20),
                   level: 15, sell: 400)
        case .pebbleHatchet:
            weapon("Pebble Hatchet", "A river stone lashed to a stick. Slow, but it thunks.", .axe, StatBonus(attack: 6),
                   level: 2, buy: 70, sell: 17)
        case .hornCleaver:
            weapon("Horn Cleaver", "A beetle horn ground into a wicked edge.", .axe, StatBonus(attack: 14, maxHP: 15),
                   level: 7, sell: 95)
        case .toadstoolChopper:
            weapon("Toadstool Chopper", "Heavy, spotted, and faintly glowing.", .axe, StatBonus(attack: 22, maxHP: 30),
                   level: 11, sell: 160)
        case .barkBuckler:
            item("Bark Buckler", "A round of oak bark. Knocks the odd bite aside.",
                 .equipment(.shield, StatBonus(defense: 2, block: 0.05)), level: 2, buy: 60, sell: 15)
        case .shellShield:
            item("Shell Shield", "A snail's old house, now yours.",
                 .equipment(.shield, StatBonus(defense: 4, maxHP: 15, block: 0.07)), level: 6, buy: 240, sell: 60)
        case .beetleAegis:
            item("Beetle Aegis", "A wing case polished to a mirror shine.",
                 .equipment(.shield, StatBonus(defense: 7, maxHP: 30, block: 0.1)), level: 10, sell: 140)
        case .toadstoolMaul:
            weapon("Toadstool Maul", "A whole toadstool on a pole. Guards only.", .maul, StatBonus(attack: 52, maxHP: 40),
                   level: 15, buy: 1_100, sell: 275)
        case .boughHammer:
            weapon("Great Bough Hammer", "Knotwood from the Great Bough itself.", .maul, StatBonus(attack: 80, maxHP: 90),
                   level: 22, sell: 700)
        case .reedBow:
            weapon("Reed Bow", "Springy fen reed and a spider-silk string. Thornshots only.", .bow, StatBonus(attack: 30),
                   level: 15, buy: 1_100, sell: 275)
        case .owlboneBow:
            weapon("Owlbone Longbow", "Strung with a single owl whisker.", .bow, StatBonus(attack: 48, maxMP: 20),
                   level: 22, sell: 700)
        case .puffballWand:
            weapon("Puffball Wand", "Tap gently. Sporecasters only.", .wand, StatBonus(attack: 24, maxMP: 40),
                   level: 15, buy: 1_100, sell: 275)
        case .glowcapScepter:
            weapon("Glowcap Scepter", "Hums in the dark.", .wand, StatBonus(attack: 38, maxMP: 80),
                   level: 22, sell: 700)
        case .dewdropStaff:
            weapon("Dewdrop Staff", "A single perfect droplet, held in a twist of vine. Dewkeepers only.", .staff,
                   StatBonus(attack: 20, maxHP: 30, maxMP: 40), level: 15, buy: 1_100, sell: 275)
        case .raincallerStaff:
            weapon("Raincaller Staff", "The air smells of rain around it.", .staff, StatBonus(attack: 32, maxHP: 60, maxMP: 70),
                   level: 22, sell: 700)
        case .featherCloak:
            item("Feathered Cloak", "Woven from the Hollow Owl's down.", .equipment(.body, StatBonus(defense: 12, maxHP: 80)),
                 level: 15, sell: 400)
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
                       buyPrice: buy, sellPrice: sell, maxStack: stack, weaponType: nil)
    }

    private func weapon(_ name: String, _ description: String, _ type: WeaponType, _ bonus: StatBonus,
                        level: Int, buy: Int? = nil, sell: Int) -> ItemDefinition {
        ItemDefinition(id: self, name: name, description: description, kind: .equipment(.weapon, bonus), requiredLevel: level,
                       buyPrice: buy, sellPrice: sell, maxStack: 1, weaponType: type)
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
