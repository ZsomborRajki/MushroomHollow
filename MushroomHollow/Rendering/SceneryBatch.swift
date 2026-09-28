import Metal
import RealityKit
import UIKit

/// CPU-side triangle mesh.
struct MeshData {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []

    var isEmpty: Bool { indices.isEmpty }

    func resource(named name: String) -> MeshResource? {
        guard !isEmpty else { return nil }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}

/// Unit shapes the scenery is assembled from, low-poly since there are thousands of them.
enum Shapes {
    /// Radius 1, centered.
    static let sphere = lathe((0...6).map { i in
        let a = Float(i) / 6 * .pi
        return [sin(a), cos(a)]
    }, segments: 10)
    /// Coarser, for things drawn many times over (bush lobes, berries).
    static let lowSphere = lathe((0...4).map { i in
        let a = Float(i) / 4 * .pi
        return [sin(a), cos(a)]
    }, segments: 7)
    /// Top half of a sphere with a flat underside, sitting on y = 0.
    static let dome = merge([
        lathe((0...4).map { i in
            let a = Float(i) / 4 * .pi / 2
            return [sin(a), cos(a)]
        }, segments: 12),
        lathe([[1, 0], [0, 0]], segments: 12),
    ])
    /// Radius 1, height 1, centered, with caps.
    static let cylinder = merge([
        lathe([[0, 0.5], [1, 0.5]], segments: 8),
        lathe([[1, 0.5], [1, -0.5]], segments: 8),
        lathe([[1, -0.5], [0, -0.5]], segments: 8),
    ])
    /// An open tube for stems and twigs (their ends are hidden or capped by something else).
    static let tube = lathe([[1, 0.5], [1, -0.5]], segments: 7)
    /// Radius 1 at the base (y = -0.5), apex at y = 0.5.
    static let cone = merge([
        lathe([[0, 0.5], [1, -0.5]], segments: 8),
        lathe([[1, -0.5], [0, -0.5]], segments: 8),
    ])
    /// A bell open at the bottom: radius 1 at the mouth (y = 0), closed on top (y = 1).
    static let bell = lathe([[0, 1], [0.45, 0.95], [0.62, 0.7], [0.7, 0.35], [0.85, 0.1], [1, 0]], segments: 9)
    /// Round at the top (y = 1), pointed at the bottom (y = -1).
    static let teardrop = lathe([[0, 1], [0.6, 0.85], [0.95, 0.4], [0.85, -0.2], [0.45, -0.7], [0, -1]], segments: 8)
    static let box = makeBox()
    /// Flat, facing +Y, radius 1.
    static let disc = lathe([[0, 0], [1, 0]], segments: 14)
    /// A leaf or petal: base at the origin, tip at z = 1, up to 0.5 wide, facing +Y. Draw double-sided.
    static let leaf = makeLeaf(cup: 0)
    /// A petal curled up at the edges, like a cupped hand.
    static let cupPetal = makeLeaf(cup: 0.35)
    /// A lily pad: a disc with a notch.
    static let lilyPad = makeLilyPad()

    /// Revolves (radius, y) points, top to bottom along an outer wall, around the Y axis.
    static func lathe(_ profile: [SIMD2<Float>], segments: Int) -> MeshData {
        var mesh = MeshData()
        let count = profile.count
        for (i, point) in profile.enumerated() {
            let tangent = profile[min(i + 1, count - 1)] - profile[max(i - 1, 0)]
            var normal = SIMD2<Float>(-tangent.y, tangent.x)
            if point.x < 0.0001, i == 0 || i == count - 1 {
                normal = [0, i == 0 ? 1 : -1]
            }
            normal = simd_length(normal) > 0 ? simd_normalize(normal) : [0, 1]
            for j in 0...segments {
                let a = Float(j) / Float(segments) * 2 * .pi
                mesh.positions.append([point.x * sin(a), point.y, point.x * cos(a)])
                mesh.normals.append([normal.x * sin(a), normal.y, normal.x * cos(a)])
                mesh.uvs.append(.zero)
            }
        }
        let row = UInt32(segments + 1)
        for i in 0..<UInt32(count - 1) {
            for j in 0..<UInt32(segments) {
                let a = i * row + j, b = a + 1, c = a + row, d = c + 1
                mesh.indices += [a, c, d, a, d, b]
            }
        }
        return mesh
    }

    static func merge(_ parts: [MeshData]) -> MeshData {
        var mesh = MeshData()
        for part in parts {
            let base = UInt32(mesh.positions.count)
            mesh.positions += part.positions
            mesh.normals += part.normals
            mesh.uvs += part.uvs
            mesh.indices += part.indices.map { $0 + base }
        }
        return mesh
    }

    private static func makeBox() -> MeshData {
        var mesh = MeshData()
        let faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
            ([1, 0, 0], [0, 0, -1], [0, 1, 0]), ([-1, 0, 0], [0, 0, 1], [0, 1, 0]),
            ([0, 1, 0], [1, 0, 0], [0, 0, -1]), ([0, -1, 0], [1, 0, 0], [0, 0, 1]),
            ([0, 0, 1], [1, 0, 0], [0, 1, 0]), ([0, 0, -1], [-1, 0, 0], [0, 1, 0]),
        ]
        for (normal, u, v) in faces {
            let base = UInt32(mesh.positions.count)
            for (su, sv) in [(-1, -1), (1, -1), (1, 1), (-1, 1)] as [(Float, Float)] {
                mesh.positions.append((normal + u * su + v * sv) * 0.5)
                mesh.normals.append(normal)
                mesh.uvs.append(.zero)
            }
            mesh.indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        return mesh
    }

    private static func makeLeaf(cup: Float) -> MeshData {
        var mesh = MeshData()
        let rows = 6
        for i in 0...rows {
            let t = Float(i) / Float(rows)
            let halfWidth = 0.5 * sin(t * .pi) * (1 - t * 0.35)
            for side: Float in [-1, 0, 1] {
                let x = side * halfWidth
                // The edges lift (cup) and the whole blade arches gently.
                let y = abs(side) * cup * halfWidth + sin(t * .pi) * 0.06
                mesh.positions.append([x, y, t])
                mesh.normals.append(simd_normalize([-side * cup, 1, 0]))
                mesh.uvs.append(.zero)
            }
        }
        for i in 0..<UInt32(rows) {
            let a = i * 3
            mesh.indices += [a, a + 3, a + 1, a + 1, a + 3, a + 4, a + 1, a + 4, a + 2, a + 2, a + 4, a + 5]
        }
        return mesh
    }

    private static func makeLilyPad() -> MeshData {
        var mesh = MeshData(positions: [[0, 0, 0]], normals: [[0, 1, 0]], uvs: [.zero])
        let segments = 16
        let notch: Float = 0.35
        for i in 0...segments {
            let a = notch + Float(i) / Float(segments) * (2 * .pi - 2 * notch)
            mesh.positions.append([sin(a), 0, cos(a)])
            mesh.normals.append([0, 1, 0])
            mesh.uvs.append(.zero)
            if i > 0 { mesh.indices += [0, UInt32(i), UInt32(i + 1)] }
        }
        return mesh
    }
}

/// Every scenery color, one texel each, so all opaque scenery shares one material.
/// Glowing colors also go in the emissive texture (lit, but they shine in the dark too).
@MainActor
final class ColorAtlas {
    static let width = 256
    private(set) var colors: [(color: UIColor, glow: Bool)] = []
    private var lookup: [String: Int] = [:]

    /// Texture coordinate for a color.
    func uv(_ color: UIColor, glow: Bool = false) -> SIMD2<Float> {
        let key = "\(color.description)-\(glow)"
        let index: Int
        if let known = lookup[key] {
            index = known
        } else {
            index = min(colors.count, Self.width - 1)
            if colors.count < Self.width {
                colors.append((color, glow))
                lookup[key] = index
            }
        }
        return [(Float(index) + 0.5) / Float(Self.width), 0.5]
    }

    func materials() -> (solid: any RealityKit.Material, foliage: any RealityKit.Material) {
        var material = PhysicallyBasedMaterial()
        material.roughness = 0.85
        material.metallic = .init(floatLiteral: 0)
        let sampler = Self.nearestSampler()
        if let base = texture({ $0.color }), let glow = texture({ $0.glow ? $0.color : .black }) {
            material.baseColor = .init(texture: .init(base, sampler: sampler))
            material.emissiveColor = .init(texture: .init(glow, sampler: sampler))
            material.emissiveIntensity = 1.2
        } else {
            material.baseColor = .init(tint: Palette.moss)
        }
        var foliage = material
        foliage.faceCulling = .none
        return (material, foliage)
    }

    private func texture(_ pick: ((color: UIColor, glow: Bool)) -> UIColor) -> TextureResource? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let size = CGSize(width: Self.width, height: 4)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for (index, entry) in colors.enumerated() {
                pick(entry).setFill()
                context.fill(CGRect(x: index, y: 0, width: 1, height: 4))
            }
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource(image: cgImage, options: .init(semantic: .color, mipmapsMode: .none))
    }

    private static func nearestSampler() -> MaterialParameters.Texture.Sampler {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .nearest
        descriptor.magFilter = .nearest
        descriptor.mipFilter = .notMipmapped
        return MaterialParameters.Texture.Sampler(descriptor)
    }
}

/// Collects the static world into a few big meshes per chunk of ground, so thousands of
/// flowers, rocks, and twigs cost a handful of draw calls, and far chunks can be switched off.
@MainActor
final class SceneryBatch {
    enum Layer: Hashable {
        /// Closed shapes (back faces culled).
        case solid
        /// Leaves and petals, seen from both sides.
        case foliage
        case translucent(color: String, opacity: Float)
    }

    private struct Slot: Hashable {
        let x: Int32, z: Int32
        let layer: Layer
    }

    let atlas: ColorAtlas
    let chunkSize: Float
    /// Which chunk the next shapes belong to: set it to the object's position before building it.
    var anchor: SIMD2<Float> = .zero
    private var meshes: [MeshData] = []
    private var slots: [Slot: Int] = [:]
    private var translucentColors: [String: UIColor] = [:]

    init(atlas: ColorAtlas, chunkSize: Float) {
        self.atlas = atlas
        self.chunkSize = chunkSize
    }

    func add(_ shape: MeshData, _ color: UIColor, glow: Bool = false, transform: simd_float4x4, layer: Layer = .solid) {
        let uv = atlas.uv(color, glow: glow)
        let slot = Slot(x: Int32((anchor.x / chunkSize).rounded(.down)), z: Int32((anchor.y / chunkSize).rounded(.down)), layer: layer)
        let index: Int
        if let existing = slots[slot] {
            index = existing
        } else {
            index = meshes.count
            meshes.append(MeshData())
            slots[slot] = index
        }
        let normalMatrix = simd_float3x3(
            SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
            SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
            SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)).inverse.transpose
        Self.append(shape, into: &meshes[index], transform: transform, normalMatrix: normalMatrix, uv: uv)
    }

    private static func append(_ shape: MeshData, into mesh: inout MeshData, transform: simd_float4x4,
                               normalMatrix: simd_float3x3, uv: SIMD2<Float>) {
        let base = UInt32(mesh.positions.count)
        for p in shape.positions {
            let q = transform * SIMD4(p, 1)
            mesh.positions.append(SIMD3(q.x, q.y, q.z))
        }
        for n in shape.normals {
            let m = normalMatrix * n
            let length = simd_length(m)
            mesh.normals.append(length > 1e-6 ? m / length : [0, 1, 0])
        }
        mesh.uvs.append(contentsOf: repeatElement(uv, count: shape.positions.count))
        for i in shape.indices { mesh.indices.append(i + base) }
    }

    // MARK: - Convenience

    static func transform(at position: SIMD3<Float>, scale: SIMD3<Float>, rotation: simd_quatf = .identity) -> simd_float4x4 {
        Transform(scale: scale, rotation: rotation, translation: position).matrix
    }

    func part(_ shape: MeshData, _ color: UIColor, at position: SIMD3<Float>, scale: SIMD3<Float>,
              rotation: simd_quatf = .identity, glow: Bool = false, layer: Layer = .solid) {
        add(shape, color, glow: glow, transform: Self.transform(at: position, scale: scale, rotation: rotation), layer: layer)
    }

    func sphere(_ color: UIColor, at position: SIMD3<Float>, radius: Float, squash: SIMD3<Float> = .one,
                rotation: simd_quatf = .identity, glow: Bool = false, low: Bool = false) {
        part(low ? Shapes.lowSphere : Shapes.sphere, color, at: position, scale: squash * radius, rotation: rotation, glow: glow)
    }

    func cylinder(_ color: UIColor, at position: SIMD3<Float>, radius: Float, height: Float, rotation: simd_quatf = .identity,
                  glow: Bool = false) {
        part(Shapes.cylinder, color, at: position, scale: [radius, height, radius], rotation: rotation, glow: glow)
    }

    /// A tube from one point to another (open ends), tapering from `radius` to `endRadius`.
    func rod(_ color: UIColor, from start: SIMD3<Float>, to end: SIMD3<Float>, radius: Float, endRadius: Float? = nil,
             capped: Bool = false) {
        let axis = end - start
        let length = simd_length(axis)
        guard length > 1e-4 else { return }
        let rotation = simd_quatf(from: [0, 1, 0], to: axis / length)
        let taper = endRadius ?? radius
        if abs(taper - radius) < 1e-4 {
            part(capped ? Shapes.cylinder : Shapes.tube, color, at: (start + end) / 2, scale: [radius, length, radius], rotation: rotation)
        } else {
            // A frustum: scale a tube's ends separately.
            var shape = capped ? Shapes.cylinder : Shapes.tube
            for i in shape.positions.indices {
                let p = shape.positions[i]
                let r = p.y > 0 ? taper : radius
                shape.positions[i] = [p.x * r, p.y * length, p.z * r]
            }
            add(shape, color, transform: Self.transform(at: (start + end) / 2, scale: .one, rotation: rotation))
        }
    }

    /// A curved stem through several points (each segment a tube, with a ball at each joint).
    func stem(_ color: UIColor, through points: [SIMD3<Float>], radius: Float, tipRadius: Float? = nil) {
        let tip = tipRadius ?? radius
        for i in 0..<(points.count - 1) {
            let t0 = Float(i) / Float(points.count - 1), t1 = Float(i + 1) / Float(points.count - 1)
            rod(color, from: points[i], to: points[i + 1], radius: radius + (tip - radius) * t0, endRadius: radius + (tip - radius) * t1)
        }
    }

    /// A leaf or petal from `base`, pointing along `direction` (tilted by pitch), `length` long.
    func leaf(_ color: UIColor, at base: SIMD3<Float>, yaw: Float, pitch: Float, length: Float, width: Float,
              roll: Float = 0, shape: MeshData = Shapes.leaf, glow: Bool = false) {
        let rotation = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: -pitch, axis: [1, 0, 0])
            * simd_quatf(angle: roll, axis: [0, 0, 1])
        part(shape, color, at: base, scale: [width, length, length], rotation: rotation, glow: glow, layer: .foliage)
    }

    func translucent(_ shape: MeshData, _ color: UIColor, opacity: Float, transform: simd_float4x4) {
        let key = "\(color.description)-\(opacity)"
        translucentColors[key] = color
        add(shape, .white, transform: transform, layer: .translucent(color: key, opacity: opacity))
    }

    // MARK: - Build

    /// Turns everything collected so far into entities under `parent`, one per chunk.
    func build(into parent: Entity, name: String, castsShadow: Bool = true) -> [SceneryChunk] {
        let materials = atlas.materials()
        var chunks: [SIMD2<Int32>: Entity] = [:]
        var bounds: [SIMD2<Int32>: ChunkBounds] = [:]
        for (slot, index) in slots.sorted(by: { ($0.value) < ($1.value) }) {
            guard let resource = meshes[index].resource(named: name) else { continue }
            let key = SIMD2(slot.x, slot.z)
            let chunk: Entity
            if let existing = chunks[key] {
                chunk = existing
            } else {
                chunk = Entity()
                chunk.name = "\(name) \(slot.x),\(slot.z)"
                parent.addChild(chunk)
                chunks[key] = chunk
            }
            var box = bounds[key] ?? ChunkBounds()
            box.include(meshes[index].positions)
            bounds[key] = box
            let material: any RealityKit.Material = switch slot.layer {
            case .solid: materials.solid
            case .foliage: materials.foliage
            case let .translucent(color, opacity): Materials.translucent(translucentColors[color] ?? .white, opacity: opacity)
            }
            let model = ModelEntity(mesh: resource, materials: [material])
            if case .translucent = slot.layer {
                model.components.set(DynamicLightShadowComponent(castsShadow: false))
            } else if !castsShadow {
                model.components.set(DynamicLightShadowComponent(castsShadow: false))
            }
            chunk.addChild(model)
        }
        meshes = []
        slots = [:]
        return chunks.compactMap { key, entity in
            bounds[key].map { SceneryChunk(entity: entity, bounds: $0) }
        }
    }
}

/// World-space bounds of a mesh, including shapes that reach into neighboring chunks.
struct ChunkBounds {
    private(set) var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
    private(set) var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

    mutating func include(_ positions: [SIMD3<Float>]) {
        for position in positions {
            minimum = simd_min(minimum, position)
            maximum = simd_max(maximum, position)
        }
    }

    var center: SIMD3<Float> { (minimum + maximum) * 0.5 }
    var radius: Float { simd_length(maximum - center) }
}

struct SceneryChunk {
    let entity: Entity
    let center: SIMD3<Float>
    let radius: Float

    init(entity: Entity, bounds: ChunkBounds) {
        self.entity = entity
        center = bounds.center
        radius = bounds.radius
    }
}

/// Conservative sphere test against the camera's near, far, and four side planes.
struct CameraFrustum {
    let position: SIMD3<Float>
    let forward: SIMD3<Float>
    let right: SIMD3<Float>
    let up: SIMD3<Float>
    let horizontalTangent: Float
    let verticalTangent: Float
    let near: Float
    let far: Float

    init(position: SIMD3<Float>, target: SIMD3<Float>, verticalFOV: Float, aspect: Float, near: Float, far: Float) {
        self.position = position
        forward = simd_normalize(target - position)
        right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
        up = simd_cross(right, forward)
        verticalTangent = tan(verticalFOV * .pi / 360)
        horizontalTangent = verticalTangent * max(aspect, 0.1)
        self.near = near
        self.far = far
    }

    func contains(center: SIMD3<Float>, radius: Float) -> Bool {
        let offset = center - position
        let depth = simd_dot(offset, forward)
        guard depth + radius >= near, depth - radius <= far else { return false }
        let horizontal = abs(simd_dot(offset, right))
        let vertical = abs(simd_dot(offset, up))
        return horizontal <= depth * horizontalTangent + radius * sqrt(1 + horizontalTangent * horizontalTangent)
            && vertical <= depth * verticalTangent + radius * sqrt(1 + verticalTangent * verticalTangent)
    }
}

/// Switches off scenery chunks beyond the haze or outside the camera view.
@MainActor
final class SceneryCuller {
    private var groups: [(chunks: [SceneryChunk], distance: Float)] = []

    func add(_ chunks: [SceneryChunk], drawDistance: Float) {
        groups.append((chunks, drawDistance))
    }

    func update(frustum: CameraFrustum) {
        for group in groups {
            for chunk in group.chunks {
                let distance = simd_distance(chunk.center, frustum.position) - chunk.radius
                let visible = distance < group.distance && frustum.contains(center: chunk.center, radius: chunk.radius)
                if chunk.entity.isEnabled != visible { chunk.entity.isEnabled = visible }
            }
        }
    }
}

extension simd_quatf {
    static let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
}
