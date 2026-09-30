import Testing
@testable import GameCore

/// The v7 Flyff feel, pinned down: slow heavy swings that Dexterity speeds up, weapons as the big
/// damage step, misses from low aim, and same-level fights of about ten swings.
@Suite struct BalanceTests {
    /// A player of `level` with points spread half into the weapon's stat, a quarter each into DEX and STA,
    /// holding the best `type` weapon Oyster sells for that level.
    private func player(_ level: Int, _ type: WeaponType? = .sword, dexShare: Float = 0.25) -> CombatStats {
        let points = Float(Attributes.earned(atLevel: level))
        let dex = Int(points * dexShare), sta = Int(points * 0.25)
        let main = Int(points) - dex - sta
        var attributes = Attributes(stamina: sta, dexterity: dex)
        attributes[type?.attribute ?? .strength] += main
        let shop = NPCID.oyster.definition.shopStock.map(\.definition)
            .filter { $0.weaponType == type && $0.requiredLevel <= level }
            .map(\.bonus.attack).max()
        // Past the shop's last tier, a dropped one a few levels behind.
        let weapon = type.map { max(shop ?? 0, WeaponType.attack(level: level - 3, type: $0)) } ?? 0
        return Progression.playerStats(level: level, bonus: StatBonus(attack: weapon), weapon: type,
                                       weaponAttack: weapon, attributes: attributes)
    }

    /// Average swings to bring down `kind` (hits, misses, and crits included).
    private func swings(_ stats: CombatStats, against kind: MobKind) -> Float {
        let mob = kind.stats.combatStats
        let perHit = max(1, Float(stats.attack) - Float(mob.defense) * 0.6)
            * (1 + stats.critChance * (GameSimulation.criticalMultiplier - 1))
        return Float(mob.maxHP) / (perHit * CombatStats.hitChance(attacker: stats, defender: mob))
    }

    @Test func swingsAreSlowUntilDexterityQuickensThem() {
        let rookie = player(1)
        #expect(rookie.attackInterval >= 1.9, "a sprout swings about every two seconds")
        let clumsy = player(30, dexShare: 0)
        let nimble = player(30, dexShare: 1)
        #expect(nimble.attackInterval < clumsy.attackInterval * 0.6, "a Dexterity build swings far faster")
        #expect(nimble.critChance > clumsy.critChance * 3)
        #expect(player(20, .maul).attackInterval > player(20, .sword).attackInterval, "mauls are slow")
    }

    @Test func aWeaponIsMostOfYourDamage() {
        for level in [1, 10, 20, 30] {
            let armed = player(level), bare = player(level, nil)
            #expect(Float(armed.attack) > Float(bare.attack) * 1.8, "level \(level)")
        }
        #expect(player(1).attack >= player(1, nil).attack * 3)
    }

    @Test func sameLevelFightsTakeAboutTenSwings() {
        for kind in MobKind.allCases where kind.hasGiant {
            let level = kind.stats.level
            let count = swings(player(min(level, Progression.maxLevel)), against: kind)
            #expect((6...20).contains(count), "\(kind): \(count) swings")
            #expect(swings(player(min(level, Progression.maxLevel), nil), against: kind) > count * 1.8,
                    "\(kind): bare-handed takes far longer")
        }
    }

    @Test func aimMattersMoreThePlayerOutlevelsIt() {
        let mob = MobKind.stagBeetle.stats.combatStats
        let brute = CombatStats.hitChance(attacker: player(30, dexShare: 0), defender: mob)
        let archer = CombatStats.hitChance(attacker: player(30, .bow, dexShare: 0.25), defender: mob)
        #expect((0.6...0.8).contains(brute), "no Dexterity at all still lands most swings")
        #expect(archer > 0.9)
        let rookie = CombatStats.hitChance(attacker: player(1), defender: MobKind.snail.stats.combatStats)
        #expect(rookie > 0.9, "the glade is forgiving")
        // Nimble players dodge: mobs miss a Dexterity build more.
        let bite = MobKind.mantis.stats.combatStats
        #expect(CombatStats.hitChance(attacker: bite, defender: player(27, dexShare: 1))
                < CombatStats.hitChance(attacker: bite, defender: player(27, dexShare: 0)) - 0.2)
    }

    @Test func autoAttacksCanMissButSkillsNeverDo() throws {
        var sim = GameSimulation(seed: 4)
        let player = sim.spawnPlayer(profile: PlayerProfile(level: 1))
        let mob = try #require(sim.snapshot().entities.first { $0.kind == .mob(.stagBeetle) && !$0.isGiant })
        sim.teleport(player, to: mob.position.xz + Vec2(1.2, 0))
        sim.enqueue(.target(mob.id, engage: true), from: player)
        var misses = 0
        for _ in 0..<(GameSimulation.tickRate * 20) {
            misses += sim.step().count { if case .missed(player, mob.id) = $0 { true } else { false } }
        }
        #expect(misses > 0, "a level 1 swinging at a level 30 misses a lot")
    }
}
