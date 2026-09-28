public enum SkillID: String, Codable, Sendable, CaseIterable {
    // Everyone
    case capBash
    case sporeBurst
    case dewdrop
    // Guard
    case barkSkin, capSlam
    // Thornshot
    case thornVolley, pinningShot
    // Sporecaster
    case sporeNova, myceliumSurge
    // Dewkeeper
    case morningDew, rainBlessing

    public static let baseSkills: [SkillID] = [.capBash, .sporeBurst, .dewdrop]
}

public enum SkillFailure: String, Codable, Sendable {
    case locked
    case cooldown
    case notEnoughMana
    case noTarget
    case airborne
}

/// Temporary effects from skills.
public enum BuffEffect: Codable, Sendable, Equatable {
    case defense(multiplier: Float)
    case attack(multiplier: Float)
    /// Heals this fraction of max HP every second.
    case regen(fractionPerSecond: Float)
}

public struct SkillDefinition: Sendable {
    public enum Effect: Sendable {
        /// One hit on the target at `multiplier` x attack.
        case strike(multiplier: Float)
        /// Hits every living mob within `radius` of the caster.
        case burst(radius: Float, multiplier: Float)
        /// Hits every living mob within `radius` of the target.
        case blast(radius: Float, multiplier: Float)
        /// Hits the target, then up to `extraTargets` more mobs near it.
        case volley(multiplier: Float, extraTargets: Int, radius: Float)
        /// Heals the caster for a fraction of max HP.
        case heal(fraction: Float)
        case buff(BuffEffect, seconds: Float)
    }

    public let id: SkillID
    public let name: String
    public let requiredLevel: Int
    /// nil = anyone can learn it.
    public let playerClass: PlayerClass?
    public let manaCost: Int
    /// Seconds.
    public let cooldown: Float
    /// Edge-to-edge distance a targeted skill needs; the player walks into range first.
    public let range: Float
    public let effect: Effect

    public var needsTarget: Bool {
        switch effect {
        case .strike, .blast, .volley: true
        case .burst, .heal, .buff: false
        }
    }
}

extension SkillID {
    public var definition: SkillDefinition {
        switch self {
        case .capBash:
            skill("Cap Bash", level: 1, mana: 8, cooldown: 5, effect: .strike(multiplier: 2.2))
        case .sporeBurst:
            skill("Spore Burst", level: 3, mana: 14, cooldown: 9, effect: .burst(radius: 3.5, multiplier: 1.4))
        case .dewdrop:
            skill("Dewdrop", level: 5, mana: 12, cooldown: 12, effect: .heal(fraction: 0.35))
        case .barkSkin:
            skill("Bark Skin", level: 15, class: .guardian, mana: 15, cooldown: 25,
                  effect: .buff(.defense(multiplier: 1.6), seconds: 10))
        case .capSlam:
            skill("Cap Slam", level: 17, class: .guardian, mana: 18, cooldown: 8,
                  effect: .burst(radius: 3.2, multiplier: 1.9))
        case .thornVolley:
            skill("Thorn Volley", level: 15, class: .thornshot, mana: 14, cooldown: 7, range: 7.5,
                  effect: .volley(multiplier: 1.5, extraTargets: 2, radius: 4))
        case .pinningShot:
            skill("Pinning Shot", level: 17, class: .thornshot, mana: 20, cooldown: 11, range: 9,
                  effect: .strike(multiplier: 2.9))
        case .sporeNova:
            skill("Spore Nova", level: 15, class: .sporecaster, mana: 20, cooldown: 8, range: 7,
                  effect: .blast(radius: 3.5, multiplier: 2.0))
        case .myceliumSurge:
            skill("Mycelium Surge", level: 17, class: .sporecaster, mana: 26, cooldown: 12, range: 7,
                  effect: .strike(multiplier: 3.6))
        case .morningDew:
            skill("Morning Dew", level: 15, class: .dewkeeper, mana: 18, cooldown: 20,
                  effect: .buff(.regen(fractionPerSecond: 0.04), seconds: 10))
        case .rainBlessing:
            skill("Rain Blessing", level: 17, class: .dewkeeper, mana: 20, cooldown: 30,
                  effect: .buff(.attack(multiplier: 1.3), seconds: 15))
        }
    }

    private func skill(_ name: String, level: Int, class playerClass: PlayerClass? = nil, mana: Int,
                       cooldown: Float, range: Float = 1, effect: SkillDefinition.Effect) -> SkillDefinition {
        SkillDefinition(id: self, name: name, requiredLevel: level, playerClass: playerClass,
                        manaCost: mana, cooldown: cooldown, range: range, effect: effect)
    }
}
