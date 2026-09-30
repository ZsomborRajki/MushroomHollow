import GameCore
import RealityKit
import SwiftUI
import UIKit

/// Sprout, the player character, in lively Flyff proportions: about five and a half heads tall,
/// long-legged and slim-waisted, with big fists and chunky cuffed boots, baggy shorts over bare
/// knees, a short-sleeved vest, pointed ears, big anime eyes, and spiky hair (with a sprout leaf
/// growing out of it). A joint hierarchy (hips, torso, head, shoulders, elbows, legs, knees)
/// animated procedurally, springy and never stiff: knees and elbows stay a little bent. Gear
/// attaches to the joints and every armor piece changes the outfit's shape and colors.
/// Townsfolk use the same body with their own `Look`. Faces +Z and stands on y = 0.
@MainActor
final class PlayerRig {
    /// Where the right hand grips the dandelion stalk while flying (model space).
    static let gliderGrip: SIMD3<Float> = [-0.42, hipHeight + 0.77, 0.04]

    let look: Look

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
    private var elbows: [Entity] = []
    private var hands: [Entity] = []
    private var legs: [Entity] = []
    private var knees: [Entity] = []
    private var scarfTails: [Entity] = []
    private var scarfParts: [ModelEntity] = []
    private var outfitParts: [ModelEntity] = []
    private var legParts: [ModelEntity] = []
    /// Bare knees and shins, covered by trousers when body armor is worn.
    private var shinParts: [ModelEntity] = []
    /// Wristbands, hidden under gloves.
    private var bandParts: [ModelEntity] = []
    private var bootParts: [ModelEntity] = []
    private var cuffParts: [ModelEntity] = []
    private var gear: [Entity] = []
    private var orb: Entity?
    private var halo: Entity?
    private var expression = FacePainter.Expression.open
    private var weapon: WeaponType?
    private var held: WeaponModels.Held?
    private var shield: Entity?

    private var swingStart: Double?
    private var swing = Swing.left
    private var comboIndex = 0
    private var lastSwing = -Double.infinity
    private let trail = SwingTrail()
    /// How far the equipped weapon's edge reaches from the fist; nil when it leaves no trail.
    private var bladeReach: Float?
    private var hurtStart: Double?
    private var blockStart: Double?
    private var castStart: Double?
    private var cheerStart: Double?
    /// 0 relaxed ... 1 in the battle stance; eases toward the wanted pose each frame.
    private var stance: Float = 0
    /// 0 standing ... 1 sitting on the ground.
    private var sit: Float = 0
    private var lastCombat = -Double.infinity
    private var lastFrame: Double?

    /// +1 is the character's left (+X), -1 their right (-X). Index 1 holds the weapon.
    private static let sides: [Float] = [1, -1]
    private static let hipHeight: Float = 0.8
    /// Hip to knee; the shin runs from the knee down to the ground.
    private static let thighLength: Float = 0.38
    private static let shinLength: Float = hipHeight - thighLength
    private static let knee: SIMD3<Float> = [0, -thighLength, 0]
    private static let shoulder: SIMD3<Float> = [0.15, 0.4, 0]
    /// Shoulder to elbow (arm space), then elbow to the fist.
    private static let elbow: SIMD3<Float> = [0, -0.2, 0]
    private static let forearmHand: SIMD3<Float> = [0, -0.22, 0]
    /// Fists (and the gloves over them) are drawn big, Flyff style.
    private static let fistSize: Float = 1.6
    /// The head keeps its anime detail but is drawn at a realistic size (Flyff's vagrant, about
    /// five and a half heads tall), not Sprout's old chibi one.
    private static let headScale: Float = 0.46
    private static let headCenter: SIMD3<Float> = [0, 0.33, 0]
    private static let headRadius: Float = 0.31

    /// A short vest over square shoulders, a chest, and a narrow waist, ending just above the
    /// belt (Flyff's travelling clothes). Wider than it is deep, like a body.
    private static let tunicMesh = Meshes.loft([
        .init(0.455, 0, 0), .init(0.452, 0.045, 0.04), .init(0.44, 0.095, 0.066), .init(0.42, 0.132, 0.08),
        .init(0.385, 0.146, 0.088), .init(0.34, 0.138, 0.094, 0.008), .init(0.27, 0.124, 0.09, 0.006),
        .init(0.2, 0.108, 0.078), .init(0.15, 0.102, 0.075), .init(0.11, 0.108, 0.08), .init(0.085, 0.114, 0.084),
        .init(0.075, 0.09, 0.066), .init(0.075, 0, 0),
    ], segments: 28, name: "tunic")
    /// Baggy shorts from under the vest to the hips, where the legs take over (hips space).
    private static let pelvisMesh = Meshes.loft([
        .init(0.2, 0, 0), .init(0.19, 0.098, 0.074), .init(0.1, 0.122, 0.088), .init(0.02, 0.142, 0.098),
        .init(-0.04, 0.146, 0.1), .init(-0.075, 0.1, 0.08), .init(-0.085, 0, 0),
    ], segments: 24, name: "pelvis")
    /// A puffed short sleeve from the shoulder to the middle of the upper arm.
    private static let sleeveMesh = Meshes.loft([
        .init(0.035, 0, 0), .init(0.025, 0.048, 0.052), .init(0, 0.066, 0.066), .init(-0.05, 0.068, 0.066),
        .init(-0.1, 0.064, 0.062), .init(-0.128, 0.06, 0.058), .init(-0.138, 0.042, 0.042), .init(-0.138, 0, 0),
    ], segments: 16, name: "sleeve")
    /// The bare upper arm below the sleeve, down to the elbow.
    private static let upperArmMesh = Meshes.loft([
        .init(-0.1, 0, 0), .init(-0.105, 0.036, 0.037), .init(-0.16, 0.034, 0.035), .init(-0.2, 0.032, 0.032),
        .init(-0.215, 0, 0),
    ], segments: 14, name: "upperArm")
    /// A forearm swelling below the elbow and slimming to the wrist (elbow space).
    private static let forearmMesh = Meshes.loft([
        .init(0.015, 0, 0), .init(0.005, 0.032, 0.032), .init(-0.05, 0.036, 0.034, 0.003), .init(-0.12, 0.03, 0.028),
        .init(-0.19, 0.025, 0.023), .init(-0.2, 0, 0),
    ], segments: 14, name: "forearm")
    /// A chunky band around the wrist (elbow space).
    private static let wristbandMesh = Meshes.loft([
        .init(-0.13, 0, 0), .init(-0.132, 0.035, 0.033), .init(-0.195, 0.032, 0.03), .init(-0.198, 0, 0),
    ], segments: 14, name: "wristband")
    /// A closed fist: knuckles run front to back while the arm hangs, the palm against the thigh.
    private static let fistMesh = Meshes.loft([
        .init(0.035, 0, 0), .init(0.03, 0.022, 0.026), .init(0.012, 0.033, 0.042), .init(-0.015, 0.037, 0.046, 0.003),
        .init(-0.038, 0.033, 0.042, 0.002), .init(-0.052, 0.022, 0.03), .init(-0.057, 0, 0),
    ], segments: 14, name: "fist")
    /// Baggy shorts down the thigh, flaring to a hem above the knee (leg space).
    private static let shortsMesh = Meshes.loft([
        .init(0.04, 0, 0), .init(0.03, 0.064, 0.066), .init(-0.02, 0.076, 0.08), .init(-0.08, 0.082, 0.084),
        .init(-0.15, 0.092, 0.09), .init(-0.2, 0.1, 0.096), .init(-0.215, 0.102, 0.097), .init(-0.225, 0.064, 0.064),
        .init(-0.23, 0, 0),
    ], segments: 18, name: "shorts")
    /// The bare thigh between the hem and the knee (leg space).
    private static let thighMesh = Meshes.loft([
        .init(-0.17, 0, 0), .init(-0.18, 0.056, 0.058), .init(-0.3, 0.05, 0.052), .init(-0.38, 0.046, 0.048),
        .init(-0.395, 0, 0),
    ], segments: 16, name: "thigh")
    /// Knee to the boot: a slim shin (knee space).
    private static let shinMesh = Meshes.loft([
        .init(0.02, 0, 0), .init(0.01, 0.047, 0.049), .init(-0.05, 0.05, 0.053, 0.006), .init(-0.12, 0.046, 0.048, 0.004),
        .init(-0.19, 0.038, 0.04), .init(-0.2, 0, 0),
    ], segments: 16, name: "shin")
    /// A boot's shaft, from mid-shin to the ankle, widening toward the foot (knee space).
    private static let bootShaftMesh = Meshes.loft([
        .init(-0.13, 0, 0), .init(-0.135, 0.058, 0.061), .init(-0.22, 0.056, 0.059), .init(-0.3, 0.064, 0.068, 0.006),
        .init(-0.345, 0.07, 0.076, 0.012), .init(-0.355, 0, 0),
    ], segments: 18, name: "bootShaft")
    /// The boot's big folded-over cuff, flaring out at the top of the shaft (knee space).
    private static let bootCuffMesh = Meshes.lathe([
        [0.055, -0.095], [0.078, -0.1], [0.1, -0.16], [0.095, -0.19], [0.06, -0.182], [0.055, -0.095],
    ], segments: 24, closed: true)
    /// The foot of a big, chunky boot, lofted toe to heel along its Y (running down its Y, like
    /// every loft, so it faces outward) and laid flat, so the sole stays level while the top
    /// slopes down to a round toe.
    private static let bootFootMesh = Meshes.loft([
        (-0.09, 0.0, 0.0), (-0.085, 0.056, 0.042), (-0.05, 0.07, 0.062), (0.0, 0.074, 0.066), (0.07, 0.078, 0.056),
        (0.14, 0.076, 0.05), (0.19, 0.062, 0.042), (0.218, 0.036, 0.026), (0.226, 0.0, 0.0),
    ].reversed().map { Meshes.Section($0.0, $0.1, $0.2, PlayerRig.soleLevel - $0.2) }, segments: 16, name: "bootFoot")
    private static let soleLevel: Float = 0.03
    private static let robeMesh = Meshes.lathe([
        [0.17, 0.02], [0.19, -0.1], [0.22, -0.27], [0.25, -0.46], [0.26, -0.5], [0.2, -0.51], [0.15, -0.33], [0.13, 0.02],
    ])
    private static let capMesh = Meshes.lathe([
        [0, 0.17], [0.08, 0.163], [0.15, 0.14], [0.21, 0.105], [0.26, 0.06], [0.293, 0.015],
        [0.305, -0.02], [0.298, -0.04],
    ])
    private static let capUndersideMesh = Meshes.lathe([[0.298, -0.04], [0.25, -0.045], [0.15, -0.03], [0, -0.02]])

    init(look: Look = .sprout) {
        self.look = look
        // Paint the faces it will show up front, so the first blink doesn't hitch (townsfolk only blink).
        let expressions: [FacePainter.Expression] = look.face == .sprout ? FacePainter.Expression.allCases : [.open, .blink]
        for expression in expressions { _ = FacePainter.material(expression, look.face) }
        face = ModelEntity(mesh: Meshes.animeFace, materials: [FacePainter.material(.open, look.face)])
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
        let trim = Materials.matte(look.trim)
        // The vest's hem at the waist, and the shirt showing between its open fronts.
        torso.addPart(Meshes.torus(radius: 0.11, tube: 0.016), trim, at: [0, 0.088, 0], scale: [1.02, 1, 0.76])
        torso.addPart(Meshes.roundedBox, Materials.matte(look.shirt ?? look.trim), at: [0, 0.27, 0.083], scale: [0.13, 0.3, 0.03],
                      rotation: simd_quatf(angle: -0.1, axis: [1, 0, 0]))
        for side in Self.sides {
            // Lapels folding back from the collar, narrowing to the waist.
            torso.addPart(Meshes.roundedBox, trim, at: [side * 0.068, 0.29, 0.095], scale: [0.035, 0.26, 0.022],
                          rotation: simd_quatf(angle: -0.1, axis: [1, 0, 0]) * simd_quatf(angle: -side * 0.12, axis: [0, 0, 1]))
        }
        // Shorts from under the vest to the thighs, belted at the waist (on the hips, so they
        // don't lean with the chest).
        legParts.append(hips.addPart(Self.pelvisMesh, Materials.matte(look.legs), at: .zero, scale: .one))
        hips.addPart(Meshes.torus(radius: 0.128, tube: 0.019), Materials.matte(SproutLook.belt), at: [0, 0.075, 0], scale: [1, 1, 0.74])
        hips.addPart(Meshes.roundedBox, Materials.glossy(SproutLook.gold), at: [0, 0.075, 0.097], scale: [0.055, 0.045, 0.02])
        // A slim neck, a little forward of the shoulders.
        torso.addPart(Meshes.loft([.init(0.57, 0.032, 0.034, 0.01), .init(0.48, 0.035, 0.037, 0.004), .init(0.42, 0.045, 0.042)],
                                  segments: 14, name: "neck"),
                      Materials.matte(look.skin, roughness: 0.7), at: .zero, scale: .one)

        // A knitted scarf with two tails that flutter behind (it takes the class color).
        guard look.scarf else { return }
        let scarf = torso.addPart(Meshes.torus(radius: 0.078, tube: 0.029), Materials.matte(SproutLook.scarf), at: [0, 0.44, 0],
                                  scale: [1, 0.8, 1])
        scarfParts.append(scarf)
        for side in Self.sides {
            let tail = Entity()
            tail.position = [side * 0.03, 0.42, -0.1]
            let piece = tail.addPart(Meshes.roundedBox, Materials.matte(SproutLook.scarf), at: [0, -0.12, -0.01],
                                     scale: [0.065, 0.24, 0.022])
            scarfParts.append(piece)
            torso.addChild(tail)
            scarfTails.append(tail)
        }
    }

    private func buildLegs() {
        let leggings = Materials.matte(look.legs)
        let shins = Materials.matte(look.bareLegs ? look.skin : look.legs, roughness: 0.7)
        let boots = Materials.matte(look.boots)
        for side in Self.sides {
            let leg = Entity()
            leg.position = [side * 0.08, 0, 0]
            legParts.append(leg.addPart(Self.shortsMesh, leggings, at: .zero, scale: .one))
            // A rolled hem, tipped out a little like the baggy shorts in Flyff.
            legParts.append(leg.addPart(Meshes.torus(radius: 0.097, tube: 0.017), leggings, at: [side * 0.004, -0.21, 0],
                                        scale: [1, 1, 1.0], rotation: simd_quatf(angle: -side * 0.08, axis: [0, 0, 1])))
            shinParts.append(leg.addPart(Self.thighMesh, shins, at: .zero, scale: .one))
            let knee = Entity()
            knee.position = Self.knee
            shinParts.append(knee.addPart(Meshes.sphere, shins, at: [0, 0, 0.004], scale: [0.047, 0.05, 0.05]))
            shinParts.append(knee.addPart(Self.shinMesh, shins, at: .zero, scale: .one))
            bootParts.append(knee.addPart(Self.bootShaftMesh, boots, at: .zero, scale: .one))
            // Laid flat so the sole sits on the ground (the shin's length below the knee).
            bootParts.append(knee.addPart(Self.bootFootMesh, boots, at: [0, Self.soleLevel - Self.shinLength, 0.018],
                                          scale: .one, rotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0])))
            cuffParts.append(knee.addPart(Self.bootCuffMesh, Materials.matte(look.bootCuff), at: .zero, scale: [1, 1, 1.04]))
            leg.addChild(knee)
            hips.addChild(leg)
            legs.append(leg)
            knees.append(knee)
        }
    }

    private func buildArms() {
        let skin = Materials.matte(look.skin, roughness: 0.7)
        for side in Self.sides {
            let arm = Entity()
            arm.position = Self.shoulder * [side, 1, 1]
            outfitParts.append(arm.addPart(Self.sleeveMesh, Materials.matte(look.tunic), at: .zero, scale: .one))
            arm.addPart(Meshes.torus(radius: 0.058, tube: 0.017), Materials.matte(look.trim), at: [0, -0.125, 0], scale: .one)
            arm.addPart(Self.upperArmMesh, skin, at: .zero, scale: .one)
            let elbow = Entity()
            elbow.position = Self.elbow
            elbow.addPart(Meshes.sphere, skin, at: .zero, scale: .init(repeating: 0.033))
            elbow.addPart(Self.forearmMesh, skin, at: .zero, scale: .one)
            bandParts.append(elbow.addPart(Self.wristbandMesh, Materials.matte(look.bootCuff), at: .zero, scale: .one))
            let hand = Entity()
            hand.position = Self.forearmHand
            addFist(to: hand, skin)
            elbow.addChild(hand)
            arm.addChild(elbow)
            torso.addChild(arm)
            arms.append(arm)
            elbows.append(elbow)
            hands.append(hand)
        }
    }

    /// A fist with its thumb folded over the front, `grow` times the bare hand's size (gloves).
    private func addFist(to hand: Entity, _ material: any RealityKit.Material, grow: Float = 1) {
        let grow = grow * Self.fistSize
        hand.addPart(Self.fistMesh, material, at: [0, 0.01, 0] * grow, scale: .init(repeating: grow))
        hand.addPart(Meshes.sphere, material, at: [0, 0.006, 0.036] * grow, scale: [0.017, 0.028, 0.016] * grow,
                     rotation: simd_quatf(angle: -0.5, axis: [1, 0, 0]))
    }

    private func buildHead() {
        head.position = [0, 0.53, 0]
        head.scale = SIMD3(repeating: Self.headScale)
        torso.addChild(head)
        let skin = Materials.matte(look.skin, roughness: 0.7)
        face.transform = Transform(scale: [0.32, Self.headRadius, Self.headRadius], rotation: simd_quatf(angle: 0, axis: [0, 1, 0]),
                                   translation: Self.headCenter)
        head.addChild(face)
        // Long pointed ears (Flyff's), sweeping up and back out of the side locks.
        for side in Self.sides {
            addLock(skin, lon: side * 1.55, lat: -0.05, size: [0.05, 0.15, 0.024], roll: side * 1.1 + .pi, lift: 0.01)
        }

        // Hair: a soft cap hugging the skull, then pointed locks laid onto it, so the outline is
        // all spikes (Flyff's hair) rather than one round ball.
        let hair = Materials.matte(look.hair, roughness: 0.55)
        head.addPart(Meshes.animeHead, hair, at: Self.headCenter + [0, 0.035, -0.045], scale: [0.335, 0.31, 0.32])
        head.addSphere(hair, at: Self.headCenter + [0, -0.07, -0.1], radius: 0.24, squash: [1.12, 1, 0.95])
        // Bangs parted off center, their points reaching the brows.
        let bangs: [(lon: Float, lat: Float, size: SIMD3<Float>, roll: Float)] = [
            (-0.86, 0.36, [0.075, 0.14, 0.05], -0.25), (-0.56, 0.47, [0.085, 0.15, 0.05], -0.32),
            (-0.24, 0.52, [0.08, 0.15, 0.05], -0.22), (0.02, 0.54, [0.07, 0.13, 0.05], 0.12),
            (0.3, 0.51, [0.085, 0.15, 0.05], 0.3), (0.6, 0.46, [0.085, 0.14, 0.05], 0.36),
            (0.9, 0.36, [0.075, 0.13, 0.05], 0.3),
        ]
        for bang in bangs {
            addLock(hair, lon: bang.lon, lat: bang.lat, size: bang.size, roll: bang.roll)
        }
        for side in Self.sides {
            // Long locks framing the cheeks down to the jaw, then spiky tufts flaring out around the head.
            addLock(hair, lon: side * 1.12, lat: -0.02, size: [0.07, 0.22, 0.055], roll: side * 0.08, lift: 0.015)
            addLock(hair, lon: side * 1.3, lat: 0.3, size: [0.08, 0.16, 0.06], roll: side * 0.35)
            addLock(hair, lon: side * 1.75, lat: 0.12, size: [0.09, 0.17, 0.06], roll: side * 0.6)
            addLock(hair, lon: side * 2.3, lat: 0.05, size: [0.1, 0.17, 0.06], roll: side * 0.55)
            addLock(hair, lon: side * 2.0, lat: 0.62, size: [0.1, 0.14, 0.06], roll: side * 0.9)
        }
        for offset: Float in [-1, -0.5, 0, 0.5, 1] {
            addLock(hair, lon: .pi + offset, lat: -0.36, size: [0.1, 0.18, 0.06], roll: -offset * 0.5)
        }
        for offset: Float in [-0.6, 0, 0.6] {
            addLock(hair, lon: .pi + offset, lat: 0.25, size: [0.12, 0.16, 0.06], roll: -offset * 0.5)
        }
        // A cowlick on the crown, sweeping up and back.
        addLock(hair, lon: .pi - 0.2, lat: 1.05, size: [0.07, 0.13, 0.05], roll: .pi + 0.35, lift: 0.01)
        switch look.hairStyle {
        case .short:
            break
        case .long:
            // Down past the shoulders, behind and beside the face.
            for offset: Float in [-1.1, -0.55, 0, 0.55, 1.1] {
                addLock(hair, lon: .pi + offset, lat: -0.5, size: [0.12, 0.3, 0.06], roll: -offset * 0.25, lift: 0.02, flare: 0.25)
            }
            for side in Self.sides {
                addLock(hair, lon: side * 1.45, lat: -0.4, size: [0.08, 0.28, 0.055], roll: side * 0.1, lift: 0.03, flare: 0.15)
            }
        case .ponytail:
            // Tied high at the back, swinging out behind.
            head.addSphere(Materials.matte(look.trim), at: Self.headCenter + [0, 0.1, -0.35], radius: 0.05)
            addLock(hair, lon: .pi, lat: 0.05, size: [0.12, 0.3, 0.07], roll: 0, lift: 0.12, flare: 0.5)
            addLock(hair, lon: .pi + 0.15, lat: 0.1, size: [0.09, 0.24, 0.06], roll: -0.3, lift: 0.1, flare: 0.4)
        }

        if let beard = look.beard {
            // A long beard or a bushy moustache under the nose.
            let material = Materials.matte(beard, roughness: 0.9)
            if look.longBeard {
                head.addSphere(material, at: Self.headCenter + [0, -0.3, 0.2], radius: 0.2, squash: [1, 1.4, 0.7])
                head.addPart(Meshes.cone, material, at: Self.headCenter + [0, -0.55, 0.22], scale: [0.13, 0.3, 0.1],
                             rotation: simd_quatf(angle: .pi, axis: [1, 0, 0]))
            } else {
                for side in Self.sides {
                    head.addSphere(material, at: Self.headCenter + [side * 0.08, -0.1, 0.29], radius: 0.07, squash: [1.3, 0.6, 0.6])
                }
            }
        }
        if let cap = look.cap { head.addChild(cap.build()) }

        // Equipped hats sit on this (hidden while none is worn, so the hair shows, as in Flyff).
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

        // Sprout's namesake: a little leaf growing out of the crown.
        sprout.position = [0, 0.69, -0.02]
        let leaf = Materials.matte(SproutLook.sproutLeaf, roughness: 0.6)
        sprout.addCylinder(leaf, at: [0, 0.04, 0], radius: 0.012, height: 0.08)
        for side in Self.sides {
            sprout.addPart(Meshes.teardrop, leaf, at: [side * 0.045, 0.085, 0], scale: [0.038, 0.065, 0.014],
                           rotation: simd_quatf(angle: side * (.pi / 2 + 0.35), axis: [0, 0, 1]))
        }
        if look.sprout { head.addChild(sprout) }
    }

    /// Lays a pointed lock (or an ear) on the skull at a longitude/latitude, hanging downward.
    /// `flare` swings the point out away from the head.
    private func addLock(_ material: any RealityKit.Material, lon: Float, lat: Float, size: SIMD3<Float>, roll: Float, lift: Float = 0,
                         flare: Float = 0) {
        let direction = SIMD3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))
        let rotation = simd_quatf(angle: lon, axis: [0, 1, 0]) * simd_quatf(angle: -lat - flare, axis: [1, 0, 0])
            * simd_quatf(angle: roll, axis: [0, 0, 1])
        head.addPart(Meshes.hairLock, material, at: Self.headCenter + direction * (Self.headRadius + size.z * 0.4 + lift),
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
        weapon = nil
        held = nil
        shield = nil
        bladeReach = nil
        hands[0].orientation = Self.identity

        var outfit = Materials.matte(look.tunic)
        var leggings = Materials.matte(look.legs)
        var shins = Materials.matte(look.bareLegs ? look.skin : look.legs, roughness: 0.7)
        var boots = Materials.matte(look.boots)
        var cuffs = Materials.matte(look.bootCuff)
        var cap = Materials.matte(Palette.capRed, roughness: 0.5)
        var showSpots = true
        var wearsHat = false
        // A complete set makes its trim glow.
        let fullSet = ItemSet.allCases.first { $0.definition.pieces.allSatisfy(items.contains) }

        for item in items {
            if let type = item.definition.weaponType {
                // Bows sit in the left hand so the right can draw the string.
                let model = WeaponModels.make(item)
                attach(model.entity, to: type == .bow ? hands[0] : hands[1])
                weapon = type
                held = model
                if let blade = model.trail {
                    bladeReach = blade.reach
                    trail.setTint(blade.tint)
                }
                continue
            }
            if item.definition.equipSlot == .shield {
                let model = WeaponModels.makeShield(item)
                attach(model, to: hands[0])
                shield = model
                continue
            }
            if item.definition.equipSlot == .hat { wearsHat = true }
            if item.definition.equipSlot == .body, let style = Self.bodyStyle(item) {
                // Legs match the armor, a shade darker (Flyff sets come with trousers).
                leggings = Materials.matte(Self.bodyColor(item).darker(0.72))
                shins = leggings
                addBodyStyle(style, color: Self.bodyColor(item), trim: Self.bodyTrim(item))
            }
            switch item {
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
                    collar.addPart(Meshes.teardrop, leaf, at: [sin(a) * 0.13, 0.32, cos(a) * 0.1 + 0.008], scale: [0.055, 0.085, 0.014],
                                   rotation: simd_quatf(angle: a, axis: [0, 1, 0]) * simd_quatf(angle: -0.6, axis: [1, 0, 0]))
                }
                attach(collar, to: torso)
            case .barkMail:
                outfit = Materials.matte(Palette.bark, roughness: 1)
                let dark = Materials.matte(Palette.darkBark, roughness: 1)
                let bands = Entity()
                bands.addPart(Meshes.torus(radius: 0.126, tube: 0.016), dark, at: [0, 0.23, 0], scale: [1, 1, 0.74])
                bands.addPart(Meshes.torus(radius: 0.158, tube: 0.016), dark, at: [0, 0.03, 0], scale: [1, 1, 0.72])
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
            case .honeycombHelm:
                cap = Materials.glossy(Palette.beeYellow)
                showSpots = false
                let stripe = Entity()
                stripe.addPart(Meshes.torus(radius: 0.255, tube: 0.022), Materials.matte(Palette.bugBlack), at: [0, 0.06, 0], scale: .one)
                attach(stripe, to: hat)
            case .pineconeHelm:
                cap = Materials.matte(Palette.pineconeDark, roughness: 0.9)
                showSpots = false
                let scales = Entity()
                let scale = Materials.matte(Palette.pinecone, roughness: 0.9)
                for (ring, (radius, y)) in [(Float(0.245), Float(0.07)), (0.17, 0.135)].enumerated() {
                    for i in 0..<8 {
                        let a = (Float(i) + Float(ring) * 0.5) / 8 * 2 * .pi
                        scales.addSphere(scale, at: [sin(a) * radius, y, cos(a) * radius], radius: 0.05, squash: [1, 0.6, 1])
                    }
                }
                attach(scales, to: hat)
            case .turtleshellMail:
                outfit = Materials.matte(Palette.turtleSkin, roughness: 0.8)
                let shell = Entity()
                shell.addSphere(Materials.matte(Palette.turtleShell, roughness: 0.7), at: [0, 0.12, -0.14], radius: 1, squash: [0.24, 0.3, 0.1])
                shell.addSphere(Materials.matte(Palette.turtleShellDark), at: [0, 0.14, -0.22], radius: 0.07, squash: [1, 1, 0.4])
                attach(shell, to: torso)
            case .mantisCarapace:
                outfit = Materials.matte(Palette.mantisWhite, roughness: 0.6)
                for arm in arms {
                    let petal = Entity()
                    petal.addSphere(Materials.matte(Palette.mantisPink, roughness: 0.6), at: [0, 0.02, 0], radius: 0.09, squash: [1.2, 0.6, 1.1])
                    attach(petal, to: arm)
                }
            case .warrenCrown:
                cap = Materials.matte(Palette.moleKing, roughness: 1)
                showSpots = false
                let crown = Entity()
                let gold = Materials.glossy(Palette.crown)
                crown.addPart(Meshes.torus(radius: 0.17, tube: 0.025), gold, at: [0, 0.13, 0], scale: .one)
                for i in 0..<6 {
                    let a = Float(i) / 6 * 2 * .pi
                    crown.addPart(Meshes.cone, gold, at: [sin(a) * 0.17, 0.19, cos(a) * 0.17], scale: [0.03, 0.09, 0.03])
                }
                crown.addSphere(Materials.glow(Palette.roseRed), at: [0, 0.14, 0.19], radius: 0.028)
                attach(crown, to: hat)
            case .tunnelerClaws:
                addGloves(Materials.matte(Palette.molePink, roughness: 0.7), cuff: Materials.matte(Palette.moleFur, roughness: 1))
            case .silkweaveGloves:
                addGloves(Materials.matte(Palette.mothFur, roughness: 0.8), cuff: Materials.matte(Palette.spiderPurple))
            case .rosethornGauntlets:
                addGloves(Materials.matte(Palette.roseRed, roughness: 0.6), cuff: Materials.matte(Palette.thornStem))
            case .frogHoppers:
                boots = Materials.matte(Palette.frogGreen, roughness: 0.5)
                cuffs = Materials.matte(Palette.frogBelly, roughness: 0.8)
            case .quilledBoots:
                boots = Materials.matte(Palette.hedgehogBrown, roughness: 1)
                cuffs = Materials.matte(Palette.quill, roughness: 0.8)
            case .mossBoots:
                boots = Materials.matte(Palette.darkMoss, roughness: 1)
                cuffs = Materials.matte(Palette.moss, roughness: 1)
            case .barkTreads:
                boots = Materials.matte(Palette.bark, roughness: 1)
                cuffs = Materials.matte(Palette.darkBark, roughness: 1)
            case .grassMitts:
                addGloves(Materials.matte(Palette.leaf, roughness: 0.8), cuff: Materials.matte(Palette.darkMoss))
            case .chitinGauntlets:
                addGloves(Materials.glossy(Palette.beetleShell), cuff: Materials.matte(Palette.darkBark))
            default:
                guard let set = item.definition.set, let slot = item.definition.equipSlot else { break }
                let look = Self.look(of: set)
                let main = Materials.matte(look.main, roughness: 0.7)
                let trim = fullSet == set ? Materials.glow(look.trim) : Materials.matte(look.trim, roughness: 0.6)
                switch slot {
                case .hat:
                    cap = main
                    showSpots = false
                    let crest = Entity()
                    crest.addPart(Meshes.teardrop, trim, at: [0.12, 0.16, 0.12], scale: [0.045, 0.09, 0.014],
                                  rotation: simd_quatf(angle: .pi / 4, axis: [0, 1, 0]) * simd_quatf(angle: -0.5, axis: [1, 0, 0]))
                    attach(crest, to: hat)
                case .body:
                    outfit = main
                    let sash = Entity()
                    sash.addPart(Meshes.torus(radius: 0.162, tube: 0.02), trim, at: [0, 0.03, 0], scale: [1, 1, 0.72])
                    sash.addSphere(trim, at: [0, 0.03, 0.128], radius: 0.035)
                    attach(sash, to: torso)
                case .gloves:
                    addGloves(main, cuff: trim)
                case .boots:
                    boots = main
                    cuffs = trim
                case .weapon, .shield:
                    break
                }
            }
        }

        for part in outfitParts { part.model?.materials = [outfit] }
        for part in legParts { part.model?.materials = [leggings] }
        for part in shinParts { part.model?.materials = [shins] }
        let gloved = items.contains { $0.definition.equipSlot == .gloves }
        for band in bandParts { band.isEnabled = !gloved }
        for part in bootParts { part.model?.materials = [boots] }
        for part in cuffParts { part.model?.materials = [cuffs] }
        hatCap.model?.materials = [cap]
        hatSpots.isEnabled = showSpots
        hat.isEnabled = wearsHat
        let scarf = Materials.matte(playerClass.map { UIColor($0.tint) } ?? look.scarfColor)
        for part in scarfParts { part.model?.materials = [scarf] }

        switch playerClass {
        case .guardian where shield == nil:
            // A spare shield on the back, until a real one is in hand.
            let shield = Entity()
            shield.addCylinder(Materials.glossy(Palette.bark), at: [0, 0.24, -0.17], radius: 0.19, height: 0.04,
                               rotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))
            shield.addPart(Meshes.torus(radius: 0.19, tube: 0.02), Materials.glossy(SproutLook.gold), at: [0, 0.24, -0.17], scale: .one,
                           rotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))
            shield.addSphere(Materials.glossy(Palette.shelfFungus), at: [0, 0.24, -0.195], radius: 0.055)
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
            halo.position = [0, 0.98, 0]
            let dew = Materials.glow(UIColor(red: 0.55, green: 0.9, blue: 1, alpha: 1))
            for i in 0..<8 {
                let a = Float(i) / 8 * 2 * .pi
                halo.addSphere(dew, at: [sin(a) * 0.27, 0, cos(a) * 0.27], radius: 0.04)
            }
            attach(halo, to: head)
            self.halo = halo
        case .guardian, nil:
            break
        }
    }

    // MARK: - Armor silhouettes

    /// How a body armor reshapes the outfit, so tiers and sets read at a glance (as in Flyff).
    enum BodyStyle {
        /// Plain travelling clothes.
        case tunic
        /// Shoulder pads, a chest plate, and plates over the hips.
        case mail
        /// A long skirt to below the knee.
        case robe
        /// A high collar and long tails behind.
        case coat
    }

    static func bodyStyle(_ item: ItemID) -> BodyStyle? {
        switch item {
        case .leafTunic, .dewleafVest: .tunic
        case .barkMail, .turtleshellMail, .mantisCarapace, .heartwoodPlate: .mail
        case .myceliumRobe, .rainpetalGown: .robe
        case .featherCloak, .thistledownCoat, .briarJerkin: .coat
        default: nil
        }
    }

    static func bodyColor(_ item: ItemID) -> UIColor {
        switch item {
        case .leafTunic: UIColor(red: 0.38, green: 0.62, blue: 0.24, alpha: 1)
        case .barkMail: Palette.bark
        case .featherCloak: UIColor(red: 0.78, green: 0.68, blue: 0.52, alpha: 1)
        case .turtleshellMail: Palette.turtleSkin
        case .mantisCarapace: Palette.mantisWhite
        default: item.definition.set.map { look(of: $0).main } ?? SproutLook.tunic
        }
    }

    static func bodyTrim(_ item: ItemID) -> UIColor {
        switch item {
        case .leafTunic: Palette.leaf
        case .barkMail: Palette.darkBark
        case .featherCloak: Palette.owlFeather
        case .turtleshellMail: Palette.turtleShell
        case .mantisCarapace: Palette.mantisPink
        default: item.definition.set.map { look(of: $0).trim } ?? SproutLook.trim
        }
    }

    private func addBodyStyle(_ style: BodyStyle, color: UIColor, trim: UIColor) {
        let main = Materials.matte(color, roughness: 0.7)
        let edge = Materials.matte(trim, roughness: 0.6)
        switch style {
        case .tunic:
            // A short tabard over the belt.
            let tabard = Entity()
            tabard.addPart(Meshes.roundedBox, main, at: [0, 0.02, 0.112], scale: [0.16, 0.2, 0.03])
            tabard.addPart(Meshes.roundedBox, edge, at: [0, -0.08, 0.122], scale: [0.17, 0.025, 0.035])
            attach(tabard, to: torso)
        case .mail:
            for arm in arms {
                let pad = Entity()
                pad.addSphere(main, at: [0, 0.02, 0], radius: 0.095, squash: [1.15, 0.75, 1.1])
                pad.addPart(Meshes.torus(radius: 0.085, tube: 0.014), edge, at: [0, -0.01, 0], scale: .one)
                attach(pad, to: arm)
            }
            let plate = Entity()
            plate.addPart(Meshes.roundedBox, main, at: [0, 0.3, 0.1], scale: [0.24, 0.2, 0.06])
            plate.addPart(Meshes.roundedBox, edge, at: [0, 0.3, 0.13], scale: [0.04, 0.16, 0.02])
            attach(plate, to: torso)
            let tassets = Entity()
            for side in Self.sides {
                tassets.addPart(Meshes.roundedBox, main, at: [side * 0.1, -0.1, 0.08], scale: [0.11, 0.14, 0.03],
                                rotation: simd_quatf(angle: side * 0.25, axis: [0, 1, 0]) * simd_quatf(angle: -0.15, axis: [1, 0, 0]))
            }
            attach(tassets, to: hips)
        case .robe:
            let skirt = Entity()
            skirt.addPart(Self.robeMesh, main, at: [0, -0.02, 0], scale: .one)
            skirt.addPart(Meshes.torus(radius: 0.255, tube: 0.018), edge, at: [0, -0.52, 0], scale: .one)
            attach(skirt, to: hips)
        case .coat:
            let coat = Entity()
            coat.addPart(Meshes.torus(radius: 0.1, tube: 0.035), edge, at: [0, 0.46, -0.01], scale: [1, 1.4, 1])
            for side in Self.sides {
                coat.addPart(Meshes.roundedBox, main, at: [side * 0.07, -0.18, -0.12], scale: [0.12, 0.42, 0.03],
                             rotation: simd_quatf(angle: 0.18, axis: [1, 0, 0]) * simd_quatf(angle: side * 0.12, axis: [0, 0, 1]))
            }
            attach(coat, to: torso)
        }
    }

    /// Mittens over both fists, with a cuff at the wrist.
    private func addGloves(_ material: any RealityKit.Material, cuff: any RealityKit.Material) {
        for hand in hands {
            let glove = Entity()
            addFist(to: glove, material, grow: 1.18)
            glove.addPart(Meshes.torus(radius: 0.034, tube: 0.014), cuff, at: [0, 0.05 * Self.fistSize, 0],
                          scale: [Self.fistSize, Self.fistSize, Self.fistSize * 1.1])
            attach(glove, to: hand)
        }
    }

    /// Each set's cloth color and its trim.
    static func look(of set: ItemSet) -> (main: UIColor, trim: UIColor) {
        switch set {
        case .dewleaf: (UIColor(red: 0.42, green: 0.76, blue: 0.48, alpha: 1), UIColor(red: 0.72, green: 0.94, blue: 1, alpha: 1))
        case .heartwood: (UIColor(red: 0.5, green: 0.32, blue: 0.18, alpha: 1), SproutLook.gold)
        case .briar: (UIColor(red: 0.33, green: 0.48, blue: 0.2, alpha: 1), UIColor(red: 0.88, green: 0.32, blue: 0.3, alpha: 1))
        case .mycelium: (UIColor(red: 0.5, green: 0.38, blue: 0.66, alpha: 1), UIColor(red: 0.86, green: 0.76, blue: 1, alpha: 1))
        case .rainpetal: (UIColor(red: 0.55, green: 0.78, blue: 0.95, alpha: 1), UIColor(red: 1, green: 0.78, blue: 0.9, alpha: 1))
        case .thistledown: (UIColor(red: 0.9, green: 0.88, blue: 0.97, alpha: 1), UIColor(red: 0.72, green: 0.58, blue: 0.95, alpha: 1))
        }
    }

    private func attach(_ part: Entity, to parent: Entity) {
        parent.addChild(part)
        gear.append(part)
    }

    /// World position projectiles leave from: the nocked arrow, a wand's tip, a staff's droplet.
    var muzzlePosition: SIMD3<Float>? {
        held?.muzzle?.position(relativeTo: nil)
    }

    /// The held weapon and its family, for effects hung on it (element auras).
    var heldWeapon: (held: WeaponModels.Held, type: WeaponType)? {
        guard let held, let weapon else { return nil }
        return (held, weapon)
    }

    // MARK: - Animation

    /// How each weapon family attacks.
    private enum Attack {
        /// Swings along arcs in a repeating combo (melee weapons, and the wand's flicks).
        case slash(SwingStyle)
        /// Loose the arrow, then nock and draw the next.
        case shoot
        /// Point the staff at the foe, then twirl it.
        case staff
        /// Bare-handed ranged classes: point and release.
        case point

        var duration: Double {
            switch self {
            case let .slash(style): style.duration
            case .shoot: 0.8
            case .staff: 0.85
            case .point: 0.42
            }
        }
    }

    /// One weapon family's swings: the combo and its timing.
    private struct SwingStyle {
        let combo: [Swing]
        let duration: Double
        /// Swing phases as fractions of `duration`: wind up, strike until `strikeEnd`, recover.
        let strikeStart: Float
        let strikeEnd: Float
        /// How far back along the arc the weapon cocks before the strike.
        let windup: Float

        static let sword = SwingStyle(combo: [.left, .right, .up, .down], duration: 0.42, strikeStart: 0.22, strikeEnd: 0.52, windup: -0.12)
        /// Slower and heavier: a bigger wind up, then the whole body follows the head through.
        static let axe = SwingStyle(combo: [.cleave, .hack, .chop], duration: 0.5, strikeStart: 0.3, strikeEnd: 0.55, windup: -0.2)
        static let maul = SwingStyle(combo: [.sweep, .slam], duration: 0.66, strikeStart: 0.36, strikeEnd: 0.58, windup: -0.22)
        static let wand = SwingStyle(combo: [.flick, .flickBack], duration: 0.4, strikeStart: 0.2, strikeEnd: 0.45, windup: -0.15)
    }

    private var attack: Attack {
        switch weapon {
        case .sword: .slash(.sword)
        case .axe: .slash(.axe)
        case .maul: .slash(.maul)
        case .wand: .slash(.wand)
        case .bow: .shoot
        case .staff: .staff
        case nil: Progression.reach(weapon: nil, playerClass: playerClass) > 2 ? .point : .slash(.sword)
        }
    }

    /// The melee auto-attack combos: fixed patterns per weapon, like Flyff.
    enum Swing {
        case left, right, up, down // sword
        case cleave, hack, chop // axe
        case sweep, slam // maul, both hands
        case flick, flickBack // wand

        /// The weapon arm sweeps `sweep` radians from `from` toward `via` (torso space, from the
        /// right shoulder) while the torso turns from `twist.0` to `twist.1`.
        private var arc: (from: SIMD3<Float>, via: SIMD3<Float>, sweep: Float, twist: (Float, Float)) {
            switch self {
            case .left: ([-0.95, -0.15, -0.3], [0, -0.2, 1], 2.7, (-0.5, 0.45)) // right to left, across the chest
            case .right: ([0.75, 0.05, 0.65], [-0.3, 0, 1], 2.8, (0.45, -0.5)) // backhand, left to right
            case .up: ([-0.45, -0.8, -0.3], [-0.15, -0.1, 1], 2.9, (-0.2, 0.25)) // rising from the ground
            case .down: ([-0.55, 0.8, -0.25], [-0.15, 0.2, 1], 2.5, (0.2, -0.1)) // overhead chop
            case .cleave: ([-0.6, 0.75, -0.35], [0.15, -0.15, 1], 2.7, (-0.65, 0.55)) // high right, down to low left
            case .hack: ([0.8, 0.2, 0.45], [-0.25, -0.05, 1], 3, (0.6, -0.65)) // a flat, heavy backhand
            case .chop: ([-0.3, 0.9, -0.4], [-0.1, 0.35, 1], 2.7, (0.25, -0.15)) // from behind the head, straight down
            case .sweep: ([-0.85, -0.25, -0.5], [0.05, -0.4, 1], 3, (-0.8, 0.65)) // low and wide, hips first
            case .slam: ([-0.15, 0.85, -0.55], [-0.05, 0.15, 1], 3, (0.15, -0.1)) // up and over, into the ground
            case .flick: ([-0.45, 0.85, -0.15], [0.1, 0.15, 1], 1.8, (-0.25, 0.25)) // over the shoulder at the foe
            case .flickBack: ([0.4, 0.85, 0.1], [-0.3, 0.1, 1], 1.7, (0.3, -0.2)) // and back across
            }
        }

        /// How the body follows the arm: torso lean (forward is positive) and lift while cocking
        /// back and at the strike, how far the front foot steps in, and how much the feet widen.
        var body: (coilLean: Float, strikeLean: Float, coilLift: Float, strikeLift: Float, step: Float, spread: Float) {
            switch self {
            case .left: (-0.08, 0.26, 0, 0, 0.38, 0.06)
            case .right: (-0.06, 0.2, 0, 0, 0.3, 0.1)
            case .up: (0.28, -0.14, 0, 0.07, 0.18, 0.12) // scoop low, then rise onto the toes
            case .down: (-0.22, 0.4, 0.03, 0, 0.5, 0.1) // rear back, then drive down into a lunge
            case .cleave: (-0.15, 0.36, 0.02, 0, 0.45, 0.1)
            case .hack: (-0.05, 0.24, 0, 0, 0.32, 0.14)
            case .chop: (-0.3, 0.5, 0.05, 0, 0.55, 0.12) // rear up, then bury it
            case .sweep: (-0.08, 0.3, 0, 0, 0.35, 0.16)
            case .slam: (-0.35, 0.6, 0.1, 0, 0.55, 0.16) // up on the toes, then down with the whole body
            case .flick, .flickBack: (-0.06, 0.14, 0.02, 0, 0.16, 0.04)
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

    /// How far back in swing progress the trail reaches.
    private static let trailSpan: Float = 0.2
    /// The wrist cocks the blade out along the arm while swinging.
    private static let wristBend = simd_quatf(angle: 1.35, axis: [1, 0, 0])
    /// Where the fist is in arm space with the elbow straight.
    private static let hand = elbow + forearmHand
    private static let identity = simd_quatf(angle: 0, axis: [1, 0, 0])
    private static let rightShoulder = shoulder * [-1, 1, 1]
    private static let leftShoulder = shoulder

    func playSwing(at time: Double) {
        lastCombat = time
        if case let .slash(style) = attack {
            // Start the pattern over after a pause in the fight.
            if time - lastSwing > 2.5 { comboIndex = 0 }
            swing = style.combo[comboIndex % style.combo.count]
            comboIndex += 1
            lastSwing = time
        }
        swingStart = time
    }
    func playHurt(at time: Double) {
        hurtStart = time
        lastCombat = time
    }
    /// Shield up: the hit glances off.
    func playBlock(at time: Double) {
        blockStart = time
        lastCombat = time
    }
    func playCast(at time: Double) { castStart = time }
    func playCheer(at time: Double) { cheerStart = time }

    struct Motion {
        var moving = false
        var airborne = false
        var fainted = false
        /// Fighting something (the sim's `EntitySnapshot.target`).
        var engaged = false
        /// Resting on the ground (Flyff's sit).
        var sitting = false
        /// An idle gesture (townsfolk waving, stretching, looking about).
        var gesture: IdleFlourish.Playing?
    }

    /// The battle-ready pose, weapon arm at index 1: feet staggered with the left foot forward,
    /// hips turned side-on, torso leaning in, and the blade raised in front (or the aim arm out).
    private struct Stance {
        var legSwing: [Float]
        var legSpread: Float
        var hipYaw: Float
        var twist: Float
        var lean: Float
        var armSwing: [Float]
        var armSpread: [Float]
        var wrist: Float
        /// Knees bend into a crouch, elbows bend the forearms up.
        var knee: [Float]
        var elbow: [Float]
    }

    private static let meleeStance = Stance(legSwing: [-0.55, 0.18], legSpread: 0.2, hipYaw: -0.38, twist: 0.1, lean: 0.18,
                                            armSwing: [-0.6, -0.9], armSpread: [0.55, 0.3], wrist: 0.3,
                                            knee: [0.55, 0.4], elbow: [0.7, 0.35])
    /// Wide and low under a heavy two-hander.
    private static let maulStance = Stance(legSwing: [-0.6, 0.22], legSpread: 0.24, hipYaw: -0.5, twist: 0.2, lean: 0.16,
                                            armSwing: [-0.8, -0.6], armSpread: [0.3, 0.3], wrist: 0,
                                            knee: [0.6, 0.45], elbow: [0, 0])
    private static let rangedStance = Stance(legSwing: [-0.38, 0.1], legSpread: 0.19, hipYaw: -0.45, twist: 0.12, lean: 0.08,
                                             armSwing: [-1.1, -0.35], armSpread: [0.2, 0.5], wrist: 0,
                                             knee: [0.4, 0.3], elbow: [0, 0.5])
    /// How long the stance lingers after the last swing or hit.
    private static let stanceLinger = 4.0

    /// Ready poses for the weapon arm, for weapons not held up like a sword.
    private static let holds: [WeaponType: simd_quatf] = [
        // Diagonally across the chest, head up by the off shoulder.
        .maul: aim([-0.25, -0.75, 0.6], toward: [0.6, 0.75, 0.2], axis: WeaponModels.bladeDirection),
        // Low in front, tip up, ready to flick.
        .wand: aim([-0.3, -0.55, 0.8], toward: [0.1, 0.8, 0.55], axis: WeaponModels.bladeDirection),
    ]

    /// A heavy weapon's head hangs forward and down while walking around.
    private static func restWrist(_ weapon: WeaponType?) -> simd_quatf {
        weapon == .maul ? simd_quatf(angle: 1.1, axis: [1, 0, 0]) : identity
    }

    // Bow and staff frames (torso space), which the hand holds whatever the arm is doing.
    /// Hanging at the side, top tipped forward.
    private static let bowRest = simd_quatf(angle: 0.5, axis: [1, 0, 0])
    /// The string hand flung back after the release.
    private static let bowFlick = simd_quatf(from: [0, -1, 0], to: simd_normalize([-0.8, 0.35, -0.5]))
    /// Like a walking stick, leaning a little forward and out.
    private static let staffRest = simd_quatf(angle: 0.12, axis: [0, 0, 1]) * simd_quatf(angle: 0.15, axis: [1, 0, 0])
    private static let staffReady = simd_quatf(angle: 0.05, axis: [0, 0, 1]) * simd_quatf(angle: 0.25, axis: [1, 0, 0])
    private static let staffThrust = simd_quatf(from: [0, 1, 0], to: simd_normalize([0.05, 0.45, 1]))
    private static let staffThrustArm = simd_quatf(from: [0, -1, 0], to: simd_normalize([-0.15, 0.1, 1]))
    /// The staff windmills around the fist, which is held out low in front.
    private static let twirlAxis = simd_normalize(SIMD3<Float>(-0.2, -0.2, 1))
    private static let staffTwirlArm = simd_quatf(from: [0, -1, 0], to: twirlAxis)
    // Shield facings: out to the side, angled toward the foe, square in front of the face.
    private static let shieldRest = simd_quatf(angle: 1.35, axis: [0, 1, 0])
    private static let shieldReady = simd_quatf(angle: 0.45, axis: [0, 1, 0])
    private static let shieldBlock = simd_quatf(angle: 0.1, axis: [0, 1, 0])
    private static let blockArm = simd_quatf(from: [0, -1, 0], to: simd_normalize([0.2, 0.3, 1]))

    func animate(_ motion: Motion, time: Double, seed: Float) {
        let t = Float(time)
        let dt = Float(min(max(time - (lastFrame ?? time), 0), 0.1))
        lastFrame = time
        let attack = attack
        let ranged = Progression.reach(weapon: weapon, playerClass: playerClass) > 2
        let attackProgress = Self.progress(&swingStart, time, duration: attack.duration)
        let hurt = Self.progress(&hurtStart, time, duration: 0.45)
        let blocking = Self.progress(&blockStart, time, duration: 0.5)
        let cast = Self.progress(&castStart, time, duration: 0.7)
        let cheer = Self.progress(&cheerStart, time, duration: 1.4)

        // Square up while fighting, and relax a few seconds after the last exchange.
        let fighting = motion.engaged || time - lastCombat < Self.stanceLinger
        let ready = fighting && !motion.moving && !motion.airborne && !motion.fainted && !motion.sitting && cheer == nil
        // Ease down onto the ground and back up.
        sit += ((motion.sitting && !motion.fainted ? 1 : 0) - sit) * min(1, dt * 7)
        let seated = Self.ease(sit)
        stance += ((ready ? 1 : 0) - stance) * min(1, dt * 6)
        let k = Self.ease(stance)

        var armSwing: [Float] = [0, 0] // about X; negative swings forward and up
        var armSpread: [Float] = [0.46, 0.46]
        var legSwing: [Float] = [0, 0] // about X; positive swings back
        var legSpread: [Float] = [0.13, 0.13] // about Z; positive moves the foot outward
        var knee: [Float] = [0, 0] // positive folds the shin back
        var legTurn: Float = 0.22 // toes and knees turned out, a little bow-legged
        var elbow: [Float] = [0.45, 0.45] // positive folds the forearm forward and up
        var armRoll: [Float] = [0.55, 0.55] // turns the elbow's bend outward, fists out from the hips
        /// 0...1 per arm: how much a pose needs the arm straight (aiming, gripping, striking).
        var straighten: [Float] = [0, 0]
        var hipYaw: Float = 0
        var twist: Float = 0
        var lean: Float = 0 // torso pitch; positive leans forward
        var wrist: Float = 0
        var nod: Float = 0
        var tilt: Float = 0
        var lift: Float = 0
        var breath: Float = 0
        var sproutSway = sin(t * 2.2 + seed) * 0.12
        var scarfLift = 0.15 + sin(t * 1.7 + seed) * 0.05

        if motion.fainted {
            armSpread = [0.55, 0.55]
            armSwing = [-0.2, -0.3]
            elbow = [0.2, 0.2]
            knee = [0.3, 0.1]
            tilt = 0.3
        } else if motion.airborne {
            // Legs dangle and kick; they trail behind when gliding forward.
            let trail: Float = motion.moving ? 0.5 : 0.15
            legSwing = [trail + sin(t * 2.1) * 0.35, trail + sin(t * 2.1 + 2) * 0.35]
            knee = [0.5 + sin(t * 2.1 + 1) * 0.35, 0.5 + sin(t * 2.1 + 3) * 0.35]
            armSpread[0] = 1.1 + sin(t * 2.4) * 0.15
            armSwing[0] = -0.3
            elbow[0] = 0.35
            scarfLift = motion.moving ? 1.1 + sin(t * 14) * 0.12 : 0.5 + sin(t * 3) * 0.1
            sproutSway = sin(t * 5) * 0.25
        } else if motion.moving {
            // A bouncy, skipping run (the renderer bobs the whole body in step).
            let stride = sin(t * 12)
            let pace = cos(t * 12)
            legSwing = [stride * 0.7, -stride * 0.7]
            legSpread = [0.03, 0.03]
            legTurn = 0.08
            // The knee folds high as the leg swings through, anime style.
            knee = [0.2 + max(0, -pace) * 1.2, 0.2 + max(0, pace) * 1.2]
            armSwing = [-stride * 0.6, stride * 0.6]
            // Forearms pump, bent up at the elbow.
            elbow = [1.0 + stride * 0.25, 1.0 - stride * 0.25]
            armRoll = [0.3, 0.3]
            twist = stride * 0.1
            nod = 0.06
            scarfLift = 0.75 + sin(t * 16) * 0.12
            sproutSway = stride * 0.3
        } else {
            // Standing easy but springy: feet apart, knees soft, elbows out, weight
            // rocking slowly from foot to foot.
            breath = sin(t * 2.1 + seed)
            let shift = sin(t * 0.9 + seed)
            armSwing = [breath * 0.04 - 0.08, -breath * 0.04 - 0.08]
            elbow = [0.5 + breath * 0.05, 0.5 - breath * 0.05]
            knee = [0.16 + shift * 0.07, 0.16 - shift * 0.07]
            legSwing = [-knee[0] * 0.5, -knee[1] * 0.5]
            hipYaw = shift * 0.04
            tilt = sin(t * 0.8 + seed) * 0.07
            nod = breath * 0.02
        }
        if seated > 0.001 {
            // Sitting on the ground, legs out in front, hands resting on the knees, swaying a little.
            let sway = sin(t * 1.1 + seed)
            for i in 0..<2 {
                legSwing[i] += (-1.5 + Float(i) * 0.08 - legSwing[i]) * seated
                legSpread[i] += (0.24 - legSpread[i]) * seated
                knee[i] += (0.45 - knee[i]) * seated
                armSwing[i] += (-0.7 - armSwing[i]) * seated
                armSpread[i] += (0.28 - armSpread[i]) * seated
                elbow[i] += (0.35 - elbow[i]) * seated
                armRoll[i] += (0.2 - armRoll[i]) * seated
            }
            lean += (0.08 + sway * 0.03) * seated
            tilt += sway * 0.05 * seated
            nod += 0.06 * seated
        }
        let strideTwist = twist

        if stance > 0.001 {
            // Bouncing lightly on the balls of the feet, Flyff style.
            let pose = weapon == .maul ? Self.maulStance : (ranged ? Self.rangedStance : Self.meleeStance)
            let bounce = sin(t * 5.5 + seed)
            func blend(_ value: inout Float, _ target: Float) { value += (target - value) * k }
            for i in 0..<2 {
                blend(&legSwing[i], pose.legSwing[i])
                blend(&legSpread[i], pose.legSpread)
                blend(&armSwing[i], pose.armSwing[i] + bounce * 0.08)
                blend(&armSpread[i], pose.armSpread[i])
                blend(&knee[i], pose.knee[i] + bounce * 0.05)
                blend(&elbow[i], pose.elbow[i])
                blend(&armRoll[i], 0)
            }
            blend(&legTurn, 0.3)
            blend(&hipYaw, pose.hipYaw)
            blend(&twist, pose.twist)
            blend(&lean, pose.lean + bounce * 0.04)
            blend(&wrist, pose.wrist)
            blend(&tilt, 0)
            blend(&lift, bounce * 0.006)
            blend(&scarfLift, 0.3 + bounce * 0.05)
        }

        var slash: (arm: simd_quatf, amount: Float)?
        var slashProgress: Float?
        var shot: Float?
        var flourish: Float?
        let base = (twist: twist, lean: lean)
        if let p = attackProgress, !motion.fainted {
            switch attack {
            case .point:
                // Point and release, turning the shooting shoulder forward.
                let thrust = sin(p * .pi)
                armSwing[1] += (-1.5 - armSwing[1]) * thrust
                armSpread[1] += (0.1 - armSpread[1]) * thrust
                straighten[1] = max(straighten[1], thrust)
                armSwing[0] += (-0.4 - armSwing[0]) * thrust
                twist += 0.25 * thrust
                hipYaw += 0.15 * thrust
                lean += 0.1 * thrust
            case let .slash(style):
                // Cock back, whip through the arc, then ease back to the base pose. The hips
                // turn and the front foot steps in with the blade.
                let phase = Self.slashPhase(p, style)
                slash = (Self.armPose(swing, phase.s), phase.amount)
                slashProgress = p
                let body = Self.slashBody(swing, style, p)
                hipYaw += body.hipYaw
                twist += body.twist
                lean += body.lean
                lift += body.lift
                legSwing[0] -= body.step
                legSwing[1] += body.step * 0.7
                knee[0] += body.step * 0.5
                for i in 0..<2 { legSpread[i] += body.spread }
                if weapon != .maul {
                    // The free arm flings back and out for balance.
                    armSwing[0] += (0.5 - armSwing[0]) * body.impact * 0.6
                    armSpread[0] += 0.35 * body.impact
                }
                scarfLift += body.impact * 0.5
                sproutSway += sin(p * .pi) * 0.4
            case .shoot:
                // The shoulders open and the body rocks back as the string lets go.
                shot = p
                let recoil = sin(min(p / 0.3, 1) * .pi)
                twist += 0.12 * recoil
                hipYaw += 0.05 * recoil
                lean -= 0.06 * recoil
                scarfLift += 0.2 * recoil
            case .staff:
                // Lunge in behind the thrust, then stand tall for the twirl.
                flourish = p
                let phase = Self.staffPhases(p)
                lean += 0.16 * phase.thrust - 0.04 * phase.twirl
                twist += 0.2 * phase.thrust
                legSwing[0] -= 0.32 * phase.thrust
                legSwing[1] += 0.22 * phase.thrust
                knee[0] += 0.2 * phase.thrust
                lift += 0.02 * phase.twirl * abs(sin(phase.spin))
                sproutSway += sin(p * 2 * .pi) * 0.3
            }
        }
        if let p = hurt, !motion.fainted {
            nod -= 0.2 * sin(p * .pi)
            lean -= 0.12 * sin(p * .pi)
        }
        var blockAmount: Float = 0
        if let p = blocking, !motion.fainted, !motion.airborne {
            // Brace behind the shield and rock back from the impact.
            blockAmount = Self.ease(min(1, p / 0.12) * min(1, (1 - p) / 0.4))
            lean -= 0.12 * blockAmount
            legSwing[0] -= 0.12 * blockAmount
            legSwing[1] += 0.12 * blockAmount
        }
        // Keep the eyes on the foe while the body turns and leans under them.
        let look = -(hipYaw + twist - strideTwist) * 0.6
        nod -= lean * 0.6

        let castAmount = cast.map { Self.ease(min(1, $0 / 0.2) * min(1, (1 - $0) / 0.3)) } ?? 0
        let cheerAmount = cheer.map { Self.ease(min(1, $0 / 0.15) * min(1, (1 - $0) / 0.2)) } ?? 0
        let raise = motion.fainted || motion.airborne ? 0 : max(castAmount, cheerAmount) // arms up for a cast or cheer
        let torsoArch = motion.fainted || motion.airborne ? 0 : 0.1 * castAmount
        let hipsRotation = simd_quatf(angle: hipYaw, axis: [0, 1, 0])
        let torsoRotation = Self.torsoRotation(twist, lean - torsoArch)

        var armPose = (0..<2).map { i in
            simd_quatf(angle: Self.sides[i] * armSpread[i], axis: [0, 0, 1]) * simd_quatf(angle: armSwing[i], axis: [1, 0, 0])
                * simd_quatf(angle: Self.sides[i] * armRoll[i], axis: [0, 1, 0])
        }
        if let hold = weapon.flatMap({ Self.holds[$0] }) {
            armPose[1] = simd_slerp(armPose[1], hold, k)
        }
        if let slash {
            armPose[1] = simd_slerp(armPose[1], slash.arm, slash.amount)
            straighten[1] = max(straighten[1], slash.amount)
        }

        // Bow: the left arm aims, the right hand draws the string back to the cheek.
        var bowFrame = Self.bowRest
        var nockAmount: Float = 0
        var arrowShown = false
        if weapon == .bow, !motion.fainted, !motion.airborne {
            let aimAmount = max(k, shot == nil ? 0 : 1)
            let forward = (hipsRotation * torsoRotation).inverse.act(simd_normalize([0, 0.06, 1]))
            armPose[0] = simd_slerp(armPose[0], simd_quatf(from: [0, -1, 0], to: forward), aimAmount)
            let up = simd_normalize(SIMD3<Float>(0, 1, 0) - forward.y * forward)
            let aimed = simd_quatf(simd_float3x3(simd_cross(up, forward), up, forward)) * simd_quatf(angle: -0.15, axis: [0, 0, 1])
            bowFrame = simd_slerp(Self.bowRest, aimed, aimAmount)
            let phase = shot.map(Self.bowPhases) ?? (draw: 0.92 + sin(t * 2) * 0.04, flick: 0, holding: 1, nocked: true)
            let grip = Self.leftShoulder + armPose[0].act(Self.hand)
            let target = grip + bowFrame.act(WeaponModels.stringRest + [0, 0, -0.34 * phase.draw])
            let pull = simd_slerp(simd_quatf(from: [0, -1, 0], to: simd_normalize(target - Self.rightShoulder)), Self.bowFlick, phase.flick)
            armPose[1] = simd_slerp(armPose[1], pull, aimAmount)
            nockAmount = aimAmount * phase.holding
            arrowShown = aimAmount > 0.4 && phase.nocked
            for i in 0..<2 { straighten[i] = max(straighten[i], aimAmount) }
        }

        // Staff: held upright, thrust at the foe, then twirled.
        var staffFrame = simd_slerp(Self.staffRest, Self.staffReady, k)
        if weapon == .staff, let p = flourish {
            let phase = Self.staffPhases(p)
            armPose[1] = simd_slerp(armPose[1], Self.staffThrustArm, phase.thrust)
            staffFrame = simd_slerp(staffFrame, Self.staffThrust, phase.thrust)
            armPose[1] = simd_slerp(armPose[1], Self.staffTwirlArm, phase.twirl)
            staffFrame = simd_slerp(staffFrame, simd_quatf(angle: phase.spin, axis: Self.twirlAxis), phase.twirl)
            straighten[1] = max(straighten[1], phase.thrust, phase.twirl)
        }

        // Shield: raised in front of the face to catch a blow.
        if shield != nil {
            armPose[0] = simd_slerp(armPose[0], Self.blockArm, blockAmount)
            elbow[0] += (0.5 - elbow[0]) * blockAmount
        }

        let slashWrist = motion.airborne || cast != nil || cheer != nil ? 0 : slash?.amount ?? 0
        let wristAmount = motion.airborne ? 0 : (wrist + (1 - wrist) * slashWrist) * (1 - raise)
        let heldWrist = simd_slerp(Self.restWrist(weapon), Self.identity, max(k, slashWrist))
        let weaponWrist = simd_slerp(heldWrist, Self.wristBend, wristAmount)

        if weapon == .maul, !motion.fainted, !motion.airborne {
            // Two hands on the haft.
            let grip = Self.rightShoulder + armPose[1].act(Self.hand + weaponWrist.act(WeaponModels.offhandGrip))
            let reach = simd_quatf(from: [0, -1, 0], to: simd_normalize(grip - Self.leftShoulder))
            armPose[0] = simd_slerp(armPose[0], reach, max(k, slash?.amount ?? 0))
            for i in 0..<2 { straighten[i] = max(straighten[i], k, slash?.amount ?? 0) }
        }

        if motion.airborne, !motion.fainted {
            // Hanging on to the dandelion stalk.
            let shoulder = SIMD3<Float>(-Self.shoulder.x, Self.hipHeight + Self.shoulder.y, 0)
            armPose[1] = simd_quatf(from: [0, -1, 0], to: simd_normalize(Self.gliderGrip - shoulder))
            straighten[1] = 1
        } else if cast != nil, !motion.fainted {
            // Both arms up in a V to call the magic down.
            for i in 0..<2 {
                let raised = simd_quatf(from: [0, -1, 0], to: simd_normalize([Self.sides[i] * 0.6, 0.75, 0.3]))
                armPose[i] = simd_slerp(armPose[i], raised, castAmount)
                elbow[i] += (0.25 - elbow[i]) * castAmount
            }
            nod -= 0.15 * castAmount
        }
        if let p = cheer, !motion.fainted, !motion.airborne {
            // Two happy hops with waving arms.
            lift += abs(sin(p * 2 * .pi)) * 0.16
            for i in 0..<2 {
                let wave = simd_quatf(angle: Self.sides[i] * sin(t * 18) * 0.3, axis: [0, 0, 1])
                let raised = wave * simd_quatf(from: [0, -1, 0], to: simd_normalize([Self.sides[i] * 0.45, 0.85, 0.1]))
                armPose[i] = simd_slerp(armPose[i], raised, cheerAmount)
                elbow[i] += (0.7 - elbow[i]) * cheerAmount
            }
            nod -= 0.12 * cheerAmount
        }
        // Idle gestures, only while standing about with nothing else going on.
        var glance: Float = 0
        var gestureFace: FacePainter.Expression?
        if let playing = motion.gesture, !motion.moving, !motion.airborne, !motion.fainted, !fighting,
           attackProgress == nil, hurt == nil, cast == nil, cheer == nil, seated < 0.999 {
            let p = playing.progress
            let amount = Self.ease(min(1, p / 0.2) * min(1, (1 - p) / 0.25)) * (1 - seated)
            switch playing.gesture {
            case .wave:
                // A friendly wave with the right hand, head tipped.
                let wave = simd_quatf(angle: sin(t * 9) * 0.35, axis: [0, 0, 1])
                armPose[1] = simd_slerp(armPose[1], wave * simd_quatf(from: [0, -1, 0], to: simd_normalize([-0.6, 0.6, 0.2])), amount)
                elbow[1] += (0.8 - elbow[1]) * amount
                tilt += 0.12 * amount
                if amount > 0.3 { gestureFace = .happy }
            case .stretch:
                // Both arms up, up on the toes, face to the sky with the eyes shut.
                for i in 0..<2 {
                    let raised = simd_quatf(from: [0, -1, 0], to: simd_normalize([Self.sides[i] * 0.3, 1, -0.1]))
                    armPose[i] = simd_slerp(armPose[i], raised, amount)
                    elbow[i] += (0.1 - elbow[i]) * amount
                }
                lift += 0.03 * amount
                nod -= 0.3 * amount
                if amount > 0.5 { gestureFace = .blink }
            case .lookAround:
                // A glance one way, then the other.
                glance = 0.75 * amount * (IdleFlourish.plateau(p, 0.05, 0.2, 0.4, 0.5) - IdleFlourish.plateau(p, 0.5, 0.62, 0.82, 0.95))
                tilt += glance * 0.1
            case .scratchHead:
                // Scratching beside the ear, head tipped toward the hand.
                let scratch = simd_quatf(angle: sin(t * 22) * 0.08, axis: [1, 0, 0])
                armPose[1] = simd_slerp(armPose[1], scratch * simd_quatf(from: [0, -1, 0], to: simd_normalize([-0.5, 0.75, 0.3])), amount)
                elbow[1] += (1.7 - elbow[1]) * amount
                tilt += 0.18 * amount
            }
        }

        var drop: Float = Self.hipHeight * 0.86 * seated
        if !motion.airborne, !motion.fainted, seated < 0.001 {
            // Sink so the planted foot stays on the ground as the legs spread, stagger, and bend
            // (the renderer bobs a running body in step, so running only sinks for the knees).
            let reach = (0..<2).map { i in
                Self.footDepth(swing: motion.moving ? 0 : legSwing[i], spread: legSpread[i], turn: legTurn, knee: knee[i])
            }.max() ?? Self.hipHeight
            drop = Self.hipHeight - reach
        }
        body.position.y = lift - drop
        hips.orientation = hipsRotation
        torso.orientation = torsoRotation
        torso.scale = [1 + breath * 0.008, 1 + breath * 0.012, 1 + breath * 0.008]
        head.orientation = simd_quatf(angle: look + glance, axis: [0, 1, 0]) * simd_quatf(angle: nod, axis: [1, 0, 0])
            * simd_quatf(angle: tilt, axis: [0, 0, 1])
        for i in 0..<2 {
            arms[i].orientation = armPose[i]
            elbows[i].orientation = simd_quatf(angle: -max(0, elbow[i]) * (1 - straighten[i]), axis: [1, 0, 0])
            legs[i].orientation = simd_quatf(angle: Self.sides[i] * legSpread[i], axis: [0, 0, 1])
                * simd_quatf(angle: legSwing[i], axis: [1, 0, 0]) * simd_quatf(angle: Self.sides[i] * legTurn, axis: [0, 1, 0])
            knees[i].orientation = simd_quatf(angle: max(0, knee[i]), axis: [1, 0, 0])
        }
        // Frames the hands hold in torso space, whatever the elbow does.
        let forearms = (0..<2).map { armPose[$0] * elbows[$0].orientation }
        for (i, tail) in scarfTails.enumerated() {
            tail.orientation = simd_quatf(angle: Self.sides[i] * 0.18, axis: [0, 0, 1])
                * simd_quatf(angle: scarfLift + Float(i) * 0.08 + sin(t * 9 + Float(i)) * 0.04, axis: [1, 0, 0])
        }
        // Bows, staves, and shields keep their own facing whatever the arm does.
        hands[1].orientation = weapon == .staff ? forearms[1].inverse * staffFrame : weaponWrist
        if weapon == .bow {
            hands[0].orientation = forearms[0].inverse * bowFrame
            updateBowString(nock: nockAmount, arrow: arrowShown)
        } else if shield != nil {
            let facing = simd_slerp(simd_slerp(Self.shieldRest, Self.shieldReady, k), Self.shieldBlock, blockAmount)
            hands[0].orientation = forearms[0].inverse * facing
        }
        if let p = slashProgress, slashWrist > 0, case let .slash(style) = attack {
            updateTrail(p, style, baseTwist: base.twist, baseLean: base.lean)
        } else {
            trail.hide()
        }
        sprout.orientation = simd_quatf(angle: sproutSway, axis: [0, 0, 1])
        orb?.position = [0.45 + cos(t * 0.9) * 0.05, 1.55 + sin(t * 2) * 0.06, -0.05 + sin(t * 0.9) * 0.05]
        halo?.orientation = simd_quatf(angle: t * 0.8, axis: [0, 1, 0])

        // Blink every few seconds, at a different moment for each player.
        let blinking = (t + seed * 0.37).truncatingRemainder(dividingBy: 3.8) < 0.13
        let wanted: FacePainter.Expression = if motion.fainted {
            .fainted
        } else if hurt != nil {
            .hurt
        } else if cheer != nil {
            .happy
        } else if let gestureFace {
            gestureFace
        } else {
            blinking ? .blink : .open
        }
        if wanted != expression {
            expression = wanted
            face.model?.materials = [FacePainter.material(wanted, self.look.face)]
        }
    }

    /// Where a melee swing is: `s` runs along the arc (a little negative while cocking back),
    /// `amount` blends from the base pose into the swing and back out.
    private static func slashPhase(_ p: Float, _ style: SwingStyle) -> (s: Float, amount: Float) {
        if p < style.strikeStart {
            let x = ease(p / style.strikeStart)
            return (style.windup * x, x)
        } else if p < style.strikeEnd {
            let x = (p - style.strikeStart) / (style.strikeEnd - style.strikeStart)
            return (style.windup + (1 - style.windup) * (1 - pow(1 - x, 3)), 1)
        } else {
            return (1, 1 - ease((p - style.strikeEnd) / (1 - style.strikeEnd)))
        }
    }

    /// Whole-body motion for one moment of a melee swing, added on top of the base pose.
    private struct SlashBody {
        var hipYaw: Float
        var twist: Float
        var lean: Float
        var lift: Float
        /// Radians the front leg steps forward (the back leg pushes back a bit less).
        var step: Float
        var spread: Float
        /// 0...1, peaking mid-strike.
        var impact: Float
    }

    private static func slashBody(_ swing: Swing, _ style: SwingStyle, _ p: Float) -> SlashBody {
        let phase = slashPhase(p, style)
        let s = min(max(phase.s, 0), 1)
        let coil = phase.amount * (1 - ease(s / 0.5))
        let follow = phase.amount * ease(s)
        let impact = phase.amount * sin(s * .pi)
        // The hips lead the turn and the shoulders finish it.
        let turn = swing.twist(phase.s) * phase.amount
        let body = swing.body
        return SlashBody(hipYaw: turn * 0.4, twist: turn * 0.6,
                         lean: body.coilLean * coil + body.strikeLean * follow,
                         lift: body.coilLift * coil + body.strikeLift * impact,
                         step: body.step * follow, spread: body.spread * min(1, coil + follow), impact: impact)
    }

    /// The bow's shot: the string snaps forward at once while the hand flings back, then the
    /// hand returns, nocks the next arrow, and draws.
    private static func bowPhases(_ p: Float) -> (draw: Float, flick: Float, holding: Float, nocked: Bool) {
        (draw: ease((p - 0.45) / 0.45), flick: sin(min(p / 0.4, 1) * .pi), holding: ease((p - 0.4) / 0.06), nocked: p > 0.42)
    }

    /// The staff's flourish: a quick thrust at the foe, then one full twirl.
    private static func staffPhases(_ p: Float) -> (thrust: Float, twirl: Float, spin: Float) {
        (thrust: ease(p / 0.07) * (1 - ease((p - 0.18) / 0.12)),
         twirl: ease((p - 0.2) / 0.1) * (1 - ease((p - 0.8) / 0.18)),
         spin: 2 * .pi * ease((p - 0.28) / 0.5))
    }

    /// Torso orientation in hips space: turned by `twist`, then leaning along its own facing.
    private static func torsoRotation(_ twist: Float, _ lean: Float) -> simd_quatf {
        simd_quatf(angle: twist, axis: [0, 1, 0]) * simd_quatf(angle: lean, axis: [1, 0, 0])
    }

    /// Arm rotation pointing the weapon arm along the swing, the fist's forward (+Z) trailing.
    private static func armPose(_ swing: Swing, _ s: Float) -> simd_quatf {
        let (direction, lean) = swing.arm(s)
        return aim(direction, toward: lean)
    }

    /// Arm rotation pointing the arm along `direction`, rolled so the fist-space `axis` leans toward `toward`.
    private static func aim(_ direction: SIMD3<Float>, toward: SIMD3<Float>, axis: SIMD3<Float> = [0, 0, 1]) -> simd_quatf {
        let y = -simd_normalize(direction)
        let side = toward - simd_dot(toward, y) * y
        let z = simd_length(side) > 0.0001 ? simd_normalize(side) : simd_normalize(simd_cross([1, 0, 0], y))
        return simd_quatf(simd_float3x3(simd_cross(y, z), y, z)) * simd_quatf(angle: -atan2(axis.x, axis.z), axis: [0, 1, 0])
    }

    /// Refits the bow string through the nock (on the drawing hand while it holds the string)
    /// and shows the arrow resting on it.
    private func updateBowString(nock amount: Float, arrow shown: Bool) {
        guard let held, held.string.count == 2, held.stringTips.count == 2 else { return }
        let hand = hands[1].position(relativeTo: held.entity)
        let nock = simd_mix(WeaponModels.stringRest, hand, SIMD3(repeating: amount))
        for (half, tip) in zip(held.string, held.stringTips) {
            WeaponModels.fit(half, from: tip, to: nock, radius: 0.004)
        }
        if let arrow = held.arrow {
            arrow.isEnabled = shown
            arrow.position = nock
            arrow.orientation = simd_quatf(from: [0, 0, 1], to: simd_normalize(SIMD3<Float>(0, 0, 0.04) - nock))
        }
    }

    /// Sweeps the trail over where the blade was during the last `trailSpan` of the strike.
    private func updateTrail(_ p: Float, _ style: SwingStyle, baseTwist: Float, baseLean: Float) {
        guard let reach = bladeReach else {
            trail.hide()
            return
        }
        let head = min(p, style.strikeEnd)
        let tail = max(style.strikeStart, p - Self.trailSpan)
        guard head > tail else {
            trail.hide()
            return
        }
        let shoulder = Self.rightShoulder
        // Only the business end of long weapons leaves a ribbon.
        let hilt = WeaponModels.bladeDirection * max(0.16, reach - 0.36)
        let tip = WeaponModels.bladeDirection * reach
        let hand = Self.hand, wristBend = Self.wristBend
        // The trail lives under the hips, so past samples are placed relative to where the hips face now.
        let hipsNow = Self.slashBody(swing, style, p).hipYaw
        let samples = (0...SwingTrail.segments).map { i in
            let q = tail + (head - tail) * Float(i) / Float(SwingTrail.segments)
            let s = Self.slashPhase(q, style).s
            let body = Self.slashBody(swing, style, q)
            let torso = simd_quatf(angle: body.hipYaw - hipsNow, axis: [0, 1, 0])
                * Self.torsoRotation(baseTwist + body.twist, baseLean + body.lean)
            let arm = Self.armPose(swing, s)
            func place(_ point: SIMD3<Float>) -> SIMD3<Float> {
                torso.act(shoulder + arm.act(hand + wristBend.act(point)))
            }
            return (hilt: place(hilt), tip: place(tip))
        }
        // Once the blade stops, the tail catches up and the whole ribbon fades.
        let strength = p > style.strikeEnd ? 1 - (p - style.strikeEnd) / Self.trailSpan : 1
        trail.show(samples, strength: strength)
    }

    /// How far below the hip joint a foot reaches with the leg swung, spread, turned, and bent at the knee.
    private static func footDepth(swing: Float, spread: Float, turn: Float, knee: Float) -> Float {
        let leg = simd_quatf(angle: spread, axis: [0, 0, 1]) * simd_quatf(angle: swing, axis: [1, 0, 0])
            * simd_quatf(angle: turn, axis: [0, 1, 0])
        let shin = simd_quatf(angle: max(0, knee), axis: [1, 0, 0]).act([0, -shinLength, 0])
        return -leg.act(Self.knee + shin).y
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

// MARK: - Looks

extension PlayerRig {
    /// Colors and headgear for one character: Sprout by default, or a townsperson.
    struct Look {
        var skin = SproutLook.skin
        var hair = SproutLook.hair
        var tunic = SproutLook.tunic
        var trim = SproutLook.trim
        var legs = UIColor(red: 0.36, green: 0.27, blue: 0.2, alpha: 1)
        var boots = SproutLook.boots
        var bootCuff = SproutLook.bootCuff
        var scarf = true
        var scarfColor = SproutLook.scarf
        /// The shirt under the open vest (the trim color when nil).
        var shirt: UIColor? = SproutLook.shirt
        /// Bare knees and shins between the shorts and the boots, like a Flyff vagrant.
        var bareLegs = true
        var sprout = true
        var beard: UIColor?
        var longBeard = false
        var iris = FacePainter.Iris.leaf
        /// 0 wide-eyed ... 1 half-lidded.
        var lids: CGFloat = 0
        var lashes = false
        var hairStyle = HairStyle.short
        /// A mushroom cap worn as a hat (the townsfolk are mushroom people at heart).
        var cap: MushroomCap?

        static let sprout = Look()

        var face: FacePainter.Face {
            FacePainter.Face(iris: iris, hair: hair, lids: lids, lashes: lashes)
        }
    }

    enum HairStyle {
        /// Sprout's spiky crop.
        case short
        /// Long locks down the back and beside the face.
        case long
        /// Tied up high at the back.
        case ponytail
    }

    /// The Hollow's mushroom hats, in head space (sitting on the hair).
    enum MushroomCap {
        /// A tall, pitted cone (Elder Morel).
        case morel(UIColor)
        /// A wavy funnel (Chanterelle).
        case funnel(UIColor)
        /// A broad, flat cap with pale cracks (Shiitake).
        case wide(UIColor)
        /// A round cap with spots.
        case beret(UIColor, spots: Bool)
        /// A cluster of tiny white caps on long stalks (Enoki).
        case cluster(UIColor)
        /// Layered frills (Maitake).
        case frills(UIColor)
        /// A pale fan shape (Oyster).
        case fan(UIColor)

        @MainActor
        func build() -> Entity {
            let e = Entity()
            let top: SIMD3<Float> = [0, 0.66, -0.02]
            switch self {
            case let .morel(color):
                let cap = Materials.matte(color, roughness: 1)
                e.addPart(Meshes.cone, cap, at: top + [0, 0.3, 0], scale: [0.36, 0.75, 0.36])
                let pit = Materials.matte(Palette.darkBark, roughness: 1)
                for i in 0..<12 {
                    let a = Float(i) * 2.4
                    let y = 0.08 + Float(i % 6) * 0.08
                    let r = 0.3 - y * 0.42
                    e.addSphere(pit, at: top + [sin(a) * r, y, cos(a) * r], radius: 0.05)
                }
            case let .funnel(color):
                let cap = Materials.matte(color, roughness: 0.6)
                e.addPart(Meshes.cone, cap, at: top + [0, 0.1, 0], scale: [0.48, 0.3, 0.48], rotation: simd_quatf(angle: .pi, axis: [1, 0, 0]))
                e.addCylinder(cap, at: top + [0, 0.25, 0], radius: 0.48, height: 0.05)
            case let .wide(color):
                e.addSphere(Materials.matte(color, roughness: 0.8), at: top + [0, 0.05, 0], radius: 0.56, squash: [1, 0.36, 1])
                let crack = Materials.matte(UIColor(red: 0.9, green: 0.82, blue: 0.68, alpha: 1))
                for i in 0..<7 {
                    let a = Float(i) * 0.9
                    let r: Float = 0.2 + Float(i % 3) * 0.1
                    e.addSphere(crack, at: top + [sin(a) * r, 0.24 - r * 0.3, cos(a) * r], radius: 0.035, squash: [1.8, 0.4, 0.7])
                }
            case let .beret(color, spots):
                e.addSphere(Materials.glossy(color), at: top + [0, 0.06, 0], radius: 0.44, squash: [1, 0.55, 1])
                if spots {
                    for (a, r) in [(Float(0.3), Float(0.15)), (1.8, 0.28), (3.4, 0.25), (4.9, 0.3)] {
                        e.addSphere(Materials.matte(Palette.capSpot), at: top + [sin(a) * r, 0.28 - r * 0.25, cos(a) * r],
                                    radius: 0.06, squash: [1, 0.4, 1])
                    }
                }
            case let .cluster(color):
                let stalk = Materials.matte(UIColor(red: 0.96, green: 0.94, blue: 0.86, alpha: 1))
                let cap = Materials.matte(color)
                for i in 0..<7 {
                    let a = Float(i) / 7 * 2 * .pi
                    let lean = SIMD3<Float>(sin(a) * 0.14, 0.4 + Float(i % 3) * 0.06, cos(a) * 0.14)
                    e.addRod(stalk, from: top, to: top + lean, radius: 0.025)
                    e.addSphere(cap, at: top + lean, radius: 0.06, squash: [1, 0.7, 1])
                }
            case let .frills(color):
                let cap = Materials.matte(color, roughness: 0.9)
                for (i, (y, r)) in [(Float(0.02), Float(0.42)), (0.12, 0.34), (0.22, 0.25), (0.3, 0.15)].enumerated() {
                    e.addSphere(cap, at: top + [Float(i % 2) * 0.03, y, 0], radius: r, squash: [1, 0.22, 1])
                }
            case let .fan(color):
                let cap = Materials.matte(color, roughness: 0.6)
                e.addSphere(cap, at: top + [0.08, 0.06, 0], radius: 0.46, squash: [1.1, 0.3, 0.9])
                e.addSphere(cap, at: top + [-0.18, 0.12, -0.05], radius: 0.3, squash: [1, 0.3, 0.9])
            }
            return e
        }
    }
}

extension UIColor {
    /// The same hue, `factor` as bright.
    func darker(_ factor: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r * factor, green: g * factor, blue: b * factor, alpha: a)
    }
}
