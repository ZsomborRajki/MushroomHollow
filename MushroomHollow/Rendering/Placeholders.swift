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
    static let blush = UIColor(red: 1.00, green: 0.55, blue: 0.60, alpha: 1)

    static let ladybugRed = UIColor(red: 0.86, green: 0.12, blue: 0.10, alpha: 1)
    static let bugBlack = UIColor(red: 0.10, green: 0.08, blue: 0.08, alpha: 1)
    static let pillGrey = UIColor(red: 0.52, green: 0.54, blue: 0.60, alpha: 1)
    static let pillDark = UIColor(red: 0.36, green: 0.38, blue: 0.45, alpha: 1)
    static let acornBrown = UIColor(red: 0.72, green: 0.46, blue: 0.20, alpha: 1)
    static let acornCap = UIColor(red: 0.46, green: 0.31, blue: 0.17, alpha: 1)
    static let acornCapDark = UIColor(red: 0.36, green: 0.24, blue: 0.13, alpha: 1)
    static let frogGreen = UIColor(red: 0.36, green: 0.64, blue: 0.26, alpha: 1)
    static let frogBelly = UIColor(red: 0.86, green: 0.90, blue: 0.62, alpha: 1)
    static let beeYellow = UIColor(red: 1.00, green: 0.80, blue: 0.22, alpha: 1)
    static let wingGlass = UIColor(red: 0.90, green: 0.96, blue: 1.00, alpha: 1)
    static let puffWhite = UIColor(red: 0.97, green: 0.97, blue: 0.94, alpha: 1)
    static let dandelionStem = UIColor(red: 0.47, green: 0.62, blue: 0.27, alpha: 1)
    static let turtleShell = UIColor(red: 0.36, green: 0.42, blue: 0.24, alpha: 1)
    static let turtleShellDark = UIColor(red: 0.27, green: 0.31, blue: 0.18, alpha: 1)
    static let turtleSkin = UIColor(red: 0.62, green: 0.70, blue: 0.46, alpha: 1)
    static let newtOrange = UIColor(red: 0.95, green: 0.42, blue: 0.16, alpha: 1)
    static let emberGlow = UIColor(red: 1.00, green: 0.62, blue: 0.22, alpha: 1)
    static let spiderPurple = UIColor(red: 0.38, green: 0.26, blue: 0.50, alpha: 1)
    static let spiderDark = UIColor(red: 0.21, green: 0.16, blue: 0.29, alpha: 1)
    static let spiderGlow = UIColor(red: 0.55, green: 0.90, blue: 1.00, alpha: 1)
    static let mothLilac = UIColor(red: 0.72, green: 0.62, blue: 0.86, alpha: 1)
    static let mothFur = UIColor(red: 0.92, green: 0.87, blue: 0.96, alpha: 1)
    static let hedgehogBrown = UIColor(red: 0.46, green: 0.34, blue: 0.25, alpha: 1)
    static let hedgehogFace = UIColor(red: 0.94, green: 0.83, blue: 0.67, alpha: 1)
    static let quill = UIColor(red: 0.30, green: 0.22, blue: 0.16, alpha: 1)
    static let pinecone = UIColor(red: 0.55, green: 0.36, blue: 0.21, alpha: 1)
    static let pineconeDark = UIColor(red: 0.38, green: 0.24, blue: 0.13, alpha: 1)
    static let mantisPink = UIColor(red: 0.98, green: 0.72, blue: 0.84, alpha: 1)
    static let mantisWhite = UIColor(red: 0.99, green: 0.94, blue: 0.96, alpha: 1)
    static let roseRed = UIColor(red: 0.84, green: 0.14, blue: 0.30, alpha: 1)
    static let rosePink = UIColor(red: 0.96, green: 0.48, blue: 0.58, alpha: 1)
    static let roseDark = UIColor(red: 0.45, green: 0.12, blue: 0.16, alpha: 1)
    static let thornStem = UIColor(red: 0.26, green: 0.44, blue: 0.20, alpha: 1)
    static let stagBrown = UIColor(red: 0.32, green: 0.18, blue: 0.10, alpha: 1)
    static let stagDark = UIColor(red: 0.17, green: 0.10, blue: 0.06, alpha: 1)
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
    static let disc = makeRing(inner: 0, outer: 1, segments: 64)
    /// A very thin annulus, for a trail that circles the world.
    static let trailRing = makeRing(inner: 0.985, outer: 1, segments: 256)
    /// Unit sphere with texture coordinates: u = 0.5 faces +Z, v = 1 at the top.
    static let uvSphere = makeUVSphere(rings: 32, segments: 48)
    /// Round at the top (y = 1), pointed at the bottom (y = -1), radius 1. Hair locks, leaves, petals.
    static let teardrop = lathe([[0, 1], [0.45, 0.92], [0.78, 0.7], [0.95, 0.38], [0.92, 0.05],
                                 [0.75, -0.3], [0.5, -0.6], [0.24, -0.84], [0, -1]], segments: 16)
    private static var toruses: [SIMD2<Float>: MeshResource] = [:]

    /// A ring around the Y axis with the given center-line radius and tube radius.
    static func torus(radius: Float, tube: Float) -> MeshResource {
        let key = SIMD2(radius, tube)
        if let cached = toruses[key] { return cached }
        let profile = (0...16).map { i -> SIMD2<Float> in
            let a = Float.pi / 2 - Float(i) / 16 * 2 * .pi
            return [radius + tube * cos(a), tube * sin(a)]
        }
        let mesh = lathe(profile, segments: 32, closed: true)
        toruses[key] = mesh
        return mesh
    }

    /// Revolves a profile of (radius, y) points around the Y axis. Walking the profile from top to
    /// bottom along an outer wall faces the surface outward; `closed` profiles repeat their first point last.
    static func lathe(_ profile: [SIMD2<Float>], segments: Int = 32, closed: Bool = false) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        let count = profile.count
        for (i, point) in profile.enumerated() {
            let before = closed && i == 0 ? profile[count - 2] : profile[max(i - 1, 0)]
            let after = closed && i == count - 1 ? profile[1] : profile[min(i + 1, count - 1)]
            let tangent = after - before
            var normal = SIMD2<Float>(-tangent.y, tangent.x)
            if !closed, point.x < 0.0001, i == 0 || i == count - 1 {
                normal = [0, i == 0 ? 1 : -1] // poles
            }
            normal = simd_length(normal) > 0 ? simd_normalize(normal) : [0, 1]
            for j in 0...segments {
                let a = Float(j) / Float(segments) * 2 * .pi
                positions.append([point.x * sin(a), point.y, point.x * cos(a)])
                normals.append([normal.x * sin(a), normal.y, normal.x * cos(a)])
                uvs.append([Float(j) / Float(segments), 1 - Float(i) / Float(count - 1)])
            }
        }
        let row = UInt32(segments + 1)
        for i in 0..<UInt32(count - 1) {
            for j in 0..<UInt32(segments) {
                let a = i * row + j, b = a + 1, c = a + row, d = c + 1
                indices += [a, c, d, a, d, b]
            }
        }
        var descriptor = MeshDescriptor(name: "lathe")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return try! MeshResource.generate(from: [descriptor])
    }

    private static func makeUVSphere(rings: Int, segments: Int) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        for i in 0...rings {
            let latitude = Float.pi / 2 - Float(i) / Float(rings) * .pi
            for j in 0...segments {
                let longitude = -Float.pi + Float(j) / Float(segments) * 2 * .pi
                positions.append([cos(latitude) * sin(longitude), sin(latitude), cos(latitude) * cos(longitude)])
                uvs.append([Float(j) / Float(segments), 1 - Float(i) / Float(rings)])
            }
        }
        let row = UInt32(segments + 1)
        for i in 0..<UInt32(rings) {
            for j in 0..<UInt32(segments) {
                let a = i * row + j, b = a + 1, c = a + row, d = c + 1
                indices += [a, c, d, a, d, b]
            }
        }
        var descriptor = MeshDescriptor(name: "uvSphere")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(positions)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return try! MeshResource.generate(from: [descriptor])
    }

    /// A flat wedge in the XZ plane pointing along +Z, radius 1, ±`halfAngle`.
    static func fan(halfAngle: Float, segments: Int = 24) -> MeshResource {
        var positions: [SIMD3<Float>] = [.zero]
        var indices: [UInt32] = []
        for i in 0...segments {
            let a = -halfAngle + 2 * halfAngle * Float(i) / Float(segments)
            positions.append([sin(a), 0, cos(a)])
            if i > 0 { indices += [0, UInt32(i), UInt32(i + 1)] }
        }
        var descriptor = MeshDescriptor(name: "fan")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(Array(repeating: [0, 1, 0], count: positions.count))
        descriptor.primitives = .triangles(indices)
        return try! MeshResource.generate(from: [descriptor])
    }

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

    /// See-through (insect wings, webs).
    static func translucent(_ color: UIColor, opacity: Float) -> any RealityKit.Material {
        let key = "translucent-\(color.description)-\(opacity)"
        if let cached = cache[key] { return cached }
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = 0.3
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        material.faceCulling = .none
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

    /// A cylinder running from one point to another.
    func addRod(_ material: any RealityKit.Material, from start: SIMD3<Float>, to end: SIMD3<Float>, radius: Float) {
        let axis = end - start
        addCylinder(material, at: (start + end) / 2, radius: radius, height: simd_length(axis),
                    rotation: simd_quatf(from: [0, 1, 0], to: simd_normalize(axis)))
    }
}
