import GameCore
import RealityKit
import SwiftUI
import UIKit

/// Small world models for rewards. Weapons and shields reuse their equipped models;
/// the remaining item families use a recognizable ground silhouette and item tint.
@MainActor
enum DropModels {
    static func make(_ kind: GroundDropKind) -> Entity {
        let root = Entity()
        switch kind {
        case .caps:
            let gold = Materials.glossy(UIColor(red: 1, green: 0.76, blue: 0.23, alpha: 1))
            let edge = Materials.matte(UIColor(red: 0.55, green: 0.3, blue: 0.08, alpha: 1))
            for (x, z, y) in [(-0.13, 0.02, 0.08), (0.1, -0.09, 0.08), (0.01, 0.12, 0.12)] as [(Float, Float, Float)] {
                root.addCylinder(edge, at: [x, y, z], radius: 0.17, height: 0.055)
                root.addCylinder(gold, at: [x, y + 0.033, z], radius: 0.145, height: 0.012)
                root.addSphere(edge, at: [x, y + 0.043, z], radius: 0.045, squash: [1, 0.18, 1])
            }
        case let .item(item, _):
            let tint = UIColor(item.tint)
            let material = Materials.glossy(tint)
            if item.definition.weaponType != nil {
                let weapon = WeaponModels.make(item).entity
                weapon.position = [0, 0.2, 0]
                weapon.scale = SIMD3(repeating: 1.35)
                root.addChild(weapon)
            } else if item.definition.equipSlot == .shield {
                let shield = WeaponModels.makeShield(item)
                shield.position = [0, 0.18, 0]
                shield.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
                shield.scale = SIMD3(repeating: 1.5)
                root.addChild(shield)
            } else {
                switch item.definition.kind {
                case .consumable:
                    root.addCylinder(Materials.translucent(tint, opacity: 0.75), at: [0, 0.19, 0], radius: 0.13, height: 0.3)
                    root.addCylinder(Materials.matte(Palette.bark), at: [0, 0.38, 0], radius: 0.09, height: 0.08)
                case .equipment(.hat, _):
                    root.addPart(Meshes.cone, material, at: [0, 0.2, 0], scale: [0.34, 0.36, 0.34])
                case .equipment(.body, _):
                    root.addPart(Meshes.roundedBox, material, at: [0, 0.13, 0], scale: [0.5, 0.15, 0.42])
                case .equipment(.gloves, _):
                    for x: Float in [-0.15, 0.15] {
                        root.addSphere(material, at: [x, 0.14, 0], radius: 0.16, squash: [0.8, 0.6, 1.2])
                    }
                case .equipment(.boots, _):
                    for x: Float in [-0.14, 0.14] {
                        root.addPart(Meshes.roundedBox, material, at: [x, 0.13, 0], scale: [0.2, 0.16, 0.34])
                    }
                case .equipment:
                    root.addSphere(material, at: [0, 0.2, 0], radius: 0.2)
                case .material:
                    addMaterial(item, to: root, material: material)
                case .glider:
                    root.addRod(Materials.matte(Palette.dandelionStem), from: [0, 0.08, 0], to: [0, 0.42, 0], radius: 0.025)
                    root.addSphere(material, at: [0, 0.45, 0], radius: 0.18)
                case .pet:
                    root.addSphere(material, at: [0, 0.2, 0], radius: 0.2)
                case .petFood:
                    // A little sack of kibble.
                    root.addSphere(material, at: [0, 0.17, 0], radius: 0.2, squash: [1, 0.85, 0.9])
                    root.addCylinder(Materials.matte(Palette.bark), at: [0, 0.34, 0], radius: 0.07, height: 0.08)
                }
            }
            if item.definition.rarity != .common {
                let glow = Materials.glow(item.definition.rarity == .unique ? Palette.owlEye : Palette.glowCap)
                root.addPart(Meshes.ring, glow, at: [0, 0.025, 0], scale: SIMD3(repeating: 0.48))
            }
        }
        root.components.set(DynamicLightShadowComponent(castsShadow: false))
        return root
    }

    private static func addMaterial(_ item: ItemID, to root: Entity, material: any RealityKit.Material) {
        switch item {
        case .amberShard:
            root.addPart(Meshes.teardrop, material, at: [0, 0.22, 0], scale: [0.18, 0.25, 0.18])
        case .wardCharm:
            root.addPart(Meshes.torus(radius: 0.17, tube: 0.04), material, at: [0, 0.18, 0], scale: .one)
        case .snailShell, .spottedWingCase, .pillBugPlate, .mossyScute, .pineScale, .emberScale:
            root.addSphere(material, at: [0, 0.15, 0], radius: 0.3, squash: [1, 0.45, 0.75])
        case .beetleHorn, .hedgehogQuill, .mantisClaw, .stagMandible:
            root.addPart(Meshes.cone, material, at: [0, 0.16, 0], scale: [0.18, 0.3, 0.18],
                         rotation: simd_quatf(angle: .pi / 2, axis: [0, 0, 1]))
        case .owlFeather:
            root.addPart(Meshes.teardrop, material, at: [0, 0.12, 0], scale: [0.12, 0.06, 0.36],
                         rotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))
        case .bitterAcorn, .roseHip:
            root.addSphere(material, at: [0, 0.2, 0], radius: 0.2)
            root.addPart(Meshes.cone, Materials.matte(Palette.bark), at: [0, 0.37, 0], scale: [0.16, 0.12, 0.16])
        default:
            root.addSphere(material, at: [0, 0.17, 0], radius: 0.21)
        }
    }
}
