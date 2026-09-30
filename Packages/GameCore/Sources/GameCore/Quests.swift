/// Quests. Saves store these raw values, so never rename or remove a case (retell it instead).
public enum QuestID: String, Codable, Sendable, CaseIterable {
    // The main story (`mainStory`), one quest after another, clockwise round the tree and out along the
    // outer ring: one species per quest, handed out by whoever in the village needs it most.
    // Dewleaf Glade
    case shellShock, spotsBeforeYourEyes, fieldNotes, sweetTooth
    // Root Maze
    case slipperySituation, rolyPoly, theWormTurns
    // Barkfall Hollow
    case barkBeetles, toughNuts, hopToIt
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
    // The Sunken Warren
    case somethingStirsBelow, crawlingWithThem, theWarrenKing

    // Side quests
    /// The world boss (only out at night, so it never blocks the story).
    case hollowOwl
    /// Truffle's: your first pet.
    case aNoseForTrouble

    // Hunting requests on Maitake's board: repeatable, one per species (see `huntTarget`).
    case huntSnail, huntLadybug, huntAphid, huntSlug, huntPillBug, huntEarthworm
    case huntBeetle, huntAcornling, huntCricket, huntSporeBeast, huntBogFrog
    case huntFuzzbee, huntPuffweed, huntMossTurtle, huntEmberNewt, huntWeaverSpider, huntDuskMoth
    case huntHedgehog, huntConeKnight, huntMantis, huntThornrose, huntGrumblecap, huntStagBeetle

    // Exploration (Flyff's patrol quests): no story to follow, just places to go and see.
    case layOfTheLand, puppyPatrol, highGround, owlsEyeView, beyondTheRing, windAndWater, stonesAndTimber, theGrandTour
    case rockAndRill

    /// The job-change trial: prove yourself against a Giant before Elder Morel lets you choose a class.
    case trialOfThePath

    // More hunting requests (the Sunken Warren)
    case huntDelverMole, huntRootcrawler

    /// Side quests that send you somewhere rather than after something.
    public static let explorations: [QuestID] = [
        .layOfTheLand, .puppyPatrol, .highGround, .owlsEyeView, .beyondTheRing, .windAndWater, .stonesAndTimber, .theGrandTour,
        .rockAndRill,
    ]

    /// In order: each one opens once the one before it is done.
    public static let mainStory: [QuestID] = allCases.filter {
        $0 != .hollowOwl && $0 != .aNoseForTrouble && $0 != .trialOfThePath && $0.huntTarget == nil && !explorations.contains($0)
    }

    /// The species a hunting request is after.
    public var huntTarget: MobKind? {
        switch self {
        case .huntSnail: .snail
        case .huntLadybug: .ladybug
        case .huntAphid: .aphid
        case .huntSlug: .slug
        case .huntPillBug: .pillBug
        case .huntEarthworm: .earthworm
        case .huntBeetle: .beetle
        case .huntAcornling: .acornling
        case .huntCricket: .cricket
        case .huntSporeBeast: .sporeBeast
        case .huntBogFrog: .bogFrog
        case .huntFuzzbee: .fuzzbee
        case .huntPuffweed: .puffweed
        case .huntMossTurtle: .mossTurtle
        case .huntEmberNewt: .emberNewt
        case .huntWeaverSpider: .weaverSpider
        case .huntDuskMoth: .duskMoth
        case .huntHedgehog: .hedgehog
        case .huntConeKnight: .coneKnight
        case .huntMantis: .mantis
        case .huntThornrose: .thornrose
        case .huntGrumblecap: .grumblecap
        case .huntStagBeetle: .stagBeetle
        case .huntDelverMole: .delverMole
        case .huntRootcrawler: .rootcrawler
        default: nil
        }
    }

    public static let huntingRequests: [QuestID] = allCases.filter { $0.huntTarget != nil }

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
    /// Set foot on each of these places, in any order.
    case explore([LandmarkID])
    /// Bring down Giants (of any kind) of at least this level.
    case defeatGiant(minLevel: Int, count: Int)

    public var goal: Int {
        switch self {
        case let .defeat(_, count), let .collect(_, count), let .defeatGiant(_, count): count
        case let .explore(places): places.count
        }
    }

    /// The kinds whose fields a `defeatGiant` quest points you to: the nearest few that qualify.
    public static func giantKinds(minLevel: Int) -> [MobKind] {
        MobKind.allCases.filter {
            $0.hasGiant && $0.stats.level + Giant.levelBonus >= minLevel && $0.stats.level + Giant.levelBonus <= minLevel + 5
        }
    }

    public var summary: String {
        switch self {
        case let .defeat(kind, count): return "Defeat \(count) \(count == 1 ? kind.displayName : kind.pluralName)"
        case let .collect(item, count): return "Collect \(count) \(item.definition.name)"
        case let .explore(places):
            let names = places.map(\.name)
            let list = names.count <= 2 ? names.joined(separator: " and ")
                : names.dropLast().joined(separator: ", ") + ", and " + names.last!
            return "Visit \(list)"
        case let .defeatGiant(minLevel, count):
            return count == 1 ? "Defeat a Giant (level \(minLevel) or higher)" : "Defeat \(count) Giants (level \(minLevel) or higher)"
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
    /// Goes straight back on the board once handed in (hunting requests).
    public var isRepeatable = false
    /// Hidden past this level (so the board only shows fields worth your time).
    public var maxLevel: Int?

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
    /// Exploration quests in progress: the places still to visit (for the map).
    public var unvisited: [LandmarkID] = []

    init(id: QuestID, state: QuestState, unvisited: [LandmarkID] = []) {
        self.id = id
        self.state = state
        self.unvisited = unvisited
    }
}

extension QuestID {
    public var definition: QuestDefinition {
        switch self {
        // MARK: Dewleaf Glade
        case .shellShock:
            story("Shell Shock", giver: .elderMorel, level: 1,
                  "Snails from Dewleaf Glade keep nibbling the village mushrooms. They won't start a fight, but they'll fight back once you swing. Chase five of them off, would you?",
                  .defeat(.snail, count: 5), xp: 60, caps: 90,
                  [ItemStack(item: .grassMitts, count: 1), ItemStack(item: .dewPotion, count: 3)])
        case .spotsBeforeYourEyes:
            story("Spots Before Your Eyes", giver: .chanterelle, level: 2,
                  "Ladybug wing cases make the loveliest buttons, and my stall's clean out. The ladybugs over in the glade leave them behind. Four should do!",
                  .collect(.spottedWingCase, count: 4), xp: 90, caps: 120,
                  [ItemStack(item: .grassMitts, count: 1), ItemStack(item: .dewPotion, count: 2)])
        case .fieldNotes:
            story("Field Notes", giver: .porcini, level: 3,
                  "I'm writing the first proper field guide to the Hollow! Five snail shell shards will start the collection. After that, bring me anything the critters drop: caps for your purse, and a lesson for your head.",
                  .collect(.snailShell, count: 5), xp: 150, caps: 150,
                  [ItemStack(item: .barkBuckler, count: 1), ItemStack(item: .nectarVial, count: 2)])

        case .sweetTooth:
            story("Sweet Tooth", giver: .oyster, level: 3,
                  "Aphids! They sip the glade's clover and leave honeydew behind, and a dab of it makes the best grip wax a blade could ask for. Five drops, please. Take some Blinkwings: crumple one and you're home in a flutter.",
                  .collect(.honeydewDrop, count: 5), xp: 190, caps: 165,
                  [ItemStack(item: .blinkwing, count: 3), ItemStack(item: .dewPotion, count: 3)])

        // MARK: Root Maze
        case .slipperySituation:
            story("A Slippery Situation", giver: .elderMorel, level: 4,
                  "Slug slime makes the finest glue for patching caps. The slugs of the Root Maze won't share it willingly, and a few of them will come at you on sight. Mind the slime trails.",
                  .collect(.slugSlime, count: 5), xp: 250, caps: 210,
                  [ItemStack(item: .leafTunic, count: 1), ItemStack(item: .nectarVial, count: 3)])
        case .rolyPoly:
            story("Roly-Poly", giver: .shiitake, level: 5,
                  "Pill bug plates make perfect rivets. Bring me five from the Root Maze and I'll throw in some amber. Try an upgrade while you're here; the first few never fail.",
                  .collect(.pillBugPlate, count: 5), xp: 380, caps: 270,
                  [ItemStack(item: .amberShard, count: 4), ItemStack(item: .dewPotion, count: 3)])

        case .theWormTurns:
            story("The Worm Turns", giver: .enoki, level: 6,
                  "Earthworm loam dyes leather the deepest brown in the Hollow. The worms in the Root Maze dive into the ground when they're hurt, so be patient. Six handfuls, and I'll make it worth your while.",
                  .collect(.richLoam, count: 6), xp: 480, caps: 330,
                  [ItemStack(item: .blinkwing, count: 2), ItemStack(item: .dewPotion, count: 4)])

        // MARK: Barkfall Hollow
        case .barkBeetles:
            story("Bark Beetles", giver: .elderMorel, level: 7,
                  "Beetles in Barkfall Hollow are chewing the Great Tree itself. Watch their charge: step aside when they lower their heads!",
                  .defeat(.beetle, count: 6), xp: 700, caps: 450,
                  [ItemStack(item: .beetleHelm, count: 1), ItemStack(item: .amberShard, count: 3)])
        case .toughNuts:
            story("Tough Nuts", giver: .chanterelle, level: 8,
                  "Acornlings! Grumpy little things, but their bitter acorns brew a tonic folk queue up for. Six, please, from Barkfall Hollow.",
                  .collect(.bitterAcorn, count: 6), xp: 850, caps: 540,
                  [ItemStack(item: .barkTreads, count: 1), ItemStack(item: .dewPotion, count: 5)])

        case .hopToIt:
            story("Hop to It", giver: .oyster, level: 10,
                  "Crickets have moved into Barkfall Hollow and they leap before they bite. I need their legs for bow springs, but first the Hollow needs thinning. Seven should quiet them down.",
                  .defeat(.cricket, count: 7), xp: 1_100, caps: 780,
                  [ItemStack(item: .amberShard, count: 4), ItemStack(item: .sapTonic, count: 5)])

        // MARK: Spore Fen
        case .sporeSeason:
            story("Spore Season", giver: .porcini, level: 10,
                  "The Spore Fen is swelling. I need spore sacs to study the bloom, and Elder Morel wants a cure. Don't breathe the purple clouds, and mind what comes out when a spore beast pops.",
                  .collect(.sporeSac, count: 5), xp: 1_300, caps: 900,
                  [ItemStack(item: .beetleBlade, count: 1), ItemStack(item: .amberShard, count: 5),
                   ItemStack(item: .wardCharm, count: 1)])
        case .bogHoppers:
            story("Bog Hoppers", giver: .shiitake, level: 12,
                  "Bog frogs keep hopping off with my tongs, and they leap before they bite. Clear six of them out of the fen. Once you're fifteen, see Elder Morel about choosing a path.",
                  .defeat(.bogFrog, count: 6), xp: 1_800, caps: 1_050,
                  [ItemStack(item: .lilypadTarge, count: 1), ItemStack(item: .amberShard, count: 5)])

        // MARK: Buttercup Meadow
        case .buzzkill:
            story("Buzzkill", giver: .chanterelle, level: 14,
                  "Past the root tips lies Buttercup Meadow, and its fuzzbees keep raiding my honey jars. Take the south road out of the village and teach them some manners.",
                  .defeat(.fuzzbee, count: 7), xp: 2_300, caps: 1_200,
                  [ItemStack(item: .dewPotion, count: 5), ItemStack(item: .amberShard, count: 4)])
        case .somethingInTheAir:
            story("Something in the Air", giver: .porcini, level: 16,
                  "Puffweeds! They burst into pufflings when popped, you know. I need six pollen puffs pressed for the guide. Achoo.",
                  .collect(.pollenPuff, count: 6), xp: 2_900, caps: 1_440,
                  [ItemStack(item: .nectarVial, count: 5), ItemStack(item: .amberShard, count: 4)])

        // MARK: Mossback Creek
        case .shellCollector:
            story("Shell Collector", giver: .shiitake, level: 17,
                  "The old turtles of Mossback Creek shed scutes that make the best armor plates. They don't shed them willingly, and mind the newts: they bite hot.",
                  .collect(.mossyScute, count: 6), xp: 3_300, caps: 1_650,
                  [ItemStack(item: .amberShard, count: 5), ItemStack(item: .wardCharm, count: 1)])
        case .playingWithFire:
            story("Playing with Fire", giver: .elderMorel, level: 19,
                  "Ember newts leave smouldering trails all through Mossback Creek. One spark in the dry leaves and the whole Hollow goes up. Put seven of them out.",
                  .defeat(.emberNewt, count: 7), xp: 4_000, caps: 1_950,
                  [ItemStack(item: .amberShard, count: 5), ItemStack(item: .dewPotion, count: 6)])

        // MARK: Silkshade Thicket
        case .tangledUp:
            story("Tangled Up", giver: .chanterelle, level: 21,
                  "Weaver spiders have strung Silkshade Thicket shut, and my traders won't go near it. Cut a way through, and don't get stuck in their webs.",
                  .defeat(.weaverSpider, count: 7), xp: 4_800, caps: 2_250,
                  [ItemStack(item: .silkweaveGloves, count: 1), ItemStack(item: .nectarVial, count: 5)])
        case .drawnToTheLight:
            story("Drawn to the Light", giver: .porcini, level: 22,
                  "Dusk moths glitter like evening itself. Their dust makes your nose itch and your eyes swim, so hold your breath while you collect six for me.",
                  .collect(.mothDust, count: 6), xp: 5_200, caps: 2_400,
                  [ItemStack(item: .amberShard, count: 6), ItemStack(item: .wardCharm, count: 1)])

        // MARK: Pinecone Rise
        case .pricklyBusiness:
            story("Prickly Business", giver: .shiitake, level: 23,
                  "Hedgehog quills make the finest rivet punches. Bring six from Pinecone Rise, and jump aside when they roll.",
                  .collect(.hedgehogQuill, count: 6), xp: 5_600, caps: 2_700,
                  [ItemStack(item: .amberShard, count: 8), ItemStack(item: .wardCharm, count: 1)])
        case .knightsOfTheCone:
            story("Knights of the Cone", giver: .elderMorel, level: 25,
                  "The cone knights of Pinecone Rise have declared the hill a kingdom and the village its subjects. Knock seven of them off their high horse.",
                  .defeat(.coneKnight, count: 7), xp: 6_600, caps: 3_000,
                  [ItemStack(item: .pineconeHelm, count: 1), ItemStack(item: .dewPotion, count: 8)])

        // MARK: Briar Tangle
        case .prayingForRain:
            story("Praying for Rain", giver: .porcini, level: 26,
                  "The orchid mantises of the Briar Tangle strike faster than you can blink. I'd like to watch them up close, which means thinning them out first. Seven should do.",
                  .defeat(.mantis, count: 7), xp: 7_000, caps: 3_300,
                  [ItemStack(item: .amberShard, count: 8), ItemStack(item: .nectarVial, count: 8)])
        case .everyRose:
            story("Every Rose", giver: .chanterelle, level: 27,
                  "Rose hip jam is the talk of the village, and the only roses left are the ones in the Briar Tangle that bite back. Six hips. Mind the pollen.",
                  .collect(.roseHip, count: 6), xp: 7_500, caps: 3_600,
                  [ItemStack(item: .rosethornGauntlets, count: 1), ItemStack(item: .dewPotion, count: 8)])

        // MARK: Stagshade Grove
        case .grumblingUnderground:
            story("Grumbling Underground", giver: .shiitake, level: 28,
                  "Grumble spores burn hotter than any coal. With six from Stagshade Grove I can forge a blade worthy of the Grove's king. You'll need one.",
                  .collect(.grumbleSpore, count: 6), xp: 8_000, caps: 3_900,
                  [ItemStack(item: .amberShard, count: 10), ItemStack(item: .wardCharm, count: 1)])
        case .kingOfTheGrove:
            story("King of the Grove", giver: .elderMorel, level: 29,
                  "In Stagshade Grove the stag beetles lock horns all day. Best the strongest bugs under the tree and you'll be a legend of the Hollow.",
                  .defeat(.stagBeetle, count: 5), xp: 12_000, caps: 6_000,
                  [ItemStack(item: .amberShard, count: 10), ItemStack(item: .wardCharm, count: 2)])

        // MARK: The Sunken Warren
        case .somethingStirsBelow:
            story("Something Stirs Below", giver: .porcini, level: 29,
                  "The ground past Pinecone Rise has fallen in, and there's a whole warren down there! Moles, dear, big ones, digging in the dark. Walk down the ramp off the ring road and bring me six velvet pelts. Mind: down there, half of them come at you.",
                  .collect(.velvetPelt, count: 6), xp: 12_000, caps: 6_000,
                  [ItemStack(item: .honeydewDraught, count: 6), ItemStack(item: .amberShard, count: 8)])
        case .crawlingWithThem:
            story("Crawling With Them", giver: .shiitake, level: 30,
                  "Rootcrawlers! A hundred legs and every one of them in a hurry. They're chewing through the Great Tree's deepest roots. Seven fewer and the roots might hold. They charge in a line, so step aside.",
                  .defeat(.rootcrawler, count: 7), xp: 14_000, caps: 7_000,
                  [ItemStack(item: .amberShard, count: 10), ItemStack(item: .wardCharm, count: 1)])
        case .theWarrenKing:
            story("The Warren King", giver: .elderMorel, level: 30,
                  "At the bottom of the Sunken Warren sits Moldywarp, the Warren King, fat on the tree's roots. It digs under your feet and bursts up where you stand, so watch the ground and keep moving. Bring the Hollow its peace, and keep whatever's in its hoard.",
                  .defeat(.moldywarp, count: 1), xp: 20_000, caps: 10_000,
                  [ItemStack(item: .wardCharm, count: 2), ItemStack(item: .amberShard, count: 12),
                   ItemStack(item: .honeydewDraught, count: 8)])

        // MARK: Hunting requests
        case .huntSnail, .huntLadybug, .huntAphid, .huntSlug, .huntPillBug, .huntEarthworm,
             .huntBeetle, .huntAcornling, .huntCricket, .huntSporeBeast, .huntBogFrog,
             .huntFuzzbee, .huntPuffweed, .huntMossTurtle, .huntEmberNewt, .huntWeaverSpider, .huntDuskMoth,
             .huntHedgehog, .huntConeKnight, .huntMantis, .huntThornrose, .huntGrumblecap, .huntStagBeetle,
             .huntDelverMole, .huntRootcrawler:
            request(huntTarget!)

        // MARK: Exploration
        case .layOfTheLand:
            explore("Lay of the Land", giver: .maitake, level: 2,
                    "Posted on the board: new faces should know their way around. Walk down to Cattail Shore on Dewdrop Lake, then up Sunny Hillock east of the south road. Nothing to fight, just keep your eyes open.",
                    [.cattailShore, .sunnyHillock], xp: 110, caps: 120,
                    [ItemStack(item: .blinkwing, count: 2), ItemStack(item: .dewPotion, count: 3)])
        case .puppyPatrol:
            explore("Puppy Patrol", giver: .truffle, level: 4, after: .aNoseForTrouble,
                    "Pip needs a proper walk, and she's picked the route herself: Clover Knoll, east past the glade, then round to the Old Knot on the far side of the trunk. She sniffs, you watch for slugs.",
                    [.cloverKnoll, .oldKnot], xp: 320, caps: 200,
                    [ItemStack(item: .kibble, count: 40), ItemStack(item: .dewPotion, count: 3)])
        case .highGround:
            explore("The High Ground", giver: .oyster, level: 8,
                    "A good shot starts with a good view. Climb Barkfall Bluff, north of the trunk, then Foxglove Hill between the Hollow and the fen, and tell me what you can see from up there.",
                    [.barkfallBluff, .foxgloveHill], xp: 900, caps: 520,
                    [ItemStack(item: .amberShard, count: 3), ItemStack(item: .dewPotion, count: 5)])
        case .owlsEyeView:
            explore("An Owl's-Eye View", giver: .porcini, level: 14,
                    "Chapter three of the field guide needs a map of the owl's country. Sketch the Great Bough from Owlwatch Hill, then stand by the fallen branch it perches on. Go by day, if you value your hat.",
                    [.owlwatchHill, .fallenBough], xp: 2_000, caps: 1_000,
                    [ItemStack(item: .nectarVial, count: 5), ItemStack(item: .amberShard, count: 4)])
        case .beyondTheRing:
            explore("Beyond the Ring", giver: .chanterelle, level: 16,
                    "My traders say the south road keeps going past the outer ring. Follow it to Rimview Bluff, then cut east to Glimmer Dell. If there's a way through, there's a trade route!",
                    [.rimviewBluff, .glimmerDell], xp: 3_000, caps: 1_500,
                    [ItemStack(item: .sapTonic, count: 5), ItemStack(item: .blinkwing, count: 3)])
        case .windAndWater:
            explore("Wind and Water", giver: .enoki, level: 19,
                    "They say the wind on Windwhistle Peak can dry a cloak in a minute, and that Moonwell Tarn is deep enough to drown the moon. Go and see both, past the creek and the thicket.",
                    [.windwhistlePeak, .moonwellTarn], xp: 4_200, caps: 2_000,
                    [ItemStack(item: .moonNectar, count: 5), ItemStack(item: .amberShard, count: 5)])
        case .stonesAndTimber:
            explore("Stones and Timber", giver: .shiitake, level: 24,
                    "Old smiths swore by stone from the Mossring and timber from the Hollowlog, out past the briars and the grove. Find both and tell me if they're still standing.",
                    [.hollowlogCrossing, .mossringStones], xp: 6_500, caps: 3_000,
                    [ItemStack(item: .amberShard, count: 8), ItemStack(item: .wardCharm, count: 1)])
        case .theGrandTour:
            explore("The Grand Tour", giver: .elderMorel, level: 27, after: .stonesAndTimber,
                    "Every sprout who's seen the whole Hollow has walked the wild fringe from end to end. Visit all six of its places, and the village will know you've truly been everywhere under the tree.",
                    [.rimviewBluff, .glimmerDell, .windwhistlePeak, .moonwellTarn, .hollowlogCrossing, .mossringStones],
                    xp: 9_000, caps: 5_000,
                    [ItemStack(item: .wardCharm, count: 2), ItemStack(item: .amberShard, count: 10),
                     ItemStack(item: .honeydewDraught, count: 5)])
        case .rockAndRill:
            explore("Rock and Rill", giver: .enoki, level: 18,
                    "My dyes want the cleanest water in the Hollow, and the cleanest water starts at Silverthread Spring, up the brook that feeds Dewdrop Lake. Then climb Sunstone Mesa, past the thicket, and tell me if the stone up there really glows at noon.",
                    [.silverthreadSpring, .sunstoneMesa], xp: 3_600, caps: 1_800,
                    [ItemStack(item: .moonNectar, count: 5), ItemStack(item: .amberShard, count: 4)])

        // MARK: Job change
        case .trialOfThePath:
            QuestDefinition(
                id: self, title: "The Trial of the Path",
                story: "Fifteen already! Before I help you choose a calling, show me you can stand your ground. Every field has its Giant, the biggest of its kind. Bring one down, one of level ten or more, and come back to me. Take potions.",
                giver: .elderMorel, requiredLevel: PlayerClass.requiredLevel, prerequisite: nil,
                objective: .defeatGiant(minLevel: 10, count: 1),
                rewardXP: 1_500, rewardCaps: 800,
                rewardItems: [ItemStack(item: .nectarVial, count: 5), ItemStack(item: .amberShard, count: 3)])

        // MARK: Side quests
        case .hollowOwl:
            QuestDefinition(
                id: self, title: "The Hollow Owl",
                story: "On dark nights something vast perches in the Great Bough. It took my grandmother's hat. Bring the forest peace.",
                giver: .elderMorel, requiredLevel: 15, prerequisite: .bogHoppers,
                objective: .defeat(.owl, count: 1),
                rewardXP: 4_000, rewardCaps: 2_400,
                rewardItems: [ItemStack(item: .dewPotion, count: 5), ItemStack(item: .nectarVial, count: 5),
                              ItemStack(item: .wardCharm, count: 1)])
        case .aNoseForTrouble:
            QuestDefinition(
                id: self, title: "A Nose for Trouble",
                story: "This little pup wandered out of the roots and won't stop sniffing after snails. Bring me some shell shards for her bowl, and she's yours. She'll fetch anything you drop!",
                giver: .truffle, requiredLevel: 3, prerequisite: .shellShock,
                objective: .collect(.snailShell, count: 5),
                rewardXP: 120, rewardCaps: 60,
                rewardItems: [ItemStack(item: .pip, count: 1), ItemStack(item: .kibble, count: 30)])
        }
    }

    /// Kills per hunting request.
    public static let requestKills = 12

    /// A hunting request: repeatable, paid in caps, and gone from the board once you've outgrown the field.
    private func request(_ kind: MobKind) -> QuestDefinition {
        let level = kind.stats.level
        return QuestDefinition(
            id: self, title: "Request: \(kind.pluralName)",
            story: "Posted on the board: the \(kind.pluralName.lowercased()) are getting bold. Defeat \(Self.requestKills) and Maitake pays on the spot, every time.",
            giver: .maitake, requiredLevel: max(1, level - 2), prerequisite: nil,
            objective: .defeat(kind, count: Self.requestKills),
            rewardXP: kind.stats.xp * 2, rewardCaps: 30 + level * 15, rewardItems: [],
            isRepeatable: true, maxLevel: level + 7)
    }

    /// An exploration quest: a side quest with places to visit instead of critters to chase.
    private func explore(_ title: String, giver: NPCID, level: Int, after prerequisite: QuestID? = nil, _ story: String,
                         _ places: [LandmarkID], xp: Int, caps: Int, _ items: [ItemStack]) -> QuestDefinition {
        QuestDefinition(id: self, title: title, story: story, giver: giver, requiredLevel: level,
                        prerequisite: prerequisite, objective: .explore(places),
                        rewardXP: xp, rewardCaps: caps, rewardItems: items)
    }

    /// A main-story quest: it follows the one before it in `mainStory`.
    private func story(_ title: String, giver: NPCID, level: Int, _ story: String, _ objective: QuestObjective,
                       xp: Int, caps: Int, _ items: [ItemStack]) -> QuestDefinition {
        QuestDefinition(id: self, title: title, story: story, giver: giver, requiredLevel: level,
                        prerequisite: previous, objective: objective,
                        rewardXP: xp, rewardCaps: caps, rewardItems: items)
    }
}
