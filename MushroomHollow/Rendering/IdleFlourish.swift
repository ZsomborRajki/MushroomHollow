import GameCore
import RealityKit

/// Now-and-then idle flourishes that make the world feel alive: a bee's barrel roll, a
/// mushroom's morning stretch, a cricket's backflip, a townsperson's wave. Each actor runs its
/// own random clock (hashed from its ID), so about one in ten idle actors is mid-flourish at any
/// moment. Pure math on the pose the renderer already sets: no entities, materials, or allocations.
enum IdleFlourish {
    /// Time is cut into slots this long; a slot holds at most one flourish.
    private static let slot: Double = 8
    /// The share of its idle time an actor spends mid-flourish.
    private static let share: Double = 0.1

    // MARK: - Mobs

    /// Moves a mob plays on its whole model.
    enum Move {
        case barrelRoll, loop, twirl, stretch, hop, leap, backflip, shake, lookAround, rearUp, reach, somersault

        var duration: Double {
            switch self {
            case .barrelRoll: 1.1
            case .loop: 1.6
            case .twirl: 1.4
            case .stretch: 2.4
            case .hop: 1.0
            case .leap, .backflip: 1.2
            case .shake: 1.0
            case .lookAround: 2.8
            case .rearUp: 2.2
            case .reach: 1.8
            case .somersault: 1.1
            }
        }
    }

    /// Model-space changes to blend into a mob's idle pose.
    struct Pose {
        var offset = SIMD3<Float>.zero
        var scale = SIMD3<Float>.one
        var rotation = simd_quatf.identity

        /// Turns by `rotation` about `pivot` (model space) instead of the feet.
        mutating func rotate(_ turn: simd_quatf, about pivot: SIMD3<Float>) {
            rotation = turn * rotation
            offset += pivot - turn.act(pivot)
        }

        /// Stretches up by `height`, keeping the volume.
        mutating func stretch(_ height: Float) {
            let width = 1 / height.squareRoot()
            scale *= [width, height, width]
        }
    }

    /// What each kind likes to do when nobody's bothering it. Bosses keep to their script.
    static func moves(_ kind: MobKind) -> [Move] {
        switch kind {
        case .fuzzbee: [.barrelRoll, .barrelRoll, .loop]
        case .duskMoth: [.loop, .barrelRoll]
        case .puffling: [.twirl]
        case .grumblecap, .sporeBeast, .sporeling, .acornling: [.stretch, .stretch, .hop]
        case .puffweed, .thornrose: [.stretch, .shake]
        case .ladybug, .aphid: [.hop, .twirl]
        case .mouse: [.hop, .shake, .lookAround]
        case .bogFrog: [.leap, .lookAround]
        case .cricket: [.backflip, .leap]
        case .pillBug: [.somersault, .shake]
        case .snail, .slug: [.reach, .lookAround]
        case .earthworm, .rootcrawler: [.rearUp, .reach]
        case .mantis, .stagBeetle: [.rearUp, .lookAround]
        case .weaverSpider: [.rearUp, .shake]
        case .hedgehog, .delverMole: [.shake, .lookAround]
        case .coneKnight: [.hop, .lookAround]
        case .owl, .moldywarp: []
        default: [.lookAround, .shake]
        }
    }

    /// The pose change `kind` is playing at `time`, if it's mid-flourish.
    static func pose(_ kind: MobKind, id: EntityID, time: Double) -> Pose? {
        let moves = moves(kind)
        guard !moves.isEmpty, let (pick, p) = playing(id, time: time, choices: moves.count, duration: { moves[$0].duration })
        else { return nil }
        let move = moves[pick]
        // Mirror the move for every other flourish so it doesn't look canned.
        let side: Float = pick % 2 == 0 ? 1 : -1
        return pose(move, p: p, side: side, kind: kind)
    }

    private static func pose(_ move: Move, p: Float, side: Float, kind: MobKind) -> Pose {
        var pose = Pose()
        let height = kind.headHeight
        let center = SIMD3<Float>(0, height * 0.5, 0)
        switch move {
        case .barrelRoll:
            // A quick full roll about the nose, with a little lift.
            pose.offset.y += sin(p * .pi) * 0.18
            pose.rotate(simd_quatf(angle: side * 2 * .pi * smooth(p), axis: [0, 0, 1]), about: [0, height * 0.6, 0])
        case .loop:
            // Nose up, over the top, and round again, climbing through it.
            pose.offset.y += sin(p * .pi) * 0.45
            pose.rotate(simd_quatf(angle: -2 * .pi * smooth(p), axis: [1, 0, 0]), about: [0, height * 0.65, 0])
        case .twirl:
            // Pirouette on the breeze.
            pose.offset.y += sin(p * .pi) * 0.2
            pose.rotation = simd_quatf(angle: side * 2 * .pi * smooth(p), axis: [0, 1, 0])
        case .stretch:
            // Crouch, stretch up tall and arch back with a shiver, then settle with a wobble.
            let crouch = bump(p, 0, 0.12, 0.26)
            let tall = plateau(p, 0.14, 0.34, 0.62, 0.78)
            let quiver = sin(p * 90) * 0.012 * tall
            let wobble = p > 0.7 ? sin((p - 0.7) * 42) * 0.05 * (1 - p) / 0.3 : 0
            pose.stretch(1 - 0.14 * crouch + 0.26 * tall + quiver + wobble)
            pose.rotation = simd_quatf(angle: -0.12 * tall, axis: [1, 0, 0])
                * simd_quatf(angle: side * 0.06 * sin(p * 2 * .pi), axis: [0, 0, 1])
        case .hop:
            // Two happy hops, squashing on each landing.
            let phase = (p * 2).truncatingRemainder(dividingBy: 1)
            pose.offset.y = sin(phase * .pi) * 0.22
            let land = bump(phase, 0.85, 1, 1) + bump(phase, 0, 0, 0.12)
            pose.stretch(1 - 0.18 * land + 0.08 * sin(phase * .pi))
            pose.rotation = simd_quatf(angle: side * 0.5 * smooth(p), axis: [0, 1, 0])
        case .leap, .backflip:
            // Crouch, spring up (flipping right over for a backflip), and land with a squash.
            let air = min(max((p - 0.22) / 0.56, 0), 1)
            let crouch = bump(p, 0.02, 0.18, 0.24) + bump(p, 0.76, 0.82, 0.98)
            pose.offset.y = sin(air * .pi) * (move == .backflip ? 1.1 : 0.7)
            pose.stretch(1 - 0.22 * crouch + (air > 0 && air < 1 ? 0.1 : 0))
            let flip: Float = move == .backflip ? -2 * .pi * smooth(air) : -0.35 * sin(air * .pi)
            pose.rotate(simd_quatf(angle: flip, axis: [1, 0, 0]), about: center)
        case .shake:
            // A wet-dog shake from side to side.
            let fade = sin(p * .pi)
            pose.rotate(simd_quatf(angle: sin(p * 2 * .pi * 7) * 0.22 * fade, axis: [0, 0, 1]), about: center)
            pose.stretch(1 + 0.05 * fade)
        case .lookAround:
            // Look one way, then the other, then back.
            let yaw = 0.55 * (plateau(p, 0.05, 0.18, 0.36, 0.48) - plateau(p, 0.48, 0.6, 0.8, 0.95))
            pose.rotation = simd_quatf(angle: side * yaw, axis: [0, 1, 0])
                * simd_quatf(angle: -0.06 * sin(p * .pi), axis: [1, 0, 0])
        case .rearUp:
            // Rear up on the back end, sway a little, and drop back down.
            let up = plateau(p, 0.05, 0.28, 0.7, 0.92)
            let sway = sin(p * 3 * .pi) * 0.08 * up
            pose.rotate(simd_quatf(angle: -0.45 * up, axis: [1, 0, 0]) * simd_quatf(angle: side * sway, axis: [0, 0, 1]),
                        about: [0, 0, -kind.radius * 0.8])
        case .reach:
            // Stretch out long and low, then bunch back up.
            let long = plateau(p, 0, 0.35, 0.55, 0.85)
            let bunch = bump(p, 0.8, 0.9, 1)
            pose.scale = [1 - 0.08 * long, 1 - 0.15 * long + 0.1 * bunch, 1 + 0.28 * long - 0.1 * bunch]
            pose.offset.z = 0.15 * long
        case .somersault:
            // Curl up and tumble head over heels.
            pose.offset.y = sin(p * .pi) * 0.5
            pose.stretch(1 - 0.2 * sin(p * .pi))
            pose.rotate(simd_quatf(angle: 2 * .pi * smooth(p), axis: [1, 0, 0]), about: center)
        }
        return pose
    }

    /// Eases a flourish in and out, so one that's cut short (the mob is attacked or wanders off)
    /// or begins while the mob is busy doesn't snap.
    struct Blend {
        private var weight: Float = 0
        private var last: Double?

        mutating func step(idle: Bool, time: Double) -> Float {
            let dt = Float(min(max(time - (last ?? time), 0), 0.1))
            last = time
            weight += ((idle ? 1 : 0) - weight) * min(1, dt * 8)
            return weight
        }
    }

    // MARK: - Townsfolk

    /// Little things townsfolk do while they wait for customers, played on their rig.
    enum Gesture: CaseIterable {
        case wave, stretch, lookAround, scratchHead

        var duration: Double {
            switch self {
            case .wave: 2.2
            case .stretch: 2.8
            case .lookAround: 3
            case .scratchHead: 2
            }
        }
    }

    /// A gesture in progress: `progress` runs 0...1.
    struct Playing {
        var gesture: Gesture
        var progress: Float
    }

    static func gesture(id: EntityID, time: Double) -> Playing? {
        let all = Gesture.allCases
        guard let (pick, p) = playing(id, time: time, choices: all.count, duration: { all[$0].duration }) else { return nil }
        return Playing(gesture: all[pick], progress: p)
    }

    // MARK: - Scheduling

    /// Which of `choices` is playing for `id` at `time`, and how far along it is. Every slot rolls
    /// a choice and whether it plays at all (longer ones less often, so each choice fills `share`
    /// of the time), then a start somewhere inside the slot.
    private static func playing(_ id: EntityID, time: Double, choices: Int,
                                duration: (Int) -> Double) -> (Int, Float)? {
        let key = UInt64(id.rawValue)
        // Each actor's slots start at a different moment.
        let shifted = time + unit(hash(key, 0x51A7)) * slot
        let index = (shifted / slot).rounded(.down)
        let roll = hash(key, UInt64(bitPattern: Int64(index)))
        let pick = Int(roll % UInt64(choices))
        let length = duration(pick)
        guard unit(roll >> 8) < share * slot / length else { return nil }
        let start = unit(roll >> 32) * (slot - length)
        let p = (shifted - index * slot - start) / length
        guard p >= 0, p < 1 else { return nil }
        return (pick, Float(p))
    }

    /// SplitMix64 on the actor and slot.
    private static func hash(_ a: UInt64, _ b: UInt64) -> UInt64 {
        var z = a &* 0x9E37_79B9_7F4A_7C15 &+ b &* 0xBF58_476D_1CE4_E5B9 &+ 0x94D0_49BB_1331_11EB
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0..<1 from the low 24 bits.
    private static func unit(_ bits: UInt64) -> Double {
        Double(bits & 0xFF_FFFF) / Double(0x100_0000)
    }

    // MARK: - Curves

    static func smooth(_ x: Float) -> Float {
        let x = min(max(x, 0), 1)
        return x * x * (3 - 2 * x)
    }

    /// 0 outside `a...c`, rising smoothly to 1 at `b`.
    static func bump(_ x: Float, _ a: Float, _ b: Float, _ c: Float) -> Float {
        if x <= a || x >= c { return 0 }
        return x < b ? smooth((x - a) / max(b - a, 0.0001)) : smooth((c - x) / max(c - b, 0.0001))
    }

    /// 0 outside `a...d`, easing up to 1 by `b` and holding until `c`.
    static func plateau(_ x: Float, _ a: Float, _ b: Float, _ c: Float, _ d: Float) -> Float {
        if x <= a || x >= d { return 0 }
        if x < b { return smooth((x - a) / (b - a)) }
        if x > c { return smooth((d - x) / (d - c)) }
        return 1
    }
}
