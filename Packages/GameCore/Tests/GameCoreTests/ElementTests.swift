import Foundation
import Testing
@testable import GameCore

@Suite struct ElementTests {
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

    private func results(_ events: [WorldEvent]) -> [ElementForgeResult] {
        events.compactMap { if case let .elementForged(_, _, result) = $0 { result } else { nil } }
    }

    // MARK: - The wheel

    @Test func theWheelRunsFireWindEarthElectricWater() {
        #expect(Element.fire.strongAgainst == .wind)
        #expect(Element.wind.strongAgainst == .earth)
        #expect(Element.earth.strongAgainst == .electric)
        #expect(Element.electric.strongAgainst == .water)
        #expect(Element.water.strongAgainst == .fire)
        for element in Element.allCases {
            #expect(element.weakAgainst.strongAgainst == element)
            #expect(Element.allCases.filter { ElementMatchup($0, against: element) == .strong }.count == 1)
            #expect(Element(stone: element.stone) == element)
        }
        #expect(Element(stone: .amberShard) == nil)
    }

    @Test func strongHitsHarderAndWeakHitsSofter() {
        let water = ElementUpgrade(.water, level: 1)
        let fire = ElementForge.attackMultiplier(water, against: .fire)
        let neutral = ElementForge.attackMultiplier(water, against: .wind)
        let electric = ElementForge.attackMultiplier(water, against: .electric)
        #expect(fire > neutral && neutral > electric)
        #expect(ElementForge.attackMultiplier(nil, against: .fire) == 1)
        #expect(abs(ElementForge.attackMultiplier(ElementUpgrade(.water, level: 10), against: .fire) - 1.5) < 0.001)
        // Every level makes a strong weapon stronger.
        for level in 1..<ElementForge.maxLevel {
            #expect(ElementForge.attackMultiplier(ElementUpgrade(.water, level: level + 1), against: .fire)
                > ElementForge.attackMultiplier(ElementUpgrade(.water, level: level), against: .fire))
        }
        // Water armor shrugs off fire and suffers electricity.
        #expect(ElementForge.defenseMultiplier(water, against: .fire) < 1)
        #expect(ElementForge.defenseMultiplier(water, against: .electric) > 1)
        #expect(ElementForge.defenseMultiplier(nil, against: .electric) == 1)
    }

    @Test func weaponsShowTheirElementFromPlusThree() {
        #expect(ElementForge.effectStrength(level: 2) == 0)
        #expect(ElementForge.effectStrength(level: 3) > 0)
        #expect(ElementForge.effectStrength(level: 10) == 1)
    }

    // MARK: - Mobs

    @Test func everyMobDropsItsOwnElementsStone() {
        for kind in MobKind.allCases {
            #expect(kind.canDrop(kind.element.stone), "\(kind) drops its stone")
            let others = Element.allCases.filter { $0 != kind.element }
            #expect(!others.contains { kind.canDrop($0.stone) }, "\(kind) drops no other stone")
            #expect(kind.drops.first?.item != kind.element.stone, "the material stays first")
        }
    }

    @Test func aSproutMeetsEveryElementBeforeLevelTen() {
        let early = Set(MobKind.allCases.filter { $0.hasGiant && $0.stats.level < 10 }.map(\.element))
        #expect(early == Set(Element.allCases))
    }

    @Test func damageFollowsTheWheel() throws {
        var sim = GameSimulation(seed: 3)
        let player = sim.spawnPlayer(profile: PlayerProfile(equipment: [
            .weapon: Gear(.twigSword, element: ElementUpgrade(.electric, level: 5)),
            .body: Gear(.leafTunic, element: ElementUpgrade(.electric, level: 5)),
        ]))
        let hero = try #require(sim.entity(player))
        let snail = try #require(sim.entities.values.first { $0.kind == .mob(.snail) })     // water
        let pillBug = try #require(sim.entities.values.first { $0.kind == .mob(.pillBug) }) // earth
        #expect(GameSimulation.elementMultiplier(attacker: hero, target: snail) > 1, "electric beats water")
        #expect(GameSimulation.elementMultiplier(attacker: hero, target: pillBug) < 1, "earth grounds electric")
        #expect(GameSimulation.elementMultiplier(attacker: snail, target: hero) < 1, "electric armor shrugs off water")
        #expect(GameSimulation.elementMultiplier(attacker: pillBug, target: hero) > 1, "earth hits electric armor hard")
        #expect(sim.snapshot(for: player).entity(player)?.weaponElement == ElementUpgrade(.electric, level: 5))
    }

    // MARK: - The forge

    @Test func infusingAWeaponAtTheForge() throws {
        var bag = Inventory()
        bag.add(.fireStone, count: 3)
        bag.add(.waterStone, count: 1)
        bag.add(.amberShard, count: 1)
        bag.add(.acornCap, count: 1)
        var sim = GameSimulation(seed: 1)
        let player = sim.spawnPlayer(profile: PlayerProfile(caps: 2_000, inventory: bag,
                                                            equipment: [.weapon: Gear(.twigSword)]))
        sim.enqueue(.infuseElement(.equipped(.weapon), element: .fire, protect: false), from: player)
        #expect(run(&sim).contains(.actionFailed(player: player, reason: .tooFar)))

        let forge = try #require(sim.map.placement(of: .shiitake))
        sim.teleport(player, to: forge.position + Vec2(0, 1.2))
        sim.enqueue(.infuseElement(.equipped(.weapon), element: .fire, protect: false), from: player)
        #expect(results(run(&sim)) == [.succeeded(ElementUpgrade(.fire, level: 1))])
        var status = try #require(sim.playerStatus(player))
        #expect(status.equipment[.weapon] == Gear(.twigSword, element: ElementUpgrade(.fire, level: 1)))
        #expect(status.inventory.count(of: .fireStone) == 2)

        // A fire weapon only takes fire stones.
        sim.enqueue(.infuseElement(.equipped(.weapon), element: .water, protect: false), from: player)
        #expect(run(&sim).contains(.actionFailed(player: player, reason: .elementMismatch)))
        sim.enqueue(.infuseElement(.equipped(.weapon), element: .fire, protect: false), from: player)
        #expect(results(run(&sim)) == [.succeeded(ElementUpgrade(.fire, level: 2))])

        // Ordinary upgrades keep the element.
        sim.enqueue(.upgrade(.equipped(.weapon), protect: false), from: player)
        _ = run(&sim)
        status = try #require(sim.playerStatus(player))
        #expect(status.equipment[.weapon] == Gear(.twigSword, upgrade: 1, element: ElementUpgrade(.fire, level: 2)))
        #expect(sim.profile(of: player)?.equipment[.weapon]?.element == ElementUpgrade(.fire, level: 2), "elements are saved")

        // Hats don't take elements.
        sim.enqueue(.infuseElement(.bag(Gear(.acornCap)), element: .fire, protect: false), from: player)
        #expect(run(&sim).contains(.actionFailed(player: player, reason: .notUsable)))
    }

    @Test func failuresPastPlusThreeCostALevelUnlessWarded() throws {
        var bag = Inventory()
        bag.add(.windStone, count: 99)
        bag.add(.wardCharm, count: 20)
        for _ in 0..<10 { bag.add(Gear(.leafTunic, element: ElementUpgrade(.wind, level: 7)), count: 1) }
        var (sim, player) = try atTheForge(PlayerProfile(caps: 100_000, inventory: bag))
        for _ in 0..<10 {
            sim.enqueue(.infuseElement(.bag(Gear(.leafTunic, element: ElementUpgrade(.wind, level: 7))), element: .wind, protect: false),
                        from: player)
        }
        let unwarded = results(run(&sim))
        #expect(unwarded.count == 10)
        #expect(unwarded.allSatisfy { $0 == .succeeded(ElementUpgrade(.wind, level: 8)) || $0 == .downgraded(ElementUpgrade(.wind, level: 6)) })
        #expect(unwarded.contains(.downgraded(ElementUpgrade(.wind, level: 6))), "+8 fails most of the time")
        let status = try #require(sim.playerStatus(player))
        #expect(status.inventory.stacks.filter { $0.item == .leafTunic }.count == 10, "never destroyed")

        let sixes = status.inventory.count(of: Gear(.leafTunic, element: ElementUpgrade(.wind, level: 6)))
        for _ in 0..<sixes {
            sim.enqueue(.infuseElement(.bag(Gear(.leafTunic, element: ElementUpgrade(.wind, level: 6))), element: .wind, protect: true),
                        from: player)
        }
        let warded = results(run(&sim))
        #expect(!warded.contains { if case .downgraded = $0 { true } else { false } }, "a Ward Charm keeps the level")
    }

    @Test func removingAndConvertingElements() throws {
        var bag = Inventory()
        bag.add(.wardCharm, count: 3)
        let infused = Gear(.thornRapier, element: ElementUpgrade(.earth, level: 4))
        bag.add(infused, count: 1)
        bag.add(Gear(.leafTunic, element: ElementUpgrade(.water, level: 2)), count: 1)
        var (sim, player) = try atTheForge(PlayerProfile(caps: 10_000, inventory: bag))

        // +4 needs four charms; three won't do.
        sim.enqueue(.convertElement(.bag(infused), to: .fire), from: player)
        #expect(run(&sim).contains(.actionFailed(player: player, reason: .missingMaterials)))

        sim.enqueue(.convertElement(.bag(Gear(.leafTunic, element: ElementUpgrade(.water, level: 2))), to: .fire), from: player)
        #expect(results(run(&sim)) == [.converted(ElementUpgrade(.fire, level: 2))])
        var status = try #require(sim.playerStatus(player))
        #expect(status.inventory.count(of: Gear(.leafTunic, element: ElementUpgrade(.fire, level: 2))) == 1)
        #expect(status.inventory.count(of: .wardCharm) == 1)
        #expect(status.caps == 10_000 - ElementForge.conversionCaps(of: .leafTunic, level: 2))

        sim.enqueue(.removeElement(.bag(infused)), from: player)
        #expect(results(run(&sim)) == [.removed])
        status = try #require(sim.playerStatus(player))
        #expect(status.inventory.count(of: Gear(.thornRapier)) == 1)
        sim.enqueue(.removeElement(.bag(Gear(.thornRapier))), from: player)
        #expect(run(&sim).contains(.actionFailed(player: player, reason: .noElement)))
    }

    @Test func infusedGearKeepsItsElementThroughTheBagAndShops() throws {
        let infused = Gear(.twigSword, upgrade: 1, element: ElementUpgrade(.water, level: 3))
        var bag = Inventory()
        bag.add(infused, count: 1)
        bag.add(.twigSword, count: 1)
        #expect(bag.stacks.count == 2, "infused gear never stacks with plain gear")
        var (sim, player) = try atTheForge(PlayerProfile(caps: 0, inventory: bag))
        sim.enqueue(.equip(.twigSword, upgrade: 1, element: ElementUpgrade(.water, level: 3)), from: player)
        _ = run(&sim)
        #expect(sim.playerStatus(player)?.equipment[.weapon] == infused)
        sim.enqueue(.unequip(.weapon), from: player)
        _ = run(&sim)
        #expect(sim.playerStatus(player)?.inventory.count(of: infused) == 1)
        #expect(infused.sellPrice > Gear(.twigSword, upgrade: 1).sellPrice)
    }

    @Test func savesFromBeforeElementsStillLoad() throws {
        let legacy = #"{"item":"twigSword","upgrade":3}"#
        let gear = try JSONDecoder().decode(Gear.self, from: Data(legacy.utf8))
        #expect(gear == Gear(.twigSword, upgrade: 3))
        let stack = try JSONDecoder().decode(ItemStack.self, from: Data(#"{"item":"leafTunic","count":1,"upgrade":0}"#.utf8))
        #expect(stack.element == nil)

        let infused = Gear(.twigSword, upgrade: 3, element: ElementUpgrade(.fire, level: 7))
        #expect(try JSONDecoder().decode(Gear.self, from: JSONEncoder().encode(infused)) == infused)
    }
}
