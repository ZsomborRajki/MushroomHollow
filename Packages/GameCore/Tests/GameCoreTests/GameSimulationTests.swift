import Foundation
import Testing
@testable import GameCore

@Suite struct GameSimulationTests {
    private func run(_ sim: inout GameSimulation, player: EntityID, move: Vec2, seconds: Float) {
        for _ in 0..<Int(seconds * Float(GameSimulation.tickRate)) {
            sim.enqueue(.move(move), from: player)
            sim.step()
        }
    }

    @Test func playerMovesInCommandedDirection() throws {
        var sim = GameSimulation(seed: 1)
        let player = sim.spawnPlayer()
        let start = try #require(sim.entity(player)).position

        run(&sim, player: player, move: Vec2(1, 0), seconds: 1)

        let end = try #require(sim.entity(player)).position
        #expect(abs((end.x - start.x) - GameSimulation.playerSpeed) < 0.01)
        #expect(abs(end.z - start.z) < 0.01)
        #expect(abs(AngleMath.wrap(try #require(sim.entity(player)).yaw - .pi / 2)) < 0.01)
    }

    @Test func moveIntentIsClampedToFullSpeed() throws {
        var sim = GameSimulation(seed: 1)
        let player = sim.spawnPlayer()
        let start = try #require(sim.entity(player)).position

        run(&sim, player: player, move: Vec2(10, 0), seconds: 1)

        let end = try #require(sim.entity(player)).position
        #expect(end.x - start.x <= GameSimulation.playerSpeed + 0.01)
    }

    @Test func playerCannotWalkIntoTheTrunk() throws {
        var sim = GameSimulation(seed: 1)
        let player = sim.spawnPlayer()

        // Spawn is south of the trunk; walk north into it for a long time.
        run(&sim, player: player, move: Vec2(0, -1), seconds: 20)

        let distance = try #require(sim.entity(player)).position.xz.length
        #expect(distance >= sim.map.trunkCollisionRadius + GameSimulation.playerRadius - 0.01)
    }

    @Test func playerStaysInsideWorldBoundary() throws {
        var sim = GameSimulation(seed: 1)
        let player = sim.spawnPlayer()

        run(&sim, player: player, move: Vec2(0, 1), seconds: 30)

        let distance = try #require(sim.entity(player)).position.xz.length
        #expect(distance <= sim.map.boundaryRadius)
    }

    @Test func mobsWanderButStayNearHome() {
        var sim = GameSimulation(seed: 7)
        let initial = sim.snapshot()
        for _ in 0..<(GameSimulation.tickRate * 60) { sim.step() }
        let later = sim.snapshot()

        let spawnCount = sim.map.mobSpawns.reduce(0) { $0 + $1.count }
        #expect(later.entities.filter(\.kind.isMob).count == spawnCount)

        var movedCount = 0
        for mob in later.entities {
            guard case let .mob(kind) = mob.kind,
                  let area = sim.map.mobSpawns.first(where: { $0.kind == kind }),
                  let before = initial.entity(mob.id) else { continue }
            #expect(mob.position.xz.distance(to: area.center) <= area.radius + kind.radius + 2)
            if mob.position.xz.distance(to: before.position.xz) > 0.5 { movedCount += 1 }
        }
        #expect(movedCount > spawnCount / 2)
    }

    @Test func simulationIsDeterministic() {
        func play() -> WorldSnapshot {
            var sim = GameSimulation(seed: 42)
            let player = sim.spawnPlayer()
            for tick in 0..<400 {
                let angle = Float(tick) * 0.05
                sim.enqueue(.move(Vec2(sin(angle), cos(angle))), from: player)
                sim.step()
            }
            return sim.snapshot()
        }
        #expect(play() == play())
    }

    @Test func localHostRunsFixedTicksAndInterpolates() {
        let host = LocalWorldHost(seed: 3)
        host.advance(by: 0.125) // 2.5 ticks at 20 Hz
        #expect(host.currentSnapshot.tick == 2)
        #expect(host.previousSnapshot.tick == 1)
        #expect(abs(host.interpolationAlpha - 0.5) < 0.01)
    }

    @Test func angleMathWrapsAndInterpolatesTheShortWay() {
        #expect(abs(AngleMath.wrap(2.5 * .pi) - 0.5 * .pi) < 1e-4)
        #expect(abs(abs(AngleMath.wrap(3 * .pi)) - .pi) < 1e-4) // ±pi, float rounding decides
        let halfway = AngleMath.lerp(.pi - 0.1, -.pi + 0.1, 0.5)
        #expect(abs(abs(halfway) - .pi) < 1e-4)
    }
}
