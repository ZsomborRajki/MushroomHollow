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
    case sapTonic, honeydewDraught, moonNectar
    /// Flyff's Blinkwing: back to town in a flutter.
    case blinkwing
    // Materials: one per mob, to sell or hand in
    case snailShell, slugSlime, beetleHorn, sporeSac, owlFeather
    case spottedWingCase, pillBugPlate, bitterAcorn, frogJelly
    case honeycombChip, pollenPuff, mossyScute, emberScale, spiderSilk, mothDust
    case hedgehogQuill, pineScale, mantisClaw, roseHip, grumbleSpore, stagMandible
    case honeydewDrop, richLoam, cricketLeg
    // Upgrading (mob drops only): the stone every attempt needs, and the charm that protects the item
    case amberShard, wardCharm
    // Swords
    case twigSword, thornRapier, beetleBlade, stingerBlade, moonTalon, silkfangSaber, mantisEdge
    // Axes
    case pebbleHatchet, hornCleaver, toadstoolChopper, mossbackCleaver, quillsplitter, stagjawAxe
    // Shields
    case barkBuckler, shellShield, beetleAegis, lilypadTarge, mossbackShield, pineconeBulwark
    // Class weapons: Guard mauls, Thornshot bows, Sporecaster wands, Dewkeeper staves
    case toadstoolMaul, emberstoneMaul, boughHammer, stagCrusher
    case reedBow, silkstringBow, owlboneBow, mantisLongbow
    case puffballWand, mothwingWand, glowcapScepter, grumblecapScepter
    case dewdropStaff, buttercupStaff, raincallerStaff, thornroseStaff
    // Hats
    case acornCap, beetleHelm, honeycombHelm, pineconeHelm
    // Body
    case leafTunic, barkMail, featherCloak, turtleshellMail, mantisCarapace
    // Gloves
    case grassMitts, chitinGauntlets, silkweaveGloves, rosethornGauntlets
    // Boots
    case mossBoots, barkTreads, frogHoppers, quilledBoots
    // Sets (see `ItemSet`): Dewleaf for anyone at level 5, one per class at 15, Thistledown for anyone at 20
    case dewleafCap, dewleafVest, dewleafGloves, dewleafSlippers
    case thistledownCap, thistledownCoat, thistledownGloves, thistledownBoots
    case heartwoodHelm, heartwoodPlate, heartwoodGauntlets, heartwoodGreaves
    case briarHood, briarJerkin, briarBracers, briarTreads
    case myceliumCowl, myceliumRobe, myceliumGloves, myceliumSlippers
    case rainpetalCirclet, rainpetalGown, rainpetalMitts, rainpetalSandals
    // Key items
    case dandelionSeed
    // Pets (see `PetKind`) and their food
    case pip, kibble
}

public struct ItemDefinition: Sendable {
    public enum Kind: Sendable {
        case consumable(ConsumableEffect)
        case material
        case equipment(EquipSlot, StatBonus)
        /// Owning one lets you fly.
        case glider
        /// A companion that sits in the pet slot.
        case pet(PetKind)
        /// Fills up the pet in the pet slot.
        case petFood
    }

    public enum ConsumableEffect: Sendable {
        case restoreHP(Int)
        case restoreMP(Int)
        /// Back to town (not mid-fight).
        case returnToTown
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
        case .sapTonic:
            item("Sap Tonic", "Thick, amber, and bracing. Restores 180 HP.", .consumable(.restoreHP(180)),
                 level: 10, buy: 32, sell: 8, stack: 20)
        case .honeydewDraught:
            item("Honeydew Draught", "The good stuff, aged in an acorn cup. Restores 420 HP.", .consumable(.restoreHP(420)),
                 level: 20, buy: 75, sell: 18, stack: 20)
        case .moonNectar:
            item("Moon Nectar", "Gathered from night-blooming flowers. Restores 140 MP.", .consumable(.restoreMP(140)),
                 level: 15, buy: 48, sell: 12, stack: 20)
        case .blinkwing:
            item("Blinkwing", "A pressed moth wing. Crumple it and you're home in a flutter. Not mid-fight.",
                 .consumable(.returnToTown), buy: 25, sell: 6, stack: 20)
        case .honeydewDrop:
            item("Honeydew Drop", "Aphids make it; ants would kill for it.", .material, sell: 2, stack: 50)
        case .richLoam:
            item("Rich Loam", "An earthworm's finest work. Dark, crumbly, and prized by gardeners.", .material, sell: 4, stack: 50)
        case .cricketLeg:
            item("Cricket Leg", "Springy. It still twitches when you whistle.", .material, sell: 8, stack: 50)
        case .snailShell:
            item("Snail Shell Shard", "Still faintly spiral.", .material, sell: 2, stack: 50)
        case .slugSlime:
            item("Slug Slime", "Surprisingly useful. Surprisingly sticky.", .material, sell: 3, stack: 50)
        case .beetleHorn:
            item("Beetle Horn", "Hard as bark, twice as pointy.", .material, sell: 6, stack: 50)
        case .sporeSac:
            item("Spore Sac", "Do not squeeze.", .material, sell: 9, stack: 50)
        case .owlFeather:
            item("Hollow Owl Feather", "Soft as moonlight. Proof you survived the night.", .material, sell: 75, stack: 50)
        case .spottedWingCase:
            item("Spotted Wing Case", "Seven spots. Lucky, apparently.", .material, sell: 2, stack: 50)
        case .pillBugPlate:
            item("Pill Bug Plate", "One overlapping plate. It still wants to curl up.", .material, sell: 4, stack: 50)
        case .bitterAcorn:
            item("Bitter Acorn", "Grumpy, even for an acorn.", .material, sell: 7, stack: 50)
        case .frogJelly:
            item("Frog Jelly", "Wobbly, green, and oddly warm.", .material, sell: 10, stack: 50)
        case .honeycombChip:
            item("Honeycomb Chip", "Sticky, golden, and worth the stings.", .material, sell: 12, stack: 50)
        case .pollenPuff:
            item("Pollen Puff", "Achoo.", .material, sell: 13, stack: 50)
        case .mossyScute:
            item("Mossy Scute", "A turtle's shell plate with a little garden on top.", .material, sell: 14, stack: 50)
        case .emberScale:
            item("Ember Scale", "Still smouldering. Carry it in something that isn't a leaf.", .material, sell: 16, stack: 50)
        case .spiderSilk:
            item("Spider Silk", "Stronger than it looks, stickier than you'd like.", .material, sell: 18, stack: 50)
        case .mothDust:
            item("Moth Dust", "Glitters like dusk. Makes your nose itch.", .material, sell: 19, stack: 50)
        case .hedgehogQuill:
            item("Hedgehog Quill", "Hold it by the blunt end.", .material, sell: 20, stack: 50)
        case .pineScale:
            item("Pine Scale", "A pinecone's armor plate, sticky with sap.", .material, sell: 22, stack: 50)
        case .mantisClaw:
            item("Mantis Claw", "Folded politely, like it's praying. It isn't.", .material, sell: 24, stack: 50)
        case .roseHip:
            item("Rose Hip", "Tart, bright, and guarded by a lot of thorns.", .material, sell: 25, stack: 50)
        case .grumbleSpore:
            item("Grumble Spore", "It mutters if you hold it to your ear.", .material, sell: 26, stack: 50)
        case .stagMandible:
            item("Stag Mandible", "Half of the grove king's crown.", .material, sell: 30, stack: 50)
        case .twigSword:
            weapon("Twig Sword", "Every hero starts somewhere.", .sword, StatBonus(attack: 4),
                   level: 1, buy: 40, sell: 10)
        case .thornRapier:
            weapon("Thorn Rapier", "A bramble thorn with a leather grip.", .sword, StatBonus(attack: 9),
                   level: 5, buy: 180, sell: 45)
        case .beetleBlade:
            weapon("Beetle-Horn Blade", "Glossy, sharp, and smug about it.", .sword, StatBonus(attack: 16, maxMP: 10),
                   level: 9, buy: 480, sell: 120)
        case .stingerBlade:
            weapon("Stinger Blade", "A fuzzbee's stinger on a honeycomb grip. Still buzzing.", .sword,
                   StatBonus(attack: 22, maxMP: 15), level: 14, buy: 800, sell: 170)
        case .silkfangSaber:
            weapon("Silkfang Saber", "A spider's fang, bound in its own silk.", .sword,
                   StatBonus(attack: 32, maxMP: 25), level: 20, buy: 1_300, sell: 260)
        case .mantisEdge:
            weapon("Mantis Edge", "Curved, pink, and terribly quick.", .sword,
                   StatBonus(attack: 44, maxMP: 35, critical: 0.03), level: 26, sell: 380)
        case .moonTalon:
            weapon("Moonlit Talon", "Still cold from the night sky.", .sword, StatBonus(attack: 26, maxMP: 20),
                   level: 15, sell: 400, rarity: .unique)
        case .pebbleHatchet:
            weapon("Pebble Hatchet", "A river stone lashed to a stick. Slow, but it thunks.", .axe, StatBonus(attack: 6),
                   level: 2, buy: 70, sell: 17)
        case .hornCleaver:
            weapon("Horn Cleaver", "A beetle horn ground into a wicked edge.", .axe, StatBonus(attack: 14, maxHP: 15),
                   level: 7, buy: 380, sell: 95)
        case .toadstoolChopper:
            weapon("Toadstool Chopper", "Heavy, spotted, and faintly glowing.", .axe, StatBonus(attack: 22, maxHP: 30),
                   level: 11, buy: 640, sell: 160)
        case .mossbackCleaver:
            weapon("Mossback Cleaver", "A turtle scute ground to an edge. Moss included.", .axe,
                   StatBonus(attack: 30, maxHP: 45), level: 17, buy: 1_000, sell: 230)
        case .quillsplitter:
            weapon("Quillsplitter", "Bristling with hedgehog quills. Mind your fingers.", .axe,
                   StatBonus(attack: 42, maxHP: 70), level: 23, sell: 330)
        case .stagjawAxe:
            weapon("Stagjaw Axe", "A stag beetle's mandible on an oak haft. Heavy as a verdict.", .axe,
                   StatBonus(attack: 56, maxHP: 100), level: 29, sell: 450)
        case .barkBuckler:
            item("Bark Buckler", "A round of oak bark. Knocks the odd bite aside.",
                 .equipment(.shield, StatBonus(defense: 2, block: 0.05)), level: 2, buy: 60, sell: 15)
        case .shellShield:
            item("Shell Shield", "A snail's old house, now yours.",
                 .equipment(.shield, StatBonus(defense: 4, maxHP: 15, block: 0.07)), level: 6, buy: 240, sell: 60)
        case .beetleAegis:
            item("Beetle Aegis", "A wing case polished to a mirror shine.",
                 .equipment(.shield, StatBonus(defense: 7, maxHP: 30, block: 0.1)), level: 10, buy: 560, sell: 140)
        case .lilypadTarge:
            item("Lilypad Targe", "Springy, waterproof, and surprisingly hard to get past.",
                 .equipment(.shield, StatBonus(defense: 9, maxHP: 40, block: 0.11)), level: 13, buy: 720, sell: 180)
        case .mossbackShield:
            item("Mossback Shield", "A turtle's shell. It carried its owner; now it carries you.",
                 .equipment(.shield, StatBonus(defense: 12, maxHP: 60, block: 0.12)), level: 18, buy: 1_000, sell: 250)
        case .pineconeBulwark:
            item("Pinecone Bulwark", "Overlapping scales, closed tight.",
                 .equipment(.shield, StatBonus(defense: 17, maxHP: 90, block: 0.14)), level: 25, sell: 360)
        case .emberstoneMaul:
            weapon("Emberstone Maul", "A glowing creek stone on a charred handle. Guards only.", .maul,
                   StatBonus(attack: 66, maxHP: 60), level: 20, buy: 2_400, sell: 420)
        case .stagCrusher:
            weapon("Stag Crusher", "Both mandibles of a stag beetle, bolted to a log.", .maul,
                   StatBonus(attack: 100, maxHP: 130), level: 28, sell: 650)
        case .silkstringBow:
            weapon("Silkstring Bow", "Weaver silk makes a string that sings. Thornshots only.", .bow,
                   StatBonus(attack: 40, maxMP: 15), level: 20, buy: 2_400, sell: 420)
        case .mantisLongbow:
            weapon("Mantis Longbow", "Two mantis claws, bent into one terrible curve.", .bow,
                   StatBonus(attack: 60, maxMP: 30, critical: 0.03), level: 27, sell: 650)
        case .mothwingWand:
            weapon("Mothwing Wand", "Leaves a trail of glittering dust. Sporecasters only.", .wand,
                   StatBonus(attack: 32, maxMP: 60), level: 21, buy: 2_400, sell: 420)
        case .grumblecapScepter:
            weapon("Grumblecap Scepter", "A tiny grumblecap on a stick. It complains when you cast.", .wand,
                   StatBonus(attack: 50, maxMP: 110), level: 28, sell: 650)
        case .buttercupStaff:
            weapon("Buttercup Staff", "Hold it under your chin: you like healing. Dewkeepers only.", .staff,
                   StatBonus(attack: 27, maxHP: 45, maxMP: 55), level: 19, buy: 2_400, sell: 420)
        case .thornroseStaff:
            weapon("Thornrose Staff", "A rose that heals the hand that holds it, and no other.", .staff,
                   StatBonus(attack: 42, maxHP: 90, maxMP: 100), level: 28, sell: 650)
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
                 level: 7, buy: 360, sell: 90)
        case .honeycombHelm:
            item("Honeycomb Helm", "Six-sided, sturdy, faintly sweet.", .equipment(.hat, StatBonus(defense: 7, maxHP: 40)),
                 level: 15, buy: 600, sell: 150)
        case .pineconeHelm:
            item("Pinecone Helm", "Scales all the way up to a point.", .equipment(.hat, StatBonus(defense: 13, maxHP: 80)),
                 level: 24, sell: 300)
        case .leafTunic:
            item("Leaf Tunic", "Stitched from a single oak leaf.", .equipment(.body, StatBonus(defense: 3, maxHP: 15)),
                 level: 3, buy: 90, sell: 22)
        case .barkMail:
            item("Bark Mail", "Overlapping scales of old bark.", .equipment(.body, StatBonus(defense: 7, maxHP: 40)),
                 level: 8, buy: 320, sell: 80)
        case .turtleshellMail:
            item("Turtleshell Mail", "Scutes stitched on leather. Slow to put on, slower to get through.",
                 .equipment(.body, StatBonus(defense: 12, maxHP: 70)), level: 18, buy: 960, sell: 240)
        case .mantisCarapace:
            item("Mantis Carapace", "Orchid-pink plates, light as petals.", .equipment(.body, StatBonus(defense: 18, maxHP: 120)),
                 level: 27, sell: 390)
        case .grassMitts:
            item("Grass Mitts", "Woven blades of grass. Better than bare knuckles.", .equipment(.gloves, StatBonus(attack: 1, defense: 1)),
                 level: 1, buy: 30, sell: 7)
        case .chitinGauntlets:
            item("Chitin Gauntlets", "Beetle plates over the knuckles.", .equipment(.gloves, StatBonus(attack: 3, defense: 3, maxHP: 10)),
                 level: 8, buy: 340, sell: 85)
        case .silkweaveGloves:
            item("Silkweave Gloves", "Grippy. Very grippy.", .equipment(.gloves, StatBonus(attack: 6, defense: 5, maxHP: 25)),
                 level: 21, buy: 1_000, sell: 250)
        case .rosethornGauntlets:
            item("Rosethorn Gauntlets", "Thorns on the outside, velvet within.",
                 .equipment(.gloves, StatBonus(attack: 9, defense: 8, maxHP: 40)), level: 28, sell: 400)
        case .mossBoots:
            item("Moss Boots", "Soft, quiet, a little damp.", .equipment(.boots, StatBonus(defense: 1, maxHP: 5, maxMP: 10)),
                 level: 1, buy: 35, sell: 8)
        case .barkTreads:
            item("Bark Treads", "Thick soles for rough roots.", .equipment(.boots, StatBonus(defense: 3, maxHP: 15, maxMP: 10)),
                 level: 7, buy: 320, sell: 80)
        case .frogHoppers:
            item("Frog Hoppers", "Springy soles. You bounce a little when you walk.",
                 .equipment(.boots, StatBonus(defense: 5, maxHP: 25, maxMP: 15)), level: 13, buy: 560, sell: 140)
        case .quilledBoots:
            item("Quilled Boots", "Nobody steps on your toes twice.", .equipment(.boots, StatBonus(defense: 8, maxHP: 40, maxMP: 20)),
                 level: 24, sell: 300)
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

        // Thistledown set (level 20, anyone): each piece drops in a different zone of the outer ring.
        case .thistledownCap:
            setPiece("Thistledown Cap", "Light as a seed on the wind.", .hat, StatBonus(defense: 9, maxHP: 45), level: 20, sell: 200)
        case .thistledownCoat:
            setPiece("Thistledown Coat", "Warm as a nest, soft as a cloud.", .body, StatBonus(defense: 13, maxHP: 75),
                     level: 20, sell: 200)
        case .thistledownGloves:
            setPiece("Thistledown Gloves", "Your blows land softly. Then they don't.", .gloves,
                     StatBonus(attack: 5, defense: 5, maxHP: 15), level: 20, sell: 200)
        case .thistledownBoots:
            setPiece("Thistledown Boots", "Every step, a little float.", .boots, StatBonus(defense: 6, maxHP: 30, maxMP: 25),
                     level: 20, sell: 200)

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
        case .pip:
            item("Pip", "A pocket-sized pup with a nose for loot. Put her in your pet slot and she'll fetch what you drop.",
                 .pet(.pup), sell: 0)
        case .kibble:
            item("Kibble", "Truffle's crunchy bites, baked from critter drops. Pets love them.", .petFood,
                 sell: 0, stack: 200)
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
