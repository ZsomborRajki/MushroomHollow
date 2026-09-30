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
        case .ladybug: 0.9
        case .pillBug: 0.8
        case .acornling: 1.3
        case .bogFrog: 1.1
        case .aphid: 0.9
        case .earthworm: 0.8
        case .cricket: 1.1
        case .fuzzbee: 1.8
        case .puffweed: 2.2
        case .puffling: 1.3
        case .mossTurtle: 1.5
        case .emberNewt: 0.9
        case .weaverSpider: 1.3
        case .duskMoth: 2.0
        case .hedgehog: 1.2
        case .coneKnight: 2.0
        case .mantis: 1.8
        case .thornrose: 2.3
        case .grumblecap: 2.3
        case .stagBeetle: 1.4
        case .delverMole: 1.3
        case .rootcrawler: 0.9
        case .moldywarp: 3.5
        case .mouse: 0.9
        case .owl: 6.8
        }
    }

    /// Flies (in looks only: the sim keeps every mob on the ground) and bobs in the air.
    var hovers: Bool {
        switch self {
        case .fuzzbee, .duskMoth, .puffling: true
        default: false
        }
    }

    /// Wing beats, in radians per second: a blur for bees, a flutter for moths.
    var flapRate: Float {
        switch self {
        case .fuzzbee: 45
        case .duskMoth: 9
        default: 0
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

    /// A boss's full title, for banners and the boss bar.
    var bossTitle: String {
        self == .mob(.moldywarp) ? "Moldywarp, the Warren King" : displayName
    }

    var displayName: String {
        switch self {
        case .player: "Sprout"
        case let .mob(kind): kind.displayName
        case let .npc(id): id.definition.name
        }
    }
}

extension EntitySnapshot {
    /// "Giant Slug" for Giants.
    var displayName: String {
        if case let .mob(kind) = kind { return kind.displayName(giant: isGiant) }
        return kind.displayName
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
