/// Flyff's four character stats. Every sprout starts with `Attributes.base` in each and earns
/// `Attributes.pointsPerLevel` points to spend on every level up.
public enum Attribute: String, Codable, Sendable, CaseIterable {
    /// Hits harder with swords, axes, and mauls.
    case strength
    /// More health and tougher skin.
    case stamina
    /// Swings faster, lands more hits and criticals, dodges more, and draws a bow harder.
    case dexterity
    /// More mana, stronger skills, and harder-hitting wands and staves.
    case intelligence

    public var name: String {
        switch self {
        case .strength: "Strength"
        case .stamina: "Stamina"
        case .dexterity: "Dexterity"
        case .intelligence: "Intelligence"
        }
    }

    /// "STR".
    public var abbreviation: String {
        switch self {
        case .strength: "STR"
        case .stamina: "STA"
        case .dexterity: "DEX"
        case .intelligence: "INT"
        }
    }
}

/// Points a player has put into each attribute, on top of `base`. Unspent points are whatever the
/// level has earned minus what's been spent, so they can never drift out of sync.
public struct Attributes: Codable, Sendable, Equatable {
    public var strength = 0
    public var stamina = 0
    public var dexterity = 0
    public var intelligence = 0

    public static let base = 15
    public static let pointsPerLevel = 3

    // What each point is worth (see `Progression.playerStats`).
    /// Attack per point of the weapon's own stat (`WeaponType.attribute`: Strength for blades, Dexterity
    /// for bows, Intelligence for wands and staves; bare hands use Strength).
    public static let attackPerPoint: Float = 1.25
    public static let hpPerStamina = 7
    public static let defensePerStamina: Float = 0.5
    /// Attack speed per Dexterity point, scaled by the weapon (`WeaponType.dexterityFactor`): about 90 points
    /// swing a sword twice as fast.
    public static let speedPerDexterity: Float = 0.012
    /// Levels add a sliver of speed too (Flyff's level / 8).
    public static let speedPerLevel: Float = 0.004
    /// Speed, set bonuses included, tops out here.
    public static let maxAttackSpeed: Float = 2.5
    public static let baseCritical: Float = 0.01
    /// Per point of Dexterity (the full value, base included).
    public static let criticalPerDexterity: Float = 0.0015
    /// Parry (dodging mob swings) per point of Dexterity (the full value).
    public static let parryPerDexterity: Float = 0.5
    public static let mpPerIntelligence = 4
    public static let skillPowerPerIntelligence: Float = 0.015

    public init(strength: Int = 0, stamina: Int = 0, dexterity: Int = 0, intelligence: Int = 0) {
        self.strength = strength
        self.stamina = stamina
        self.dexterity = dexterity
        self.intelligence = intelligence
    }

    public subscript(attribute: Attribute) -> Int {
        get {
            switch attribute {
            case .strength: strength
            case .stamina: stamina
            case .dexterity: dexterity
            case .intelligence: intelligence
            }
        }
        set {
            switch attribute {
            case .strength: strength = newValue
            case .stamina: stamina = newValue
            case .dexterity: dexterity = newValue
            case .intelligence: intelligence = newValue
            }
        }
    }

    /// The number shown on the stat screen: `base` plus the points spent.
    public func value(_ attribute: Attribute) -> Int { Self.base + self[attribute] }

    public var spent: Int { strength + stamina + dexterity + intelligence }

    public var isValid: Bool { Attribute.allCases.allSatisfy { self[$0] >= 0 } }

    /// Every level after the first earns points.
    public static func earned(atLevel level: Int) -> Int { max(0, level - 1) * pointsPerLevel }

    public func unspent(atLevel level: Int) -> Int { max(0, Self.earned(atLevel: level) - spent) }

    public static func + (a: Attributes, b: Attributes) -> Attributes {
        Attributes(strength: a.strength + b.strength, stamina: a.stamina + b.stamina,
                   dexterity: a.dexterity + b.dexterity, intelligence: a.intelligence + b.intelligence)
    }
}

extension GameSimulation {
    /// Spends stat points: `points` says how many go into each attribute (the stat screen collects a
    /// few, then confirms them all at once). Points can't be taken back.
    mutating func spendStatPoints(_ points: Attributes, player: inout WorldEntity) -> ActionFailure? {
        guard var data = player.player else { return .notAvailable }
        guard points.isValid, points.spent > 0 else { return .notAvailable }
        guard points.spent <= data.attributes.unspent(atLevel: player.stats.level) else { return .noStatPoints }
        data.attributes = data.attributes + points
        player.player = data
        refreshStats(&player)
        events.append(.attributesChanged(player: player.id))
        return nil
    }
}
