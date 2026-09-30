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
        var groundMaterial: any RealityKit.Material = material
        if ArtStyle.isInk, let cgImage = painting.cgImage, let mask = GroundPainter.paintSurfaceMask(map, size: 1024).cgImage,
           let texture = try? TextureResource(image: cgImage, options: .init(semantic: .color)),
           let surfaces = try? TextureResource(image: mask, options: .init(semantic: .raw)),
           let detail = InkPainter.groundDetail(),
           let ink = InkMaterials.ground(texture, surfaces: surfaces, detail: detail) {
            groundMaterial = ink
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
                let tile = ModelEntity(mesh: resource, materials: [groundMaterial])
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
        let radii: [Float] = [GroundPainter.extent - 6, 385, 410, 440, 480, 540, 620, 740, 940]
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
            // A finer grid where a narrow brook runs, or its edge comes out saw-toothed.
            let step: Float = lake.discs.contains { $0.radius < 5 } ? 0.75 : 1.5
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
                    let isWet = depth > 0.05 && lake.signedDistance(to: p) < 0.5
                    wet[row * n + column] = isWet
                    // Dry corners dip under the bank, so the ground cuts the water along its own smooth
                    // line instead of the grid's staircase.
                    mesh.positions.append([p.x, lake.waterLevel - (isWet ? 0 : 0.4), p.y])
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

    // MARK: - Cliffs

    /// Rock faces over every mesa's and basin's cliffs. The 2 m ground grid can only draw a cliff as a
    /// smeared slope, so a finer, lumpy wall of rock is laid over it (lifted along the ground's normal
    /// so the coarse ground never pokes through), leaving the ramps as bare earth.
    static func addCliffs(_ map: WorldMap, to world: Entity, into batch: SceneryBatch) {
        let rows: [Float] = [-0.15, 0, 0.12, 0.25, 0.38, 0.5, 0.62, 0.75, 0.88, 1, 1.15]
        for plateau in map.terrain.plateaus {
            var mesh = MeshData()
            let columns = max(24, Int(2 * .pi * (plateau.radius + plateau.cliffWidth) / 1.1))
            var ramp = [Float](repeating: 0, count: (columns + 1) * rows.count)
            var up = [SIMD3<Float>](repeating: [0, 1, 0], count: (columns + 1) * rows.count)
            for column in 0...columns {
                let yaw = Float(column % columns) / Float(columns) * 2 * .pi
                let direction = AngleMath.direction(forYaw: yaw)
                let rim = plateau.rimRadius(atYaw: yaw)
                for (row, t) in rows.enumerated() {
                    let p = plateau.center + direction * (rim + t * plateau.cliffWidth)
                    let normal = map.terrain.normal(at: p, step: 0.6)
                    let weight = plateau.rampWeight(at: p)
                    // Lumpy strata: bulging most mid-face, tucked under the ground at the top and foot.
                    let inside = t >= 0 && t <= 1
                    let lump = 0.55 + 0.25 * sin(yaw * 23 + t * 4) + 0.2 * sin(yaw * 57 - t * 9 + plateau.center.x)
                    let lift = inside ? lump * (0.35 + sin(t * .pi)) * (1 - weight) : -0.4
                    let ground = SIMD3<Float>(p.x, map.groundHeight(at: p), p.y)
                    mesh.positions.append(ground + normal * lift)
                    mesh.normals.append(normal)
                    mesh.uvs.append([Float(column) / Float(columns), t])
                    ramp[column * rows.count + row] = weight
                    up[column * rows.count + row] = normal
                }
            }
            let stride = rows.count
            for column in 0..<columns {
                for row in 0..<(stride - 1) {
                    let a = column * stride + row, b = a + 1, c = a + stride, d = c + 1
                    guard min(ramp[a], ramp[b], ramp[c], ramp[d]) < 0.8 else { continue }
                    // Wind each quad to face out of the rock (the way the ground's normal points).
                    let face = simd_cross(mesh.positions[c] - mesh.positions[a], mesh.positions[b] - mesh.positions[a])
                    let outward = simd_dot(face, up[a] + up[d]) > 0
                    let quad: [Int] = outward ? [a, c, b, b, c, d] : [a, b, c, b, d, c]
                    mesh.indices += quad.map(UInt32.init)
                }
            }
            // Smooth normals from the faces, so the ink shading reads the lumps.
            var smoothed = [SIMD3<Float>](repeating: .zero, count: mesh.positions.count)
            for i in Swift.stride(from: 0, to: mesh.indices.count, by: 3) {
                let a = Int(mesh.indices[i]), b = Int(mesh.indices[i + 1]), c = Int(mesh.indices[i + 2])
                let n = simd_cross(mesh.positions[b] - mesh.positions[a], mesh.positions[c] - mesh.positions[a])
                for v in [a, b, c] { smoothed[v] += n }
            }
            mesh.normals = zip(smoothed, mesh.normals).map { simd_length($0) > 1e-6 ? simd_normalize($0) : $1 }
            guard let resource = mesh.resource(named: "cliff") else { continue }
            let cliff = ModelEntity(mesh: resource, materials: [Materials.matte(Palette.cliffRock, roughness: 1)])
            cliff.name = plateau.name
            world.addChild(cliff)

            // Rubble at the foot of the cliff (not on the ramps).
            var random = SeededRandom(seed: UInt64(bitPattern: Int64(plateau.center.x * 100 + plateau.center.y)))
            for i in 0..<Int(Float(columns) / 3) {
                let yaw = (Float(i) + random.float(in: 0...0.8)) / Float(columns / 3) * 2 * .pi
                let distance = plateau.rimRadius(atYaw: yaw) + plateau.cliffWidth * (plateau.isBasin ? 0.05 : 0.95)
                let spot = plateau.center + AngleMath.direction(forYaw: yaw) * distance
                guard plateau.rampWeight(at: spot) < 0.3, random.unit() < 0.7 else { continue }
                let radius = random.float(in: 0.5...1.3)
                FloraBuilder.build(Boulder(position: spot, radius: radius, height: radius * random.float(in: 0.8...1.4),
                                           yaw: random.float(in: 0...(2 * .pi)), variant: UInt32(truncatingIfNeeded: random.next())),
                                   map: map, into: batch)
            }
        }
    }

    /// Flat stepping stones across each ford, along the road.
    static func addFords(_ map: WorldMap, to world: Entity) {
        let stone = Materials.matte(Palette.pebble, roughness: 0.9)
        for lake in map.terrain.lakes {
            for ford in lake.fords {
                let along = Vec2(ford.y, -ford.x).normalizedOrZero
                let across = ford.normalizedOrZero
                for i in -3...3 {
                    let p = ford + along * (Float(i) * 1.5) + across * (i % 2 == 0 ? 0.35 : -0.35)
                    guard lake.signedDistance(to: p) < 0.3 else { continue }
                    let size = 0.55 + Float((i + 3) % 3) * 0.1
                    let entity = ModelEntity(mesh: Meshes.sphere, materials: [stone])
                    entity.position = [p.x, lake.waterLevel - 0.03, p.y]
                    entity.scale = [size, 0.13, size * 0.8]
                    entity.orientation = simd_quatf(angle: Float(i) * 0.7, axis: [0, 1, 0])
                    world.addChild(entity)
                }
            }
        }
    }

    // MARK: - Grass

    /// Grass tufts in chunks (one draw call each); the Metal geometry modifier animates them.
    static func addGrass(_ map: WorldMap, to world: Entity, random: inout SeededRandom) -> [SceneryChunk] {
        let chunkSize: Float = 32
        var chunks: [SIMD2<Int32>: MeshData] = [:]
        // 30,000 tufts for a world of radius 300; the same density however big it is.
        let tuftCount = Int(30000 * pow((map.boundaryRadius + 12) / 312, 2))
        for _ in 0..<tuftCount {
            let center = random.point(inDiscAt: .zero, radius: map.boundaryRadius + 12)
            if center.length < map.trunkCollisionRadius + 0.5 { continue }
            if center.length < map.boundaryRadius, map.isBlocked(center, radius: 0.2) { continue }
            if map.terrain.lakes.contains(where: { $0.signedDistance(to: center) < 1 }) { continue }
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
