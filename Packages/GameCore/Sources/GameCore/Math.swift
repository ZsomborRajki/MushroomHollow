import Foundation

public typealias Vec2 = SIMD2<Float>
public typealias Vec3 = SIMD3<Float>

extension SIMD2 where Scalar == Float {
    public var length: Float { (x * x + y * y).squareRoot() }

    public var normalizedOrZero: Vec2 {
        let l = length
        return l > 1e-5 ? self / l : .zero
    }

    public func clampedLength(_ maxLength: Float) -> Vec2 {
        let l = length
        return l > maxLength ? self * (maxLength / l) : self
    }

    public func distance(to other: Vec2) -> Float { (other - self).length }
}

extension SIMD3 where Scalar == Float {
    /// Ground-plane projection (x, z).
    public var xz: Vec2 {
        get { Vec2(x, z) }
        set { x = newValue.x; z = newValue.y }
    }
}

/// Yaw convention used everywhere: yaw 0 faces +Z, and a yaw of `a` faces (sin a, cos a) on the XZ plane.
public enum AngleMath {
    public static func yaw(facing direction: Vec2) -> Float {
        atan2(direction.x, direction.y)
    }

    public static func direction(forYaw yaw: Float) -> Vec2 {
        Vec2(sin(yaw), cos(yaw))
    }

    /// Wraps into (-pi, pi].
    public static func wrap(_ angle: Float) -> Float {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a <= -.pi { a += 2 * .pi }
        if a > .pi { a -= 2 * .pi }
        return a
    }

    public static func lerp(_ from: Float, _ to: Float, _ t: Float) -> Float {
        from + wrap(to - from) * t
    }

    public static func moveToward(_ current: Float, _ target: Float, maxDelta: Float) -> Float {
        let delta = wrap(target - current)
        if abs(delta) <= maxDelta { return target }
        return wrap(current + (delta > 0 ? maxDelta : -maxDelta))
    }
}
