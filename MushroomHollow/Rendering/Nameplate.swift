import GameCore
import RealityKit
import UIKit

/// The floating name over mobs and NPCs, like Flyff's: "Lv 3 Aphid", tinted by how tough it is
/// for you (grey: not worth it, green: easy, white: even, orange: tough, red: run), and NPC names in
/// mint with their trade underneath. Always faces the camera.
@MainActor
final class Nameplate {
    let root = Entity()
    private let title: String
    private let isNPC: Bool
    private let isGiant: Bool
    private var label: ModelEntity?
    private var shownLevel: Int?
    private var shownTier: Tier?

    private static let fontSize: Float = 0.2
    private static let lift: Float = 0.35

    enum Tier {
        case trivial, easy, even, tough, deadly

        init(mobLevel: Int, viewerLevel: Int) {
            let gap = mobLevel - viewerLevel
            self = switch gap {
            case ...(-8): .trivial
            case ...(-3): .easy
            case ...2: .even
            case ...5: .tough
            default: .deadly
            }
        }

        var color: UIColor {
            switch self {
            case .trivial: UIColor(white: 0.62, alpha: 1)
            case .easy: UIColor(red: 0.55, green: 0.95, blue: 0.45, alpha: 1)
            case .even: .white
            case .tough: UIColor(red: 1, green: 0.66, blue: 0.25, alpha: 1)
            case .deadly: UIColor(red: 1, green: 0.3, blue: 0.25, alpha: 1)
            }
        }
    }

    init(title: String, subtitle: String?, isNPC: Bool, isGiant: Bool) {
        self.title = title
        self.isNPC = isNPC
        self.isGiant = isGiant
        root.components.set(DynamicLightShadowComponent(castsShadow: false))
        if isNPC {
            let name = Self.text(title, size: Self.fontSize, color: UIColor(red: 0.6, green: 1, blue: 0.75, alpha: 1))
            name.position.y = 0.12
            root.addChild(name)
            if let subtitle {
                let trade = Self.text(subtitle, size: Self.fontSize * 0.7, color: UIColor(red: 1, green: 0.9, blue: 0.6, alpha: 1))
                trade.position.y = -0.1
                root.addChild(trade)
            }
        }
    }

    /// Hangs the plate above an actor whose entity is scaled by `size` (Giants), keeping the text its normal size.
    func attach(to entity: Entity, headHeight: Float, size: Float) {
        root.scale = SIMD3(repeating: 1 / size)
        root.position = [0, headHeight + Self.lift / size, 0]
        entity.addChild(root)
    }

    func update(level: Int, viewerLevel: Int?, alive: Bool, facing: simd_quatf) {
        if root.isEnabled != alive { root.isEnabled = alive }
        if alive { root.setOrientation(facing, relativeTo: nil) }
        guard !isNPC, alive else { return }
        let tier = Tier(mobLevel: level, viewerLevel: viewerLevel ?? level)
        guard level != shownLevel || tier != shownTier else { return }
        shownLevel = level
        shownTier = tier
        label?.removeFromParent()
        let text = Self.text("Lv \(level) \(title)", size: isGiant ? Self.fontSize * 1.25 : Self.fontSize, color: tier.color)
        root.addChild(text)
        label = text
    }

    // MARK: - Text

    private static var meshes: [String: MeshResource] = [:]

    /// Centered text with a dark drop shadow so it reads against bright grass and sky.
    private static func text(_ string: String, size: Float, color: UIColor) -> ModelEntity {
        let key = "\(string)|\(size)"
        let mesh: MeshResource
        if let cached = meshes[key] {
            mesh = cached
        } else {
            mesh = MeshResource.generateText(string, extrusionDepth: 0.002,
                                             font: UIFont.systemFont(ofSize: CGFloat(size), weight: .bold))
            meshes[key] = mesh
        }
        let center = mesh.bounds.center
        let label = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)])
        label.position = [-center.x, -center.y, 0]
        let shadow = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: UIColor(white: 0, alpha: 1))])
        shadow.position = [size * 0.06, -size * 0.06, -0.01]
        label.addChild(shadow)
        let holder = ModelEntity()
        holder.addChild(label)
        return holder
    }
}
