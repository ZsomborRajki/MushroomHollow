import Foundation

/// Deterministic, platform-independent RNG (SplitMix64). The simulation only uses this,
/// so the same seed and command stream always produce the same world.
public struct SeededRandom: RandomNumberGenerator, Codable, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    public mutating func unit() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }

    public mutating func float(in range: ClosedRange<Float>) -> Float {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }

    public mutating func int(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    /// Uniform point inside a disc.
    public mutating func point(inDiscAt center: Vec2, radius: Float) -> Vec2 {
        let r = radius * unit().squareRoot()
        let a = unit() * 2 * .pi
        return center + Vec2(sin(a), cos(a)) * r
    }
}
