public struct EntityID: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UInt32

    public init(_ rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static func < (lhs: EntityID, rhs: EntityID) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { "#\(rawValue)" }
}

public enum MobKind: String, Codable, Sendable, CaseIterable {
    case snail, slug, beetle, sporeBeast, sporeling, owl

    public var displayName: String {
        switch self {
        case .snail: "Snail"
        case .slug: "Slug"
        case .beetle: "Beetle"
        case .sporeBeast: "Spore Beast"
        case .sporeling: "Sporeling"
        case .owl: "The Hollow Owl"
        }
    }

    /// Collision radius on the ground plane, in meters.
    public var radius: Float {
        switch self {
        case .snail: 0.55
        case .slug: 0.5
        case .beetle: 0.7
        case .sporeBeast: 0.9
        case .sporeling: 0.4
        case .owl: 3.0
        }
    }

    /// Wander speed, in meters per second.
    public var wanderSpeed: Float {
        switch self {
        case .snail: 0.6
        case .slug: 0.8
        case .beetle: 1.6
        case .sporeBeast: 1.1
        case .sporeling: 1.4
        case .owl: 3.0
        }
    }
}

public enum EntityKind: Hashable, Codable, Sendable {
    case player
    case mob(MobKind)
    case npc(NPCID)

    public var isMob: Bool {
        if case .mob = self { return true }
        return false
    }
}

/// What an entity is visibly doing, beyond moving (drives animations and telegraphs).
public enum Pose: String, Codable, Sendable {
    case normal
    /// Snail pulled into its shell: much harder to hurt.
    case hiding
    /// Beetle lowering its head before a charge. Get out of the way!
    case windingUp
    case charging
}

struct CombatState: Codable, Sendable {
    var target: EntityID?
    /// Auto-attacking (and chasing) `target`. Selecting without engaging is allowed.
    var engaged = false
    /// Ticks until the next auto-attack may land.
    var attackTimer = 0
    /// A targeted skill waiting for the player to get in range.
    var queuedSkill: SkillID?
    var lastCombatTick: UInt64 = 0
}

struct PlayerData: Codable, Sendable {
    var xp = 0
    var caps = 0
    var inventory = Inventory()
    var equipment: [EquipSlot: ItemID] = [:]
    /// Active quests and their kill counts (collect quests count the bag instead).
    var activeQuests: [QuestID: Int] = [:]
    var completedQuests: Set<QuestID> = []
    /// Ticks of cooldown remaining; absent means ready.
    var cooldowns: [SkillID: Int] = [:]
    var itemCooldown = 0
    var hpRegen: Float = 0
    var mpRegen: Float = 0
}

/// Server-side mob AI state.
struct MobBrain: Codable, Sendable {
    enum State: Codable, Sendable {
        case idle(ticksLeft: Int)
        case wander(target: Vec2, stuckTicks: Int)
        /// Chasing / attacking `combat.target`.
        case engaged
        /// Leashed: walking home, then fully heals.
        case returning
        case hiding(ticksLeft: Int)
        case windingUp(direction: Vec2, ticksLeft: Int)
        case charging(direction: Vec2, ticksLeft: Int)
    }

    var home: Vec2
    var leashRadius: Float
    /// nil for mobs that shouldn't respawn (e.g. sporelings).
    var spawnArea: Int?
    var state: State
    /// Ticks until the mob's special ability is ready again.
    var abilityTimer = 0
    var hasHidden = false
}

public struct WorldEntity: Codable, Sendable {
    public let id: EntityID
    public var kind: EntityKind
    public var position: Vec3
    public var yaw: Float
    public var velocity: Vec3 = .zero
    public var radius: Float
    public var moveSpeed: Float
    public var stats: CombatStats

    /// Players: the latest desired move direction in world XZ, length <= 1.
    var moveIntent: Vec2 = .zero
    var combat = CombatState()
    /// Mobs only.
    var brain: MobBrain?
    /// Players only.
    var player: PlayerData?
    /// Ticks since death (mob corpses linger briefly).
    var deathTicks = 0

    public var isMoving: Bool { velocity.xz.length > 0.05 }

    public var pose: Pose {
        switch brain?.state {
        case .hiding: .hiding
        case .windingUp: .windingUp
        case .charging: .charging
        default: .normal
        }
    }
}
