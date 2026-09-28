public enum QuestID: String, Codable, Sendable, CaseIterable {
    case shellShock
    case slipperySituation
    case barkBeetles
    case sporeSeason
    case hollowOwl
    // The outer ring, after Spore Season
    case buzzkill
    case shellCollector
    case tangledUp
    case pricklyBusiness
    case prayingForRain
    case kingOfTheGrove
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
        case let .defeat(kind, count): "Defeat \(count) \(count == 1 ? kind.displayName : kind.pluralName)"
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
                rewardItems: [ItemStack(item: .beetleHelm, count: 1), ItemStack(item: .amberShard, count: 3)])
        case .sporeSeason:
            QuestDefinition(
                id: self, title: "Spore Season",
                story: "The Spore Fen is swelling. Bring me spore sacs so we can brew a cure, and don't breathe the purple clouds.",
                giver: .elderMorel, requiredLevel: 10, prerequisite: .barkBeetles,
                objective: .collect(.sporeSac, count: 5),
                rewardXP: 1500, rewardCaps: 300,
                rewardItems: [ItemStack(item: .beetleBlade, count: 1), ItemStack(item: .amberShard, count: 5),
                              ItemStack(item: .wardCharm, count: 1)])
        case .hollowOwl:
            QuestDefinition(
                id: self, title: "The Hollow Owl",
                story: "On dark nights something vast perches in the Great Bough. It took my grandmother's hat. Bring the forest peace.",
                giver: .elderMorel, requiredLevel: 15, prerequisite: .sporeSeason,
                objective: .defeat(.owl, count: 1),
                rewardXP: 3000, rewardCaps: 600,
                rewardItems: [ItemStack(item: .dewPotion, count: 5), ItemStack(item: .nectarVial, count: 5)])
        case .buzzkill:
            QuestDefinition(
                id: self, title: "Buzzkill",
                story: "Past the root tips lies Buttercup Meadow, and its fuzzbees have started raiding our honey jars. Teach them some manners.",
                giver: .elderMorel, requiredLevel: 14, prerequisite: .sporeSeason,
                objective: .defeat(.fuzzbee, count: 8),
                rewardXP: 2_000, rewardCaps: 400,
                rewardItems: [ItemStack(item: .dewPotion, count: 5), ItemStack(item: .amberShard, count: 4)])
        case .shellCollector:
            QuestDefinition(
                id: self, title: "Shell Collector",
                story: "The old turtles of Mossback Creek shed scutes that make the best roof tiles. They don't shed them willingly, and mind the newts: they bite hot.",
                giver: .elderMorel, requiredLevel: 17, prerequisite: .buzzkill,
                objective: .collect(.mossyScute, count: 6),
                rewardXP: 3_000, rewardCaps: 550,
                rewardItems: [ItemStack(item: .amberShard, count: 5), ItemStack(item: .wardCharm, count: 1)])
        case .tangledUp:
            QuestDefinition(
                id: self, title: "Tangled Up",
                story: "Weaver spiders have strung Silkshade Thicket shut. Cut a way through, and don't get stuck in their webs.",
                giver: .elderMorel, requiredLevel: 20, prerequisite: .shellCollector,
                objective: .defeat(.weaverSpider, count: 8),
                rewardXP: 4_200, rewardCaps: 700,
                rewardItems: [ItemStack(item: .silkweaveGloves, count: 1), ItemStack(item: .nectarVial, count: 5)])
        case .pricklyBusiness:
            QuestDefinition(
                id: self, title: "Prickly Business",
                story: "Hedgehog quills make the finest sewing needles. Bring some from Pinecone Rise, and jump aside when they roll.",
                giver: .elderMorel, requiredLevel: 23, prerequisite: .tangledUp,
                objective: .collect(.hedgehogQuill, count: 6),
                rewardXP: 5_500, rewardCaps: 900,
                rewardItems: [ItemStack(item: .amberShard, count: 8), ItemStack(item: .wardCharm, count: 1)])
        case .prayingForRain:
            QuestDefinition(
                id: self, title: "Praying for Rain",
                story: "The orchid mantises of the Briar Tangle strike faster than you can blink. Thin them out before they wander this way.",
                giver: .elderMorel, requiredLevel: 26, prerequisite: .pricklyBusiness,
                objective: .defeat(.mantis, count: 8),
                rewardXP: 7_000, rewardCaps: 1_100,
                rewardItems: [ItemStack(item: .pineconeHelm, count: 1), ItemStack(item: .dewPotion, count: 8)])
        case .kingOfTheGrove:
            QuestDefinition(
                id: self, title: "King of the Grove",
                story: "In Stagshade Grove the stag beetles lock horns all day. Best the strongest bugs under the tree and you'll be a legend of the Hollow.",
                giver: .elderMorel, requiredLevel: 28, prerequisite: .prayingForRain,
                objective: .defeat(.stagBeetle, count: 5),
                rewardXP: 9_000, rewardCaps: 1_500,
                rewardItems: [ItemStack(item: .amberShard, count: 10), ItemStack(item: .wardCharm, count: 2)])
        }
    }
}
