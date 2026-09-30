import Foundation
import Testing
@testable import GameCore

/// Stat points, the one-in-five aggro rule, the main story, and Porcini's material trade.
@Suite struct ProgressionTests {
    @discardableResult
    private func run(_ sim: inout GameSimulation, seconds: Float) -> [WorldEvent] {
        var events: [WorldEvent] = []
        for _ in 0..<Int(seconds * Float(GameSimulation.tickRate)) { events += sim.step() }
        return events
    }

    private func standNear(_ npc: NPCID, _ player: EntityID, in sim: inout GameSimulation) throws {
        let placement = try #require(sim.map.placement(of: npc))
        sim.teleport(player, to: placement.position + Vec2(0, 1.2))
    }

    // MARK: - Stat points

    @Test func levelsEarnStatPointsToSpend() throws {
        var sim = GameSimulation(seed: 1)
        let player = sim.spawnPlayer(profile: .newCharacter)
        #expect(sim.playerStatus(player)?.unspentStatPoints == 0)

        var entity = try #require(sim.entities[player])
        sim.awardXP(to: &entity, amount: Progression.xpToNextLevel(1))
        sim.entities[player] = entity
        #expect(sim.playerStatus(player)?.stats.level == 2)
        #expect(sim.playerStatus(player)?.unspentStatPoints == Attributes.pointsPerLevel)
    }

    @Test func spendingPointsRaisesStats() throws {
        var sim = GameSimulation(seed: 1)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 10))
        let before = try #require(sim.playerStatus(player))
        #expect(before.unspentStatPoints == 27)

        sim.enqueue(.spendStatPoints(Attributes(strength: 5, stamina: 4)), from: player)
        #expect(run(&sim, seconds: 0.1).contains(.attributesChanged(player: player)))
        let after = try #require(sim.playerStatus(player))
        #expect(after.attributes == Attributes(strength: 5, stamina: 4))
        #expect(after.unspentStatPoints == 18)
        #expect(after.stats.attack > before.stats.attack)
        #expect(after.stats.maxHP == before.stats.maxHP + 4 * Attributes.hpPerStamina)
        #expect(after.stats.defense > before.stats.defense)
        #expect(after.stats.maxMP == before.stats.maxMP, "strength and stamina don't touch mana")
    }

    @Test func eachAttributeDoesItsJob() {
        let bare = Progression.playerStats(level: 20)
        func with(_ attribute: Attribute) -> CombatStats {
            var points = Attributes()
            points[attribute] = 20
            return Progression.playerStats(level: 20, attributes: points)
        }
        #expect(with(.strength).attack > bare.attack)
        #expect(with(.stamina).maxHP > bare.maxHP)
        #expect(with(.stamina).defense > bare.defense)
        #expect(with(.dexterity).attackInterval < bare.attackInterval)
        #expect(with(.dexterity).critChance > bare.critChance)
        #expect(with(.intelligence).maxMP > bare.maxMP)
        #expect(with(.intelligence).skillPower > bare.skillPower)
    }

    @Test func cantOverspendOrRefund() throws {
        var sim = GameSimulation(seed: 1)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 3)) // 6 points
        sim.enqueue(.spendStatPoints(Attributes(dexterity: 7)), from: player)
        sim.enqueue(.spendStatPoints(Attributes(strength: 3, stamina: -2)), from: player)
        let events = run(&sim, seconds: 0.1)
        #expect(events.contains(.actionFailed(player: player, reason: .noStatPoints)))
        #expect(events.contains(.actionFailed(player: player, reason: .notAvailable)))
        #expect(sim.playerStatus(player)?.attributes == Attributes())

        sim.enqueue(.spendStatPoints(Attributes(intelligence: 6)), from: player)
        run(&sim, seconds: 0.1)
        #expect(sim.playerStatus(player)?.unspentStatPoints == 0)
    }

    @Test func spentPointsAreSaved() throws {
        var sim = GameSimulation(seed: 1)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 8))
        sim.enqueue(.spendStatPoints(Attributes(strength: 2, dexterity: 10)), from: player)
        run(&sim, seconds: 0.1)
        let profile = try #require(sim.profile(of: player))
        let decoded = try JSONDecoder().decode(PlayerProfile.self, from: JSONEncoder().encode(profile))
        #expect(decoded.attributes == Attributes(strength: 2, dexterity: 10))

        var fresh = GameSimulation(seed: 2)
        let reloaded = fresh.spawnPlayer(profile: decoded)
        #expect(fresh.playerStatus(reloaded)?.stats.attack == sim.playerStatus(player)?.stats.attack)
        #expect(fresh.playerStatus(reloaded)?.unspentStatPoints == Attributes.earned(atLevel: 8) - 12)
    }

    @Test func savesFromBeforeStatsGetEveryPointToSpend() throws {
        // A save from before attributes existed has no "attributes" key at all.
        let old = #"{"level":12,"xp":0,"caps":5,"inventory":{"stacks":[]},"equipment":[],"activeQuests":[],"completedQuests":[]}"#
        let profile = try JSONDecoder().decode(PlayerProfile.self, from: Data(old.utf8))
        #expect(profile.attributes == nil)
        var sim = GameSimulation(seed: 1)
        let player = sim.spawnPlayer(profile: profile)
        #expect(sim.playerStatus(player)?.unspentStatPoints == 33)
    }

    // MARK: - Aggro

    @Test func aboutOneMobInFiveIsAggressive() {
        let sim = GameSimulation(seed: 4)
        let mobs = sim.snapshot().entities.filter(\.kind.isMob)
        for (index, area) in sim.map.mobSpawns.enumerated() {
            let aggressive = mobs.filter { sim.entities[$0.id]?.brain?.spawnArea == index && $0.isAggressive }.count
            let expected = area.kind.stats.aggroRadius > 0 ? max(1, area.count / area.aggressiveShare) : 0
            #expect(aggressive == expected, "\(area.kind)")
        }
        #expect(!mobs.contains { $0.kind == .mob(.snail) && $0.isAggressive }, "the starter glade never picks fights")
    }

    @Test func passiveMobsIgnoreYouUntilHit() throws {
        var sim = GameSimulation(seed: 4)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 5))
        let calm = try #require(sim.snapshot().entities.first { $0.kind == .mob(.slug) && !$0.isAggressive })
        sim.teleport(player, to: calm.position.xz + Vec2(1.5, 0))
        run(&sim, seconds: 3)
        #expect(sim.entity(calm.id)?.combat.target == nil, "a passive slug minds its own business")

        sim.enqueue(.target(calm.id, engage: true), from: player)
        run(&sim, seconds: 2)
        #expect(sim.entity(calm.id)?.combat.target == player, "but it fights back")
    }

    @Test func theAggressiveSlotRefillsOnRespawn() throws {
        var sim = GameSimulation(seed: 4)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 30))
        let area = try #require(sim.map.mobSpawns.firstIndex { $0.kind == .slug })
        let angry = try #require(sim.snapshot().entities.first { $0.kind == .mob(.slug) && $0.isAggressive })
        sim.entities[player]?.stats.attack = 10_000
        sim.teleport(player, to: angry.position.xz + Vec2(1.2, 0))
        sim.enqueue(.target(angry.id, engage: true), from: player)
        run(&sim, seconds: 2)
        #expect(sim.entity(angry.id)?.stats.isAlive != true)

        sim.teleport(player, to: sim.map.playerSpawn) // out of the way
        run(&sim, seconds: MobKind.slug.stats.respawnSeconds + 3)
        let aggressive = sim.order.filter { id in
            guard let e = sim.entities[id], e.stats.isAlive else { return false }
            return e.brain?.spawnArea == area && e.brain?.aggressive == true
        }
        #expect(aggressive.count == 1)
    }

    // MARK: - Main story

    @Test func theMainStoryIsOneLine() {
        var level = 0
        for (index, quest) in QuestID.mainStory.enumerated() {
            let definition = quest.definition
            #expect(definition.prerequisite == (index > 0 ? QuestID.mainStory[index - 1] : nil), "\(quest)")
            #expect(definition.requiredLevel >= level, "\(quest) comes after an easier quest")
            level = definition.requiredLevel
        }
        #expect(QuestID.shellShock.next == .spotsBeforeYourEyes)
        #expect(QuestID.kingOfTheGrove.next == .somethingStirsBelow)
        #expect(QuestID.theWarrenKing.next == nil)
        #expect(!QuestID.trialOfThePath.definition.isMainStory)
        #expect(!QuestID.hollowOwl.definition.isMainStory)
    }

    @Test func theStoryVisitsEverySpecies() {
        let hunted = Set(QuestID.mainStory.map { quest -> MobKind? in
            switch quest.definition.objective {
            case let .defeat(kind, _): kind
            case let .collect(item, _): item.specimenOf
            case .explore, .defeatGiant: nil
            }
        })
        for area in WorldMap.mushroomHollow.mobSpawns {
            #expect(hunted.contains(area.kind), "a quest sends you after \(area.kind)")
        }
        let givers = Set(QuestID.mainStory.map(\.definition.giver))
        #expect(givers.isSuperset(of: [.elderMorel, .chanterelle, .shiitake, .porcini]))
    }

    // MARK: - Porcini

    @Test func everyMobsMaterialHasABounty() {
        // Summons have no material of their own, and Moldywarp drops its moles' pelts.
        for kind in MobKind.allCases where kind != .mouse && kind != .sporeling && kind != .puffling && !kind.isFieldBoss {
            let material = kind.drops[0].item
            #expect(material.bounty?.source == kind, "\(kind)")
        }
        #expect(ItemID.amberShard.bounty == nil)
        #expect(ItemID.dewPotion.bounty == nil)
        #expect(ItemID.twigSword.bounty == nil)
    }

    @Test func porciniTradesMaterialsForXPAndCaps() throws {
        var sim = GameSimulation(seed: 1)
        var bag = Inventory()
        bag.add(.beetleHorn, count: 10)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 8, caps: 0, inventory: bag))
        try standNear(.porcini, player, in: &sim)

        sim.enqueue(.tradeMaterials(.beetleHorn, count: 4, at: .porcini), from: player)
        let events = run(&sim, seconds: 0.1)
        let bounty = try #require(ItemID.beetleHorn.bounty)
        let xp = bounty.xp(forPlayerLevel: 8) * 4
        #expect(events.contains(.materialsTraded(player: player, item: .beetleHorn, count: 4, xp: xp, caps: bounty.caps * 4)))
        #expect(events.contains(.xpGained(player: player, amount: xp)))
        let status = try #require(sim.playerStatus(player))
        #expect(status.caps == bounty.caps * 4)
        #expect(status.xp == xp)
        #expect(status.inventory.count(of: .beetleHorn) == 6)
    }

    @Test func oldMaterialsAreWorthLessXPToVeterans() throws {
        let shell = try #require(ItemID.snailShell.bounty)
        #expect(shell.xp(forPlayerLevel: 1) > shell.xp(forPlayerLevel: 20))
        #expect(shell.xp(forPlayerLevel: 20) >= 1)
    }

    @Test func porciniOnlyTakesMaterialsInPerson() throws {
        var sim = GameSimulation(seed: 1)
        var bag = Inventory()
        bag.add(.snailShell, count: 3)
        bag.add(.amberShard, count: 3)
        let player = sim.spawnPlayer(profile: PlayerProfile(inventory: bag))
        sim.enqueue(.tradeMaterials(.snailShell, count: 1, at: .porcini), from: player)
        #expect(run(&sim, seconds: 0.1).contains(.actionFailed(player: player, reason: .tooFar)))

        try standNear(.porcini, player, in: &sim)
        sim.enqueue(.tradeMaterials(.amberShard, count: 1, at: .porcini), from: player)
        sim.enqueue(.tradeMaterials(.snailShell, count: 5, at: .porcini), from: player)
        let events = run(&sim, seconds: 0.1)
        #expect(events.contains(.actionFailed(player: player, reason: .notUsable)))
        #expect(events.contains(.actionFailed(player: player, reason: .missingItem)))

        try standNear(.chanterelle, player, in: &sim)
        sim.enqueue(.tradeMaterials(.snailShell, count: 1, at: .chanterelle), from: player)
        #expect(run(&sim, seconds: 0.1).contains(.actionFailed(player: player, reason: .notAvailable)))
        #expect(sim.playerStatus(player)?.inventory.count(of: .snailShell) == 3)
    }

    @Test func porciniStandsInTheOpen() throws {
        let map = WorldMap.mushroomHollow
        let porcini = try #require(map.placement(of: .porcini))
        #expect(map.zone(at: porcini.position)?.name == "Capstone Town")
        for angle in stride(from: Float(0), to: 2 * .pi, by: .pi / 2) {
            let spot = porcini.position + AngleMath.direction(forYaw: angle) * 1.5
            #expect(!map.isBlocked(spot, radius: GameSimulation.playerRadius), "blocked at \(angle)")
        }
        for other in map.npcs where other.id != .porcini {
            #expect(other.position.distance(to: porcini.position) > NPCID.interactionRange)
        }
    }
}
