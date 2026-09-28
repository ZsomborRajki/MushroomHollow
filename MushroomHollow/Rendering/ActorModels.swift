import GameCore
import RealityKit

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
        case .mob(.owl): buildOwl(into: model)
        }
        return model
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
