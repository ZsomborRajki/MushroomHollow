import Foundation
import Testing
@testable import GameCore

@Suite struct GearTests {
    // MARK: - Helpers

    private func run(_ sim: inout GameSimulation, seconds: Float = 0.1) -> [WorldEvent] {
        var events: [WorldEvent] = []
        for _ in 0..<max(1, Int(seconds * Float(GameSimulation.tickRate))) { events += sim.step() }
        return events
    }

    /// A player standing at Shiitake's forge.
    private func atTheForge(_ profile: PlayerProfile, seed: UInt64 = 1) throws -> (GameSimulation, EntityID) {
        var sim = GameSimulation(seed: seed)
        let player = sim.spawnPlayer(profile: profile)
        let forge = try #require(sim.map.placement(of: .shiitake))
        sim.teleport(player, to: forge.position + Vec2(0, 1.2))
        return (sim, player)
    }

    private func results(_ events: [WorldEvent]) -> [UpgradeResult] {
        events.compactMap { if case let .upgradeAttempted(_, _, result) = $0 { result } else { nil } }
    }

    // MARK: - Upgrade numbers

    @Test func everyUpgradeLevelMakesGearStronger() {
        for item in ItemID.allCases where item.definition.isUpgradable {
            let slot = item.definition.equipSlot!
            var previous = Gear(item).bonus
            for level in 1...Upgrade.maxLevel {
                let bonus = Gear(item, upgrade: level).bonus
                if slot == .weapon {
                    #expect(bonus.attack > previous.attack, "\(item) +\(level)")
                } else {
                    #expect(bonus.defense > previous.defense || bonus.maxHP > previous.maxHP, "\(item) +\(level)")
                }
                previous = bonus
            }
        }
        #expect(Gear(.twigSword).bonus.attack == 4)
        #expect(Gear(.moonTalon, upgrade: 10).bonus.attack == 26 * 3, "+10 triples a weapon's attack")
    }

    @Test func upgradesGetRiskierAndPricier() {
        for level in 2...Upgrade.maxLevel {
            #expect(Upgrade.chance(toReach: level) < Upgrade.chance(toReach: level - 1))
            #expect(Upgrade.amberCost(toReach: level) >= Upgrade.amberCost(toReach: level - 1))
            #expect(Upgrade.capsCost(of: .twigSword, toReach: level) > Upgrade.capsCost(of: .twigSword, toReach: level - 1))
        }
        #expect(Upgrade.chance(toReach: 1) == 1)
        #expect(Upgrade.risk(toReach: 3) == .none)
        #expect(Upgrade.risk(toReach: 5) == .downgrade)
        #expect(Upgrade.risk(toReach: 6) == .destroy)
    }

    // MARK: - The blacksmith

    @Test func upgradingAtTheForge() throws {
        var bag = Inventory()
        bag.add(.amberShard, count: 3)
        bag.add(.mossBoots, count: 1)
        var sim = GameSimulation(seed: 1)
        let player = sim.spawnPlayer(profile: PlayerProfile(caps: 1_000, inventory: bag, equipment: [.weapon: Gear(.twigSword)]))
        let attack = try #require(sim.entity(player)).stats.attack

        sim.enqueue(.upgrade(.equipped(.weapon), protect: false), from: player)
        #expect(run(&sim).contains(.actionFailed(player: player, reason: .tooFar)))

        let forge = try #require(sim.map.placement(of: .shiitake))
        sim.teleport(player, to: forge.position + Vec2(0, 1.2))
        sim.enqueue(.upgrade(.equipped(.weapon), protect: false), from: player) // +1 always works
        var events = run(&sim)
        #expect(results(events) == [.succeeded(level: 1)])
        var status = try #require(sim.playerStatus(player))
        #expect(status.equipment[.weapon] == Gear(.twigSword, upgrade: 1))
        #expect(status.stats.attack == attack + 1)
        #expect(status.caps == 1_000 - Upgrade.capsCost(of: .twigSword, toReach: 1))
        #expect(status.inventory.count(of: .amberShard) == 2)
        #expect(sim.profile(of: player)?.equipment[.weapon]?.upgrade == 1, "upgrades are saved")

        sim.enqueue(.upgrade(.bag(Gear(.mossBoots)), protect: false), from: player)
        events = run(&sim)
        #expect(results(events) == [.succeeded(level: 1)])
        status = try #require(sim.playerStatus(player))
        #expect(status.inventory.count(of: .mossBoots, upgrade: 1) == 1)
        #expect(status.inventory.count(of: .mossBoots, upgrade: 0) == 0)

        // Equip the +1 boots straight from the bag.
        sim.enqueue(.equip(.mossBoots, upgrade: 1), from: player)
        _ = run(&sim)
        #expect(sim.playerStatus(player)?.equipment[.boots] == Gear(.mossBoots, upgrade: 1))

        // One shard left, but the next weapon upgrade needs one: fine. After that, none.
        sim.enqueue(.upgrade(.equipped(.weapon), protect: false), from: player)
        sim.enqueue(.upgrade(.equipped(.weapon), protect: false), from: player)
        events = run(&sim)
        #expect(events.contains(.actionFailed(player: player, reason: .missingMaterials)))
    }

    @Test func noUpgradeWithoutAmberOrPastPlusTen() throws {
        var bag = Inventory()
        bag.add(.amberShard, count: 50)
        var (sim, player) = try atTheForge(PlayerProfile(caps: 100_000, inventory: bag,
                                                         equipment: [.weapon: Gear(.twigSword, upgrade: 10)]))
        sim.enqueue(.upgrade(.equipped(.weapon), protect: false), from: player)
        #expect(run(&sim).contains(.actionFailed(player: player, reason: .maxUpgrade)))
        sim.enqueue(.upgrade(.bag(Gear(.amberShard)), protect: false), from: player)
        #expect(run(&sim).contains(.actionFailed(player: player, reason: .notUsable)))

        (sim, player) = try atTheForge(PlayerProfile(caps: 100_000, equipment: [.weapon: Gear(.twigSword)]))
        sim.enqueue(.upgrade(.equipped(.weapon), protect: false), from: player)
        #expect(run(&sim).contains(.actionFailed(player: player, reason: .missingMaterials)))
    }

    @Test func failuresPastPlusFiveDestroyTheItem() throws {
        var bag = Inventory()
        for _ in 0..<10 { bag.add(.twigSword, count: 1, upgrade: 5) }
        bag.add(.amberShard, count: 99)
        var (sim, player) = try atTheForge(PlayerProfile(caps: 100_000, inventory: bag))
        for _ in 0..<10 { sim.enqueue(.upgrade(.bag(Gear(.twigSword, upgrade: 5)), protect: false), from: player) }
        let outcomes = results(run(&sim))
        #expect(outcomes.count == 10)
        let destroyed = outcomes.count { $0 == .destroyed }
        let succeeded = outcomes.count { $0 == .succeeded(level: 6) }
        #expect(destroyed + succeeded == 10)
        #expect(destroyed > 0, "a 35% shot fails most of the time")
        let status = try #require(sim.playerStatus(player))
        #expect(status.inventory.count(of: .twigSword) == succeeded)
        #expect(status.inventory.count(of: .twigSword, upgrade: 6) == succeeded)
    }

    @Test func failuresAtPlusFourAndFiveCostALevel() throws {
        var bag = Inventory()
        for _ in 0..<10 { bag.add(.acornCap, count: 1, upgrade: 4) }
        bag.add(.amberShard, count: 99)
        var (sim, player) = try atTheForge(PlayerProfile(caps: 100_000, inventory: bag))
        for _ in 0..<10 { sim.enqueue(.upgrade(.bag(Gear(.acornCap, upgrade: 4)), protect: false), from: player) }
        let outcomes = results(run(&sim))
        #expect(outcomes.allSatisfy { $0 == .succeeded(level: 5) || $0 == .downgraded(level: 3) })
        #expect(outcomes.contains(.downgraded(level: 3)))
        #expect(sim.playerStatus(player)?.inventory.count(of: .acornCap) == 10, "nothing destroyed")
    }

    @Test func aWardCharmSavesTheItem() throws {
        var bag = Inventory()
        for _ in 0..<10 { bag.add(.twigSword, count: 1, upgrade: 7) }
        bag.add(.amberShard, count: 99)
        bag.add(.wardCharm, count: 10)
        var (sim, player) = try atTheForge(PlayerProfile(caps: 100_000, inventory: bag))
        for _ in 0..<10 { sim.enqueue(.upgrade(.bag(Gear(.twigSword, upgrade: 7)), protect: true), from: player) }
        let outcomes = results(run(&sim))
        #expect(!outcomes.contains(.destroyed))
        #expect(outcomes.contains(.protected(level: 7)))
        let status = try #require(sim.playerStatus(player))
        #expect(status.inventory.count(of: .twigSword) == 10)
        #expect(status.inventory.count(of: .wardCharm) == 0, "one charm per risky attempt")
    }

    @Test func safeUpgradesDontSpendCharms() throws {
        var bag = Inventory()
        bag.add(.amberShard, count: 5)
        bag.add(.wardCharm, count: 1)
        var (sim, player) = try atTheForge(PlayerProfile(caps: 10_000, inventory: bag, equipment: [.weapon: Gear(.twigSword)]))
        sim.enqueue(.upgrade(.equipped(.weapon), protect: true), from: player)
        _ = run(&sim)
        #expect(sim.playerStatus(player)?.inventory.count(of: .wardCharm) == 1)
    }

    @Test func upgradedGearSellsForMore() throws {
        var bag = Inventory()
        bag.add(.twigSword, count: 1, upgrade: 4)
        var sim = GameSimulation(seed: 1)
        let player = sim.spawnPlayer(profile: PlayerProfile(inventory: bag))
        let shop = try #require(sim.map.placement(of: .chanterelle))
        sim.teleport(player, to: shop.position + Vec2(0, 1.2))
        sim.enqueue(.sell(.twigSword, count: 1, to: .chanterelle), from: player)
        #expect(run(&sim).contains(.actionFailed(player: player, reason: .missingItem)), "there's no +0 one")
        sim.enqueue(.sell(.twigSword, count: 1, upgrade: 4, to: .chanterelle), from: player)
        _ = run(&sim)
        #expect(sim.playerStatus(player)?.caps == ItemID.twigSword.definition.sellPrice * 3)
    }

    // MARK: - Sets

    @Test func setBonusesGrowWithEachPiece() throws {
        let pieces = ItemSet.dewleaf.definition.pieces
        var bag = Inventory()
        for piece in pieces { bag.add(piece, count: 1) }
        var sim = GameSimulation(seed: 1)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 8, inventory: bag))
        let bare = try #require(sim.entity(player)).stats

        var gearOnly = StatBonus()
        var previousTotal = bare.maxHP + bare.attack + bare.defense
        for (index, piece) in pieces.enumerated() {
            sim.enqueue(.equip(piece), from: player)
            _ = run(&sim)
            gearOnly = gearOnly + piece.definition.bonus
            let stats = try #require(sim.entity(player)).stats
            let setBonus = ItemSet.dewleaf.definition.bonus(worn: index + 1)
            #expect(stats.maxHP == bare.maxHP + gearOnly.maxHP + setBonus.maxHP)
            #expect(stats.attack == bare.attack + gearOnly.attack + setBonus.attack)
            #expect(stats.maxHP + stats.attack + stats.defense > previousTotal)
            previousTotal = stats.maxHP + stats.attack + stats.defense
        }
        let full = try #require(sim.entity(player)).stats
        #expect(full.attackInterval < bare.attackInterval, "the full set attacks faster")
        #expect(full.critChance > bare.critChance)
        #expect(ItemSet.dewleaf.definition.bonus(worn: 1) == StatBonus())

        sim.enqueue(.unequip(.gloves), from: player)
        _ = run(&sim)
        let three = try #require(sim.entity(player)).stats
        #expect(three.attackInterval == bare.attackInterval, "three pieces lose the full-set bonus")
    }

    @Test func classSetsNeedTheirClassAndLevel() throws {
        var bag = Inventory()
        bag.add(.briarHood, count: 1)
        bag.add(.dewleafCap, count: 1)
        var sim = GameSimulation(seed: 1)
        let guardian = sim.spawnPlayer(profile: PlayerProfile(level: 16, inventory: bag, playerClass: .guardian))
        let sprout = sim.spawnPlayer(profile: PlayerProfile(level: 4, inventory: bag))
        sim.enqueue(.equip(.briarHood), from: guardian)
        sim.enqueue(.equip(.dewleafCap), from: sprout)
        let events = run(&sim)
        #expect(events.contains(.actionFailed(player: guardian, reason: .wrongClass)))
        #expect(events.contains(.actionFailed(player: sprout, reason: .levelTooLow)), "Dewleaf is a level 5 set")
    }

    @Test func everySetHasFourPiecesOneForEachArmorSlot() {
        for set in ItemSet.allCases {
            let pieces = set.definition.pieces
            #expect(pieces.count == 4)
            #expect(Set(pieces.compactMap(\.definition.equipSlot)) == [.hat, .body, .gloves, .boots])
            #expect(pieces.allSatisfy { $0.definition.set == set && $0.definition.rarity == .set && $0.definition.buyPrice == nil })
        }
        for job in PlayerClass.allCases {
            #expect(ItemSet.forClass(job) != nil, "\(job) has a set")
        }
    }

    // MARK: - Drops

    @Test func theDewleafSetIsSpreadAcrossTheZones() {
        func source(of piece: ItemID) -> [MobKind] {
            MobKind.allCases.filter { kind in kind.drops.contains { $0.item == piece } }
        }
        #expect(source(of: .dewleafSlippers) == [.snail]) // level 1–4
        #expect(source(of: .dewleafCap) == [.slug]) // 4–7
        #expect(source(of: .dewleafGloves) == [.beetle]) // 7–10
        #expect(source(of: .dewleafVest) == [.sporeBeast]) // 10–15
        for kind in MobKind.allCases {
            for drop in kind.drops where drop.item.definition.rarity == .set {
                #expect(drop.chance <= 0.01, "set pieces are very rare")
            }
        }
    }

    @Test func upgradeStonesOnlyComeFromMobs() {
        for npc in NPCID.allCases {
            #expect(!npc.definition.shopStock.contains(.amberShard))
            #expect(!npc.definition.shopStock.contains(.wardCharm))
        }
        let droppers = [MobKind.snail, .slug, .beetle, .sporeBeast, .owl]
        #expect(droppers.allSatisfy { kind in kind.drops.contains { $0.item == .amberShard } })
    }

    @Test func classSetPiecesDropForTheKillersClass() throws {
        var sim = GameSimulation(seed: 9)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 16, playerClass: .thornshot))
        let hero = try #require(sim.entities[player])
        for _ in 0..<40 {
            sim.rollLoot(for: .owl, ownedBy: hero, at: hero.position.xz)
        }
        let received = sim.drops.compactMap { drop -> ItemID? in
            if case let .item(item, _) = drop.kind, item.definition.rarity == .set, drop.owner == player { item } else { nil }
        }
        #expect(!received.isEmpty)
        #expect(received.allSatisfy { $0.definition.set == .briar })

        // A classless sprout never gets class set pieces.
        let sprout = sim.spawnPlayer(profile: PlayerProfile(level: 14))
        let kid = try #require(sim.entities[sprout])
        for _ in 0..<40 {
            sim.rollLoot(for: .owl, ownedBy: kid, at: kid.position.xz)
        }
        #expect(!sim.drops.contains {
            if case let .item(item, _) = $0.kind, $0.owner == sprout { item.definition.rarity == .set } else { false }
        })
    }

    // MARK: - Saves

    @Test func savesFromBeforeUpgradesStillLoad() throws {
        let legacy = """
        {"level": 7, "xp": 12, "caps": 50,
         "inventory": {"stacks": [{"item": "dewPotion", "count": 3}, {"item": "barkMail", "count": 1}]},
         "equipment": ["weapon", "thornRapier", "boots", "mossBoots"],
         "activeQuests": [], "completedQuests": ["shellShock"]}
        """
        let profile = try JSONDecoder().decode(PlayerProfile.self, from: Data(legacy.utf8))
        #expect(profile.equipment[.weapon] == Gear(.thornRapier))
        #expect(profile.equipment[.boots] == Gear(.mossBoots))
        #expect(profile.inventory.count(of: .barkMail, upgrade: 0) == 1)

        var upgraded = profile
        upgraded.equipment[.weapon]?.upgrade = 6
        let decoded = try JSONDecoder().decode(PlayerProfile.self, from: JSONEncoder().encode(upgraded))
        #expect(decoded.equipment[.weapon] == Gear(.thornRapier, upgrade: 6))
    }
}
