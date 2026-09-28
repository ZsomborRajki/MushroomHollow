import GameCore
import simd

/// Flyff-style free-orbit third-person camera around the player.
struct OrbitCamera {
    /// Yaw 0 puts the camera on the +Z side of the target, looking toward -Z.
    var yaw: Float = 0
    /// Radians above the horizon.
    var pitch: Float = 0.38
    var distance: Float = 8

    static let pitchRange: ClosedRange<Float> = 0.06...1.3
    static let distanceRange: ClosedRange<Float> = 3...18
    static let lookHeight: Float = 1.3

    private(set) var focus: SIMD3<Float> = .zero
    private var hasFocus = false

    /// `look.x` > 0 turns the view right; `look.y` > 0 looks up.
    mutating func apply(look: SIMD2<Float>, zoom: Float) {
        yaw = AngleMath.wrap(yaw - look.x)
        pitch = min(max(pitch - look.y, Self.pitchRange.lowerBound), Self.pitchRange.upperBound)
        distance = min(max(distance + zoom, Self.distanceRange.lowerBound), Self.distanceRange.upperBound)
    }

    mutating func follow(_ target: SIMD3<Float>, deltaTime: Float) {
        let goal = target + [0, Self.lookHeight, 0]
        if !hasFocus {
            focus = goal
            hasFocus = true
        } else {
            let t = 1 - exp(-14 * deltaTime)
            focus = simd_mix(focus, goal, SIMD3(repeating: t))
        }
    }

    /// Camera position, pulled in so it never ends up inside the trunk.
    func position(avoidingTrunkRadius trunkRadius: Float) -> SIMD3<Float> {
        var d = distance
        while true {
            let p = focus + offset(distance: d)
            if p.xz.length > trunkRadius + 0.5 || d <= Self.distanceRange.lowerBound {
                return SIMD3(p.x, max(p.y, 0.3), p.z)
            }
            d -= 0.25
        }
    }

    /// Camera-relative movement basis on the ground plane.
    var groundForward: Vec2 { Vec2(-sin(yaw), -cos(yaw)) }
    var groundRight: Vec2 { Vec2(cos(yaw), -sin(yaw)) }

    /// Converts a stick (x right, y forward) into a world-space XZ move direction.
    func worldDirection(forStick stick: SIMD2<Float>) -> Vec2 {
        (groundRight * stick.x + groundForward * stick.y).clampedLength(1)
    }

    private func offset(distance: Float) -> SIMD3<Float> {
        SIMD3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
    }
}
