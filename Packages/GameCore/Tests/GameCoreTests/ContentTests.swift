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

    /// Every main-story quest before `quest`, done.
    private func storyBefore(_ quest: QuestID) -> Set<QuestID> {
        Set(QuestID.mainStory.prefix { $0 != quest })
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

    @Test func killsLeaveCapsAndItemsOnTheGroundUntilCollected() throws {
        var sim = GameSimulation(seed: 21)
        let player = sim.spawnPlayer(profile: PlayerProfile())
        setLevel(8, player, in: &sim)
        var events: [WorldEvent] = []
        for _ in 0..<8 {
            events += try slay(.snail, player, in: &sim)
            for drop in sim.snapshot(for: player).drops {
                sim.teleport(player, to: drop.position)
                sim.enqueue(.pickupDrop(drop.id), from: player)
                events += sim.step()
            }
        }

        let status = try #require(sim.playerStatus(player))
        #expect(status.caps > 0)
        #expect(status.inventory.count(of: .snailShell) > 0)
        #expect(events.contains { if case .itemReceived(player, .snailShell, _) = $0 { true } else { false } })
    }

    @Test func groundDropsRequireOwnershipAndProximity() throws {
        var sim = GameSimulation(seed: 22)
        let owner = sim.spawnPlayer()
        let other = sim.spawnPlayer()
        let startingCaps = try #require(sim.playerStatus(owner)).caps
        let mob = try #require(sim.snapshot().entities.first { $0.kind == .mob(.snail) })
        let ownerEntity = try #require(sim.entity(owner))
        // A Giant always drops caps (a regular mob only sometimes).
        sim.rollLoot(for: .snail, giant: true, ownedBy: ownerEntity, at: mob.position.xz)
        let drop = try #require(sim.snapshot(for: owner).drops.first)
        #expect(sim.snapshot(for: other).drops.isEmpty)
        #expect(sim.playerStatus(owner)?.caps == startingCaps)

        sim.enqueue(.pickupDrop(drop.id), from: other)
        #expect(sim.step().contains(.actionFailed(player: other, reason: .notAvailable)))
        sim.enqueue(.pickupDrop(drop.id), from: owner)
        #expect(sim.step().contains(.actionFailed(player: owner, reason: .tooFar)))

        sim.teleport(owner, to: drop.position)
        sim.enqueue(.pickupDrop(drop.id), from: owner)
        let events = sim.step()
        #expect(events.contains { if case .capsChanged(owner, _) = $0 { true } else { false } })
        #expect(sim.snapshot(for: owner).drops.allSatisfy { $0.id != drop.id })
    }

    @Test func nearbyDropsAreCollectedAfterTheirDisplayDelay() throws {
        var sim = GameSimulation(seed: 24)
        let player = sim.spawnPlayer()
        let origin = try #require(sim.entity(player)).position.xz
        let initialCaps = try #require(sim.playerStatus(player)).caps
        let owner = try #require(sim.entity(player))
        sim.rollLoot(for: .snail, ownedBy: owner, at: origin)
        #expect(sim.snapshot(for: player).drops.contains { if case .caps = $0.kind { true } else { false } })

        _ = run(&sim, seconds: 0.5)
        #expect(sim.playerStatus(player)?.caps == initialCaps)
        let events = run(&sim, seconds: 0.5)
        #expect(events.contains { if case .capsChanged(player, _) = $0 { true } else { false } })
        #expect(sim.playerStatus(player)?.caps ?? 0 > initialCaps)
    }

    @Test func fullBagKeepsDropOnGround() throws {
        var bag = Inventory()
        for _ in 0..<Inventory.capacity { bag.add(.twigSword, count: 1) }
        var sim = GameSimulation(seed: 23)
        let player = sim.spawnPlayer(profile: PlayerProfile(inventory: bag))
        let origin = try #require(sim.entity(player)).position.xz
        sim.drops.append(GroundDrop(id: 1, owner: player, position: origin, kind: .item(.snailShell, count: 2),
                                    availableAtTick: 0, expiresAtTick: 1_000))
        sim.nextDropID = 1

        _ = sim.step()
        #expect(sim.snapshot(for: player).drops.count == 1)
        #expect(sim.playerStatus(player)?.inventory.count(of: .snailShell) == 0)

        sim.entities[player]?.player?.inventory = Inventory()
        let events = sim.step()
        #expect(events.contains(.itemReceived(player: player, item: .snailShell, count: 2)))
        #expect(sim.snapshot(for: player).drops.isEmpty)
    }

    // MARK: - Shop

    @Test func buyingAndSellingAtTheShop() throws {
        var sim = GameSimulation(seed: 1)
        let player = sim.spawnPlayer(profile: PlayerProfile(caps: 50))

        sim.enqueue(.buy(.twigSword, from: .oyster), from: player)
        #expect(run(&sim, seconds: 0.1).contains(.actionFailed(player: player, reason: .tooFar)))

        try standNear(.oyster, player, in: &sim)
        sim.enqueue(.buy(.twigSword, from: .oyster), from: player)
        sim.enqueue(.buy(.twigSword, from: .oyster), from: player)
        let events = run(&sim, seconds: 0.1)
        #expect(events.contains(.actionFailed(player: player, reason: .notEnoughCaps)))
        var status = try #require(sim.playerStatus(player))
        #expect(status.caps == 10)
        #expect(status.inventory.count(of: .twigSword) == 1)

        sim.enqueue(.sell(.twigSword, count: 1, to: .oyster), from: player)
        _ = run(&sim, seconds: 0.1)
        status = try #require(sim.playerStatus(player))
        #expect(status.caps == 10 + ItemID.twigSword.definition.sellPrice)
        #expect(status.inventory.count(of: .twigSword) == 0)

        sim.enqueue(.buy(.moonTalon, from: .oyster), from: player)
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
        #expect(status.equipment[.weapon]?.item == .twigSword)
        #expect(status.inventory.count(of: .twigSword) == 0)
        #expect(sim.snapshot().entity(player)?.gear == [.twigSword])

        sim.enqueue(.unequip(.weapon), from: player)
        _ = run(&sim, seconds: 0.1)
        status = try #require(sim.playerStatus(player))
        #expect(status.stats.attack == base.attack)
        #expect(status.inventory.count(of: .twigSword) == 1)
    }

    @Test func weaponTypesSetSpeedAndReach() throws {
        var bag = Inventory()
        bag.add(.pebbleHatchet, count: 1)
        bag.add(.reedBow, count: 1)
        var sim = GameSimulation(seed: 1)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 15, inventory: bag, playerClass: .thornshot))
        let unarmed = try #require(sim.entity(player)).stats
        #expect(unarmed.reach > 2, "bare-handed thornshots still fling thorns")

        sim.enqueue(.equip(.pebbleHatchet), from: player)
        _ = run(&sim, seconds: 0.1)
        var stats = try #require(sim.entity(player)).stats
        #expect(stats.reach < 2, "an axe is a melee weapon, whoever holds it")
        #expect(stats.attackInterval > unarmed.attackInterval)
        #expect(sim.snapshot().entity(player)?.weapon == .axe)

        sim.enqueue(.equip(.reedBow), from: player)
        _ = run(&sim, seconds: 0.1)
        stats = try #require(sim.entity(player)).stats
        #expect(stats.reach == WeaponType.bow.reach)
        #expect(sim.snapshot().entity(player)?.fightsAtRange == true)
    }

    @Test func classWeaponsNeedTheClass() throws {
        var bag = Inventory()
        bag.add(.toadstoolMaul, count: 1)
        var sim = GameSimulation(seed: 1)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 16, inventory: bag, playerClass: .sporecaster))
        sim.enqueue(.equip(.toadstoolMaul), from: player)
        #expect(run(&sim, seconds: 0.1).contains(.actionFailed(player: player, reason: .wrongClass)))
        #expect(try #require(sim.playerStatus(player)).equipment[.weapon] == nil)
    }

    @Test func twoHandedWeaponsAndShieldsPushEachOtherOff() throws {
        var bag = Inventory()
        bag.add(.toadstoolMaul, count: 1)
        bag.add(.shellShield, count: 1)
        var sim = GameSimulation(seed: 1)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 16, inventory: bag,
                                                            equipment: [.weapon: Gear(.twigSword), .shield: Gear(.barkBuckler)],
                                                            playerClass: .guardian))
        sim.enqueue(.equip(.toadstoolMaul), from: player)
        _ = run(&sim, seconds: 0.1)
        var status = try #require(sim.playerStatus(player))
        #expect(status.equipment[.weapon]?.item == .toadstoolMaul)
        #expect(status.equipment[.shield] == nil)
        #expect(status.inventory.count(of: .twigSword) == 1)
        #expect(status.inventory.count(of: .barkBuckler) == 1)
        #expect(status.stats.blockChance == 0)

        sim.enqueue(.equip(.shellShield), from: player)
        _ = run(&sim, seconds: 0.1)
        status = try #require(sim.playerStatus(player))
        #expect(status.equipment[.shield]?.item == .shellShield)
        #expect(status.equipment[.weapon] == nil, "the maul needs both hands")
        #expect(status.inventory.count(of: .toadstoolMaul) == 1)
        // Guards are better at blocking than anyone.
        #expect(abs(status.stats.blockChance - (0.07 + 0.05)) < 0.0001)
    }

    @Test func shieldsBlockMobAttacks() throws {
        func blocks(shield: Bool) throws -> (blocked: Int, hits: Int) {
            var sim = GameSimulation(seed: 3)
            let player = sim.spawnPlayer(profile: PlayerProfile(level: 10, equipment: shield ? [.shield: Gear(.beetleAegis)] : [:]))
            sim.entities[player]?.stats.maxHP = 100_000
            sim.entities[player]?.stats.hp = 100_000
            let slug = try #require(sim.snapshot().entities.first { $0.kind == .mob(.slug) })
            sim.teleport(player, to: slug.position.xz + Vec2(1, 0))
            let events = run(&sim, seconds: 60)
            let blocked = events.count { if case .blocked(slug.id, player) = $0 { true } else { false } }
            let hits = events.count { if case .damage(slug.id, player, _, _, _) = $0 { true } else { false } }
            return (blocked, hits)
        }
        let unshielded = try blocks(shield: false)
        #expect(unshielded.blocked == 0)
        let shielded = try blocks(shield: true)
        #expect(shielded.blocked > 0)
        #expect(shielded.hits > shielded.blocked * 3, "a 10% block shouldn't stop most hits")
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
        #expect(sim.playerStatus(player)?.quests.first { $0.id == .spotsBeforeYourEyes }?.state == .hidden)

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
        #expect(status.quests.first { $0.id == .spotsBeforeYourEyes }?.state == .available, "the story moves on")
        #expect(status.quests.first { $0.id == .slipperySituation }?.state == .hidden)
    }

    @Test func collectQuestCountsTheBagAndConsumesItems() throws {
        var sim = GameSimulation(seed: 3)
        var bag = Inventory()
        bag.add(.slugSlime, count: 7)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 4, inventory: bag, completedQuests: storyBefore(.slipperySituation)))
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
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 5, completedQuests: storyBefore(.barkBeetles)))
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
        let beetle = try #require(sim.snapshot().entities.first { $0.kind == .mob(.beetle) && $0.isAggressive })
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
        setLevel(18, player, in: &sim) // bog frogs share the fen and may join in
        let events = try slay(.sporeBeast, player, in: &sim)

        #expect(events.contains { if case .mobAbility(_, .cloud) = $0 { true } else { false } })
        #expect(events.contains { if case .mobAbility(_, .split) = $0 { true } else { false } })
        let sporelings = sim.snapshot().entities.filter { $0.kind == .mob(.sporeling) }
        #expect(sporelings.count == 2)
        #expect(sporelings.allSatisfy { $0.target == player }, "sporelings go straight for the killer")
    }

    @Test func outerRingMobsReuseTheAbilities() throws {
        var sim = GameSimulation(seed: 21)
        let player = sim.spawnPlayer(profile: PlayerProfile())
        setLevel(30, player, in: &sim)

        let curl = try slay(.pillBug, player, in: &sim)
        #expect(curl.contains { if case .mobAbility(_, .hide) = $0 { true } else { false } }, "pill bugs curl up")

        let burst = try slay(.puffweed, player, in: &sim)
        #expect(burst.contains { if case .mobAbility(_, .split) = $0 { true } else { false } })
        #expect(sim.snapshot().entities.filter { $0.kind == .mob(.puffling) }.count == 2)
    }

    @Test func bogFrogsLeapLikeBeetlesCharge() throws {
        var sim = GameSimulation(seed: 8)
        let player = sim.spawnPlayer(profile: PlayerProfile())
        setLevel(16, player, in: &sim)
        let frog = try #require(sim.snapshot().entities.first { $0.kind == .mob(.bogFrog) })
        sim.teleport(player, to: frog.position.xz + Vec2(5, 0))

        var sawWindup = false, sawCharge = false
        for _ in 0..<(GameSimulation.tickRate * 4) {
            _ = sim.step()
            let pose = sim.entity(frog.id)?.pose
            sawWindup = sawWindup || pose == .windingUp
            sawCharge = sawCharge || (sawWindup && pose == .charging)
        }
        #expect(sawWindup && sawCharge)
    }

    @Test func emberNewtsLeaveBurningTrailsWhileChasing() throws {
        var sim = GameSimulation(seed: 3)
        let player = sim.spawnPlayer(profile: PlayerProfile())
        setLevel(20, player, in: &sim)
        let newt = try #require(sim.snapshot().entities.first { $0.kind == .mob(.emberNewt) })
        _ = run(&sim, seconds: 3)
        #expect(!sim.hazards.contains { $0.kind == .embers }, "no embers while wandering")

        // Pick a fight from range, then keep backing off so it has to chase.
        sim.teleport(player, to: try #require(sim.entity(newt.id)).position.xz + Vec2(4, 0))
        sim.entities[newt.id]?.combat.target = player
        sim.entities[newt.id]?.combat.engaged = true
        sim.entities[newt.id]?.brain?.state = .engaged
        for _ in 0..<(GameSimulation.tickRate * 2) {
            sim.enqueue(.move(Vec2(1, 0)), from: player)
            _ = sim.step()
        }
        let embers = sim.hazards.filter { $0.kind == .embers }
        #expect(!embers.isEmpty)
        #expect(embers.allSatisfy { $0.damagePerSecond > 0 })
    }

    @Test func spiderWebsSlowLikeSlime() throws {
        var sim = GameSimulation(seed: 2)
        let player = sim.spawnPlayer(profile: PlayerProfile())
        sim.spawnHazard(.web, at: sim.map.playerSpawn, radius: 2, seconds: 10, owner: player)
        _ = run(&sim, seconds: 0.1)
        #expect(sim.playerStatus(player)?.isSlowed == true)
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
                                     equipment: [.weapon: Gear(.thornRapier)], activeQuests: [.slipperySituation: 0],
                                     completedQuests: [.shellShock], position: Vec2(10, 40))
        let player = sim.spawnPlayer(profile: original)
        let saved = try #require(sim.profile(of: player))

        let decoded = try JSONDecoder().decode(PlayerProfile.self, from: JSONEncoder().encode(saved))
        #expect(decoded == saved)
        #expect(decoded.level == 6)
        #expect(decoded.caps == 123)
        #expect(decoded.equipment[.weapon] == Gear(.thornRapier))
        #expect(decoded.inventory == bag)
        #expect(decoded.completedQuests == [.shellShock])
        #expect(sim.entity(player)?.stats.attack == Progression.playerStats(level: 6).attack + 9)
    }
}
