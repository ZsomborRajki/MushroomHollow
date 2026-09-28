import GameCore
import RealityKit
import UIKit

/// Weapons and shields built from primitives. Blades, hafts, and wands are modeled in fist space
/// (grip at the origin). Staves, bows, and shields have their own frame, which the rig turns to
/// face the right way every frame.
@MainActor
enum WeaponModels {
    /// Blades point forward and a little up from the fist while the arm hangs.
    static let bladeDirection = simd_normalize(SIMD3<Float>(0, 0.35, 1))
    /// Where the off hand grips a two-handed haft (fist space).
    static let offhandGrip = -bladeDirection * 0.11
    /// Bow frame: arrows fly along +Z, limbs run along ±Y, and the string sits behind (-Z).
    static let stringRest: SIMD3<Float> = [0, 0, -0.1]

    struct Held {
        let entity: Entity
        /// Where projectiles leave from.
        var muzzle: Entity?
        /// Bow string halves (to the top tip, to the bottom tip), refit to the nock every frame.
        var string: [ModelEntity] = []
        var stringTips: [SIMD3<Float>] = []
        /// The nocked arrow; its origin sits on the string.
        var arrow: Entity?
        /// How far the edge reaches from the fist along `bladeDirection`, and its swing trail color.
        var trail: (reach: Float, tint: UIColor)?
    }

    /// The side of a haft that leads a swing: perpendicular to the blade, down while the arm hangs.
    private static let edge = simd_normalize(simd_cross([1, 0, 0], bladeDirection))
    /// Axe and hammer heads: x through the flat, y toward the edge, z up the haft.
    private static let headFrame = simd_quatf(simd_float3x3(simd_cross(edge, bladeDirection), edge, bladeDirection))
    private static let identity = simd_quatf(angle: 0, axis: [0, 1, 0])

    // MARK: - Weapons

    static func make(_ item: ItemID) -> Held {
        switch item.definition.weaponType {
        case .sword: sword(item)
        case .axe: axe(item)
        case .maul: maul(item)
        case .bow: bow(item)
        case .wand: wand(item)
        case .staff: staff(item)
        case nil: Held(entity: Entity())
        }
    }

    private static func sword(_ item: ItemID) -> Held {
        let e = Entity()
        let d = bladeDirection
        let along = simd_quatf(from: [0, 1, 0], to: d)
        e.addRod(Materials.matte(Palette.darkBark), from: -d * 0.07, to: d * 0.07, radius: 0.02)
        let trail: (Float, UIColor)
        switch item {
        case .thornRapier:
            let thorn = Materials.glossy(Palette.shelfFungus)
            e.addPart(Meshes.cylinder, thorn, at: d * 0.075, scale: [0.055, 0.015, 0.055], rotation: along)
            e.addPart(Meshes.cone, thorn, at: d * 0.39, scale: [0.022, 0.62, 0.022], rotation: along)
            trail = (0.7, UIColor(red: 1, green: 0.86, blue: 0.55, alpha: 1))
        case .beetleBlade:
            let shell = Materials.glossy(Palette.beetleShell)
            let flat = simd_quatf(from: [0, 0, 1], to: d)
            e.addPart(Meshes.roundedBox, shell, at: d * 0.075, scale: [0.05, 0.16, 0.035], rotation: flat)
            e.addPart(Meshes.box, shell, at: d * 0.33, scale: [0.022, 0.09, 0.5], rotation: flat)
            e.addPart(Meshes.cone, shell, at: d * 0.64, scale: [0.011, 0.12, 0.045], rotation: along)
            trail = (0.7, UIColor(red: 0.5, green: 0.72, blue: 1, alpha: 1))
        case .moonTalon:
            // A crescent of cold moonlight.
            let glow = Materials.glow(UIColor(red: 0.75, green: 0.85, blue: 1, alpha: 1))
            let up = SIMD3<Float>(0, d.z, -d.y)
            let points = (0...6).map { i -> SIMD3<Float> in
                let s = Float(i) / 6
                return d * (0.08 + s * 0.6) + up * sin(s * .pi) * 0.12
            }
            for (a, b) in zip(points, points.dropFirst()) {
                e.addRod(glow, from: a, to: b, radius: 0.028 * (1 - simd_length(b) * 0.9))
                e.addSphere(glow, at: b, radius: 0.028 * (1 - simd_length(b) * 0.9))
            }
            trail = (0.68, UIColor(red: 0.78, green: 0.9, blue: 1, alpha: 1))
        case .stingerBlade:
            let comb = Materials.matte(Palette.beeYellow, roughness: 0.4)
            e.addPart(Meshes.cylinder, comb, at: d * 0.075, scale: [0.05, 0.02, 0.05], rotation: along)
            e.addPart(Meshes.cone, Materials.glossy(Palette.bugBlack), at: d * 0.37, scale: [0.028, 0.58, 0.028], rotation: along)
            trail = (0.66, UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1))
        case .silkfangSaber:
            let fang = Materials.glossy(Palette.mantisWhite)
            e.addPart(Meshes.cone, fang, at: d * 0.4, scale: [0.03, 0.66, 0.03], rotation: along)
            for s: Float in [0.1, 0.16, 0.22] {
                e.addPart(Meshes.torus(radius: 0.03, tube: 0.007), Materials.matte(Palette.mothLilac), at: d * s, scale: .one, rotation: along)
            }
            trail = (0.72, UIColor(red: 0.85, green: 0.8, blue: 1, alpha: 1))
        case .mantisEdge:
            // A long pink crescent.
            let edge = Materials.glossy(Palette.mantisPink)
            let up = SIMD3<Float>(0, d.z, -d.y)
            let points = (0...6).map { i -> SIMD3<Float> in
                let s = Float(i) / 6
                return d * (0.08 + s * 0.66) - up * sin(s * .pi) * 0.1
            }
            for (a, b) in zip(points, points.dropFirst()) {
                e.addRod(edge, from: a, to: b, radius: 0.026 * (1 - simd_length(b) * 0.8))
                e.addSphere(edge, at: b, radius: 0.026 * (1 - simd_length(b) * 0.8))
            }
            trail = (0.74, UIColor(red: 1, green: 0.7, blue: 0.85, alpha: 1))
        default: // Twig sword
            let wood = Materials.matte(Palette.bark)
            e.addSphere(wood, at: d * 0.07, radius: 0.035)
            e.addRod(wood, from: d * 0.07, to: d * 0.55, radius: 0.024)
            e.addPart(Meshes.teardrop, Materials.matte(Palette.leaf), at: d * 0.4 + [0.04, 0.02, 0], scale: [0.025, 0.045, 0.008],
                      rotation: simd_quatf(angle: -1.1, axis: [0, 0, 1]))
            trail = (0.55, UIColor(red: 0.85, green: 1, blue: 0.72, alpha: 1))
        }
        return Held(entity: e, trail: trail)
    }

    /// A short haft with a head on the leading side.
    private static func axe(_ item: ItemID) -> Held {
        let e = Entity()
        let d = bladeDirection
        let head = d * 0.44
        func part(_ mesh: MeshResource, _ material: any RealityKit.Material, _ offset: SIMD3<Float>, _ scale: SIMD3<Float>,
                  _ rotation: simd_quatf = identity) {
            e.addPart(mesh, material, at: head + headFrame.act(offset), scale: scale, rotation: headFrame * rotation)
        }
        let flat = simd_quatf(angle: .pi / 2, axis: [0, 0, 1]) // a disc facing the flat side
        let trail: (Float, UIColor)
        switch item {
        case .hornCleaver:
            e.addRod(Materials.matte(Palette.darkBark), from: -d * 0.08, to: d * 0.52, radius: 0.019)
            let shell = Materials.glossy(Palette.beetleShell)
            part(Meshes.roundedBox, shell, [0, 0.07, 0], [0.018, 0.13, 0.15])
            part(Meshes.cylinder, shell, [0, 0.13, 0], [0.085, 0.012, 0.085], flat)
            part(Meshes.cone, Materials.glossy(Palette.eye), [0, -0.06, 0], [0.02, 0.08, 0.02], simd_quatf(angle: .pi, axis: [1, 0, 0]))
            trail = (0.56, UIColor(red: 0.55, green: 0.7, blue: 1, alpha: 1))
        case .toadstoolChopper:
            e.addRod(Materials.matte(Palette.stem), from: -d * 0.08, to: d * 0.52, radius: 0.022)
            part(Meshes.cylinder, Materials.matte(Palette.capRed, roughness: 0.5), [0, 0.06, 0], [0.11, 0.022, 0.11], flat)
            let spot = Materials.matte(Palette.capSpot)
            for (y, z) in [(0.1, 0.03), (0.05, -0.05), (0.12, -0.04), (0.02, 0.06)] as [(Float, Float)] {
                for side: Float in [-1, 1] {
                    part(Meshes.sphere, spot, [side * 0.012, y, z], [0.006, 0.016, 0.016])
                }
            }
            trail = (0.58, UIColor(red: 1, green: 0.55, blue: 0.45, alpha: 1))
        case .mossbackCleaver:
            e.addRod(Materials.matte(Palette.bark), from: -d * 0.08, to: d * 0.52, radius: 0.021)
            part(Meshes.sphere, Materials.matte(Palette.turtleShell, roughness: 0.7), [0, 0.06, 0], [0.025, 0.1, 0.1])
            part(Meshes.sphere, Materials.matte(Palette.moss, roughness: 1), [0.012, 0.04, 0.02], [0.02, 0.05, 0.05])
            trail = (0.58, UIColor(red: 0.6, green: 0.85, blue: 0.4, alpha: 1))
        case .quillsplitter:
            e.addRod(Materials.matte(Palette.darkBark), from: -d * 0.08, to: d * 0.54, radius: 0.021)
            part(Meshes.roundedBox, Materials.matte(Palette.hedgehogBrown), [0, 0.07, 0], [0.022, 0.14, 0.14])
            let quill = Materials.matte(Palette.quill)
            for z: Float in [-0.05, 0, 0.05] {
                part(Meshes.cone, quill, [0, 0.16, z], [0.012, 0.08, 0.012])
            }
            trail = (0.6, UIColor(red: 0.85, green: 0.7, blue: 0.5, alpha: 1))
        case .stagjawAxe:
            e.addRod(Materials.matte(Palette.darkBark), from: -d * 0.08, to: d * 0.56, radius: 0.023)
            let jaw = Materials.glossy(Palette.stagBrown)
            part(Meshes.cone, jaw, [0, 0.09, 0.04], [0.02, 0.2, 0.03], simd_quatf(angle: -0.5, axis: [1, 0, 0]))
            part(Meshes.cone, jaw, [0, 0.09, -0.04], [0.02, 0.2, 0.03], simd_quatf(angle: 0.5, axis: [1, 0, 0]))
            part(Meshes.sphere, Materials.glossy(Palette.stagDark), [0, 0.02, 0], [0.035, 0.04, 0.05])
            trail = (0.64, UIColor(red: 1, green: 0.72, blue: 0.4, alpha: 1))
        default: // Pebble hatchet
            e.addRod(Materials.matte(Palette.bark), from: -d * 0.08, to: d * 0.5, radius: 0.02)
            part(Meshes.sphere, Materials.matte(Palette.pebble, roughness: 0.6), [0, 0.05, 0], [0.032, 0.085, 0.065])
            part(Meshes.torus(radius: 0.026, tube: 0.009), Materials.matte(Palette.deadLeaf), [0, 0, 0], .one,
                 simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))
            trail = (0.52, UIColor(red: 0.9, green: 0.88, blue: 0.8, alpha: 1))
        }
        return Held(entity: e, trail: trail)
    }

    /// A long two-handed haft with a heavy head.
    private static func maul(_ item: ItemID) -> Held {
        let e = Entity()
        let d = bladeDirection
        let head = d * 0.56
        func part(_ mesh: MeshResource, _ material: any RealityKit.Material, _ offset: SIMD3<Float>, _ scale: SIMD3<Float>,
                  _ rotation: simd_quatf = identity) {
            e.addPart(mesh, material, at: head + headFrame.act(offset), scale: scale, rotation: headFrame * rotation)
        }
        let trail: (Float, UIColor)
        switch item {
        case .boughHammer:
            e.addRod(Materials.matte(Palette.darkBark), from: -d * 0.2, to: head, radius: 0.025)
            part(Meshes.cylinder, Materials.matte(Palette.bark, roughness: 1), .zero, [0.1, 0.3, 0.1])
            for y: Float in [-0.11, 0.11] {
                part(Meshes.torus(radius: 0.1, tube: 0.02), Materials.matte(Palette.moss), [0, y, 0], .one)
            }
            part(Meshes.torus(radius: 0.102, tube: 0.012), Materials.glow(Palette.glowCap), .zero, .one)
            trail = (0.68, UIColor(red: 0.6, green: 1, blue: 0.9, alpha: 1))
        case .emberstoneMaul:
            e.addRod(Materials.matte(Palette.darkBark), from: -d * 0.2, to: head, radius: 0.024)
            part(Meshes.cylinder, Materials.matte(UIColor(white: 0.35, alpha: 1), roughness: 0.9), .zero, [0.085, 0.26, 0.085])
            for y: Float in [-0.08, 0.08] {
                part(Meshes.torus(radius: 0.087, tube: 0.012), Materials.glow(Palette.emberGlow), [0, y, 0], .one)
            }
            trail = (0.66, UIColor(red: 1, green: 0.55, blue: 0.2, alpha: 1))
        case .stagCrusher:
            e.addRod(Materials.matte(Palette.stagDark), from: -d * 0.2, to: head, radius: 0.026)
            part(Meshes.cylinder, Materials.glossy(Palette.stagBrown), .zero, [0.1, 0.3, 0.1])
            for y: Float in [-1, 1] {
                part(Meshes.cone, Materials.glossy(Palette.stagDark), [0, y * 0.2, 0], [0.04, 0.12, 0.04],
                     simd_quatf(angle: y > 0 ? 0 : .pi, axis: [1, 0, 0]))
            }
            trail = (0.7, UIColor(red: 1, green: 0.72, blue: 0.4, alpha: 1))
        default: // Toadstool maul
            e.addRod(Materials.matte(Palette.stem), from: -d * 0.2, to: head, radius: 0.023)
            part(Meshes.cylinder, Materials.matte(Palette.capRed, roughness: 0.5), .zero, [0.08, 0.24, 0.08])
            let spot = Materials.matte(Palette.capSpot)
            for y: Float in [-0.12, 0.12] {
                part(Meshes.sphere, spot, [0, y, 0], [0.078, 0.025, 0.078])
            }
            for (x, y) in [(1, 0.05), (-1, -0.04), (0.2, 0.0)] as [(Float, Float)] {
                let side = simd_normalize(SIMD3<Float>(x, 0, 1 - abs(x) * 0.5))
                part(Meshes.sphere, spot, SIMD3(side.x * 0.078, y, side.z * 0.078), [0.02, 0.02, 0.02])
            }
            trail = (0.64, UIColor(red: 1, green: 0.6, blue: 0.5, alpha: 1))
        }
        // Leather wraps where both hands hold on.
        let wrap = Materials.matte(Palette.door)
        for s: Float in [-0.11, 0] {
            e.addPart(Meshes.torus(radius: 0.026, tube: 0.01), wrap, at: d * s, scale: .one, rotation: simd_quatf(from: [0, 1, 0], to: d))
        }
        return Held(entity: e, trail: trail)
    }

    private static func wand(_ item: ItemID) -> Held {
        let e = Entity()
        let d = bladeDirection
        let muzzle = Entity()
        let trail: (Float, UIColor)
        switch item {
        case .glowcapScepter:
            e.addRod(Materials.matte(Palette.darkBark), from: -d * 0.05, to: d * 0.3, radius: 0.014)
            for s: Float in [0.02, 0.26] {
                e.addPart(Meshes.torus(radius: 0.016, tube: 0.006), Materials.glossy(SproutLook.gold), at: d * s, scale: .one,
                          rotation: simd_quatf(from: [0, 1, 0], to: d))
            }
            let glow = Materials.glow(Palette.glowCap)
            e.addPart(Meshes.sphere, glow, at: d * 0.34, scale: [0.06, 0.03, 0.06], rotation: simd_quatf(from: [0, 1, 0], to: d))
            e.addSphere(glow, at: d * 0.31, radius: 0.018)
            muzzle.position = d * 0.36
            trail = (0.36, Palette.glowCap)
        case .mothwingWand:
            e.addRod(Materials.matte(Palette.darkBark), from: -d * 0.05, to: d * 0.3, radius: 0.013)
            let wing = Materials.matte(Palette.mothLilac)
            for side: Float in [-1, 1] {
                e.addPart(Meshes.teardrop, wing, at: d * 0.3 + [side * 0.04, 0.01, 0], scale: [0.03, 0.05, 0.006],
                          rotation: simd_quatf(angle: side * -1.2, axis: [0, 0, 1]))
            }
            e.addSphere(Materials.glow(Palette.spiderGlow), at: d * 0.33, radius: 0.022)
            muzzle.position = d * 0.35
            trail = (0.36, UIColor(red: 0.75, green: 0.7, blue: 1, alpha: 1))
        case .grumblecapScepter:
            e.addRod(Materials.matte(Palette.stem), from: -d * 0.05, to: d * 0.3, radius: 0.016)
            let cap = d * 0.33
            e.addSphere(Materials.matte(Palette.capRed, roughness: 0.5), at: cap, radius: 0.055)
            for i in 0..<4 {
                let a = Float(i) / 4 * 2 * .pi
                e.addSphere(Materials.matte(Palette.capSpot), at: cap + [cos(a) * 0.045, 0.02 + sin(a) * 0.02, sin(a) * 0.03], radius: 0.012)
            }
            muzzle.position = d * 0.36
            trail = (0.38, UIColor(red: 1, green: 0.4, blue: 0.35, alpha: 1))
        default: // Puffball wand
            e.addRod(Materials.matte(Palette.stem), from: -d * 0.05, to: d * 0.28, radius: 0.013)
            e.addSphere(Materials.matte(Palette.capSpot, roughness: 1), at: d * 0.32, radius: 0.045)
            let spore = Materials.glow(UIColor(red: 0.8, green: 0.5, blue: 1, alpha: 1))
            for i in 0..<5 {
                let a = Float(i) / 5 * 2 * .pi
                e.addSphere(spore, at: d * 0.32 + [cos(a) * 0.05, sin(a) * 0.035, sin(a) * 0.02], radius: 0.01)
            }
            muzzle.position = d * 0.33
            trail = (0.34, UIColor(red: 0.8, green: 0.55, blue: 1, alpha: 1))
        }
        e.addChild(muzzle)
        return Held(entity: e, muzzle: muzzle, trail: trail)
    }

    /// Staff frame: the shaft runs along +Y, just in front of the fist so it clears the arm.
    private static func staff(_ item: ItemID) -> Held {
        let e = Entity()
        let a: SIMD3<Float> = [0, 1, 0]
        let front: SIMD3<Float> = [0, 0, 0.045]
        let muzzle = Entity()
        let dew = Materials.glow(UIColor(red: 0.55, green: 0.9, blue: 1, alpha: 1))
        switch item {
        case .raincallerStaff:
            e.addRod(Materials.matte(Palette.stem), from: front - a * 0.42, to: front + a * 0.72, radius: 0.021)
            // A gold ring facing forward, beaded with droplets around a big one.
            let top = front + a * 0.81
            e.addPart(Meshes.torus(radius: 0.08, tube: 0.012), Materials.glossy(SproutLook.gold), at: top, scale: .one,
                      rotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))
            e.addSphere(dew, at: top, radius: 0.04)
            for i in 0..<6 {
                let angle = Float(i) / 6 * 2 * .pi
                e.addSphere(dew, at: top + [cos(angle), sin(angle), 0] * 0.08, radius: 0.014)
            }
            muzzle.position = top
        case .buttercupStaff:
            e.addRod(Materials.matte(Palette.dandelionStem), from: front - a * 0.42, to: front + a * 0.7, radius: 0.019)
            let top = front + a * 0.76
            e.addPart(Meshes.cone, Materials.matte(Palette.beeYellow, roughness: 0.35), at: top, scale: [0.075, 0.09, 0.075],
                      rotation: simd_quatf(angle: .pi, axis: [1, 0, 0]))
            e.addSphere(dew, at: top + a * 0.03, radius: 0.03)
            muzzle.position = top + a * 0.03
        case .thornroseStaff:
            let stem = Materials.matte(Palette.thornStem)
            e.addRod(stem, from: front - a * 0.42, to: front + a * 0.72, radius: 0.021)
            for i in 0..<4 {
                let angle = Float(i) * 2.3
                e.addPart(Meshes.cone, Materials.matte(Palette.roseDark), at: front + a * (Float(i) * 0.18 - 0.1) + [cos(angle), 0, sin(angle)] * 0.02,
                          scale: [0.008, 0.035, 0.008], rotation: simd_quatf(from: [0, 1, 0], to: simd_normalize([cos(angle), 0.3, sin(angle)])))
            }
            let top = front + a * 0.8
            e.addSphere(Materials.matte(Palette.roseRed, roughness: 0.6), at: top, radius: 0.05)
            for i in 0..<6 {
                let angle = Float(i) / 6 * 2 * .pi
                e.addPart(Meshes.teardrop, Materials.matte(Palette.rosePink, roughness: 0.6), at: top + [cos(angle), sin(angle), 0] * 0.05,
                          scale: [0.025, 0.035, 0.01], rotation: simd_quatf(angle: angle - .pi / 2, axis: [0, 0, 1]))
            }
            muzzle.position = top
        default: // Dewdrop staff
            e.addRod(Materials.matte(Palette.bark), from: front - a * 0.42, to: front + a * 0.66, radius: 0.02)
            // Three vine tendrils cupping a droplet.
            let vine = Materials.matte(Palette.leaf)
            for i in 0..<3 {
                let angle = Float(i) / 3 * 2 * .pi
                let out = SIMD3<Float>(cos(angle), 0, sin(angle))
                e.addRod(vine, from: front + a * 0.64 + out * 0.02, to: front + a * 0.84 + out * 0.045, radius: 0.008)
            }
            e.addPart(Meshes.teardrop, dew, at: front + a * 0.72, scale: [0.045, 0.07, 0.045], rotation: simd_quatf(angle: 0, axis: a))
            muzzle.position = front + a * 0.76
        }
        e.addChild(muzzle)
        return Held(entity: e, muzzle: muzzle)
    }

    /// Limbs curve forward from the grip; the string, redrawn every frame, runs behind.
    private static func bow(_ item: ItemID) -> Held {
        let e = Entity()
        let long = item == .owlboneBow || item == .mantisLongbow
        let tip: Float = long ? 0.42 : 0.36
        let limbColor = switch item {
        case .owlboneBow: UIColor(red: 0.92, green: 0.89, blue: 0.8, alpha: 1)
        case .silkstringBow: Palette.spiderPurple
        case .mantisLongbow: Palette.mantisPink
        default: UIColor(red: 0.72, green: 0.74, blue: 0.4, alpha: 1)
        }
        let limb = Materials.matte(limbColor, roughness: 0.6)
        let points = (0...10).map { i -> SIMD3<Float> in
            let y = tip * (Float(i) / 5 - 1)
            let s = y / tip
            return [0, y, 0.04 - 0.14 * s * s]
        }
        for (a, b) in zip(points, points.dropFirst()) {
            e.addRod(limb, from: a, to: b, radius: 0.017 - abs(a.y + b.y) / 2 / tip * 0.008)
        }
        e.addCylinder(Materials.matte(Palette.door), at: [0, 0, 0.04], radius: 0.024, height: 0.1)
        let tipTrim = switch item {
        case .owlboneBow: Materials.matte(Palette.owlFeather)
        case .silkstringBow: Materials.glow(Palette.spiderGlow)
        case .mantisLongbow: Materials.matte(Palette.mantisWhite)
        default: Materials.matte(Palette.leaf)
        }
        for end in [points.first!, points.last!] {
            e.addPart(Meshes.teardrop, tipTrim, at: end + [0, 0, 0.02], scale: [0.02, 0.05, 0.012],
                      rotation: simd_quatf(angle: end.y > 0 ? -0.5 : .pi + 0.5, axis: [1, 0, 0]))
        }

        let silk = Materials.matte(UIColor(white: 0.95, alpha: 1), roughness: 0.4)
        let string = (0..<2).map { _ in
            let half = ModelEntity(mesh: Meshes.cylinder, materials: [silk])
            e.addChild(half)
            return half
        }
        let arrow = Entity()
        arrow.addRod(Materials.matte(Palette.stem), from: .zero, to: [0, 0, 0.46], radius: 0.008)
        arrow.addPart(Meshes.cone, Materials.glossy(Palette.shelfFungus), at: [0, 0, 0.49], scale: [0.018, 0.07, 0.018],
                      rotation: simd_quatf(from: [0, 1, 0], to: [0, 0, 1]))
        for side: Float in [-1, 1] {
            arrow.addPart(Meshes.teardrop, Materials.matte(Palette.leaf), at: [side * 0.018, 0, 0.05], scale: [0.018, 0.045, 0.004],
                          rotation: simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]) * simd_quatf(angle: side * 0.3, axis: [0, 0, 1]))
        }
        e.addChild(arrow)
        let muzzle = Entity()
        muzzle.position = [0, 0, 0.3]
        e.addChild(muzzle)
        return Held(entity: e, muzzle: muzzle, string: string, stringTips: [points.last!, points.first!], arrow: arrow)
    }

    /// Stretches a unit cylinder between two points.
    static func fit(_ rod: Entity, from start: SIMD3<Float>, to end: SIMD3<Float>, radius: Float) {
        let axis = end - start
        let length = max(simd_length(axis), 0.0001)
        rod.transform = Transform(scale: [radius, length, radius], rotation: simd_quatf(from: [0, 1, 0], to: axis / length),
                                  translation: (start + end) / 2)
    }

    // MARK: - Shields

    /// A shield in its own frame: facing +Z, strapped to the forearm just behind the face.
    static func makeShield(_ item: ItemID) -> Entity {
        let e = Entity()
        let face = simd_quatf(angle: .pi / 2, axis: [1, 0, 0]) // unit cylinders and tori stand along Y
        switch item {
        case .shellShield:
            e.addCylinder(Materials.glossy(Palette.snailShell), at: [0, 0, 0.05], radius: 0.17, height: 0.03, rotation: face)
            for (i, radius) in [Float(0.13), 0.09, 0.05].enumerated() {
                let color = i.isMultiple(of: 2) ? Palette.snailShellLight : Palette.snailShell
                e.addPart(Meshes.torus(radius: radius, tube: 0.02), Materials.glossy(color), at: [0.012 * Float(i), 0, 0.07 + Float(i) * 0.01],
                          scale: .one, rotation: face)
            }
            e.addSphere(Materials.glossy(Palette.snailShellLight), at: [0.036, 0, 0.1], radius: 0.03)
        case .beetleAegis:
            let shell = Materials.glossy(Palette.beetleShell)
            e.addSphere(shell, at: [0, 0, 0.05], radius: 1, squash: [0.16, 0.21, 0.05])
            e.addPart(Meshes.roundedBox, shell, at: [0, 0, 0.09], scale: [0.025, 0.36, 0.03])
            e.addPart(Meshes.cone, Materials.glossy(Palette.eye), at: [0, 0.1, 0.12], scale: [0.03, 0.12, 0.03],
                      rotation: simd_quatf(from: [0, 1, 0], to: simd_normalize([0, 0.8, 1])))
        case .lilypadTarge:
            e.addCylinder(Materials.matte(Palette.frogGreen, roughness: 0.5), at: [0, 0, 0.05], radius: 0.17, height: 0.025, rotation: face)
            e.addPart(Meshes.torus(radius: 0.17, tube: 0.014), Materials.matte(Palette.moss), at: [0, 0, 0.05], scale: .one, rotation: face)
            e.addSphere(Materials.matte(Palette.rosePink), at: [0.05, 0.05, 0.08], radius: 0.035, squash: [1, 1.3, 1])
        case .mossbackShield:
            e.addSphere(Materials.matte(Palette.turtleShell, roughness: 0.7), at: [0, 0, 0.04], radius: 1, squash: [0.19, 0.21, 0.07])
            let scute = Materials.matte(Palette.turtleShellDark)
            for (x, y) in [(0, 0), (0.08, 0.09), (-0.08, 0.09), (0.08, -0.09), (-0.08, -0.09)] as [(Float, Float)] {
                e.addSphere(scute, at: [x, y, 0.09 - (abs(x) + abs(y)) * 0.15], radius: 0.05, squash: [1, 1, 0.3])
            }
        case .pineconeBulwark:
            e.addSphere(Materials.matte(Palette.pineconeDark), at: [0, 0, 0.04], radius: 1, squash: [0.18, 0.22, 0.05])
            let scale = Materials.matte(Palette.pinecone, roughness: 0.9)
            for row in 0..<4 {
                let y = Float(row) * 0.1 - 0.15
                for column in -1...1 {
                    e.addSphere(scale, at: [Float(column) * 0.08 + (row % 2 == 0 ? 0.04 : 0), y, 0.08], radius: 0.05, squash: [1, 0.6, 0.4])
                }
            }
        default: // Bark buckler
            e.addCylinder(Materials.matte(Palette.bark, roughness: 1), at: [0, 0, 0.05], radius: 0.15, height: 0.035, rotation: face)
            e.addPart(Meshes.torus(radius: 0.15, tube: 0.018), Materials.matte(Palette.darkBark), at: [0, 0, 0.05], scale: .one, rotation: face)
            e.addSphere(Materials.glossy(SproutLook.gold), at: [0, 0, 0.075], radius: 0.04)
        }
        return e
    }
}
