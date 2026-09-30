import Foundation
import Testing
@testable import GameCore

/// The cliffs, the brook, the Sunken Warren and its king, the job-change trial, and sitting down to rest.
@Suite struct WarrenTests {
    private let map = WorldMap.mushroomHollow

    private func run(_ sim: inout GameSimulation, seconds: Float, each: ((inout GameSimulation) -> Void)? = nil) -> [WorldEvent] {
        var events: [WorldEvent] = []
        for _ in 0..<Int(seconds * Float(GameSimulation.tickRate)) {
            each?(&sim)
            events += sim.step()
        }
        return events
    }

    /// Walks `player` toward `target` for a while and returns where it ended up.
    private func walk(_ player: EntityID, toward target: Vec2, seconds: Float, in sim: inout GameSimulation) throws -> Vec2 {
        _ = run(&sim, seconds: seconds) { sim in
            guard let here = sim.entity(player)?.position.xz else { return }
            sim.enqueue(.move((target - here).clampedLength(1)), from: player)
        }
        return try #require(sim.entity(player)).position.xz
    }

    /// A world with no mobs in it, for walking about undisturbed.
    private func emptyWorld() -> GameSimulation {
        var sim = GameSimulation(seed: 1)
        for id in sim.order where sim.entities[id]?.kind.isMob == true { sim.removeEntity(id) }
        return sim
    }

    private func plateau(_ name: String) throws -> Plateau {
        try #require(map.terrain.plateaus.first { $0.name == name })
    }

    // MARK: - Cliffs

    @Test func mesasStandTallAndAreClimbedByTheirRamp() throws {
        for name in ["Barkfall Bluff", "Sunstone Mesa"] {
            let mesa = try plateau(name)
            let ramp = try #require(mesa.ramps.first)
            let down = AngleMath.direction(forYaw: ramp.yaw)
            let behind = mesa.center - down * (mesa.radius * 1.12 + mesa.cliffWidth + 4)
            #expect(map.groundHeight(at: mesa.center) > map.groundHeight(at: behind) + mesa.height - 2, "\(name) stands tall")

            var sim = emptyWorld()
            let player = sim.spawnPlayer()
            sim.teleport(player, to: behind)
            let blocked = try walk(player, toward: mesa.center, seconds: 8, in: &sim)
            #expect(blocked.distance(to: mesa.center) > mesa.radius * 0.88, "\(name)'s cliff is in the way")

            sim.teleport(player, to: mesa.center + down * (mesa.radius + ramp.length + 2))
            let top = try walk(player, toward: mesa.center, seconds: 10, in: &sim)
            #expect(top.distance(to: mesa.center) < mesa.radius * 0.5, "\(name)'s ramp leads to the top")
        }
    }

    @Test func theWarrenIsASunkenBasinWithOneWayDown() throws {
        let warren = try plateau("The Sunken Warren")
        #expect(warren.isBasin)
        let ramp = try #require(warren.ramps.first)
        let up = AngleMath.direction(forYaw: ramp.yaw)
        let top = warren.center + up * (warren.radius + ramp.length + 2)
        #expect(map.groundHeight(at: warren.center) < map.groundHeight(at: top) - 5)
        #expect(map.zone(at: warren.center)?.name == "The Sunken Warren")

        var sim = emptyWorld()
        let player = sim.spawnPlayer()
        // Off the cliff edge on the far side: you can't just jump in.
        sim.teleport(player, to: warren.center - up * (warren.radius * 1.12 + warren.cliffWidth + 3))
        let rim = try walk(player, toward: warren.center, seconds: 8, in: &sim)
        #expect(rim.distance(to: warren.center) > warren.radius * 0.88)
        // Down the ramp is fine.
        sim.teleport(player, to: top)
        let floor = try walk(player, toward: warren.center, seconds: 12, in: &sim)
        #expect(floor.distance(to: warren.center) < 3)
    }

    // MARK: - The brook

    @Test func theBrookIsFordedWhereTheRoadCrosses() throws {
        let lake = try #require(map.terrain.lakes.first { $0.name == "Dewdrop Lake" })
        let ford = try #require(lake.fords.first)
        #expect(lake.signedDistance(to: ford) < 0, "the ford is in the water")
        #expect(!map.isOverDeepWater(ford), "but shallow")
        let spring = try #require(map.landmark(.silverthreadSpring))
        #expect(lake.signedDistance(to: spring.position) < Lake.shoreWidth + 3, "the spring feeds the brook")

        func onRing(_ degrees: Float, _ radius: Float) -> Vec2 { AngleMath.direction(forYaw: degrees * .pi / 180) * radius }
        var sim = emptyWorld()
        let player = sim.spawnPlayer()
        // Along the ring road: straight through the ford.
        sim.teleport(player, to: onRing(-20, 190))
        var wet = false
        for _ in 0..<(GameSimulation.tickRate * 8) {
            guard let here = sim.entity(player)?.position.xz else { break }
            if lake.signedDistance(to: here) < 0 { wet = true }
            sim.enqueue(.move((onRing(-29, 190) - here).clampedLength(1)), from: player)
            sim.step()
        }
        #expect(wet, "wades through the water")
        #expect(try #require(sim.entity(player)).position.xz.distance(to: onRing(-29, 190)) < 1.5, "and out the other side")

        // Upstream the brook runs too deep to wade.
        sim.teleport(player, to: onRing(-21, 215))
        let stuck = try walk(player, toward: onRing(-31, 215), seconds: 8, in: &sim)
        #expect(stuck.distance(to: onRing(-31, 215)) > 4)
    }

    // MARK: - The Sunken Warren

    @Test func theWarrenIsMeanerThanTheFields() throws {
        let sim = GameSimulation(seed: 3)
        for (index, area) in sim.map.mobSpawns.enumerated() where area.kind == .delverMole || area.kind == .rootcrawler {
            let aggressive = sim.order.filter { id in
                guard let brain = sim.entities[id]?.brain else { return false }
                return brain.spawnArea == index && brain.aggressive && !brain.isGiant
            }
            #expect(aggressive.count == area.count / 2, "half the \(area.kind.pluralName) bite first")
        }
        let kings = sim.bosses.filter { sim.entity($0)?.kind == .mob(.moldywarp) }
        #expect(kings.count == 1, "one king, and no Giant of it")
        #expect(sim.bosses.allSatisfy { sim.entity($0)?.brain?.isGiant == false })
    }

    /// The king, all alone, with a sturdy level-30 hero standing in front of it.
    private func lair() throws -> (GameSimulation, king: EntityID, hero: EntityID) {
        var sim = GameSimulation(seed: 5)
        for id in sim.order {
            guard let e = sim.entities[id], e.kind.isMob, e.kind != .mob(.moldywarp) else { continue }
            sim.removeEntity(id)
        }
        let king = try #require(sim.bosses.first)
        let kingSpot = try #require(sim.entity(king)).position.xz
        let warren = try plateau("The Sunken Warren")
        let hero = sim.spawnPlayer(profile: PlayerProfile(level: 30, playerClass: .guardian))
        sim.teleport(hero, to: kingSpot + (warren.center - kingSpot).normalizedOrZero * 4.5)
        return (sim, king, hero)
    }

    @Test func moldywarpTunnelsUnderYouAndCantBeHurtBelow() throws {
        var (sim, king, hero) = try lair()
        sim.enqueue(.target(king, engage: true), from: hero)
        var dug = false, hitsBelow = 0, sawMarker = false
        var erupted: [WorldEvent]?
        for _ in 0..<(GameSimulation.tickRate * 20) {
            let events = sim.step()
            if events.contains(.mobAbility(entity: king, ability: .burrow)) { dug = true }
            if sim.entity(king)?.pose == .burrowed {
                hitsBelow += events.count { if case .damage(hero, king, _, _, _) = $0 { true } else { false } }
                if !sim.snapshot().telegraphs.isEmpty { sawMarker = true }
            }
            if events.contains(.mobAbility(entity: king, ability: .erupt)) {
                erupted = events
                break
            }
        }
        #expect(dug)
        #expect(sawMarker, "the ground is marked where it will burst up")
        #expect(hitsBelow == 0, "nothing reaches it underground")
        let burst = try #require(erupted)
        #expect(burst.contains { if case .damage(king, hero, _, _, _) = $0 { true } else { false } }, "standing on the mark hurts")
        #expect(burst.contains(.knockedBack(entity: hero)))
    }

    @Test func steppingOffTheMarkDodgesTheEruption() throws {
        var (sim, king, hero) = try lair()
        let warren = try plateau("The Sunken Warren")
        sim.enqueue(.target(king, engage: true), from: hero)
        var dodging = false
        for _ in 0..<(GameSimulation.tickRate * 20) {
            if dodging, let here = sim.entity(hero)?.position.xz {
                sim.enqueue(.move((warren.center - here).clampedLength(1)), from: hero)
            }
            let events = sim.step()
            if events.contains(.mobAbility(entity: king, ability: .burrow)) { dodging = true }
            if events.contains(.mobAbility(entity: king, ability: .erupt)) {
                #expect(!events.contains { if case .damage(king, hero, _, _, _) = $0 { true } else { false } })
                return
            }
        }
        Issue.record("Moldywarp never erupted")
    }

    @Test func moldywarpCallsItsMolesAndEnrages() throws {
        var (sim, king, hero) = try lair()
        sim.enqueue(.target(king, engage: true), from: hero)
        _ = run(&sim, seconds: 1)
        let maxHP = try #require(sim.entity(king)).stats.maxHP
        sim.entities[king]?.stats.hp = Int(Float(maxHP) * 0.55)
        let first = run(&sim, seconds: 1)
        #expect(first.contains(.mobAbility(entity: king, ability: .summon)))
        let moles = sim.snapshot().entities.filter { $0.kind == .mob(.delverMole) }
        #expect(moles.count == 2)
        #expect(moles.allSatisfy { $0.target == hero })

        sim.entities[king]?.stats.hp = Int(Float(maxHP) * 0.25)
        let second = run(&sim, seconds: 1)
        #expect(second.contains(.mobAbility(entity: king, ability: .enrage)))
    }

    @Test func slainKingPaysOutAndIsAFieldBoss() throws {
        var (sim, king, hero) = try lair()
        sim.entities[king]?.stats.hp = 1
        sim.enqueue(.target(king, engage: true), from: hero)
        let events = run(&sim, seconds: 3)
        #expect(events.contains { if case .fieldBossDefeated(king, .moldywarp, _) = $0 { true } else { false } })
        #expect(!events.contains { if case .worldBossDefeated = $0 { true } else { false } })
        #expect(sim.snapshot(for: hero).drops.contains { if case let .item(.velvetPelt, count) = $0.kind { count >= 3 } else { false } })
    }

    // MARK: - The trial

    @Test func theTrialWantsARealGiant() throws {
        var sim = GameSimulation(seed: 2)
        let hero = sim.spawnPlayer(profile: PlayerProfile(level: 15))
        let elder = try #require(sim.map.placement(of: .elderMorel))
        sim.teleport(hero, to: elder.position + Vec2(0, 1.2))
        sim.enqueue(.acceptQuest(.trialOfThePath), from: hero)
        _ = run(&sim, seconds: 0.1)

        func kill(_ kind: MobKind, giant: Bool) {
            var entity = sim.entities[hero]!
            sim.recordKill(of: kind, giant: giant, by: &entity)
            sim.entities[hero] = entity
        }
        kill(.snail, giant: true)
        kill(.bogFrog, giant: false)
        #expect(sim.playerStatus(hero)?.quests.first { $0.id == .trialOfThePath }?.state == .active(progress: 0, goal: 1),
                "a snail Giant and a plain frog don't count")
        kill(.bogFrog, giant: true)
        #expect(sim.playerStatus(hero)?.quests.first { $0.id == .trialOfThePath }?.state == .readyToTurnIn)

        sim.enqueue(.completeQuest(.trialOfThePath), from: hero)
        sim.enqueue(.chooseClass(.dewkeeper), from: hero)
        let events = run(&sim, seconds: 0.1)
        #expect(events.contains(.classChosen(player: hero, playerClass: .dewkeeper)))
    }

    @Test func theTrialIsHiddenFromThoseWhoChoseLongAgo() {
        var sim = GameSimulation(seed: 2)
        let old = sim.spawnPlayer(profile: PlayerProfile(level: 20, playerClass: .thornshot))
        #expect(sim.playerStatus(old)?.quests.first { $0.id == .trialOfThePath }?.state == .hidden)
    }

    // MARK: - Quick potions

    @Test func quickSlotsDrinkTheRightSizedPotion() throws {
        var bag = Inventory()
        bag.add(.dewPotion, count: 3)
        bag.add(.sapTonic, count: 3)
        bag.add(.honeydewDraught, count: 3)
        var sim = GameSimulation(seed: 1)
        let hero = sim.spawnPlayer(profile: PlayerProfile(level: 25, hp: 1, inventory: bag))
        let maxHP = try #require(sim.entity(hero)).stats.maxHP
        func pick(hp: Int) throws -> ItemID? {
            sim.entities[hero]?.stats.hp = hp
            return try #require(sim.playerStatus(hero)).quickPotion(restoresMP: false)
        }
        #expect(try pick(hp: maxHP - 30) == .dewPotion, "a scratch gets the small one")
        #expect(try pick(hp: maxHP - 150) == .sapTonic)
        #expect(try pick(hp: 1) == .honeydewDraught, "nothing tops it up: the strongest")
        #expect(try #require(sim.playerStatus(hero)).quickPotion(restoresMP: true) == nil, "no MP potions in the bag")
    }

    // MARK: - Sitting

    @Test func sittingRestsFasterUntilYouMoveOrGetHit() throws {
        var sim = emptyWorld()
        let sitter = sim.spawnPlayer(profile: PlayerProfile(level: 10, hp: 10))
        let stander = sim.spawnPlayer(profile: PlayerProfile(level: 10, hp: 10))
        sim.teleport(stander, to: sim.map.playerSpawn + Vec2(3, 0))
        sim.enqueue(.toggleSit, from: sitter)
        _ = run(&sim, seconds: 3)
        let sat = try #require(sim.entity(sitter)), stood = try #require(sim.entity(stander))
        #expect(sat.pose == .sitting)
        #expect(sat.stats.hp - 10 > (stood.stats.hp - 10) * 2, "sitting recovers much faster")

        sim.enqueue(.move(Vec2(1, 0)), from: sitter)
        _ = sim.step()
        #expect(sim.entity(sitter)?.pose == .normal, "moving stands you up")

        sim.enqueue(.move(.zero), from: sitter)
        sim.enqueue(.toggleSit, from: sitter)
        _ = sim.step()
        #expect(sim.entity(sitter)?.pose == .sitting)
        var bully = sim.entities[stander]!
        sim.dealDamage(from: &bully, to: sitter, multiplier: 1, skill: nil)
        #expect(sim.entity(sitter)?.pose == .normal, "a hit knocks you back to your feet")
    }
}
