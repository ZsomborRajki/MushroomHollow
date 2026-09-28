import Foundation
import Testing
@testable import GameCore

@Suite struct PetTests {
    // MARK: - Helpers

    private func run(_ sim: inout GameSimulation, seconds: Float) -> [WorldEvent] {
        var events: [WorldEvent] = []
        for _ in 0..<Int(seconds * Float(GameSimulation.tickRate)) { events += sim.step() }
        return events
    }

    /// A player standing in the village (no mobs around) with Pip in the bag.
    private func villageWithPip(level: Int = 5) -> (GameSimulation, EntityID) {
        var sim = GameSimulation(seed: 7)
        var bag = Inventory()
        bag.add(.pip, count: 1)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: level, inventory: bag))
        sim.teleport(player, to: sim.map.playerSpawn)
        return (sim, player)
    }

    private func summonPip(_ player: EntityID, in sim: inout GameSimulation) {
        sim.enqueue(.slotPet(.pip), from: player)
        sim.enqueue(.summonPet, from: player)
        _ = sim.step()
    }

    @discardableResult
    private func drop(_ kind: GroundDropKind, for owner: EntityID, at position: Vec2, in sim: inout GameSimulation) -> UInt32 {
        sim.nextDropID += 1
        sim.drops.append(GroundDrop(id: sim.nextDropID, owner: owner, position: sim.map.resolve(position, radius: 0.15), kind: kind,
                                    availableAtTick: sim.tick, expiresAtTick: sim.tick + 100_000))
        return sim.nextDropID
    }

    private func pet(of player: EntityID, in sim: GameSimulation) -> PetData? {
        sim.entities[player]?.player?.pet
    }

    private func setFullness(_ ticks: Int, _ player: EntityID, in sim: inout GameSimulation) {
        sim.entities[player]?.player?.pet.fullness[.pup] = ticks
    }

    // MARK: - Getting a pet

    @Test func truffleGivesPipForSnailShells() throws {
        var sim = GameSimulation(seed: 3)
        var bag = Inventory()
        bag.add(.snailShell, count: 5)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 3, inventory: bag, completedQuests: [.shellShock]))
        let truffle = try #require(sim.map.placement(of: .truffle))
        sim.teleport(player, to: truffle.position + Vec2(0, -1.2))

        sim.enqueue(.acceptQuest(.aNoseForTrouble), from: player)
        _ = sim.step()
        sim.enqueue(.completeQuest(.aNoseForTrouble), from: player)
        let events = sim.step()

        #expect(events.contains(.questCompleted(player: player, quest: .aNoseForTrouble)))
        let inventory = try #require(sim.playerStatus(player)).inventory
        #expect(inventory.count(of: .pip) == 1)
        #expect(inventory.count(of: .kibble) == 30)
        #expect(inventory.count(of: .snailShell) == 0)
    }

    @Test func petQuestNeedsShellShockFirst() {
        var sim = GameSimulation(seed: 3)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 5))
        #expect(sim.playerStatus(player)?.quests.first { $0.id == .aNoseForTrouble }?.state == .hidden)
    }

    @Test func truffleStandsInTheOpen() throws {
        let map = WorldMap.mushroomHollow
        let truffle = try #require(map.placement(of: .truffle))
        #expect(map.zone(at: truffle.position)?.name == "Capstone Village")
        // Players can walk up to talk from any side.
        for angle in stride(from: Float(0), to: 2 * .pi, by: .pi / 2) {
            let spot = truffle.position + AngleMath.direction(forYaw: angle) * 1.5
            #expect(!map.isBlocked(spot, radius: GameSimulation.playerRadius), "blocked at \(angle)")
        }
        for other in map.npcs where other.id != .truffle {
            #expect(other.position.distance(to: truffle.position) > NPCID.interactionRange)
        }
    }

    // MARK: - Slot, summon, dismiss

    @Test func slottingAndSummoningBringsPipOut() throws {
        var (sim, player) = villageWithPip()
        summonPip(player, in: &sim)

        let status = try #require(sim.playerStatus(player))
        #expect(status.pet.slot == .pip)
        #expect(status.pet.isSummoned && status.pet.isOut)
        #expect(status.inventory.count(of: .pip) == 0)
        let snapshot = sim.snapshot(for: player)
        let pip = try #require(snapshot.pets.first)
        #expect(pip.owner == player && pip.kind == .pup)
        #expect(pip.position.xz.distance(to: try #require(snapshot.entity(player)).position.xz) < 2)
        // Pets are companions, not combatants: never a target.
        #expect(snapshot.hostiles(near: pip.position).allSatisfy { $0.kind.isMob })
    }

    @Test func summonNeedsAPetInTheSlot() {
        var (sim, player) = villageWithPip()
        sim.enqueue(.summonPet, from: player)
        #expect(sim.step().contains(.actionFailed(player: player, reason: .noPet)))
        sim.enqueue(.slotPet(.snailShell), from: player)
        #expect(sim.step().contains(.actionFailed(player: player, reason: .notUsable)))
    }

    @Test func dismissingAndUnslotting() throws {
        var (sim, player) = villageWithPip()
        summonPip(player, in: &sim)

        sim.enqueue(.dismissPet, from: player)
        #expect(sim.step().contains(.petDismissed(player: player, reason: .requested)))
        #expect(sim.snapshot().pets.isEmpty)
        #expect(sim.playerStatus(player)?.pet.slot == .pip)

        sim.enqueue(.summonPet, from: player)
        _ = sim.step()
        sim.enqueue(.unslotPet, from: player)
        #expect(sim.step().contains(.petDismissed(player: player, reason: .unslotted)))
        let status = try #require(sim.playerStatus(player))
        #expect(status.pet.slot == nil && !status.pet.isSummoned)
        #expect(status.inventory.count(of: .pip) == 1)
        #expect(sim.snapshot().pets.isEmpty)
    }

    @Test func pipCantBeSold() throws {
        var (sim, player) = villageWithPip()
        let shop = try #require(sim.map.placement(of: .chanterelle))
        sim.teleport(player, to: shop.position + Vec2(0, 1.2))
        sim.enqueue(.sell(.pip, count: 1, to: .chanterelle), from: player)
        #expect(sim.step().contains(.actionFailed(player: player, reason: .notAvailable)))
        #expect(sim.playerStatus(player)?.inventory.count(of: .pip) == 1)
    }

    // MARK: - Following and fetching

    @Test func pipFollowsItsOwner() throws {
        var (sim, player) = villageWithPip()
        summonPip(player, in: &sim)
        sim.enqueue(.move(Vec2(0, 1)), from: player)
        _ = run(&sim, seconds: 3)
        sim.enqueue(.move(.zero), from: player)
        _ = run(&sim, seconds: 2)

        let snapshot = sim.snapshot()
        let me = try #require(snapshot.entity(player)).position.xz
        let pip = try #require(snapshot.pets.first)
        #expect(me.distance(to: sim.map.playerSpawn) > 10, "the player walked")
        #expect(pip.position.xz.distance(to: me) < 2.5)
        #expect(!pip.isMoving, "settles down once you stop")
    }

    @Test func pipFetchesOnlyItsOwnersDrops() throws {
        var (sim, player) = villageWithPip()
        var stranger = PlayerProfile()
        stranger.position = sim.map.playerSpawn + Vec2(0, -30)
        let other = sim.spawnPlayer(profile: stranger)
        summonPip(player, in: &sim)

        let spawn = sim.map.playerSpawn
        let mine = drop(.item(.snailShell, count: 2), for: player, at: spawn + Vec2(4, 1.5), in: &sim)
        let caps = drop(.caps(9), for: player, at: spawn + Vec2(-3, 2.5), in: &sim)
        let theirs = drop(.item(.slugSlime, count: 1), for: other, at: spawn + Vec2(3, -2), in: &sim)
        let capsBefore = try #require(sim.playerStatus(player)).caps

        let events = run(&sim, seconds: 6)
        #expect(events.filter { $0 == .petFetched(player: player) }.count == 2)
        #expect(!sim.drops.contains { $0.id == mine || $0.id == caps })
        #expect(sim.drops.contains { $0.id == theirs })
        let status = try #require(sim.playerStatus(player))
        #expect(status.inventory.count(of: .snailShell) == 2)
        #expect(status.caps == capsBefore + 9)
        #expect(sim.entity(player)?.position.xz.distance(to: spawn) ?? 99 < 0.5, "the owner never moved")
    }

    @Test func pipIgnoresFarDropsAndOnesThatDontFit() throws {
        var (sim, player) = villageWithPip()
        summonPip(player, in: &sim)
        let spawn = sim.map.playerSpawn
        // Fill the bag: 23 swords plus the Pip-free slot's worth of potions.
        sim.entities[player]?.player?.inventory.add(.twigSword, count: 23)
        sim.entities[player]?.player?.inventory.add(.dewPotion, count: 20)
        let full = drop(.item(.slugSlime, count: 1), for: player, at: spawn + Vec2(3, 2), in: &sim)
        let stackable = drop(.item(.dewPotion, count: 5), for: player, at: spawn + Vec2(-3, 2), in: &sim)
        let far = drop(.caps(5), for: player, at: spawn + Vec2(0, 12), in: &sim)

        _ = run(&sim, seconds: 3)
        #expect(sim.drops.contains { $0.id == full }, "no room for slime")
        #expect(sim.drops.contains { $0.id == stackable }, "the potion stack is full too")
        #expect(sim.drops.contains { $0.id == far }, "too far from its owner")

        sim.entities[player]?.player?.inventory.remove(.dewPotion, count: 3)
        _ = run(&sim, seconds: 3)
        #expect(sim.playerStatus(player)?.inventory.count(of: .dewPotion) == 20)
        let leftover = sim.drops.first { $0.id == stackable }
        #expect(leftover?.kind == .item(.dewPotion, count: 2), "picks up what fits, leaves the rest")
    }

    @Test func pipCatchesUpAfterATeleport() throws {
        var (sim, player) = villageWithPip()
        summonPip(player, in: &sim)
        sim.teleport(player, to: sim.map.playerSpawn + Vec2(0, 40))
        _ = sim.step()
        let pip = try #require(sim.snapshot().pets.first)
        #expect(pip.position.xz.distance(to: try #require(sim.entity(player)).position.xz) < 3)
    }

    // MARK: - Flight and fainting

    @Test func pipHidesWhileFlyingAndReturnsOnLanding() throws {
        var (sim, player) = villageWithPip(level: 10)
        sim.entities[player]?.player?.inventory.add(.dandelionSeed, count: 1)
        summonPip(player, in: &sim)

        sim.enqueue(.toggleFlight, from: player)
        sim.enqueue(.climb(1), from: player)
        _ = run(&sim, seconds: 1)
        #expect(sim.snapshot().pets.isEmpty)
        #expect(sim.playerStatus(player)?.pet.isSummoned == true, "still wants to come along")
        let fullness = try #require(pet(of: player, in: sim)).fullness(of: .pup)
        _ = run(&sim, seconds: 2)
        #expect(pet(of: player, in: sim)?.fullness(of: .pup) == fullness, "no hunger while tucked away")

        sim.enqueue(.toggleFlight, from: player)
        _ = run(&sim, seconds: 6)
        #expect(sim.entity(player)?.position.y == 0)
        #expect(sim.snapshot().pets.count == 1)
    }

    @Test func pipHidesWhileYouAreFainted() {
        var (sim, player) = villageWithPip()
        summonPip(player, in: &sim)
        sim.entities[player]?.stats.hp = 0
        _ = sim.step()
        #expect(sim.snapshot().pets.isEmpty)
        sim.enqueue(.respawn, from: player)
        _ = run(&sim, seconds: 0.2)
        #expect(sim.snapshot().pets.count == 1)
    }

    // MARK: - Hunger and food

    @Test func hungryPipSlowsDown() throws {
        var (sim, player) = villageWithPip()
        summonPip(player, in: &sim)

        func chaseSpeed(_ sim: inout GameSimulation) throws -> Float {
            sim.teleport(player, to: sim.map.playerSpawn)
            _ = run(&sim, seconds: 1.5)
            sim.teleport(player, to: sim.map.playerSpawn + Vec2(0, 12))
            _ = sim.step()
            let start = try #require(sim.snapshot().pets.first).position.xz
            _ = run(&sim, seconds: 0.5)
            return try #require(sim.snapshot().pets.first).position.xz.distance(to: start) / 0.5
        }

        let fed = try chaseSpeed(&sim)
        setFullness(GameSimulation.petHungryFullness + 3, player, in: &sim)
        let events = run(&sim, seconds: 0.25)
        #expect(events.contains(.petHungry(player: player)))
        #expect(sim.playerStatus(player)?.pet.isHungry == true)
        #expect(sim.snapshot().pets.first?.isHungry == true)
        let hungry = try chaseSpeed(&sim)
        #expect(hungry < fed * 0.7, "fed \(fed) m/s, hungry \(hungry) m/s")
    }

    @Test func starvingPipGoesHomeAndComesBackWhenFed() throws {
        var (sim, player) = villageWithPip()
        summonPip(player, in: &sim)
        setFullness(3, player, in: &sim)

        let events = run(&sim, seconds: 0.5)
        #expect(events.contains(.petDismissed(player: player, reason: .starving)))
        #expect(sim.snapshot().pets.isEmpty)
        var status = try #require(sim.playerStatus(player)).pet
        #expect(status.awaitingFood && !status.isSummoned && status.fullness == 0)

        sim.enqueue(.summonPet, from: player)
        #expect(sim.step().contains(.actionFailed(player: player, reason: .petHungry)))
        sim.enqueue(.useItem(.kibble), from: player)
        #expect(sim.step().contains(.actionFailed(player: player, reason: .missingItem)))

        sim.entities[player]?.player?.inventory.add(.kibble, count: 200)
        sim.enqueue(.useItem(.kibble), from: player)
        let fed = sim.step()
        let meal = GameSimulation.petMaxFullness / GameSimulation.kibbleFullness
        #expect(fed.contains(.petFed(player: player, kibble: meal)))
        #expect(fed.contains(.petSummoned(player: player)))
        _ = sim.step()
        status = try #require(sim.playerStatus(player)).pet
        #expect(status.isOut && !status.awaitingFood && status.fullness > 0.99)
        #expect(sim.playerStatus(player)?.inventory.count(of: .kibble) == 200 - meal)
    }

    @Test func feedingUsesOnlyWhatItNeeds() throws {
        var (sim, player) = villageWithPip()
        sim.enqueue(.slotPet(.pip), from: player)
        _ = sim.step()
        sim.entities[player]?.player?.inventory.add(.kibble, count: 10)
        sim.enqueue(.useItem(.kibble), from: player)
        #expect(sim.step().contains(.actionFailed(player: player, reason: .petFull)))

        // Two and a half Kibble short: three go in, and it's full.
        setFullness(GameSimulation.petMaxFullness - GameSimulation.kibbleFullness * 5 / 2, player, in: &sim)
        sim.enqueue(.useItem(.kibble), from: player)
        #expect(sim.step().contains(.petFed(player: player, kibble: 3)))
        #expect(pet(of: player, in: sim)?.fullness(of: .pup) == GameSimulation.petMaxFullness)
        #expect(sim.playerStatus(player)?.inventory.count(of: .kibble) == 7)
        // Pet food isn't a potion: no shared cooldown.
        #expect(sim.playerStatus(player)?.itemCooldown == 0)
    }

    @Test func aFullBellyLastsHalfAnHour() {
        #expect(GameSimulation.petMaxFullness == 30 * 60 * GameSimulation.tickRate)
        #expect(GameSimulation.petMaxFullness / GameSimulation.kibbleFullness == 10)
        #expect(ItemID.kibble.definition.maxStack == 200)
    }

    @Test func truffleBakesMaterialsIntoKibble() throws {
        var (sim, player) = villageWithPip()
        let truffle = try #require(sim.map.placement(of: .truffle))
        sim.entities[player]?.player?.inventory.add(.snailShell, count: 10)
        sim.entities[player]?.player?.inventory.add(.stagMandible, count: 4)
        sim.entities[player]?.player?.inventory.add(.amberShard, count: 3)

        sim.enqueue(.makePetFood(.snailShell, count: 10, at: .truffle), from: player)
        #expect(sim.step().contains(.actionFailed(player: player, reason: .tooFar)))

        sim.teleport(player, to: truffle.position + Vec2(0, -1.2))
        sim.enqueue(.makePetFood(.snailShell, count: 10, at: .truffle), from: player)
        #expect(sim.step().contains(.itemReceived(player: player, item: .kibble, count: 10)))
        sim.enqueue(.makePetFood(.stagMandible, count: 4, at: .truffle), from: player)
        #expect(sim.step().contains(.itemReceived(player: player, item: .kibble, count: 4 * 13)))
        sim.enqueue(.makePetFood(.amberShard, count: 3, at: .truffle), from: player)
        #expect(sim.step().contains(.actionFailed(player: player, reason: .notUsable)))
        sim.enqueue(.makePetFood(.beetleHorn, count: 1, at: .truffle), from: player)
        #expect(sim.step().contains(.actionFailed(player: player, reason: .missingItem)))
        sim.enqueue(.makePetFood(.snailShell, count: 1, at: .chanterelle), from: player)
        #expect(sim.step().contains(.actionFailed(player: player, reason: .tooFar)))

        let bag = try #require(sim.playerStatus(player)).inventory
        #expect(bag.count(of: .kibble) == 62)
        #expect(bag.count(of: .snailShell) == 0 && bag.count(of: .stagMandible) == 0)
        #expect(bag.count(of: .amberShard) == 3)
    }

    @Test func kibbleStacksTo200AndBakingIsAllOrNothing() throws {
        var (sim, player) = villageWithPip()
        let truffle = try #require(sim.map.placement(of: .truffle))
        sim.teleport(player, to: truffle.position + Vec2(0, -1.2))
        sim.entities[player]?.player?.inventory.add(.kibble, count: 190)
        sim.entities[player]?.player?.inventory.add(.snailShell, count: 30)
        sim.entities[player]?.player?.inventory.add(.twigSword, count: 21) // bag: pip, kibble, shells, 21 swords = full

        // Baking 30 shells frees the shell slot, so 190 + 30 = 220 Kibble fits as 200 + 20.
        sim.enqueue(.makePetFood(.snailShell, count: 30, at: .truffle), from: player)
        _ = sim.step()
        let bag = try #require(sim.playerStatus(player)).inventory
        #expect(bag.count(of: .kibble) == 220)
        #expect(bag.stacks.filter { $0.item == .kibble }.map(\.count).sorted() == [20, 200])

        // 40 mandibles bake into 520 Kibble: 180 top up the small stack, but the rest needs two
        // new stacks and baking frees only one slot. The whole batch is refused and nothing is lost.
        sim.entities[player]?.player?.inventory.remove(.twigSword, count: 1)
        sim.entities[player]?.player?.inventory.add(.stagMandible, count: 40)
        sim.enqueue(.makePetFood(.stagMandible, count: 40, at: .truffle), from: player)
        #expect(sim.step().contains(.actionFailed(player: player, reason: .inventoryFull)))
        #expect(sim.playerStatus(player)?.inventory.count(of: .stagMandible) == 40)
        #expect(sim.playerStatus(player)?.inventory.count(of: .kibble) == 220)
    }

    @Test func kibbleValuesFollowMaterialWorth() {
        #expect(ItemID.snailShell.kibbleValue == 1)
        #expect(ItemID.beetleHorn.kibbleValue == 3)
        #expect(ItemID.stagMandible.kibbleValue == 13)
        #expect(ItemID.amberShard.kibbleValue == nil)
        #expect(ItemID.wardCharm.kibbleValue == nil)
        #expect(ItemID.dewPotion.kibbleValue == nil)
        // Every mob's own material can feed a pet.
        for kind in MobKind.allCases where kind != .mouse {
            #expect(kind.drops.contains { $0.item.kibbleValue != nil }, "\(kind)")
        }
    }

    // MARK: - Saves

    @Test func petSurvivesASaveRoundTrip() throws {
        var (sim, player) = villageWithPip()
        summonPip(player, in: &sim)
        setFullness(1234, player, in: &sim)
        let saved = try #require(sim.profile(of: player))
        let decoded = try JSONDecoder().decode(PlayerProfile.self, from: JSONEncoder().encode(saved))
        #expect(decoded == saved)

        var restored = GameSimulation(seed: 1)
        let again = restored.spawnPlayer(profile: decoded)
        _ = restored.step()
        let status = try #require(restored.playerStatus(again)).pet
        #expect(status.slot == .pip && status.isSummoned && status.isOut)
        #expect(restored.snapshot().pets.count == 1)
        #expect(restored.entities[again]?.player?.pet.fullness(of: .pup) == 1233)
    }

    @Test func savesFromBeforePetsStillLoad() throws {
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PlayerProfile.newCharacter)) as! [String: Any]
        legacy["pet"] = nil
        let decoded = try JSONDecoder().decode(PlayerProfile.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.pet == nil)
        var sim = GameSimulation(seed: 1)
        let player = sim.spawnPlayer(profile: decoded)
        #expect(sim.playerStatus(player)?.pet.slot == nil)
    }
}
