/// The client's view of "the server". The renderer and input layers only talk to this,
/// so going online means adding a `RemoteWorldHost` without touching gameplay code.
public protocol WorldHost: AnyObject {
    var map: WorldMap { get }
    var localPlayerID: EntityID { get }
    /// The two most recent snapshots; the client renders between them.
    var previousSnapshot: WorldSnapshot { get }
    var currentSnapshot: WorldSnapshot { get }
    /// How far (0...1) rendering time is between `previousSnapshot` and `currentSnapshot`.
    var interpolationAlpha: Float { get }

    func send(_ command: PlayerCommand)
    func advance(by deltaTime: Double)
    /// Events since the last call, oldest first.
    func drainEvents() -> [WorldEvent]
}

/// Offline host: runs the simulation in-process on a fixed timestep.
public final class LocalWorldHost: WorldHost {
    public private(set) var simulation: GameSimulation
    public let localPlayerID: EntityID
    public private(set) var previousSnapshot: WorldSnapshot
    public private(set) var currentSnapshot: WorldSnapshot
    public private(set) var interpolationAlpha: Float = 0

    private var accumulator: Double = 0
    private var pendingEvents: [WorldEvent] = []
    private static let maxTicksPerAdvance = 5

    public var map: WorldMap { simulation.map }

    public init(profile: PlayerProfile = .newCharacter, seed: UInt64 = 0x4D55_5348, startTimeOfDay: Float = 0.32) {
        var simulation = GameSimulation(seed: seed, startTimeOfDay: startTimeOfDay)
        localPlayerID = simulation.spawnPlayer(profile: profile)
        self.simulation = simulation
        currentSnapshot = simulation.snapshot(for: localPlayerID)
        previousSnapshot = currentSnapshot
    }

    public func send(_ command: PlayerCommand) {
        simulation.enqueue(command, from: localPlayerID)
    }

    public func advance(by deltaTime: Double) {
        let tickDuration = Double(GameSimulation.tickDuration)
        accumulator += deltaTime
        var ticks = 0
        while accumulator >= tickDuration {
            accumulator -= tickDuration
            ticks += 1
            if ticks > Self.maxTicksPerAdvance {
                // We fell far behind (debugger pause, app switch); drop time rather than spiral.
                accumulator = 0
                break
            }
            pendingEvents.append(contentsOf: simulation.step())
            previousSnapshot = currentSnapshot
            currentSnapshot = simulation.snapshot(for: localPlayerID)
        }
        interpolationAlpha = Float(accumulator / tickDuration)
    }

    /// Debug / game-master tool: bring out the world boss now.
    public func summonWorldBoss() {
        simulation.summonWorldBoss()
        currentSnapshot = simulation.snapshot(for: localPlayerID)
        previousSnapshot = currentSnapshot
    }

    /// Debug / game-master tool.
    public func teleportPlayer(to point: Vec2) {
        simulation.teleport(localPlayerID, to: point)
        currentSnapshot = simulation.snapshot(for: localPlayerID)
        previousSnapshot = currentSnapshot
    }

    public func drainEvents() -> [WorldEvent] {
        defer { pendingEvents.removeAll(keepingCapacity: true) }
        return pendingEvents
    }
}
