import Foundation

/// Combat numbers shared by players and mobs.
public struct CombatStats: Codable, Sendable, Equatable {
    public var level: Int
    public var maxHP: Int
    public var hp: Int
    public var maxMP: Int
    public var mp: Int
    public var attack: Int
    public var defense: Int
    /// Seconds between auto-attacks.
    public var attackInterval: Float
    /// Melee reach in meters, measured edge to edge.
    public var reach: Float
    /// Chance (0...1) to block a mob's attack outright.
    public var blockChance: Float = 0
    /// Chance (0...1) that a hit lands as a critical.
    public var critChance: Float = 0.1

    public var isAlive: Bool { hp > 0 }
}

/// Tuning for one kind of mob.
public struct MobStats: Sendable {
    public let level: Int
    public let maxHP: Int
    public let attack: Int
    public let defense: Int
    public let xp: Int
    /// 0 = passive (only fights back); otherwise attacks players within this radius.
    public let aggroRadius: Float
    public let chaseSpeed: Float
    public let attackInterval: Float
    public let reach: Float
    public let respawnSeconds: Float

    var combatStats: CombatStats {
        CombatStats(level: level, maxHP: maxHP, hp: maxHP, maxMP: 0, mp: 0,
                    attack: attack, defense: defense, attackInterval: attackInterval, reach: reach)
    }
}

extension MobKind {
    public var stats: MobStats {
        switch self {
        case .snail:
            MobStats(level: 1, maxHP: 45, attack: 5, defense: 1, xp: 12, aggroRadius: 0,
                     chaseSpeed: 2.2, attackInterval: 1.8, reach: 0.5, respawnSeconds: 12)
        case .slug:
            MobStats(level: 4, maxHP: 80, attack: 10, defense: 3, xp: 30, aggroRadius: 5,
                     chaseSpeed: 2.6, attackInterval: 1.6, reach: 0.5, respawnSeconds: 15)
        case .beetle:
            MobStats(level: 8, maxHP: 160, attack: 18, defense: 6, xp: 70, aggroRadius: 7,
                     chaseSpeed: 4, attackInterval: 1.4, reach: 0.6, respawnSeconds: 18)
        case .sporeBeast:
            MobStats(level: 12, maxHP: 260, attack: 26, defense: 9, xp: 130, aggroRadius: 7,
                     chaseSpeed: 3, attackInterval: 2, reach: 0.8, respawnSeconds: 20)
        case .sporeling:
            MobStats(level: 10, maxHP: 60, attack: 16, defense: 4, xp: 25, aggroRadius: 8,
                     chaseSpeed: 4.5, attackInterval: 1.2, reach: 0.4, respawnSeconds: 0)
        case .ladybug:
            MobStats(level: 2, maxHP: 60, attack: 7, defense: 2, xp: 18, aggroRadius: 0,
                     chaseSpeed: 2.4, attackInterval: 1.7, reach: 0.5, respawnSeconds: 12)
        case .pillBug:
            MobStats(level: 5, maxHP: 110, attack: 12, defense: 5, xp: 38, aggroRadius: 4,
                     chaseSpeed: 2.6, attackInterval: 1.6, reach: 0.5, respawnSeconds: 15)
        case .acornling:
            MobStats(level: 9, maxHP: 185, attack: 20, defense: 7, xp: 85, aggroRadius: 6,
                     chaseSpeed: 3.2, attackInterval: 1.4, reach: 0.5, respawnSeconds: 18)
        case .bogFrog:
            MobStats(level: 13, maxHP: 290, attack: 29, defense: 9, xp: 150, aggroRadius: 5,
                     chaseSpeed: 3.5, attackInterval: 1.6, reach: 0.6, respawnSeconds: 20)

        // The outer ring: tougher, and most of them come looking for you (but only from close by, so
        // walking into a hunting ground doesn't pull the whole pack).
        case .fuzzbee:
            MobStats(level: 15, maxHP: 360, attack: 40, defense: 10, xp: 195, aggroRadius: 4,
                     chaseSpeed: 5, attackInterval: 1.2, reach: 0.6, respawnSeconds: 20)
        case .puffweed:
            MobStats(level: 17, maxHP: 460, attack: 44, defense: 12, xp: 235, aggroRadius: 0,
                     chaseSpeed: 2.8, attackInterval: 1.8, reach: 0.9, respawnSeconds: 22)
        case .puffling:
            MobStats(level: 15, maxHP: 90, attack: 30, defense: 6, xp: 40, aggroRadius: 8,
                     chaseSpeed: 4.5, attackInterval: 1.1, reach: 0.4, respawnSeconds: 0)
        case .mossTurtle:
            MobStats(level: 18, maxHP: 560, attack: 42, defense: 20, xp: 255, aggroRadius: 0,
                     chaseSpeed: 2.2, attackInterval: 2, reach: 0.7, respawnSeconds: 22)
        case .emberNewt:
            MobStats(level: 20, maxHP: 520, attack: 55, defense: 14, xp: 300, aggroRadius: 5,
                     chaseSpeed: 4.2, attackInterval: 1.3, reach: 0.5, respawnSeconds: 22)
        case .weaverSpider:
            MobStats(level: 22, maxHP: 600, attack: 60, defense: 16, xp: 345, aggroRadius: 6,
                     chaseSpeed: 4.4, attackInterval: 1.4, reach: 0.7, respawnSeconds: 24)
        case .duskMoth:
            MobStats(level: 23, maxHP: 580, attack: 64, defense: 15, xp: 365, aggroRadius: 5,
                     chaseSpeed: 4, attackInterval: 1.5, reach: 0.8, respawnSeconds: 24)
        case .hedgehog:
            MobStats(level: 24, maxHP: 700, attack: 66, defense: 19, xp: 390, aggroRadius: 5,
                     chaseSpeed: 3.8, attackInterval: 1.4, reach: 0.6, respawnSeconds: 24)
        case .coneKnight:
            MobStats(level: 26, maxHP: 820, attack: 72, defense: 22, xp: 440, aggroRadius: 5,
                     chaseSpeed: 3.4, attackInterval: 1.6, reach: 0.8, respawnSeconds: 25)
        case .mantis:
            MobStats(level: 27, maxHP: 800, attack: 82, defense: 20, xp: 465, aggroRadius: 7,
                     chaseSpeed: 5.2, attackInterval: 1.2, reach: 0.9, respawnSeconds: 25)
        case .thornrose:
            MobStats(level: 28, maxHP: 900, attack: 78, defense: 23, xp: 490, aggroRadius: 4,
                     chaseSpeed: 2.4, attackInterval: 1.8, reach: 1, respawnSeconds: 25)
        case .grumblecap:
            MobStats(level: 29, maxHP: 1_000, attack: 84, defense: 24, xp: 515, aggroRadius: 5,
                     chaseSpeed: 2.8, attackInterval: 1.9, reach: 1, respawnSeconds: 26)
        case .stagBeetle:
            MobStats(level: 30, maxHP: 1_150, attack: 92, defense: 26, xp: 560, aggroRadius: 6,
                     chaseSpeed: 4.5, attackInterval: 1.5, reach: 0.9, respawnSeconds: 28)

        case .mouse:
            MobStats(level: 12, maxHP: 90, attack: 20, defense: 4, xp: 30, aggroRadius: 12,
                     chaseSpeed: 5.5, attackInterval: 1, reach: 0.4, respawnSeconds: 0)
        case .owl:
            // Tuned for a geared level 15–18 player solo; a party makes it comfortable.
            MobStats(level: 16, maxHP: 3_500, attack: 38, defense: 10, xp: 1_200, aggroRadius: 14,
                     chaseSpeed: 5, attackInterval: 1.6, reach: 1.2, respawnSeconds: 0)
        }
    }
}

/// Player levelling curve and growth.
public enum Progression {
    public static let maxLevel = 30

    public static func xpToNextLevel(_ level: Int) -> Int {
        Int((40 * pow(Double(level), 1.8)).rounded())
    }

    /// Stats for a player at `level` with `playerClass`, wearing gear worth `bonus` and wielding `weapon`, fully healed.
    public static func playerStats(level: Int, bonus: StatBonus = StatBonus(), playerClass: PlayerClass? = nil,
                                   weapon: WeaponType? = nil) -> CombatStats {
        let l = Float(level - 1)
        let job = playerClass?.definition
        func scaled(_ base: Float, _ scale: Float?) -> Int { Int((base * (scale ?? 1)).rounded()) }
        let maxHP = scaled(90 + 14 * l, job?.hpScale) + bonus.maxHP
        let maxMP = scaled(40 + 6 * l, job?.mpScale) + bonus.maxMP
        return CombatStats(level: level, maxHP: maxHP, hp: maxHP, maxMP: maxMP, mp: maxMP,
                           attack: scaled(9 + 3 * l, job?.attackScale) + bonus.attack,
                           defense: scaled(2 + l, job?.defenseScale) + bonus.defense,
                           attackInterval: (weapon?.attackInterval ?? 0.9) / (1 + bonus.attackSpeed),
                           reach: reach(weapon: weapon, playerClass: playerClass),
                           blockChance: bonus.block > 0 ? bonus.block + (job?.blockBonus ?? 0) : 0,
                           critChance: 0.1 + bonus.critical)
    }

    /// Auto-attack reach: the weapon decides; bare-handed, the class does (thornshots fling thorns).
    public static func reach(weapon: WeaponType?, playerClass: PlayerClass?) -> Float {
        weapon?.reach ?? playerClass?.definition.reach ?? 0.9
    }

    /// Fighting mobs above your level pays more; farming far weaker ones pays little.
    public static func xpReward(baseXP: Int, mobLevel: Int, playerLevel: Int) -> Int {
        let diff = mobLevel - playerLevel
        let factor: Float = diff >= 0
            ? 1 + 0.1 * Float(min(diff, 5))
            : max(0.1, 1 + 0.2 * Float(diff))
        return max(1, Int((Float(baseXP) * factor).rounded()))
    }
}
