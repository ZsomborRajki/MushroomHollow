import Foundation

/// Static collision shape on the ground plane.
public enum Collider: Codable, Sendable {
    case circle(center: Vec2, radius: Float)
    case capsule(a: Vec2, b: Vec2, radius: Float)

    /// Returns how far to push a circle out of this shape, or nil if they don't overlap.
    func separation(for point: Vec2, radius: Float) -> Vec2? {
        let closest: Vec2
        let shapeRadius: Float
        switch self {
        case let .circle(center, r):
            closest = center
            shapeRadius = r
        case let .capsule(a, b, r):
            let ab = b - a
            let t = max(0, min(1, ((point - a) * ab).sum() / max((ab * ab).sum(), 1e-6)))
            closest = a + ab * t
            shapeRadius = r
        }
        let offset = point - closest
        let distance = offset.length
        let minDistance = shapeRadius + radius
        guard distance < minDistance else { return nil }
        let normal = distance > 1e-5 ? offset / distance : Vec2(0, 1)
        return normal * (minDistance - distance)
    }
}

/// A root running out from the trunk, as a polyline with a thickness at each point.
public struct TreeRoot: Codable, Sendable {
    public let points: [Vec2]
    public let radii: [Float]
}

public struct MushroomHouse: Codable, Sendable {
    public let position: Vec2
    /// Yaw the door faces.
    public let yaw: Float
    public let stemRadius: Float
    public let stemHeight: Float
    public let capRadius: Float
}

public struct NPCPlacement: Codable, Sendable {
    public let id: NPCID
    public let position: Vec2
    public let yaw: Float
}

/// A named region, shown in the HUD.
public struct Zone: Codable, Sendable {
    public let name: String
    public let center: Vec2
    public let radius: Float
    /// Suggested level range, for the HUD.
    public let levels: ClosedRange<Int>?
}

/// Where the world boss lives.
public struct BossArena: Codable, Sendable {
    public let kind: MobKind
    public let center: Vec2
    public let radius: Float
    /// The fallen branch it perches beside.
    public let perch: Vec2
}

public struct MobSpawnArea: Codable, Sendable {
    public let kind: MobKind
    public let center: Vec2
    public let radius: Float
    public let count: Int
}

/// Static layout of the world. Both the simulation (collision, spawns) and the client
/// (placeholder geometry) build from this, so they always agree.
public struct WorldMap: Codable, Sendable {
    public let boundaryRadius: Float
    public let trunkRadius: Float
    /// Includes the flared base of the trunk.
    public let trunkCollisionRadius: Float
    public let roots: [TreeRoot]
    public let houses: [MushroomHouse]
    public let villageCenter: Vec2
    public let villageRadius: Float
    public let playerSpawn: Vec2
    public let mobSpawns: [MobSpawnArea]
    public let npcs: [NPCPlacement]
    public let zones: [Zone]
    public let bossArena: BossArena?
    public let colliders: [Collider]

    public init(
        boundaryRadius: Float,
        trunkRadius: Float,
        trunkCollisionRadius: Float,
        roots: [TreeRoot],
        houses: [MushroomHouse],
        villageCenter: Vec2,
        villageRadius: Float,
        playerSpawn: Vec2,
        mobSpawns: [MobSpawnArea],
        npcs: [NPCPlacement],
        zones: [Zone],
        bossArena: BossArena? = nil
    ) {
        self.boundaryRadius = boundaryRadius
        self.trunkRadius = trunkRadius
        self.trunkCollisionRadius = trunkCollisionRadius
        self.roots = roots
        self.houses = houses
        self.villageCenter = villageCenter
        self.villageRadius = villageRadius
        self.playerSpawn = playerSpawn
        self.mobSpawns = mobSpawns
        self.npcs = npcs
        self.zones = zones
        self.bossArena = bossArena

        var colliders: [Collider] = [.circle(center: .zero, radius: trunkCollisionRadius)]
        for root in roots {
            for i in 0..<(root.points.count - 1) {
                let radius = (root.radii[i] + root.radii[i + 1]) / 2
                colliders.append(.capsule(a: root.points[i], b: root.points[i + 1], radius: radius))
            }
        }
        for house in houses {
            colliders.append(.circle(center: house.position, radius: house.stemRadius + 0.15))
        }
        for npc in npcs {
            colliders.append(.circle(center: npc.position, radius: 0.45))
        }
        self.colliders = colliders
    }

    /// Roots, houses, and NPCs are shorter than this; above it only the trunk is in the way.
    public static let obstacleHeight: Float = 6

    /// Pushes a circle out of every collider and back inside the world boundary.
    /// Above `obstacleHeight` only the trunk (always the first collider) blocks.
    public func resolve(_ point: Vec2, radius: Float, altitude: Float = 0) -> Vec2 {
        var p = point
        let active = altitude > Self.obstacleHeight ? colliders.prefix(1) : colliders[...]
        for _ in 0..<2 {
            for collider in active {
                if let push = collider.separation(for: p, radius: radius) {
                    p += push
                }
            }
        }
        let limit = boundaryRadius - radius
        if p.length > limit {
            p = p.normalizedOrZero * limit
        }
        return p
    }

    /// The named zone containing `point`, if any (smallest wins, so the village beats the forest).
    public func zone(at point: Vec2) -> Zone? {
        zones.filter { $0.center.distance(to: point) <= $0.radius }.min { $0.radius < $1.radius }
    }

    public func placement(of npc: NPCID) -> NPCPlacement? {
        npcs.first { $0.id == npc }
    }

    public func isBlocked(_ point: Vec2, radius: Float) -> Bool {
        if point.length > boundaryRadius - radius { return true }
        return colliders.contains { $0.separation(for: point, radius: radius) != nil }
    }
}

// MARK: - The Mushroom Hollow layout

extension WorldMap {
    /// The forest floor under the giant tree. The trunk is at the origin; +Z is "south",
    /// where Capstone Village sits between two roots.
    public static let mushroomHollow: WorldMap = {
        let trunkRadius: Float = 13

        // Root angles in degrees (0 = +Z). The gap around 0° holds the village.
        let rootAngles: [Float] = [-30, 30, 92, 148, 205, 262]
        let distances: [Float] = [10, 18, 27, 36, 45, 53]
        let radii: [Float] = [3.4, 2.6, 1.9, 1.3, 0.85, 0.5]
        let roots = rootAngles.enumerated().map { index, degrees in
            let angle = degrees * .pi / 180
            let outward = AngleMath.direction(forYaw: angle)
            let side = Vec2(outward.y, -outward.x)
            let points = distances.enumerated().map { i, d in
                // A gentle, deterministic wiggle so roots don't look ruler-straight.
                let wiggle = sin(Float(i) * 1.7 + Float(index) * 2.3) * Float(i) * 0.9
                return outward * d + side * wiggle
            }
            return TreeRoot(points: points, radii: radii)
        }

        let villageCenter = Vec2(0, 36)
        let houseSpots: [(Vec2, Float, Float)] = [
            (Vec2(-7.5, 28), 1.2, 3.2),
            (Vec2(7.5, 29), 1.0, 2.8),
            (Vec2(-10, 39), 1.4, 3.6),
            (Vec2(10.5, 40), 1.1, 3.0),
            (Vec2(-4.5, 47), 1.3, 3.4),
            (Vec2(6, 48.5), 1.5, 3.9),
        ]
        let houses = houseSpots.map { position, stemRadius, stemHeight in
            MushroomHouse(
                position: position,
                yaw: AngleMath.yaw(facing: villageCenter - position),
                stemRadius: stemRadius,
                stemHeight: stemHeight,
                capRadius: stemRadius * 2.6
            )
        }

        func areaCenter(degrees: Float, distance: Float) -> Vec2 {
            AngleMath.direction(forYaw: degrees * .pi / 180) * distance
        }

        let glade = areaCenter(degrees: 60, distance: 44)
        let maze = areaCenter(degrees: 120, distance: 46)
        let barkfall = areaCenter(degrees: 176, distance: 47)
        let fen = areaCenter(degrees: 233, distance: 48)
        let bough = areaCenter(degrees: 296, distance: 52)
        let boughSide = Vec2(bough.y, -bough.x).normalizedOrZero

        // The fallen bough: a thick branch lying along the far edge of the owl's arena.
        let fallenBranch = TreeRoot(
            points: [0, 1, 2, 3].map { i in bough + bough.normalizedOrZero * 13 + boughSide * (Float(i) * 6 - 9) },
            radii: [1.8, 1.6, 1.4, 1.0])

        return WorldMap(
            boundaryRadius: 85,
            trunkRadius: trunkRadius,
            trunkCollisionRadius: trunkRadius + 2,
            roots: roots + [fallenBranch],
            houses: houses,
            villageCenter: villageCenter,
            villageRadius: 17,
            playerSpawn: Vec2(0, 37),
            // Zones run clockwise around the trunk, getting tougher as you go.
            mobSpawns: [
                MobSpawnArea(kind: .snail, center: glade, radius: 12, count: 8),
                MobSpawnArea(kind: .slug, center: maze, radius: 12, count: 6),
                MobSpawnArea(kind: .beetle, center: barkfall, radius: 12, count: 6),
                MobSpawnArea(kind: .sporeBeast, center: fen, radius: 12, count: 5),
            ],
            npcs: [
                NPCPlacement(id: .elderMorel, position: villageCenter + Vec2(-3.2, -2.5), yaw: 0.6),
                NPCPlacement(id: .chanterelle, position: villageCenter + Vec2(3.6, -1.5), yaw: -0.9),
                NPCPlacement(id: .shiitake, position: villageCenter + Vec2(0.5, -6), yaw: 0.1),
            ],
            zones: [
                Zone(name: "Capstone Village", center: villageCenter, radius: 17, levels: nil),
                Zone(name: "Dewleaf Glade", center: glade, radius: 17, levels: 1...4),
                Zone(name: "Root Maze", center: maze, radius: 17, levels: 3...7),
                Zone(name: "Barkfall Hollow", center: barkfall, radius: 17, levels: 7...11),
                Zone(name: "Spore Fen", center: fen, radius: 17, levels: 10...15),
                Zone(name: "The Great Bough", center: bough, radius: 17, levels: 15...20),
                Zone(name: "The Forest Floor", center: .zero, radius: 200, levels: nil),
            ],
            bossArena: BossArena(kind: .owl, center: bough, radius: 14, perch: bough + bough.normalizedOrZero * 4)
        )
    }()
}
