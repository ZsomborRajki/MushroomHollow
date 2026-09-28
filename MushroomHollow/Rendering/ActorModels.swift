import GameCore
import RealityKit
import UIKit

/// Placeholder models for mobs and NPCs, built from primitives (the player is `PlayerRig`).
/// The newer critters live in `CritterModels`.
/// Every model faces +Z (yaw 0) and stands on y = 0.
@MainActor
enum ActorModels {
    static func make(_ kind: EntityKind) -> Entity {
        let model = Entity()
        switch kind {
        case .player: return PlayerRig().root
        case .mob(.snail): buildSnail(into: model)
        case .mob(.slug): buildSlug(into: model)
        case .mob(.beetle): buildBeetle(into: model)
        case .mob(.sporeBeast): buildSporeBeast(into: model)
        case .mob(.sporeling): buildSporeling(into: model)
        case .mob(.mouse): buildMouse(into: model)
        case .mob(.ladybug): buildLadybug(into: model)
        case .mob(.pillBug): buildPillBug(into: model)
        case .mob(.acornling): buildAcornling(into: model)
        case .mob(.bogFrog): buildBogFrog(into: model)
        case .mob(.fuzzbee): buildFuzzbee(into: model)
        case .mob(.puffweed): buildPuffweed(into: model)
        case .mob(.puffling): buildPuffling(into: model)
        case .mob(.mossTurtle): buildMossTurtle(into: model)
        case .mob(.emberNewt): buildEmberNewt(into: model)
        case .mob(.weaverSpider): buildWeaverSpider(into: model)
        case .mob(.duskMoth): buildDuskMoth(into: model)
        case .mob(.hedgehog): buildHedgehog(into: model)
        case .mob(.coneKnight): buildConeKnight(into: model)
        case .mob(.mantis): buildMantis(into: model)
        case .mob(.thornrose): buildThornrose(into: model)
        case .mob(.grumblecap): buildGrumblecap(into: model)
        case .mob(.stagBeetle): buildStagBeetle(into: model)
        case .mob(.owl): buildOwl(into: model)
        case .npc(.elderMorel): buildElderMorel(into: model)
        case .npc(.chanterelle): buildChanterelle(into: model)
        case .npc(.shiitake): buildShiitake(into: model)
        case .npc(.truffle): buildTruffle(into: model)
        case .npc(.porcini): buildPorcini(into: model)
        }
        return model
    }

    /// A dandelion seed parachute; the player holds its long stalk at `grip`.
    static func makeGlider(grip: SIMD3<Float>) -> Entity {
        let e = Entity()
        let fluff = Materials.matte(UIColor(white: 0.97, alpha: 1), roughness: 1)
        let top = SIMD3<Float>(grip.x, 2.9, grip.z)
        e.addRod(Materials.matte(Palette.stem, roughness: 0.8), from: grip - [0, 0.1, 0], to: top, radius: 0.022)
        e.addSphere(Materials.matte(Palette.capBrown), at: grip - [0, 0.14, 0], radius: 0.05, squash: [1, 1.4, 1])
        for i in 0..<14 {
            let yaw = Float(i) / 14 * 2 * .pi
            let tilt = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: 1.05, axis: [1, 0, 0])
            let tip = tilt.act([0, 0.75, 0])
            e.addCylinder(fluff, at: top + tip / 2, radius: 0.012, height: 0.75, rotation: tilt)
            e.addSphere(fluff, at: top + tip, radius: 0.1, squash: [1, 0.6, 1])
        }
        e.addSphere(fluff, at: top, radius: 0.12)
        return e
    }

    private static func buildSnail(into e: Entity) {
        let body = Materials.matte(Palette.snailBody, roughness: 0.4)
        e.addPart(Meshes.roundedBox, body, at: [0, 0.11, 0.05], scale: [0.42, 0.22, 1.2])
        e.addSphere(body, at: [0, 0.24, 0.52], radius: 0.19)
        addEyeStalks(to: e, material: body, z: 0.55, baseY: 0.32)
        e.addSphere(Materials.matte(Palette.snailShell, roughness: 0.5), at: [0, 0.52, -0.14], radius: 0.42, squash: [0.85, 1, 1])
        let swirl = Materials.matte(Palette.snailShellLight, roughness: 0.5)
        e.addSphere(swirl, at: [0.2, 0.54, -0.14], radius: 0.27, squash: [0.8, 1, 1])
        e.addSphere(swirl, at: [0.32, 0.55, -0.14], radius: 0.13, squash: [0.8, 1, 1])
    }

    private static func buildSlug(into e: Entity) {
        let body = Materials.matte(Palette.slugBody, roughness: 0.3)
        e.addPart(Meshes.roundedBox, body, at: [0, 0.15, 0], scale: [0.45, 0.3, 1.4])
        e.addSphere(Materials.matte(Palette.slugRidge, roughness: 0.3), at: [0, 0.3, -0.12], radius: 1, squash: [0.2, 0.12, 0.5])
        e.addSphere(body, at: [0, 0.22, 0.58], radius: 0.2)
        addEyeStalks(to: e, material: body, z: 0.62, baseY: 0.32)
    }

    private static func buildBeetle(into e: Entity) {
        e.addSphere(Materials.glossy(Palette.beetleShell), at: [0, 0.45, -0.05], radius: 0.6, squash: [1, 0.6, 1.25])
        let dark = Materials.glossy(Palette.eye)
        e.addSphere(dark, at: [0, 0.35, 0.72], radius: 0.28)
        e.addPart(Meshes.cone, dark, at: [0, 0.6, 0.9], scale: [0.08, 0.4, 0.08],
                  rotation: simd_quatf(angle: 0.7, axis: [1, 0, 0]))
    }

    private static func buildSporeBeast(into e: Entity) {
        e.addSphere(Materials.matte(Palette.sporeBody), at: [0, 0.75, 0], radius: 0.75)
        e.addSphere(Materials.matte(Palette.capBrown, roughness: 0.5), at: [0, 1.35, 0], radius: 0.95, squash: [1, 0.45, 1])
        let glow = Materials.glow(Palette.sporeGlow)
        e.addSphere(glow, at: [0.4, 1.6, 0.3], radius: 0.12)
        e.addSphere(glow, at: [-0.35, 1.62, -0.2], radius: 0.1)
        e.addSphere(glow, at: [-0.2, 0.9, 0.68], radius: 0.09)
        e.addSphere(glow, at: [0.2, 0.9, 0.68], radius: 0.09)
    }

    private static func buildSporeling(into e: Entity) {
        e.addSphere(Materials.matte(Palette.sporeBody), at: [0, 0.35, 0], radius: 0.35)
        e.addSphere(Materials.matte(Palette.capBrown, roughness: 0.5), at: [0, 0.62, 0], radius: 0.38, squash: [1, 0.45, 1])
        let glow = Materials.glow(Palette.sporeGlow)
        e.addSphere(glow, at: [-0.1, 0.42, 0.3], radius: 0.05)
        e.addSphere(glow, at: [0.1, 0.42, 0.3], radius: 0.05)
    }

    private static func buildElderMorel(into e: Entity) {
        let robe = Materials.matte(UIColor(red: 0.45, green: 0.42, blue: 0.5, alpha: 1))
        e.addCylinder(robe, at: [0, 0.55, 0], radius: 0.32, height: 1.1)
        e.addSphere(robe, at: [0, 0.08, 0], radius: 0.34, squash: [1, 0.3, 1])
        e.addSphere(Materials.matte(Palette.skin), at: [0, 1.28, 0], radius: 0.25)
        e.addSphere(Materials.matte(Palette.capSpot), at: [0, 1.12, 0.17], radius: 0.2, squash: [1, 1.3, 0.6]) // beard
        let eye = Materials.glossy(Palette.eye)
        e.addSphere(eye, at: [-0.08, 1.32, 0.22], radius: 0.03)
        e.addSphere(eye, at: [0.08, 1.32, 0.22], radius: 0.03)
        // A tall, wrinkled morel cap.
        let morel = Materials.matte(Palette.capBrown, roughness: 1)
        e.addPart(Meshes.cone, morel, at: [0, 1.85, 0], scale: [0.36, 0.9, 0.36])
        let pit = Materials.matte(Palette.darkBark, roughness: 1)
        for i in 0..<10 {
            let a = Float(i) * 2.4
            let y: Float = 1.55 + Float(i % 5) * 0.12
            let r: Float = 0.3 - (y - 1.45) * 0.3
            e.addSphere(pit, at: [sin(a) * r, y, cos(a) * r], radius: 0.06)
        }
        // Walking staff.
        e.addCylinder(Materials.matte(Palette.bark), at: [0.42, 0.8, 0.1], radius: 0.035, height: 1.6)
        e.addSphere(Materials.glow(Palette.glowCap), at: [0.42, 1.64, 0.1], radius: 0.08)
    }

    private static func buildChanterelle(into e: Entity) {
        e.addCylinder(Materials.matte(Palette.stem), at: [0, 0.6, 0], radius: 0.28, height: 1.0)
        e.addCylinder(Materials.matte(UIColor(red: 0.95, green: 0.9, blue: 0.8, alpha: 1)), at: [0, 0.55, 0.05], radius: 0.29, height: 0.6) // apron
        e.addSphere(Materials.matte(Palette.skin), at: [0, 1.28, 0], radius: 0.25)
        let eye = Materials.glossy(Palette.eye)
        e.addSphere(eye, at: [-0.08, 1.3, 0.22], radius: 0.035)
        e.addSphere(eye, at: [0.08, 1.3, 0.22], radius: 0.035)
        // Chanterelles have funnel-shaped, wavy orange caps.
        let orange = Materials.matte(UIColor(red: 0.98, green: 0.62, blue: 0.15, alpha: 1), roughness: 0.6)
        e.addPart(Meshes.cone, orange, at: [0, 1.62, 0], scale: [0.5, 0.35, 0.5], rotation: simd_quatf(angle: .pi, axis: [1, 0, 0]))
        e.addCylinder(orange, at: [0, 1.79, 0], radius: 0.5, height: 0.05)
        // A satchel of wares.
        e.addPart(Meshes.roundedBox, Materials.matte(Palette.door), at: [-0.33, 0.7, 0], scale: [0.14, 0.32, 0.3])
    }

    /// The blacksmith: stout, with a broad cracked shiitake cap, a leather apron, and a hammer.
    private static func buildShiitake(into e: Entity) {
        e.addCylinder(Materials.matte(Palette.stem), at: [0, 0.55, 0], radius: 0.36, height: 0.95)
        let leather = Materials.matte(UIColor(red: 0.36, green: 0.22, blue: 0.14, alpha: 1), roughness: 0.9)
        e.addCylinder(leather, at: [0, 0.5, 0.04], radius: 0.37, height: 0.7) // apron
        e.addPart(Meshes.torus(radius: 0.37, tube: 0.025), Materials.matte(Palette.darkBark), at: [0, 0.82, 0], scale: .one)
        e.addSphere(Materials.matte(Palette.skin), at: [0, 1.22, 0], radius: 0.26)
        let eye = Materials.glossy(Palette.eye)
        e.addSphere(eye, at: [-0.09, 1.25, 0.23], radius: 0.035)
        e.addSphere(eye, at: [0.09, 1.25, 0.23], radius: 0.035)
        e.addSphere(Materials.matte(Palette.darkBark), at: [0, 1.1, 0.2], radius: 0.13, squash: [1.4, 0.45, 0.6]) // moustache
        // A wide, dark brown cap with pale cracks.
        let cap = Materials.matte(UIColor(red: 0.42, green: 0.26, blue: 0.16, alpha: 1), roughness: 0.8)
        e.addSphere(cap, at: [0, 1.5, 0], radius: 0.56, squash: [1, 0.42, 1])
        let crack = Materials.matte(UIColor(red: 0.9, green: 0.82, blue: 0.68, alpha: 1))
        for i in 0..<7 {
            let a = Float(i) * 0.9
            let r: Float = 0.2 + Float(i % 3) * 0.1
            e.addSphere(crack, at: [sin(a) * r, 1.72 - r * 0.35, cos(a) * r], radius: 0.035, squash: [1.8, 0.4, 0.7])
        }
        // A smith's hammer, resting in the right hand.
        let handle = Materials.matte(Palette.bark)
        e.addCylinder(handle, at: [-0.45, 0.62, 0.12], radius: 0.03, height: 0.6)
        e.addPart(Meshes.roundedBox, Materials.glossy(UIColor(white: 0.45, alpha: 1)), at: [-0.45, 0.95, 0.12], scale: [0.26, 0.13, 0.13])
        e.addSphere(Materials.matte(Palette.skin), at: [-0.45, 0.7, 0.12], radius: 0.07)
    }

    /// The naturalist: a fat porcini with a bulbous stem, round spectacles, and a field notebook.
    private static func buildPorcini(into e: Entity) {
        let stem = Materials.matte(UIColor(red: 0.93, green: 0.88, blue: 0.76, alpha: 1))
        e.addSphere(stem, at: [0, 0.42, 0], radius: 0.4, squash: [1, 1.05, 1]) // a porcini's belly of a stem
        e.addCylinder(stem, at: [0, 0.85, 0], radius: 0.27, height: 0.45)
        let vest = Materials.matte(UIColor(red: 0.36, green: 0.46, blue: 0.3, alpha: 1), roughness: 0.9)
        e.addCylinder(vest, at: [0, 0.62, 0.03], radius: 0.36, height: 0.4)
        e.addSphere(Materials.matte(Palette.skin), at: [0, 1.2, 0], radius: 0.25)
        let eye = Materials.glossy(Palette.eye)
        e.addSphere(eye, at: [-0.08, 1.23, 0.22], radius: 0.03)
        e.addSphere(eye, at: [0.08, 1.23, 0.22], radius: 0.03)
        // Round spectacles.
        let wire = Materials.glossy(UIColor(red: 0.75, green: 0.6, blue: 0.3, alpha: 1))
        for side: Float in [-1, 1] {
            e.addPart(Meshes.torus(radius: 0.065, tube: 0.01), wire, at: [side * 0.08, 1.23, 0.235], scale: .one,
                      rotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))
        }
        // A plump, glossy chestnut cap, paler at the rim.
        let cap = Materials.glossy(UIColor(red: 0.55, green: 0.33, blue: 0.17, alpha: 1))
        e.addSphere(cap, at: [0, 1.52, 0], radius: 0.5, squash: [1, 0.55, 1])
        e.addPart(Meshes.torus(radius: 0.45, tube: 0.06), Materials.matte(UIColor(red: 0.78, green: 0.6, blue: 0.4, alpha: 1)),
                  at: [0, 1.4, 0], scale: .one)
        // A field notebook in one hand, a pencil in the other.
        let hand = Materials.matte(Palette.skin)
        e.addPart(Meshes.roundedBox, Materials.matte(UIColor(red: 0.62, green: 0.25, blue: 0.2, alpha: 1)),
                  at: [0.3, 0.78, 0.3], scale: [0.2, 0.26, 0.05], rotation: simd_quatf(angle: -0.5, axis: [0, 1, 0]))
        e.addSphere(hand, at: [0.36, 0.72, 0.26], radius: 0.07)
        e.addCylinder(Materials.matte(UIColor(red: 0.95, green: 0.8, blue: 0.3, alpha: 1)), at: [-0.34, 0.8, 0.28],
                      radius: 0.018, height: 0.22)
        e.addSphere(hand, at: [-0.34, 0.74, 0.28], radius: 0.07)
    }

    /// Named wing pivots, so the renderer can flap and spread them (the owl, bees, moths).
    static let wingNames = ["wing.left", "wing.right"]

    private static func buildOwl(into e: Entity) {
        let feather = Materials.matte(Palette.owlFeather)
        let chest = Materials.matte(UIColor(red: 0.78, green: 0.68, blue: 0.52, alpha: 1))
        let dark = Materials.matte(UIColor(red: 0.28, green: 0.2, blue: 0.14, alpha: 1))
        e.addSphere(feather, at: [0, 2.5, 0], radius: 2.1, squash: [1, 1.2, 0.9])
        e.addSphere(chest, at: [0, 2.3, 0.9], radius: 1.5, squash: [1, 1.15, 0.6])
        for row in 0..<3 {
            for column in -1...1 {
                e.addSphere(dark, at: [Float(column) * 0.5, 1.7 + Float(row) * 0.55, 1.75], radius: 0.12, squash: [1.4, 0.6, 0.5])
            }
        }
        // Head, facial disc, ear tufts, beak.
        e.addSphere(feather, at: [0, 4.8, 0.15], radius: 1.45)
        e.addSphere(chest, at: [0, 4.75, 1.05], radius: 1.1, squash: [1.15, 1, 0.45])
        for side: Float in [-1, 1] {
            e.addPart(Meshes.cone, feather, at: [side * 0.8, 6.2, 0], scale: [0.35, 0.9, 0.3],
                      rotation: simd_quatf(angle: side * -0.35, axis: [0, 0, 1]))
            e.addSphere(Materials.glow(Palette.owlEye), at: [side * 0.52, 4.95, 1.4], radius: 0.42, squash: [1, 1, 0.3])
            e.addSphere(Materials.glossy(Palette.eye), at: [side * 0.52, 4.95, 1.52], radius: 0.2, squash: [1, 1, 0.3])
        }
        e.addPart(Meshes.cone, Materials.glossy(UIColor(red: 0.35, green: 0.3, blue: 0.25, alpha: 1)), at: [0, 4.45, 1.55],
                  scale: [0.2, 0.5, 0.2], rotation: simd_quatf(angle: .pi, axis: [1, 0, 0]))
        // Talons.
        for side: Float in [-1, 1] {
            e.addSphere(Materials.matte(Palette.shelfFungus), at: [side * 0.7, 0.2, 0.6], radius: 0.35, squash: [1, 0.5, 1.4])
        }
        // Wings: pivot at the shoulder so they can fold and spread.
        for (index, side) in [Float(-1), 1].enumerated() {
            let wing = Entity()
            wing.name = wingNames[index]
            wing.position = [side * 1.7, 3.6, -0.2]
            wing.addSphere(feather, at: [side * 0.6, -1.3, 0], radius: 1, squash: [0.45, 1.6, 1.1])
            wing.addSphere(dark, at: [side * 0.7, -2.4, -0.1], radius: 0.6, squash: [0.4, 1, 1])
            e.addChild(wing)
        }
    }

    private static func buildMouse(into e: Entity) {
        let fur = Materials.matte(UIColor(red: 0.55, green: 0.47, blue: 0.4, alpha: 1))
        let pink = Materials.matte(UIColor(red: 0.95, green: 0.7, blue: 0.7, alpha: 1))
        e.addSphere(fur, at: [0, 0.35, -0.05], radius: 0.35, squash: [1, 0.9, 1.4])
        e.addSphere(fur, at: [0, 0.45, 0.45], radius: 0.22)
        e.addSphere(pink, at: [0, 0.42, 0.66], radius: 0.05)
        for side: Float in [-1, 1] {
            e.addCylinder(pink, at: [side * 0.15, 0.68, 0.4], radius: 0.13, height: 0.03,
                          rotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))
            e.addSphere(Materials.glossy(Palette.eye), at: [side * 0.09, 0.5, 0.62], radius: 0.035)
        }
        e.addCylinder(pink, at: [0, 0.25, -0.75], radius: 0.025, height: 0.7,
                      rotation: simd_quatf(angle: 1.2, axis: [1, 0, 0]))
    }

    private static func addEyeStalks(to e: Entity, material: any RealityKit.Material, z: Float, baseY: Float) {
        let tilt = simd_quatf(angle: 0.35, axis: [1, 0, 0])
        let eye = Materials.glossy(Palette.eye)
        for side: Float in [-1, 1] {
            e.addCylinder(material, at: [side * 0.08, baseY + 0.14, z + 0.04], radius: 0.028, height: 0.32, rotation: tilt)
            e.addSphere(eye, at: [side * 0.08, baseY + 0.3, z + 0.1], radius: 0.05)
        }
    }
}
