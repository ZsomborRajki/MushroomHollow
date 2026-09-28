import GameCore
import RealityKit
import UIKit

/// Colors of the forest floor's plants and stones.
enum Flora {
    static let stem = UIColor(red: 0.36, green: 0.55, blue: 0.22, alpha: 1)
    static let paleStem = UIColor(red: 0.5, green: 0.66, blue: 0.3, alpha: 1)
    static let leaf = UIColor(red: 0.27, green: 0.5, blue: 0.18, alpha: 1)
    static let darkLeaf = UIColor(red: 0.16, green: 0.36, blue: 0.14, alpha: 1)
    static let lightLeaf = UIColor(red: 0.45, green: 0.66, blue: 0.24, alpha: 1)
    static let petalWhite = UIColor(red: 0.98, green: 0.97, blue: 0.93, alpha: 1)
    static let daisyHeart = UIColor(red: 1, green: 0.78, blue: 0.16, alpha: 1)
    static let buttercup = UIColor(red: 1, green: 0.84, blue: 0.1, alpha: 1)
    static let dandelion = UIColor(red: 1, green: 0.76, blue: 0.08, alpha: 1)
    static let seedFluff = UIColor(red: 0.96, green: 0.96, blue: 0.92, alpha: 1)
    static let seedBrown = UIColor(red: 0.45, green: 0.33, blue: 0.2, alpha: 1)
    static let tulips = [UIColor(red: 0.9, green: 0.16, blue: 0.2, alpha: 1), UIColor(red: 0.98, green: 0.55, blue: 0.7, alpha: 1),
                         UIColor(red: 1, green: 0.8, blue: 0.2, alpha: 1), UIColor(red: 0.55, green: 0.3, blue: 0.75, alpha: 1)]
    static let bluebells = [UIColor(red: 0.36, green: 0.42, blue: 0.9, alpha: 1), UIColor(red: 0.55, green: 0.42, blue: 0.9, alpha: 1)]
    static let poppy = UIColor(red: 0.93, green: 0.22, blue: 0.12, alpha: 1)
    static let poppyHeart = UIColor(red: 0.12, green: 0.12, blue: 0.1, alpha: 1)
    static let foxgloves = [UIColor(red: 0.85, green: 0.42, blue: 0.72, alpha: 1), UIColor(red: 0.7, green: 0.45, blue: 0.85, alpha: 1),
                            UIColor(red: 0.96, green: 0.86, blue: 0.9, alpha: 1)]
    static let fern = UIColor(red: 0.3, green: 0.55, blue: 0.2, alpha: 1)
    static let fernDark = UIColor(red: 0.2, green: 0.42, blue: 0.16, alpha: 1)
    static let cattail = UIColor(red: 0.42, green: 0.26, blue: 0.14, alpha: 1)
    static let reed = UIColor(red: 0.4, green: 0.52, blue: 0.24, alpha: 1)
    static let clover = UIColor(red: 0.3, green: 0.58, blue: 0.24, alpha: 1)
    static let cloverFlower = UIColor(red: 0.96, green: 0.8, blue: 0.9, alpha: 1)
    static let caps = [Palette.capRed, Palette.capBrown, UIColor(red: 0.85, green: 0.7, blue: 0.45, alpha: 1)]
    static let gills = UIColor(red: 0.92, green: 0.86, blue: 0.74, alpha: 1)
    static let glowCaps = [Palette.glowCap, UIColor(red: 0.75, green: 0.55, blue: 1, alpha: 1)]
    static let bushes = [UIColor(red: 0.22, green: 0.42, blue: 0.17, alpha: 1), UIColor(red: 0.28, green: 0.48, blue: 0.2, alpha: 1),
                         UIColor(red: 0.19, green: 0.36, blue: 0.16, alpha: 1)]
    static let berry = UIColor(red: 0.85, green: 0.12, blue: 0.2, alpha: 1)
    static let blackberry = UIColor(red: 0.2, green: 0.08, blue: 0.2, alpha: 1)
    static let needles = UIColor(red: 0.18, green: 0.34, blue: 0.2, alpha: 1)
    static let lilyPad = UIColor(red: 0.28, green: 0.5, blue: 0.22, alpha: 1)
    static let lilyFlower = UIColor(red: 0.98, green: 0.82, blue: 0.9, alpha: 1)
    static let rocks = [UIColor(red: 0.5, green: 0.49, blue: 0.45, alpha: 1), UIColor(red: 0.44, green: 0.43, blue: 0.42, alpha: 1),
                        UIColor(red: 0.56, green: 0.52, blue: 0.45, alpha: 1)]
    static let rockMoss = UIColor(red: 0.3, green: 0.46, blue: 0.18, alpha: 1)
    static let twigs = [UIColor(red: 0.4, green: 0.29, blue: 0.19, alpha: 1), UIColor(red: 0.33, green: 0.24, blue: 0.16, alpha: 1),
                        UIColor(red: 0.47, green: 0.37, blue: 0.26, alpha: 1)]
    static let twigEnd = UIColor(red: 0.78, green: 0.66, blue: 0.47, alpha: 1)
}

/// Builds each piece of scenery from the shared `WorldMap` into scenery batches.
@MainActor
enum FloraBuilder {
    // MARK: - Plants

    static func build(_ plant: Plant, map: WorldMap, into batch: SceneryBatch) {
        var random = SeededRandom(seed: UInt64(plant.variant) | 1)
        let s = plant.height / plant.kind.typicalHeight
        let ground = plant.kind == .lilyPad ? map.surfaceHeight(at: plant.position) : map.groundHeight(at: plant.position)
        let base = SIMD3<Float>(plant.position.x, ground, plant.position.y)
        batch.anchor = plant.position
        let context = PlantContext(base: base, yaw: plant.yaw, s: s, h: plant.height)
        switch plant.kind {
        case .daisy: daisy(context, batch, &random)
        case .tulip: tulip(context, batch, &random)
        case .bluebell: bluebell(context, batch, &random)
        case .dandelion: dandelion(context, batch, &random, clock: false)
        case .dandelionClock: dandelion(context, batch, &random, clock: true)
        case .buttercup: buttercup(context, batch, &random)
        case .poppy: poppy(context, batch, &random)
        case .foxglove: foxglove(context, batch, &random)
        case .fern: fern(context, batch, &random)
        case .cattail: cattail(context, batch, &random)
        case .clover: clover(context, batch, &random)
        case .toadstool: toadstool(context, batch, &random)
        case .glowcap: glowcaps(context, batch, &random)
        case .bush: bush(context, batch, &random)
        case .bramble: bramble(context, batch, &random)
        case .sapling: sapling(context, batch, &random)
        case .lilyPad: lilyPad(context, batch, &random)
        }
    }

    private struct PlantContext {
        let base: SIMD3<Float>
        let yaw: Float
        let s: Float
        let h: Float

        func horizontal(_ yaw: Float) -> SIMD3<Float> {
            let d = AngleMath.direction(forYaw: yaw)
            return [d.x, 0, d.y]
        }
    }

    /// A stem that leans a little, returning its points (base to top).
    private static func leaningStem(_ c: PlantContext, height: Float, lean: Float, _ random: inout SeededRandom) -> [SIMD3<Float>] {
        let direction = c.horizontal(c.yaw + random.float(in: -0.5...0.5))
        return (0...3).map { i in
            let t = Float(i) / 3
            return c.base + [0, height * t, 0] + direction * lean * t * t
        }
    }

    /// Leaves fanning out from the foot of a plant.
    private static func rosette(_ c: PlantContext, _ batch: SceneryBatch, _ random: inout SeededRandom, count: Int,
                                length: Float, width: Float, pitch: Float, color: UIColor = Flora.leaf) {
        for i in 0..<count {
            let yaw = c.yaw + Float(i) / Float(count) * 2 * .pi + random.float(in: -0.3...0.3)
            batch.leaf(color, at: c.base + [0, 0.05, 0], yaw: yaw, pitch: pitch + random.float(in: -0.15...0.15),
                       length: length * random.float(in: 0.8...1.15), width: width)
        }
    }

    /// A ring of petals around a head facing along `facing`.
    private static func petalRing(_ batch: SceneryBatch, center: SIMD3<Float>, facing: simd_quatf, count: Int, color: UIColor,
                                  length: Float, width: Float, pitch: Float, offset: Float, shape: MeshData = Shapes.leaf,
                                  twist: Float = 0) {
        for i in 0..<count {
            let a = Float(i) / Float(count) * 2 * .pi + twist
            let local = simd_quatf(angle: a, axis: [0, 1, 0]) * simd_quatf(angle: -pitch, axis: [1, 0, 0])
            let rotation = facing * local
            let start = center + facing.act(simd_quatf(angle: a, axis: [0, 1, 0]).act([0, 0, offset]))
            batch.part(shape, color, at: start, scale: [width, length, length], rotation: rotation, layer: .foliage)
        }
    }

    private static func daisy(_ c: PlantContext, _ batch: SceneryBatch, _ random: inout SeededRandom) {
        let points = leaningStem(c, height: c.h, lean: c.h * random.float(in: 0.05...0.15), &random)
        batch.stem(Flora.stem, through: points, radius: 0.075 * c.s, tipRadius: 0.05 * c.s)
        rosette(c, batch, &random, count: 4, length: 1.1 * c.s, width: 0.4 * c.s, pitch: 0.4)
        let top = points[3]
        let tilt = simd_quatf(angle: random.float(in: 0...(2 * .pi)), axis: [0, 1, 0]) * simd_quatf(angle: random.float(in: 0.15...0.45), axis: [1, 0, 0])
        batch.part(Shapes.dome, Flora.daisyHeart, at: top, scale: [0.3, 0.16, 0.3] * c.s, rotation: tilt)
        batch.part(Shapes.dome, Flora.stem, at: top, scale: [0.28, 0.1, 0.28] * c.s, rotation: tilt * simd_quatf(angle: .pi, axis: [1, 0, 0]))
        petalRing(batch, center: top + tilt.act([0, 0.04, 0]) * c.s, facing: tilt, count: random.int(in: 13...17), color: Flora.petalWhite,
                  length: 0.78 * c.s, width: 0.24 * c.s, pitch: 0.12, offset: 0.2 * c.s)
    }

    private static func tulip(_ c: PlantContext, _ batch: SceneryBatch, _ random: inout SeededRandom) {
        let points = leaningStem(c, height: c.h * 0.86, lean: c.h * 0.05, &random)
        batch.stem(Flora.paleStem, through: points, radius: 0.085 * c.s, tipRadius: 0.07 * c.s)
        for i in 0..<2 {
            batch.leaf(Flora.lightLeaf, at: c.base + [0, 0.1, 0], yaw: c.yaw + Float(i) * .pi + random.float(in: -0.4...0.4),
                       pitch: 1.05, length: 1.9 * c.s, width: 0.55 * c.s, shape: Shapes.cupPetal)
        }
        let color = Flora.tulips[random.int(in: 0...(Flora.tulips.count - 1))]
        let top = points[3]
        batch.sphere(Flora.paleStem, at: top, radius: 0.13 * c.s, low: true)
        petalRing(batch, center: top, facing: .identity, count: 6, color: color, length: 0.85 * c.s, width: 0.58 * c.s,
                  pitch: 1.25, offset: 0.06 * c.s, shape: Shapes.cupPetal, twist: random.float(in: 0...1))
    }

    private static func bluebell(_ c: PlantContext, _ batch: SceneryBatch, _ random: inout SeededRandom) {
        let over = c.horizontal(c.yaw)
        let points: [SIMD3<Float>] = [c.base, c.base + [0, c.h * 0.55, 0], c.base + over * c.h * 0.22 + [0, c.h * 0.92, 0],
                                      c.base + over * c.h * 0.5 + [0, c.h * 0.86, 0]]
        batch.stem(Flora.stem, through: points, radius: 0.055 * c.s, tipRadius: 0.035 * c.s)
        rosette(c, batch, &random, count: 3, length: 1.4 * c.s, width: 0.28 * c.s, pitch: 0.9, color: Flora.lightLeaf)
        let color = Flora.bluebells[random.int(in: 0...1)]
        let count = random.int(in: 4...6)
        for i in 0..<count {
            let t = 0.35 + Float(i) / Float(count) * 0.65
            let along = points[2] + (points[3] - points[2]) * t
            let side = SIMD3(over.z, 0, -over.x) * (i % 2 == 0 ? 0.12 : -0.12) * c.s
            let hang = along + side - [0, 0.12 * c.s, 0]
            batch.rod(Flora.stem, from: along, to: hang, radius: 0.015 * c.s)
            let size = (0.2 + 0.05 * t) * c.s
            batch.part(Shapes.bell, color, at: hang - [0, size * 1.5, 0], scale: [size, size * 1.5, size],
                       rotation: simd_quatf(angle: random.float(in: -0.3...0.3), axis: [1, 0, 0]), layer: .foliage)
        }
    }

    private static func dandelion(_ c: PlantContext, _ batch: SceneryBatch, _ random: inout SeededRandom, clock: Bool) {
        let points = leaningStem(c, height: c.h, lean: c.h * random.float(in: 0.05...0.14), &random)
        batch.stem(Flora.paleStem, through: points, radius: 0.07 * c.s, tipRadius: 0.06 * c.s)
        rosette(c, batch, &random, count: 5, length: 1.3 * c.s, width: 0.35 * c.s, pitch: 0.12)
        let top = points[3]
        if clock {
            batch.sphere(Flora.seedBrown, at: top, radius: 0.16 * c.s, low: true)
            for direction in ActorModels.fibonacciDirections(18) where direction.y > -0.6 {
                let tip = top + direction * 0.6 * c.s
                batch.rod(Flora.seedFluff, from: top, to: tip, radius: 0.012 * c.s)
                batch.part(Shapes.disc, Flora.seedFluff, at: tip, scale: SIMD3(repeating: 0.16 * c.s),
                           rotation: simd_quatf(from: [0, 1, 0], to: direction), layer: .foliage)
            }
        } else {
            batch.sphere(Flora.dandelion, at: top + [0, 0.05 * c.s, 0], radius: 0.3 * c.s, squash: [1, 0.5, 1])
            petalRing(batch, center: top, facing: .identity, count: 16, color: Flora.dandelion, length: 0.42 * c.s,
                      width: 0.13 * c.s, pitch: 0.3, offset: 0.18 * c.s)
            petalRing(batch, center: top + [0, 0.06 * c.s, 0], facing: .identity, count: 11, color: Flora.buttercup,
                      length: 0.3 * c.s, width: 0.12 * c.s, pitch: 0.7, offset: 0.1 * c.s, twist: 0.3)
        }
    }

    private static func buttercup(_ c: PlantContext, _ batch: SceneryBatch, _ random: inout SeededRandom) {
        rosette(c, batch, &random, count: 3, length: 0.8 * c.s, width: 0.55 * c.s, pitch: 0.3, color: Flora.clover)
        let heads = random.int(in: 1...3)
        for i in 0..<heads {
            let yaw = c.yaw + Float(i) * 2.2
            let height = c.h * (1 - Float(i) * 0.18)
            let out = c.horizontal(yaw) * Float(i) * 0.25 * c.s
            let points = [c.base, c.base + [0, height * 0.5, 0] + out * 0.5, c.base + [0, height, 0] + out]
            batch.stem(Flora.stem, through: points, radius: 0.04 * c.s)
            let top = points[2]
            petalRing(batch, center: top, facing: .identity, count: 5, color: Flora.buttercup, length: 0.34 * c.s,
                      width: 0.34 * c.s, pitch: 0.75, offset: 0.03 * c.s, shape: Shapes.cupPetal, twist: Float(i))
            batch.sphere(Flora.daisyHeart, at: top + [0, 0.05 * c.s, 0], radius: 0.07 * c.s, low: true)
        }
    }

    private static func poppy(_ c: PlantContext, _ batch: SceneryBatch, _ random: inout SeededRandom) {
        let over = c.horizontal(c.yaw)
        let points = [c.base, c.base + [0, c.h * 0.5, 0] + over * 0.1 * c.s, c.base + [0, c.h * 0.85, 0] + over * 0.3 * c.s,
                      c.base + [0, c.h, 0] + over * 0.35 * c.s]
        batch.stem(Flora.stem, through: points, radius: 0.055 * c.s, tipRadius: 0.045 * c.s)
        rosette(c, batch, &random, count: 3, length: 1.1 * c.s, width: 0.4 * c.s, pitch: 0.5)
        let top = points[3]
        let facing = simd_quatf(angle: c.yaw, axis: [0, 1, 0]) * simd_quatf(angle: 0.3, axis: [1, 0, 0])
        petalRing(batch, center: top, facing: facing, count: 4, color: Flora.poppy, length: 0.8 * c.s, width: 1.0 * c.s,
                  pitch: 0.75, offset: 0.05 * c.s, shape: Shapes.cupPetal, twist: random.float(in: 0...1))
        batch.part(Shapes.dome, Flora.poppyHeart, at: top + facing.act([0, 0.04, 0]) * c.s, scale: [0.16, 0.14, 0.16] * c.s,
                   rotation: facing)
    }

    private static func foxglove(_ c: PlantContext, _ batch: SceneryBatch, _ random: inout SeededRandom) {
        let points = leaningStem(c, height: c.h, lean: c.h * 0.05, &random)
        batch.stem(Flora.stem, through: points, radius: 0.13 * c.s, tipRadius: 0.04 * c.s)
        rosette(c, batch, &random, count: 6, length: 1.9 * c.s, width: 0.7 * c.s, pitch: 0.25, color: Flora.darkLeaf)
        let color = Flora.foxgloves[random.int(in: 0...(Flora.foxgloves.count - 1))]
        let count = random.int(in: 11...15)
        for i in 0..<count {
            let t = 0.4 + Float(i) / Float(count) * 0.55
            let along = c.base + [0, c.h * t, 0] + (points[3] - points[0]) * [1, 0, 1] * t * t
            // Most bells face one way, as on a real foxglove.
            let yaw = c.yaw + random.float(in: -1.1...1.1)
            let out = c.horizontal(yaw)
            let size = (0.34 - 0.18 * (t - 0.4)) * c.s
            let mouth = simd_normalize(out * 0.75 + [0, -0.65, 0])
            batch.part(Shapes.bell, color, at: along + out * size * 0.6, scale: [size, size * 1.9, size],
                       rotation: simd_quatf(from: [0, -1, 0], to: mouth), layer: .foliage)
        }
        batch.sphere(Flora.stem, at: points[3], radius: 0.08 * c.s, low: true)
    }

    private static func fern(_ c: PlantContext, _ batch: SceneryBatch, _ random: inout SeededRandom) {
        let count = random.int(in: 6...9)
        for i in 0..<count {
            let yaw = c.yaw + Float(i) / Float(count) * 2 * .pi + random.float(in: -0.25...0.25)
            let length = c.h * random.float(in: 0.85...1.15)
            let rotation = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: -random.float(in: 0.35...0.6), axis: [1, 0, 0])
            batch.part(Shapes.frond, i % 2 == 0 ? Flora.fern : Flora.fernDark, at: c.base + [0, 0.1, 0],
                       scale: [length * 0.9, length, length], rotation: rotation, layer: .foliage)
        }
        // A fiddlehead still uncurling in the middle.
        batch.rod(Flora.fern, from: c.base, to: c.base + [0, c.h * 0.35, 0], radius: 0.05 * c.s)
        batch.sphere(Flora.fernDark, at: c.base + [0, c.h * 0.37, 0], radius: 0.12 * c.s, squash: [1, 1, 0.6], low: true)
    }

    private static func cattail(_ c: PlantContext, _ batch: SceneryBatch, _ random: inout SeededRandom) {
        let lean = c.horizontal(c.yaw) * c.h * 0.04
        let top = c.base + [0, c.h, 0] + lean
        batch.rod(Flora.reed, from: c.base - [0, 0.3, 0], to: top, radius: 0.05 * c.s, endRadius: 0.035 * c.s)
        batch.sphere(Flora.cattail, at: c.base + [0, c.h * 0.78, 0] + lean * 0.78, radius: 0.16 * c.s, squash: [1, 3.6, 1], low: true)
        for i in 0..<3 {
            batch.leaf(Flora.reed, at: c.base + [0, 0.05, 0], yaw: c.yaw + Float(i) * 2.1 + random.float(in: -0.3...0.3),
                       pitch: random.float(in: 1.15...1.4), length: c.h * random.float(in: 0.6...0.85), width: 0.18 * c.s)
        }
    }

    private static func clover(_ c: PlantContext, _ batch: SceneryBatch, _ random: inout SeededRandom) {
        let top = c.base + [0, c.h, 0]
        batch.rod(Flora.stem, from: c.base, to: top, radius: 0.03 * c.s)
        for i in 0..<3 {
            batch.leaf(Flora.clover, at: top, yaw: c.yaw + Float(i) * 2.09, pitch: 0.12, length: 0.42 * c.s, width: 0.5 * c.s,
                       shape: Shapes.cupPetal)
        }
        if random.unit() < 0.3 {
            let flower = c.base + c.horizontal(c.yaw + 1) * 0.3 * c.s + [0, c.h * 1.3, 0]
            batch.rod(Flora.stem, from: c.base, to: flower, radius: 0.025 * c.s)
            batch.sphere(Flora.cloverFlower, at: flower, radius: 0.16 * c.s, low: true)
        }
    }

    private static func toadstool(_ c: PlantContext, _ batch: SceneryBatch, _ random: inout SeededRandom) {
        let lean = c.horizontal(c.yaw) * c.h * random.float(in: 0...0.12)
        let capCenter = c.base + [0, c.h * 0.78, 0] + lean
        batch.rod(Palette.stem, from: c.base - [0, 0.1, 0], to: capCenter, radius: 0.34 * c.s, endRadius: 0.22 * c.s)
        let capRadius = c.h * random.float(in: 0.4...0.55)
        let color = Flora.caps[random.int(in: 0...(Flora.caps.count - 1))]
        let tilt = simd_quatf(from: [0, 1, 0], to: simd_normalize([lean.x, c.h, lean.z]))
        batch.part(Shapes.dome, color, at: capCenter, scale: [capRadius, capRadius * 0.6, capRadius], rotation: tilt)
        batch.part(Shapes.disc, Flora.gills, at: capCenter + [0, -0.01, 0], scale: SIMD3(repeating: capRadius * 0.97),
                   rotation: tilt * simd_quatf(angle: .pi, axis: [1, 0, 0]))
        if color == Palette.capRed {
            for _ in 0..<6 {
                let a = random.float(in: 0...(2 * .pi)), r = random.float(in: 0.1...0.75)
                let y = 0.6 * (1 - r * r).squareRoot()
                let local = SIMD3<Float>(sin(a) * r, y, cos(a) * r) * capRadius
                batch.sphere(Palette.capSpot, at: capCenter + tilt.act(local), radius: capRadius * 0.13, squash: [1, 0.4, 1],
                             rotation: tilt, low: true)
            }
        }
    }

    private static func glowcaps(_ c: PlantContext, _ batch: SceneryBatch, _ random: inout SeededRandom) {
        let glow = Flora.glowCaps[random.int(in: 0...1)]
        for i in 0..<random.int(in: 2...4) {
            let spot = c.base + c.horizontal(c.yaw + Float(i) * 2.4) * (i == 0 ? 0 : 0.45 * c.s)
            let h = c.h * (i == 0 ? 1 : random.float(in: 0.45...0.75))
            batch.rod(Palette.stem, from: spot, to: spot + [0, h, 0], radius: 0.09 * c.s * h / c.h + 0.03, endRadius: 0.06 * c.s)
            batch.part(Shapes.dome, glow, at: spot + [0, h, 0], scale: [0.45, 0.3, 0.45] * h, glow: true)
        }
    }

    private static func bush(_ c: PlantContext, _ batch: SceneryBatch, _ random: inout SeededRandom) {
        let lobes = random.int(in: 5...8)
        let spread = 1.1 * c.s
        for i in 0..<lobes {
            let a = c.yaw + Float(i) / Float(lobes) * 2 * .pi
            let r = i == 0 ? 0 : spread * random.float(in: 0.5...1)
            let size = c.s * (i == 0 ? 1.15 : random.float(in: 0.65...0.95))
            let spot = c.base + c.horizontal(a) * r + [0, size * 0.75 + (i == 0 ? 0.4 * c.s : 0), 0]
            batch.sphere(Flora.bushes[i % Flora.bushes.count], at: spot, radius: size, squash: [1, 0.85, 1], low: true)
        }
        if random.unit() < 0.4 {
            for _ in 0..<7 {
                let d = ActorModels.fibonacciDirections(7)[random.int(in: 0...6)]
                let spot = c.base + [0, 1.1 * c.s, 0] + SIMD3(d.x, abs(d.y) * 0.6, d.z) * 1.35 * c.s
                batch.sphere(Flora.berry, at: spot, radius: 0.12 * c.s, glow: false, low: true)
            }
        }
    }

    private static func bramble(_ c: PlantContext, _ batch: SceneryBatch, _ random: inout SeededRandom) {
        for i in 0..<6 {
            let out = c.horizontal(c.yaw + Float(i) * 1.05 + random.float(in: -0.3...0.3))
            let reach = c.s * random.float(in: 1.3...2)
            let peak = c.base + out * reach * 0.4 + [0, c.h * random.float(in: 0.7...1.1), 0]
            let end = c.base + out * reach + [0, 0.1, 0]
            batch.stem(Palette.roseDark, through: [c.base, peak, end], radius: 0.06 * c.s, tipRadius: 0.035 * c.s)
            batch.part(Shapes.cone, Palette.roseDark, at: peak + [0, 0.1 * c.s, 0], scale: [0.04, 0.18, 0.04] * c.s)
            batch.leaf(Flora.darkLeaf, at: peak, yaw: random.float(in: 0...(2 * .pi)), pitch: 0.2, length: 0.45 * c.s, width: 0.3 * c.s)
            if i % 2 == 0 {
                batch.sphere(Flora.blackberry, at: (peak + end) / 2 + [0, 0.12 * c.s, 0], radius: 0.13 * c.s, low: true)
            }
        }
    }

    private static func sapling(_ c: PlantContext, _ batch: SceneryBatch, _ random: inout SeededRandom) {
        batch.rod(Palette.bark, from: c.base - [0, 0.2, 0], to: c.base + [0, c.h * 0.4, 0], radius: 0.18 * c.s, endRadius: 0.12 * c.s)
        for tier in 0..<4 {
            let t = Float(tier)
            let width = c.h * (0.36 - t * 0.075)
            batch.part(Shapes.cone, tier % 2 == 0 ? Flora.needles : Flora.darkLeaf, at: c.base + [0, c.h * (0.36 + t * 0.19), 0],
                       scale: [width, c.h * 0.32, width], rotation: simd_quatf(angle: c.yaw + t, axis: [0, 1, 0]))
        }
    }

    private static func lilyPad(_ c: PlantContext, _ batch: SceneryBatch, _ random: inout SeededRandom) {
        let radius = 1.3 * c.s
        batch.part(Shapes.lilyPad, Flora.lilyPad, at: c.base + [0, 0.03, 0], scale: SIMD3(repeating: radius),
                   rotation: simd_quatf(angle: c.yaw, axis: [0, 1, 0]), layer: .foliage)
        if random.unit() < 0.25 {
            let center = c.base + [0, 0.1, 0] + c.horizontal(c.yaw + 2) * radius * 0.3
            petalRing(batch, center: center, facing: .identity, count: 8, color: Flora.lilyFlower, length: 0.5 * c.s,
                      width: 0.3 * c.s, pitch: 0.7, offset: 0.05, shape: Shapes.cupPetal)
            petalRing(batch, center: center + [0, 0.05, 0], facing: .identity, count: 6, color: Flora.lilyFlower, length: 0.4 * c.s,
                      width: 0.26 * c.s, pitch: 1.1, offset: 0.03, shape: Shapes.cupPetal, twist: 0.4)
            batch.sphere(Flora.daisyHeart, at: center + [0, 0.12, 0], radius: 0.1 * c.s, low: true)
        }
    }

    // MARK: - Rocks

    static func build(_ boulder: Boulder, map: WorldMap, into batch: SceneryBatch) {
        batch.anchor = boulder.position
        let ground = map.groundHeight(at: boulder.position)
        let variant = Int(boulder.variant % UInt32(rockShapes.count))
        let color = Flora.rocks[Int(boulder.variant / 7 % UInt32(Flora.rocks.count))]
        let rotation = simd_quatf(angle: boulder.yaw, axis: [0, 1, 0])
        // Sunk a little into the ground, so it looks heavy.
        let center = SIMD3<Float>(boulder.position.x, ground + boulder.height * 0.35, boulder.position.y)
        batch.part(rockShapes[variant], color, at: center, scale: [boulder.radius, boulder.height * 0.6, boulder.radius], rotation: rotation)
        if boulder.variant % 3 != 0 {
            // A cushion of moss on top.
            batch.part(Shapes.dome, Flora.rockMoss, at: center + [0, boulder.height * 0.38, 0],
                       scale: [boulder.radius * 0.62, boulder.height * 0.18, boulder.radius * 0.55], rotation: rotation)
        }
    }

    /// A few lumpy, flat-shaded stones to pick from.
    private static let rockShapes: [MeshData] = (0..<6).map { makeRock(seed: UInt64($0) + 11) }

    private static func makeRock(seed: UInt64) -> MeshData {
        var random = SeededRandom(seed: seed)
        let bumps = (0..<5).map { _ in (direction: ActorModels.fibonacciDirections(5)[random.int(in: 0...4)] + SIMD3(random.float(in: -0.4...0.4), 0, random.float(in: -0.4...0.4)),
                                        size: random.float(in: -0.25...0.25)) }
        let sphere = Shapes.lathe((0...5).map { i in
            let a = Float(i) / 5 * .pi
            return [sin(a), cos(a)]
        }, segments: 8)
        func displaced(_ p: SIMD3<Float>) -> SIMD3<Float> {
            let d = simd_length(p) > 0 ? simd_normalize(p) : [0, 1, 0]
            var r: Float = 1
            for bump in bumps { r += bump.size * max(0, simd_dot(d, simd_normalize(bump.direction))) }
            var q = d * r
            q.y = max(q.y, -0.55) // flat underneath
            return q
        }
        // Unshare the vertices so each face has its own normal: chunky, chiselled facets.
        var mesh = MeshData()
        for t in stride(from: 0, to: sphere.indices.count, by: 3) {
            let a = displaced(sphere.positions[Int(sphere.indices[t])])
            let b = displaced(sphere.positions[Int(sphere.indices[t + 1])])
            let c = displaced(sphere.positions[Int(sphere.indices[t + 2])])
            let normal = simd_cross(b - a, c - a)
            guard simd_length(normal) > 1e-6 else { continue }
            let n = simd_normalize(normal)
            let base = UInt32(mesh.positions.count)
            mesh.positions += [a, b, c]
            mesh.normals += [n, n, n]
            mesh.uvs += [.zero, .zero, .zero]
            mesh.indices += [base, base + 1, base + 2]
        }
        return mesh
    }

    // MARK: - Twigs

    static func build(_ twig: Twig, map: WorldMap, into batch: SceneryBatch) {
        batch.anchor = (twig.from + twig.to) / 2
        var random = SeededRandom(seed: UInt64(twig.variant) | 1)
        let color = Flora.twigs[Int(twig.variant % UInt32(Flora.twigs.count))]
        func onGround(_ p: Vec2, lift: Float) -> SIMD3<Float> {
            [p.x, map.groundHeight(at: p) + lift, p.y]
        }
        // Follow the ground in a few segments so the twig neither floats nor sinks.
        let steps = 3
        let points = (0...steps).map { i in onGround(twig.from + (twig.to - twig.from) * (Float(i) / Float(steps)), lift: twig.radius * 0.75) }
        batch.stem(color, through: points, radius: twig.radius, tipRadius: twig.radius * 0.75)
        // Snapped-off ends show paler wood.
        let direction = simd_normalize(points[steps] - points[0])
        batch.part(Shapes.disc, Flora.twigEnd, at: points[0] - direction * 0.01, scale: SIMD3(repeating: twig.radius),
                   rotation: simd_quatf(from: [0, 1, 0], to: -direction))
        batch.part(Shapes.disc, Flora.twigEnd, at: points[steps] + direction * 0.01, scale: SIMD3(repeating: twig.radius * 0.75),
                   rotation: simd_quatf(from: [0, 1, 0], to: direction))
        // A fork or two, and sometimes a last dry leaf.
        let along = twig.to - twig.from
        let side = Vec2(along.y, -along.x).normalizedOrZero
        for i in 0..<random.int(in: 1...2) {
            let t = random.float(in: 0.3...0.75)
            let start2 = twig.from + along * t
            let end2 = start2 + along.normalizedOrZero * along.length * 0.2 + side * (i == 0 ? 1 : -1) * along.length * random.float(in: 0.15...0.3)
            let start = onGround(start2, lift: twig.radius * 0.75)
            let end = onGround(end2, lift: twig.radius * 0.45)
            batch.rod(color, from: start, to: end, radius: twig.radius * 0.55, endRadius: twig.radius * 0.3)
            if random.unit() < 0.5 {
                batch.leaf(Palette.deadLeaf, at: end, yaw: AngleMath.yaw(facing: end2 - start2), pitch: 0.1,
                           length: 1.2, width: 0.7)
            }
        }
    }
}

extension Shapes {
    /// A fern frond: an arching, tapering strip with leaflets along both sides, base at the origin, tip toward z = 1.
    static let frond: MeshData = {
        var mesh = MeshData()
        let rows = 16
        for i in 0...rows {
            let t = Float(i) / Float(rows)
            let lift = 0.5 * sin(t * .pi * 0.85) - 0.2 * t * t
            // Leaflets: every other row reaches out, the rows between pinch in toward the midrib.
            let reach: Float = i % 2 == 1 ? 1 : 0.3
            let halfWidth = 0.17 * sin(min(1, t * 1.2) * .pi) * reach + 0.01
            for side: Float in [-1, 0, 1] {
                mesh.positions.append([side * halfWidth, lift + (side == 0 ? 0.015 : -abs(side) * halfWidth * 0.3), t])
                mesh.normals.append([0, 1, 0])
                mesh.uvs.append(.zero)
            }
        }
        for i in 0..<UInt32(rows) {
            let a = i * 3
            mesh.indices += [a, a + 3, a + 1, a + 1, a + 3, a + 4, a + 1, a + 4, a + 2, a + 2, a + 4, a + 5]
        }
        return mesh
    }()
}
