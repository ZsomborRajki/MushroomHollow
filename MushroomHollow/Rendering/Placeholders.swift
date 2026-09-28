import Metal
import RealityKit
import UIKit

/// Colors for the placeholder art. Swap for real assets later; keep the mood.
enum Palette {
    static let moss = UIColor(red: 0.24, green: 0.36, blue: 0.16, alpha: 1)
    static let darkMoss = UIColor(red: 0.17, green: 0.28, blue: 0.12, alpha: 1)
    static let dirt = UIColor(red: 0.42, green: 0.33, blue: 0.22, alpha: 1)
    static let bark = UIColor(red: 0.30, green: 0.21, blue: 0.14, alpha: 1)
    static let darkBark = UIColor(red: 0.21, green: 0.14, blue: 0.09, alpha: 1)
    static let stem = UIColor(red: 0.90, green: 0.84, blue: 0.70, alpha: 1)
    static let capRed = UIColor(red: 0.78, green: 0.18, blue: 0.14, alpha: 1)
    static let capBrown = UIColor(red: 0.62, green: 0.38, blue: 0.20, alpha: 1)
    static let capSpot = UIColor(red: 0.98, green: 0.96, blue: 0.90, alpha: 1)
    static let door = UIColor(red: 0.33, green: 0.20, blue: 0.11, alpha: 1)
    static let windowGlow = UIColor(red: 1.00, green: 0.80, blue: 0.42, alpha: 1)
    static let glowCap = UIColor(red: 0.45, green: 0.95, blue: 0.85, alpha: 1)
    static let leaf = UIColor(red: 0.45, green: 0.52, blue: 0.20, alpha: 1)
    static let deadLeaf = UIColor(red: 0.62, green: 0.42, blue: 0.20, alpha: 1)
    static let pebble = UIColor(red: 0.52, green: 0.52, blue: 0.48, alpha: 1)
    static let shelfFungus = UIColor(red: 0.85, green: 0.62, blue: 0.32, alpha: 1)

    static let tunic = UIColor(red: 0.20, green: 0.55, blue: 0.55, alpha: 1)
    static let skin = UIColor(red: 0.96, green: 0.80, blue: 0.66, alpha: 1)
    static let boots = UIColor(red: 0.30, green: 0.20, blue: 0.14, alpha: 1)
    static let eye = UIColor(red: 0.08, green: 0.06, blue: 0.05, alpha: 1)

    static let snailBody = UIColor(red: 0.80, green: 0.78, blue: 0.52, alpha: 1)
    static let snailShell = UIColor(red: 0.55, green: 0.33, blue: 0.18, alpha: 1)
    static let snailShellLight = UIColor(red: 0.74, green: 0.52, blue: 0.30, alpha: 1)
    static let slugBody = UIColor(red: 0.64, green: 0.36, blue: 0.16, alpha: 1)
    static let slugRidge = UIColor(red: 0.46, green: 0.24, blue: 0.10, alpha: 1)
    static let beetleShell = UIColor(red: 0.14, green: 0.22, blue: 0.42, alpha: 1)
    static let sporeBody = UIColor(red: 0.45, green: 0.30, blue: 0.55, alpha: 1)
    static let sporeGlow = UIColor(red: 0.70, green: 1.00, blue: 0.45, alpha: 1)
    static let owlFeather = UIColor(red: 0.45, green: 0.34, blue: 0.24, alpha: 1)
    static let owlEye = UIColor(red: 1.00, green: 0.78, blue: 0.20, alpha: 1)
}

/// Shared unit meshes; every placeholder part is one of these, scaled.
@MainActor
enum Meshes {
    static let sphere = MeshResource.generateSphere(radius: 1)
    static let cylinder = MeshResource.generateCylinder(height: 1, radius: 1)
    static let cone = MeshResource.generateCone(height: 1, radius: 1)
    static let box = MeshResource.generateBox(size: 1)
    static let roundedBox = MeshResource.generateBox(size: 1, cornerRadius: 0.25)
    /// Flat annulus in the XZ plane, outer radius 1.
    static let ring = makeRing(inner: 0.82, outer: 1, segments: 64)

    private static func makeRing(inner: Float, outer: Float, segments: Int) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for i in 0...segments {
            let a = Float(i) / Float(segments) * 2 * .pi
            let d = SIMD3<Float>(sin(a), 0, cos(a))
            positions.append(d * inner)
            positions.append(d * outer)
        }
        for i in 0..<UInt32(segments) {
            let v = i * 2
            indices += [v, v + 1, v + 2, v + 1, v + 3, v + 2]
        }
        var descriptor = MeshDescriptor(name: "ring")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(Array(repeating: [0, 1, 0], count: positions.count))
        descriptor.primitives = .triangles(indices)
        return try! MeshResource.generate(from: [descriptor])
    }
}

@MainActor
enum Materials {
    private static var cache: [String: any RealityKit.Material] = [:]

    static func matte(_ color: UIColor, roughness: Float = 0.85) -> any RealityKit.Material {
        let key = "matte-\(color.description)-\(roughness)"
        if let cached = cache[key] { return cached }
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: 0)
        cache[key] = material
        return material
    }

    static func glossy(_ color: UIColor) -> any RealityKit.Material {
        matte(color, roughness: 0.25)
    }

    static func glow(_ color: UIColor) -> any RealityKit.Material {
        let key = "glow-\(color.description)"
        if let cached = cache[key] { return cached }
        let material = UnlitMaterial(color: color)
        cache[key] = material
        return material
    }

    /// The app's compiled Metal shaders (Shaders/*.metal).
    static let shaderLibrary: (any MTLLibrary)? = MTLCreateSystemDefaultDevice()?.makeDefaultLibrary()

    /// Grass with Metal wind sway and a height/position color gradient.
    static let grass: any RealityKit.Material = {
        guard let library = shaderLibrary,
              var material = try? CustomMaterial(
                  surfaceShader: .init(named: "grassSurface", in: library),
                  geometryModifier: .init(named: "grassSway", in: library),
                  lightingModel: .lit)
        else {
            var fallback = PhysicallyBasedMaterial()
            fallback.baseColor = .init(tint: Palette.leaf)
            fallback.faceCulling = .none
            return fallback
        }
        material.faceCulling = .none
        return material
    }()

    /// Gradient sky, seen from inside a sphere.
    static let sky: any RealityKit.Material = {
        guard let library = shaderLibrary,
              var material = try? CustomMaterial(
                  surfaceShader: .init(named: "skyGradient", in: library),
                  lightingModel: .unlit)
        else {
            var fallback = UnlitMaterial(color: UIColor(red: 0.45, green: 0.58, blue: 0.45, alpha: 1))
            fallback.faceCulling = .front
            return fallback
        }
        material.faceCulling = .front
        return material
    }()
}

extension Entity {
    /// Adds a scaled unit-mesh part as a child and returns it.
    @discardableResult
    func addPart(
        _ mesh: MeshResource,
        _ material: any RealityKit.Material,
        at position: SIMD3<Float>,
        scale: SIMD3<Float>,
        rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    ) -> ModelEntity {
        let part = ModelEntity(mesh: mesh, materials: [material])
        part.transform = Transform(scale: scale, rotation: rotation, translation: position)
        addChild(part)
        return part
    }

    func addSphere(_ material: any RealityKit.Material, at position: SIMD3<Float>, radius: Float, squash: SIMD3<Float> = .one) {
        addPart(Meshes.sphere, material, at: position, scale: squash * radius)
    }

    /// A unit cylinder is 1 tall along Y; this sizes it by radius and height.
    func addCylinder(_ material: any RealityKit.Material, at position: SIMD3<Float>, radius: Float, height: Float, rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)) {
        addPart(Meshes.cylinder, material, at: position, scale: [radius, height, radius], rotation: rotation)
    }
}
