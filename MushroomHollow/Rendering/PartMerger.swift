import Metal
import RealityKit
import UIKit

/// Merges the many primitive parts a model is built from into a few meshes, so a critter costs a
/// couple of draw calls instead of fifty (and its ink outline a couple more, not fifty).
///
/// Only unnamed, childless `ModelEntity` leaves with one untextured material are merged, and only
/// with siblings under the same parent, so joints keep animating what hangs off them. Anything that
/// moves, swaps its material, or gets refit on its own (wings, bow strings, the swing trail, faces)
/// is named or textured and stays separate. In the ink style every toon color goes into one shared
/// atlas texture (`PartAtlas`), so all the opaque parts on a joint become a single mesh.
@MainActor
enum PartMerger {
    /// Merged meshes are named this; their outline-less variants add `noHullSuffix`.
    static let mergedName = "merged"
    static let noHullSuffix = ".nohull"

    /// What `merge` took apart, so it can be put back (a player's rig before it changes gear).
    final class Record {
        fileprivate var groups: [(parent: Entity, merged: [Entity], originals: [Entity])] = []

        /// Puts every merged part back where it was and removes the merged meshes.
        func restore() {
            for group in groups {
                for entity in group.merged { entity.removeFromParent() }
                for part in group.originals { group.parent.addChild(part) }
            }
            groups = []
        }
    }

    private struct Candidate {
        let part: ModelEntity
        let mesh: MeshData
        let transform: simd_float4x4
        let bucket: String
        let material: any RealityKit.Material
        /// Atlas texel for the part's color (ink toon parts only).
        let uv: SIMD2<Float>?
        let castsShadow: Bool
        let wantsHull: Bool
    }

    /// Merges sibling parts throughout `root`. `hullMinimumSize` mirrors `addInkHulls`: parts
    /// smaller than that (eye glints, pupils) are merged separately and get no outline.
    @discardableResult
    static func merge(_ root: Entity, hullMinimumSize: Float? = 0.05) -> Record {
        let record = Record()
        mergeChildren(of: root, root: root, hullMinimumSize: hullMinimumSize, record: record)
        PartAtlas.shared.flush()
        return record
    }

    private static func mergeChildren(of parent: Entity, root: Entity, hullMinimumSize: Float?, record: Record) {
        var candidates: [Candidate] = []
        for child in Array(parent.children) {
            if let part = child as? ModelEntity, let candidate = candidate(part, transform: part.transform.matrix,
                                                                           root: root, hullMinimumSize: hullMinimumSize) {
                candidates.append(candidate)
            } else {
                mergeChildren(of: child, root: root, hullMinimumSize: hullMinimumSize, record: record)
            }
        }
        let merged = build(candidates, into: parent)
        if !merged.originals.isEmpty {
            record.groups.append((parent, merged.entities, merged.originals))
        }
    }

    /// Flattens a whole static subtree (nothing in it may move later) into merged meshes directly
    /// under `root`, one set per `cellSize` square of ground so the camera can still cull them.
    static func flatten(_ root: Entity, cellSize: Float) {
        var cells: [SIMD2<Int32>: [Candidate]] = [:]
        func collect(_ entity: Entity) {
            for child in Array(entity.children) {
                if let part = child as? ModelEntity,
                   let candidate = candidate(part, transform: part.transformMatrix(relativeTo: root), root: root, hullMinimumSize: nil) {
                    let p = candidate.transform.columns.3
                    let key = SIMD2(Int32((p.x / cellSize).rounded(.down)), Int32((p.z / cellSize).rounded(.down)))
                    cells[key, default: []].append(candidate)
                } else {
                    collect(child)
                }
            }
        }
        collect(root)
        for key in cells.keys.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
            _ = build(cells[key] ?? [], into: root)
        }
        PartAtlas.shared.flush()
    }

    // MARK: - Building

    private static func candidate(_ part: ModelEntity, transform: simd_float4x4, root: Entity,
                                  hullMinimumSize: Float?) -> Candidate? {
        guard part.name.isEmpty, part.isEnabled,
              part.children.allSatisfy({ $0.name == InkStyle.hullName }),
              let model = part.model, model.materials.count == 1, let material = model.materials.first,
              part.components[OpacityComponent.self] == nil,
              let fingerprint = fingerprint(material), let mesh = meshData(model.mesh) else { return nil }
        let castsShadow = part.components[DynamicLightShadowComponent.self]?.castsShadow ?? true
        var wantsHull = false
        if let minimum = hullMinimumSize, Entity.takesInkOutline(material) {
            let size = model.mesh.bounds.extents * part.scale(relativeTo: root)
            wantsHull = max(size.x, size.y, size.z) >= minimum
        }
        var bucket = fingerprint
        var uv: SIMD2<Float>?
        var bucketMaterial = material
        if let color = InkMaterials.toonColor(fingerprint: fingerprint), let texel = PartAtlas.shared.uv(for: color),
           let atlas = PartAtlas.shared.material {
            bucket = "atlas"
            uv = texel
            bucketMaterial = atlas
        }
        bucket += "|\(castsShadow)|\(wantsHull)"
        return Candidate(part: part, mesh: mesh, transform: transform, bucket: bucket, material: bucketMaterial, uv: uv,
                         castsShadow: castsShadow, wantsHull: wantsHull)
    }

    /// Merges groups of two or more parts sharing a bucket; lone parts are left as they are.
    private static func build(_ candidates: [Candidate], into parent: Entity) -> (entities: [Entity], originals: [Entity]) {
        var buckets: [String: [Candidate]] = [:]
        var order: [String] = []
        for candidate in candidates {
            if buckets[candidate.bucket] == nil { order.append(candidate.bucket) }
            buckets[candidate.bucket, default: []].append(candidate)
        }
        var entities: [Entity] = []
        var originals: [Entity] = []
        for key in order {
            guard let group = buckets[key], group.count > 1, let first = group.first,
                  let resource = mesh(for: group) else { continue }
            let merged = ModelEntity(mesh: resource, materials: [first.material])
            merged.name = first.wantsHull ? mergedName : mergedName + noHullSuffix
            if !first.castsShadow { merged.components.set(DynamicLightShadowComponent(castsShadow: false)) }
            parent.addChild(merged)
            entities.append(merged)
            for candidate in group {
                // Outlines go on the merged mesh; a part put back later gets a fresh one if it needs it.
                for hull in candidate.part.children where hull.name == InkStyle.hullName { hull.removeFromParent() }
                candidate.part.removeFromParent()
                originals.append(candidate.part)
            }
        }
        return (entities, originals)
    }

    /// Identical groups (the same parts in the same colors, e.g. every NPC's hands) share one mesh.
    private static var mergedMeshes: [Int: MeshResource] = [:]

    private static func mesh(for group: [Candidate]) -> MeshResource? {
        var hasher = Hasher()
        for candidate in group {
            hasher.combine(ObjectIdentifier(candidate.part.model!.mesh))
            for column in [candidate.transform.columns.0, candidate.transform.columns.1,
                           candidate.transform.columns.2, candidate.transform.columns.3] {
                hasher.combine(column)
            }
            hasher.combine(candidate.uv)
        }
        let key = hasher.finalize()
        if let cached = mergedMeshes[key] { return cached }

        var data = MeshData()
        for candidate in group {
            let transform = candidate.transform
            let linear = simd_float3x3(SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
                                       SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
                                       SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z))
            let normalMatrix = linear.inverse.transpose
            // A mirrored part (negative scale) would come out inside out: flip its winding.
            let mirrored = linear.determinant < 0
            let base = UInt32(data.positions.count)
            for p in candidate.mesh.positions {
                let q = transform * SIMD4(p, 1)
                data.positions.append(SIMD3(q.x, q.y, q.z))
            }
            for n in candidate.mesh.normals {
                let m = normalMatrix * n
                let length = simd_length(m)
                data.normals.append(length > 1e-6 ? m / length : [0, 1, 0])
            }
            if let uv = candidate.uv {
                data.uvs.append(contentsOf: repeatElement(uv, count: candidate.mesh.positions.count))
            } else {
                data.uvs.append(contentsOf: candidate.mesh.uvs)
            }
            let indices = candidate.mesh.indices
            var i = 0
            while i + 2 < indices.count {
                if mirrored {
                    data.indices += [indices[i] + base, indices[i + 2] + base, indices[i + 1] + base]
                } else {
                    data.indices += [indices[i] + base, indices[i + 1] + base, indices[i + 2] + base]
                }
                i += 3
            }
        }
        guard let resource = data.resource(named: mergedName) else { return nil }
        mergedMeshes[key] = resource
        return resource
    }

    // MARK: - Geometry and materials

    /// Mesh contents by resource (kept alive here, so an identifier is never reused for another mesh).
    private static var geometry: [ObjectIdentifier: (mesh: MeshResource, data: MeshData?)] = [:]

    /// A mesh's triangles as plain arrays (every instance and part, in the mesh's own space).
    static func meshData(_ mesh: MeshResource) -> MeshData? {
        let id = ObjectIdentifier(mesh)
        if let hit = geometry[id] { return hit.data }
        var data = MeshData()
        let contents = mesh.contents
        for instance in contents.instances {
            guard let model = contents.models[instance.model] else { continue }
            let transform = instance.transform
            let linear = simd_float3x3(SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
                                       SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
                                       SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z))
            let normalMatrix = linear.inverse.transpose
            for part in model.parts {
                guard let indices = part.triangleIndices?.elements else { continue }
                let positions = part.positions.elements
                let normals = part.normals?.elements
                let uvs = part.textureCoordinates?.elements
                let base = UInt32(data.positions.count)
                for (i, p) in positions.enumerated() {
                    let q = transform * SIMD4(p, 1)
                    data.positions.append(SIMD3(q.x, q.y, q.z))
                    let n = normals.map { normalMatrix * $0[i] } ?? [0, 1, 0]
                    data.normals.append(simd_length(n) > 1e-6 ? simd_normalize(n) : [0, 1, 0])
                    data.uvs.append(uvs?[i] ?? .zero)
                }
                data.indices += indices.map { $0 + base }
            }
        }
        let result = data.isEmpty ? nil : data
        geometry[id] = (mesh, result)
        return result
    }

    /// A key that's equal for materials that draw the same, or nil for ones that can't be merged
    /// (textured materials: the face, painted signs).
    static func fingerprint(_ material: any RealityKit.Material) -> String? {
        switch material {
        case let custom as CustomMaterial:
            guard custom.baseColor.texture == nil, custom.emissiveColor.texture == nil else { return nil }
            return "custom|\(components(custom.baseColor.tint))|\(custom.custom.value)|\(custom.faceCulling)|\(custom.blending)|\(custom.lightingModel)"
        case let pbr as PhysicallyBasedMaterial:
            guard pbr.baseColor.texture == nil, pbr.emissiveColor.texture == nil else { return nil }
            return "pbr|\(components(pbr.baseColor.tint))|\(pbr.roughness.scale)|\(pbr.metallic.scale)|\(pbr.faceCulling)|\(pbr.blending)"
        case let unlit as UnlitMaterial:
            guard unlit.color.texture == nil else { return nil }
            return "unlit|\(components(unlit.color.tint))|\(unlit.faceCulling)|\(unlit.blending)"
        default:
            return nil
        }
    }

    private static func components(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%.4f,%.4f,%.4f,%.4f", r, g, b, a)
    }
}

// MARK: - Atlas

/// Every toon color the merged parts use, one texel each, in one texture shared by every actor
/// (the ink style). New colors are added as models are built and the texture is rewritten.
@MainActor
final class PartAtlas {
    static let shared = PartAtlas()
    static let width = 1024

    private var texels: [SIMD4<UInt8>] = []
    private var lookup: [SIMD4<UInt8>: Int] = [:]
    private var dirty = false
    private let texture: LowLevelTexture?
    private let base: TextureResource?
    private let glow: TextureResource?
    private let queue: (any MTLCommandQueue)?
    private let staging: (any MTLBuffer)?
    private var cachedMaterial: (any RealityKit.Material)?

    private init() {
        let device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()
        staging = device?.makeBuffer(length: Self.width * 4, options: .storageModeShared)
        let descriptor = LowLevelTexture.Descriptor(textureType: .type2D, pixelFormat: .rgba8Unorm_srgb, width: Self.width,
                                                    height: 1, depth: 1, mipmapLevelCount: 1, textureUsage: [.shaderRead])
        texture = ArtStyle.isInk ? try? LowLevelTexture(descriptor: descriptor) : nil
        base = texture.flatMap { try? TextureResource(from: $0) }
        glow = Self.black()
    }

    /// The texel for `color`, or nil once the atlas is full.
    func uv(for color: UIColor) -> SIMD2<Float>? {
        guard texture != nil else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> UInt8 { UInt8((min(max(v, 0), 1) * 255).rounded()) }
        let texel = SIMD4(byte(r), byte(g), byte(b), 255)
        let index: Int
        if let known = lookup[texel] {
            index = known
        } else {
            guard texels.count < Self.width else { return nil }
            index = texels.count
            texels.append(texel)
            lookup[texel] = index
            dirty = true
        }
        return [(Float(index) + 0.5) / Float(Self.width), 0.5]
    }

    var material: (any RealityKit.Material)? {
        if let cachedMaterial { return cachedMaterial }
        guard let base, let glow, let material = InkMaterials.atlas(base: base, glow: glow, doubleSided: false) else {
            return nil
        }
        cachedMaterial = material
        return material
    }

    /// Uploads colors added since the last flush.
    func flush() {
        guard dirty, let texture, let queue, let staging, let commandBuffer = queue.makeCommandBuffer() else { return }
        dirty = false
        let bytes = staging.contents().bindMemory(to: SIMD4<UInt8>.self, capacity: Self.width)
        for (i, texel) in texels.enumerated() { bytes[i] = texel }
        let target = texture.replace(using: commandBuffer)
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.copy(from: staging, sourceOffset: 0, sourceBytesPerRow: Self.width * 4, sourceBytesPerImage: Self.width * 4,
                      sourceSize: MTLSize(width: Self.width, height: 1, depth: 1),
                      to: target, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
            blit.endEncoding()
        }
        commandBuffer.commit()
    }

    /// The atlas material's glow slot: nothing glows.
    private static func black() -> TextureResource? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource(image: cgImage, options: .init(semantic: .color, mipmapsMode: .none))
    }
}
