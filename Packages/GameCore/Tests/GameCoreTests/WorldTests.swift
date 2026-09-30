import Foundation
import Testing
@testable import GameCore

@Suite struct WorldTests {
    private func run(_ sim: inout GameSimulation, seconds: Float, each: ((inout GameSimulation) -> Void)? = nil) -> [WorldEvent] {
        var events: [WorldEvent] = []
        for _ in 0..<Int(seconds * Float(GameSimulation.tickRate)) {
            each?(&sim)
            events += sim.step()
        }
        return events
    }

    private func standNear(_ npc: NPCID, _ player: EntityID, in sim: inout GameSimulation) throws {
        let placement = try #require(sim.map.placement(of: npc))
        sim.teleport(player, to: placement.position + Vec2(0, 1.2))
    }

    private func glider() -> Inventory {
        var bag = Inventory()
        bag.add(.dandelionSeed, count: 1)
        return bag
    }

    // MARK: - World

    @Test func mobsDoNotStack() throws {
        var sim = GameSimulation(seed: 2)
        let snails = sim.snapshot().entities.filter { $0.kind == .mob(.snail) }.prefix(3)
        let spot = try #require(snails.first).position.xz
        for snail in snails { sim.teleport(snail.id, to: spot) }
        _ = run(&sim, seconds: 1)

        let positions = snails.compactMap { sim.entity($0.id)?.position.xz }
        for i in positions.indices {
            for j in positions.indices where j > i {
                #expect(positions[i].distance(to: positions[j]) > MobKind.snail.radius)
            }
        }
    }

    @Test func dayTurnsToNight() {
        var sim = GameSimulation(seed: 1, startTimeOfDay: 0.7)
        #expect(!sim.isNight)
        let ticksToNight = Int(Double(GameSimulation.dayLengthTicks) * 0.15)
        for _ in 0..<ticksToNight { sim.step() }
        #expect(sim.isNight)
        #expect(abs(sim.snapshot().timeOfDay - 0.85) < 0.01)
    }

    // MARK: - Classes

    @Test func choosingAClassNeedsLevel15AndTheElder() throws {
        var sim = GameSimulation(seed: 1)
        let rookie = sim.spawnPlayer(profile: PlayerProfile(level: 14))
        try standNear(.elderMorel, rookie, in: &sim)
        sim.enqueue(.chooseClass(.guardian), from: rookie)
        #expect(run(&sim, seconds: 0.1).contains(.actionFailed(player: rookie, reason: .levelTooLow)))

        let untested = sim.spawnPlayer(profile: PlayerProfile(level: 15))
        try standNear(.elderMorel, untested, in: &sim)
        sim.enqueue(.chooseClass(.guardian), from: untested)
        #expect(run(&sim, seconds: 0.1).contains(.actionFailed(player: untested, reason: .trialFirst)), "the trial comes first")

        let veteran = sim.spawnPlayer(profile: PlayerProfile(level: 15, completedQuests: [.trialOfThePath]))
        sim.enqueue(.chooseClass(.guardian), from: veteran)
        #expect(run(&sim, seconds: 0.1).contains(.actionFailed(player: veteran, reason: .tooFar)))

        try standNear(.elderMorel, veteran, in: &sim)
        let before = try #require(sim.entity(veteran)).stats
        sim.enqueue(.chooseClass(.guardian), from: veteran)
        sim.enqueue(.chooseClass(.thornshot), from: veteran) // only once
        let events = run(&sim, seconds: 0.1)
        #expect(events.contains(.classChosen(player: veteran, playerClass: .guardian)))
        #expect(events.contains(.actionFailed(player: veteran, reason: .notAvailable)))

        let status = try #require(sim.playerStatus(veteran))
        #expect(status.playerClass == .guardian)
        #expect(status.stats.maxHP > before.maxHP)
        #expect(status.stats.defense > before.defense)
        #expect(status.skills.map(\.id) == SkillID.baseSkills + [.barkSkin, .capSlam])
    }

    @Test func classSkillsNeedTheClass() throws {
        var sim = GameSimulation(seed: 1)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 20))
        sim.enqueue(.useSkill(.barkSkin), from: player)
        #expect(run(&sim, seconds: 0.1).contains(.skillFailed(caster: player, skill: .barkSkin, reason: .locked)))
    }

    @Test func thornshotFightsFromRange() throws {
        var sim = GameSimulation(seed: 4)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 15, playerClass: .thornshot))
        let snail = try #require(sim.snapshot().entities.first { $0.kind == .mob(.snail) })
        sim.teleport(player, to: snail.position.xz + Vec2(6, 0))
        let start = try #require(sim.entity(player)).position.xz
        sim.enqueue(.target(snail.id, engage: true), from: player)
        let events = run(&sim, seconds: 1.5)

        #expect(events.contains { if case .damage(player, snail.id, _, _, _) = $0 { true } else { false } })
        let moved = try #require(sim.entity(player)).position.xz.distance(to: start)
        #expect(moved < 0.5, "shoots without walking up")
    }

    @Test func volleyHitsSeveralMobs() throws {
        var sim = GameSimulation(seed: 6)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 15, playerClass: .thornshot))
        let snails = Array(sim.snapshot().entities.filter { $0.kind == .mob(.snail) }.prefix(3))
        let center = snails[0].position.xz
        sim.teleport(snails[1].id, to: center + Vec2(1.5, 0))
        sim.teleport(snails[2].id, to: center + Vec2(-1.5, 0))
        sim.teleport(player, to: center + Vec2(0, 6))
        sim.enqueue(.target(snails[0].id, engage: false), from: player)
        sim.enqueue(.useSkill(.thornVolley), from: player)
        let events = run(&sim, seconds: 0.5)

        let hit = Set(events.compactMap { event -> EntityID? in
            if case let .damage(player, target, _, _, .thornVolley) = event { return target } else { return nil }
        })
        #expect(hit.count == 3)
    }

    @Test func barkSkinReducesDamageTaken() throws {
        func damageTaken(buffed: Bool) throws -> Int {
            var sim = GameSimulation(seed: 9)
            let player = sim.spawnPlayer(profile: PlayerProfile(level: 15, playerClass: .guardian))
            // Hits hard enough that defense matters (slugs already bottom out at 1 damage).
            let beast = try #require(sim.snapshot().entities.first { $0.kind == .mob(.sporeBeast) })
            sim.teleport(player, to: beast.position.xz + Vec2(1.5, 0))
            if buffed { sim.enqueue(.useSkill(.barkSkin), from: player) }
            return run(&sim, seconds: 8).reduce(0) { total, event in
                if case let .damage(_, target, amount, _, _) = event, target == player { total + amount } else { total }
            }
        }
        let buffed = try damageTaken(buffed: true)
        let unbuffed = try damageTaken(buffed: false)
        #expect(buffed < unbuffed, "buffed \(buffed) vs \(unbuffed)")
    }

    @Test func morningDewHealsOverTime() throws {
        var sim = GameSimulation(seed: 1)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 15, playerClass: .dewkeeper))
        sim.entities[player]?.stats.hp = 20
        sim.entities[player]?.combat.lastCombatTick = 1
        sim.enqueue(.useSkill(.morningDew), from: player)
        _ = run(&sim, seconds: 0.1)
        #expect(sim.playerStatus(player)?.buffs.first?.skill == .morningDew)
        sim.entities[player]?.combat.lastCombatTick = sim.tick // stay "in combat": no passive regen boost
        _ = run(&sim, seconds: 3) { $0.entities[player]?.combat.lastCombatTick = $0.tick }
        #expect(try #require(sim.entity(player)).stats.hp > 20 + Int(Float(try #require(sim.entity(player)).stats.maxHP) * 0.1))
    }

    // MARK: - Flight

    @Test func flightNeedsTheSeedAndLevel10() throws {
        var sim = GameSimulation(seed: 1)
        let grounded = sim.spawnPlayer(profile: PlayerProfile(level: 12))
        let tooYoung = sim.spawnPlayer(profile: PlayerProfile(level: 9, inventory: glider()))
        sim.enqueue(.toggleFlight, from: grounded)
        sim.enqueue(.toggleFlight, from: tooYoung)
        let events = run(&sim, seconds: 0.1)
        #expect(events.contains(.actionFailed(player: grounded, reason: .missingItem)))
        #expect(events.contains(.actionFailed(player: tooYoung, reason: .levelTooLow)))
    }

    @Test func flyingOverRootsAndLanding() throws {
        var sim = GameSimulation(seed: 1)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 10, inventory: glider()))
        // Stand just outside a root, facing it.
        let root = sim.map.roots[0]
        let side = Vec2(root.points[2].y, -root.points[2].x).normalizedOrZero
        sim.teleport(player, to: root.points[2] + side * (root.radii[2] + 1))

        sim.enqueue(.toggleFlight, from: player)
        #expect(run(&sim, seconds: 0.1).contains(.flightChanged(player: player, isFlying: true)))
        _ = run(&sim, seconds: 2) { $0.enqueue(.climb(1), from: player) }
        #expect(try #require(sim.entity(player)).position.y > WorldMap.obstacleHeight)

        // Fly straight across the root.
        _ = run(&sim, seconds: 1.2) { $0.enqueue(.move(-side), from: player) }
        let across = try #require(sim.entity(player)).position.xz
        #expect(simd_dot_2(across - root.points[2], side) < 0, "crossed over the root")

        sim.enqueue(.move(.zero), from: player)
        sim.enqueue(.toggleFlight, from: player)
        _ = run(&sim, seconds: 3)
        let landed = try #require(sim.entity(player))
        #expect(landed.position.y == 0)
        #expect(!sim.map.isBlocked(landed.position.xz, radius: landed.radius - 0.01), "lands clear of the root")
    }

    @Test func mobsCantReachFlyers() throws {
        var sim = GameSimulation(seed: 3)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 10, inventory: glider()))
        let slug = try #require(sim.snapshot().entities.first { $0.kind == .mob(.slug) && $0.isAggressive })
        sim.teleport(player, to: slug.position.xz + Vec2(1.2, 0))
        _ = run(&sim, seconds: 2)
        #expect(sim.entity(slug.id)?.combat.target == player, "aggroed on the ground")

        sim.enqueue(.toggleFlight, from: player)
        _ = run(&sim, seconds: 2) { $0.enqueue(.climb(1), from: player) }
        let events = run(&sim, seconds: 3) { $0.enqueue(.climb(1), from: player) }
        #expect(!events.contains { if case .damage(_, player, _, _, _) = $0 { true } else { false } })
        #expect(sim.entity(slug.id)?.combat.target == nil)

        sim.enqueue(.useSkill(.capBash), from: player)
        #expect(run(&sim, seconds: 0.1).contains { if case .skillFailed(player, _, .airborne) = $0 { true } else { false } })
    }

    @Test func classSurvivesSaveRoundTrip() throws {
        var sim = GameSimulation(seed: 1)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 16, playerClass: .sporecaster))
        let profile = try #require(sim.profile(of: player))
        let decoded = try JSONDecoder().decode(PlayerProfile.self, from: JSONEncoder().encode(profile))
        #expect(decoded.playerClass == .sporecaster)

        // Saves from before classes existed have no "playerClass" key and must still load.
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as! [String: Any]
        legacy["playerClass"] = nil
        let old = try JSONDecoder().decode(PlayerProfile.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(old.playerClass == nil)
    }
}

private func simd_dot_2(_ a: Vec2, _ b: Vec2) -> Float { (a * b).sum() }
