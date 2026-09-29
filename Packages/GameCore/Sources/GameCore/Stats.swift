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
    /// Skill damage multiplier (Intelligence).
    public var skillPower: Float = 1

    public var isAlive: Bool { hp > 0 }
}

/// Tuning for one kind of mob.
///
/// Mobs are built to last: fights take a while (lots of health) but each hit stings less than it
/// looks, so a same-level fight stays winnable and the long ones are what potions are for.
public struct MobStats: Sendable {
    public let level: Int
    public let maxHP: Int
    public let attack: Int
    public let defense: Int
    public let xp: Int
    /// How close a player must come before an *aggressive* one attacks. Only about one mob in five
    /// is aggressive (see `GameSimulation.aggressiveShare`); the rest only fight back. 0 = never aggressive.
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
        // Snails and ladybugs never start a fight: the glade is where sprouts learn to swing.
        case .snail:
            MobStats(level: 1, maxHP: 135, attack: 4, defense: 1, xp: 24, aggroRadius: 0,
                     chaseSpeed: 2.2, attackInterval: 1.8, reach: 0.5, respawnSeconds: 12)
        case .slug:
            MobStats(level: 4, maxHP: 240, attack: 7, defense: 3, xp: 60, aggroRadius: 5,
                     chaseSpeed: 2.6, attackInterval: 1.6, reach: 0.5, respawnSeconds: 15)
        case .beetle:
            MobStats(level: 8, maxHP: 480, attack: 13, defense: 6, xp: 140, aggroRadius: 7,
                     chaseSpeed: 4, attackInterval: 1.4, reach: 0.6, respawnSeconds: 18)
        case .sporeBeast:
            MobStats(level: 12, maxHP: 780, attack: 18, defense: 9, xp: 260, aggroRadius: 7,
                     chaseSpeed: 3, attackInterval: 2, reach: 0.8, respawnSeconds: 20)
        case .sporeling:
            MobStats(level: 10, maxHP: 180, attack: 11, defense: 4, xp: 50, aggroRadius: 8,
                     chaseSpeed: 4.5, attackInterval: 1.2, reach: 0.4, respawnSeconds: 0)
        case .ladybug:
            MobStats(level: 2, maxHP: 180, attack: 5, defense: 2, xp: 36, aggroRadius: 0,
                     chaseSpeed: 2.4, attackInterval: 1.7, reach: 0.5, respawnSeconds: 12)
        case .pillBug:
            MobStats(level: 5, maxHP: 330, attack: 8, defense: 5, xp: 76, aggroRadius: 4,
                     chaseSpeed: 2.6, attackInterval: 1.6, reach: 0.5, respawnSeconds: 15)
        case .acornling:
            MobStats(level: 9, maxHP: 555, attack: 14, defense: 7, xp: 170, aggroRadius: 6,
                     chaseSpeed: 3.2, attackInterval: 1.4, reach: 0.5, respawnSeconds: 18)
        // Filling the gaps, so every couple of levels brings a new field to hunt (as in Flaris).
        case .aphid:
            MobStats(level: 3, maxHP: 210, attack: 6, defense: 2, xp: 48, aggroRadius: 0,
                     chaseSpeed: 2.6, attackInterval: 1.6, reach: 0.5, respawnSeconds: 12)
        case .earthworm:
            MobStats(level: 6, maxHP: 390, attack: 10, defense: 5, xp: 100, aggroRadius: 4,
                     chaseSpeed: 2.4, attackInterval: 1.7, reach: 0.6, respawnSeconds: 16)
        case .cricket:
            MobStats(level: 11, maxHP: 660, attack: 16, defense: 8, xp: 215, aggroRadius: 6,
                     chaseSpeed: 4.2, attackInterval: 1.3, reach: 0.6, respawnSeconds: 19)
        case .bogFrog:
            MobStats(level: 13, maxHP: 870, attack: 20, defense: 9, xp: 300, aggroRadius: 5,
                     chaseSpeed: 3.5, attackInterval: 1.6, reach: 0.6, respawnSeconds: 20)

        // The outer ring: tougher, and their aggressive ones come looking for you (but only from close by,
        // so walking into a hunting ground doesn't pull the whole pack).
        case .fuzzbee:
            MobStats(level: 15, maxHP: 1_080, attack: 24, defense: 10, xp: 390, aggroRadius: 4,
                     chaseSpeed: 5, attackInterval: 1.2, reach: 0.6, respawnSeconds: 20)
        case .puffweed:
            MobStats(level: 17, maxHP: 1_380, attack: 26, defense: 12, xp: 470, aggroRadius: 4,
                     chaseSpeed: 2.8, attackInterval: 1.8, reach: 0.9, respawnSeconds: 22)
        case .puffling:
            MobStats(level: 15, maxHP: 270, attack: 18, defense: 6, xp: 80, aggroRadius: 8,
                     chaseSpeed: 4.5, attackInterval: 1.1, reach: 0.4, respawnSeconds: 0)
        case .mossTurtle:
            MobStats(level: 18, maxHP: 1_680, attack: 25, defense: 20, xp: 510, aggroRadius: 4,
                     chaseSpeed: 2.2, attackInterval: 2, reach: 0.7, respawnSeconds: 22)
        case .emberNewt:
            MobStats(level: 20, maxHP: 1_560, attack: 33, defense: 14, xp: 600, aggroRadius: 5,
                     chaseSpeed: 4.2, attackInterval: 1.3, reach: 0.5, respawnSeconds: 22)
        case .weaverSpider:
            MobStats(level: 22, maxHP: 1_800, attack: 36, defense: 16, xp: 690, aggroRadius: 6,
                     chaseSpeed: 4.4, attackInterval: 1.4, reach: 0.7, respawnSeconds: 24)
        case .duskMoth:
            MobStats(level: 23, maxHP: 1_740, attack: 38, defense: 15, xp: 730, aggroRadius: 5,
                     chaseSpeed: 4, attackInterval: 1.5, reach: 0.8, respawnSeconds: 24)
        case .hedgehog:
            MobStats(level: 24, maxHP: 2_100, attack: 40, defense: 19, xp: 780, aggroRadius: 5,
                     chaseSpeed: 3.8, attackInterval: 1.4, reach: 0.6, respawnSeconds: 24)
        case .coneKnight:
            MobStats(level: 26, maxHP: 2_460, attack: 43, defense: 22, xp: 880, aggroRadius: 5,
                     chaseSpeed: 3.4, attackInterval: 1.6, reach: 0.8, respawnSeconds: 25)
        case .mantis:
            MobStats(level: 27, maxHP: 2_400, attack: 49, defense: 20, xp: 930, aggroRadius: 7,
                     chaseSpeed: 5.2, attackInterval: 1.2, reach: 0.9, respawnSeconds: 25)
        case .thornrose:
            MobStats(level: 28, maxHP: 2_700, attack: 47, defense: 23, xp: 980, aggroRadius: 4,
                     chaseSpeed: 2.4, attackInterval: 1.8, reach: 1, respawnSeconds: 25)
        case .grumblecap:
            MobStats(level: 29, maxHP: 3_000, attack: 50, defense: 24, xp: 1_030, aggroRadius: 5,
                     chaseSpeed: 2.8, attackInterval: 1.9, reach: 1, respawnSeconds: 26)
        case .stagBeetle:
            MobStats(level: 30, maxHP: 3_450, attack: 55, defense: 26, xp: 1_120, aggroRadius: 6,
                     chaseSpeed: 4.5, attackInterval: 1.5, reach: 0.9, respawnSeconds: 28)

        case .mouse:
            MobStats(level: 12, maxHP: 270, attack: 14, defense: 4, xp: 60, aggroRadius: 12,
                     chaseSpeed: 5.5, attackInterval: 1, reach: 0.4, respawnSeconds: 0)
        case .owl:
            // A long fight for a geared level 15–18 player solo; a party makes it comfortable.
            MobStats(level: 16, maxHP: 9_000, attack: 32, defense: 10, xp: 2_400, aggroRadius: 14,
                     chaseSpeed: 5, attackInterval: 1.6, reach: 1.2, respawnSeconds: 0)
        }
    }
}

/// Player levelling curve and growth.
public enum Progression {
    public static let maxLevel = 30

    /// The first fifteen levels come quickly; past the first job every level is a longer climb (the Flyff grind).
    public static func xpToNextLevel(_ level: Int) -> Int {
        let grind = 1 + 0.12 * Double(max(0, level - 15))
        return Int((40 * pow(Double(level), 1.8) * grind).rounded())
    }

    /// From this level on, fainting costs XP (as in Flyff), though never a level.
    public static let deathPenaltyLevel = 10
    public static let deathPenaltyFraction: Double = 0.04

    /// XP lost for fainting at `level` with `xp` into it.
    public static func deathPenalty(level: Int, xp: Int) -> Int {
        guard level >= deathPenaltyLevel, level < maxLevel else { return 0 }
        return min(xp, Int((Double(xpToNextLevel(level)) * deathPenaltyFraction).rounded()))
    }

    /// Stats for a player at `level` with `playerClass`, wearing gear worth `bonus`, wielding `weapon`, and with
    /// stat points spent as in `attributes`, fully healed. Levels alone add a little of everything; where the
    /// points go decides the build (a Strength glass cannon, a Stamina wall, a quick Dexterity duelist,
    /// an Intelligence skill caster).
    public static func playerStats(level: Int, bonus: StatBonus = StatBonus(), playerClass: PlayerClass? = nil,
                                   weapon: WeaponType? = nil, attributes: Attributes = Attributes()) -> CombatStats {
        let l = Float(level - 1)
        let job = playerClass?.definition
        func scaled(_ base: Float, _ scale: Float?) -> Int { Int((base * (scale ?? 1)).rounded()) }
        let str = Float(attributes.strength), sta = Float(attributes.stamina)
        let dex = Float(attributes.dexterity), int = Float(attributes.intelligence)
        let maxHP = scaled(90 + 9 * l, job?.hpScale) + attributes.stamina * Attributes.hpPerStamina + bonus.maxHP
        let maxMP = scaled(40 + 3.5 * l, job?.mpScale) + attributes.intelligence * Attributes.mpPerIntelligence + bonus.maxMP
        let attackSpeed = bonus.attackSpeed + dex * Attributes.speedPerDexterity
        return CombatStats(level: level, maxHP: maxHP, hp: maxHP, maxMP: maxMP, mp: maxMP,
                           attack: scaled(9 + 2.2 * l, job?.attackScale) + Int((str * Attributes.attackPerStrength).rounded()) + bonus.attack,
                           defense: scaled(2 + 0.6 * l, job?.defenseScale) + Int((sta * Attributes.defensePerStamina).rounded()) + bonus.defense,
                           attackInterval: (weapon?.attackInterval ?? 0.9) / (1 + attackSpeed),
                           reach: reach(weapon: weapon, playerClass: playerClass),
                           blockChance: bonus.block > 0 ? bonus.block + (job?.blockBonus ?? 0) : 0,
                           critChance: 0.1 + bonus.critical + dex * Attributes.criticalPerDexterity,
                           skillPower: 1 + int * Attributes.skillPowerPerIntelligence)
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
