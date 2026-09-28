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
        case .owl:
            MobStats(level: 30, maxHP: 20_000, attack: 90, defense: 30, xp: 8_000, aggroRadius: 14,
                     chaseSpeed: 5, attackInterval: 2.2, reach: 2, respawnSeconds: 1_800)
        }
    }
}

/// Player levelling curve and growth.
public enum Progression {
    public static let maxLevel = 15

    public static func xpToNextLevel(_ level: Int) -> Int {
        Int((40 * pow(Double(level), 1.8)).rounded())
    }

    /// Stats for a player at `level` wearing gear worth `bonus`, fully healed.
    public static func playerStats(level: Int, bonus: StatBonus = StatBonus()) -> CombatStats {
        let l = level - 1
        let maxHP = 90 + 14 * l + bonus.maxHP
        let maxMP = 40 + 6 * l + bonus.maxMP
        return CombatStats(level: level, maxHP: maxHP, hp: maxHP, maxMP: maxMP, mp: maxMP,
                           attack: 9 + 3 * l + bonus.attack, defense: 2 + l + bonus.defense,
                           attackInterval: 0.9, reach: 0.9)
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
