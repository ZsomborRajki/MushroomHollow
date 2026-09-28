public struct EntityID: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UInt32

    public init(_ rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static func < (lhs: EntityID, rhs: EntityID) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { "#\(rawValue)" }
}

public enum MobKind: String, Codable, Sendable, CaseIterable {
    // The inner ring, levels 1–15
    case snail, slug, beetle, sporeBeast, sporeling
    case ladybug, pillBug, acornling, bogFrog
    // The outer ring, levels 14–30
    case fuzzbee, puffweed, puffling
    case mossTurtle, emberNewt
    case weaverSpider, duskMoth
    case hedgehog, coneKnight
    case mantis, thornrose
    case grumblecap, stagBeetle
    // The Hollow Owl and its summons
    case mouse, owl

    public var displayName: String {
        switch self {
        case .snail: "Snail"
        case .slug: "Slug"
        case .beetle: "Beetle"
        case .sporeBeast: "Spore Beast"
        case .sporeling: "Sporeling"
        case .ladybug: "Ladybug"
        case .pillBug: "Pill Bug"
        case .acornling: "Acornling"
        case .bogFrog: "Bog Frog"
        case .fuzzbee: "Fuzzbee"
        case .puffweed: "Puffweed"
        case .puffling: "Puffling"
        case .mossTurtle: "Mossback Turtle"
        case .emberNewt: "Ember Newt"
        case .weaverSpider: "Weaver Spider"
        case .duskMoth: "Dusk Moth"
        case .hedgehog: "Bristle Hedgehog"
        case .coneKnight: "Cone Knight"
        case .mantis: "Orchid Mantis"
        case .thornrose: "Thornrose"
        case .grumblecap: "Grumblecap"
        case .stagBeetle: "Stag Beetle"
        case .mouse: "Field Mouse"
        case .owl: "The Hollow Owl"
        }
    }

    /// "Defeat 8 Orchid Mantises".
    public var pluralName: String {
        switch self {
        case .mantis: "Orchid Mantises"
        case .puffweed: "Puffweeds"
        case .mouse: "Field Mice"
        default: displayName + "s"
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
        case .ladybug: 0.5
        case .pillBug: 0.55
        case .acornling: 0.5
        case .bogFrog: 0.65
        case .fuzzbee: 0.55
        case .puffweed: 0.8
        case .puffling: 0.4
        case .mossTurtle: 0.95
        case .emberNewt: 0.6
        case .weaverSpider: 0.85
        case .duskMoth: 0.8
        case .hedgehog: 0.75
        case .coneKnight: 0.8
        case .mantis: 0.8
        case .thornrose: 0.9
        case .grumblecap: 1.0
        case .stagBeetle: 1.1
        case .mouse: 0.45
        case .owl: 2.6
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
        case .ladybug: 0.9
        case .pillBug: 0.9
        case .acornling: 1.2
        case .bogFrog: 1.4
        case .fuzzbee: 2
        case .puffweed: 0.8
        case .puffling: 1.6
        case .mossTurtle: 0.7
        case .emberNewt: 1.8
        case .weaverSpider: 1.8
        case .duskMoth: 1.6
        case .hedgehog: 1.5
        case .coneKnight: 1.1
        case .mantis: 2
        case .thornrose: 0.6
        case .grumblecap: 0.9
        case .stagBeetle: 1.5
        case .mouse: 2
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
    /// Pulled into its shell (or curled up): much harder to hurt.
    case hiding
    /// Lowering its head before a charge. Get out of the way!
    case windingUp
    case charging
    /// Owl rising before a swoop.
    case soaring
    /// Owl diving onto the marked spot.
    case diving
    /// Owl spreading its wings before a gust.
    case spreadingWings
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
    var equipment: [EquipSlot: Gear] = [:]
    /// Active quests and their kill counts (collect quests count the bag instead).
    var activeQuests: [QuestID: Int] = [:]
    var completedQuests: Set<QuestID> = []
    /// Ticks of cooldown remaining; absent means ready.
    var cooldowns: [SkillID: Int] = [:]
    var itemCooldown = 0
    var playerClass: PlayerClass?
    var buffs: [ActiveBuff] = []
    var hpRegen: Float = 0
    var mpRegen: Float = 0
}

struct ActiveBuff: Codable, Sendable {
    let skill: SkillID
    let effect: BuffEffect
    let totalTicks: Int
    var ticksLeft: Int
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
    /// World bosses only.
    var boss: BossBrain?
}

/// Extra state for the world boss's scripted fight.
struct BossBrain: Codable, Sendable {
    enum Action: Codable, Sendable {
        case none
        case swoopWindup(target: Vec2, ticksLeft: Int)
        case swoopDive(from: Vec2, to: Vec2, ticksLeft: Int)
        case gustWindup(direction: Vec2, ticksLeft: Int)
    }

    var action = Action.none
    var swoopTimer = 0
    var gustTimer = 0
    var summonsDone = 0
    var enraged = false
    /// Everyone who has hurt the boss this fight shares the rewards.
    var damagers: Set<EntityID> = []
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
    /// Players: riding the wind on a dandelion seed.
    var isFlying = false
    /// Players, while flying: -1 (descend) ... 1 (climb).
    var climbIntent: Float = 0
    var combat = CombatState()
    /// Mobs only.
    var brain: MobBrain?
    /// Players only.
    var player: PlayerData?
    /// Ticks since death (mob corpses linger briefly).
    var deathTicks = 0
    /// Players: being shoved (e.g. by the owl's wing gust); no control until it ends.
    var knockback: Vec2 = .zero
    var knockbackTicks = 0

    public var isMoving: Bool { velocity.xz.length > 0.05 }

    public var pose: Pose {
        switch brain?.boss?.action {
        case .swoopWindup: return .soaring
        case .swoopDive: return .diving
        case .gustWindup: return .spreadingWings
        case .some(.none), nil: break
        }
        return switch brain?.state {
        case .hiding: .hiding
        case .windingUp: .windingUp
        case .charging: .charging
        default: .normal
        }
    }
}
