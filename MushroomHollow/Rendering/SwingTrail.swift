import Metal
import RealityKit
import UIKit

/// A glowing ribbon swept by a blade: shows where the edge was a split second ago, like the
/// sword trails in Flyff. The owner feeds it hilt/tip positions (oldest first) every frame.
@MainActor
final class SwingTrail {
    static let segments = 24

    let entity = ModelEntity()
    private let mesh: LowLevelMesh?
    private var tint: SIMD3<Float>?

    private struct Vertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
        var uv: SIMD2<Float>
    }

    init() {
        mesh = Self.makeMesh()
        if let mesh, let resource = try? MeshResource(from: mesh) {
            entity.model = ModelComponent(mesh: resource, materials: [Self.makeMaterial()])
        }
        entity.components.set(DynamicLightShadowComponent(castsShadow: false))
        entity.components.set(OpacityComponent(opacity: 1))
        entity.isEnabled = false
        setTint(.white)
    }

    /// Only touches the material when the color actually changes (on re-equipping), not per frame.
    func setTint(_ color: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let tint = SIMD3(Float(r), Float(g), Float(b))
        guard tint != self.tint else { return }
        self.tint = tint
        if var custom = entity.model?.materials.first as? CustomMaterial {
            custom.custom.value = SIMD4(tint, 1)
            entity.model?.materials = [custom]
        }
    }

    func hide() {
        entity.isEnabled = false
    }

    /// Rebuilds the ribbon through `samples` (oldest first, in the parent's space).
    /// `strength` fades the whole trail out once the swing is over.
    func show(_ samples: [(hilt: SIMD3<Float>, tip: SIMD3<Float>)], strength: Float) {
        guard let mesh, samples.count > 1, strength > 0 else {
            hide()
            return
        }
        let count = min(samples.count, Self.segments + 1)
        var low = samples[0].tip, high = samples[0].tip
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let vertices = raw.bindMemory(to: Vertex.self)
            for i in 0..<count {
                let sample = samples[i]
                let u = Float(i) / Float(count - 1)
                let normal = simd_normalize(simd_cross(sample.tip - sample.hilt, [0, 1, 0]) + [0, 0.001, 0])
                vertices[i * 2] = Vertex(position: sample.hilt, normal: normal, uv: [u, 0])
                vertices[i * 2 + 1] = Vertex(position: sample.tip, normal: normal, uv: [u, 1])
                low = simd_min(low, simd_min(sample.hilt, sample.tip))
                high = simd_max(high, simd_max(sample.hilt, sample.tip))
            }
        }
        mesh.parts.replaceAll([
            LowLevelMesh.Part(indexCount: (count - 1) * 6, topology: .triangle, bounds: BoundingBox(min: low, max: high)),
        ])
        // The fade rides on opacity, so the material never changes mid-swing.
        entity.components.set(OpacityComponent(opacity: min(1, strength)))
        entity.isEnabled = true
    }

    private static func makeMesh() -> LowLevelMesh? {
        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexCapacity = (segments + 1) * 2
        descriptor.indexCapacity = segments * 6
        descriptor.indexType = .uint16
        descriptor.vertexAttributes = [
            .init(semantic: .position, format: .float3, offset: MemoryLayout<Vertex>.offset(of: \.position)!),
            .init(semantic: .normal, format: .float3, offset: MemoryLayout<Vertex>.offset(of: \.normal)!),
            .init(semantic: .uv0, format: .float2, offset: MemoryLayout<Vertex>.offset(of: \.uv)!),
        ]
        descriptor.vertexLayouts = [.init(bufferIndex: 0, bufferStride: MemoryLayout<Vertex>.stride)]
        guard let mesh = try? LowLevelMesh(descriptor: descriptor) else { return nil }
        mesh.withUnsafeMutableIndices { raw in
            let indices = raw.bindMemory(to: UInt16.self)
            for i in 0..<segments {
                let a = UInt16(i * 2), b = a + 1, c = a + 2, d = a + 3
                for (offset, index) in [a, c, b, b, c, d].enumerated() {
                    indices[i * 6 + offset] = index
                }
            }
        }
        return mesh
    }

    private static func makeMaterial() -> any RealityKit.Material {
        guard let library = Materials.shaderLibrary,
              var material = try? CustomMaterial(surfaceShader: .init(named: "swingTrail", in: library), lightingModel: .unlit)
        else {
            var fallback = UnlitMaterial(color: .white)
            fallback.blending = .transparent(opacity: 0.4)
            fallback.faceCulling = .none
            return fallback
        }
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        material.faceCulling = .none
        return material
    }
}
