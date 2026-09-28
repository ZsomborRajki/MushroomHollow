public enum QuestID: String, Codable, Sendable, CaseIterable {
    case shellShock
    case slipperySituation
    case barkBeetles
    case sporeSeason
}

public enum QuestObjective: Sendable, Equatable {
    case defeat(MobKind, count: Int)
    case collect(ItemID, count: Int)

    public var goal: Int {
        switch self {
        case let .defeat(_, count), let .collect(_, count): count
        }
    }

    public var summary: String {
        switch self {
        case let .defeat(kind, count): "Defeat \(count) \(kind.displayName)s"
        case let .collect(item, count): "Collect \(count) \(item.definition.name)"
        }
    }
}

public struct QuestDefinition: Sendable {
    public let id: QuestID
    public let title: String
    public let story: String
    public let giver: NPCID
    public let requiredLevel: Int
    public let prerequisite: QuestID?
    public let objective: QuestObjective
    public let rewardXP: Int
    public let rewardCaps: Int
    public let rewardItems: [ItemStack]
}

public enum QuestState: Codable, Sendable, Equatable {
    /// Prerequisites unmet; don't show it.
    case hidden
    case tooLowLevel(required: Int)
    case available
    case active(progress: Int, goal: Int)
    case readyToTurnIn
    case completed
}

public struct QuestStatus: Codable, Sendable, Equatable, Identifiable {
    public let id: QuestID
    public let state: QuestState
}

extension QuestID {
    public var definition: QuestDefinition {
        switch self {
        case .shellShock:
            QuestDefinition(
                id: self, title: "Shell Shock",
                story: "Snails from Dewleaf Glade keep nibbling the village mushrooms. Chase a few of them off, would you?",
                giver: .elderMorel, requiredLevel: 1, prerequisite: nil,
                objective: .defeat(.snail, count: 6),
                rewardXP: 60, rewardCaps: 30,
                rewardItems: [ItemStack(item: .twigSword, count: 1), ItemStack(item: .dewPotion, count: 3)])
        case .slipperySituation:
            QuestDefinition(
                id: self, title: "A Slippery Situation",
                story: "Slug slime makes the finest glue for patching caps. The slugs of the Root Maze won't share it willingly.",
                giver: .elderMorel, requiredLevel: 3, prerequisite: .shellShock,
                objective: .collect(.slugSlime, count: 5),
                rewardXP: 180, rewardCaps: 60,
                rewardItems: [ItemStack(item: .leafTunic, count: 1), ItemStack(item: .nectarVial, count: 3)])
        case .barkBeetles:
            QuestDefinition(
                id: self, title: "Bark Beetles",
                story: "Beetles in Barkfall Hollow are chewing the Great Tree itself. Watch their charge: step aside when they lower their heads!",
                giver: .elderMorel, requiredLevel: 7, prerequisite: .slipperySituation,
                objective: .defeat(.beetle, count: 6),
                rewardXP: 650, rewardCaps: 150,
                rewardItems: [ItemStack(item: .beetleHelm, count: 1)])
        case .sporeSeason:
            QuestDefinition(
                id: self, title: "Spore Season",
                story: "The Spore Fen is swelling. Bring me spore sacs so we can brew a cure, and don't breathe the purple clouds.",
                giver: .elderMorel, requiredLevel: 10, prerequisite: .barkBeetles,
                objective: .collect(.sporeSac, count: 5),
                rewardXP: 1500, rewardCaps: 300,
                rewardItems: [ItemStack(item: .beetleBlade, count: 1)])
        }
    }
}
