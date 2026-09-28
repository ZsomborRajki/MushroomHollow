import GameCore
import RealityKit
import SwiftUI
import UIKit

/// Sprout, the player character: a chibi forest kid with big anime eyes, a mushroom beret,
/// and a sprout growing out of it. A joint hierarchy (hips, torso, head, shoulders, legs)
/// animated procedurally; gear attaches to the joints. Faces +Z and stands on y = 0.
@MainActor
final class PlayerRig {
    /// Where the right hand grips the dandelion stalk while flying (model space).
    static let gliderGrip: SIMD3<Float> = [-0.36, 0.89, 0.04]

    let root = Entity()
    private(set) var playerClass: PlayerClass?

    private let body = Entity()
    private let hips = Entity()
    private let torso = Entity()
    private let head = Entity()
    private let face: ModelEntity
    private let hat = Entity()
    private let hatCap: ModelEntity
    private let hatSpots = Entity()
    private let sprout = Entity()
    private var arms: [Entity] = []
    private var hands: [Entity] = []
    private var legs: [Entity] = []
    private var scarfTails: [Entity] = []
    private var scarfParts: [ModelEntity] = []
    private var outfitParts: [ModelEntity] = []
    private var bootParts: [ModelEntity] = []
    private var cuffParts: [ModelEntity] = []
    private var gear: [Entity] = []
    private var orb: Entity?
    private var halo: Entity?
    private var expression = FacePainter.Expression.open

    private var swingStart: Double?
    private var swing = Swing.left
    private var comboIndex = 0
    private var lastSwing = -Double.infinity
    private let trail = SwingTrail()
    /// How far the equipped blade reaches from the fist; nil when unarmed.
    private var bladeReach: Float?
    private var hurtStart: Double?
    private var castStart: Double?
    private var cheerStart: Double?

    /// +1 is the character's left (+X), -1 their right (-X). Index 1 holds the weapon.
    private static let sides: [Float] = [1, -1]
    private static let hipHeight: Float = 0.42
    private static let shoulder: SIMD3<Float> = [0.165, 0.3, 0]
    private static let headCenter: SIMD3<Float> = [0, 0.33, 0]
    private static let headRadius: Float = 0.31
    /// Weapons point forward and a little up from the fist while the arm hangs.
    private static let bladeDirection = simd_normalize(SIMD3<Float>(0, 0.35, 1))

    private static let tunicMesh = Meshes.lathe([
        [0, 0.38], [0.08, 0.375], [0.13, 0.345], [0.15, 0.29], [0.145, 0.21], [0.15, 0.14],
        [0.175, 0.07], [0.205, 0], [0.222, -0.05], [0.222, -0.05], [0.2, -0.065], [0, -0.06],
    ])
    private static let capMesh = Meshes.lathe([
        [0, 0.17], [0.08, 0.163], [0.15, 0.14], [0.21, 0.105], [0.26, 0.06], [0.293, 0.015],
        [0.305, -0.02], [0.298, -0.04],
    ])
    private static let capUndersideMesh = Meshes.lathe([[0.298, -0.04], [0.25, -0.045], [0.15, -0.03], [0, -0.02]])

    init() {
        face = ModelEntity(mesh: Meshes.uvSphere, materials: [FacePainter.materials[.open]!])
        hatCap = ModelEntity(mesh: Self.capMesh, materials: [Materials.matte(Palette.capRed, roughness: 0.5)])

        root.addChild(body)
        hips.position = [0, Self.hipHeight, 0]
        body.addChild(hips)
        hips.addChild(torso)
        buildTorso()
        buildLegs()
        buildArms()
        buildHead()
        hips.addChild(trail.entity)
        dress([], playerClass: nil)
    }

    // MARK: - Build

    private func buildTorso() {
        let tunic = ModelEntity(mesh: Self.tunicMesh, materials: [])
        torso.addChild(tunic)
        outfitParts.append(tunic)
        let trim = Materials.matte(SproutLook.trim)
        torso.addPart(Meshes.torus(radius: 0.214, tube: 0.02), trim, at: [0, -0.05, 0], scale: .one)
        torso.addPart(Meshes.torus(radius: 0.148, tube: 0.022), Materials.matte(SproutLook.belt), at: [0, 0.13, 0], scale: .one)
        torso.addPart(Meshes.roundedBox, Materials.glossy(SproutLook.gold), at: [0, 0.13, 0.168], scale: [0.06, 0.05, 0.02])
        for y: Float in [0.22, 0.29] {
            torso.addSphere(trim, at: [0, y, 0.152], radius: 0.014)
        }

        // A chunky knitted scarf with two tails that flutter behind.
        let scarf = torso.addPart(Meshes.torus(radius: 0.1, tube: 0.046), Materials.matte(SproutLook.scarf), at: [0, 0.375, 0],
                                  scale: [1, 0.8, 1])
        scarfParts.append(scarf)
        for side in Self.sides {
            let tail = Entity()
            tail.position = [side * 0.035, 0.36, -0.12]
            let piece = tail.addPart(Meshes.roundedBox, Materials.matte(SproutLook.scarf), at: [0, -0.1, -0.01],
                                     scale: [0.07, 0.2, 0.025])
            scarfParts.append(piece)
            torso.addChild(tail)
            scarfTails.append(tail)
        }
    }

    private func buildLegs() {
        let leggings = Materials.matte(SproutLook.trim)
        for side in Self.sides {
            let leg = Entity()
            leg.position = [side * 0.08, 0, 0]
            leg.addCylinder(leggings, at: [0, -0.13, 0], radius: 0.05, height: 0.26)
            bootParts.append(leg.addPart(Meshes.cylinder, Materials.matte(SproutLook.boots), at: [0, -0.3, 0], scale: [0.062, 0.11, 0.062]))
            bootParts.append(leg.addPart(Meshes.sphere, Materials.matte(SproutLook.boots), at: [0, -0.37, 0.03], scale: [0.07, 0.05, 0.098]))
            cuffParts.append(leg.addPart(Meshes.torus(radius: 0.063, tube: 0.02), Materials.matte(SproutLook.bootCuff),
                                         at: [0, -0.245, 0], scale: .one))
            hips.addChild(leg)
            legs.append(leg)
        }
    }

    private func buildArms() {
        let skin = Materials.matte(SproutLook.skin, roughness: 0.7)
        for side in Self.sides {
            let arm = Entity()
            arm.position = Self.shoulder * [side, 1, 1]
            outfitParts.append(arm.addPart(Meshes.sphere, Materials.matte(SproutLook.tunic), at: [0, -0.02, 0], scale: .init(repeating: 0.068)))
            outfitParts.append(arm.addPart(Meshes.cylinder, Materials.matte(SproutLook.tunic), at: [0, -0.08, 0], scale: [0.044, 0.14, 0.044]))
            arm.addPart(Meshes.torus(radius: 0.044, tube: 0.014), Materials.matte(SproutLook.trim), at: [0, -0.15, 0], scale: .one)
            arm.addCylinder(skin, at: [0, -0.19, 0], radius: 0.036, height: 0.08)
            let hand = Entity()
            hand.position = Self.hand
            hand.addSphere(skin, at: .zero, radius: 0.048)
            arm.addChild(hand)
            torso.addChild(arm)
            arms.append(arm)
            hands.append(hand)
        }
    }

    private func buildHead() {
        head.position = [0, 0.38, 0]
        torso.addChild(head)
        head.addCylinder(Materials.matte(SproutLook.skin, roughness: 0.7), at: [0, 0.03, 0], radius: 0.05, height: 0.08)
        face.transform = Transform(scale: [0.325, Self.headRadius, Self.headRadius], rotation: simd_quatf(angle: 0, axis: [0, 1, 0]),
                                   translation: Self.headCenter)
        head.addChild(face)

        // Hair: a big soft cap, a nape, then locks laid onto the skull.
        let hair = Materials.matte(SproutLook.hair, roughness: 0.55)
        head.addSphere(hair, at: Self.headCenter + [0, 0.045, -0.06], radius: 0.345, squash: [1.02, 0.95, 1])
        head.addSphere(hair, at: Self.headCenter + [0, -0.06, -0.11], radius: 0.27, squash: [1.1, 1, 0.95])
        let bangs: [(lon: Float, lat: Float, size: SIMD3<Float>)] = [
            (-0.8, 0.44, [0.075, 0.1, 0.05]), (-0.47, 0.47, [0.085, 0.115, 0.05]), (-0.16, 0.48, [0.08, 0.12, 0.05]),
            (0.15, 0.49, [0.085, 0.11, 0.05]), (0.46, 0.47, [0.085, 0.115, 0.05]), (0.8, 0.44, [0.075, 0.1, 0.05]),
        ]
        for bang in bangs {
            addLock(hair, lon: bang.lon, lat: bang.lat, size: bang.size, roll: bang.lon * 0.45)
        }
        for side in Self.sides {
            // Side locks framing the cheeks, and spiky tufts around the crown.
            addLock(hair, lon: side * 1.15, lat: -0.05, size: [0.07, 0.19, 0.055], roll: side * 0.1, lift: 0.02)
            addLock(hair, lon: side * 1.6, lat: 0.2, size: [0.09, 0.15, 0.06], roll: side * 0.5)
            addLock(hair, lon: side * 2.25, lat: 0.15, size: [0.1, 0.15, 0.06], roll: side * 0.4)
        }
        for offset: Float in [-1, -0.5, 0, 0.5, 1] {
            addLock(hair, lon: .pi + offset, lat: -0.32, size: [0.1, 0.16, 0.06], roll: -offset * 0.4)
        }
        for offset: Float in [-0.35, 0.35] {
            addLock(hair, lon: .pi + offset, lat: 0.2, size: [0.12, 0.15, 0.06], roll: -offset * 0.4)
        }

        // The Hollow's red mushroom beret, worn at a jaunty angle.
        hat.transform = Transform(scale: .one,
                                  rotation: simd_quatf(angle: 0.2, axis: [0, 0, 1]) * simd_quatf(angle: -0.15, axis: [1, 0, 0]),
                                  translation: [0.02, 0.61, -0.03])
        head.addChild(hat)
        hat.addChild(hatCap)
        hat.addPart(Self.capUndersideMesh, Materials.matte(SproutLook.trim), at: .zero, scale: .one)
        let spot = Materials.matte(Palette.capSpot)
        let spots: [(lon: Float, lat: Float, radius: Float)] = [
            (0.15, 0.95, 0.055), (1.35, 0.45, 0.05), (-1.3, 0.5, 0.05), (2.5, 0.55, 0.045),
            (-2.4, 0.4, 0.05), (-0.55, 0.3, 0.04), (0.75, 0.25, 0.035), (3.1, 0.95, 0.04),
        ]
        let axes = SIMD3<Float>(0.29, 0.165, 0.29)
        for s in spots {
            let p = SIMD3(cos(s.lat) * sin(s.lon), sin(s.lat), cos(s.lat) * cos(s.lon)) * axes
            let normal = simd_normalize(p / (axes * axes))
            hatSpots.addPart(Meshes.sphere, spot, at: p, scale: [s.radius, s.radius * 0.3, s.radius],
                             rotation: simd_quatf(from: [0, 1, 0], to: normal))
        }
        hat.addChild(hatSpots)

        // Sprout's namesake, growing out of the top of the cap.
        sprout.position = [0, 0.155, 0]
        let leaf = Materials.matte(SproutLook.sproutLeaf, roughness: 0.6)
        sprout.addCylinder(leaf, at: [0, 0.04, 0], radius: 0.012, height: 0.08)
        for side in Self.sides {
            sprout.addPart(Meshes.teardrop, leaf, at: [side * 0.045, 0.085, 0], scale: [0.038, 0.065, 0.014],
                           rotation: simd_quatf(angle: side * (.pi / 2 + 0.35), axis: [0, 0, 1]))
        }
        hat.addChild(sprout)
    }

    /// Lays a teardrop lock on the skull at a longitude/latitude, hanging downward.
    private func addLock(_ material: any RealityKit.Material, lon: Float, lat: Float, size: SIMD3<Float>, roll: Float, lift: Float = 0) {
        let direction = SIMD3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))
        let rotation = simd_quatf(angle: lon, axis: [0, 1, 0]) * simd_quatf(angle: -lat, axis: [1, 0, 0])
            * simd_quatf(angle: roll, axis: [0, 0, 1])
        head.addPart(Meshes.teardrop, material, at: Self.headCenter + direction * (Self.headRadius + size.z * 0.4 + lift),
                     scale: size, rotation: rotation)
    }

    // MARK: - Gear

    /// Shows equipped items on the body and a class emblem; the scarf takes the class color.
    func dress(_ items: [ItemID], playerClass: PlayerClass?) {
        self.playerClass = playerClass
        for part in gear { part.removeFromParent() }
        gear = []
        orb = nil
        halo = nil
        bladeReach = nil

        var outfit = Materials.matte(SproutLook.tunic)
        var boots = Materials.matte(SproutLook.boots)
        var cuffs = Materials.matte(SproutLook.bootCuff)
        var cap = Materials.matte(Palette.capRed, roughness: 0.5)
        var showSpots = true

        for item in items {
            switch item {
            case .twigSword, .thornRapier, .beetleBlade, .moonTalon:
                attach(Self.makeWeapon(item), to: hands[1])
                let blade = Self.blade(item)
                bladeReach = blade.reach
                trail.setTint(blade.trail)
            case .acornCap:
                let acorn = Entity()
                acorn.addSphere(Materials.matte(Palette.capBrown, roughness: 0.9), at: [0, 0.12, 0], radius: 0.17, squash: [1, 0.5, 1])
                acorn.addPart(Meshes.torus(radius: 0.165, tube: 0.018), Materials.matte(Palette.darkBark), at: [0, 0.105, 0], scale: .one)
                attach(acorn, to: hat)
            case .beetleHelm:
                cap = Materials.glossy(Palette.beetleShell)
                showSpots = false
                let horn = Entity()
                horn.addPart(Meshes.cone, Materials.glossy(Palette.eye), at: [0, 0.14, 0.22], scale: [0.035, 0.2, 0.035],
                             rotation: simd_quatf(angle: 0.8, axis: [1, 0, 0]))
                attach(horn, to: hat)
            case .leafTunic:
                outfit = Materials.matte(UIColor(red: 0.38, green: 0.62, blue: 0.24, alpha: 1), roughness: 0.7)
                // A collar of leaf petals.
                let collar = Entity()
                let leaf = Materials.matte(Palette.leaf, roughness: 0.7)
                for i in 0..<7 {
                    let a = Float(i) / 7 * 2 * .pi
                    collar.addPart(Meshes.teardrop, leaf, at: [sin(a) * 0.13, 0.32, cos(a) * 0.13], scale: [0.055, 0.085, 0.014],
                                   rotation: simd_quatf(angle: a, axis: [0, 1, 0]) * simd_quatf(angle: -0.6, axis: [1, 0, 0]))
                }
                attach(collar, to: torso)
            case .barkMail:
                outfit = Materials.matte(Palette.bark, roughness: 1)
                let dark = Materials.matte(Palette.darkBark, roughness: 1)
                let bands = Entity()
                bands.addPart(Meshes.torus(radius: 0.15, tube: 0.016), dark, at: [0, 0.23, 0], scale: .one)
                bands.addPart(Meshes.torus(radius: 0.19, tube: 0.016), dark, at: [0, 0.03, 0], scale: .one)
                attach(bands, to: torso)
                for arm in arms {
                    let pad = Entity()
                    pad.addSphere(dark, at: [0, 0.01, 0], radius: 0.085, squash: [1.1, 0.7, 1.1])
                    attach(pad, to: arm)
                }
            case .featherCloak:
                outfit = Materials.matte(UIColor(red: 0.78, green: 0.68, blue: 0.52, alpha: 1))
                let cloak = Entity()
                let feather = Materials.matte(Palette.owlFeather)
                cloak.addSphere(feather, at: [0, 0.1, -0.13], radius: 1, squash: [0.27, 0.36, 0.09])
                for i in 0..<5 {
                    let x = Float(i - 2) * 0.09
                    cloak.addPart(Meshes.teardrop, feather, at: [x, -0.22, -0.15], scale: [0.06, 0.1, 0.02],
                                  rotation: simd_quatf(angle: x * -1.2, axis: [0, 0, 1]))
                }
                attach(cloak, to: torso)
            case .mossBoots:
                boots = Materials.matte(Palette.darkMoss, roughness: 1)
                cuffs = Materials.matte(Palette.moss, roughness: 1)
            default:
                break
            }
        }

        for part in outfitParts { part.model?.materials = [outfit] }
        for part in bootParts { part.model?.materials = [boots] }
        for part in cuffParts { part.model?.materials = [cuffs] }
        hatCap.model?.materials = [cap]
        hatSpots.isEnabled = showSpots
        let scarf = Materials.matte(playerClass.map { UIColor($0.tint) } ?? SproutLook.scarf)
        for part in scarfParts { part.model?.materials = [scarf] }

        switch playerClass {
        case .guardian:
            let shield = Entity()
            shield.addCylinder(Materials.glossy(Palette.bark), at: [0, 0.18, -0.2], radius: 0.19, height: 0.04,
                               rotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))
            shield.addPart(Meshes.torus(radius: 0.19, tube: 0.02), Materials.glossy(SproutLook.gold), at: [0, 0.18, -0.2], scale: .one,
                           rotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))
            shield.addSphere(Materials.glossy(Palette.shelfFungus), at: [0, 0.18, -0.225], radius: 0.055)
            attach(shield, to: torso)
        case .thornshot:
            let quiver = Entity()
            let tilt = simd_quatf(angle: -0.4, axis: [0, 0, 1])
            quiver.addCylinder(Materials.matte(Palette.door), at: [0.05, 0.2, -0.17], radius: 0.055, height: 0.34, rotation: tilt)
            for i in 0..<3 {
                quiver.addPart(Meshes.cone, Materials.matte(Palette.leaf), at: [0.12 + Float(i) * 0.03, 0.42 - Float(i) * 0.015, -0.17],
                               scale: [0.025, 0.14, 0.025], rotation: tilt)
            }
            attach(quiver, to: torso)
        case .sporecaster:
            let orb = Entity()
            orb.addSphere(Materials.glow(UIColor(red: 0.75, green: 0.45, blue: 1, alpha: 1)), at: .zero, radius: 0.1)
            orb.addSphere(Materials.glow(Palette.sporeGlow), at: .zero, radius: 0.05)
            attach(orb, to: root)
            self.orb = orb
        case .dewkeeper:
            let halo = Entity()
            halo.position = [0, 0.93, 0]
            let dew = Materials.glow(UIColor(red: 0.55, green: 0.9, blue: 1, alpha: 1))
            for i in 0..<8 {
                let a = Float(i) / 8 * 2 * .pi
                halo.addSphere(dew, at: [sin(a) * 0.27, 0, cos(a) * 0.27], radius: 0.04)
            }
            attach(halo, to: head)
            self.halo = halo
        case nil:
            break
        }
    }

    private func attach(_ part: Entity, to parent: Entity) {
        parent.addChild(part)
        gear.append(part)
    }

    /// A weapon in fist space: the grip sits in the hand, the blade points along `bladeDirection`.
    private static func makeWeapon(_ item: ItemID) -> Entity {
        let e = Entity()
        let d = bladeDirection
        let along = simd_quatf(from: [0, 1, 0], to: d)
        e.addRod(Materials.matte(Palette.darkBark), from: -d * 0.07, to: d * 0.07, radius: 0.02)
        switch item {
        case .twigSword:
            let wood = Materials.matte(Palette.bark)
            e.addSphere(wood, at: d * 0.07, radius: 0.035)
            e.addRod(wood, from: d * 0.07, to: d * 0.55, radius: 0.024)
            e.addPart(Meshes.teardrop, Materials.matte(Palette.leaf), at: d * 0.4 + [0.04, 0.02, 0], scale: [0.025, 0.045, 0.008],
                      rotation: simd_quatf(angle: -1.1, axis: [0, 0, 1]))
        case .thornRapier:
            let thorn = Materials.glossy(Palette.shelfFungus)
            e.addPart(Meshes.cylinder, thorn, at: d * 0.075, scale: [0.055, 0.015, 0.055], rotation: along)
            e.addPart(Meshes.cone, thorn, at: d * 0.39, scale: [0.022, 0.62, 0.022], rotation: along)
        case .beetleBlade:
            let shell = Materials.glossy(Palette.beetleShell)
            let flat = simd_quatf(from: [0, 0, 1], to: d)
            e.addPart(Meshes.roundedBox, shell, at: d * 0.075, scale: [0.05, 0.16, 0.035], rotation: flat)
            e.addPart(Meshes.box, shell, at: d * 0.33, scale: [0.022, 0.09, 0.5], rotation: flat)
            e.addPart(Meshes.cone, shell, at: d * 0.64, scale: [0.011, 0.12, 0.045], rotation: along)
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
        default:
            break
        }
        return e
    }

    /// How far each blade reaches from the fist, and the color of its swing trail.
    private static func blade(_ item: ItemID) -> (reach: Float, trail: UIColor) {
        switch item {
        case .thornRapier: (0.7, UIColor(red: 1, green: 0.86, blue: 0.55, alpha: 1))
        case .beetleBlade: (0.7, UIColor(red: 0.5, green: 0.72, blue: 1, alpha: 1))
        case .moonTalon: (0.68, UIColor(red: 0.78, green: 0.9, blue: 1, alpha: 1))
        default: (0.55, UIColor(red: 0.85, green: 1, blue: 0.72, alpha: 1))
        }
    }

    // MARK: - Animation

    static let swingDuration = 0.42

    /// The melee auto-attack combo: a fixed four-hit pattern, like Flyff.
    enum Swing: CaseIterable {
        case left, right, up, down

        /// The weapon arm sweeps `sweep` radians from `from` toward `via` (torso space, from the
        /// right shoulder) while the torso turns from `twist.0` to `twist.1`.
        private var arc: (from: SIMD3<Float>, via: SIMD3<Float>, sweep: Float, twist: (Float, Float)) {
            switch self {
            case .left: ([-0.95, -0.15, -0.3], [0, -0.2, 1], 2.7, (-0.5, 0.45)) // right to left, across the chest
            case .right: ([0.75, 0.05, 0.65], [-0.3, 0, 1], 2.8, (0.45, -0.5)) // backhand, left to right
            case .up: ([-0.45, -0.8, -0.3], [-0.15, -0.1, 1], 2.9, (-0.2, 0.25)) // rising from the ground
            case .down: ([-0.55, 0.8, -0.25], [-0.15, 0.2, 1], 2.5, (0.2, -0.1)) // overhead chop
            }
        }

        /// Arm direction and the way the blade trails behind it, `s` of the way through the sweep.
        func arm(_ s: Float) -> (direction: SIMD3<Float>, lean: SIMD3<Float>) {
            let arc = arc
            let from = simd_normalize(arc.from)
            let axis = simd_normalize(simd_cross(from, arc.via))
            let direction = simd_quatf(angle: arc.sweep * s, axis: axis).act(from)
            return (direction, -simd_cross(axis, direction))
        }

        func twist(_ s: Float) -> Float {
            arc.twist.0 + (arc.twist.1 - arc.twist.0) * s
        }
    }

    /// Swing phases as fractions of `swingDuration`: wind up, strike, recover.
    private static let strikeStart: Float = 0.22
    private static let strikeEnd: Float = 0.52
    /// How far back in swing progress the trail reaches.
    private static let trailSpan: Float = 0.2
    /// The wrist cocks the blade out along the arm while swinging.
    private static let wristBend = simd_quatf(angle: 1.35, axis: [1, 0, 0])
    private static let hand: SIMD3<Float> = [0, -0.25, 0]

    func playSwing(at time: Double) {
        if playerClass?.definition.isRanged != true {
            // Start the pattern over after a pause in the fight.
            if time - lastSwing > 2.5 { comboIndex = 0 }
            swing = Swing.allCases[comboIndex % Swing.allCases.count]
            comboIndex += 1
            lastSwing = time
        }
        swingStart = time
    }
    func playHurt(at time: Double) { hurtStart = time }
    func playCast(at time: Double) { castStart = time }
    func playCheer(at time: Double) { cheerStart = time }

    struct Motion {
        var moving = false
        var airborne = false
        var fainted = false
    }

    func animate(_ motion: Motion, time: Double, seed: Float) {
        let t = Float(time)
        let swingProgress = Self.progress(&swingStart, time, duration: Self.swingDuration)
        let hurt = Self.progress(&hurtStart, time, duration: 0.45)
        let cast = Self.progress(&castStart, time, duration: 0.7)
        let cheer = Self.progress(&cheerStart, time, duration: 1.4)

        var armSwing: [Float] = [0, 0] // about X; negative swings forward and up
        var armSpread: [Float] = [0.28, 0.28]
        var legSwing: [Float] = [0, 0] // about X; positive swings back
        var twist: Float = 0
        var nod: Float = 0
        var tilt: Float = 0
        var lift: Float = 0
        var breath: Float = 0
        var sproutSway = sin(t * 2.2 + seed) * 0.12
        var scarfLift = 0.15 + sin(t * 1.7 + seed) * 0.05

        if motion.fainted {
            armSpread = [0.55, 0.55]
            armSwing = [-0.2, -0.3]
            tilt = 0.3
        } else if motion.airborne {
            // Legs dangle and kick; they trail behind when gliding forward.
            let trail: Float = motion.moving ? 0.5 : 0.15
            legSwing = [trail + sin(t * 2.1) * 0.35, trail + sin(t * 2.1 + 2) * 0.35]
            armSpread[0] = 1.1 + sin(t * 2.4) * 0.15
            armSwing[0] = -0.3
            scarfLift = motion.moving ? 1.1 + sin(t * 14) * 0.12 : 0.5 + sin(t * 3) * 0.1
            sproutSway = sin(t * 5) * 0.25
        } else if motion.moving {
            // A bouncy, skipping run (the renderer bobs the whole body in step).
            let stride = sin(t * 11)
            legSwing = [stride * 0.75, -stride * 0.75]
            armSwing = [-stride * 0.65, stride * 0.65]
            twist = stride * 0.1
            nod = 0.06
            scarfLift = 0.75 + sin(t * 16) * 0.12
            sproutSway = stride * 0.3
        } else {
            breath = sin(t * 2.1 + seed)
            armSwing = [breath * 0.04, -breath * 0.04]
            tilt = sin(t * 0.8 + seed) * 0.07
            nod = breath * 0.02
        }

        var slash: (arm: simd_quatf, amount: Float)?
        var slashProgress: Float?
        let baseTwist = twist
        if let p = swingProgress, !motion.fainted {
            if playerClass?.definition.isRanged == true {
                // Point and release, turning the shooting shoulder forward.
                let thrust = sin(p * .pi)
                armSwing[1] = -1.5 * thrust
                armSpread[1] = 0.1
                armSwing[0] = -0.4 * thrust
                twist += 0.25 * thrust
            } else {
                // Cock back, whip through the arc, then ease back to the base pose.
                let phase = Self.slashPhase(p)
                slash = (Self.armPose(swing, phase.s), phase.amount)
                slashProgress = p
                twist += swing.twist(phase.s) * phase.amount
                sproutSway += sin(p * .pi) * 0.4
            }
        }
        if let p = hurt, !motion.fainted {
            nod -= 0.2 * sin(p * .pi)
        }

        var armPose = (0..<2).map { i in
            simd_quatf(angle: Self.sides[i] * armSpread[i], axis: [0, 0, 1]) * simd_quatf(angle: armSwing[i], axis: [1, 0, 0])
        }
        if let slash {
            armPose[1] = simd_slerp(armPose[1], slash.arm, slash.amount)
        }
        if motion.airborne, !motion.fainted {
            // Hanging on to the dandelion stalk.
            let shoulder = SIMD3<Float>(-Self.shoulder.x, Self.hipHeight + Self.shoulder.y, 0)
            armPose[1] = simd_quatf(from: [0, -1, 0], to: simd_normalize(Self.gliderGrip - shoulder))
        } else if let p = cast, !motion.fainted {
            // Both arms up in a V to call the magic down.
            let amount = Self.ease(min(1, p / 0.2) * min(1, (1 - p) / 0.3))
            for i in 0..<2 {
                let raised = simd_quatf(from: [0, -1, 0], to: simd_normalize([Self.sides[i] * 0.6, 0.75, 0.3]))
                armPose[i] = simd_slerp(armPose[i], raised, amount)
            }
            nod -= 0.15 * amount
        }
        if let p = cheer, !motion.fainted, !motion.airborne {
            // Two happy hops with waving arms.
            lift = abs(sin(p * 2 * .pi)) * 0.16
            let amount = Self.ease(min(1, p / 0.15) * min(1, (1 - p) / 0.2))
            for i in 0..<2 {
                let wave = simd_quatf(angle: Self.sides[i] * sin(t * 18) * 0.3, axis: [0, 0, 1])
                let raised = wave * simd_quatf(from: [0, -1, 0], to: simd_normalize([Self.sides[i] * 0.45, 0.85, 0.1]))
                armPose[i] = simd_slerp(armPose[i], raised, amount)
            }
            nod -= 0.12 * amount
        }

        body.position.y = lift
        torso.orientation = simd_quatf(angle: twist, axis: [0, 1, 0])
        torso.scale = [1 + breath * 0.008, 1 + breath * 0.012, 1 + breath * 0.008]
        head.orientation = simd_quatf(angle: nod, axis: [1, 0, 0]) * simd_quatf(angle: tilt, axis: [0, 0, 1])
        for i in 0..<2 {
            arms[i].orientation = armPose[i]
            legs[i].orientation = simd_quatf(angle: legSwing[i], axis: [1, 0, 0])
            scarfTails[i].orientation = simd_quatf(angle: Self.sides[i] * 0.18, axis: [0, 0, 1])
                * simd_quatf(angle: scarfLift + Float(i) * 0.08 + sin(t * 9 + Float(i)) * 0.04, axis: [1, 0, 0])
        }
        let wrist = motion.airborne || cast != nil || cheer != nil ? 0 : slash?.amount ?? 0
        hands[1].orientation = simd_slerp(simd_quatf(angle: 0, axis: [1, 0, 0]), Self.wristBend, wrist)
        if let p = slashProgress, wrist > 0 {
            updateTrail(p, baseTwist: baseTwist)
        } else {
            trail.hide()
        }
        sprout.orientation = simd_quatf(angle: sproutSway, axis: [0, 0, 1])
        orb?.position = [0.42 + cos(t * 0.9) * 0.05, 1.2 + sin(t * 2) * 0.06, -0.05 + sin(t * 0.9) * 0.05]
        halo?.orientation = simd_quatf(angle: t * 0.8, axis: [0, 1, 0])

        // Blink every few seconds, at a different moment for each player.
        let blinking = (t + seed * 0.37).truncatingRemainder(dividingBy: 3.8) < 0.13
        let wanted: FacePainter.Expression = if motion.fainted {
            .fainted
        } else if hurt != nil {
            .hurt
        } else if cheer != nil {
            .happy
        } else {
            blinking ? .blink : .open
        }
        if wanted != expression, let material = FacePainter.materials[wanted] {
            expression = wanted
            face.model?.materials = [material]
        }
    }

    /// Where a melee swing is: `s` runs along the arc (a little negative while cocking back),
    /// `amount` blends from the base pose into the swing and back out.
    private static func slashPhase(_ p: Float) -> (s: Float, amount: Float) {
        let windup: Float = -0.12
        if p < strikeStart {
            let x = ease(p / strikeStart)
            return (windup * x, x)
        } else if p < strikeEnd {
            let x = (p - strikeStart) / (strikeEnd - strikeStart)
            return (windup + (1 - windup) * (1 - pow(1 - x, 3)), 1)
        } else {
            return (1, 1 - ease((p - strikeEnd) / (1 - strikeEnd)))
        }
    }

    /// Arm rotation pointing the weapon arm along the swing, the fist's forward (+Z) trailing.
    private static func armPose(_ swing: Swing, _ s: Float) -> simd_quatf {
        let (direction, lean) = swing.arm(s)
        let y = -direction
        let z = simd_normalize(lean - simd_dot(lean, direction) * direction)
        return simd_quatf(simd_float3x3(simd_cross(y, z), y, z))
    }

    /// Sweeps the trail over where the blade was during the last `trailSpan` of the strike.
    private func updateTrail(_ p: Float, baseTwist: Float) {
        guard let reach = bladeReach else {
            trail.hide()
            return
        }
        let head = min(p, Self.strikeEnd)
        let tail = max(Self.strikeStart, p - Self.trailSpan)
        guard head > tail else {
            trail.hide()
            return
        }
        let shoulder = Self.shoulder * [Self.sides[1], 1, 1]
        let hilt = Self.bladeDirection * 0.16
        let tip = Self.bladeDirection * reach
        let hand = Self.hand, wristBend = Self.wristBend
        let samples = (0...SwingTrail.segments).map { i in
            let s = Self.slashPhase(tail + (head - tail) * Float(i) / Float(SwingTrail.segments)).s
            let torso = simd_quatf(angle: baseTwist + swing.twist(s), axis: [0, 1, 0])
            let arm = Self.armPose(swing, s)
            func place(_ point: SIMD3<Float>) -> SIMD3<Float> {
                torso.act(shoulder + arm.act(hand + wristBend.act(point)))
            }
            return (hilt: place(hilt), tip: place(tip))
        }
        // Once the blade stops, the tail catches up and the whole ribbon fades.
        let strength = p > Self.strikeEnd ? 1 - (p - Self.strikeEnd) / Self.trailSpan : 1
        trail.show(samples, strength: strength)
    }

    /// 0...1 progress of a timed move, clearing it once it's over.
    private static func progress(_ start: inout Double?, _ time: Double, duration: Double) -> Float? {
        guard let begin = start else { return nil }
        let p = (time - begin) / duration
        guard p >= 0, p < 1 else {
            start = nil
            return nil
        }
        return Float(p)
    }

    private static func ease(_ x: Float) -> Float {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }
}
