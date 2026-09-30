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
    public var critChance: Float = 0.03
    /// Skill damage multiplier (Intelligence).
    public var skillPower: Float = 1
    /// How well auto-attacks find their mark (a player's Dexterity), weighed against the target's `parry`.
    public var accuracy: Float = 15
    /// How well auto-attacks are dodged (half a player's Dexterity).
    public var parry: Float = 7.5
    /// Each auto-attack rolls between `attack × (1 - spread)` and `attack × (1 + spread)`: a weapon's
    /// min~max (axes swing wide, swords stay steady).
    public var attackSpread: Float = 0.15

    public var isAlive: Bool { hp > 0 }

    /// Flyff's hit rate: accuracy against parry, weighed by level. An even fight lands most swings;
    /// a mob far above you (or a clumsy build against a nimble target) misses a lot more.
    public static func hitChance(attacker: CombatStats, defender: CombatStats) -> Float {
        let skill = 1.6 * attacker.accuracy / max(1, attacker.accuracy + defender.parry)
        let levels = 1.2 * Float(attacker.level) / Float(max(1, attacker.level + defender.level))
        return min(0.96, max(0.2, skill * 1.5 * levels))
    }
}

/// Tuning for one kind of mob.
///
/// As in Flyff, a same-level fight is eight to fifteen slow, heavy swings (a weapon of your level is what
/// makes it that short), and a mob hits back hard enough that you sit or drink between pulls.
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
                    attack: attack, defense: defense, attackInterval: attackInterval, reach: reach,
                    accuracy: Self.accuracy(level: level), parry: Self.parry(level: level))
    }

    /// A mob's aim and dodge grow slowly with its level, so a Strength build with no Dexterity at all
    /// still lands about seven swings in ten on its own level at 30, and a Dexterity build almost all.
    static func accuracy(level: Int) -> Float { 12 + Float(level) }
    static func parry(level: Int) -> Float { 6 + 0.3 * Float(level) }
}

extension MobKind {
    public var stats: MobStats {
        switch self {
        // Snails and ladybugs never start a fight: the glade is where sprouts learn to swing.
        case .snail:
            MobStats(level: 1, maxHP: 90, attack: 6, defense: 1, xp: 24, aggroRadius: 0,
                     chaseSpeed: 2.2, attackInterval: 2.2, reach: 0.5, respawnSeconds: 12)
        case .slug:
            MobStats(level: 4, maxHP: 150, attack: 10, defense: 4, xp: 60, aggroRadius: 5,
                     chaseSpeed: 2.6, attackInterval: 2, reach: 0.5, respawnSeconds: 15)
        case .beetle:
            MobStats(level: 8, maxHP: 350, attack: 18, defense: 8, xp: 140, aggroRadius: 7,
                     chaseSpeed: 4, attackInterval: 1.8, reach: 0.6, respawnSeconds: 18)
        case .sporeBeast:
            MobStats(level: 12, maxHP: 570, attack: 25, defense: 13, xp: 260, aggroRadius: 7,
                     chaseSpeed: 3, attackInterval: 2.5, reach: 0.8, respawnSeconds: 20)
        case .sporeling:
            MobStats(level: 10, maxHP: 140, attack: 15, defense: 6, xp: 50, aggroRadius: 8,
                     chaseSpeed: 4.5, attackInterval: 1.5, reach: 0.4, respawnSeconds: 0)
        case .ladybug:
            MobStats(level: 2, maxHP: 110, attack: 7, defense: 3, xp: 36, aggroRadius: 0,
                     chaseSpeed: 2.4, attackInterval: 2.1, reach: 0.5, respawnSeconds: 12)
        case .pillBug:
            MobStats(level: 5, maxHP: 260, attack: 11, defense: 7, xp: 76, aggroRadius: 4,
                     chaseSpeed: 2.6, attackInterval: 2, reach: 0.5, respawnSeconds: 15)
        case .acornling:
            MobStats(level: 9, maxHP: 430, attack: 20, defense: 10, xp: 170, aggroRadius: 6,
                     chaseSpeed: 3.2, attackInterval: 1.8, reach: 0.5, respawnSeconds: 18)
        // Filling the gaps, so every couple of levels brings a new field to hunt (as in Flaris).
        case .aphid:
            MobStats(level: 3, maxHP: 130, attack: 8, defense: 3, xp: 48, aggroRadius: 0,
                     chaseSpeed: 2.6, attackInterval: 2, reach: 0.5, respawnSeconds: 12)
        case .earthworm:
            MobStats(level: 6, maxHP: 290, attack: 14, defense: 7, xp: 100, aggroRadius: 4,
                     chaseSpeed: 2.4, attackInterval: 2.1, reach: 0.6, respawnSeconds: 16)
        case .cricket:
            MobStats(level: 11, maxHP: 500, attack: 22, defense: 11, xp: 215, aggroRadius: 6,
                     chaseSpeed: 4.2, attackInterval: 1.6, reach: 0.6, respawnSeconds: 19)
        case .bogFrog:
            MobStats(level: 13, maxHP: 630, attack: 28, defense: 13, xp: 300, aggroRadius: 5,
                     chaseSpeed: 3.5, attackInterval: 2, reach: 0.6, respawnSeconds: 20)

        // The outer ring: tougher, and their aggressive ones come looking for you (but only from close by,
        // so walking into a hunting ground doesn't pull the whole pack).
        case .fuzzbee:
            MobStats(level: 15, maxHP: 860, attack: 34, defense: 14, xp: 390, aggroRadius: 4,
                     chaseSpeed: 5, attackInterval: 1.5, reach: 0.6, respawnSeconds: 20)
        case .puffweed:
            MobStats(level: 17, maxHP: 1_070, attack: 36, defense: 17, xp: 470, aggroRadius: 4,
                     chaseSpeed: 2.8, attackInterval: 2.2, reach: 0.9, respawnSeconds: 22)
        case .puffling:
            MobStats(level: 15, maxHP: 220, attack: 25, defense: 8, xp: 80, aggroRadius: 8,
                     chaseSpeed: 4.5, attackInterval: 1.4, reach: 0.4, respawnSeconds: 0)
        case .mossTurtle:
            MobStats(level: 18, maxHP: 1_260, attack: 35, defense: 28, xp: 510, aggroRadius: 4,
                     chaseSpeed: 2.2, attackInterval: 2.5, reach: 0.7, respawnSeconds: 22)
        case .emberNewt:
            MobStats(level: 20, maxHP: 1_250, attack: 46, defense: 20, xp: 600, aggroRadius: 5,
                     chaseSpeed: 4.2, attackInterval: 1.6, reach: 0.5, respawnSeconds: 22)
        case .weaverSpider:
            MobStats(level: 22, maxHP: 1_420, attack: 50, defense: 22, xp: 690, aggroRadius: 6,
                     chaseSpeed: 4.4, attackInterval: 1.8, reach: 0.7, respawnSeconds: 24)
        case .duskMoth:
            MobStats(level: 23, maxHP: 1_360, attack: 53, defense: 21, xp: 730, aggroRadius: 5,
                     chaseSpeed: 4, attackInterval: 1.9, reach: 0.8, respawnSeconds: 24)
        case .hedgehog:
            MobStats(level: 24, maxHP: 1_610, attack: 56, defense: 27, xp: 780, aggroRadius: 5,
                     chaseSpeed: 3.8, attackInterval: 1.8, reach: 0.6, respawnSeconds: 24)
        case .coneKnight:
            MobStats(level: 26, maxHP: 1_930, attack: 60, defense: 31, xp: 880, aggroRadius: 5,
                     chaseSpeed: 3.4, attackInterval: 2, reach: 0.8, respawnSeconds: 25)
        case .mantis:
            MobStats(level: 27, maxHP: 1_870, attack: 69, defense: 28, xp: 930, aggroRadius: 7,
                     chaseSpeed: 5.2, attackInterval: 1.5, reach: 0.9, respawnSeconds: 25)
        case .thornrose:
            MobStats(level: 28, maxHP: 2_090, attack: 66, defense: 32, xp: 980, aggroRadius: 4,
                     chaseSpeed: 2.4, attackInterval: 2.2, reach: 1, respawnSeconds: 25)
        case .grumblecap:
            MobStats(level: 29, maxHP: 2_300, attack: 70, defense: 34, xp: 1_030, aggroRadius: 5,
                     chaseSpeed: 2.8, attackInterval: 2.4, reach: 1, respawnSeconds: 26)
        case .stagBeetle:
            MobStats(level: 30, maxHP: 2_630, attack: 77, defense: 36, xp: 1_120, aggroRadius: 6,
                     chaseSpeed: 4.5, attackInterval: 1.9, reach: 0.9, respawnSeconds: 28)

        case .mouse:
            MobStats(level: 12, maxHP: 200, attack: 20, defense: 6, xp: 60, aggroRadius: 12,
                     chaseSpeed: 5.5, attackInterval: 1.2, reach: 0.4, respawnSeconds: 0)
        case .owl:
            // A long fight for a geared level 15–18 player solo; a party makes it comfortable.
            MobStats(level: 16, maxHP: 5_670, attack: 40, defense: 14, xp: 2_400, aggroRadius: 14,
                     chaseSpeed: 5, attackInterval: 2, reach: 1.2, respawnSeconds: 0)

        // The Sunken Warren: the Hollow's dungeon, for the level cap and a little past it.
        case .delverMole:
            MobStats(level: 28, maxHP: 2_190, attack: 67, defense: 34, xp: 990, aggroRadius: 5,
                     chaseSpeed: 3.4, attackInterval: 1.9, reach: 0.7, respawnSeconds: 22)
        case .rootcrawler:
            MobStats(level: 30, maxHP: 2_510, attack: 76, defense: 35, xp: 1_100, aggroRadius: 6,
                     chaseSpeed: 4.8, attackInterval: 1.6, reach: 0.8, respawnSeconds: 24)
        case .moldywarp:
            // A field boss: always home, back ten minutes after it falls. A long fight for a geared level 30.
            MobStats(level: 32, maxHP: 18_070, attack: 78, defense: 36, xp: 9_000, aggroRadius: 9,
                     chaseSpeed: 3.8, attackInterval: 2.2, reach: 1.2, respawnSeconds: 600)
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

    /// Stats for a player at `level` with `playerClass`, wearing gear worth `bonus` (the weapon's share of
    /// its attack is `weaponAttack`), wielding `weapon`, and with stat points spent as in `attributes`,
    /// fully healed. As in Flyff, levels alone add little: the weapon is most of your damage, and where
    /// the points go decides the build (Strength hits harder with blades, Dexterity swings faster, lands
    /// more hits and crits, and powers bows, Stamina holds the line, Intelligence feeds wands and skills).
    public static func playerStats(level: Int, bonus: StatBonus = StatBonus(), playerClass: PlayerClass? = nil,
                                   weapon: WeaponType? = nil, weaponAttack: Int = 0,
                                   attributes: Attributes = Attributes()) -> CombatStats {
        let l = Float(level - 1)
        let job = playerClass?.definition
        func scaled(_ base: Float, _ scale: Float?) -> Int { Int((base * (scale ?? 1)).rounded()) }
        // Points above the starting 15, from stat points and gear alike.
        let points = attributes + bonus.attributes
        let sta = Float(points.stamina), dex = Float(points.dexterity), int = Float(points.intelligence)
        let dexterity = Float(Attributes.base) + dex
        let power = Float(points[weapon?.attribute ?? .strength])
        let maxHP = scaled(90 + 9 * l, job?.hpScale) + points.stamina * Attributes.hpPerStamina + bonus.maxHP
        let maxMP = scaled(40 + 3.5 * l, job?.mpScale) + points.intelligence * Attributes.mpPerIntelligence + bonus.maxMP
        let attack = scaled(3 + 0.8 * l, job?.attackScale) + Int((power * Attributes.attackPerPoint).rounded()) + bonus.attack
        let speed = min(Attributes.maxAttackSpeed,
                        1 + dex * Attributes.speedPerDexterity * (weapon?.dexterityFactor ?? 1)
                            + Float(level) * Attributes.speedPerLevel + bonus.attackSpeed)
        return CombatStats(level: level, maxHP: maxHP, hp: maxHP, maxMP: maxMP, mp: maxMP,
                           attack: attack,
                           defense: scaled(2 + 0.6 * l, job?.defenseScale) + Int((sta * Attributes.defensePerStamina).rounded()) + bonus.defense,
                           attackInterval: (weapon?.attackInterval ?? WeaponType.unarmedInterval) / speed,
                           reach: reach(weapon: weapon, playerClass: playerClass),
                           blockChance: bonus.block > 0 ? bonus.block + (job?.blockBonus ?? 0) : 0,
                           critChance: Attributes.baseCritical + dexterity * Attributes.criticalPerDexterity + bonus.critical,
                           skillPower: 1 + int * Attributes.skillPowerPerIntelligence,
                           accuracy: dexterity,
                           parry: dexterity * Attributes.parryPerDexterity,
                           // Only the weapon's share of the attack swings between its min and max.
                           attackSpread: (weapon?.spread ?? 0) * Float(weaponAttack) / Float(max(1, attack)) + 0.03)
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
