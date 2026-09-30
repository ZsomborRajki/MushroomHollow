import Foundation

/// The big plants of the forest floor. We're tiny down here, so an ordinary daisy towers
/// over you. The kind decides the look (client) and how thick its stem is to walk around.
public enum PlantKind: String, Codable, Sendable, CaseIterable {
    case daisy, tulip, bluebell, dandelion, dandelionClock, buttercup, poppy, foxglove
    case fern, cattail, clover, toadstool, glowcap, bush, bramble, sapling, lilyPad

    /// A typical grown height, in meters (a plant's `height` scales everything from this).
    public var typicalHeight: Float {
        switch self {
        case .daisy: 3.2
        case .tulip: 3.6
        case .bluebell: 2.8
        case .dandelion: 3.4
        case .dandelionClock: 4.2
        case .buttercup: 2.4
        case .poppy: 3.8
        case .foxglove: 7
        case .fern: 4.5
        case .cattail: 5.5
        case .clover: 1.1
        case .toadstool: 2.4
        case .glowcap: 1.8
        case .bush: 2.2
        case .bramble: 2
        case .sapling: 5
        case .lilyPad: 0.1
        }
    }

    /// Radius of the part you bump into, at `typicalHeight`. Zero: walk right through.
    var typicalCollisionRadius: Float {
        switch self {
        case .daisy, .dandelion, .dandelionClock, .poppy: 0.14
        case .tulip: 0.16
        case .bluebell, .buttercup, .cattail: 0.1
        case .foxglove: 0.24
        case .fern: 0.4
        case .toadstool: 0.34
        case .glowcap: 0.22
        case .bush: 1.5
        case .bramble: 1.3
        case .sapling: 0.22
        case .clover, .lilyPad: 0
        }
    }
}

public struct Plant: Codable, Sendable {
    public let kind: PlantKind
    public let position: Vec2
    public let height: Float
    public let yaw: Float
    /// Drives small per-plant differences in the look (petal count, lean, color).
    public let variant: UInt32

    public var collisionRadius: Float {
        kind.typicalCollisionRadius * height / kind.typicalHeight
    }
}

/// A rock, which to us is a boulder.
public struct Boulder: Codable, Sendable {
    public let position: Vec2
    public let radius: Float
    public let height: Float
    public let yaw: Float
    public let variant: UInt32

    public init(position: Vec2, radius: Float, height: Float, yaw: Float, variant: UInt32) {
        self.position = position
        self.radius = radius
        self.height = height
        self.yaw = yaw
        self.variant = variant
    }

    var collider: Collider { .circle(center: position, radius: radius * 0.9) }
}

/// A fallen twig, which to us is a log to walk around.
public struct Twig: Codable, Sendable {
    public let from: Vec2
    public let to: Vec2
    public let radius: Float
    public let variant: UInt32

    var collider: Collider { .capsule(a: from, b: to, radius: radius + 0.05) }
}

/// A dirt path. Kept clear of scenery.
public struct Trail: Codable, Sendable {
    public let points: [Vec2]
    public let width: Float
    public let closed: Bool

    public init(points: [Vec2], width: Float, closed: Bool = false) {
        self.points = points
        self.width = width
        self.closed = closed
    }

    /// Distance to the path's center line.
    public func distance(to p: Vec2) -> Float {
        var best = Float.greatestFiniteMagnitude
        let count = closed ? points.count : points.count - 1
        for i in 0..<max(count, 0) {
            let a = points[i], b = points[(i + 1) % points.count]
            let ab = b - a
            let t = max(0, min(1, ((p - a) * ab).sum() / max((ab * ab).sum(), 1e-6)))
            best = min(best, (a + ab * t).distance(to: p))
        }
        return best
    }

    static func ring(radius: Float, segments: Int = 96, width: Float) -> Trail {
        Trail(points: (0..<segments).map { AngleMath.direction(forYaw: Float($0) / Float(segments) * 2 * .pi) * radius },
              width: width, closed: true)
    }
}

/// Uniform grid over collider bounding boxes, so a move only tests nearby obstacles.
/// Queries return indices in ascending order: the same order a full scan would use.
struct ColliderGrid: Codable, Sendable {
    let cellSize: Float
    let origin: Vec2
    let columns: Int
    let rows: Int
    let cells: [[Int32]]

    init(colliders: [Collider], extent: Float, cellSize: Float = 16) {
        self.cellSize = cellSize
        origin = Vec2(-extent, -extent)
        columns = Int((2 * extent / cellSize).rounded(.up))
        rows = columns
        var cells = Array(repeating: [Int32](), count: columns * rows)
        for (index, collider) in colliders.enumerated() {
            let (lo, hi) = collider.bounds
            for cell in Self.cellRange(lo, hi, origin: origin, cellSize: cellSize, columns: columns, rows: rows) {
                cells[cell].append(Int32(index))
            }
        }
        self.cells = cells
    }

    /// Colliders whose bounds might reach within `radius` of `point`.
    func candidates(near point: Vec2, radius: Float) -> [Int] {
        let pad = Vec2(repeating: radius)
        let range = Self.cellRange(point - pad, point + pad, origin: origin, cellSize: cellSize, columns: columns, rows: rows)
        if range.count == 1, let only = range.first { return cells[only].map(Int.init) }
        var found = Set<Int32>()
        for cell in range { found.formUnion(cells[cell]) }
        return found.sorted().map(Int.init)
    }

    private static func cellRange(_ lo: Vec2, _ hi: Vec2, origin: Vec2, cellSize: Float, columns: Int, rows: Int) -> [Int] {
        func clampCell(_ v: Float, _ count: Int) -> Int { max(0, min(count - 1, Int(((v) / cellSize).rounded(.down)))) }
        let x0 = clampCell(lo.x - origin.x, columns), x1 = clampCell(hi.x - origin.x, columns)
        let y0 = clampCell(lo.y - origin.y, rows), y1 = clampCell(hi.y - origin.y, rows)
        var result: [Int] = []
        result.reserveCapacity((x1 - x0 + 1) * (y1 - y0 + 1))
        for y in y0...y1 {
            for x in x0...x1 { result.append(y * columns + x) }
        }
        return result
    }
}

extension Collider {
    var bounds: (Vec2, Vec2) {
        switch self {
        case let .circle(center, radius):
            return (center - Vec2(repeating: radius), center + Vec2(repeating: radius))
        case let .capsule(a, b, radius):
            let r = Vec2(repeating: radius)
            return (Vec2(min(a.x, b.x), min(a.y, b.y)) - r, Vec2(max(a.x, b.x), max(a.y, b.y)) + r)
        }
    }
}
