/// Quests. Saves store these raw values, so never rename or remove a case (retell it instead).
public enum QuestID: String, Codable, Sendable, CaseIterable {
    // The main story (`mainStory`), one quest after another, clockwise round the tree and out along the
    // outer ring: one species per quest, handed out by whoever in the village needs it most.
    // Dewleaf Glade
    case shellShock, spotsBeforeYourEyes, fieldNotes
    // Root Maze
    case slipperySituation, rolyPoly
    // Barkfall Hollow
    case barkBeetles, toughNuts
    // Spore Fen
    case sporeSeason, bogHoppers
    // Buttercup Meadow
    case buzzkill, somethingInTheAir
    // Mossback Creek
    case shellCollector, playingWithFire
    // Silkshade Thicket
    case tangledUp, drawnToTheLight
    // Pinecone Rise
    case pricklyBusiness, knightsOfTheCone
    // Briar Tangle
    case prayingForRain, everyRose
    // Stagshade Grove
    case grumblingUnderground, kingOfTheGrove

    // Side quests
    /// The world boss (only out at night, so it never blocks the story).
    case hollowOwl
    /// Truffle's: your first pet.
    case aNoseForTrouble

    /// In order: each one opens once the one before it is done.
    public static let mainStory: [QuestID] = allCases.filter { $0 != .hollowOwl && $0 != .aNoseForTrouble }

    /// The main-story quest that opens when this one is done.
    public var next: QuestID? {
        guard let index = Self.mainStory.firstIndex(of: self), index + 1 < Self.mainStory.count else { return nil }
        return Self.mainStory[index + 1]
    }

    /// The main-story quest this one follows.
    var previous: QuestID? {
        guard let index = Self.mainStory.firstIndex(of: self), index > 0 else { return nil }
        return Self.mainStory[index - 1]
    }
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

    /// Part of the one long story around the tree (the rest are side quests).
    public var isMainStory: Bool { QuestID.mainStory.contains(id) }
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
        // MARK: Dewleaf Glade
        case .shellShock:
            story("Shell Shock", giver: .elderMorel, level: 1,
                  "Snails from Dewleaf Glade keep nibbling the village mushrooms. They won't start a fight, but they'll fight back once you swing. Chase five of them off, would you?",
                  .defeat(.snail, count: 5), xp: 60, caps: 30,
                  [ItemStack(item: .twigSword, count: 1), ItemStack(item: .dewPotion, count: 3)])
        case .spotsBeforeYourEyes:
            story("Spots Before Your Eyes", giver: .chanterelle, level: 2,
                  "Ladybug wing cases make the loveliest buttons, and my stall's clean out. The ladybugs over in the glade leave them behind. Four should do!",
                  .collect(.spottedWingCase, count: 4), xp: 90, caps: 40,
                  [ItemStack(item: .grassMitts, count: 1), ItemStack(item: .dewPotion, count: 2)])
        case .fieldNotes:
            story("Field Notes", giver: .porcini, level: 3,
                  "I'm writing the first proper field guide to the Hollow! Five snail shell shards will start the collection. After that, bring me anything the critters drop: caps for your purse, and a lesson for your head.",
                  .collect(.snailShell, count: 5), xp: 150, caps: 50,
                  [ItemStack(item: .barkBuckler, count: 1), ItemStack(item: .nectarVial, count: 2)])

        // MARK: Root Maze
        case .slipperySituation:
            story("A Slippery Situation", giver: .elderMorel, level: 4,
                  "Slug slime makes the finest glue for patching caps. The slugs of the Root Maze won't share it willingly, and a few of them will come at you on sight. Mind the slime trails.",
                  .collect(.slugSlime, count: 5), xp: 250, caps: 70,
                  [ItemStack(item: .leafTunic, count: 1), ItemStack(item: .nectarVial, count: 3)])
        case .rolyPoly:
            story("Roly-Poly", giver: .shiitake, level: 5,
                  "Pill bug plates make perfect rivets. Bring me five from the Root Maze and I'll throw in some amber. Try an upgrade while you're here; the first few never fail.",
                  .collect(.pillBugPlate, count: 5), xp: 380, caps: 90,
                  [ItemStack(item: .amberShard, count: 4), ItemStack(item: .dewPotion, count: 3)])

        // MARK: Barkfall Hollow
        case .barkBeetles:
            story("Bark Beetles", giver: .elderMorel, level: 7,
                  "Beetles in Barkfall Hollow are chewing the Great Tree itself. Watch their charge: step aside when they lower their heads!",
                  .defeat(.beetle, count: 6), xp: 700, caps: 150,
                  [ItemStack(item: .beetleHelm, count: 1), ItemStack(item: .amberShard, count: 3)])
        case .toughNuts:
            story("Tough Nuts", giver: .chanterelle, level: 8,
                  "Acornlings! Grumpy little things, but their bitter acorns brew a tonic folk queue up for. Six, please, from Barkfall Hollow.",
                  .collect(.bitterAcorn, count: 6), xp: 850, caps: 180,
                  [ItemStack(item: .barkTreads, count: 1), ItemStack(item: .dewPotion, count: 5)])

        // MARK: Spore Fen
        case .sporeSeason:
            story("Spore Season", giver: .porcini, level: 10,
                  "The Spore Fen is swelling. I need spore sacs to study the bloom, and Elder Morel wants a cure. Don't breathe the purple clouds, and mind what comes out when a spore beast pops.",
                  .collect(.sporeSac, count: 5), xp: 1_300, caps: 300,
                  [ItemStack(item: .beetleBlade, count: 1), ItemStack(item: .amberShard, count: 5),
                   ItemStack(item: .wardCharm, count: 1)])
        case .bogHoppers:
            story("Bog Hoppers", giver: .shiitake, level: 12,
                  "Bog frogs keep hopping off with my tongs, and they leap before they bite. Clear six of them out of the fen. Once you're fifteen, see Elder Morel about choosing a path.",
                  .defeat(.bogFrog, count: 6), xp: 1_800, caps: 350,
                  [ItemStack(item: .lilypadTarge, count: 1), ItemStack(item: .amberShard, count: 5)])

        // MARK: Buttercup Meadow
        case .buzzkill:
            story("Buzzkill", giver: .chanterelle, level: 14,
                  "Past the root tips lies Buttercup Meadow, and its fuzzbees keep raiding my honey jars. Take the south road out of the village and teach them some manners.",
                  .defeat(.fuzzbee, count: 7), xp: 2_300, caps: 400,
                  [ItemStack(item: .dewPotion, count: 5), ItemStack(item: .amberShard, count: 4)])
        case .somethingInTheAir:
            story("Something in the Air", giver: .porcini, level: 16,
                  "Puffweeds! They burst into pufflings when popped, you know. I need six pollen puffs pressed for the guide. Achoo.",
                  .collect(.pollenPuff, count: 6), xp: 2_900, caps: 480,
                  [ItemStack(item: .nectarVial, count: 5), ItemStack(item: .amberShard, count: 4)])

        // MARK: Mossback Creek
        case .shellCollector:
            story("Shell Collector", giver: .shiitake, level: 17,
                  "The old turtles of Mossback Creek shed scutes that make the best armor plates. They don't shed them willingly, and mind the newts: they bite hot.",
                  .collect(.mossyScute, count: 6), xp: 3_300, caps: 550,
                  [ItemStack(item: .amberShard, count: 5), ItemStack(item: .wardCharm, count: 1)])
        case .playingWithFire:
            story("Playing with Fire", giver: .elderMorel, level: 19,
                  "Ember newts leave smouldering trails all through Mossback Creek. One spark in the dry leaves and the whole Hollow goes up. Put seven of them out.",
                  .defeat(.emberNewt, count: 7), xp: 4_000, caps: 650,
                  [ItemStack(item: .amberShard, count: 5), ItemStack(item: .dewPotion, count: 6)])

        // MARK: Silkshade Thicket
        case .tangledUp:
            story("Tangled Up", giver: .chanterelle, level: 21,
                  "Weaver spiders have strung Silkshade Thicket shut, and my traders won't go near it. Cut a way through, and don't get stuck in their webs.",
                  .defeat(.weaverSpider, count: 7), xp: 4_800, caps: 750,
                  [ItemStack(item: .silkweaveGloves, count: 1), ItemStack(item: .nectarVial, count: 5)])
        case .drawnToTheLight:
            story("Drawn to the Light", giver: .porcini, level: 22,
                  "Dusk moths glitter like evening itself. Their dust makes your nose itch and your eyes swim, so hold your breath while you collect six for me.",
                  .collect(.mothDust, count: 6), xp: 5_200, caps: 800,
                  [ItemStack(item: .amberShard, count: 6), ItemStack(item: .wardCharm, count: 1)])

        // MARK: Pinecone Rise
        case .pricklyBusiness:
            story("Prickly Business", giver: .shiitake, level: 23,
                  "Hedgehog quills make the finest rivet punches. Bring six from Pinecone Rise, and jump aside when they roll.",
                  .collect(.hedgehogQuill, count: 6), xp: 5_600, caps: 900,
                  [ItemStack(item: .amberShard, count: 8), ItemStack(item: .wardCharm, count: 1)])
        case .knightsOfTheCone:
            story("Knights of the Cone", giver: .elderMorel, level: 25,
                  "The cone knights of Pinecone Rise have declared the hill a kingdom and the village its subjects. Knock seven of them off their high horse.",
                  .defeat(.coneKnight, count: 7), xp: 6_600, caps: 1_000,
                  [ItemStack(item: .pineconeHelm, count: 1), ItemStack(item: .dewPotion, count: 8)])

        // MARK: Briar Tangle
        case .prayingForRain:
            story("Praying for Rain", giver: .porcini, level: 26,
                  "The orchid mantises of the Briar Tangle strike faster than you can blink. I'd like to watch them up close, which means thinning them out first. Seven should do.",
                  .defeat(.mantis, count: 7), xp: 7_000, caps: 1_100,
                  [ItemStack(item: .amberShard, count: 8), ItemStack(item: .nectarVial, count: 8)])
        case .everyRose:
            story("Every Rose", giver: .chanterelle, level: 27,
                  "Rose hip jam is the talk of the village, and the only roses left are the ones in the Briar Tangle that bite back. Six hips. Mind the pollen.",
                  .collect(.roseHip, count: 6), xp: 7_500, caps: 1_200,
                  [ItemStack(item: .rosethornGauntlets, count: 1), ItemStack(item: .dewPotion, count: 8)])

        // MARK: Stagshade Grove
        case .grumblingUnderground:
            story("Grumbling Underground", giver: .shiitake, level: 28,
                  "Grumble spores burn hotter than any coal. With six from Stagshade Grove I can forge a blade worthy of the Grove's king. You'll need one.",
                  .collect(.grumbleSpore, count: 6), xp: 8_000, caps: 1_300,
                  [ItemStack(item: .amberShard, count: 10), ItemStack(item: .wardCharm, count: 1)])
        case .kingOfTheGrove:
            story("King of the Grove", giver: .elderMorel, level: 29,
                  "In Stagshade Grove the stag beetles lock horns all day. Best the strongest bugs under the tree and you'll be a legend of the Hollow.",
                  .defeat(.stagBeetle, count: 5), xp: 12_000, caps: 2_000,
                  [ItemStack(item: .amberShard, count: 10), ItemStack(item: .wardCharm, count: 2)])

        // MARK: Side quests
        case .hollowOwl:
            QuestDefinition(
                id: self, title: "The Hollow Owl",
                story: "On dark nights something vast perches in the Great Bough. It took my grandmother's hat. Bring the forest peace.",
                giver: .elderMorel, requiredLevel: 15, prerequisite: .bogHoppers,
                objective: .defeat(.owl, count: 1),
                rewardXP: 4_000, rewardCaps: 800,
                rewardItems: [ItemStack(item: .dewPotion, count: 5), ItemStack(item: .nectarVial, count: 5),
                              ItemStack(item: .wardCharm, count: 1)])
        case .aNoseForTrouble:
            QuestDefinition(
                id: self, title: "A Nose for Trouble",
                story: "This little pup wandered out of the roots and won't stop sniffing after snails. Bring me some shell shards for her bowl, and she's yours. She'll fetch anything you drop!",
                giver: .truffle, requiredLevel: 3, prerequisite: .shellShock,
                objective: .collect(.snailShell, count: 5),
                rewardXP: 120, rewardCaps: 20,
                rewardItems: [ItemStack(item: .pip, count: 1), ItemStack(item: .kibble, count: 30)])
        }
    }

    /// A main-story quest: it follows the one before it in `mainStory`.
    private func story(_ title: String, giver: NPCID, level: Int, _ story: String, _ objective: QuestObjective,
                       xp: Int, caps: Int, _ items: [ItemStack]) -> QuestDefinition {
        QuestDefinition(id: self, title: title, story: story, giver: giver, requiredLevel: level,
                        prerequisite: previous, objective: objective,
                        rewardXP: xp, rewardCaps: caps, rewardItems: items)
    }
}
