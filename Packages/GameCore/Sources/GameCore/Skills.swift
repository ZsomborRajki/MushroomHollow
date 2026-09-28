public enum SkillID: String, Codable, Sendable, CaseIterable {
    case capBash
    case sporeBurst
    case dewdrop
}

public enum SkillFailure: String, Codable, Sendable {
    case locked
    case cooldown
    case notEnoughMana
    case noTarget
}

public struct SkillDefinition: Sendable {
    public enum Effect: Sendable {
        /// One hit on the target at `multiplier` x attack.
        case strike(multiplier: Float)
        /// Hits every living mob within `radius` of the caster.
        case burst(radius: Float, multiplier: Float)
        /// Heals the caster for a fraction of max HP.
        case heal(fraction: Float)
    }

    public let id: SkillID
    public let name: String
    public let requiredLevel: Int
    public let manaCost: Int
    /// Seconds.
    public let cooldown: Float
    public let effect: Effect

    public var needsTarget: Bool {
        if case .strike = effect { return true }
        return false
    }

    /// Edge-to-edge distance a targeted skill needs; the player walks into range first.
    public var range: Float { 1.0 }
}

extension SkillID {
    public var definition: SkillDefinition {
        switch self {
        case .capBash:
            SkillDefinition(id: self, name: "Cap Bash", requiredLevel: 1, manaCost: 8, cooldown: 5,
                            effect: .strike(multiplier: 2.2))
        case .sporeBurst:
            SkillDefinition(id: self, name: "Spore Burst", requiredLevel: 3, manaCost: 14, cooldown: 9,
                            effect: .burst(radius: 3.5, multiplier: 1.4))
        case .dewdrop:
            SkillDefinition(id: self, name: "Dewdrop", requiredLevel: 5, manaCost: 12, cooldown: 12,
                            effect: .heal(fraction: 0.35))
        }
    }
}
