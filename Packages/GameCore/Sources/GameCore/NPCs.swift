public enum NPCID: String, Codable, Sendable, CaseIterable {
    case elderMorel
    case chanterelle
}

public struct NPCDefinition: Sendable {
    public let id: NPCID
    public let name: String
    public let title: String
    public let greeting: String
    /// Items for sale; empty = not a shopkeeper.
    public let shopStock: [ItemID]

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
                id: self, name: "Chanterelle", title: "Trader",
                greeting: "Potions, blades, boots! Everything a sprout needs. Selling shells? I'm buying.",
                shopStock: [.dewPotion, .nectarVial, .twigSword, .mossBoots, .acornCap, .leafTunic, .thornRapier, .barkMail])
        }
    }
}
