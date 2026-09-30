import Foundation
import GameCore
import Metal
import RealityKit
import UIKit

/// Which look the world is drawn in. Chosen at launch (materials are built once and cached):
/// a client preference, never part of `PlayerProfile`. DEBUG builds also take `-style ink|classic`.
nonisolated enum ArtStyle: String, CaseIterable, Sendable {
    /// Hand-drawn, like the "2D café": bold black marker lines, matte flat cartoon fills (see InkStyle).
    case ink
    /// The original lit, shadowed, physically based look.
    case classic

    static let defaultsKey = "artStyle"

    static let current: ArtStyle = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-style"), arguments.indices.contains(index + 1),
           let style = ArtStyle(rawValue: arguments[index + 1]) {
            return style
        }
        #endif
        return UserDefaults.standard.string(forKey: defaultsKey).flatMap(ArtStyle.init(rawValue:)) ?? .ink
    }()

    static var isInk: Bool { current == .ink }
}

/// Tuning for the ink style.
nonisolated enum InkStyle {
    /// Lines, hatching, and outlines are redrawn this many times a second ("on threes" at 24 fps).
    /// World.metal's `boilFrame` must match.
    static let boilRate: Float = 8
    static let hullName = "inkHull"

    /// Outline width (meters, as seen from 8 m) for an actor: bold on the boss, finer on small critters.
    static func hullWidth(for kind: EntityKind) -> Float {
        switch kind {
        case .player: 0.03
        case .npc: 0.03
        case .mob(.owl): 0.08
        case .mob(.moldywarp): 0.06
        case let .mob(mob): min(0.042, max(0.022, mob.radius * 0.07))
        }
    }

    /// Outline width for static scenery and the town (like `hullWidth`, meters as seen from 8 m).
    static let sceneryHullWidth: Float = 0.04

    /// Radius of the hatched blob shadow under an actor.
    static func shadowRadius(for kind: EntityKind) -> Float {
        switch kind {
        case .player: 0.42
        case .npc: 0.5
        case .mob(.owl): 3.2
        case .mob(.moldywarp): 2.6
        case let .mob(mob): mob.radius * 1.25
        }
    }
}

// MARK: - Lighting

/// The toon materials are unlit, so the sun doesn't reach them: instead every ink material samples
/// this tiny shared texture (lit and shadow multipliers, ink color, key direction), and `Atmosphere`
/// rewrites it as the day turns. One texture update restyles every material at once, with no
/// per-material parameters to push.
@MainActor
final class ToonLighting {
    struct Values: Equatable {
        var key = SIMD3<Float>(1, 1, 1)
        var shadow = SIMD3<Float>(0.8, 0.75, 0.88)
        var ink = SIMD3<Float>(0.008, 0.007, 0.007)
        var direction = simd_normalize(SIMD3<Float>(0.45, 0.8, 0.4))
    }

    static let shared = ToonLighting()

    let resource: TextureResource?
    private let texture: LowLevelTexture?
    private let queue: (any MTLCommandQueue)?
    private let staging: (any MTLBuffer)?
    private var current: Values?

    private init() {
        let device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()
        staging = device?.makeBuffer(length: 4 * 4 * MemoryLayout<Float16>.stride, options: .storageModeShared)
        let descriptor = LowLevelTexture.Descriptor(textureType: .type2D, pixelFormat: .rgba16Float, width: 4, height: 1,
                                                    depth: 1, mipmapLevelCount: 1, textureUsage: [.shaderRead])
        texture = try? LowLevelTexture(descriptor: descriptor)
        resource = texture.flatMap { try? TextureResource(from: $0) }
        set(Values())
    }

    func set(_ values: Values) {
        guard values != current, let texture, let queue, let staging,
              let commandBuffer = queue.makeCommandBuffer() else { return }
        current = values
        let texels: [SIMD4<Float>] = [SIMD4(values.key, 1), SIMD4(values.shadow, 1),
                                      SIMD4(values.ink, 1), SIMD4(values.direction, 1)]
        let halves = staging.contents().bindMemory(to: Float16.self, capacity: 16)
        for (i, texel) in texels.enumerated() {
            for c in 0..<4 { halves[i * 4 + c] = Float16(texel[c]) }
        }
        let target = texture.replace(using: commandBuffer)
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.copy(from: staging, sourceOffset: 0, sourceBytesPerRow: 4 * 4 * MemoryLayout<Float16>.stride,
                      sourceBytesPerImage: 4 * 4 * MemoryLayout<Float16>.stride, sourceSize: MTLSize(width: 4, height: 1, depth: 1),
                      to: target, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
            blit.endEncoding()
        }
        commandBuffer.commit()
    }
}

// MARK: - Materials

/// The ink style's materials (Shaders/World.metal). Each returns nil if the shaders can't be
/// loaded, and the caller falls back to the classic material.
@MainActor
enum InkMaterials {
    private static var cache: [String: any RealityKit.Material] = [:]

    private static func make(_ surface: String, geometry: String? = nil) -> CustomMaterial? {
        guard let library = Materials.shaderLibrary, let lighting = ToonLighting.shared.resource,
              var material = try? CustomMaterial(
                  surfaceShader: .init(named: surface, in: library),
                  geometryModifier: geometry.map { .init(named: $0, in: library) },
                  lightingModel: .unlit)
        else { return nil }
        material.custom = .init(value: [0, 0, 1, 1], texture: .init(lighting))
        return material
    }

    private static func cached(_ key: String, _ build: () -> (any RealityKit.Material)?) -> (any RealityKit.Material)? {
        if let hit = cache[key] { return hit }
        guard let material = build() else { return nil }
        cache[key] = material
        return material
    }

    /// Matte flat fill in the color's cartoon version, with one crisp shadow tone.
    static func toon(_ color: UIColor) -> (any RealityKit.Material)? {
        cached("toon-\(color.description)") {
            guard var material = make("toonSurface") else { return nil }
            material.baseColor = .init(tint: color)
            material.custom.value = [0, 1, 0, 1]
            if let fingerprint = PartMerger.fingerprint(material) { toonColors[fingerprint] = color }
            return material
        }
    }

    /// Opaque toon materials by `PartMerger.fingerprint`, so merged parts can move into the atlas.
    private static var toonColors: [String: UIColor] = [:]

    static func toonColor(fingerprint: String) -> UIColor? {
        toonColors[fingerprint]
    }

    static func translucent(_ color: UIColor, opacity: Float) -> (any RealityKit.Material)? {
        cached("translucent-\(color.description)-\(opacity)") {
            guard var material = make("toonSurface") else { return nil }
            material.baseColor = .init(tint: color)
            material.custom.value = [0, 1, 0, opacity]
            material.blending = .transparent(opacity: .init(floatLiteral: 1))
            material.faceCulling = .none
            return material
        }
    }

    /// A painted texture (the face), toon shaded in the colors it was painted in.
    static func textured(_ texture: TextureResource) -> (any RealityKit.Material)? {
        guard var material = make("toonTextured") else { return nil }
        material.baseColor = .init(tint: .white, texture: .init(texture))
        material.custom.value = [0, 0, 0, 1]
        return material
    }

    /// Batched scenery and merged actor parts: the color atlas, glowing colors in the emissive atlas
    /// (scenery's wobble is baked in, see `InkWobble`).
    static func atlas(base: TextureResource, glow: TextureResource, doubleSided: Bool) -> (any RealityKit.Material)? {
        guard var material = make("toonAtlas") else { return nil }
        material.baseColor = .init(tint: .white, texture: .init(base))
        material.emissiveColor = .init(color: .black, texture: .init(glow))
        material.custom.value = [0, 1, 0, 1]
        if doubleSided { material.faceCulling = .none }
        return material
    }

    /// The forest floor, with its contact shadows (white = shadow).
    /// The forest floor: the painted ground (base color), the surface mask (roughness slot: r contact
    /// shadow, g dirt, b sand; see `GroundPainter.paintSurfaceMask`), and the repeating block detail
    /// (emissive slot, `InkPainter.groundDetail`).
    static func ground(_ painting: TextureResource, surfaces: TextureResource, detail: TextureResource) -> (any RealityKit.Material)? {
        guard var material = make("inkGround") else { return nil }
        material.baseColor = .init(tint: .white, texture: .init(painting))
        material.roughness = .init(scale: 1, texture: .init(surfaces))
        material.emissiveColor = .init(color: .white, texture: .init(detail))
        material.custom.value = [0, 0, 0, 1]
        return material
    }

    static let grass: (any RealityKit.Material)? = {
        guard var material = make("grassInk", geometry: "grassSway") else { return nil }
        material.faceCulling = .none
        return material
    }()

    static let water: (any RealityKit.Material)? = {
        guard var material = make("waterInk") else { return nil }
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        return material
    }()

    /// The drawn sky (inside of a sphere): paper, a scalloped canopy line, drawn stars.
    static let sky: (any RealityKit.Material)? = {
        guard var material = make("inkSky") else { return nil }
        material.faceCulling = .front
        return material
    }()

    /// The outline shell for inverted-hull outlines. `weightedByUV`: each vertex's u scales the
    /// width (batched scenery, where thin stems want thin lines).
    static func hull(width: Float, weightedByUV: Bool = false) -> (any RealityKit.Material)? {
        cached("hull-\(width)-\(weightedByUV)") {
            guard var material = make("inkHullSurface", geometry: "inkHullPush") else { return nil }
            material.custom.value = [width, weightedByUV ? 1 : 0, 0, 1]
            material.faceCulling = .front
            return material
        }
    }

    static let blobShadow: (any RealityKit.Material)? = {
        guard let texture = InkPainter.blobShadow(), var material = make("inkBlobShadow") else { return nil }
        material.baseColor = .init(tint: .white, texture: .init(texture))
        material.custom.value = [0, 0, 0, 1]
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        return material
    }()
}

// MARK: - Wobble

/// Nothing drawn by hand is perfectly round: static scenery gets its vertices nudged by smooth
/// noise of their position, baked in when the chunk is built (it used to be a per-frame vertex
/// shader, recomputing the same offsets every frame). Every vertex at one spot moves the same way,
/// so hard edges don't split.
nonisolated enum InkWobble {
    /// How far a vertex can move, in meters.
    static let amount: Float = 0.05

    static func apply(to positions: inout [SIMD3<Float>]) {
        let frequency = 0.08 / amount
        for i in positions.indices {
            let m = positions[i] * frequency
            let offset = SIMD3(noise(m), noise(m + 17.3), noise(m + 41.7)) - 0.5
            positions[i] += offset * 2 * amount
        }
    }

    /// Smooth value noise, 0...1.
    private static func noise(_ p: SIMD3<Float>) -> Float {
        let i = p.rounded(.down), f = p - i
        let s = f * f * (3 - 2 * f)
        let x = Int32(clamping: Int(i.x)), y = Int32(clamping: Int(i.y)), z = Int32(clamping: Int(i.z))
        func h(_ dx: Int32, _ dy: Int32, _ dz: Int32) -> Float { hash(x &+ dx, y &+ dy, z &+ dz) }
        let a = lerp(h(0, 0, 0), h(1, 0, 0), s.x), b = lerp(h(0, 1, 0), h(1, 1, 0), s.x)
        let c = lerp(h(0, 0, 1), h(1, 0, 1), s.x), d = lerp(h(0, 1, 1), h(1, 1, 1), s.x)
        return lerp(lerp(a, b, s.y), lerp(c, d, s.y), s.z)
    }

    private static func hash(_ x: Int32, _ y: Int32, _ z: Int32) -> Float {
        var n = UInt32(bitPattern: x) &* 0x8DA6_B343 ^ UInt32(bitPattern: y) &* 0xD816_3841 ^ UInt32(bitPattern: z) &* 0xCB1A_B31F
        n ^= n >> 16
        n &*= 0x7FEB_352D
        n ^= n >> 15
        n &*= 0x846C_A68B
        n ^= n >> 16
        return Float(n >> 8) / 16_777_216
    }

    private static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
}

// MARK: - Outlines and shadows

extension Entity {
    /// Gives every solid part under this entity an inverted-hull outline (a child sharing its mesh).
    /// Safe to call again after parts are added (gear, a glider): outlined parts are skipped.
    /// Tiny bits (eye glints) and glowing or see-through parts get none.
    func addInkHulls(width: Float, minimumSize: Float = 0.05) {
        guard ArtStyle.isInk, let material = InkMaterials.hull(width: width) else { return }
        addInkHulls(material, root: self, minimumSize: minimumSize)
    }

    private func addInkHulls(_ material: any RealityKit.Material, root: Entity, minimumSize: Float) {
        for child in Array(children) where child.name != InkStyle.hullName {
            if let part = child as? ModelEntity, let model = part.model, !model.materials.isEmpty,
               !part.name.hasSuffix(PartMerger.noHullSuffix),
               model.materials.allSatisfy(Self.takesInkOutline),
               !part.children.contains(where: { $0.name == InkStyle.hullName }) {
                let size = model.mesh.bounds.extents * part.scale(relativeTo: root)
                if max(size.x, size.y, size.z) >= minimumSize {
                    let hull = ModelEntity(mesh: InkHullMesh.smoothed(model.mesh),
                                           materials: Array(repeating: material, count: model.materials.count))
                    hull.name = InkStyle.hullName
                    hull.components.set(DynamicLightShadowComponent(castsShadow: false))
                    part.addChild(hull)
                }
            }
            child.addInkHulls(material, root: root, minimumSize: minimumSize)
        }
    }

    /// Opaque toon surfaces only (glowing `UnlitMaterial`s and see-through parts stay clean).
    static func takesInkOutline(_ material: any RealityKit.Material) -> Bool {
        guard let custom = material as? CustomMaterial, custom.faceCulling != .front else { return false }
        if case .opaque = custom.blending { return true }
        return false
    }

    /// A flat drawn shadow on the ground, for actors (the ink style has no shadow maps).
    static func makeBlobShadow(radius: Float) -> ModelEntity? {
        guard let material = InkMaterials.blobShadow else { return nil }
        let shadow = ModelEntity(mesh: InkPainter.shadowPlane, materials: [material])
        shadow.name = "blobShadow"
        shadow.scale = SIMD3(repeating: radius)
        shadow.position.y = 0.04
        shadow.components.set(DynamicLightShadowComponent(castsShadow: false))
        return shadow
    }
}

// MARK: - Hull meshes

/// Outline shells want smooth normals: pushed along a box's face normals, the faces drift apart and
/// the outline breaks at every corner. These copies share the original's triangles, with each normal
/// averaged over every vertex at that spot (hard edges and all), so the shell inflates in one piece.
@MainActor
enum InkHullMesh {
    /// By source mesh (kept alive here, so an identifier is never reused for another mesh).
    private static var cache: [ObjectIdentifier: (source: MeshResource, hull: MeshResource)] = [:]

    static func smoothed(_ mesh: MeshResource) -> MeshResource {
        let id = ObjectIdentifier(mesh)
        if let hit = cache[id] { return hit.hull }
        let hull = PartMerger.meshData(mesh).flatMap { smoothed($0).resource(named: InkStyle.hullName) } ?? mesh
        cache[id] = (mesh, hull)
        return hull
    }

    /// The same triangles with normals averaged per position (to about a millimeter). Triangles are
    /// weighted by area, so a sliver doesn't tip a corner.
    static func smoothed(_ data: MeshData) -> MeshData {
        var sums: [SIMD3<Int32>: SIMD3<Float>] = [:]
        func key(_ p: SIMD3<Float>) -> SIMD3<Int32> {
            SIMD3(Int32(clamping: Int((p.x * 1000).rounded())), Int32(clamping: Int((p.y * 1000).rounded())),
                  Int32(clamping: Int((p.z * 1000).rounded())))
        }
        var i = 0
        while i + 2 < data.indices.count {
            let a = data.positions[Int(data.indices[i])], b = data.positions[Int(data.indices[i + 1])]
            let c = data.positions[Int(data.indices[i + 2])]
            let face = simd_cross(b - a, c - a)
            for p in [a, b, c] { sums[key(p), default: .zero] += face }
            i += 3
        }
        var result = data
        for (index, p) in data.positions.enumerated() {
            let sum = sums[key(p)] ?? .zero
            result.normals[index] = simd_length(sum) > 1e-9 ? simd_normalize(sum) : data.normals[index]
        }
        return result
    }
}
