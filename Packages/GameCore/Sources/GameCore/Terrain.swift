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
    /// Shallow crossings (a brook's fords), for the client's stepping stones. Their discs are too
    /// narrow to be deep, so walkers wade straight across.
    public let fords: [Vec2]
    /// A rough bounding circle (for quick rejection and the map).
    public let bounds: Disc

    /// You can wade this far in from the shoreline before it gets too deep to walk.
    public static let wadeDistance: Float = 2.5
    /// Width of the beach sloping down to the water.
    public static let shoreWidth: Float = 5
    /// Distance from the shoreline to full depth.
    static let deepDistance: Float = 9

    public init(name: String, discs: [Disc], waterLevel: Float, depth: Float, fords: [Vec2] = []) {
        self.name = name
        self.discs = discs
        self.waterLevel = waterLevel
        self.depth = depth
        self.fords = fords
        let center = discs.reduce(Vec2.zero) { $0 + $1.center } / Float(max(discs.count, 1))
        let radius = discs.map { $0.center.distance(to: center) + $0.radius }.max() ?? 0
        bounds = Disc(center: center, radius: radius)
    }

    /// Negative inside the water, positive on land: roughly meters to the shoreline.
    public func signedDistance(to point: Vec2) -> Float {
        // Far away: the bounding circle is close enough (and saves visiting every disc of a long brook).
        let outside = point.distance(to: bounds.center) - bounds.radius
        if outside > Self.shoreWidth + 1 { return outside }
        return discs.reduce(Float.greatestFiniteMagnitude) { min($0, point.distance(to: $1.center) - $1.radius) }
    }

    /// Everything that's too deep to walk, as circles the simulation collides with. Narrow water
    /// (a brook's fords) is shallow enough to wade all the way across.
    var deepWater: [Collider] {
        discs.filter { $0.radius - Self.wadeDistance >= 0.75 }
            .map { .circle(center: $0.center, radius: $0.radius - Self.wadeDistance) }
    }

    /// A winding brook: a chain of overlapping discs along `path`, `width` across, narrowing to
    /// wadeable fords within a few meters of each of `fords`.
    public static func brook(along path: [Vec2], width: Float, fords: [Vec2] = [], spacing: Float = 2) -> [Disc] {
        var discs: [Disc] = []
        for i in 0..<(path.count - 1) {
            let a = path[i], b = path[i + 1]
            let steps = max(1, Int((a.distance(to: b) / spacing).rounded(.up)))
            for step in 0..<steps {
                let p = a + (b - a) * (Float(step) / Float(steps))
                let nearFord = fords.contains { $0.distance(to: p) < 5 }
                discs.append(Disc(center: p, radius: nearFord ? Self.wadeDistance + 0.3 : width / 2))
            }
        }
        if let last = path.last { discs.append(Disc(center: last, radius: width / 2)) }
        return discs
    }
}

/// A table of raised ground walled by cliffs (or, with a negative `height`, a sunken basin).
/// The cliffs collide, so the only ways up (or down) are the `ramps`. The rim wanders a little,
/// so it doesn't look drawn with a compass.
public struct Plateau: Codable, Sendable {
    public struct Ramp: Codable, Sendable {
        /// The way the ramp runs out from the middle (down off a mesa, up out of a basin).
        public let yaw: Float
        public let width: Float
        /// How far the slope runs, in meters.
        public let length: Float

        public init(yaw: Float, width: Float, length: Float) {
            self.yaw = yaw
            self.width = width
            self.length = length
        }
    }

    public let name: String
    public let center: Vec2
    /// Mean radius of the top (or the basin's floor), where the cliff starts.
    public let radius: Float
    /// How far the top stands above (or the floor sinks below) the ground around it.
    public let height: Float
    /// How far out the cliff face runs, in meters.
    public let cliffWidth: Float
    public let ramps: [Ramp]

    public init(name: String, center: Vec2, radius: Float, height: Float, cliffWidth: Float = 5, ramps: [Ramp]) {
        self.name = name
        self.center = center
        self.radius = radius
        self.height = height
        self.cliffWidth = cliffWidth
        self.ramps = ramps
    }

    public var isBasin: Bool { height < 0 }

    /// Where the cliff starts in the direction of `yaw`.
    public func rimRadius(atYaw yaw: Float) -> Float {
        let phase = center.x * 0.13 + center.y * 0.07
        return radius * (1 + 0.07 * sin(3 * yaw + phase) + 0.04 * sin(5 * yaw - phase * 2))
    }

    /// 1 on a ramp, easing to 0 a few meters to either side of it.
    public func rampWeight(at p: Vec2) -> Float {
        let offset = p - center
        var weight: Float = 0
        for ramp in ramps {
            let along = AngleMath.direction(forYaw: ramp.yaw)
            guard (offset * along).sum() > 0 else { continue }
            let lateral = abs(offset.x * along.y - offset.y * along.x)
            weight = max(weight, 1 - smoothstep(ramp.width / 2, ramp.width / 2 + 3, lateral))
        }
        return weight
    }

    /// How far the slope runs at `p`: the cliff's width, or a ramp's length.
    func fadeWidth(at p: Vec2) -> Float {
        let weight = rampWeight(at: p)
        guard weight > 0 else { return cliffWidth }
        let length = ramps.map(\.length).max() ?? cliffWidth
        return cliffWidth + (length - cliffWidth) * weight
    }

    /// How much of `height` applies at `p`: 1 on the top (or floor), 0 past the foot of the cliff.
    public func influence(at p: Vec2) -> Float {
        let offset = p - center
        let d = offset.length
        guard d < radius * 1.12 + max(cliffWidth, ramps.map(\.length).max() ?? 0) else { return 0 }
        let rim = rimRadius(atYaw: AngleMath.yaw(facing: offset))
        guard d > rim else { return 1 }
        return 1 - smoothstep(rim, rim + fadeWidth(at: p), d)
    }

    /// Capsules along the middle of the cliff face, leaving gaps for the ramps.
    var cliffColliders: [Collider] {
        let mid = radius + cliffWidth / 2
        let count = max(12, Int((2 * .pi * mid / 3).rounded(.up)))
        let spots: [Vec2?] = (0..<count).map { i in
            let yaw = Float(i) / Float(count) * 2 * .pi
            let p = center + AngleMath.direction(forYaw: yaw) * (rimRadius(atYaw: yaw) + cliffWidth / 2)
            return rampWeight(at: p) > 0.35 ? nil : p
        }
        return (0..<count).compactMap { i in
            guard let a = spots[i], let b = spots[(i + 1) % count] else { return nil }
            return .capsule(a: a, b: b, radius: cliffWidth / 2)
        }
    }
}

/// The shape of the forest floor: gentle rolling ground, hills and hollows, a bowl rising
/// at the edge of the world, flattened clearings, and lakes. Pure arithmetic on the map's
/// own data, so the simulation, the renderer, and the map screen always agree.
public struct Terrain: Codable, Sendable {
    public let hills: [Hill]
    public let flats: [FlatArea]
    public let lakes: [Lake]
    /// Cliff-walled mesas and sunken basins.
    public let plateaus: [Plateau]
    /// The ground starts curling up into the rim of the hollow here...
    public let rimStart: Float
    /// ...and reaches `rimHeight` here, climbing on beyond.
    public let rimEnd: Float
    public let rimHeight: Float

    public init(hills: [Hill] = [], flats: [FlatArea] = [], lakes: [Lake] = [], plateaus: [Plateau] = [],
                rimStart: Float = 1_000, rimEnd: Float = 1_100, rimHeight: Float = 0) {
        self.hills = hills
        self.flats = flats
        self.lakes = lakes
        self.plateaus = plateaus
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

        for plateau in plateaus {
            let w = plateau.influence(at: p)
            if w > 0 { h += plateau.height * w }
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
