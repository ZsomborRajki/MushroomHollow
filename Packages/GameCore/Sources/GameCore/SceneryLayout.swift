import Foundation

/// Scatters the forest floor's rocks, fallen twigs, and giant flowers, deterministically from a
/// seed. Each area has its own flora; hunting grounds stay fairly open and roads stay clear.
struct SceneryLayout {
    enum Biome {
        case wild, rim, lakeshore
        case glade, maze, barkfall, fen, bough
        case meadow, creek, thicket, rise, briars, grove
    }

    let boundaryRadius: Float
    /// The trunk, roots, houses, and NPCs.
    let blockers: [Collider]
    let keepClear: [Disc]
    let trails: [Trail]
    let terrain: Terrain
    let spawns: [MobSpawnArea]
    let biomes: [(Disc, Biome)]

    struct Result {
        var plants: [Plant] = []
        var boulders: [Boulder] = []
        var twigs: [Twig] = []
    }

    func grow(seed: UInt64) -> Result {
        var random = SeededRandom(seed: seed)
        var placed = Footprints()
        var result = Result()
        placeBoulders(&result, &placed, &random)
        placeTwigs(&result, &placed, &random)
        placePlants(&result, &placed, &random)
        return result
    }

    // MARK: - Where things may go

    func biome(at p: Vec2) -> Biome {
        if let lake = terrain.lakes.first, lake.signedDistance(to: p) < 12 { return .lakeshore }
        if p.length > 236 { return .rim }
        return biomes.first { $0.0.center.distance(to: p) <= $0.0.radius }?.1 ?? .wild
    }

    private func distanceToTrail(_ p: Vec2) -> Float {
        trails.map { $0.distance(to: p) - $0.width / 2 }.min() ?? .greatestFiniteMagnitude
    }

    /// Open ground for something of this footprint: inside the world, off roads and structures, out of the water.
    private func isOpen(_ p: Vec2, radius: Float, trailMargin: Float = 1.5, allowWater: Bool = false) -> Bool {
        let r = p.length
        guard r < boundaryRadius + 18, r > 17 + radius else { return false }
        if keepClear.contains(where: { $0.center.distance(to: p) < $0.radius + radius }) { return false }
        if distanceToTrail(p) < radius + trailMargin { return false }
        if !allowWater, let lake = terrain.lakes.first, lake.signedDistance(to: p) < radius + 0.5 { return false }
        return !blockers.contains { $0.separation(for: p, radius: radius + 0.4) != nil }
    }

    /// The mob spawn area around `p`, and how far into it (0 at the edge, 1 at the center).
    private func spawnDepth(_ p: Vec2) -> Float {
        spawns.map { 1 - $0.center.distance(to: p) / $0.radius }.max().map { max(0, $0) } ?? 0
    }

    // MARK: - Boulders

    private func placeBoulders(_ result: inout Result, _ placed: inout Footprints, _ random: inout SeededRandom) {
        let cell: Float = 24
        forEachCell(cell, &random) { p, random in
            let chance: Float = switch biome(at: p) {
            case .rim: 0.75
            case .rise, .creek: 0.6
            case .briars, .bough: 0.45
            case .wild: 0.32
            case .lakeshore: 0.35
            case .maze, .barkfall, .grove, .thicket: 0.25
            case .glade, .meadow, .fen: 0.12
            }
            guard random.unit() < chance * (1 - spawnDepth(p) * 0.8) else { return }
            // A cluster: one big stone and a few smaller ones leaning on it.
            let big: Float = biome(at: p) == .rim ? random.float(in: 2.5...6) : random.float(in: 1...3.4)
            let count = random.int(in: 1...4)
            for i in 0..<count {
                let radius = i == 0 ? big : big * random.float(in: 0.3...0.6)
                let offset = i == 0 ? Vec2.zero : AngleMath.direction(forYaw: random.float(in: 0...(2 * .pi))) * (big + radius * 0.6)
                let spot = p + offset
                guard isOpen(spot, radius: radius, trailMargin: 2), placed.isFree(spot, radius: radius, gap: 0.2) else { continue }
                let boulder = Boulder(position: spot, radius: radius, height: radius * random.float(in: 0.8...1.5),
                                      yaw: random.float(in: 0...(2 * .pi)), variant: UInt32(truncatingIfNeeded: random.next()))
                result.boulders.append(boulder)
                placed.add(spot, radius: radius)
            }
        }
    }

    // MARK: - Twigs

    private func placeTwigs(_ result: inout Result, _ placed: inout Footprints, _ random: inout SeededRandom) {
        forEachCell(20, &random) { p, random in
            let chance: Float = switch biome(at: p) {
            case .barkfall: 0.8
            case .rise, .grove: 0.55
            case .wild, .maze, .bough, .thicket: 0.32
            case .rim, .lakeshore, .briars, .creek: 0.2
            case .glade, .meadow, .fen: 0.12
            }
            guard random.unit() < chance * (1 - spawnDepth(p) * 0.7) else { return }
            let length = random.float(in: 3.5...10)
            let radius = random.float(in: 0.1...0.26) * (0.8 + length / 20)
            let direction = AngleMath.direction(forYaw: random.float(in: 0...(2 * .pi)))
            let a = p - direction * length / 2, b = p + direction * length / 2
            let samples = (0...Int(length)).map { a + (b - a) * (Float($0) / Float(Int(length))) }
            guard samples.allSatisfy({ isOpen($0, radius: radius + 0.3, trailMargin: 1.8) && placed.isFree($0, radius: radius, gap: 0.6) })
            else { return }
            result.twigs.append(Twig(from: a, to: b, radius: radius, variant: UInt32(truncatingIfNeeded: random.next())))
            for s in samples { placed.add(s, radius: radius) }
        }
    }

    // MARK: - Plants

    private func flora(_ biome: Biome) -> (density: Float, mix: [(PlantKind, Float)]) {
        switch biome {
        case .wild: (0.17, [(.daisy, 3), (.fern, 4), (.bluebell, 2), (.tulip, 1.5), (.foxglove, 1), (.bush, 2), (.toadstool, 1.5),
                           (.dandelion, 1), (.clover, 2), (.poppy, 0.8)])
        case .rim: (0.24, [(.fern, 6), (.bush, 4), (.foxglove, 2), (.bluebell, 1), (.sapling, 2), (.toadstool, 1)])
        case .lakeshore: (0.3, [(.daisy, 3), (.clover, 3), (.buttercup, 2), (.bluebell, 1), (.fern, 1), (.tulip, 1)])
        case .glade: (0.18, [(.daisy, 5), (.clover, 5), (.buttercup, 3), (.tulip, 2)])
        case .maze: (0.2, [(.fern, 4), (.bluebell, 4), (.toadstool, 2), (.clover, 1)])
        case .barkfall: (0.14, [(.fern, 2), (.bush, 2), (.toadstool, 2), (.daisy, 1)])
        case .fen: (0.22, [(.glowcap, 5), (.cattail, 3), (.toadstool, 2), (.fern, 1)])
        case .bough: (0.08, [(.fern, 2), (.bluebell, 1), (.toadstool, 1)])
        case .meadow: (0.2, [(.buttercup, 4), (.dandelion, 3), (.dandelionClock, 2), (.clover, 3), (.poppy, 2), (.daisy, 1)])
        case .creek: (0.14, [(.cattail, 3), (.fern, 2), (.clover, 1), (.bluebell, 1)])
        case .thicket: (0.26, [(.fern, 6), (.foxglove, 2), (.bluebell, 2), (.bush, 1)])
        case .rise: (0.17, [(.sapling, 5), (.fern, 1), (.bush, 1), (.foxglove, 1)])
        case .briars: (0.2, [(.bramble, 4), (.poppy, 2), (.foxglove, 1), (.tulip, 1)])
        case .grove: (0.2, [(.toadstool, 4), (.glowcap, 3), (.fern, 3)])
        }
    }

    private func placePlants(_ result: inout Result, _ placed: inout Footprints, _ random: inout SeededRandom) {
        forEachCell(7, &random) { p, random in
            // Lily pads float on the lake, cattails stand in the shallows.
            if let lake = terrain.lakes.first {
                let d = lake.signedDistance(to: p)
                if d < -Lake.wadeDistance - 1 {
                    guard random.unit() < 0.3, placed.isFree(p, radius: 1.2, gap: 0.3) else { return }
                    add(.lilyPad, at: p, scale: random.float(in: 0.7...1.4), &result, &placed, &random)
                    return
                }
                if d < 1.2 {
                    guard random.unit() < 0.5, placed.isFree(p, radius: 0.3, gap: 0.6),
                          isOpen(p, radius: 0.2, allowWater: true) else { return }
                    add(.cattail, at: p, scale: random.float(in: 0.8...1.25), &result, &placed, &random)
                    return
                }
            }
            let biome = biome(at: p)
            let (density, mix) = flora(biome)
            let depth = spawnDepth(p)
            guard random.unit() < density * (1 - depth * 0.6) else { return }
            var pick = random.float(in: 0...mix.reduce(0) { $0 + $1.1 })
            let kind = mix.first { pick -= $0.1; return pick <= 0 }?.0 ?? mix[0].0
            let scale = random.float(in: 0.75...1.3)
            let reach = max(kind.typicalCollisionRadius * scale, 0.3)
            // Keep the middle of each hunting ground clear of anything you'd bump into.
            if depth > 0.75, kind.typicalCollisionRadius > 0.3 { return }
            guard isOpen(p, radius: reach), placed.isFree(p, radius: reach, gap: kind == .clover ? 0.3 : 1) else { return }
            add(kind, at: p, scale: scale, &result, &placed, &random)
        }
    }

    private func add(_ kind: PlantKind, at p: Vec2, scale: Float, _ result: inout Result, _ placed: inout Footprints,
                     _ random: inout SeededRandom) {
        let plant = Plant(kind: kind, position: p, height: kind.typicalHeight * scale,
                          yaw: random.float(in: 0...(2 * .pi)), variant: UInt32(truncatingIfNeeded: random.next()))
        result.plants.append(plant)
        placed.add(p, radius: max(plant.collisionRadius, kind == .lilyPad ? 1.2 * scale : 0.3))
    }

    /// Visits one jittered point per grid cell, across the whole world.
    private func forEachCell(_ size: Float, _ random: inout SeededRandom, _ body: (Vec2, inout SeededRandom) -> Void) {
        let extent = boundaryRadius + 18
        let count = Int((2 * extent / size).rounded(.up))
        for row in 0..<count {
            for column in 0..<count {
                let jitter = Vec2(random.float(in: -0.45...0.45), random.float(in: -0.45...0.45)) * size
                let p = Vec2(-extent + (Float(column) + 0.5) * size, -extent + (Float(row) + 0.5) * size) + jitter
                guard p.length < extent else { continue }
                body(p, &random)
            }
        }
    }
}

/// Discs already claimed by scenery, bucketed for quick overlap tests.
private struct Footprints {
    private var buckets: [SIMD2<Int32>: [Disc]] = [:]
    private static let cell: Float = 8
    private static let maxRadius: Float = 8

    private static func key(_ p: Vec2) -> SIMD2<Int32> {
        SIMD2(Int32((p.x / cell).rounded(.down)), Int32((p.y / cell).rounded(.down)))
    }

    func isFree(_ p: Vec2, radius: Float, gap: Float) -> Bool {
        let k = Self.key(p)
        let reach = Int32(((radius + gap + Self.maxRadius) / Self.cell).rounded(.up))
        for dy in -reach...reach {
            for dx in -reach...reach {
                for disc in buckets[k &+ SIMD2(dx, dy)] ?? [] where disc.center.distance(to: p) < disc.radius + radius + gap {
                    return false
                }
            }
        }
        return true
    }

    mutating func add(_ p: Vec2, radius: Float) {
        buckets[Self.key(p), default: []].append(Disc(center: p, radius: min(radius, Self.maxRadius)))
    }
}
