import GameCore
import Metal
import RealityKit
import UIKit

/// The ground itself: textured heightfield tiles, a plain skirt climbing away past the edge of
/// the world, the lakes' water, and grass in chunks that switch off beyond a short range.
@MainActor
enum TerrainBuilder {
    /// Grid spacing of the ground mesh, in meters.
    static let spacing: Float = 2
    static let tileCount = 6

    static func addGround(_ map: WorldMap, to world: Entity) -> UIImage {
        let extent = GroundPainter.extent
        let painting = GroundPainter.paint(map, size: 2048)
        var material = PhysicallyBasedMaterial()
        material.roughness = .init(floatLiteral: 1)
        material.metallic = .init(floatLiteral: 0)
        if let cgImage = painting.cgImage,
           let texture = try? TextureResource(image: cgImage, options: .init(semantic: .color)) {
            material.baseColor = .init(texture: .init(texture))
        } else {
            material.baseColor = .init(tint: Palette.moss)
        }

        // Heights once on a shared grid, so neighboring tiles meet exactly.
        let n = Int((2 * extent / spacing).rounded()) + 1
        var heights = [Float](repeating: 0, count: n * n)
        for row in 0..<n {
            for column in 0..<n {
                heights[row * n + column] = map.groundHeight(at: gridPoint(column, row))
            }
        }
        func height(_ column: Int, _ row: Int) -> Float {
            heights[max(0, min(n - 1, row)) * n + max(0, min(n - 1, column))]
        }

        let quadsPerTile = (n - 1 + tileCount - 1) / tileCount
        for tileRow in 0..<tileCount {
            for tileColumn in 0..<tileCount {
                var mesh = MeshData()
                let c0 = tileColumn * quadsPerTile, r0 = tileRow * quadsPerTile
                let c1 = min(n - 1, c0 + quadsPerTile), r1 = min(n - 1, r0 + quadsPerTile)
                guard c1 > c0, r1 > r0 else { continue }
                let width = c1 - c0 + 1
                for row in r0...r1 {
                    for column in c0...c1 {
                        let p = gridPoint(column, row)
                        mesh.positions.append([p.x, height(column, row), p.y])
                        let dx = height(column + 1, row) - height(column - 1, row)
                        let dz = height(column, row + 1) - height(column, row - 1)
                        mesh.normals.append(simd_normalize(SIMD3(-dx, 2 * spacing, -dz)))
                        mesh.uvs.append([(p.x + extent) / (2 * extent), 1 - (p.y + extent) / (2 * extent)])
                    }
                }
                for row in 0..<(r1 - r0) {
                    for column in 0..<(c1 - c0) {
                        // Round the square off into a disc; the skirt carries on beyond it.
                        let center = gridPoint(c0 + column, r0 + row) + Vec2(repeating: spacing / 2)
                        guard center.length < extent - 2 else { continue }
                        let a = UInt32(row * width + column), b = a + 1, c = a + UInt32(width), d = c + 1
                        mesh.indices += [a, c, d, a, d, b]
                    }
                }
                guard let resource = mesh.resource(named: "ground") else { continue }
                let tile = ModelEntity(mesh: resource, materials: [material])
                tile.name = "Ground \(tileColumn),\(tileRow)"
                world.addChild(tile)
            }
        }
        addSkirt(map, to: world)
        return painting
    }

    private static func gridPoint(_ column: Int, _ row: Int) -> Vec2 {
        Vec2(-GroundPainter.extent + Float(column) * spacing, -GroundPainter.extent + Float(row) * spacing)
    }

    /// The forest floor carrying on up into the haze past the rim, where no one can walk.
    private static func addSkirt(_ map: WorldMap, to world: Entity) {
        var mesh = MeshData()
        let radii: [Float] = [GroundPainter.extent - 6, 345, 370, 400, 440, 500, 580, 700, 900]
        let segments = 128
        for r in radii {
            for j in 0...segments {
                let a = Float(j) / Float(segments) * 2 * .pi
                let p = AngleMath.direction(forYaw: a) * r
                mesh.positions.append([p.x, map.groundHeight(at: p) - 0.3, p.y])
                mesh.normals.append(map.terrain.normal(at: p, step: 4))
                mesh.uvs.append(.zero)
            }
        }
        let row = UInt32(segments + 1)
        for i in 0..<UInt32(radii.count - 1) {
            for j in 0..<UInt32(segments) {
                let a = i * row + j, b = a + 1, c = a + row, d = c + 1
                mesh.indices += [a, d, b, a, c, d]
            }
        }
        guard let resource = mesh.resource(named: "skirt") else { return }
        let skirt = ModelEntity(mesh: resource, materials: [Materials.matte(UIColor(red: 0.15, green: 0.22, blue: 0.13, alpha: 1), roughness: 1)])
        skirt.components.set(DynamicLightShadowComponent(castsShadow: false))
        world.addChild(skirt)
    }

    // MARK: - Water

    static func addWater(_ map: WorldMap, to world: Entity) {
        for lake in map.terrain.lakes {
            let bounds = lake.bounds
            let step: Float = 1.5
            let n = Int((2 * (bounds.radius + 2) / step).rounded(.up)) + 1
            let origin = bounds.center - Vec2(repeating: bounds.radius + 2)
            var mesh = MeshData()
            var wet = [Bool](repeating: false, count: n * n)
            for row in 0..<n {
                for column in 0..<n {
                    let p = origin + Vec2(Float(column), Float(row)) * step
                    let depth = lake.waterLevel - map.groundHeight(at: p)
                    // Only inside the shoreline: low ground elsewhere is dry hollow, not lake.
                    // (A quad is kept if any corner is wet, so the water still reaches the shore.)
                    wet[row * n + column] = depth > 0.05 && lake.signedDistance(to: p) < 0.5
                    mesh.positions.append([p.x, lake.waterLevel, p.y])
                    mesh.normals.append([0, 1, 0])
                    // The shader reads the depth here: 0 at the shore, 1 in the deeps.
                    mesh.uvs.append([max(0, min(1, depth / lake.depth)), 0])
                }
            }
            for row in 0..<(n - 1) {
                for column in 0..<(n - 1) {
                    let a = row * n + column, b = a + 1, c = a + n, d = c + 1
                    guard wet[a] || wet[b] || wet[c] || wet[d] else { continue }
                    mesh.indices += [UInt32(a), UInt32(c), UInt32(d), UInt32(a), UInt32(d), UInt32(b)]
                }
            }
            guard let resource = mesh.resource(named: "water") else { continue }
            let water = ModelEntity(mesh: resource, materials: [Materials.water])
            water.name = lake.name
            water.components.set(DynamicLightShadowComponent(castsShadow: false))
            world.addChild(water)
        }
    }

    // MARK: - Grass

    /// Grass tufts in chunks (one draw call each); the Metal geometry modifier animates them.
    static func addGrass(_ map: WorldMap, to world: Entity, random: inout SeededRandom) -> [SceneryChunk] {
        let chunkSize: Float = 32
        var chunks: [SIMD2<Int32>: MeshData] = [:]
        let tuftCount = 30000
        for _ in 0..<tuftCount {
            let center = random.point(inDiscAt: .zero, radius: map.boundaryRadius + 12)
            if center.length < map.trunkCollisionRadius + 0.5 { continue }
            if center.length < map.boundaryRadius, map.isBlocked(center, radius: 0.2) { continue }
            if let lake = map.terrain.lakes.first, lake.signedDistance(to: center) < 1 { continue }
            // Keep the village clearing and the roads mostly trimmed.
            if center.distance(to: map.villageCenter) < map.villageRadius * 0.75, random.unit() < 0.85 { continue }
            if map.trails.contains(where: { $0.distance(to: center) < $0.width * 0.45 }), random.unit() < 0.9 { continue }

            let key = SIMD2(Int32((center.x / chunkSize).rounded(.down)), Int32((center.y / chunkSize).rounded(.down)))
            let ground = map.groundHeight(at: center)
            var mesh = chunks[key] ?? MeshData()
            chunks[key] = nil
            for _ in 0..<5 {
                let base = center + Vec2(random.float(in: -0.15...0.15), random.float(in: -0.15...0.15))
                let angle = random.float(in: 0...(2 * .pi))
                let across = AngleMath.direction(forYaw: angle) * random.float(in: 0.03...0.05)
                let lean = AngleMath.direction(forYaw: angle + .pi / 2) * random.float(in: 0.05...0.2)
                let height = random.float(in: 0.3...0.7)
                let first = UInt32(mesh.positions.count)
                mesh.positions.append([base.x - across.x, ground - 0.03, base.y - across.y])
                mesh.positions.append([base.x + across.x, ground - 0.03, base.y + across.y])
                mesh.positions.append([base.x + lean.x, ground + height, base.y + lean.y])
                mesh.normals.append(contentsOf: [[0, 1, 0], [0, 1, 0], [0, 1, 0]])
                // uv.y: 0 at the root, height / 0.7 at the tip (the shader bends and shades by it).
                mesh.uvs.append(contentsOf: [[0, 0], [1, 0], [0.5, height / 0.7]])
                mesh.indices.append(contentsOf: [first, first + 1, first + 2])
            }
            chunks[key] = mesh
        }

        var result: [SceneryChunk] = []
        for (_, mesh) in chunks.sorted(by: { ($0.key.y, $0.key.x) < ($1.key.y, $1.key.x) }) {
            guard let resource = mesh.resource(named: "grass") else { continue }
            let grass = ModelEntity(mesh: resource, materials: [Materials.grass])
            grass.components.set(DynamicLightShadowComponent(castsShadow: false))
            world.addChild(grass)
            var bounds = ChunkBounds()
            bounds.include(mesh.positions)
            result.append(SceneryChunk(entity: grass, bounds: bounds))
        }
        return result
    }
}
