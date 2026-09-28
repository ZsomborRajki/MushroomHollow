import GameCore
import RealityKit
import UIKit

/// Placeholder models for players and mobs, built from primitives.
/// Every model faces +Z (yaw 0) and stands on y = 0.
@MainActor
enum ActorModels {
    static func make(_ kind: EntityKind) -> Entity {
        let model = Entity()
        switch kind {
        case .player: buildPlayer(into: model)
        case .mob(.snail): buildSnail(into: model)
        case .mob(.slug): buildSlug(into: model)
        case .mob(.beetle): buildBeetle(into: model)
        case .mob(.sporeBeast): buildSporeBeast(into: model)
        case .mob(.sporeling): buildSporeling(into: model)
        case .mob(.owl): buildOwl(into: model)
        case .npc(.elderMorel): buildElderMorel(into: model)
        case .npc(.chanterelle): buildChanterelle(into: model)
        }
        return model
    }

    /// A dandelion seed parachute that the player hangs from while flying.
    static func makeGlider() -> Entity {
        let e = Entity()
        let fluff = Materials.matte(UIColor(white: 0.97, alpha: 1), roughness: 1)
        let stalk = Materials.matte(Palette.stem, roughness: 0.8)
        e.addCylinder(stalk, at: [0, 2.3, 0], radius: 0.025, height: 1.2)
        e.addSphere(Materials.matte(Palette.capBrown), at: [0, 1.72, 0], radius: 0.07)
        for i in 0..<14 {
            let yaw = Float(i) / 14 * 2 * .pi
            let tilt = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: 1.05, axis: [1, 0, 0])
            let tip = tilt.act([0, 0.75, 0])
            e.addCylinder(fluff, at: [0, 2.9, 0] + tip / 2, radius: 0.012, height: 0.75, rotation: tilt)
            e.addSphere(fluff, at: [0, 2.9, 0] + tip, radius: 0.1, squash: [1, 0.6, 1])
        }
        e.addSphere(fluff, at: [0, 2.9, 0], radius: 0.12)
        return e
    }

    /// Visible gear layered onto the player model, plus a class emblem.
    static func makeGear(_ gear: [ItemID], playerClass: PlayerClass?) -> Entity {
        let e = Entity()
        switch playerClass {
        case .guardian:
            // Round shield on the back.
            e.addCylinder(Materials.glossy(Palette.bark), at: [0, 0.8, -0.3], radius: 0.3, height: 0.06,
                          rotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))
            e.addSphere(Materials.glossy(Palette.shelfFungus), at: [0, 0.8, -0.34], radius: 0.08)
        case .thornshot:
            // Quiver of thorns.
            e.addCylinder(Materials.matte(Palette.door), at: [0.12, 0.85, -0.3], radius: 0.08, height: 0.5,
                          rotation: simd_quatf(angle: 0.35, axis: [0, 0, 1]))
            for i in 0..<3 {
                e.addPart(Meshes.cone, Materials.matte(Palette.leaf), at: [0.2 + Float(i) * 0.04, 1.18, -0.3],
                          scale: [0.03, 0.2, 0.03], rotation: simd_quatf(angle: 0.35, axis: [0, 0, 1]))
            }
        case .sporecaster:
            // A floating spore orb over the shoulder.
            e.addSphere(Materials.glow(UIColor(red: 0.75, green: 0.45, blue: 1, alpha: 1)), at: [0.45, 1.55, -0.1], radius: 0.12)
            e.addSphere(Materials.glow(Palette.sporeGlow), at: [0.45, 1.55, -0.1], radius: 0.06)
        case .dewkeeper:
            // A halo of dew.
            let dew = Materials.glow(UIColor(red: 0.55, green: 0.9, blue: 1, alpha: 1))
            for i in 0..<8 {
                let a = Float(i) / 8 * 2 * .pi
                e.addSphere(dew, at: [sin(a) * 0.32, 1.85, cos(a) * 0.32], radius: 0.05)
            }
        case nil:
            break
        }
        for item in gear {
            switch item {
            case .twigSword, .thornRapier, .beetleBlade:
                let color = item == .twigSword ? Palette.bark : item == .thornRapier ? Palette.shelfFungus : Palette.beetleShell
                let blade = Materials.glossy(color)
                let grip = simd_quatf(angle: 0.9, axis: [1, 0, 0])
                let length: Float = item == .beetleBlade ? 0.9 : 0.75
                e.addCylinder(blade, at: [0.33, 0.75, 0.28], radius: item == .twigSword ? 0.035 : 0.03, height: length, rotation: grip)
                e.addSphere(Materials.matte(Palette.boots), at: [0.33, 0.55, 0.05], radius: 0.06)
            case .acornCap:
                e.addSphere(Materials.matte(Palette.capBrown, roughness: 0.9), at: [0, 1.6, 0], radius: 0.3, squash: [1, 0.45, 1])
                e.addCylinder(Materials.matte(Palette.darkBark), at: [0, 1.76, 0], radius: 0.035, height: 0.12)
            case .beetleHelm:
                e.addSphere(Materials.glossy(Palette.beetleShell), at: [0, 1.58, 0], radius: 0.44, squash: [1, 0.5, 1])
            case .leafTunic:
                e.addCylinder(Materials.matte(Palette.leaf, roughness: 0.7), at: [0, 0.7, 0], radius: 0.285, height: 0.5)
            case .barkMail:
                e.addCylinder(Materials.matte(Palette.bark, roughness: 1), at: [0, 0.72, 0], radius: 0.3, height: 0.55)
            case .mossBoots:
                let moss = Materials.matte(Palette.darkMoss, roughness: 1)
                e.addSphere(moss, at: [-0.11, 0.06, 0.03], radius: 0.11, squash: [1, 0.7, 1.3])
                e.addSphere(moss, at: [0.11, 0.06, 0.03], radius: 0.11, squash: [1, 0.7, 1.3])
            default:
                break
            }
        }
        return e
    }

    private static func buildPlayer(into e: Entity) {
        let boots = Materials.matte(Palette.boots)
        e.addCylinder(boots, at: [-0.11, 0.2, 0], radius: 0.085, height: 0.4)
        e.addCylinder(boots, at: [0.11, 0.2, 0], radius: 0.085, height: 0.4)
        e.addCylinder(Materials.matte(Palette.tunic), at: [0, 0.68, 0], radius: 0.26, height: 0.6)
        e.addSphere(Materials.matte(Palette.tunic), at: [0, 0.4, 0], radius: 0.27, squash: [1, 0.35, 1])
        e.addSphere(Materials.matte(Palette.skin), at: [0, 1.22, 0], radius: 0.25)
        let eye = Materials.glossy(Palette.eye)
        e.addSphere(eye, at: [-0.085, 1.24, 0.225], radius: 0.035)
        e.addSphere(eye, at: [0.085, 1.24, 0.225], radius: 0.035)
        // The mushroom-cap hat every Hollow villager wears.
        e.addSphere(Materials.matte(Palette.capRed, roughness: 0.5), at: [0, 1.42, 0], radius: 0.42, squash: [1, 0.48, 1])
        let spot = Materials.matte(Palette.capSpot)
        e.addSphere(spot, at: [0, 1.62, 0], radius: 0.09, squash: [1, 0.4, 1])
        e.addSphere(spot, at: [0.24, 1.55, 0.1], radius: 0.07, squash: [1, 0.45, 1])
        e.addSphere(spot, at: [-0.2, 1.55, -0.16], radius: 0.07, squash: [1, 0.45, 1])
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

    private static func buildOwl(into e: Entity) {
        let feather = Materials.matte(Palette.owlFeather)
        e.addSphere(feather, at: [0, 2.6, 0], radius: 2.2, squash: [1, 1.2, 0.95])
        e.addSphere(feather, at: [0, 5.0, 0.2], radius: 1.5)
        let eye = Materials.glow(Palette.owlEye)
        e.addSphere(eye, at: [-0.6, 5.1, 1.45], radius: 0.45, squash: [1, 1, 0.3])
        e.addSphere(eye, at: [0.6, 5.1, 1.45], radius: 0.45, squash: [1, 1, 0.3])
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
