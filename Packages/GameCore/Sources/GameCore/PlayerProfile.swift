/// Everything about a character that persists between sessions. Offline it's saved on
/// device (SwiftData); online the server will store the same Codable value.
public struct PlayerProfile: Codable, Sendable, Equatable {
    public var level: Int
    public var xp: Int
    public var hp: Int?
    public var mp: Int?
    public var caps: Int
    public var inventory: Inventory
    /// Older saves stored bare `ItemID`s here; `Gear` decodes those as +0.
    public var equipment: [EquipSlot: Gear]
    public var activeQuests: [QuestID: Int]
    public var completedQuests: Set<QuestID>
    public var position: Vec2?
    /// Optional so saves from before classes existed still load.
    public var playerClass: PlayerClass?
    /// Optional so saves from before pets existed still load.
    public var pet: PetProfile?
    /// Stat points spent. nil in saves from before stats existed: every earned point is waiting to be spent.
    public var attributes: Attributes?

    public init(level: Int = 1, xp: Int = 0, hp: Int? = nil, mp: Int? = nil, caps: Int = 0,
                inventory: Inventory = Inventory(), equipment: [EquipSlot: Gear] = [:],
                activeQuests: [QuestID: Int] = [:], completedQuests: Set<QuestID> = [], position: Vec2? = nil,
                playerClass: PlayerClass? = nil, pet: PetProfile? = nil, attributes: Attributes? = nil) {
        self.level = level
        self.xp = xp
        self.hp = hp
        self.mp = mp
        self.caps = caps
        self.inventory = inventory
        self.equipment = equipment
        self.activeQuests = activeQuests
        self.completedQuests = completedQuests
        self.position = position
        self.playerClass = playerClass
        self.pet = pet
        self.attributes = attributes
    }

    /// A brand-new sprout, as in Flyff: a wooden (twig) sword in hand, a little pocket money, and a few potions.
    public static var newCharacter: PlayerProfile {
        var inventory = Inventory()
        inventory.add(.dewPotion, count: 3)
        return PlayerProfile(caps: 20, inventory: inventory, equipment: [.weapon: Gear(.twigSword)])
    }
}

extension GameSimulation {
    /// Spawns a player from a saved profile (or a new character).
    @discardableResult
    public mutating func spawnPlayer(profile: PlayerProfile = .newCharacter) -> EntityID {
        let id = makeID()
        let level = min(max(1, profile.level), Progression.maxLevel)
        var data = PlayerData()
        data.xp = profile.xp
        data.caps = profile.caps
        data.inventory = profile.inventory
        data.equipment = profile.equipment
        data.activeQuests = profile.activeQuests
        data.completedQuests = profile.completedQuests
        data.playerClass = level >= PlayerClass.requiredLevel ? profile.playerClass : nil
        data.pet = PetData(profile: profile.pet)
        // A save can't hold more spent points than its level earned (e.g. an edited or future save).
        if let attributes = profile.attributes, attributes.isValid,
           attributes.spent <= Attributes.earned(atLevel: level) {
            data.attributes = attributes
        }

        var stats = Self.playerStats(level: level, data: data)
        if let hp = profile.hp, hp > 0 { stats.hp = min(hp, stats.maxHP) }
        if let mp = profile.mp { stats.mp = min(max(0, mp), stats.maxMP) }

        var spawn = map.playerSpawn
        if let saved = profile.position, profile.hp ?? 1 > 0, !map.isBlocked(saved, radius: Self.playerRadius) {
            spawn = saved
        }
        spawn = map.resolve(spawn, radius: Self.playerRadius)

        insert(WorldEntity(
            id: id,
            kind: .player,
            position: Vec3(spawn.x, 0, spawn.y),
            yaw: AngleMath.yaw(facing: -spawn), // face the trunk
            radius: Self.playerRadius,
            moveSpeed: Self.playerSpeed,
            stats: stats,
            player: data
        ))
        return id
    }

    public func profile(of id: EntityID) -> PlayerProfile? {
        guard let e = entities[id], let data = e.player else { return nil }
        return PlayerProfile(
            level: e.stats.level, xp: data.xp, hp: e.stats.hp, mp: e.stats.mp, caps: data.caps,
            inventory: data.inventory, equipment: data.equipment,
            activeQuests: data.activeQuests, completedQuests: data.completedQuests,
            position: e.position.xz, playerClass: data.playerClass, pet: data.pet.profile,
            attributes: data.attributes)
    }

    /// Worn gear (with upgrades) plus any set bonuses.
    public static func equipmentBonus(_ equipment: [EquipSlot: Gear]) -> StatBonus {
        EquipSlot.allCases.reduce(ItemSet.bonus(for: equipment)) { total, slot in
            total + (equipment[slot]?.bonus ?? StatBonus())
        }
    }

    /// Full-health stats for a player's level, class, and gear.
    static func playerStats(level: Int, data: PlayerData) -> CombatStats {
        Progression.playerStats(level: level, bonus: equipmentBonus(data.equipment), playerClass: data.playerClass,
                                weapon: data.equipment[.weapon]?.definition.weaponType,
                                weaponAttack: data.equipment[.weapon]?.bonus.attack ?? 0, attributes: data.attributes)
    }
}
