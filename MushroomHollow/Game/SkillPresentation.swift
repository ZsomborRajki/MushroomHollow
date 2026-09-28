import GameCore
import SwiftUI
import UIKit

/// Client-only look of each skill (the sim only knows numbers).
extension SkillID {
    var symbol: String {
        switch self {
        case .capBash: "hammer.fill"
        case .sporeBurst: "aqi.medium"
        case .dewdrop: "drop.fill"
        case .barkSkin: "shield.lefthalf.filled"
        case .capSlam: "burst.fill"
        case .thornVolley: "arrow.up.right.and.arrow.down.left"
        case .pinningShot: "scope"
        case .sporeNova: "sparkles"
        case .myceliumSurge: "point.3.filled.connected.trianglepath.dotted"
        case .morningDew: "sun.horizon.fill"
        case .rainBlessing: "cloud.rain.fill"
        }
    }

    var tint: Color { Color(uiColor: effectColor) }

    var effectColor: UIColor {
        switch self {
        case .capBash: UIColor(red: 1.0, green: 0.55, blue: 0.2, alpha: 1)
        case .sporeBurst: UIColor(red: 0.55, green: 0.95, blue: 0.35, alpha: 1)
        case .dewdrop: UIColor(red: 0.45, green: 0.8, blue: 1.0, alpha: 1)
        case .barkSkin, .capSlam: UIColor(red: 0.95, green: 0.7, blue: 0.35, alpha: 1)
        case .thornVolley, .pinningShot: UIColor(red: 0.55, green: 0.9, blue: 0.4, alpha: 1)
        case .sporeNova, .myceliumSurge: UIColor(red: 0.8, green: 0.5, blue: 1.0, alpha: 1)
        case .morningDew, .rainBlessing: UIColor(red: 0.5, green: 0.9, blue: 1.0, alpha: 1)
        }
    }
}

extension SkillFailure {
    func message(for skill: SkillID) -> String {
        switch self {
        case .locked: "\(skill.definition.name) unlocks at Lv \(skill.definition.requiredLevel)"
        case .cooldown: "\(skill.definition.name) isn't ready"
        case .notEnoughMana: "Not enough MP"
        case .noTarget: "No target"
        case .airborne: "Land first to fight"
        }
    }
}

extension MobKind {
    /// Rough height for placing damage numbers and effects above the model.
    var headHeight: Float {
        switch self {
        case .snail: 1.0
        case .slug: 0.8
        case .beetle: 1.1
        case .sporeBeast: 2.0
        case .sporeling: 0.9
        case .owl: 7.0
        }
    }
}

extension EntityKind {
    var headHeight: Float {
        switch self {
        case .player: 1.9
        case let .mob(kind): kind.headHeight
        case .npc: 2.1
        }
    }

    var displayName: String {
        switch self {
        case .player: "Sprout"
        case let .mob(kind): kind.displayName
        case let .npc(id): id.definition.name
        }
    }
}

extension PlayerClass {
    var symbol: String {
        switch self {
        case .guardian: "shield.fill"
        case .thornshot: "arrow.up.forward"
        case .sporecaster: "sparkles"
        case .dewkeeper: "leaf.fill"
        }
    }

    var tint: Color {
        switch self {
        case .guardian: .orange
        case .thornshot: .green
        case .sporecaster: .purple
        case .dewkeeper: .cyan
        }
    }
}
