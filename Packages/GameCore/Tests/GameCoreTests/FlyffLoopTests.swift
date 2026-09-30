import Foundation
import Testing
@testable import GameCore

/// The classic loop: Giants, Blinkwings, the request board, death penalties, and money that comes from quests.
@Suite struct FlyffLoopTests {
    private func run(_ sim: inout GameSimulation, seconds: Float) -> [WorldEvent] {
        var events: [WorldEvent] = []
        for _ in 0..<Int(seconds * Float(GameSimulation.tickRate)) { events += sim.step() }
        return events
    }

    private func standNear(_ npc: NPCID, _ player: EntityID, in sim: inout GameSimulation) throws {
        let placement = try #require(sim.map.placement(of: npc))
        sim.teleport(player, to: placement.position + Vec2(0, 1.2))
    }

    // MARK: - Giants

    @Test func everyFieldHasOneGiant() {
        let sim = GameSimulation(seed: 3)
        let giants = sim.snapshot().entities.filter(\.isGiant)
        let fields = sim.map.mobSpawns.filter(\.kind.hasGiant)
        #expect(giants.count == fields.count)
        for area in fields {
            #expect(giants.contains { $0.kind == .mob(area.kind) }, "\(area.kind) has a Giant")
        }
        #expect(sim.snapshot().entities.filter { $0.isGiant && $0.isAggressive }.isEmpty, "Giants never start a fight")
    }

    @Test func giantsAreTougherAndPayMore() throws {
        var sim = GameSimulation(seed: 3)
        let snapshot = sim.snapshot()
        let giant = try #require(snapshot.entities.first { $0.isGiant && $0.kind == .mob(.slug) })
        let regular = try #require(snapshot.entities.first { !$0.isGiant && $0.kind == .mob(.slug) })
        #expect(giant.maxHP == regular.maxHP * Giant.hpMultiplier)
        #expect(giant.level == regular.level + Giant.levelBonus)
        let giantRadius = try #require(sim.entity(giant.id)).radius
        #expect(giantRadius > (try #require(sim.entity(regular.id)).radius))

        let player = sim.spawnPlayer(profile: PlayerProfile(level: 4))
        var hunter = try #require(sim.entity(player))
        sim.awardXP(to: &hunter, for: .slug)
        let regularXP = try #require(hunter.player).xp
        hunter = try #require(sim.entity(player))
        sim.awardXP(to: &hunter, for: .slug, giant: true)
        #expect(try #require(hunter.player).xp > regularXP * 5)
    }

    @Test func giantsAlwaysLeaveGearAndCaps() throws {
        var sim = GameSimulation(seed: 5)
        let player = sim.spawnPlayer()
        let entity = try #require(sim.entity(player))
        sim.rollLoot(for: .beetle, giant: true, ownedBy: entity, at: Vec2(80, 0))
        let drops = sim.snapshot(for: player).drops
        #expect(drops.contains { if case .caps = $0.kind { true } else { false } })
        #expect(drops.contains { if case let .item(item, _) = $0.kind { item.definition.equipSlot != nil } else { false } })
    }

    @Test func slainGiantsTakeMinutesToReturn() throws {
        var sim = GameSimulation(seed: 3)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 30))
        let giant = try #require(sim.snapshot().entities.first { $0.isGiant && $0.kind == .mob(.snail) })
        var target = try #require(sim.entity(giant.id))
        sim.kill(&target, killer: player)
        sim.entities[giant.id] = target
        _ = run(&sim, seconds: 60)
        #expect(!sim.snapshot().entities.contains { $0.isGiant && $0.kind == .mob(.snail) }, "not back after a minute")
        _ = run(&sim, seconds: Giant.respawnSeconds)
        #expect(sim.snapshot().entities.contains { $0.isGiant && $0.kind == .mob(.snail) }, "back after a few minutes")
    }

    @Test func autoTargetingPassesOverGiants() throws {
        var sim = GameSimulation(seed: 3)
        let player = sim.spawnPlayer()
        let giant = try #require(sim.snapshot().entities.first { $0.isGiant && $0.kind == .mob(.snail) })
        sim.teleport(player, to: giant.position.xz + Vec2(2.5, 0))
        let snapshot = sim.snapshot(for: player)
        let me = try #require(snapshot.entity(player))
        let picked = try #require(snapshot.nearestHostile(to: me.position, within: 40))
        #expect(picked != giant.id)
        #expect(snapshot.cycleTarget(from: me.position, current: nil, step: 1) == giant.id, "but you can still pick one")
    }

    // MARK: - Money

    @Test func killsPayLittleAndOnlySometimes() throws {
        var sim = GameSimulation(seed: 9)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 8))
        let entity = try #require(sim.entity(player))
        var caps = 0, piles = 0
        let kills = 400
        for _ in 0..<kills {
            let before = sim.drops.count
            sim.rollLoot(for: .beetle, ownedBy: entity, at: Vec2(80, 0))
            for drop in sim.drops[before...] {
                if case let .caps(amount) = drop.kind { caps += amount; piles += 1 }
            }
            sim.drops.removeAll()
        }
        let share = Float(piles) / Float(kills)
        #expect(share > 0.3 && share < 0.5, "a pile about 40% of the time (\(share))")
        #expect(caps / kills < 5, "a few caps a kill on average")
        // One story quest at the same level pays as much as a hundred kills.
        #expect(QuestID.barkBeetles.definition.rewardCaps >= caps / kills * 100)
    }

    @Test func farWeakerMobsDropOnlyTheirMaterial() throws {
        var sim = GameSimulation(seed: 12)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 20))
        let entity = try #require(sim.entity(player))
        for _ in 0..<200 {
            sim.rollLoot(for: .snail, ownedBy: entity, at: Vec2(80, 0))
        }
        #expect(!sim.drops.isEmpty)
        #expect(sim.drops.allSatisfy { $0.kind == .item(.snailShell, count: 1) })
    }

    @Test func shopsSellAGearTierEveryFewLevels() {
        let weapons = NPCID.oyster.definition.shopStock
        let armor = NPCID.enoki.definition.shopStock
        for item in weapons + armor {
            #expect(item.definition.buyPrice != nil, "\(item) has a price")
        }
        let weaponLevels = Set(weapons.filter { $0.definition.weaponType?.playerClass == nil }.map(\.definition.requiredLevel))
        let armorLevels = Set(armor.map(\.definition.requiredLevel))
        for level in stride(from: 1, through: 20, by: 5) {
            #expect(weaponLevels.contains { abs($0 - level) <= 3 }, "a weapon for level \(level)")
            #expect(armorLevels.contains { abs($0 - level) <= 3 }, "armor for level \(level)")
        }
        #expect(NPCID.chanterelle.definition.shopStock.contains(.blinkwing))
    }

    // MARK: - Hunting requests

    @Test func everyFieldHasARepeatableRequest() {
        let hunted = Set(QuestID.huntingRequests.compactMap(\.huntTarget))
        for area in WorldMap.mushroomHollow.mobSpawns where !area.kind.isFieldBoss {
            #expect(hunted.contains(area.kind), "a request for \(area.kind)")
        }
        for quest in QuestID.huntingRequests {
            let definition = quest.definition
            #expect(definition.isRepeatable && definition.giver == .maitake && !definition.isMainStory)
        }
    }

    @Test func requestsGoBackOnTheBoard() throws {
        var sim = GameSimulation(seed: 2)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 3, caps: 0))
        try standNear(.maitake, player, in: &sim)
        sim.enqueue(.acceptQuest(.huntSnail), from: player)
        _ = run(&sim, seconds: 0.1)
        var hunter = try #require(sim.entity(player))
        for _ in 0..<QuestID.requestKills { sim.recordKill(of: .snail, by: &hunter) }
        sim.entities[player] = hunter
        sim.enqueue(.completeQuest(.huntSnail), from: player)
        let events = run(&sim, seconds: 0.1)
        #expect(events.contains(.questCompleted(player: player, quest: .huntSnail)))
        let status = try #require(sim.playerStatus(player))
        #expect(status.caps == QuestID.huntSnail.definition.rewardCaps)
        #expect(status.quests.first { $0.id == .huntSnail }?.state == .available, "straight back on the board")
    }

    @Test func outgrownRequestsLeaveTheBoard() throws {
        var sim = GameSimulation(seed: 2)
        let veteran = sim.spawnPlayer(profile: PlayerProfile(level: 20))
        let status = try #require(sim.playerStatus(veteran))
        #expect(status.quests.first { $0.id == .huntSnail }?.state == .hidden)
        #expect(status.quests.first { $0.id == .huntWeaverSpider }?.state == .available)
    }

    // MARK: - Blinkwings

    @Test func blinkwingsFlyYouHomeButNotMidFight() throws {
        var sim = GameSimulation(seed: 4)
        var bag = Inventory()
        bag.add(.blinkwing, count: 2)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 5, inventory: bag))
        let slug = try #require(sim.snapshot().entities.first { $0.kind == .mob(.slug) && !$0.isGiant })
        sim.teleport(player, to: slug.position.xz + Vec2(1.2, 0))
        sim.enqueue(.target(slug.id, engage: true), from: player)
        _ = run(&sim, seconds: 2)
        sim.enqueue(.useItem(.blinkwing), from: player)
        #expect(run(&sim, seconds: 0.1).contains(.actionFailed(player: player, reason: .inCombat)))

        sim.teleport(player, to: Vec2(-120, 0))
        sim.entities[player]?.combat = CombatState()
        _ = run(&sim, seconds: 5)
        sim.enqueue(.useItem(.blinkwing), from: player)
        #expect(run(&sim, seconds: 0.1).contains(.blinked(player: player)))
        let home = try #require(sim.entity(player)).position.xz
        #expect(home.distance(to: sim.map.playerSpawn) < 1)
        #expect(sim.playerStatus(player)?.inventory.count(of: .blinkwing) == 1)
    }

    // MARK: - Levelling

    @Test func faintingCostsXPFromLevelTen() throws {
        var sim = GameSimulation(seed: 1)
        let rookie = sim.spawnPlayer(profile: PlayerProfile(level: 5, xp: 100))
        let veteran = sim.spawnPlayer(profile: PlayerProfile(level: 12, xp: 1_000))
        for id in [rookie, veteran] {
            var e = try #require(sim.entity(id))
            sim.kill(&e, killer: nil)
            sim.entities[id] = e
        }
        #expect(sim.playerStatus(rookie)?.xp == 100)
        let lost = Progression.deathPenalty(level: 12, xp: 1_000)
        #expect(lost > 0)
        #expect(sim.playerStatus(veteran)?.xp == 1_000 - lost)
        #expect(Progression.deathPenalty(level: 12, xp: 3) == 3, "never costs a level")
    }

    @Test func levelsPastTheFirstJobTakeLonger() {
        // Kills of a same-level mob needed per level: flat-ish early, climbing after the first job.
        func kills(_ kind: MobKind) -> Double {
            Double(Progression.xpToNextLevel(kind.stats.level)) / Double(kind.stats.xp)
        }
        #expect(kills(.stagBeetle) > 2 * kills(.fuzzbee))
        #expect(kills(.fuzzbee) < 1.5 * kills(.beetle))
    }
}
