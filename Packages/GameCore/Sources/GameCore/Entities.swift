public struct EntityID: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UInt32

    public init(_ rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static func < (lhs: EntityID, rhs: EntityID) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { "#\(rawValue)" }
}

public enum MobKind: String, Codable, Sendable, CaseIterable {
    case snail, slug, beetle, sporeBeast, owl

    public var displayName: String {
        switch self {
        case .snail: "Snail"
        case .slug: "Slug"
        case .beetle: "Beetle"
        case .sporeBeast: "Spore Beast"
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
        case .owl: 3.0
        }
    }
}

public enum EntityKind: Hashable, Codable, Sendable {
    case player
    case mob(MobKind)
}

/// Server-side mob AI state.
struct MobBrain: Codable, Sendable {
    enum State: Codable, Sendable {
        case idle(ticksLeft: Int)
        case wander(target: Vec2, stuckTicks: Int)
    }

    var home: Vec2
    var leashRadius: Float
    var state: State
}

public struct WorldEntity: Codable, Sendable {
    public let id: EntityID
    public var kind: EntityKind
    public var position: Vec3
    public var yaw: Float
    public var velocity: Vec3 = .zero
    public var radius: Float
    public var moveSpeed: Float

    /// Players: the latest desired move direction in world XZ, length <= 1.
    var moveIntent: Vec2 = .zero
    /// Mobs only.
    var brain: MobBrain?

    public var isMoving: Bool { velocity.xz.length > 0.05 }
}
