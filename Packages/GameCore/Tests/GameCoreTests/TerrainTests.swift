import Foundation
import Testing
@testable import GameCore

/// The shape of the world: hills, the lake, scenery, and how spread out the mobs are.
@Suite struct TerrainTests {
    private let map = WorldMap.mushroomHollow

    private func run(_ sim: inout GameSimulation, seconds: Float, each: ((inout GameSimulation) -> Void)? = nil) {
        for _ in 0..<Int(seconds * Float(GameSimulation.tickRate)) {
            each?(&sim)
            sim.step()
        }
    }

    @Test func clearingsAreFlatAndTheWorldRolls() throws {
        for point in [map.villageCenter, map.playerSpawn, Vec2(0, 20), try #require(map.bossArena).center] {
            #expect(abs(map.groundHeight(at: point) - map.groundHeight(at: map.villageCenter)) < 0.6, "flat at \(point)")
        }
        let heights = stride(from: -200, through: 200, by: 10).flatMap { x in
            stride(from: -200, through: 200, by: 10).map { z in map.groundHeight(at: Vec2(Float(x), Float(z))) }
        }
        #expect((heights.max() ?? 0) - (heights.min() ?? 0) > 8, "real hills and hollows")
        #expect(map.groundHeight(at: Vec2(0, 299)) > 15, "the hollow's rim rises at the edge")
    }

    @Test func pineconeRiseIsAHill() throws {
        let rise = try #require(map.zones.first { $0.name == "Pinecone Rise" })
        #expect(map.groundHeight(at: rise.center) > map.groundHeight(at: map.villageCenter) + 5)
    }

    @Test func theLakeIsDeepInTheMiddleAndBlocksWalkers() throws {
        let lake = try #require(map.terrain.lakes.first)
        let middle = lake.discs[0].center
        #expect(map.groundHeight(at: middle) < lake.waterLevel - 2)
        #expect(map.surfaceHeight(at: middle) == lake.waterLevel)
        #expect(map.isBlocked(middle, radius: 0.35))

        var sim = GameSimulation(seed: 1)
        let player = sim.spawnPlayer()
        let shore = middle + Vec2(lake.discs[0].radius + 3, 0)
        sim.teleport(player, to: shore)
        run(&sim, seconds: 8) { $0.enqueue(.move(Vec2(-1, 0)), from: player) }
        let stop = try #require(sim.entity(player)).position.xz
        #expect(lake.signedDistance(to: stop) < 0, "wades into the shallows")
        #expect(!map.isOverDeepWater(stop), "but no deeper")
    }

    @Test func glidersSkimOverTheLake() throws {
        let lake = try #require(map.terrain.lakes.first)
        var sim = GameSimulation(seed: 1)
        var bag = Inventory()
        bag.add(.dandelionSeed, count: 1)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 10, inventory: bag))
        let middle = lake.discs[0].center
        sim.teleport(player, to: middle + Vec2(lake.discs[0].radius + 3, 0))
        sim.enqueue(.toggleFlight, from: player)
        run(&sim, seconds: 1) { $0.enqueue(.climb(1), from: player) }
        sim.enqueue(.climb(0), from: player)
        run(&sim, seconds: 4) { $0.enqueue(.move(Vec2(-1, 0)), from: player) }
        #expect(map.isOverDeepWater(try #require(sim.entity(player)).position.xz))

        // Asking to land over deep water leaves you hovering just above it.
        sim.enqueue(.move(.zero), from: player)
        sim.enqueue(.toggleFlight, from: player)
        run(&sim, seconds: 2)
        let hovering = try #require(sim.entity(player))
        #expect(hovering.position.y == WorldMap.waterHoverAltitude, "at \(hovering.position)")
        #expect(map.isOverDeepWater(hovering.position.xz), "not shoved ashore")

        // Drift back to shore and touch down.
        run(&sim, seconds: 8) { $0.enqueue(.move(Vec2(1, 0)), from: player) }
        let landed = try #require(sim.entity(player))
        #expect(landed.position.y == 0)
        #expect(!map.isOverDeepWater(landed.position.xz))
    }

    @Test func mobsStartSpreadOut() {
        let sim = GameSimulation(seed: 5)
        let mobs = sim.snapshot().entities.filter(\.kind.isMob)
        let gaps = mobs.map { mob in
            mobs.filter { $0.id != mob.id }.map { $0.position.xz.distance(to: mob.position.xz) }.min() ?? 0
        }.sorted()
        let median = gaps[gaps.count / 2]
        #expect(median > 8, "median nearest neighbour \(median) m")
        #expect(gaps[gaps.count / 10] > 5, "few mobs start in pairs")
    }

    @Test func mobsRespawnAwayFromThePlayer() throws {
        var sim = GameSimulation(seed: 11)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 30))
        let area = try #require(map.mobSpawns.first { $0.kind == .snail })
        sim.teleport(player, to: area.center)
        let snails = sim.snapshot().entities.filter { $0.kind == .mob(.snail) }.map(\.id)
        for id in snails { sim.entities[id]?.stats.hp = 0 }
        run(&sim, seconds: MobKind.snail.stats.respawnSeconds + 3)
        let fresh = sim.snapshot().entities.filter { $0.kind == .mob(.snail) && $0.isAlive }
        #expect(fresh.count == area.count)
        let me = try #require(sim.entity(player)).position.xz
        #expect(fresh.allSatisfy { $0.position.xz.distance(to: me) > 3 })
    }

    @Test func gridResolvesLikeAFullScan() {
        var random = SeededRandom(seed: 99)
        for _ in 0..<3000 {
            let p = random.point(inDiscAt: .zero, radius: map.boundaryRadius)
            let radius = random.float(in: 0.3...1.2)
            let blocked = map.colliders.contains { $0.separation(for: p, radius: radius) != nil }
                || map.isOverDeepWater(p, radius: radius) || p.length > map.boundaryRadius - radius
            #expect(map.isBlocked(p, radius: radius) == blocked, "at \(p)")
        }
    }

    @Test func roadsVillageAndSpawnsStayClear() throws {
        for trail in map.trails {
            let count = trail.closed ? trail.points.count : trail.points.count - 1
            for i in 0..<count {
                let a = trail.points[i], b = trail.points[(i + 1) % trail.points.count]
                for step in 0...10 {
                    let p = a + (b - a) * (Float(step) / 10)
                    let rootsOnly = map.colliders.prefix(1 + map.roots.count * 6)
                    guard !rootsOnly.contains(where: { $0.separation(for: p, radius: 0.4) != nil }) else { continue }
                    #expect(!map.isBlocked(p, radius: 0.4), "road clear at \(p)")
                }
            }
        }
        for npc in map.npcs {
            #expect(!map.isBlocked(npc.position + Vec2(0, 1.2), radius: GameSimulation.playerRadius))
        }
        for area in map.mobSpawns {
            #expect(!map.isBlocked(area.center, radius: 1.5), "\(area.kind) has room")
        }
    }

    @Test func theForestIsFullOfThings() {
        #expect(map.plants.count > 600)
        #expect(map.boulders.count > 120)
        #expect(map.twigs.count > 80)
        #expect(Set(map.plants.map(\.kind)).count == PlantKind.allCases.count, "every kind of plant grows somewhere")
        print("scenery: \(map.plants.count) plants, \(map.boulders.count) boulders, \(map.twigs.count) twigs, \(map.colliders.count) colliders")
    }
}
