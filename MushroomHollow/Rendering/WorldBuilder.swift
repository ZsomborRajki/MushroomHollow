import GameCore
import RealityKit
import UIKit

/// The static world, built from the shared `WorldMap`.
struct BuiltWorld {
    let root: Entity
    /// Switches far scenery off; call `update` as the camera moves.
    let culler: SceneryCuller
    /// The painted forest floor, top-down (the map screen draws it too).
    let groundPainting: UIImage
}

/// Builds the static world from the shared `WorldMap`, so what you see always matches what
/// the simulation collides with. Scenery is merged into a few big meshes per chunk of ground
/// (see `SceneryBatch`), and everything sits on the terrain's height.
@MainActor
enum WorldBuilder {
    /// Where scenery chunks stop drawing (the haze hides them well before this).
    static let sceneryDrawDistance: Float = 210
    static let detailDrawDistance: Float = 115
    static let grassDrawDistance: Float = 62

    static func build(_ map: WorldMap) -> BuiltWorld {
        let world = Entity()
        world.name = "World"
        var random = SeededRandom(seed: 0xF0_4E57)
        let culler = SceneryCuller()

        let painting = TerrainBuilder.addGround(map, to: world)
        TerrainBuilder.addWater(map, to: world)

        let atlas = ColorAtlas()
        let landmarks = SceneryBatch(atlas: atlas, chunkSize: 80)
        let scenery = SceneryBatch(atlas: atlas, chunkSize: 80)
        let details = SceneryBatch(atlas: atlas, chunkSize: 48)

        addTrunk(map, to: landmarks, random: &random)
        for root in map.roots { addRoot(root, map: map, to: landmarks) }
        addDistantTrees(map, to: landmarks, random: &random)
        for house in map.houses { addHouse(house, map: map, to: scenery, random: &random) }
        for plant in map.plants { FloraBuilder.build(plant, map: map, into: scenery) }
        for boulder in map.boulders { FloraBuilder.build(boulder, map: map, into: scenery) }
        for twig in map.twigs { FloraBuilder.build(twig, map: map, into: scenery) }
        addGroundLitter(map, to: details, random: &random)
        addZoneDressing(map, to: details, lights: world, random: &random)
        if let arena = map.bossArena { addBossArena(arena, map: map, to: details, lights: world, random: &random) }

        culler.add(landmarks.build(into: world, name: "Landmarks"), drawDistance: 850)
        culler.add(scenery.build(into: world, name: "Scenery"), drawDistance: sceneryDrawDistance)
        culler.add(details.build(into: world, name: "Details", castsShadow: false), drawDistance: detailDrawDistance)
        culler.add(TerrainBuilder.addGrass(map, to: world, random: &random), drawDistance: grassDrawDistance)

        addForge(map, to: world)
        TownBuilder.build(map, into: world)
        return BuiltWorld(root: world, culler: culler, groundPainting: painting)
    }

    private static func onGround(_ map: WorldMap, _ p: Vec2, lift: Float = 0) -> SIMD3<Float> {
        [p.x, map.groundHeight(at: p) + lift, p.y]
    }

    // MARK: - The giant tree

    private static let trunkShape = Shapes.lathe([[1, 0.5], [1, -0.5]], segments: 40)
    /// The trunk's feet: wide at the ground, easing into the trunk.
    private static let flareShape = Shapes.lathe([[0.86, 1], [0.88, 0.7], [0.92, 0.45], [0.98, 0.22], [1, 0]], segments: 40)

    private static func addTrunk(_ map: WorldMap, to batch: SceneryBatch, random: inout SeededRandom) {
        batch.anchor = .zero
        let height: Float = 220
        batch.part(trunkShape, Palette.bark, at: [0, height / 2, 0], scale: [map.trunkRadius, height, map.trunkRadius])
        // Flared base; the simulation's trunk collider includes this.
        let flare = map.trunkCollisionRadius + 0.2
        batch.part(flareShape, Palette.bark, at: [0, -0.5, 0], scale: [flare, 9, flare])

        for i in 0..<28 {
            let angle = Float(i) / 28 * 2 * .pi + random.float(in: -0.05...0.05)
            let d = AngleMath.direction(forYaw: angle) * (map.trunkRadius + 0.1)
            batch.part(Shapes.box, Palette.darkBark, at: [d.x, height / 2, d.y], scale: [random.float(in: 0.5...1.2), height, 0.6],
                       rotation: simd_quatf(angle: angle, axis: [0, 1, 0]))
        }

        // Shelf fungi stepping up the trunk.
        for i in 0..<9 {
            let angle = Float(i) * 2.1 + 0.4
            let y = 6 + Float(i) * 4.5
            let d = AngleMath.direction(forYaw: angle) * (map.trunkRadius + 0.2)
            let size = random.float(in: 1.6...3.0)
            batch.part(Shapes.dome, Palette.shelfFungus, at: [d.x, y, d.y], scale: [size, 0.45, size])
            batch.part(Shapes.disc, Flora.gills, at: [d.x, y - 0.01, d.y], scale: SIMD3(repeating: size),
                       rotation: simd_quatf(angle: .pi, axis: [1, 0, 0]))
        }
    }

    private static func addRoot(_ root: TreeRoot, map: WorldMap, to batch: SceneryBatch) {
        func point3(_ i: Int) -> SIMD3<Float> {
            // Roots rise out of the ground near the trunk and sink as they thin out.
            let lift: Float = i == 0 ? 0.55 : 0.3
            return onGround(map, root.points[i], lift: root.radii[i] * lift)
        }
        for i in 0..<root.points.count {
            batch.anchor = root.points[i]
            batch.sphere(Palette.bark, at: point3(i), radius: root.radii[i])
        }
        for i in 0..<(root.points.count - 1) {
            batch.anchor = root.points[i]
            batch.rod(Palette.bark, from: point3(i), to: point3(i + 1), radius: root.radii[i], endRadius: root.radii[i + 1])
        }
    }

    /// Other giants of the forest, standing far off in the haze past the rim, to show how small we are.
    private static func addDistantTrees(_ map: WorldMap, to batch: SceneryBatch, random: inout SeededRandom) {
        let bark = UIColor(red: 0.24, green: 0.18, blue: 0.13, alpha: 1)
        for i in 0..<9 {
            let angle = Float(i) / 9 * 2 * .pi + random.float(in: -0.2...0.2)
            let spot = AngleMath.direction(forYaw: angle) * random.float(in: 390...520)
            let radius = random.float(in: 9...16)
            let base = onGround(map, spot, lift: -2)
            batch.anchor = spot
            batch.part(trunkShape, bark, at: base + [0, 200, 0], scale: [radius, 400, radius])
            batch.part(flareShape, bark, at: base, scale: [radius * 1.35, radius * 1.2, radius * 1.35])
            for r in 0..<5 {
                let out = AngleMath.direction(forYaw: angle + Float(r) * 1.3 + random.float(in: -0.3...0.3))
                let end = spot + out * radius * random.float(in: 2.5...3.5)
                batch.rod(bark, from: base + [out.x * radius * 0.8, radius * 0.4, out.y * radius * 0.8],
                          to: onGround(map, end, lift: -0.5), radius: radius * 0.3, endRadius: radius * 0.08)
            }
        }
    }

    // MARK: - Village

    private static func addHouse(_ house: MushroomHouse, map: WorldMap, to batch: SceneryBatch, random: inout SeededRandom) {
        batch.anchor = house.position
        let origin = onGround(map, house.position)
        let facing = simd_quatf(angle: house.yaw, axis: [0, 1, 0])
        func local(_ p: SIMD3<Float>) -> SIMD3<Float> { origin + facing.act(p) }

        let h = house.stemHeight
        batch.part(Shapes.cylinder, Palette.stem, at: local([0, h / 2 - 0.2, 0]), scale: [house.stemRadius, h + 0.4, house.stemRadius])
        let capColor = random.unit() < 0.7 ? Palette.capRed : Palette.capBrown
        let capY = h + house.capRadius * 0.12
        batch.sphere(capColor, at: local([0, capY, 0]), radius: house.capRadius, squash: [1, 0.5, 1])
        // Underside so the cap doesn't look hollow from below.
        batch.cylinder(Palette.stem, at: local([0, capY - 0.02, 0]), radius: house.capRadius * 0.97, height: 0.04)

        for _ in 0..<7 {
            let a = random.float(in: 0...(2 * .pi))
            let r = random.float(in: 0.15...0.8) * house.capRadius
            // Sit each spot on the squashed-sphere surface.
            let y = capY + house.capRadius * 0.5 * (1 - (r / house.capRadius) * (r / house.capRadius)).squareRoot()
            let d = AngleMath.direction(forYaw: a) * r
            batch.sphere(Palette.capSpot, at: local([d.x, y, d.y]), radius: random.float(in: 0.22...0.45), squash: [1, 0.35, 1])
        }

        let r = house.stemRadius
        batch.part(Shapes.box, Palette.door, at: local([0, 0.85, r - 0.05]), scale: [0.8, 1.7, 0.2], rotation: facing)
        let side = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        for angle: Float in [-0.9, 0.9] {
            let d = AngleMath.direction(forYaw: angle) * (r - 0.02)
            batch.cylinder(Palette.windowGlow, at: local([d.x, h * 0.62, d.y]), radius: 0.22, height: 0.1,
                           rotation: facing * simd_quatf(angle: angle, axis: [0, 1, 0]) * side, glow: true)
        }
    }

    // MARK: - Small things on the ground

    /// Ankle-high mushrooms, pebbles, acorns, and fallen leaves, everywhere but the roads.
    private static func addGroundLitter(_ map: WorldMap, to batch: SceneryBatch, random: inout SeededRandom) {
        func freeSpot(radius: Float, avoidVillage: Bool = true) -> Vec2? {
            for _ in 0..<10 {
                let p = random.point(inDiscAt: .zero, radius: map.boundaryRadius + 10)
                if p.length < map.trunkCollisionRadius + 1 { continue }
                if map.isBlocked(p, radius: radius) && p.length < map.boundaryRadius { continue }
                if avoidVillage, p.distance(to: map.villageCenter) < map.villageRadius { continue }
                if map.terrain.lakes.contains(where: { $0.signedDistance(to: p) < 1 }) { continue }
                if map.trails.contains(where: { $0.distance(to: p) < $0.width / 2 + radius }) { continue }
                return p
            }
            return nil
        }

        for i in 0..<700 {
            guard let p = freeSpot(radius: 0.4) else { continue }
            batch.anchor = p
            let s = random.float(in: 0.25...0.9)
            let base = onGround(map, p)
            let glow = i % 6 == 0
            let cap = glow ? Palette.glowCap : [Palette.capRed, Palette.capBrown, Palette.capSpot][i % 3]
            batch.cylinder(Palette.stem, at: base + [0, s * 0.3, 0], radius: s * 0.1, height: s * 0.7)
            batch.sphere(cap, at: base + [0, s * 0.65, 0], radius: s * 0.32, squash: [1, 0.5, 1], glow: glow, low: true)
        }

        for i in 0..<160 {
            guard let p = freeSpot(radius: 1.5) else { continue }
            batch.anchor = p
            // Leaves as long as we are tall, lying where they fell.
            let normal = map.terrain.normal(at: p)
            let rotation = simd_quatf(from: [0, 1, 0], to: normal) * simd_quatf(angle: random.float(in: 0...(2 * .pi)), axis: [0, 1, 0])
            let length = random.float(in: 2...4)
            batch.part(Shapes.leaf, i % 3 == 0 ? Palette.leaf : Palette.deadLeaf, at: onGround(map, p, lift: 0.03) - rotation.act([0, 0, length / 2]),
                       scale: [length * 0.55, length, length], rotation: rotation, layer: .foliage)
        }

        for _ in 0..<450 {
            guard let p = freeSpot(radius: 0.3, avoidVillage: false) else { continue }
            batch.anchor = p
            let s = random.float(in: 0.15...0.5)
            batch.sphere(Palette.pebble, at: onGround(map, p, lift: s * 0.2), radius: s, squash: [1, 0.6, random.float(in: 0.8...1.3)],
                         rotation: simd_quatf(angle: random.float(in: 0...(2 * .pi)), axis: [0, 1, 0]), low: true)
        }

        for _ in 0..<90 {
            guard let p = freeSpot(radius: 0.4) else { continue }
            batch.anchor = p
            let base = onGround(map, p)
            let tip = simd_quatf(angle: random.float(in: 0...(2 * .pi)), axis: [0, 1, 0]) * simd_quatf(angle: 1.3, axis: [1, 0, 0])
            batch.sphere(Palette.acornBrown, at: base + [0, 0.22, 0], radius: 0.24, squash: [1, 1.25, 1], rotation: tip, low: true)
            batch.part(Shapes.dome, Palette.acornCap, at: base + [0, 0.22, 0] + tip.act([0, 0.18, 0]), scale: [0.27, 0.16, 0.27], rotation: tip)
        }
    }

    // MARK: - Hunting grounds

    /// Each hunting ground gets its own small dressing (the big plants come from the map).
    private static func addZoneDressing(_ map: WorldMap, to batch: SceneryBatch, lights: Entity, random: inout SeededRandom) {
        for area in map.mobSpawns {
            func spots(_ count: Int, spread: Float = 4, clearance: Float = 0.3) -> [Vec2] {
                (0..<count).compactMap { _ in
                    let p = random.point(inDiscAt: area.center, radius: area.radius + spread)
                    return map.isBlocked(p, radius: clearance) ? nil : p
                }
            }
            func yaw() -> simd_quatf { simd_quatf(angle: random.float(in: 0...(2 * .pi)), axis: [0, 1, 0]) }
            func light(_ color: UIColor, intensity: Float, radius: Float, height: Float) {
                let light = PointLight()
                light.light.color = color
                light.light.intensity = intensity
                light.light.attenuationRadius = radius
                light.position = onGround(map, area.center, lift: height)
                lights.addChild(light)
            }
            let upsideDown = simd_quatf(angle: .pi, axis: [1, 0, 0])
            batch.anchor = area.center

            switch area.kind {
            case .beetle:
                // Barkfall Hollow: slabs of fallen bark.
                for p in spots(22, spread: 3, clearance: 1) {
                    batch.anchor = p
                    let rotation = yaw() * simd_quatf(angle: random.float(in: -0.3...0.3), axis: [1, 0, 0])
                    batch.part(Shapes.box, Palette.darkBark, at: onGround(map, p, lift: 0.1),
                               scale: [random.float(in: 0.6...1.4), 0.25, random.float(in: 1.5...3)], rotation: rotation)
                }

            case .sporeBeast:
                for p in spots(30, spread: 6, clearance: 0.4) {
                    batch.anchor = p
                    let s = random.float(in: 0.4...1.2)
                    let base = onGround(map, p)
                    batch.cylinder(Palette.stem, at: base + [0, s * 0.3, 0], radius: s * 0.08, height: s * 0.7)
                    batch.sphere(UIColor(red: 0.75, green: 0.45, blue: 1, alpha: 1), at: base + [0, s * 0.65, 0], radius: s * 0.3,
                                 squash: [1, 0.45, 1], glow: true, low: true)
                }
                light(UIColor(red: 0.7, green: 0.4, blue: 1, alpha: 1), intensity: 9000, radius: 22, height: 3)

            case .fuzzbee:
                // Knee-high buttercups under the big ones.
                for p in spots(50) {
                    batch.anchor = p
                    let h = random.float(in: 0.5...1.1)
                    let base = onGround(map, p)
                    batch.rod(Palette.dandelionStem, from: base, to: base + [0, h, 0], radius: 0.025)
                    batch.part(Shapes.cone, Palette.beeYellow, at: base + [0, h + 0.05, 0], scale: [0.15, 0.14, 0.15], rotation: upsideDown)
                }

            case .puffweed:
                for (i, p) in spots(24).enumerated() {
                    batch.anchor = p
                    let h = random.float(in: 0.8...1.8)
                    let base = onGround(map, p)
                    batch.rod(Palette.dandelionStem, from: base, to: base + [0, h, 0], radius: 0.03)
                    if i % 2 == 0 {
                        batch.sphere(Palette.puffWhite, at: base + [0, h + 0.2, 0], radius: 0.25, low: true)
                    } else {
                        batch.sphere(Palette.beeYellow, at: base + [0, h + 0.05, 0], radius: 0.22, squash: [1, 0.35, 1], low: true)
                    }
                }

            case .mossTurtle:
                // Mossback Creek: river pebbles and the last few pools along the dry bed.
                let bed = map.terrain.hills.filter { $0.height < 0 && $0.radius < 10 && $0.center.distance(to: area.center) < 50 }
                let water = UIColor(red: 0.45, green: 0.7, blue: 0.85, alpha: 1)
                for (i, dip) in bed.enumerated() {
                    batch.anchor = dip.center
                    if i % 3 == 1 {
                        let rotation = simd_quatf(from: [0, 1, 0], to: map.terrain.normal(at: dip.center))
                        batch.translucent(Shapes.disc, water, opacity: 0.6,
                                          transform: SceneryBatch.transform(at: onGround(map, dip.center, lift: 0.04),
                                                                            scale: [2.2, 1, 1.6] * random.float(in: 0.8...1.3), rotation: rotation))
                    }
                    for _ in 0..<5 {
                        let p = random.point(inDiscAt: dip.center, radius: dip.radius * 0.7)
                        let r = random.float(in: 0.12...0.35)
                        batch.sphere(Palette.pebble, at: onGround(map, p, lift: r * 0.2), radius: r, squash: [1, 0.5, random.float(in: 0.8...1.4)], low: true)
                    }
                }

            case .emberNewt:
                // Scorched stones that still glow.
                for (i, p) in spots(22).enumerated() {
                    batch.anchor = p
                    let r = random.float(in: 0.15...0.35)
                    batch.sphere(i % 3 == 0 ? UIColor(white: 0.3, alpha: 1) : Palette.emberGlow, at: onGround(map, p, lift: r * 0.15),
                                 radius: r, squash: [1, 0.55, 1], glow: i % 3 != 0, low: true)
                }
                light(UIColor(red: 1, green: 0.55, blue: 0.25, alpha: 1), intensity: 6000, radius: 16, height: 2.5)

            case .weaverSpider:
                // Silkshade Thicket: webs strung between reed stalks.
                let vertical = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
                for p in spots(12, clearance: 1.5) {
                    batch.anchor = p
                    let facing = yaw()
                    let side = facing.act([1, 0, 0])
                    let h = random.float(in: 2.2...3.2)
                    let base = onGround(map, p)
                    for s: Float in [-1.4, 1.4] {
                        batch.rod(Palette.thornStem, from: base + side * s - [0, 0.2, 0], to: base + side * s + [0, h, 0], radius: 0.045)
                    }
                    let center = base + [0, h * 0.6, 0]
                    batch.translucent(Shapes.disc, .white, opacity: 0.2,
                                      transform: SceneryBatch.transform(at: center, scale: SIMD3(repeating: 1.25), rotation: facing * vertical))
                    for r: Float in [0.5, 0.85, 1.2] {
                        batch.translucent(ring, .white, opacity: 0.7,
                                          transform: SceneryBatch.transform(at: center, scale: SIMD3(repeating: r), rotation: facing * vertical))
                    }
                }

            case .duskMoth:
                // Night flowers that glow blue and lilac.
                for (i, p) in spots(28).enumerated() {
                    batch.anchor = p
                    let h = random.float(in: 0.4...1)
                    let base = onGround(map, p)
                    batch.rod(Palette.thornStem, from: base, to: base + [0, h, 0], radius: 0.025)
                    batch.part(Shapes.teardrop, i % 2 == 0 ? Palette.spiderGlow : Palette.mothLilac, at: base + [0, h + 0.1, 0],
                               scale: [0.1, 0.12, 0.1], rotation: upsideDown, glow: true)
                }

            case .hedgehog:
                // Pinecone Rise: fallen cones and needle litter.
                for p in spots(18, clearance: 1) {
                    batch.anchor = p
                    let size = random.float(in: 0.4...0.8)
                    let rotation = yaw() * simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
                    let center = onGround(map, p, lift: size * 0.45)
                    batch.sphere(Palette.pinecone, at: center, radius: 1, squash: [size * 0.5, size, size * 0.5], rotation: rotation, low: true)
                    for direction in ActorModels.fibonacciDirections(6) {
                        let local = direction * SIMD3(size * 0.5, size, size * 0.5) * 0.9
                        batch.sphere(Palette.pineconeDark, at: center + rotation.act(local), radius: size * 0.17, squash: [1, 0.5, 1],
                                     rotation: rotation, low: true)
                    }
                }
                for p in spots(60, clearance: 0.1) {
                    batch.anchor = p
                    batch.part(Shapes.box, Palette.acornCap, at: onGround(map, p, lift: 0.02), scale: [0.03, 0.03, random.float(in: 0.8...1.4)],
                               rotation: yaw())
                }

            case .coneKnight:
                break

            case .mantis:
                // Briar Tangle: orchids for the mantises to hide among.
                for p in spots(24) {
                    batch.anchor = p
                    let h = random.float(in: 0.5...1)
                    let base = onGround(map, p)
                    batch.rod(Palette.thornStem, from: base, to: base + [0, h, 0], radius: 0.02)
                    for i in 0..<3 {
                        let a = Float(i) * 2.1
                        batch.part(Shapes.teardrop, Palette.mantisPink, at: base + [sin(a) * 0.08, h + 0.05, cos(a) * 0.08],
                                   scale: [0.06, 0.1, 0.03], rotation: simd_quatf(angle: a, axis: [0, 1, 0]) * simd_quatf(angle: -1, axis: [1, 0, 0]))
                    }
                }

            case .thornrose:
                // Wild rose bushes.
                for p in spots(12, clearance: 1) {
                    batch.anchor = p
                    let r = random.float(in: 0.5...0.8)
                    let base = onGround(map, p)
                    batch.sphere(Palette.thornStem, at: base + [0, r * 0.6, 0], radius: r, squash: [1, 0.75, 1], low: true)
                    for i in 0..<4 {
                        let d = AngleMath.direction(forYaw: Float(i) * 1.6 + r) * r * 0.8
                        batch.sphere(i % 2 == 0 ? Palette.roseRed : Palette.rosePink, at: base + [d.x, r * 0.9, d.y], radius: 0.12, low: true)
                    }
                }

            case .grumblecap:
                for p in spots(26) {
                    batch.anchor = p
                    let s = random.float(in: 0.3...0.8)
                    let base = onGround(map, p)
                    batch.cylinder(Palette.stem, at: base + [0, s * 0.3, 0], radius: s * 0.08, height: s * 0.7)
                    batch.sphere(Palette.glowCap, at: base + [0, s * 0.65, 0], radius: s * 0.3, squash: [1, 0.45, 1], glow: true, low: true)
                }

            case .stagBeetle:
                // Rotting logs the stag beetles fight over.
                for p in spots(10, clearance: 1.5) {
                    batch.anchor = p
                    let direction = AngleMath.direction(forYaw: random.float(in: 0...(2 * .pi)))
                    let length = random.float(in: 1.8...3.2)
                    let a = onGround(map, p - direction * length / 2, lift: 0.3), b = onGround(map, p + direction * length / 2, lift: 0.3)
                    batch.rod(Palette.darkBark, from: a, to: b, radius: 0.3, capped: true)
                    batch.sphere(Palette.moss, at: (a + b) / 2 + [0, 0.25, 0], radius: 0.35, squash: [1, 0.3, 1.4], low: true)
                }

            default:
                break
            }
        }
    }

    /// A thin flat ring (web strands).
    private static let ring: MeshData = {
        var mesh = MeshData()
        let segments = 24
        for i in 0...segments {
            let a = Float(i) / Float(segments) * 2 * .pi
            let d = SIMD3<Float>(sin(a), 0, cos(a))
            mesh.positions += [d * 0.94, d]
            mesh.normals += [[0, 1, 0], [0, 1, 0]]
            mesh.uvs += [.zero, .zero]
        }
        for i in 0..<UInt32(segments) {
            let v = i * 2
            mesh.indices += [v, v + 1, v + 2, v + 1, v + 3, v + 2]
        }
        return mesh
    }()

    /// The Great Bough: pale moonlit ground, scattered feathers and pellets, cold light.
    private static func addBossArena(_ arena: BossArena, map: WorldMap, to batch: SceneryBatch, lights: Entity, random: inout SeededRandom) {
        let feather = UIColor(red: 0.85, green: 0.78, blue: 0.66, alpha: 1)
        let pellet = UIColor(red: 0.45, green: 0.43, blue: 0.4, alpha: 1)
        for _ in 0..<18 {
            let p = random.point(inDiscAt: arena.center, radius: arena.radius + 4)
            batch.anchor = p
            let rotation = simd_quatf(angle: random.float(in: 0...(2 * .pi)), axis: [0, 1, 0])
            batch.sphere(feather, at: onGround(map, p, lift: 0.04), radius: 1, squash: [0.25, 0.03, 1.1] * random.float(in: 0.7...1.5),
                         rotation: rotation, low: true)
        }
        for _ in 0..<10 {
            let p = random.point(inDiscAt: arena.center, radius: arena.radius)
            batch.anchor = p
            batch.sphere(pellet, at: onGround(map, p, lift: 0.15), radius: random.float(in: 0.25...0.4), squash: [1, 0.7, 1.5], low: true)
        }
        let moonlight = PointLight()
        moonlight.light.color = UIColor(red: 0.6, green: 0.7, blue: 1, alpha: 1)
        moonlight.light.intensity = 14000
        moonlight.light.attenuationRadius = 24
        moonlight.position = onGround(map, arena.center, lift: 8)
        lights.addChild(moonlight)
    }

    // MARK: - Village props

    /// An anvil and a glowing ember pit beside the blacksmith.
    private static func addForge(_ map: WorldMap, to world: Entity) {
        guard let smith = map.npcs.first(where: { $0.id.definition.upgradesGear }) else { return }
        let forge = Entity()
        forge.position = onGround(map, smith.position)
        forge.orientation = simd_quatf(angle: smith.yaw, axis: [0, 1, 0])
        let iron = Materials.glossy(UIColor(white: 0.32, alpha: 1))
        forge.addPart(Meshes.roundedBox, Materials.matte(Palette.darkBark), at: [0.95, 0.2, 0.2], scale: [0.36, 0.4, 0.36]) // stump
        forge.addPart(Meshes.roundedBox, iron, at: [0.95, 0.47, 0.2], scale: [0.44, 0.14, 0.22])
        forge.addPart(Meshes.cone, iron, at: [1.25, 0.49, 0.2], scale: [0.07, 0.18, 0.07],
                      rotation: simd_quatf(angle: -.pi / 2, axis: [0, 0, 1]))
        let stone = Materials.matte(UIColor(white: 0.5, alpha: 1), roughness: 1)
        for i in 0..<8 {
            let a = Float(i) / 8 * 2 * .pi
            forge.addSphere(stone, at: [-1 + sin(a) * 0.38, 0.1, -0.2 + cos(a) * 0.38], radius: 0.13)
        }
        let ember = Materials.glow(UIColor(red: 1, green: 0.55, blue: 0.15, alpha: 1))
        forge.addSphere(ember, at: [-1, 0.08, -0.2], radius: 0.28, squash: [1, 0.35, 1])
        let light = PointLight()
        light.light.color = UIColor(red: 1, green: 0.6, blue: 0.25, alpha: 1)
        light.light.intensity = 6000
        light.light.attenuationRadius = 5
        light.position = [-1, 0.6, -0.2]
        forge.addChild(light)
        world.addChild(forge)
    }
}
