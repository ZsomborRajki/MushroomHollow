public enum EquipSlot: String, Codable, Sendable, CaseIterable {
    case weapon, shield, hat, body, gloves, boots

    /// Hat, body, gloves, and boots: the four pieces of an armor set.
    public var isArmor: Bool {
        switch self {
        case .hat, .body, .gloves, .boots: true
        case .weapon, .shield: false
        }
    }
}

/// How special an item is (the client colors names by it).
public enum Rarity: String, Codable, Sendable {
    /// Standard gear: sold in shops or dropped by mobs of its level.
    case common
    /// A piece of a four-part armor set.
    case set
    /// Dropped by a world boss.
    case unique
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
    /// Fraction faster auto-attacks (0.15 = 15% faster). Set bonuses.
    public var attackSpeed: Float = 0
    /// Extra critical-hit chance (0...1). Set bonuses.
    public var critical: Float = 0

    public init(attack: Int = 0, defense: Int = 0, maxHP: Int = 0, maxMP: Int = 0, block: Float = 0,
                attackSpeed: Float = 0, critical: Float = 0) {
        self.attack = attack
        self.defense = defense
        self.maxHP = maxHP
        self.maxMP = maxMP
        self.block = block
        self.attackSpeed = attackSpeed
        self.critical = critical
    }

    public static func + (a: StatBonus, b: StatBonus) -> StatBonus {
        StatBonus(attack: a.attack + b.attack, defense: a.defense + b.defense,
                  maxHP: a.maxHP + b.maxHP, maxMP: a.maxMP + b.maxMP, block: a.block + b.block,
                  attackSpeed: a.attackSpeed + b.attackSpeed, critical: a.critical + b.critical)
    }
}

public enum ItemID: String, Codable, Sendable, CaseIterable {
    // Consumables
    case dewPotion, nectarVial
    // Materials
    case snailShell, slugSlime, beetleHorn, sporeSac, owlFeather
    // Upgrading (mob drops only): the stone every attempt needs, and the charm that protects the item
    case amberShard, wardCharm
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
    // Gloves
    case grassMitts, chitinGauntlets
    // Boots
    case mossBoots, barkTreads
    // Sets (see `ItemSet`): the Dewleaf set for anyone at level 5, then one per class at 15
    case dewleafCap, dewleafVest, dewleafGloves, dewleafSlippers
    case heartwoodHelm, heartwoodPlate, heartwoodGauntlets, heartwoodGreaves
    case briarHood, briarJerkin, briarBracers, briarTreads
    case myceliumCowl, myceliumRobe, myceliumGloves, myceliumSlippers
    case rainpetalCirclet, rainpetalGown, rainpetalMitts, rainpetalSandals
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
    public let rarity: Rarity

    /// The armor set this piece belongs to.
    public var set: ItemSet? { ItemSet.allCases.first { $0.definition.pieces.contains(id) } }

    /// Only this class may equip it; nil = anyone.
    public var requiredClass: PlayerClass? { weaponType?.playerClass ?? set?.definition.playerClass }

    /// Gear can be upgraded at a blacksmith.
    public var isUpgradable: Bool { equipSlot != nil }

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
                   level: 15, sell: 400, rarity: .unique)
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
                   level: 22, sell: 700, rarity: .unique)
        case .reedBow:
            weapon("Reed Bow", "Springy fen reed and a spider-silk string. Thornshots only.", .bow, StatBonus(attack: 30),
                   level: 15, buy: 1_100, sell: 275)
        case .owlboneBow:
            weapon("Owlbone Longbow", "Strung with a single owl whisker.", .bow, StatBonus(attack: 48, maxMP: 20),
                   level: 22, sell: 700, rarity: .unique)
        case .puffballWand:
            weapon("Puffball Wand", "Tap gently. Sporecasters only.", .wand, StatBonus(attack: 24, maxMP: 40),
                   level: 15, buy: 1_100, sell: 275)
        case .glowcapScepter:
            weapon("Glowcap Scepter", "Hums in the dark.", .wand, StatBonus(attack: 38, maxMP: 80),
                   level: 22, sell: 700, rarity: .unique)
        case .dewdropStaff:
            weapon("Dewdrop Staff", "A single perfect droplet, held in a twist of vine. Dewkeepers only.", .staff,
                   StatBonus(attack: 20, maxHP: 30, maxMP: 40), level: 15, buy: 1_100, sell: 275)
        case .raincallerStaff:
            weapon("Raincaller Staff", "The air smells of rain around it.", .staff, StatBonus(attack: 32, maxHP: 60, maxMP: 70),
                   level: 22, sell: 700, rarity: .unique)
        case .featherCloak:
            item("Feathered Cloak", "Woven from the Hollow Owl's down.", .equipment(.body, StatBonus(defense: 12, maxHP: 80)),
                 level: 15, sell: 400, rarity: .unique)
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
        case .grassMitts:
            item("Grass Mitts", "Woven blades of grass. Better than bare knuckles.", .equipment(.gloves, StatBonus(attack: 1, defense: 1)),
                 level: 1, buy: 30, sell: 7)
        case .chitinGauntlets:
            item("Chitin Gauntlets", "Beetle plates over the knuckles.", .equipment(.gloves, StatBonus(attack: 3, defense: 3, maxHP: 10)),
                 level: 8, sell: 85)
        case .mossBoots:
            item("Moss Boots", "Soft, quiet, a little damp.", .equipment(.boots, StatBonus(defense: 1, maxHP: 5, maxMP: 10)),
                 level: 1, buy: 35, sell: 8)
        case .barkTreads:
            item("Bark Treads", "Thick soles for rough roots.", .equipment(.boots, StatBonus(defense: 3, maxHP: 15, maxMP: 10)),
                 level: 7, sell: 80)
        case .amberShard:
            item("Amber Shard", "Tree resin, hardened for an age. Blacksmiths need one for every upgrade.", .material,
                 sell: 20, stack: 99)
        case .wardCharm:
            item("Ward Charm", "Keeps gear safe if an upgrade fails. Used up on any risky attempt.", .material,
                 sell: 150, stack: 20)

        // Dewleaf set (level 5, anyone): each piece drops from a different zone.
        case .dewleafCap:
            setPiece("Dewleaf Cap", "Snail-silver thread on a young leaf.", .hat, StatBonus(defense: 3, maxHP: 15), level: 5, sell: 60)
        case .dewleafVest:
            setPiece("Dewleaf Vest", "Still wet with the glade's dew.", .body, StatBonus(defense: 5, maxHP: 25), level: 5, sell: 60)
        case .dewleafGloves:
            setPiece("Dewleaf Gloves", "Cool to the touch, even at noon.", .gloves, StatBonus(attack: 2, defense: 2), level: 5, sell: 60)
        case .dewleafSlippers:
            setPiece("Dewleaf Slippers", "You leave little wet footprints.", .boots, StatBonus(defense: 2, maxHP: 10, maxMP: 10),
                     level: 5, sell: 60)

        // Guard set: Heartwood.
        case .heartwoodHelm:
            setPiece("Heartwood Helm", "Carved from the Great Tree's core.", .hat, StatBonus(defense: 8, maxHP: 50), level: 15, sell: 350)
        case .heartwoodPlate:
            setPiece("Heartwood Plate", "Rings of a thousand years, strapped on.", .body, StatBonus(defense: 14, maxHP: 90),
                     level: 15, sell: 350)
        case .heartwoodGauntlets:
            setPiece("Heartwood Gauntlets", "Knuckles like knots.", .gloves, StatBonus(attack: 4, defense: 6, maxHP: 30),
                     level: 15, sell: 350)
        case .heartwoodGreaves:
            setPiece("Heartwood Greaves", "Rooted. Immovable.", .boots, StatBonus(defense: 6, maxHP: 40), level: 15, sell: 350)

        // Thornshot set: Briar.
        case .briarHood:
            setPiece("Briar Hood", "Hides you in the brambles.", .hat, StatBonus(attack: 3, defense: 5, maxHP: 30), level: 15, sell: 350)
        case .briarJerkin:
            setPiece("Briar Jerkin", "Thorny side out.", .body, StatBonus(defense: 9, maxHP: 55), level: 15, sell: 350)
        case .briarBracers:
            setPiece("Briar Bracers", "Steady arms, straight shots.", .gloves, StatBonus(attack: 6, defense: 3), level: 15, sell: 350)
        case .briarTreads:
            setPiece("Briar Treads", "Silent on dry leaves.", .boots, StatBonus(defense: 4, maxHP: 25, maxMP: 15), level: 15, sell: 350)

        // Sporecaster set: Mycelium.
        case .myceliumCowl:
            setPiece("Mycelium Cowl", "Whispers from the underground.", .hat, StatBonus(defense: 4, maxMP: 40), level: 15, sell: 350)
        case .myceliumRobe:
            setPiece("Mycelium Robe", "Threads that grow back when torn.", .body, StatBonus(defense: 8, maxHP: 40, maxMP: 60),
                     level: 15, sell: 350)
        case .myceliumGloves:
            setPiece("Mycelium Gloves", "Spores drift from the fingertips.", .gloves, StatBonus(attack: 7, maxMP: 20),
                     level: 15, sell: 350)
        case .myceliumSlippers:
            setPiece("Mycelium Slippers", "Soft as loam.", .boots, StatBonus(defense: 3, maxMP: 30), level: 15, sell: 350)

        // Dewkeeper set: Rainpetal.
        case .rainpetalCirclet:
            setPiece("Rainpetal Circlet", "Petals that never wilt.", .hat, StatBonus(defense: 5, maxHP: 30, maxMP: 30),
                     level: 15, sell: 350)
        case .rainpetalGown:
            setPiece("Rainpetal Gown", "Smells of the first spring rain.", .body, StatBonus(defense: 9, maxHP: 60, maxMP: 40),
                     level: 15, sell: 350)
        case .rainpetalMitts:
            setPiece("Rainpetal Mitts", "Gentle hands, quick to mend.", .gloves, StatBonus(attack: 4, defense: 3, maxMP: 20),
                     level: 15, sell: 350)
        case .rainpetalSandals:
            setPiece("Rainpetal Sandals", "Every step sounds like a raindrop.", .boots, StatBonus(defense: 4, maxHP: 25, maxMP: 25),
                     level: 15, sell: 350)
        case .dandelionSeed:
            item("Dandelion Seed", "Hold on tight and let the breeze do the rest. Lets you fly.", .glider,
                 level: 10, buy: 300, sell: 75)
        }
    }

    private func item(_ name: String, _ description: String, _ kind: ItemDefinition.Kind,
                      level: Int = 1, buy: Int? = nil, sell: Int, stack: Int = 1, rarity: Rarity = .common) -> ItemDefinition {
        ItemDefinition(id: self, name: name, description: description, kind: kind, requiredLevel: level,
                       buyPrice: buy, sellPrice: sell, maxStack: stack, weaponType: nil, rarity: rarity)
    }

    private func weapon(_ name: String, _ description: String, _ type: WeaponType, _ bonus: StatBonus,
                        level: Int, buy: Int? = nil, sell: Int, rarity: Rarity = .common) -> ItemDefinition {
        ItemDefinition(id: self, name: name, description: description, kind: .equipment(.weapon, bonus), requiredLevel: level,
                       buyPrice: buy, sellPrice: sell, maxStack: 1, weaponType: type, rarity: rarity)
    }

    /// Set pieces are never sold in shops.
    private func setPiece(_ name: String, _ description: String, _ slot: EquipSlot, _ bonus: StatBonus,
                          level: Int, sell: Int) -> ItemDefinition {
        ItemDefinition(id: self, name: name, description: description, kind: .equipment(slot, bonus), requiredLevel: level,
                       buyPrice: nil, sellPrice: sell, maxStack: 1, weaponType: nil, rarity: .set)
    }
}

public struct ItemStack: Codable, Sendable, Equatable {
    public let item: ItemID
    public var count: Int
    /// +0...+10 (gear only). Stacks only merge at the same upgrade.
    public var upgrade: Int

    public init(item: ItemID, count: Int, upgrade: Int = 0) {
        self.item = item
        self.count = count
        self.upgrade = upgrade
    }

    /// Saves from before upgrades have no `upgrade`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        item = try container.decode(ItemID.self, forKey: .item)
        count = try container.decode(Int.self, forKey: .count)
        upgrade = try container.decodeIfPresent(Int.self, forKey: .upgrade) ?? 0
    }

    public var gear: Gear { Gear(item, upgrade: upgrade) }
}

/// One piece of gear as it exists in the world: which item, and how far it has been upgraded.
public struct Gear: Codable, Sendable, Hashable {
    public let item: ItemID
    public var upgrade: Int

    public init(_ item: ItemID, upgrade: Int = 0) {
        self.item = item
        self.upgrade = upgrade
    }

    public var definition: ItemDefinition { item.definition }

    /// The item's stats, including its upgrade.
    public var bonus: StatBonus {
        guard case let .equipment(slot, base) = definition.kind else { return StatBonus() }
        return Upgrade.bonus(base, slot: slot, level: upgrade)
    }

    /// Upgraded gear is worth more to a shopkeeper.
    public var sellPrice: Int { definition.sellPrice * (2 + upgrade) / 2 }

    private enum CodingKeys: String, CodingKey { case item, upgrade }

    /// Saves from before upgrades stored equipped gear as a bare `ItemID`.
    public init(from decoder: any Decoder) throws {
        if let legacy = try? decoder.singleValueContainer().decode(ItemID.self) {
            self.init(legacy)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try container.decode(ItemID.self, forKey: .item),
                  upgrade: try container.decodeIfPresent(Int.self, forKey: .upgrade) ?? 0)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(item, forKey: .item)
        try container.encode(upgrade, forKey: .upgrade)
    }
}

/// A bag of stacks with a fixed number of slots.
public struct Inventory: Codable, Sendable, Equatable {
    public static let capacity = 24

    public private(set) var stacks: [ItemStack] = []

    public init() {}

    /// How many of `item` at any upgrade.
    public func count(of item: ItemID) -> Int {
        stacks.reduce(0) { $0 + ($1.item == item ? $1.count : 0) }
    }

    public func count(of item: ItemID, upgrade: Int) -> Int {
        stacks.reduce(0) { $0 + ($1.item == item && $1.upgrade == upgrade ? $1.count : 0) }
    }

    public func canAdd(_ item: ItemID, count: Int, upgrade: Int = 0) -> Bool {
        var probe = self
        return probe.add(item, count: count, upgrade: upgrade) == 0
    }

    /// Adds as much as fits; returns how many didn't.
    @discardableResult
    public mutating func add(_ item: ItemID, count: Int, upgrade: Int = 0) -> Int {
        let maxStack = item.definition.maxStack
        var remaining = count
        for i in stacks.indices where stacks[i].item == item && stacks[i].upgrade == upgrade && remaining > 0 {
            let room = maxStack - stacks[i].count
            let moved = min(room, remaining)
            stacks[i].count += moved
            remaining -= moved
        }
        while remaining > 0, stacks.count < Self.capacity {
            let moved = min(maxStack, remaining)
            stacks.append(ItemStack(item: item, count: moved, upgrade: upgrade))
            remaining -= moved
        }
        return remaining
    }

    /// Removes exactly `count` at `upgrade`, or nothing.
    @discardableResult
    public mutating func remove(_ item: ItemID, count: Int, upgrade: Int = 0) -> Bool {
        guard count > 0, self.count(of: item, upgrade: upgrade) >= count else { return false }
        var remaining = count
        for i in stacks.indices.reversed() where stacks[i].item == item && stacks[i].upgrade == upgrade && remaining > 0 {
            let taken = min(stacks[i].count, remaining)
            stacks[i].count -= taken
            remaining -= taken
        }
        stacks.removeAll { $0.count == 0 }
        return true
    }
}
