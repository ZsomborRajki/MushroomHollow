public enum NPCID: String, Codable, Sendable, CaseIterable {
    case elderMorel
    case chanterelle
    case shiitake
    case truffle
    case porcini
    case oyster
    case enoki
    case maitake
}

public struct NPCDefinition: Sendable {
    public let id: NPCID
    public let name: String
    public let title: String
    public let greeting: String
    /// Items for sale; empty = not a shopkeeper.
    public let shopStock: [ItemID]
    /// A blacksmith: upgrades gear.
    public var upgradesGear = false
    /// A pet keeper: turns mob materials into Kibble.
    public var makesPetFood = false
    /// A naturalist: buys mob materials for XP and caps (see `Bounties.swift`).
    public var buysMaterials = false

    public var isShopkeeper: Bool { !shopStock.isEmpty }
    public var givesQuests: Bool { QuestID.allCases.contains { $0.definition.giver == id } }
}

extension NPCID {
    /// How close (center to center) a player must be to talk, trade, or hand in quests.
    public static let interactionRange: Float = 3.5

    public var definition: NPCDefinition {
        switch self {
        case .elderMorel:
            NPCDefinition(
                id: self, name: "Elder Morel", title: "Village Elder",
                greeting: "Ah, a fresh sprout! The roots have been restless lately. Care to help an old morel?",
                shopStock: [])
        case .chanterelle:
            NPCDefinition(
                id: self, name: "Chanterelle", title: "General Store",
                greeting: "Potions, tonics, Blinkwings! Never leave town without a stack of each. And I'll buy whatever's weighing down your bag.",
                shopStock: [.dewPotion, .sapTonic, .honeydewDraught, .nectarVial, .moonNectar, .blinkwing, .dandelionSeed])
        case .shiitake:
            NPCDefinition(
                id: self, name: "Shiitake", title: "Blacksmith",
                greeting: "Bring me amber from the wilds and I'll make that gear sing. Past +5 it gets dicey, mind.",
                shopStock: [], upgradesGear: true)
        case .truffle:
            NPCDefinition(
                id: self, name: "Truffle", title: "Pet Keeper",
                greeting: "Mind the tail! Bring me whatever the critters drop and I'll bake it into kibble. Hungry pets are slow pets.",
                shopStock: [], makesPetFood: true)
        case .porcini:
            NPCDefinition(
                id: self, name: "Porcini", title: "Naturalist",
                greeting: "Specimens! Every critter under the tree leaves something behind, and I'm cataloguing the lot. Bring me what they drop and I'll pay you in caps and know-how.",
                shopStock: [], buysMaterials: true)
        case .oyster:
            NPCDefinition(
                id: self, name: "Oyster", title: "Weapon Shop",
                greeting: "Swords, axes, and every class weapon a sprout could grow into. A new blade every few levels keeps the critters honest.",
                shopStock: [.twigSword, .pebbleHatchet, .thornRapier, .hornCleaver, .beetleBlade, .toadstoolChopper,
                            .stingerBlade, .mossbackCleaver, .silkfangSaber,
                            .toadstoolMaul, .reedBow, .puffballWand, .dewdropStaff,
                            .emberstoneMaul, .silkstringBow, .mothwingWand, .buttercupStaff])
        case .enoki:
            NPCDefinition(
                id: self, name: "Enoki", title: "Armor Shop",
                greeting: "Hats, coats, gloves, boots, shields. Dress for the field you're walking into, not the one you left.",
                shopStock: [.acornCap, .beetleHelm, .honeycombHelm, .leafTunic, .barkMail, .turtleshellMail,
                            .grassMitts, .chitinGauntlets, .silkweaveGloves, .mossBoots, .barkTreads, .frogHoppers,
                            .barkBuckler, .shellShield, .beetleAegis, .lilypadTarge, .mossbackShield])
        case .maitake:
            NPCDefinition(
                id: self, name: "Maitake", title: "Request Board",
                greeting: "The board's full again. Every field around town has a request on it, and I pay the moment you're done. Come back as often as you like.",
                shopStock: [])
        }
    }
}
