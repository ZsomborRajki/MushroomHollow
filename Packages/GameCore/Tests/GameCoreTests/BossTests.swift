import Foundation
import Testing
@testable import GameCore

@Suite struct BossTests {
    private func run(_ sim: inout GameSimulation, seconds: Float, each: ((inout GameSimulation) -> Void)? = nil) -> [WorldEvent] {
        var events: [WorldEvent] = []
        for _ in 0..<Int(seconds * Float(GameSimulation.tickRate)) {
            each?(&sim)
            events += sim.step()
        }
        return events
    }

    /// A night-time world with the owl out and a sturdy hero standing next to it.
    private func arena(heroes: Int = 1) throws -> (GameSimulation, owl: EntityID, heroes: [EntityID]) {
        var sim = GameSimulation(seed: 5, startTimeOfDay: 0.9)
        _ = sim.step()
        let owl = try #require(sim.worldBoss)
        let owlPosition = try #require(sim.entity(owl)).position.xz
        // Stand on the open side (toward the arena center), away from the fallen branch.
        let center = try #require(sim.map.bossArena).center
        let inward = AngleMath.yaw(facing: center - owlPosition)
        let ids = (0..<heroes).map { index in
            let id = sim.spawnPlayer(profile: PlayerProfile(level: 20, playerClass: .guardian))
            sim.teleport(id, to: owlPosition + AngleMath.direction(forYaw: inward + Float(index) * 0.5) * 4.5)
            return id
        }
        return (sim, owl, ids)
    }

    private func setHealth(_ fraction: Float, of id: EntityID, in sim: inout GameSimulation) {
        guard let max = sim.entities[id]?.stats.maxHP else { return }
        sim.entities[id]?.stats.hp = Int(Float(max) * fraction)
    }

    // MARK: - Night cycle

    @Test func owlComesOutAtNightAndLeavesAtDawn() throws {
        var sim = GameSimulation(seed: 1, startTimeOfDay: 0.79)
        _ = sim.step()
        #expect(sim.worldBoss == nil, "not yet night")

        let untilNight = Float(GameSimulation.dayLengthTicks) * 0.02 / Float(GameSimulation.tickRate)
        let evening = run(&sim, seconds: untilNight)
        #expect(evening.contains { if case .worldBossSpawned(_, .owl) = $0 { true } else { false } })
        let owl = try #require(sim.worldBoss)
        #expect(sim.map.bossArena.map { sim.entity(owl)!.position.xz.distance(to: $0.center) < $0.radius } == true)

        let untilDawn = Float(GameSimulation.dayLengthTicks) * 0.45 / Float(GameSimulation.tickRate)
        let morning = run(&sim, seconds: untilDawn)
        #expect(morning.contains(.worldBossDeparted(entity: owl)))
        #expect(sim.worldBoss == nil)
    }

    @Test func defeatedOwlStaysGoneUntilTomorrowNight() throws {
        var (sim, owl, heroes) = try arena()
        setHealth(0.001, of: owl, in: &sim)
        sim.enqueue(.target(owl, engage: true), from: heroes[0])
        let events = run(&sim, seconds: 6)
        #expect(events.contains { if case .worldBossDefeated(owl, _) = $0 { true } else { false } })

        let rest = run(&sim, seconds: 60)
        #expect(!rest.contains { if case .worldBossSpawned = $0 { true } else { false } })
    }

    // MARK: - Moves

    @Test func swoopHitsWhoeverStaysInTheCircle() throws {
        var (sim, owl, heroes) = try arena()
        let hero = heroes[0]
        sim.enqueue(.target(owl, engage: true), from: hero)

        var impactHit: Bool?
        for _ in 0..<(GameSimulation.tickRate * 20) where impactHit == nil {
            let events = sim.step()
            if events.contains(.mobAbility(entity: owl, ability: .swoopImpact)) {
                impactHit = events.contains { if case .damage(owl, hero, _, _, _) = $0 { true } else { false } }
            }
        }
        #expect(impactHit == true)
        #expect(sim.entity(owl)?.position.y == 0, "lands after the dive")
    }

    @Test func steppingOutOfTheCircleDodgesTheSwoop() throws {
        var (sim, owl, heroes) = try arena()
        let hero = heroes[0]
        sim.enqueue(.target(owl, engage: true), from: hero)

        var impactHit: Bool?
        var dodged = false
        for _ in 0..<(GameSimulation.tickRate * 20) where impactHit == nil {
            let events = sim.step()
            if !dodged, let circle = sim.snapshot().telegraphs.first {
                // Walk well clear of the marked circle.
                let away = (sim.entity(hero)!.position.xz - circle.position).normalizedOrZero
                sim.teleport(hero, to: circle.position + (away == .zero ? Vec2(1, 0) : away) * (GameSimulation.swoopRadius + 3))
                sim.enqueue(.target(nil, engage: false), from: hero) // stop chasing back in
                dodged = true
            }
            if events.contains(.mobAbility(entity: owl, ability: .swoopImpact)) {
                impactHit = events.contains { if case .damage(owl, hero, _, _, _) = $0 { true } else { false } }
            }
        }
        #expect(dodged)
        #expect(impactHit == false)
    }

    @Test func wingGustKnocksPlayersBack() throws {
        var (sim, owl, heroes) = try arena()
        let hero = heroes[0]
        setHealth(0.5, of: owl, in: &sim)
        sim.enqueue(.target(owl, engage: true), from: hero)

        var start: Vec2?
        for _ in 0..<(GameSimulation.tickRate * 20) where start == nil {
            if sim.step().contains(.knockedBack(entity: hero)) {
                start = sim.entity(hero)?.position.xz
            }
        }
        let before = try #require(start)
        _ = run(&sim, seconds: 0.5)
        let after = try #require(sim.entity(hero)).position.xz
        #expect(after.distance(to: before) > 2.5, "moved \(after.distance(to: before))")
    }

    @Test func summonsMiceAndEnragesWhenHurt() throws {
        var (sim, owl, heroes) = try arena()
        setHealth(0.29, of: owl, in: &sim)
        sim.enqueue(.target(owl, engage: true), from: heroes[0])
        let events = run(&sim, seconds: 1)

        #expect(events.contains(.mobAbility(entity: owl, ability: .summon)))
        #expect(events.contains(.mobAbility(entity: owl, ability: .enrage)))
        let mice = sim.snapshot().entities.filter { $0.kind == .mob(.mouse) }
        #expect(mice.count == 4)
        #expect(mice.allSatisfy { $0.target == heroes[0] })
    }

    @Test func everyoneWhoFoughtSharesTheSpoils() throws {
        var (sim, owl, heroes) = try arena(heroes: 2)
        for hero in heroes { sim.enqueue(.target(owl, engage: true), from: hero) }
        _ = run(&sim, seconds: 3)
        setHealth(0.001, of: owl, in: &sim)
        let events = run(&sim, seconds: 3)

        let defeated = events.compactMap { event -> [EntityID]? in
            if case let .worldBossDefeated(_, participants) = event { participants } else { nil }
        }.first
        #expect(Set(defeated ?? []) == Set(heroes))
        for hero in heroes {
            #expect((sim.playerStatus(hero)?.inventory.count(of: .owlFeather) ?? 0) >= 2)
        }
    }

    @Test func theOwlHuntsFlyers() throws {
        var (sim, owl, _) = try arena()
        var bag = Inventory()
        bag.add(.dandelionSeed, count: 1)
        let flyer = sim.spawnPlayer(profile: PlayerProfile(level: 20, inventory: bag))
        sim.teleport(flyer, to: try #require(sim.entity(owl)).position.xz + Vec2(0, 6))
        sim.enqueue(.toggleFlight, from: flyer)
        _ = run(&sim, seconds: 2) { $0.enqueue(.climb(1), from: flyer) }
        _ = run(&sim, seconds: 3)

        #expect(sim.entity(owl)?.combat.target != nil)
        #expect(try #require(sim.entity(owl)).position.y > 2)
    }
}
