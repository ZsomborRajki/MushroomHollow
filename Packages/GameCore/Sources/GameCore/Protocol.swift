/// Everything a client may ask the simulation to do. Offline these go straight to the
/// local simulation; online they will be serialized and sent to the server.
public enum PlayerCommand: Codable, Sendable, Equatable {
    /// Desired movement in world XZ. Length is clamped to 1 (analog stick magnitude = speed).
    /// Any movement cancels auto-attack.
    case move(Vec2)
    /// Select a target (nil clears). `engage` starts walking to it and auto-attacking.
    case target(EntityID?, engage: Bool)
    case useSkill(SkillID)
    /// Get back up at the village after fainting.
    case respawn

    // Items
    case useItem(ItemID)
    case equip(ItemID)
    case unequip(EquipSlot)

    // NPCs (must be within `NPCID.interactionRange`)
    case buy(ItemID, from: NPCID)
    case sell(ItemID, count: Int, to: NPCID)
    case acceptQuest(QuestID)
    case completeQuest(QuestID)
    /// First job change at level 15, at Elder Morel.
    case chooseClass(PlayerClass)

    // Flight (needs a Dandelion Seed)
    case toggleFlight
    /// While flying: -1 (descend) ... 1 (climb).
    case climb(Float)
}

public enum ActionFailure: String, Codable, Sendable {
    case tooFar
    case notEnoughCaps
    case inventoryFull
    case levelTooLow
    case missingItem
    case notUsable
    case notAvailable
    case itemCooldown
}

public enum MobAbility: String, Codable, Sendable {
    case hide, charge, sporeCloud, split
    // The Hollow Owl
    case swoop, swoopImpact, gust, summon, enrage
}

/// Things that happened during a tick, for effects, sounds, and HUD feedback.
public enum WorldEvent: Codable, Sendable, Equatable {
    case damage(source: EntityID, target: EntityID, amount: Int, isCritical: Bool, skill: SkillID?)
    case heal(target: EntityID, amount: Int, skill: SkillID?)
    case manaRestored(target: EntityID, amount: Int)
    case skillCast(caster: EntityID, skill: SkillID, target: EntityID?)
    case skillFailed(caster: EntityID, skill: SkillID, reason: SkillFailure)
    case mobAbility(entity: EntityID, ability: MobAbility)
    case died(entity: EntityID, killer: EntityID?)
    case xpGained(player: EntityID, amount: Int)
    case levelUp(player: EntityID, level: Int)
    case respawned(entity: EntityID)

    case capsChanged(player: EntityID, delta: Int)
    case itemReceived(player: EntityID, item: ItemID, count: Int)
    case itemUsed(player: EntityID, item: ItemID)
    case equipmentChanged(player: EntityID)
    case questAccepted(player: EntityID, quest: QuestID)
    case questProgress(player: EntityID, quest: QuestID, progress: Int, goal: Int)
    case questCompleted(player: EntityID, quest: QuestID)
    case actionFailed(player: EntityID, reason: ActionFailure)
    case classChosen(player: EntityID, playerClass: PlayerClass)
    case flightChanged(player: EntityID, isFlying: Bool)
    /// World events, announced to everyone.
    case worldBossSpawned(entity: EntityID, kind: MobKind)
    case worldBossDeparted(entity: EntityID)
    case worldBossDefeated(entity: EntityID, participants: [EntityID])
    case knockedBack(entity: EntityID)
}

/// A danger marker on the ground: get out before it goes off.
public struct TelegraphSnapshot: Codable, Sendable, Equatable {
    public enum Shape: Codable, Sendable, Equatable {
        case circle(radius: Float)
        /// A wedge from `position` toward `direction`.
        case cone(direction: Vec2, radius: Float, halfAngle: Float)
    }

    public let source: EntityID
    public let position: Vec2
    public let shape: Shape
    /// 0 when it appears, 1 when it goes off.
    public let progress: Float
}

/// What a client needs to render one entity.
public struct EntitySnapshot: Codable, Sendable, Equatable, Identifiable {
    public let id: EntityID
    public let kind: EntityKind
    public let position: Vec3
    public let yaw: Float
    public let isMoving: Bool
    public let pose: Pose
    public let level: Int
    public let hp: Int
    public let maxHP: Int
    /// Who this entity is fighting, if anyone.
    public let target: EntityID?
    /// Visible gear (players only), in `EquipSlot` order.
    public let gear: [ItemID]
    public let playerClass: PlayerClass?
    public let isFlying: Bool

    public var isAlive: Bool { hp > 0 }
}

public struct BuffStatus: Codable, Sendable, Equatable, Identifiable {
    public let skill: SkillID
    /// Seconds.
    public let remaining: Float
    public let total: Float

    public var id: SkillID { skill }
}

public struct SkillStatus: Codable, Sendable, Equatable, Identifiable {
    public let id: SkillID
    public let isUnlocked: Bool
    public let canAfford: Bool
    /// Seconds.
    public let cooldownRemaining: Float
    public let cooldownTotal: Float

    public var isReady: Bool { isUnlocked && canAfford && cooldownRemaining <= 0 }
}

/// Private state only the owning player receives.
public struct PlayerStatus: Codable, Sendable, Equatable {
    public let id: EntityID
    public let stats: CombatStats
    public let xp: Int
    public let xpToNextLevel: Int
    public let target: EntityID?
    public let isEngaged: Bool
    public let skills: [SkillStatus]
    public let caps: Int
    public let inventory: Inventory
    public let equipment: [EquipSlot: ItemID]
    public let quests: [QuestStatus]
    /// Seconds until potions can be used again.
    public let itemCooldown: Float
    public let isSlowed: Bool
    public let playerClass: PlayerClass?
    public let buffs: [BuffStatus]
    public let canFly: Bool
    public let isFlying: Bool
    /// Meters above the ground.
    public let altitude: Float
}

/// The world as seen by one viewer at the end of one simulation tick.
public struct WorldSnapshot: Codable, Sendable, Equatable {
    public let tick: UInt64
    public let entities: [EntitySnapshot]
    public let hazards: [HazardSnapshot]
    public let viewer: PlayerStatus?
    /// 0 = midnight, 0.25 = dawn, 0.5 = noon, 0.75 = dusk.
    public let timeOfDay: Float
    public let telegraphs: [TelegraphSnapshot]

    public static let empty = WorldSnapshot(tick: 0, entities: [], hazards: [], viewer: nil, timeOfDay: 0.4, telegraphs: [])

    public func entity(_ id: EntityID) -> EntitySnapshot? {
        entities.first { $0.id == id }
    }
}
