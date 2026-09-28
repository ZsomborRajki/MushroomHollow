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
}

/// Offline host: runs the simulation in-process on a fixed timestep.
public final class LocalWorldHost: WorldHost {
    public private(set) var simulation: GameSimulation
    public let localPlayerID: EntityID
    public private(set) var previousSnapshot: WorldSnapshot
    public private(set) var currentSnapshot: WorldSnapshot
    public private(set) var interpolationAlpha: Float = 0

    private var accumulator: Double = 0
    private static let maxTicksPerAdvance = 5

    public var map: WorldMap { simulation.map }

    public init(seed: UInt64 = 0x4D55_5348) {
        var simulation = GameSimulation(seed: seed)
        localPlayerID = simulation.spawnPlayer()
        self.simulation = simulation
        currentSnapshot = simulation.snapshot()
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
            simulation.step()
            previousSnapshot = currentSnapshot
            currentSnapshot = simulation.snapshot()
        }
        interpolationAlpha = Float(accumulator / tickDuration)
    }
}
