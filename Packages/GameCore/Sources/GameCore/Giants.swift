/// Flyff-style Giants: every hunting field keeps one huge specimen of its species on top of the
/// regular pack. It never starts a fight, but it hits hard, takes a long time to bring down, and
/// comes back only every few minutes. The reward is a big pile of XP and caps plus a guaranteed
/// piece of gear.
public enum Giant {
    /// Seconds before a slain Giant returns.
    public static let respawnSeconds: Float = 300
    /// How much bigger it is than the regular kind, for collisions (and the client's model).
    public static let sizeScale: Float = 1.8
    /// Shown (and fought) this many levels above its kind.
    public static let levelBonus = 2
    static let hpMultiplier = 6
    static let attackMultiplier: Float = 1.4
    static let defenseMultiplier: Float = 1.3
    static let xpMultiplier = 6
    /// Caps piles are this many times the regular kind's (and always drop).
    static let capsMultiplier = 6
    /// Rolls on the regular drop table (plus one guaranteed piece of gear).
    static let lootRolls = 3
    /// Class set pieces are this many times likelier.
    static let classSetMultiplier: Float = 10

    static func stats(for kind: MobKind) -> CombatStats {
        var stats = kind.stats.combatStats
        stats.level += levelBonus
        stats.maxHP *= hpMultiplier
        stats.hp = stats.maxHP
        stats.attack = Int((Float(stats.attack) * attackMultiplier).rounded())
        stats.defense = Int((Float(stats.defense) * defenseMultiplier).rounded())
        return stats
    }
}

extension MobKind {
    /// Species with a hunting field of their own get a Giant (not summons or the world boss).
    public var hasGiant: Bool {
        switch self {
        case .sporeling, .puffling, .mouse, .owl, .moldywarp: false
        default: true
        }
    }

    /// A boss that lives in its lair all the time and respawns on a timer (unlike the night's owl).
    public var isFieldBoss: Bool { self == .moldywarp }

    /// "Giant Snail".
    public func displayName(giant: Bool) -> String {
        giant ? "Giant \(displayName)" : displayName
    }
}
