import GameCore
import RealityKit
import UIKit

/// Builds the static placeholder world from the shared `WorldMap`, so what you
/// see always matches what the simulation collides with.
@MainActor
enum WorldBuilder {
    static func build(_ map: WorldMap) -> Entity {
        let world = Entity()
        world.name = "World"
        var random = SeededRandom(seed: 0xF0_4E57)

        addGround(map, to: world, random: &random)
        addTrunk(map, to: world, random: &random)
        for root in map.roots { addRoot(root, to: world) }
        for house in map.houses { world.addChild(makeHouse(house, random: &random)) }
        addDecorations(map, to: world, random: &random)
        addZoneDressing(map, to: world, random: &random)
        if let arena = map.bossArena { addBossArena(arena, to: world, random: &random) }
        addMarketStall(map, to: world)
        addForge(map, to: world)
        if let grass = makeGrass(map, random: &random) { world.addChild(grass) }
        return world
    }

    // MARK: - Ground

    private static func addGround(_ map: WorldMap, to world: Entity, random: inout SeededRandom) {
        let ground = ModelEntity(
            mesh: .generatePlane(width: 600, depth: 600),
            materials: [Materials.matte(Palette.moss, roughness: 1)])
        world.addChild(ground)

        // Darker moss patches and a packed-dirt village clearing, as thin discs.
        let darkMoss = Materials.matte(Palette.darkMoss, roughness: 1)
        for _ in 0..<40 {
            let p = random.point(inDiscAt: .zero, radius: map.boundaryRadius)
            let r = random.float(in: 3...9)
            world.addCylinder(darkMoss, at: [p.x, 0.005, p.y], radius: r, height: 0.01)
        }
        let dirt = Materials.matte(Palette.dirt, roughness: 1)
        let village = map.villageCenter
        world.addCylinder(dirt, at: [village.x, 0.012, village.y], radius: map.villageRadius * 0.8, height: 0.01)
        // A path from the village up to the trunk.
        let pathLength = village.length - map.trunkCollisionRadius
        world.addPart(Meshes.box, dirt, at: [village.x * 0.62, 0.011, village.y * 0.62], scale: [3, 0.01, pathLength])
    }

    // MARK: - The giant tree

    private static func addTrunk(_ map: WorldMap, to world: Entity, random: inout SeededRandom) {
        let bark = Materials.matte(Palette.bark, roughness: 0.95)
        let height: Float = 220
        world.addCylinder(bark, at: [0, height / 2, 0], radius: map.trunkRadius, height: height)
        // Flared base; the simulation's trunk collider includes this.
        world.addPart(Meshes.cone, bark, at: [0, 5, 0], scale: [map.trunkCollisionRadius + 0.2, 10, map.trunkCollisionRadius + 0.2])

        let darkBark = Materials.matte(Palette.darkBark, roughness: 1)
        for i in 0..<28 {
            let angle = Float(i) / 28 * 2 * .pi + random.float(in: -0.05...0.05)
            let d = AngleMath.direction(forYaw: angle) * (map.trunkRadius + 0.1)
            world.addPart(Meshes.box, darkBark, at: [d.x, height / 2, d.y], scale: [random.float(in: 0.5...1.2), height, 0.6],
                          rotation: simd_quatf(angle: angle, axis: [0, 1, 0]))
        }

        // Shelf fungi stepping up the trunk.
        let fungus = Materials.matte(Palette.shelfFungus, roughness: 0.6)
        for i in 0..<9 {
            let angle = Float(i) * 2.1 + 0.4
            let y = 6 + Float(i) * 4.5
            let d = AngleMath.direction(forYaw: angle) * (map.trunkRadius + 0.4)
            let size = random.float(in: 1.6...3.0)
            world.addCylinder(fungus, at: [d.x, y, d.y], radius: size, height: 0.35)
        }
    }

    private static func addRoot(_ root: TreeRoot, to world: Entity) {
        let bark = Materials.matte(Palette.bark, roughness: 0.95)
        func point3(_ i: Int) -> SIMD3<Float> {
            // Roots rise out of the ground near the trunk and sink as they thin out.
            let p = root.points[i]
            let lift: Float = i == 0 ? 0.55 : 0.3
            return [p.x, root.radii[i] * lift, p.y]
        }
        for i in 0..<root.points.count {
            world.addSphere(bark, at: point3(i), radius: root.radii[i])
        }
        for i in 0..<(root.points.count - 1) {
            let a = point3(i), b = point3(i + 1)
            let axis = b - a
            let radius = (root.radii[i] + root.radii[i + 1]) / 2
            world.addCylinder(bark, at: (a + b) / 2, radius: radius, height: simd_length(axis),
                              rotation: simd_quatf(from: [0, 1, 0], to: simd_normalize(axis)))
        }
    }

    // MARK: - Village

    private static func makeHouse(_ house: MushroomHouse, random: inout SeededRandom) -> Entity {
        let e = Entity()
        e.position = [house.position.x, 0, house.position.y]
        e.orientation = simd_quatf(angle: house.yaw, axis: [0, 1, 0])

        let h = house.stemHeight
        e.addCylinder(Materials.matte(Palette.stem), at: [0, h / 2, 0], radius: house.stemRadius, height: h)
        let capColor = random.unit() < 0.7 ? Palette.capRed : Palette.capBrown
        let capY = h + house.capRadius * 0.12
        e.addSphere(Materials.matte(capColor, roughness: 0.55), at: [0, capY, 0], radius: house.capRadius, squash: [1, 0.5, 1])
        // Underside so the cap doesn't look hollow from below.
        e.addCylinder(Materials.matte(Palette.stem, roughness: 1), at: [0, capY - 0.02, 0], radius: house.capRadius * 0.97, height: 0.04)

        let spot = Materials.matte(Palette.capSpot)
        for _ in 0..<7 {
            let a = random.float(in: 0...(2 * .pi))
            let r = random.float(in: 0.15...0.8) * house.capRadius
            // Sit each spot on the squashed-sphere surface.
            let y = capY + house.capRadius * 0.5 * (1 - (r / house.capRadius) * (r / house.capRadius)).squareRoot()
            let d = AngleMath.direction(forYaw: a) * r
            e.addSphere(spot, at: [d.x, y, d.y], radius: random.float(in: 0.22...0.45), squash: [1, 0.35, 1])
        }

        let r = house.stemRadius
        e.addPart(Meshes.roundedBox, Materials.matte(Palette.door), at: [0, 0.85, r - 0.05], scale: [0.8, 1.7, 0.2])
        let window = Materials.glow(Palette.windowGlow)
        let side = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        for angle: Float in [-0.9, 0.9] {
            let d = AngleMath.direction(forYaw: angle) * (r - 0.02)
            e.addCylinder(window, at: [d.x, h * 0.62, d.y], radius: 0.22, height: 0.1,
                          rotation: simd_quatf(angle: angle, axis: [0, 1, 0]) * side)
        }
        return e
    }

    // MARK: - Decorations

    private static func addDecorations(_ map: WorldMap, to world: Entity, random: inout SeededRandom) {
        func freeSpot(radius: Float, avoidVillage: Bool = false) -> Vec2? {
            for _ in 0..<10 {
                let p = random.point(inDiscAt: .zero, radius: map.boundaryRadius + 20)
                if p.length < map.trunkCollisionRadius + 1 { continue }
                if p.length < map.boundaryRadius, map.isBlocked(p, radius: radius) { continue }
                if avoidVillage, p.distance(to: map.villageCenter) < map.villageRadius { continue }
                return p
            }
            return nil
        }

        // Little mushrooms everywhere, a few of them glowing.
        let stem = Materials.matte(Palette.stem)
        let caps = [Palette.capRed, Palette.capBrown, Palette.capSpot].map { Materials.matte($0, roughness: 0.5) }
        let glowCap = Materials.glow(Palette.glowCap)
        for i in 0..<180 {
            guard let p = freeSpot(radius: 0.4, avoidVillage: true) else { continue }
            let s = random.float(in: 0.25...0.9)
            let cap = i % 6 == 0 ? glowCap : caps[i % caps.count]
            world.addCylinder(stem, at: [p.x, s * 0.35, p.y], radius: s * 0.1, height: s * 0.7)
            world.addSphere(cap, at: [p.x, s * 0.7, p.y], radius: s * 0.32, squash: [1, 0.5, 1])
        }

        // Fallen leaves the size of rooftops: we're tiny down here.
        let leaves = [Materials.matte(Palette.leaf, roughness: 0.7), Materials.matte(Palette.deadLeaf, roughness: 0.9)]
        for i in 0..<22 {
            guard let p = freeSpot(radius: 2.5, avoidVillage: true) else { continue }
            let rotation = simd_quatf(angle: random.float(in: 0...(2 * .pi)), axis: [0, 1, 0])
                * simd_quatf(angle: random.float(in: -0.08...0.08), axis: [1, 0, 0])
            world.addPart(Meshes.sphere, leaves[i % 2], at: [p.x, 0.04, p.y], scale: [1.6, 0.05, 3.6] * random.float(in: 0.8...1.4), rotation: rotation)
        }

        let pebble = Materials.matte(Palette.pebble, roughness: 0.7)
        for _ in 0..<70 {
            guard let p = freeSpot(radius: 0.3) else { continue }
            let s = random.float(in: 0.15...0.5)
            world.addSphere(pebble, at: [p.x, s * 0.25, p.y], radius: s, squash: [1, 0.6, random.float(in: 0.8...1.3)])
        }
    }

    /// Each hunting ground gets its own look: bark litter for the beetles, a glowing purple fen for the spore beasts.
    private static func addZoneDressing(_ map: WorldMap, to world: Entity, random: inout SeededRandom) {
        for area in map.mobSpawns {
            switch area.kind {
            case .beetle:
                let chunk = Materials.matte(Palette.darkBark, roughness: 1)
                let litter = Materials.matte(Palette.dirt, roughness: 1)
                for _ in 0..<6 {
                    let p = random.point(inDiscAt: area.center, radius: area.radius)
                    world.addCylinder(litter, at: [p.x, 0.008, p.y], radius: random.float(in: 3...6), height: 0.01)
                }
                for _ in 0..<16 {
                    let p = random.point(inDiscAt: area.center, radius: area.radius + 3)
                    guard !map.isBlocked(p, radius: 1) else { continue }
                    let rotation = simd_quatf(angle: random.float(in: 0...(2 * .pi)), axis: [0, 1, 0])
                        * simd_quatf(angle: random.float(in: -0.3...0.3), axis: [1, 0, 0])
                    world.addPart(Meshes.roundedBox, chunk, at: [p.x, 0.1, p.y],
                                  scale: [random.float(in: 0.6...1.4), 0.25, random.float(in: 1.5...3)], rotation: rotation)
                }
            case .sporeBeast:
                let fen = Materials.matte(UIColor(red: 0.28, green: 0.2, blue: 0.3, alpha: 1), roughness: 1)
                for _ in 0..<8 {
                    let p = random.point(inDiscAt: area.center, radius: area.radius)
                    world.addCylinder(fen, at: [p.x, 0.009, p.y], radius: random.float(in: 3...7), height: 0.01)
                }
                let glow = Materials.glow(UIColor(red: 0.75, green: 0.45, blue: 1, alpha: 1))
                let stem = Materials.matte(Palette.stem)
                for _ in 0..<24 {
                    let p = random.point(inDiscAt: area.center, radius: area.radius + 4)
                    guard !map.isBlocked(p, radius: 0.4) else { continue }
                    let s = random.float(in: 0.4...1.2)
                    world.addCylinder(stem, at: [p.x, s * 0.35, p.y], radius: s * 0.08, height: s * 0.7)
                    world.addSphere(glow, at: [p.x, s * 0.7, p.y], radius: s * 0.3, squash: [1, 0.45, 1])
                }
                let light = PointLight()
                light.light.color = UIColor(red: 0.7, green: 0.4, blue: 1, alpha: 1)
                light.light.intensity = 9000
                light.light.attenuationRadius = 20
                light.position = [area.center.x, 3, area.center.y]
                world.addChild(light)
            default:
                break
            }
        }
    }

    /// The Great Bough: pale moonlit ground, scattered feathers and pellets, cold light.
    private static func addBossArena(_ arena: BossArena, to world: Entity, random: inout SeededRandom) {
        let ground = Materials.matte(UIColor(red: 0.3, green: 0.32, blue: 0.3, alpha: 1), roughness: 1)
        world.addCylinder(ground, at: [arena.center.x, 0.008, arena.center.y], radius: arena.radius, height: 0.01)
        let feather = Materials.matte(UIColor(red: 0.85, green: 0.78, blue: 0.66, alpha: 1), roughness: 1)
        let pellet = Materials.matte(UIColor(red: 0.45, green: 0.43, blue: 0.4, alpha: 1), roughness: 1)
        for _ in 0..<18 {
            let p = random.point(inDiscAt: arena.center, radius: arena.radius + 4)
            let rotation = simd_quatf(angle: random.float(in: 0...(2 * .pi)), axis: [0, 1, 0])
            world.addPart(Meshes.sphere, feather, at: [p.x, 0.04, p.y], scale: [0.25, 0.03, 1.1] * random.float(in: 0.7...1.5), rotation: rotation)
        }
        for _ in 0..<10 {
            let p = random.point(inDiscAt: arena.center, radius: arena.radius)
            world.addSphere(pellet, at: [p.x, 0.15, p.y], radius: random.float(in: 0.25...0.4), squash: [1, 0.7, 1.5])
        }
        let moonlight = PointLight()
        moonlight.light.color = UIColor(red: 0.6, green: 0.7, blue: 1, alpha: 1)
        moonlight.light.intensity = 14000
        moonlight.light.attenuationRadius = 24
        moonlight.position = [arena.center.x, 8, arena.center.y]
        world.addChild(moonlight)
    }

    /// An anvil and a glowing ember pit beside the blacksmith.
    private static func addForge(_ map: WorldMap, to world: Entity) {
        guard let smith = map.npcs.first(where: { $0.id.definition.upgradesGear }) else { return }
        let forge = Entity()
        forge.position = [smith.position.x, 0, smith.position.y]
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

    /// Crates and a little sign next to the trader.
    private static func addMarketStall(_ map: WorldMap, to world: Entity) {
        guard let trader = map.npcs.first(where: { $0.id.definition.isShopkeeper }) else { return }
        let stall = Entity()
        stall.position = [trader.position.x, 0, trader.position.y]
        stall.orientation = simd_quatf(angle: trader.yaw, axis: [0, 1, 0])
        let wood = Materials.matte(Palette.bark, roughness: 0.9)
        stall.addPart(Meshes.roundedBox, wood, at: [0.95, 0.25, -0.3], scale: [0.5, 0.5, 0.5])
        stall.addPart(Meshes.roundedBox, wood, at: [1.05, 0.7, -0.3], scale: [0.4, 0.4, 0.4])
        stall.addPart(Meshes.roundedBox, wood, at: [-0.9, 0.22, -0.4], scale: [0.45, 0.45, 0.45])
        for (index, color) in [UIColor.systemRed, .systemBlue, .systemRed].enumerated() {
            stall.addCylinder(Materials.glossy(color), at: [0.85 + Float(index) * 0.12, 0.6, -0.2], radius: 0.05, height: 0.16)
        }
        stall.addCylinder(wood, at: [-1.2, 0.6, 0.2], radius: 0.04, height: 1.2)
        stall.addPart(Meshes.roundedBox, Materials.matte(Palette.capSpot), at: [-1.2, 1.15, 0.24], scale: [0.6, 0.35, 0.05])
        world.addChild(stall)
    }

    /// All grass as one mesh (one draw call); the Metal geometry modifier animates it.
    private static func makeGrass(_ map: WorldMap, random: inout SeededRandom) -> ModelEntity? {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        let tuftCount = 3200
        for _ in 0..<tuftCount {
            let center = random.point(inDiscAt: .zero, radius: map.boundaryRadius + 15)
            if center.length < map.trunkCollisionRadius + 0.5 { continue }
            if center.length < map.boundaryRadius, map.isBlocked(center, radius: 0.2) { continue }
            // Keep the village clearing mostly trimmed.
            if center.distance(to: map.villageCenter) < map.villageRadius * 0.75, random.unit() < 0.85 { continue }

            for _ in 0..<5 {
                let base = center + Vec2(random.float(in: -0.15...0.15), random.float(in: -0.15...0.15))
                let angle = random.float(in: 0...(2 * .pi))
                let across = AngleMath.direction(forYaw: angle) * random.float(in: 0.03...0.05)
                let lean = AngleMath.direction(forYaw: angle + .pi / 2) * random.float(in: 0.05...0.2)
                let height = random.float(in: 0.3...0.7)
                let first = UInt32(positions.count)
                positions.append([base.x - across.x, 0, base.y - across.y])
                positions.append([base.x + across.x, 0, base.y + across.y])
                positions.append([base.x + lean.x, height, base.y + lean.y])
                normals.append(contentsOf: [[0, 1, 0], [0, 1, 0], [0, 1, 0]])
                indices.append(contentsOf: [first, first + 1, first + 2])
            }
        }

        var descriptor = MeshDescriptor(name: "grass")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }
        let grass = ModelEntity(mesh: mesh, materials: [Materials.grass])
        grass.components.set(DynamicLightShadowComponent(castsShadow: false))
        return grass
    }

}
