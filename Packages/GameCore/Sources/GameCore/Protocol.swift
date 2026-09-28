/// Everything a client may ask the simulation to do. Offline these go straight to the
/// local simulation; online they will be serialized and sent to the server.
public enum PlayerCommand: Codable, Sendable, Equatable {
    /// Desired movement in world XZ. Length is clamped to 1 (analog stick magnitude = speed).
    case move(Vec2)
}

/// What a client needs to render one entity.
public struct EntitySnapshot: Codable, Sendable, Equatable, Identifiable {
    public let id: EntityID
    public let kind: EntityKind
    public let position: Vec3
    public let yaw: Float
    public let isMoving: Bool
}

/// The world as seen at the end of one simulation tick.
public struct WorldSnapshot: Codable, Sendable, Equatable {
    public let tick: UInt64
    public let entities: [EntitySnapshot]

    public static let empty = WorldSnapshot(tick: 0, entities: [])

    public func entity(_ id: EntityID) -> EntitySnapshot? {
        entities.first { $0.id == id }
    }
}
