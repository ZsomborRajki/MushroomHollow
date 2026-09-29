import Foundation
import Testing
@testable import GameCore

@Suite struct CombatTests {
    /// A sim with the player standing right next to the first mob of `kind`.
    private func arena(_ kind: MobKind = .snail, seed: UInt64 = 11) throws -> (GameSimulation, player: EntityID, mob: EntityID) {
        var sim = GameSimulation(seed: seed)
        let player = sim.spawnPlayer()
        // Aggressive kinds: pick one that attacks on sight (most only fight back).
        let mob = try #require(sim.snapshot().entities.first { $0.kind == .mob(kind) && ($0.isAggressive || kind.stats.aggroRadius == 0) })
        sim.teleport(player, to: mob.position.xz + Vec2(1.2, 0))
        return (sim, player, mob.id)
    }

    @discardableResult
    private func run(_ sim: inout GameSimulation, seconds: Float, each: ((inout GameSimulation) -> Void)? = nil) -> [WorldEvent] {
        var events: [WorldEvent] = []
        for _ in 0..<Int(seconds * Float(GameSimulation.tickRate)) {
            each?(&sim)
            events += sim.step()
        }
        return events
    }

    @Test func engagingKillsASnailAndGrantsXP() throws {
        var (sim, player, snail) = try arena()
        sim.enqueue(.target(snail, engage: true), from: player)

        let events = run(&sim, seconds: 25)

        #expect(events.contains(.died(entity: snail, killer: player)))
        #expect(events.contains { if case .xpGained(player, _) = $0 { true } else { false } })
        let status = try #require(sim.playerStatus(player))
        #expect(status.xp > 0 || status.stats.level > 1)
        #expect(status.target == nil, "dead targets are cleared")
    }

    @Test func playerChasesTargetOutOfReach() throws {
        var (sim, player, snail) = try arena()
        let snailPosition = try #require(sim.entity(snail)).position.xz
        sim.teleport(player, to: snailPosition + Vec2(6, 0))
        let before = try #require(sim.entity(player)).position.xz.distance(to: snailPosition)

        sim.enqueue(.target(snail, engage: true), from: player)
        run(&sim, seconds: 0.5)

        let after = try #require(sim.entity(player)).position.xz.distance(to: try #require(sim.entity(snail)).position.xz)
        #expect(after < before - 1)
    }

    @Test func movingCancelsAutoAttackButKeepsTarget() throws {
        var (sim, player, snail) = try arena()
        sim.enqueue(.target(snail, engage: true), from: player)
        run(&sim, seconds: 1)

        sim.enqueue(.move(Vec2(1, 0)), from: player)
        run(&sim, seconds: 0.2)

        let status = try #require(sim.playerStatus(player))
        #expect(status.target == snail)
        #expect(!status.isEngaged)
    }

    @Test func passiveSnailOnlyFightsBack() throws {
        var (sim, player, snail) = try arena()
        run(&sim, seconds: 3)
        #expect(sim.entity(player)?.stats.hp == sim.entity(player)?.stats.maxHP, "snails are passive")

        sim.enqueue(.target(snail, engage: true), from: player)
        let events = run(&sim, seconds: 3)
        #expect(events.contains { if case .damage(snail, player, _, _, _) = $0 { true } else { false } })
    }

    @Test func aggressiveSlugAttacksNearbyPlayer() throws {
        var (sim, player, slug) = try arena(.slug)
        let events = run(&sim, seconds: 4)
        #expect(events.contains { if case .damage(slug, player, _, _, _) = $0 { true } else { false } })
    }

    @Test func mobGivesUpWhenPulledPastItsLeash() throws {
        var (sim, player, snail) = try arena()
        sim.enqueue(.target(snail, engage: true), from: player)
        run(&sim, seconds: 1.5)
        // Run far away, out past the glade.
        sim.enqueue(.target(nil, engage: false), from: player)
        run(&sim, seconds: 12) { $0.enqueue(.move(Vec2(1, 0)), from: player) }
        run(&sim, seconds: 20)

        let mob = try #require(sim.entity(snail))
        #expect(mob.stats.hp == mob.stats.maxHP, "leashed mobs reset to full health")
        #expect(mob.combat.target == nil)
    }

    @Test func levelUpRaisesStatsAndHeals() throws {
        var sim = GameSimulation(seed: 1)
        let id = sim.spawnPlayer()
        var player = try #require(sim.entity(id))
        player.stats.hp = 10

        for _ in 0..<3 { sim.awardXP(to: &player, for: .slug) }

        #expect(player.stats.level >= 2)
        #expect(player.stats.hp == player.stats.maxHP)
        #expect(player.stats.attack > Progression.playerStats(level: 1).attack)
    }

    @Test func xpRewardScalesWithLevelDifference() {
        let even = Progression.xpReward(baseXP: 10, mobLevel: 5, playerLevel: 5)
        #expect(Progression.xpReward(baseXP: 10, mobLevel: 8, playerLevel: 5) > even)
        #expect(Progression.xpReward(baseXP: 10, mobLevel: 2, playerLevel: 5) < even)
        #expect(Progression.xpReward(baseXP: 10, mobLevel: 1, playerLevel: 15) >= 1)
    }

    @Test func targetedSkillSpendsManaAndStartsCooldown() throws {
        var (sim, player, snail) = try arena()
        sim.enqueue(.target(snail, engage: false), from: player)
        sim.enqueue(.useSkill(.capBash), from: player)
        let events = run(&sim, seconds: 1)

        #expect(events.contains(.skillCast(caster: player, skill: .capBash, target: snail)))
        let status = try #require(sim.playerStatus(player))
        let bash = try #require(status.skills.first { $0.id == .capBash })
        #expect(bash.cooldownRemaining > 0)
        #expect(status.stats.mp < status.stats.maxMP)
        #expect(status.isEngaged, "a targeted skill starts auto-attack")

        sim.enqueue(.useSkill(.capBash), from: player)
        let retry = run(&sim, seconds: 0.1)
        #expect(retry.contains(.skillFailed(caster: player, skill: .capBash, reason: .cooldown)))
    }

    @Test func skillFailuresAreReported() throws {
        var (sim, player, _) = try arena()
        sim.enqueue(.useSkill(.capBash), from: player) // no target
        sim.enqueue(.useSkill(.dewdrop), from: player) // level 5 skill at level 1
        let events = run(&sim, seconds: 0.1)
        #expect(events.contains(.skillFailed(caster: player, skill: .capBash, reason: .noTarget)))
        #expect(events.contains(.skillFailed(caster: player, skill: .dewdrop, reason: .locked)))
    }

    @Test func deadMobsDespawnAndRespawn() throws {
        var (sim, player, snail) = try arena()
        let snailCount = { (sim: GameSimulation) in sim.snapshot().entities.filter { $0.kind == .mob(.snail) }.count }
        let initial = snailCount(sim)
        sim.enqueue(.target(snail, engage: true), from: player)
        run(&sim, seconds: 40) // mobs are built to last
        #expect(sim.entity(snail) == nil, "corpse despawned")

        run(&sim, seconds: MobKind.snail.stats.respawnSeconds + 1)
        #expect(snailCount(sim) == initial)
    }

    @Test func faintedPlayerRespawnsInVillage() throws {
        var (sim, player, _) = try arena(.slug)
        var fainted = false
        for _ in 0..<(GameSimulation.tickRate * 120) where !fainted {
            fainted = sim.step().contains(.died(entity: player, killer: nil)) || sim.entity(player)?.stats.isAlive == false
        }
        #expect(fainted, "a level 1 player idling next to slugs eventually faints")

        sim.enqueue(.move(Vec2(1, 0)), from: player)
        run(&sim, seconds: 0.5)
        let corpse = try #require(sim.entity(player))
        #expect(corpse.velocity == .zero, "fainted players can't move")

        sim.enqueue(.respawn, from: player)
        let events = run(&sim, seconds: 0.1)
        #expect(events.contains(.respawned(entity: player)))
        let revived = try #require(sim.entity(player))
        #expect(revived.stats.hp == revived.stats.maxHP)
        #expect(revived.position.xz.distance(to: sim.map.playerSpawn) < 1)
    }

    @Test func tabTargetingCyclesByDistance() throws {
        let sim = GameSimulation(seed: 5)
        let snapshot = sim.snapshot()
        let snail = try #require(snapshot.entities.first { $0.kind == .mob(.snail) })
        let origin = snail.position
        let ordered = snapshot.hostiles(near: origin).map(\.id)
        #expect(ordered.first == snail.id)

        let second = snapshot.cycleTarget(from: origin, current: ordered[0], step: 1)
        #expect(second == ordered[1])
        let wrapped = snapshot.cycleTarget(from: origin, current: ordered[0], step: -1)
        #expect(wrapped == ordered.last)
    }
}
