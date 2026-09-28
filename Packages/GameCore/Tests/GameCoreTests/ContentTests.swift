import Foundation
import Testing
@testable import GameCore

@Suite struct ContentTests {
    // MARK: - Helpers

    private func run(_ sim: inout GameSimulation, seconds: Float) -> [WorldEvent] {
        var events: [WorldEvent] = []
        for _ in 0..<Int(seconds * Float(GameSimulation.tickRate)) { events += sim.step() }
        return events
    }

    private func standNear(_ npc: NPCID, _ player: EntityID, in sim: inout GameSimulation) throws {
        let placement = try #require(sim.map.placement(of: npc))
        sim.teleport(player, to: placement.position + Vec2(0, 1.2))
    }

    private func setLevel(_ level: Int, _ player: EntityID, in sim: inout GameSimulation) {
        sim.entities[player]?.stats = Progression.playerStats(level: level)
    }

    /// Walks up to the nearest living `kind` and fights it to the death.
    private func slay(_ kind: MobKind, _ player: EntityID, in sim: inout GameSimulation) throws -> [WorldEvent] {
        let me = try #require(sim.entity(player)).position
        let mob = try #require(sim.snapshot().entities
            .filter { $0.kind == .mob(kind) && $0.isAlive }
            .min { $0.position.xz.distance(to: me.xz) < $1.position.xz.distance(to: me.xz) })
        sim.teleport(player, to: mob.position.xz + Vec2(1.2, 0))
        sim.enqueue(.target(mob.id, engage: true), from: player)
        var events: [WorldEvent] = []
        for _ in 0..<(GameSimulation.tickRate * 60) {
            events += sim.step()
            if events.contains(.died(entity: mob.id, killer: player)) { return events }
        }
        Issue.record("\(kind) \(mob.id) never died")
        return events
    }

    // MARK: - Inventory

    @Test func inventoryStacksAndRespectsCapacity() {
        var bag = Inventory()
        #expect(bag.add(.dewPotion, count: 25) == 0)
        #expect(bag.stacks.count == 2, "20 per stack")
        #expect(bag.count(of: .dewPotion) == 25)
        let removed = bag.remove(.dewPotion, count: 21)
        #expect(removed)
        #expect(bag.stacks.count == 1)
        let overdrawn = bag.remove(.dewPotion, count: 5)
        #expect(!overdrawn, "all or nothing")

        for _ in 0..<Inventory.capacity { bag.add(.twigSword, count: 1) }
        #expect(!bag.canAdd(.mossBoots, count: 1))
        // 4 potions left in their stack (room for 16); no free slot for a new stack.
        let leftover = bag.add(.dewPotion, count: 20)
        #expect(leftover == 4, "tops up the existing stack only")
    }

    // MARK: - Loot

    @Test func killsPayCapsAndDropLoot() throws {
        var sim = GameSimulation(seed: 21)
        let player = sim.spawnPlayer(profile: PlayerProfile())
        setLevel(8, player, in: &sim)
        var events: [WorldEvent] = []
        for _ in 0..<8 { events += try slay(.snail, player, in: &sim) }

        let status = try #require(sim.playerStatus(player))
        #expect(status.caps > 0)
        #expect(status.inventory.count(of: .snailShell) > 0)
        #expect(events.contains { if case .itemReceived(player, .snailShell, _) = $0 { true } else { false } })
    }

    // MARK: - Shop

    @Test func buyingAndSellingAtTheShop() throws {
        var sim = GameSimulation(seed: 1)
        let player = sim.spawnPlayer(profile: PlayerProfile(caps: 50))

        sim.enqueue(.buy(.twigSword, from: .chanterelle), from: player)
        #expect(run(&sim, seconds: 0.1).contains(.actionFailed(player: player, reason: .tooFar)))

        try standNear(.chanterelle, player, in: &sim)
        sim.enqueue(.buy(.twigSword, from: .chanterelle), from: player)
        sim.enqueue(.buy(.twigSword, from: .chanterelle), from: player)
        let events = run(&sim, seconds: 0.1)
        #expect(events.contains(.actionFailed(player: player, reason: .notEnoughCaps)))
        var status = try #require(sim.playerStatus(player))
        #expect(status.caps == 10)
        #expect(status.inventory.count(of: .twigSword) == 1)

        sim.enqueue(.sell(.twigSword, count: 1, to: .chanterelle), from: player)
        _ = run(&sim, seconds: 0.1)
        status = try #require(sim.playerStatus(player))
        #expect(status.caps == 10 + ItemID.twigSword.definition.sellPrice)
        #expect(status.inventory.count(of: .twigSword) == 0)

        sim.enqueue(.buy(.beetleBlade, from: .chanterelle), from: player)
        #expect(run(&sim, seconds: 0.1).contains(.actionFailed(player: player, reason: .notAvailable)))
    }

    // MARK: - Equipment and consumables

    @Test func equippingGearChangesStats() throws {
        var bag = Inventory()
        bag.add(.twigSword, count: 1)
        bag.add(.barkMail, count: 1)
        var sim = GameSimulation(seed: 1)
        let player = sim.spawnPlayer(profile: PlayerProfile(inventory: bag))
        let base = try #require(sim.entity(player)).stats

        sim.enqueue(.equip(.twigSword), from: player)
        sim.enqueue(.equip(.barkMail), from: player) // level 8 item
        let events = run(&sim, seconds: 0.1)
        #expect(events.contains(.actionFailed(player: player, reason: .levelTooLow)))
        var status = try #require(sim.playerStatus(player))
        #expect(status.stats.attack == base.attack + 4)
        #expect(status.equipment[.weapon] == .twigSword)
        #expect(status.inventory.count(of: .twigSword) == 0)
        #expect(sim.snapshot().entity(player)?.gear == [.twigSword])

        sim.enqueue(.unequip(.weapon), from: player)
        _ = run(&sim, seconds: 0.1)
        status = try #require(sim.playerStatus(player))
        #expect(status.stats.attack == base.attack)
        #expect(status.inventory.count(of: .twigSword) == 1)
    }

    @Test func potionsHealAndShareACooldown() throws {
        var sim = GameSimulation(seed: 1)
        let player = sim.spawnPlayer(profile: .newCharacter)
        sim.entities[player]?.stats.hp = 10
        sim.entities[player]?.combat.lastCombatTick = 1 // in combat: no fast regen

        sim.enqueue(.useItem(.dewPotion), from: player)
        sim.enqueue(.useItem(.dewPotion), from: player)
        let events = run(&sim, seconds: 0.1)
        #expect(events.contains(.heal(target: player, amount: 60, skill: nil)))
        #expect(events.contains(.actionFailed(player: player, reason: .itemCooldown)))
        #expect(sim.playerStatus(player)?.inventory.count(of: .dewPotion) == 2)
    }

    // MARK: - Quests

    @Test func killQuestFromAcceptToReward() throws {
        var sim = GameSimulation(seed: 3)
        let player = sim.spawnPlayer(profile: .newCharacter)
        #expect(sim.playerStatus(player)?.quests.first { $0.id == .shellShock }?.state == .available)
        #expect(sim.playerStatus(player)?.quests.first { $0.id == .slipperySituation }?.state == .hidden)

        try standNear(.elderMorel, player, in: &sim)
        sim.enqueue(.acceptQuest(.shellShock), from: player)
        #expect(run(&sim, seconds: 0.1).contains(.questAccepted(player: player, quest: .shellShock)))

        setLevel(6, player, in: &sim) // survive the grind
        for _ in 0..<6 { _ = try slay(.snail, player, in: &sim) }
        #expect(sim.playerStatus(player)?.quests.first { $0.id == .shellShock }?.state == .readyToTurnIn)

        try standNear(.elderMorel, player, in: &sim)
        sim.enqueue(.completeQuest(.shellShock), from: player)
        let events = run(&sim, seconds: 0.1)
        #expect(events.contains(.questCompleted(player: player, quest: .shellShock)))
        let status = try #require(sim.playerStatus(player))
        #expect(status.inventory.count(of: .twigSword) >= 1)
        #expect(status.quests.first { $0.id == .shellShock }?.state == .completed)
        #expect(status.quests.first { $0.id == .slipperySituation }?.state == .available)
    }

    @Test func collectQuestCountsTheBagAndConsumesItems() throws {
        var sim = GameSimulation(seed: 3)
        var bag = Inventory()
        bag.add(.slugSlime, count: 7)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 3, inventory: bag, completedQuests: [.shellShock]))
        try standNear(.elderMorel, player, in: &sim)

        sim.enqueue(.acceptQuest(.slipperySituation), from: player)
        _ = run(&sim, seconds: 0.1)
        #expect(sim.playerStatus(player)?.quests.first { $0.id == .slipperySituation }?.state == .readyToTurnIn)

        sim.enqueue(.completeQuest(.slipperySituation), from: player)
        _ = run(&sim, seconds: 0.1)
        let status = try #require(sim.playerStatus(player))
        #expect(status.inventory.count(of: .slugSlime) == 2)
        #expect(status.inventory.count(of: .leafTunic) == 1)
    }

    @Test func questLevelGate() throws {
        var sim = GameSimulation(seed: 3)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 5, completedQuests: [.shellShock, .slipperySituation]))
        #expect(sim.playerStatus(player)?.quests.first { $0.id == .barkBeetles }?.state == .tooLowLevel(required: 7))
    }

    // MARK: - Mob abilities

    @Test func snailHidesInItsShellWhenHurt() throws {
        var sim = GameSimulation(seed: 5)
        let player = sim.spawnPlayer(profile: PlayerProfile())
        let events = try slay(.snail, player, in: &sim)
        #expect(events.contains { if case .mobAbility(_, .hide) = $0 { true } else { false } })
    }

    @Test func beetleWindsUpThenCharges() throws {
        var sim = GameSimulation(seed: 8)
        let player = sim.spawnPlayer(profile: PlayerProfile())
        setLevel(12, player, in: &sim)
        let beetle = try #require(sim.snapshot().entities.first { $0.kind == .mob(.beetle) })
        sim.teleport(player, to: beetle.position.xz + Vec2(5, 0)) // inside aggro, in charge range

        var sawWindup = false, sawCharge = false
        for _ in 0..<(GameSimulation.tickRate * 4) {
            _ = sim.step()
            let pose = sim.entity(beetle.id)?.pose
            sawWindup = sawWindup || pose == .windingUp
            sawCharge = sawCharge || (sawWindup && pose == .charging)
        }
        #expect(sawWindup)
        #expect(sawCharge)
    }

    @Test func sporeBeastPoisonsAndSplits() throws {
        var sim = GameSimulation(seed: 13)
        let player = sim.spawnPlayer(profile: PlayerProfile())
        setLevel(15, player, in: &sim)
        let events = try slay(.sporeBeast, player, in: &sim)

        #expect(events.contains { if case .mobAbility(_, .sporeCloud) = $0 { true } else { false } })
        #expect(events.contains { if case .mobAbility(_, .split) = $0 { true } else { false } })
        let sporelings = sim.snapshot().entities.filter { $0.kind == .mob(.sporeling) }
        #expect(sporelings.count == 2)
        #expect(sporelings.allSatisfy { $0.target == player }, "sporelings go straight for the killer")
    }

    @Test func slugSlimeSlowsPlayers() throws {
        var sim = GameSimulation(seed: 2)
        let player = sim.spawnPlayer(profile: PlayerProfile())
        sim.spawnHazard(.slime, at: sim.map.playerSpawn, radius: 2, seconds: 10, owner: player)
        _ = run(&sim, seconds: 0.1)
        #expect(sim.playerStatus(player)?.isSlowed == true)

        let start = try #require(sim.entity(player)).position.xz
        for _ in 0..<10 {
            sim.enqueue(.move(Vec2(1, 0)), from: player)
            _ = sim.step()
        }
        let moved = try #require(sim.entity(player)).position.xz.distance(to: start)
        #expect(moved < GameSimulation.playerSpeed * 0.5 * 0.5 + 0.05)
    }

    // MARK: - Saves

    @Test func profileRoundTripsThroughCodable() throws {
        var sim = GameSimulation(seed: 4)
        var bag = Inventory()
        bag.add(.dewPotion, count: 4)
        bag.add(.snailShell, count: 9)
        let original = PlayerProfile(level: 6, xp: 33, hp: 50, mp: 20, caps: 123, inventory: bag,
                                     equipment: [.weapon: .thornRapier], activeQuests: [.slipperySituation: 0],
                                     completedQuests: [.shellShock], position: Vec2(10, 40))
        let player = sim.spawnPlayer(profile: original)
        let saved = try #require(sim.profile(of: player))

        let decoded = try JSONDecoder().decode(PlayerProfile.self, from: JSONEncoder().encode(saved))
        #expect(decoded == saved)
        #expect(decoded.level == 6)
        #expect(decoded.caps == 123)
        #expect(decoded.equipment[.weapon] == .thornRapier)
        #expect(decoded.inventory == bag)
        #expect(decoded.completedQuests == [.shellShock])
        #expect(sim.entity(player)?.stats.attack == Progression.playerStats(level: 6).attack + 9)
    }
}
