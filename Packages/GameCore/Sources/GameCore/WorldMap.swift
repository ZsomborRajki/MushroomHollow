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

/// A named region, shown in the HUD and on the map.
public struct Zone: Codable, Sendable {
    public let name: String
    public let center: Vec2
    public let radius: Float
    /// Suggested level range, for the HUD. nil: nothing hunts here.
    public let levels: ClosedRange<Int>?
    /// One line about the place, for the map and the arrival banner.
    public let blurb: String?

    public init(name: String, center: Vec2, radius: Float, levels: ClosedRange<Int>?, blurb: String? = nil) {
        self.name = name
        self.center = center
        self.radius = radius
        self.levels = levels
        self.blurb = blurb
    }
}

/// A wooden sign at the edge of a hunting field (or the town gate): what lives there, and how tough it is.
public struct Signpost: Codable, Sendable {
    public let position: Vec2
    /// The way its readable side faces.
    public let yaw: Float
    public let title: String
    public let levels: ClosedRange<Int>?

    public init(position: Vec2, yaw: Float, title: String, levels: ClosedRange<Int>?) {
        self.position = position
        self.yaw = yaw
        self.title = title
        self.levels = levels
    }
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
    /// Roughly one mob in this many comes after players on its own (dungeons are meaner than fields).
    public var aggressiveShare = GameSimulation.aggressiveShare
}

/// Static layout of the world. Both the simulation (collision, spawns) and the client
/// (geometry, the map screen) build from this, so they always agree.
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
    public let terrain: Terrain
    public let trails: [Trail]
    public let plants: [Plant]
    public let boulders: [Boulder]
    public let twigs: [Twig]
    /// The town's plaza fountain.
    public let fountain: Disc?
    public let signposts: [Signpost]
    /// Named places exploration quests send you to.
    public let landmarks: [Landmark]
    public let colliders: [Collider]
    /// Too deep to walk (flyers and gliders pass over).
    public let waterColliders: [Collider]
    private let grid: ColliderGrid
    private let waterGrid: ColliderGrid

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
        bossArena: BossArena? = nil,
        terrain: Terrain = Terrain(),
        trails: [Trail] = [],
        plants: [Plant] = [],
        boulders: [Boulder] = [],
        twigs: [Twig] = [],
        fountain: Disc? = nil,
        signposts: [Signpost] = [],
        landmarks: [Landmark] = []
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
        self.terrain = terrain
        self.trails = trails
        self.plants = plants
        self.boulders = boulders
        self.twigs = twigs
        self.fountain = fountain
        self.signposts = signposts
        self.landmarks = landmarks

        var colliders = Self.structureColliders(trunkCollisionRadius: trunkCollisionRadius, roots: roots, houses: houses, npcs: npcs,
                                                fountain: fountain, signposts: signposts)
        colliders += boulders.map(\.collider)
        colliders += twigs.map(\.collider)
        colliders += terrain.plateaus.flatMap(\.cliffColliders)
        for plant in plants where plant.collisionRadius > 0 {
            colliders.append(.circle(center: plant.position, radius: plant.collisionRadius))
        }
        self.colliders = colliders
        waterColliders = terrain.lakes.flatMap(\.deepWater)
        grid = ColliderGrid(colliders: colliders, extent: boundaryRadius + 20)
        waterGrid = ColliderGrid(colliders: waterColliders, extent: boundaryRadius + 20)
    }

    /// The trunk (always first), roots, houses, NPCs, the fountain, and signposts.
    private static func structureColliders(trunkCollisionRadius: Float, roots: [TreeRoot], houses: [MushroomHouse],
                                           npcs: [NPCPlacement], fountain: Disc? = nil,
                                           signposts: [Signpost] = []) -> [Collider] {
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
        if let fountain {
            colliders.append(.circle(center: fountain.center, radius: fountain.radius))
        }
        for sign in signposts {
            colliders.append(.circle(center: sign.position, radius: 0.2))
        }
        return colliders
    }

    /// Roots, rocks, stalks, houses, and NPCs are shorter than this; above it only the trunk is in the way.
    public static let obstacleHeight: Float = 6
    /// Below this altitude deep water blocks you; a glider hovers at `waterHoverAltitude` over it.
    public static let wadeAltitude: Float = 0.5
    public static let waterHoverAltitude: Float = 1

    /// Pushes a circle out of every collider and back inside the world boundary.
    /// Above `obstacleHeight` only the trunk (always the first collider) blocks; deep water only
    /// blocks below `wadeAltitude`.
    public func resolve(_ point: Vec2, radius: Float, altitude: Float = 0) -> Vec2 {
        var p = point
        let nearby = altitude > Self.obstacleHeight ? [0] : grid.candidates(near: point, radius: radius + 1)
        let water = altitude < Self.wadeAltitude ? waterGrid.candidates(near: point, radius: radius + 1) : []
        for _ in 0..<2 {
            for index in nearby {
                if let push = colliders[index].separation(for: p, radius: radius) {
                    p += push
                }
            }
            for index in water {
                if let push = waterColliders[index].separation(for: p, radius: radius) {
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

    /// Whether something walking there would overlap an obstacle, deep water, or the edge of the world.
    public func isBlocked(_ point: Vec2, radius: Float) -> Bool {
        if point.length > boundaryRadius - radius { return true }
        if isOverDeepWater(point, radius: radius) { return true }
        return grid.candidates(near: point, radius: radius).contains { colliders[$0].separation(for: point, radius: radius) != nil }
    }

    /// Too deep to wade here.
    public func isOverDeepWater(_ point: Vec2, radius: Float = 0) -> Bool {
        waterGrid.candidates(near: point, radius: radius).contains { waterColliders[$0].separation(for: point, radius: radius) != nil }
    }

    /// Ground height (meters) at a point.
    public func groundHeight(at point: Vec2) -> Float {
        terrain.height(at: point)
    }

    /// Where something standing, swimming, or hovering at altitude 0 sits: the ground, or a lake's surface.
    public func surfaceHeight(at point: Vec2) -> Float {
        terrain.surfaceHeight(at: point)
    }
}

// MARK: - The Mushroom Hollow layout

extension WorldMap {
    /// The forest floor under the giant tree: a wide, shallow bowl. The trunk is at the origin;
    /// +Z is "south", where Capstone Town sits between two roots. An inner ring of hunting
    /// grounds lies between the roots, an outer ring on a trail at radius 190, and Dewdrop Lake
    /// glitters between the two, southwest of the village. Past the outer ring, before the rim
    /// climbs away, lies the wild fringe: no hunting grounds, just places worth the walk.
    public static let mushroomHollow: WorldMap = {
        let trunkRadius: Float = 13
        let boundary: Float = 340

        // Root angles in degrees (0 = +Z). The gap around 0° holds the village.
        let rootAngles: [Float] = [-30, 30, 92, 148, 205, 262]
        let distances: [Float] = [10, 19, 29, 40, 51, 62]
        let radii: [Float] = [3.4, 2.7, 2.0, 1.4, 0.9, 0.55]
        let roots = rootAngles.enumerated().map { index, degrees in
            let angle = degrees * .pi / 180
            let outward = AngleMath.direction(forYaw: angle)
            let side = Vec2(outward.y, -outward.x)
            let points = distances.enumerated().map { i, d in
                // A gentle, deterministic wiggle so roots don't look ruler-straight.
                let wiggle = sin(Float(i) * 1.7 + Float(index) * 2.3) * Float(i) * 1.1
                return outward * d + side * wiggle
            }
            return TreeRoot(points: points, radii: radii)
        }

        func at(_ degrees: Float, _ distance: Float) -> Vec2 {
            AngleMath.direction(forYaw: degrees * .pi / 180) * distance
        }

        // Capstone Town, nestled between the two southern roots: a ring of mushroom houses around a
        // fountain plaza, with every shop and service facing the fountain (like Flarine's square).
        let villageCenter = Vec2(0, 44)
        let villageRadius: Float = 22
        let plaza = villageCenter + Vec2(0, 2)
        let fountain = Disc(center: plaza, radius: 2.2)
        func around(_ center: Vec2, _ degrees: Float, _ distance: Float) -> Vec2 { center + at(degrees, distance) }
        let houseSpots: [(degrees: Float, distance: Float, stemRadius: Float, stemHeight: Float)] = [
            (38, 17, 1.2, 3.2), (72, 16, 1.0, 2.8), (108, 15.5, 1.4, 3.6), (148, 14, 1.1, 3.0),
            (212, 14, 1.3, 3.4), (252, 15.5, 1.5, 3.9), (288, 16, 1.1, 3.1), (322, 17, 1.25, 3.3),
        ]
        let houses = houseSpots.map { spot in
            let position = around(villageCenter, spot.degrees, spot.distance)
            return MushroomHouse(
                position: position,
                yaw: AngleMath.yaw(facing: plaza - position),
                stemRadius: spot.stemRadius,
                stemHeight: spot.stemHeight,
                capRadius: spot.stemRadius * 2.6
            )
        }
        // Around the fountain, clockwise from the elder's seat on the trunk side.
        let npcSpots: [(NPCID, Float, Float)] = [
            (.elderMorel, 180, 7.5), (.chanterelle, 135, 7.5), (.oyster, 90, 7.5), (.enoki, 52, 7.5),
            (.maitake, 18, 10), (.truffle, 312, 7.5), (.shiitake, 270, 7.5), (.porcini, 225, 7.5),
        ]
        let npcs = npcSpots.map { id, degrees, distance in
            let position = around(plaza, degrees, distance)
            return NPCPlacement(id: id, position: position, yaw: AngleMath.yaw(facing: plaza - position))
        }

        // The inner ring, between the roots.
        let innerDistance: Float = 74, innerRadius: Float = 32
        let innerAngles: [Float] = [60, 120, 176, 233, 296]
        let glade = at(60, innerDistance)
        let maze = at(120, innerDistance)
        let barkfall = at(176, innerDistance)
        let fen = at(233, innerDistance)
        let bough = at(296, innerDistance)
        let boughSide = Vec2(bough.y, -bough.x).normalizedOrZero

        // The outer ring: open forest floor past the root tips, clockwise from beside the village.
        let outerDistance: Float = 190, outerRadius: Float = 44
        let meadow = at(28, outerDistance)
        let creek = at(82, outerDistance)
        let thicket = at(136, outerDistance)
        let ridge = at(190, outerDistance)
        let briars = at(244, outerDistance)
        let grove = at(312, outerDistance)

        /// Two species share each hunting ground, each in its own half so they only mingle in the middle.
        /// The grounds are wide and the mobs few, so you usually meet them one at a time.
        func pair(_ first: MobKind, _ second: MobKind, at center: Vec2, counts: (Int, Int),
                  radius: Float, spread: Float) -> [MobSpawnArea] {
            let side = Vec2(center.y, -center.x).normalizedOrZero * spread
            return [MobSpawnArea(kind: first, center: center - side, radius: radius, count: counts.0),
                    MobSpawnArea(kind: second, center: center + side, radius: radius, count: counts.1)]
        }
        /// Flaris-style fields: each species gets a patch of its own, walked in level order: two near the
        /// roots, one further out between them.
        func fields(_ kinds: [MobKind], around degrees: Float) -> [MobSpawnArea] {
            let spots = kinds.count == 3
                ? [at(degrees - 16, 64), at(degrees, 84), at(degrees + 16, 64)]
                : [at(degrees - 14, 70), at(degrees + 14, 70)]
            return zip(kinds, spots).map { MobSpawnArea(kind: $0, center: $1, radius: 11, count: 6) }
        }
        func outer(_ first: MobKind, _ second: MobKind, at center: Vec2, counts: (Int, Int) = (7, 7)) -> [MobSpawnArea] {
            pair(first, second, at: center, counts: counts, radius: 24, spread: 17)
        }

        // The Sunken Warren: a basin walled by cliffs past Pinecone Rise, with one ramp down from the
        // ring road. The Hollow's dungeon: moles on one side, rootcrawlers on the other, half of them
        // aggressive, and Moldywarp at the back.
        let warren = at(206, 236)
        let warrenIn = (-warren).normalizedOrZero
        let warrenSide = Vec2(warrenIn.y, -warrenIn.x)
        let warrenBasin = Plateau(name: "The Sunken Warren", center: warren, radius: 20, height: -7, cliffWidth: 5,
                                  ramps: [Plateau.Ramp(yaw: AngleMath.yaw(facing: warrenIn), width: 7, length: 22)])
        var warrenSpawns = [
            MobSpawnArea(kind: .delverMole, center: warren + warrenSide * 8 + warrenIn * 2, radius: 8, count: 6),
            MobSpawnArea(kind: .rootcrawler, center: warren - warrenSide * 8 + warrenIn * 2, radius: 8, count: 6),
        ]
        for i in warrenSpawns.indices { warrenSpawns[i].aggressiveShare = 2 }
        warrenSpawns.append(MobSpawnArea(kind: .moldywarp, center: warren - warrenIn * 10, radius: 4, count: 1))

        // Cliff-walled mesas: Barkfall Bluff (a ramp along its side) and Sunstone Mesa out on the fringe.
        let bluff = at(176, 118)
        let bluffMesa = Plateau(name: "Barkfall Bluff", center: bluff, radius: 11, height: 6, cliffWidth: 5,
                                ramps: [Plateau.Ramp(yaw: 266 * .pi / 180, width: 6, length: 18)])
        let mesa = at(130, 244)
        let sunstoneMesa = Plateau(name: "Sunstone Mesa", center: mesa, radius: 13, height: 7, cliffWidth: 5,
                                   ramps: [Plateau.Ramp(yaw: AngleMath.yaw(facing: -mesa), width: 6, length: 20)])

        // Zones run clockwise around the trunk, getting tougher as you go.
        let mobSpawns: [MobSpawnArea] = [
            fields([.snail, .ladybug, .aphid], around: innerAngles[0]),
            fields([.slug, .pillBug, .earthworm], around: innerAngles[1]),
            fields([.beetle, .acornling, .cricket], around: innerAngles[2]),
            fields([.sporeBeast, .bogFrog], around: innerAngles[3]),
            outer(.fuzzbee, .puffweed, at: meadow),
            outer(.mossTurtle, .emberNewt, at: creek),
            outer(.weaverSpider, .duskMoth, at: thicket),
            outer(.hedgehog, .coneKnight, at: ridge),
            outer(.mantis, .thornrose, at: briars),
            outer(.grumblecap, .stagBeetle, at: grove, counts: (6, 6)),
            warrenSpawns,
        ].flatMap { $0 }

        // The fallen bough: a thick branch lying along the far edge of the owl's arena.
        let fallenBranch = TreeRoot(
            points: [0, 1, 2, 3].map { i in bough + bough.normalizedOrZero * 13 + boughSide * (Float(i) * 6 - 9) },
            radii: [1.8, 1.6, 1.4, 1.0])
        let arena = BossArena(kind: .owl, center: bough, radius: 14, perch: bough + bough.normalizedOrZero * 4)

        // Dewdrop Lake: a lobed pond southwest of the village, beside the road south, fed by Silverthread
        // Brook, which winds down from a spring on the fringe and crosses the outer ring road at a ford.
        let pond = [
            Disc(center: Vec2(-44, 134), radius: 24),
            Disc(center: Vec2(-63, 118), radius: 16),
            Disc(center: Vec2(-27, 151), radius: 14),
            Disc(center: Vec2(-57, 152), radius: 15),
        ]
        let spring = at(-34, 258)
        let ford = at(-24.4, outerDistance)
        let brook = Lake.brook(along: [at(-19.5, 168), at(-22, 180), at(-24.5, 190), at(-26, 200), at(-25, 212),
                                       at(-28, 225), at(-31, 238), at(-33, 250), spring],
                               width: 7.6, fords: [ford])
        let lake = Lake(name: "Dewdrop Lake", discs: pond + brook + [Disc(center: spring, radius: 7)],
                        waterLevel: -0.3, depth: 3, fords: [ford])
        let lakeBounds = Lake(name: "Dewdrop Lake", discs: pond, waterLevel: -0.3, depth: 3).bounds

        // The wild fringe, between the outer ring and the rim: one place to find every 50-odd degrees.
        let fringeDistance: Float = 250
        let rimview = at(0, 262)
        let dell = at(55, fringeDistance)
        let peak = at(100, 252)
        let tarnLake = Lake(name: "Moonwell Tarn", discs: [
            Disc(center: at(163, fringeDistance), radius: 15),
            Disc(center: at(157, 262), radius: 9),
            Disc(center: at(170, 243), radius: 8),
        ], waterLevel: 0.2, depth: 3.5)
        let log = at(222, 254)
        let stones = at(283, fringeDistance)

        // Hollowlog Crossing: a fallen limb as long as a street, lying along the fringe.
        let logAlong = Vec2(log.y, -log.x).normalizedOrZero
        let logOutward = log.normalizedOrZero
        let logSpots: [Float] = [-20, -7, 6, 19]
        let hollowLog = TreeRoot(
            points: logSpots.map { t -> Vec2 in
                let bow: Float = sin(t * 0.09) * 2
                return log + logAlong * t + logOutward * bow
            },
            radii: [2.5, 2.3, 2.0, 1.5])
        // Mossring Stones: nine standing stones round a mossy clearing, a gap facing the path in
        // and the ninth fallen over across the ring from it.
        let towardTrunk = AngleMath.yaw(facing: -stones)
        let standingStones = (0..<9).map { i -> Boulder in
            let angle: Float = towardTrunk + (Float(i) + 0.5) / 9 * 2 * .pi
            let spot = stones + AngleMath.direction(forYaw: angle) * 10.5
            let fallen = i == 4
            let height: Float = fallen ? 2.2 : 4.4 + Float(i % 3) * 0.5
            return Boulder(position: spot, radius: fallen ? 1.2 : 1.55, height: height,
                           yaw: angle, variant: UInt32(i) &* 2_654_435_761)
        }

        let landmarks = [
            Landmark(id: .cattailShore, position: Vec2(-17, 132), radius: 7),
            Landmark(id: .sunnyHillock, position: at(18, 150)),
            Landmark(id: .cloverKnoll, position: at(92, 112)),
            Landmark(id: .oldKnot, position: at(176, 23), radius: 7),
            Landmark(id: .barkfallBluff, position: at(176, 118)),
            Landmark(id: .foxgloveHill, position: at(217, 145)),
            Landmark(id: .owlwatchHill, position: at(278, 145)),
            Landmark(id: .fallenBough, position: at(296, 82), radius: 7),
            Landmark(id: .rimviewBluff, position: at(0, 252)),
            Landmark(id: .glimmerDell, position: dell, radius: 9),
            Landmark(id: .windwhistlePeak, position: peak),
            // On the tarn's inner shore, where the path comes down.
            Landmark(id: .moonwellTarn, position: at(163, fringeDistance - 18), radius: 7),
            Landmark(id: .hollowlogCrossing, position: log - log.normalizedOrZero * 6),
            Landmark(id: .mossringStones, position: stones, radius: 9),
            Landmark(id: .silverthreadSpring, position: at(-31.2, 258)),
            Landmark(id: .sunstoneMesa, position: mesa, radius: 9),
        ]

        // Mossback Creek: a dry creek bed across the hunting ground.
        let creekAlong = Vec2(creek.y, -creek.x).normalizedOrZero
        let creekBed = (-6...6).map { i in
            Hill(center: creek + creekAlong * Float(i) * 7 + Vec2(creekAlong.y, -creekAlong.x) * sin(Float(i) * 0.8) * 3,
                 radius: 7, height: -1.1)
        }
        var hills: [Hill] = [
            Hill(center: ridge, radius: 58, height: 9),                 // Pinecone Rise
            Hill(center: at(176, 222), radius: 30, height: 5),
            Hill(center: grove, radius: 42, height: 3.5),               // Stagshade Grove's mound
            Hill(center: thicket, radius: 46, height: -2.4),            // Silkshade Thicket's hollow
            Hill(center: fen, radius: 30, height: -1.4),                // Spore Fen's bog
            Hill(center: meadow, radius: 46, height: 1.6),
            Hill(center: at(244, 178), radius: 16, height: 3),          // Briar knolls
            Hill(center: at(252, 206), radius: 14, height: 3.5),
            Hill(center: at(236, 202), radius: 12, height: 2.5),
            Hill(center: at(92, 112), radius: 18, height: 4),
            Hill(center: at(18, 150), radius: 20, height: 3.5),
            // The wild fringe.
            Hill(center: rimview, radius: 24, height: 7),               // Rimview Bluff
            Hill(center: dell, radius: 22, height: -2.6),               // Glimmer Dell
            Hill(center: peak, radius: 34, height: 15),                 // Windwhistle Peak
        ] + creekBed
        // Wooded hills between the rings.
        for (i, degrees) in [55, 109, 163, 217, 278].enumerated() {
            hills.append(Hill(center: at(Float(degrees), 145), radius: 22 + Float(i % 3) * 4, height: 4 + Float(i % 2) * 2.5))
        }
        // Low rises between the fringe's places, so the walk out there isn't flat.
        for (i, degrees) in [30, 250, 322].enumerated() {
            hills.append(Hill(center: at(Float(degrees), 244), radius: 16 + Float(i % 2) * 5, height: 3 + Float(i % 3)))
        }
        // Lumps along the rim, so the skyline isn't a perfect bowl.
        for i in 0..<12 {
            let degrees = Float(i) * 30 + 11
            hills.append(Hill(center: at(degrees, 312 + Float(i % 3) * 12), radius: 28 + Float(i % 4) * 5, height: 7 + Float((i * 7) % 5) * 2))
        }
        let terrain = Terrain(
            hills: hills,
            flats: [
                FlatArea(center: .zero, radius: 22, fade: 18, height: 0),
                FlatArea(center: villageCenter, radius: villageRadius + 2, fade: 14, height: 0),
                FlatArea(center: arena.center, radius: arena.radius + 1, fade: 10, height: 0.4),
                FlatArea(center: stones, radius: 13, fade: 10, height: 0.5),
            ],
            lakes: [lake, tarnLake],
            plateaus: [bluffMesa, sunstoneMesa, warrenBasin],
            rimStart: 272, rimEnd: boundary - 2, rimHeight: 20)

        // Dirt roads: south from the village past the lake to the outer ring, a loop just past
        // the root tips with a spur into each inner hunting ground, and the outer ring itself.
        let plazaRing = Trail(points: (0..<24).map { around(plaza, Float($0) * 15, 5.2) }, width: 3.4, closed: true)
        var trails = [
            plazaRing,
            Trail(points: [plaza + Vec2(0, 5), Vec2(0, 66), Vec2(2, 80), Vec2(-1, 110), Vec2(3, 150), Vec2(0, outerDistance)],
                  width: 3.2),
            // Out of the town gate and round the root tips: east to the first fields, west toward the lake.
            Trail(points: [Vec2(1, 60), Vec2(14, 62), Vec2(28, 62), at(49, 50)], width: 2.4),
            Trail(points: [Vec2(-1, 60), Vec2(-14, 62), Vec2(-30, 64), Vec2(-44, 72)], width: 2.2),
            Trail(points: [Vec2(1, 128), Vec2(-8, 131), Vec2(-15, 134)], width: 2.2),
            Trail.ring(radius: 100, width: 2.8),
            Trail.ring(radius: outerDistance, segments: 128, width: 3.4),
        ]
        for degrees in innerAngles {
            trails.append(Trail(points: [at(degrees, 100), at(degrees, 90), at(degrees + 2, innerDistance)], width: 2.4))
        }
        // Footpaths from the outer ring out to each place on the fringe (the south road carries on to Rimview Bluff).
        trails.append(Trail(points: [Vec2(0, outerDistance), at(-1.5, 215), at(0.5, 234), at(0, 247)], width: 2.8))
        // Each ends short of its place: below the peak, on the tarn's shore, before the log and the stone ring.
        let spurs: [(place: Vec2, shortBy: Float)] = [(dell, 10), (peak, 10), (tarnLake.discs[0].center, 20), (log, 9), (stones, 12),
                                                      (mesa, 31)]
        for (place, shortBy) in spurs {
            let degrees: Float = AngleMath.yaw(facing: place) * 180 / .pi
            let end = place.length - shortBy
            trails.append(Trail(points: [at(degrees, outerDistance), at(degrees + 1.5, (outerDistance + end) / 2), at(degrees, end)],
                                width: 2))
        }

        // A path up each mesa's ramp (which also keeps it clear of scenery).
        for plateau in [bluffMesa, sunstoneMesa] {
            for ramp in plateau.ramps {
                let along = AngleMath.direction(forYaw: ramp.yaw)
                trails.append(Trail(points: [plateau.center + along * (plateau.radius + ramp.length + 2),
                                             plateau.center + along * (plateau.radius - 4)], width: 2.4))
            }
        }
        // Up the brook's east bank to the spring, and down the Warren's ramp.
        trails.append(Trail(points: [at(-20, outerDistance), at(-21, 212), at(-24.5, 232), at(-28.5, 252)], width: 2))
        trails.append(Trail(points: [at(206, outerDistance), warren + warrenIn * 36, warren + warrenIn * 24, warren + warrenIn * 14],
                            width: 2.6))

        // Each place on the fringe is its own little zone, so arriving gets a banner.
        let fringeZones: [(LandmarkID, Vec2, Float)] = [
            (.rimviewBluff, rimview, 22), (.glimmerDell, dell, 22), (.windwhistlePeak, peak, 28),
            (.moonwellTarn, tarnLake.bounds.center, tarnLake.bounds.radius + 6), (.hollowlogCrossing, log, 24),
            (.mossringStones, stones, 20),
            (.silverthreadSpring, spring, 16), (.sunstoneMesa, mesa, 24),
        ]
        let zones = [
            Zone(name: "Capstone Town", center: villageCenter, radius: villageRadius, levels: nil,
                 blurb: "Shops, the request board, and a fountain to rest by"),
            Zone(name: "Dewleaf Glade", center: glade, radius: innerRadius, levels: 1...4,
                 blurb: "Daisies, clover, and sleepy snails"),
            Zone(name: "Root Maze", center: maze, radius: innerRadius, levels: 4...8,
                 blurb: "Ferns and bluebells between the roots"),
            Zone(name: "Barkfall Hollow", center: barkfall, radius: innerRadius, levels: 8...12,
                 blurb: "Bark litter, fallen twigs, and chirping"),
            Zone(name: "Spore Fen", center: fen, radius: innerRadius, levels: 12...15,
                 blurb: "A glowing purple bog"),
            Zone(name: "The Great Bough", center: bough, radius: innerRadius, levels: 15...20,
                 blurb: "The Hollow Owl hunts here at night"),
            Zone(name: "Dewdrop Lake", center: lakeBounds.center, radius: lakeBounds.radius + 6, levels: nil,
                 blurb: "Lily pads and cattails. Glide across on a seed"),
            Zone(name: "Buttercup Meadow", center: meadow, radius: outerRadius, levels: 14...18,
                 blurb: "Sunny, buzzing, full of dandelions"),
            Zone(name: "Mossback Creek", center: creek, radius: outerRadius, levels: 17...21,
                 blurb: "A dry creek bed and smouldering stones"),
            Zone(name: "Silkshade Thicket", center: thicket, radius: outerRadius, levels: 20...24,
                 blurb: "A dim hollow strung with webs"),
            Zone(name: "Pinecone Rise", center: ridge, radius: outerRadius, levels: 23...27,
                 blurb: "A needle-strewn hill of pine saplings"),
            Zone(name: "Briar Tangle", center: briars, radius: outerRadius, levels: 26...30,
                 blurb: "Brambles, roses, and orchids with claws"),
            Zone(name: "Stagshade Grove", center: grove, radius: outerRadius, levels: 28...30,
                 blurb: "Glowcaps and rotting logs"),
            Zone(name: "The Sunken Warren", center: warren, radius: 27, levels: 28...32,
                 blurb: "The Hollow's dungeon. Half of what lives down here bites first"),
            Zone(name: "The Forest Floor", center: .zero, radius: 400, levels: nil,
                 blurb: "Wild forest between the hunting grounds"),
        ] + fringeZones.map { place, center, radius in
            Zone(name: place.name, center: center, radius: radius, levels: nil, blurb: place.blurb)
        }

        // A signpost at the edge of every field, on the side facing the trunk road, and one at the town gate.
        var signposts = mobSpawns.filter { !$0.kind.isFieldBoss }.map { area in
            let inward = (-area.center).normalizedOrZero
            let position = area.center + inward * (area.radius + 1.5)
            let level = area.kind.stats.level
            return Signpost(position: position, yaw: AngleMath.yaw(facing: inward), title: area.kind.pluralName,
                            levels: level...(level + 1))
        }
        signposts.append(Signpost(position: Vec2(-3.2, 64), yaw: 0, title: "Capstone Town", levels: nil))
        signposts.append(Signpost(position: warren + warrenIn * 43 + warrenSide * 5.5, yaw: AngleMath.yaw(facing: warrenIn),
                                  title: "The Sunken Warren", levels: 28...32))
        // Every landmark has a sign, so you know you've arrived (the Old Knot's faces away from the trunk).
        // It stands beside the way in, not on the path.
        for place in landmarks {
            let facing = place.id == .oldKnot ? place.position : -place.position
            let offset = place.id == .windwhistlePeak || place.id == .mossringStones || place.id == .glimmerDell
                ? Vec2.zero : Vec2(facing.y, -facing.x).normalizedOrZero * 2.5
            signposts.append(Signpost(position: place.position + offset, yaw: AngleMath.yaw(facing: facing),
                                      title: place.id.name, levels: nil))
        }

        let fallenLimbs = [fallenBranch, hollowLog]
        let layout = SceneryLayout(
            boundaryRadius: boundary,
            blockers: structureColliders(trunkCollisionRadius: trunkRadius + 2, roots: roots + fallenLimbs,
                                         houses: houses, npcs: npcs, fountain: fountain, signposts: signposts)
                + standingStones.map(\.collider) + terrain.plateaus.flatMap(\.cliffColliders),
            keepClear: [Disc(center: villageCenter, radius: villageRadius + 3), Disc(center: arena.center, radius: arena.radius + 2),
                        Disc(center: Vec2(0, 64), radius: 6), Disc(center: stones, radius: 13)]
                + landmarks.map { Disc(center: $0.position, radius: 4) }
                + mobSpawns.map { Disc(center: $0.center, radius: 2.5) },
            trails: trails, terrain: terrain, spawns: mobSpawns,
            biomes: [
                (Disc(center: glade, radius: innerRadius), .glade), (Disc(center: maze, radius: innerRadius), .maze),
                (Disc(center: barkfall, radius: innerRadius), .barkfall), (Disc(center: fen, radius: innerRadius), .fen),
                (Disc(center: bough, radius: innerRadius), .bough),
                (Disc(center: meadow, radius: outerRadius), .meadow), (Disc(center: creek, radius: outerRadius), .creek),
                (Disc(center: thicket, radius: outerRadius), .thicket), (Disc(center: ridge, radius: outerRadius), .rise),
                (Disc(center: briars, radius: outerRadius), .briars), (Disc(center: grove, radius: outerRadius), .grove),
                (Disc(center: dell, radius: 24), .dell), (Disc(center: peak, radius: 30), .peak),
                (Disc(center: stones, radius: 26), .stones),
                (Disc(center: warren, radius: 27), .warren), (Disc(center: mesa, radius: 18), .peak),
                (Disc(center: bluff, radius: 12), .peak),
            ])
        let scenery = layout.grow(seed: 0x5EED_F0E5)

        return WorldMap(
            boundaryRadius: boundary,
            trunkRadius: trunkRadius,
            trunkCollisionRadius: trunkRadius + 2,
            roots: roots + fallenLimbs,
            houses: houses,
            villageCenter: villageCenter,
            villageRadius: villageRadius,
            playerSpawn: plaza + Vec2(0, 4),
            mobSpawns: mobSpawns,
            npcs: npcs,
            zones: zones,
            bossArena: arena,
            terrain: terrain,
            trails: trails,
            plants: scenery.plants,
            boulders: scenery.boulders + standingStones,
            twigs: scenery.twigs,
            fountain: fountain,
            signposts: signposts,
            landmarks: landmarks
        )
    }()
}
