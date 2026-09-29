import GameCore
import RealityKit
import UIKit

/// Capstone Town's square (the Flyff-style town hub): the fountain, lamp posts round the plaza,
/// a stall and hanging signboard behind every shopkeeper, the request board, and the wooden
/// signposts at the edge of every hunting field. Built from the shared `WorldMap`.
@MainActor
enum TownBuilder {
    static func build(_ map: WorldMap, into world: Entity) {
        if let fountain = map.fountain { addFountain(fountain, map: map, to: world) }
        addLamps(map, to: world)
        for npc in map.npcs { addShopFront(npc, map: map, to: world) }
        for sign in map.signposts { addSignpost(sign, map: map, to: world) }
    }

    private static func onGround(_ map: WorldMap, _ p: Vec2, lift: Float = 0) -> SIMD3<Float> {
        [p.x, map.groundHeight(at: p) + lift, p.y]
    }

    private static let stone = UIColor(red: 0.78, green: 0.74, blue: 0.66, alpha: 1)
    private static let stoneDark = UIColor(red: 0.58, green: 0.55, blue: 0.5, alpha: 1)
    private static let water = UIColor(red: 0.45, green: 0.78, blue: 0.95, alpha: 1)
    private static let wood = Palette.bark
    private static let plank = UIColor(red: 0.72, green: 0.55, blue: 0.36, alpha: 1)
    private static let ink = UIColor(red: 0.22, green: 0.14, blue: 0.08, alpha: 1)

    // MARK: - Fountain

    /// A round stone basin with a toadstool-shaped spout basin in the middle, spilling water.
    private static func addFountain(_ disc: Disc, map: WorldMap, to world: Entity) {
        let fountain = Entity()
        fountain.name = "Fountain"
        fountain.position = onGround(map, disc.center)
        let r = disc.radius
        let stoneMaterial = Materials.matte(stone, roughness: 0.9)
        let rim = Materials.matte(stoneDark, roughness: 0.9)
        // The basin wall: a ring of chunky stones with a cap ring on top.
        let blocks = 22
        for i in 0..<blocks {
            let a = Float(i) / Float(blocks) * 2 * .pi
            fountain.addPart(Meshes.roundedBox, i % 2 == 0 ? stoneMaterial : rim, at: [sin(a) * r, 0.22, cos(a) * r],
                             scale: [0.62, 0.44, 0.34], rotation: simd_quatf(angle: a, axis: [0, 1, 0]))
        }
        fountain.addPart(Meshes.torus(radius: r, tube: 0.12), stoneMaterial, at: [0, 0.46, 0], scale: .one)
        // The pool, and the water spilling from the upper basin.
        let pool = Materials.glossy(water)
        fountain.addCylinder(pool, at: [0, 0.3, 0], radius: r - 0.1, height: 0.06)
        fountain.addCylinder(stoneMaterial, at: [0, 0.9, 0], radius: 0.22, height: 1.3)
        fountain.addSphere(stoneMaterial, at: [0, 1.62, 0], radius: 0.85, squash: [1, 0.32, 1])
        fountain.addCylinder(pool, at: [0, 1.78, 0], radius: 0.7, height: 0.04)
        fountain.addSphere(Materials.matte(Palette.capRed, roughness: 0.5), at: [0, 2.05, 0], radius: 0.3, squash: [1, 0.6, 1])
        fountain.addSphere(Materials.matte(Palette.capSpot), at: [0.1, 2.2, 0.12], radius: 0.07, squash: [1, 0.4, 1])
        let falling = Materials.translucent(water, opacity: 0.55)
        for i in 0..<8 {
            let a = Float(i) / 8 * 2 * .pi
            let lip = SIMD3<Float>(sin(a) * 0.82, 1.62, cos(a) * 0.82)
            fountain.addRod(falling, from: lip, to: [sin(a) * 1.05, 0.34, cos(a) * 1.05], radius: 0.05)
        }
        let light = PointLight()
        light.light.color = UIColor(red: 0.6, green: 0.85, blue: 1, alpha: 1)
        light.light.intensity = 2500
        light.light.attenuationRadius = 6
        light.position = [0, 1.2, 0]
        fountain.addChild(light)
        world.addChild(fountain)
    }

    // MARK: - Lamps

    /// Glowcap lamp posts around the plaza.
    private static func addLamps(_ map: WorldMap, to world: Entity) {
        guard let fountain = map.fountain else { return }
        let post = Materials.matte(Palette.darkBark, roughness: 0.9)
        let glow = Materials.glow(UIColor(red: 1, green: 0.85, blue: 0.5, alpha: 1))
        let cap = Materials.matte(Palette.capBrown, roughness: 0.6)
        for i in 0..<8 {
            let degrees = Float(i) * 45 + 22.5
            let spot = fountain.center + AngleMath.direction(forYaw: degrees * .pi / 180) * 11
            guard !map.isBlocked(spot, radius: 0.3) else { continue }
            let lamp = Entity()
            lamp.position = onGround(map, spot)
            lamp.addCylinder(post, at: [0, 1.1, 0], radius: 0.06, height: 2.2)
            lamp.addSphere(glow, at: [0, 2.3, 0], radius: 0.2)
            lamp.addSphere(cap, at: [0, 2.48, 0], radius: 0.32, squash: [1, 0.45, 1])
            world.addChild(lamp)
        }
    }

    // MARK: - Shop fronts

    /// What a shopkeeper's signboard shows, and the props on their stall.
    private enum Front {
        case weapons, armor, goods, board, none
    }

    private static func front(of npc: NPCID) -> Front {
        switch npc {
        case .oyster: .weapons
        case .enoki: .armor
        case .chanterelle: .goods
        case .maitake: .board
        default: .none
        }
    }

    private static func addShopFront(_ placement: NPCPlacement, map: WorldMap, to world: Entity) {
        let front = front(of: placement.id)
        guard front != .none else { return }
        let stall = Entity()
        stall.position = onGround(map, placement.position)
        stall.orientation = simd_quatf(angle: placement.yaw, axis: [0, 1, 0])
        let woodMaterial = Materials.matte(wood, roughness: 0.9)
        let plankMaterial = Materials.matte(plank, roughness: 0.9)

        if front == .board {
            // A notice board on two posts, covered in pinned requests.
            for x: Float in [-0.75, 0.75] {
                stall.addCylinder(woodMaterial, at: [x, 0.9, -1], radius: 0.06, height: 1.8)
            }
            stall.addPart(Meshes.roundedBox, plankMaterial, at: [0, 1.25, -1], scale: [1.6, 0.9, 0.06])
            stall.addPart(Meshes.roundedBox, woodMaterial, at: [0, 1.75, -1], scale: [1.8, 0.1, 0.18])
            let papers: [(Float, Float, Float)] = [(-0.5, 1.4, 0.1), (-0.1, 1.2, -0.08), (0.3, 1.42, 0.05),
                                                   (0.55, 1.08, -0.1), (-0.45, 1.02, 0.12), (0.05, 0.98, 0.02)]
            let paper = Materials.matte(UIColor(red: 0.98, green: 0.95, blue: 0.85, alpha: 1))
            let pin = Materials.glossy(.systemRed)
            for (x, y, roll) in papers {
                stall.addPart(Meshes.roundedBox, paper, at: [x, y, -0.96], scale: [0.28, 0.34, 0.01],
                              rotation: simd_quatf(angle: roll, axis: [0, 0, 1]))
                stall.addSphere(pin, at: [x, y + 0.14, -0.95], radius: 0.025)
            }
            addLabel("REQUESTS", to: stall, at: [0, 1.75, -0.89], height: 0.13, color: ink)
            world.addChild(stall)
            return
        }

        // A counter behind the keeper under a striped awning.
        stall.addPart(Meshes.roundedBox, woodMaterial, at: [0, 0.45, -1.1], scale: [2, 0.9, 0.6])
        stall.addPart(Meshes.roundedBox, plankMaterial, at: [0, 0.92, -1.1], scale: [2.1, 0.06, 0.7])
        for x: Float in [-1, 1] {
            stall.addCylinder(woodMaterial, at: [x, 1.2, -1.4], radius: 0.05, height: 2.4)
        }
        let stripes: [UIColor] = switch front {
        case .weapons: [UIColor(red: 0.85, green: 0.25, blue: 0.2, alpha: 1), UIColor(red: 0.98, green: 0.92, blue: 0.8, alpha: 1)]
        case .armor: [UIColor(red: 0.25, green: 0.45, blue: 0.85, alpha: 1), UIColor(red: 0.98, green: 0.92, blue: 0.8, alpha: 1)]
        default: [UIColor(red: 0.3, green: 0.65, blue: 0.3, alpha: 1), UIColor(red: 0.98, green: 0.92, blue: 0.8, alpha: 1)]
        }
        for i in 0..<6 {
            let x = -1.05 + Float(i) * 0.42
            stall.addPart(Meshes.roundedBox, Materials.matte(stripes[i % 2], roughness: 0.8), at: [x, 2.3, -1.15],
                          scale: [0.42, 0.05, 0.9], rotation: simd_quatf(angle: 0.28, axis: [1, 0, 0]))
        }
        // The signboard over the stall.
        stall.addPart(Meshes.roundedBox, plankMaterial, at: [0, 2.72, -1.45], scale: [1.5, 0.42, 0.06])
        let title = switch front {
        case .weapons: "WEAPONS"
        case .armor: "ARMOR"
        default: "GENERAL"
        }
        addLabel(title, to: stall, at: [0, 2.72, -1.41], height: 0.2, color: ink)

        switch front {
        case .weapons:
            // Blades standing in a rack on the counter.
            let steel = Materials.glossy(UIColor(white: 0.82, alpha: 1))
            let grip = Materials.matte(Palette.darkBark)
            for i in 0..<4 {
                let x = -0.7 + Float(i) * 0.3
                stall.addPart(Meshes.roundedBox, steel, at: [x, 1.35, -1.2], scale: [0.07, 0.7, 0.02])
                stall.addPart(Meshes.roundedBox, grip, at: [x, 0.98, -1.2], scale: [0.18, 0.04, 0.05])
            }
            stall.addPart(Meshes.roundedBox, Materials.glossy(UIColor(white: 0.55, alpha: 1)), at: [0.6, 1.1, -1.1],
                          scale: [0.34, 0.2, 0.12]) // an axe head
        case .armor:
            // A dressed mannequin and a shield on the counter.
            let cloth = Materials.matte(UIColor(red: 0.35, green: 0.55, blue: 0.85, alpha: 1))
            stall.addCylinder(woodMaterial, at: [-0.6, 1.2, -1.2], radius: 0.03, height: 0.6)
            stall.addPart(Meshes.roundedBox, cloth, at: [-0.6, 1.3, -1.2], scale: [0.36, 0.42, 0.18])
            stall.addSphere(Materials.matte(Palette.capBrown), at: [-0.6, 1.62, -1.2], radius: 0.13)
            stall.addCylinder(Materials.glossy(UIColor(red: 0.75, green: 0.55, blue: 0.3, alpha: 1)), at: [0.45, 1.2, -1.2],
                              radius: 0.25, height: 0.05, rotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))
        default:
            // Potion bottles.
            let colors: [UIColor] = [.systemRed, .systemBlue, .systemOrange, .systemRed, .systemIndigo]
            for (i, color) in colors.enumerated() {
                stall.addCylinder(Materials.glossy(color), at: [-0.6 + Float(i) * 0.3, 1.05, -1.05], radius: 0.07, height: 0.2)
            }
        }
        world.addChild(stall)
    }

    // MARK: - Signposts

    /// A post with an arrow-shaped plank: "Snails" over "Lv 1–2", readable from both sides.
    private static func addSignpost(_ sign: Signpost, map: WorldMap, to world: Entity) {
        let post = Entity()
        post.position = onGround(map, sign.position)
        post.orientation = simd_quatf(angle: sign.yaw, axis: [0, 1, 0])
        let woodMaterial = Materials.matte(wood, roughness: 0.9)
        post.addCylinder(woodMaterial, at: [0, 0.8, 0], radius: 0.07, height: 1.6)
        post.addPart(Meshes.roundedBox, Materials.matte(plank, roughness: 0.9), at: [0, 1.4, 0], scale: [1.3, 0.52, 0.07])
        let levels = sign.levels.map { "Lv \($0.lowerBound)–\($0.upperBound)" }
        for side: Float in [1, -1] {
            let face = Entity()
            face.orientation = simd_quatf(angle: side > 0 ? 0 : .pi, axis: [0, 1, 0])
            addLabel(sign.title, to: face, at: [0, levels == nil ? 1.4 : 1.49, 0.04], height: 0.17, color: ink, maxWidth: 1.2)
            if let levels {
                addLabel(levels, to: face, at: [0, 1.28, 0.04], height: 0.13, color: UIColor(red: 0.6, green: 0.15, blue: 0.1, alpha: 1))
            }
            post.addChild(face)
        }
        world.addChild(post)
    }

    private static var textCache: [String: MeshResource] = [:]

    /// Flat text centered on `position` (in `parent`'s space), facing +Z.
    private static func addLabel(_ text: String, to parent: Entity, at position: SIMD3<Float>, height: Float, color: UIColor,
                                 maxWidth: Float = 1.4) {
        let key = "\(text)|\(height)"
        let mesh: MeshResource
        if let cached = textCache[key] {
            mesh = cached
        } else {
            let font = UIFont.systemFont(ofSize: CGFloat(height), weight: .heavy)
            mesh = MeshResource.generateText(text, extrusionDepth: 0.005, font: font)
            textCache[key] = mesh
        }
        let label = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)])
        let bounds = mesh.bounds
        let width = bounds.extents.x
        let scale = width > maxWidth ? maxWidth / width : 1
        label.scale = SIMD3(repeating: scale)
        label.position = position - SIMD3(bounds.center.x, bounds.center.y, 0) * scale
        parent.addChild(label)
    }
}
