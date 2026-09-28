import Foundation

/// A round area on the ground plane.
public struct Disc: Codable, Sendable, Equatable {
    public let center: Vec2
    public let radius: Float

    public init(center: Vec2, radius: Float) {
        self.center = center
        self.radius = radius
    }
}

/// A smooth bump in the forest floor (a dip, with a negative height).
public struct Hill: Codable, Sendable {
    public let center: Vec2
    public let radius: Float
    public let height: Float
}

/// Ground pressed level to `height` (the village, the arena, the trunk's feet), easing back over `fade`.
public struct FlatArea: Codable, Sendable {
    public let center: Vec2
    public let radius: Float
    public let fade: Float
    public let height: Float
}

/// Standing water. Its shoreline is the edge of the union of `discs`.
public struct Lake: Codable, Sendable {
    public let name: String
    public let discs: [Disc]
    public let waterLevel: Float
    /// How far below the surface the bed sinks in the middle.
    public let depth: Float

    /// You can wade this far in from the shoreline before it gets too deep to walk.
    public static let wadeDistance: Float = 2.5
    /// Width of the beach sloping down to the water.
    public static let shoreWidth: Float = 5
    /// Distance from the shoreline to full depth.
    static let deepDistance: Float = 9

    /// Negative inside the water, positive on land: roughly meters to the shoreline.
    public func signedDistance(to point: Vec2) -> Float {
        discs.reduce(Float.greatestFiniteMagnitude) { min($0, point.distance(to: $1.center) - $1.radius) }
    }

    /// Everything that's too deep to walk, as circles the simulation collides with.
    var deepWater: [Collider] {
        discs.map { .circle(center: $0.center, radius: max(0.5, $0.radius - Self.wadeDistance)) }
    }

    /// A rough bounding circle (for quick rejection and the map).
    public var bounds: Disc {
        let center = discs.reduce(Vec2.zero) { $0 + $1.center } / Float(max(discs.count, 1))
        let radius = discs.map { $0.center.distance(to: center) + $0.radius }.max() ?? 0
        return Disc(center: center, radius: radius)
    }
}

/// The shape of the forest floor: gentle rolling ground, hills and hollows, a bowl rising
/// at the edge of the world, flattened clearings, and lakes. Pure arithmetic on the map's
/// own data, so the simulation, the renderer, and the map screen always agree.
public struct Terrain: Codable, Sendable {
    public let hills: [Hill]
    public let flats: [FlatArea]
    public let lakes: [Lake]
    /// The ground starts curling up into the rim of the hollow here...
    public let rimStart: Float
    /// ...and reaches `rimHeight` here, climbing on beyond.
    public let rimEnd: Float
    public let rimHeight: Float

    public init(hills: [Hill] = [], flats: [FlatArea] = [], lakes: [Lake] = [],
                rimStart: Float = 1_000, rimEnd: Float = 1_100, rimHeight: Float = 0) {
        self.hills = hills
        self.flats = flats
        self.lakes = lakes
        self.rimStart = rimStart
        self.rimEnd = rimEnd
        self.rimHeight = rimHeight
    }

    /// Ground height at a point, in meters (0 is the village square).
    public func height(at p: Vec2) -> Float {
        // Low, lazy undulation everywhere, a meter or two peak to trough.
        var h = 0.8 * sin(p.x * 0.019 + 1.3) * cos(p.y * 0.023 - 0.7)
            + 0.5 * sin(p.x * 0.041 + p.y * 0.029 + 2.1)
            + 0.3 * sin(p.y * 0.067 - p.x * 0.053 + 0.4)

        for hill in hills {
            let offset = p - hill.center
            let d2 = (offset * offset).sum()
            let r2 = hill.radius * hill.radius
            guard d2 < r2 else { continue }
            let t = 1 - d2 / r2
            h += hill.height * t * t
        }

        let r = p.length
        if r > rimStart {
            // Keeps climbing past rimEnd so the ground never shows an edge.
            let past = max(0, r - rimEnd)
            h += rimHeight * smoothstep(rimStart, rimEnd, r) + past * 0.35
        }

        for flat in flats {
            let d = p.distance(to: flat.center)
            guard d < flat.radius + flat.fade else { continue }
            let w = 1 - smoothstep(flat.radius, flat.radius + flat.fade, d)
            h += (flat.height - h) * w
        }

        for lake in lakes {
            let d = lake.signedDistance(to: p)
            guard d < Lake.shoreWidth else { continue }
            let beach = lake.waterLevel + 0.2
            if d > 0 {
                // The beach slopes down to just above the water.
                h += (beach - h) * (1 - smoothstep(0, Lake.shoreWidth, d))
            } else {
                h = beach - (lake.depth + 0.2) * smoothstep(0, Lake.deepDistance, -d)
            }
        }
        return h
    }

    /// Unit surface normal (y up), from the slope around `p`.
    public func normal(at p: Vec2, step: Float = 0.5) -> Vec3 {
        let dx = height(at: p + Vec2(step, 0)) - height(at: p - Vec2(step, 0))
        let dz = height(at: p + Vec2(0, step)) - height(at: p - Vec2(0, step))
        let n = Vec3(-dx, 2 * step, -dz)
        return n / (n * n).sum().squareRoot()
    }

    /// The lake whose water covers `p`, if any.
    public func lake(at p: Vec2) -> Lake? {
        lakes.first { $0.signedDistance(to: p) < 0 }
    }

    /// What you'd stand (or float) on: the ground, or the water's surface over a lake.
    public func surfaceHeight(at p: Vec2) -> Float {
        let ground = height(at: p)
        guard let lake = lake(at: p) else { return ground }
        return max(ground, lake.waterLevel)
    }
}

func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}
