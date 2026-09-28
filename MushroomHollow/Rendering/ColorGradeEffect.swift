import Metal
import RealityKit
import Synchronization

/// Uniforms for `PostProcess.metal`; layout must match `GradeUniforms` there.
nonisolated struct GradeUniforms: Sendable {
    /// rgb multiplier, a = saturation
    var tint = SIMD4<Float>(1, 1, 1, 1)
    /// rgb fog color, a = density per meter
    var fog = SIMD4<Float>(0.6, 0.7, 0.5, 0.01)
    /// x = vignette, y = highlight keep, z/w = projection terms (filled per frame)
    var settings = SIMD4<Float>(0.25, 0, 0, 0)
    /// x = boil frame (filled per frame), y = line radius in points, z = boil amount in points, w = paper grain
    var ink = SIMD4<Float>(0, 1, 1, 0)
    /// rgb = line color, a = line strength (0 turns the ink off)
    var inkColor = SIMD4<Float>(0, 0, 0, 0)
    /// x = radians per pixel (filled per frame), y/z = lines fade out between these distances, w = pixels per point (filled per frame)
    var inkShape = SIMD4<Float>(0, 60, 150, 1)
}

/// Thread-safe mailbox between the game (main actor) and the render thread.
nonisolated final class GradeSettings: Sendable {
    private let uniforms = Mutex(GradeUniforms())

    func set(_ value: GradeUniforms) {
        uniforms.withLock { $0 = value }
    }

    func get() -> GradeUniforms {
        uniforms.withLock { $0 }
    }
}

/// RealityKit post-process pass: color grades the frame for the time of day, adds depth-based
/// forest haze, and (in the ink style) draws boiling hand-drawn lines from the depth buffer.
///
/// It draws a full-screen triangle rather than dispatching a compute kernel: the target is often
/// an sRGB or extended-range drawable format that compute can't write, and non-uniform threadgroup
/// dispatch isn't available on every GPU (both trap under Metal validation).
nonisolated struct ColorGradeEffect: PostProcessEffect, @unchecked Sendable {
    let settings: GradeSettings
    private var device: (any MTLDevice)?
    private var library: (any MTLLibrary)?
    /// Keyed by fragment function and target pixel format; nil entries failed to build.
    private var pipelines: [String: (any MTLRenderPipelineState)?] = [:]

    init(settings: GradeSettings) {
        self.settings = settings
    }

    mutating func prepare(for device: any MTLDevice) {
        self.device = device
        library = device.makeDefaultLibrary()
    }

    mutating func postProcess(context: borrowing PostProcessEffectContext<any MTLCommandBuffer>) {
        let source = context.sourceColorTexture
        let target = context.targetColorTexture
        let depth = context.sourceDepthTexture
        let hasDepth = depth.textureType == .type2D && depth.pixelFormat.isDepth
        guard let pipeline = pipeline(hasDepth ? "gradeInkFragment" : "gradeFragment", format: target.pixelFormat) else {
            copy(source, to: target, commandBuffer: context.commandBuffer)
            return
        }

        var uniforms = settings.get()
        let projection = context.projection
        uniforms.settings.z = projection.columns.2.z
        uniforms.settings.w = projection.columns.3.z
        // Sizes are authored in points on a ~400 pt tall landscape phone, and scale with the screen.
        let pointsToPixels = Float(source.height) / 400
        uniforms.ink.x = (Float(context.time) * InkStyle.boilRate).rounded(.down)
        uniforms.ink.y *= pointsToPixels
        uniforms.ink.z *= pointsToPixels
        uniforms.inkShape.x = 2 / (max(projection.columns.1.y, 0.01) * Float(source.height))
        uniforms.inkShape.w = pointsToPixels

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = context.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(source, index: 0)
        if hasDepth { encoder.setFragmentTexture(depth, index: 1) }
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GradeUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private mutating func pipeline(_ fragment: String, format: MTLPixelFormat) -> (any MTLRenderPipelineState)? {
        let key = "\(fragment)-\(format.rawValue)"
        if let cached = pipelines[key] { return cached }
        var state: (any MTLRenderPipelineState)?
        if let device, let library,
           let vertex = library.makeFunction(name: "fullscreenVertex"),
           let fragment = library.makeFunction(name: fragment) {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = format
            state = try? device.makeRenderPipelineState(descriptor: descriptor)
        }
        pipelines[key] = state
        return state
    }

    /// Without a pipeline, at least show the unprocessed frame.
    private func copy(_ source: any MTLTexture, to target: any MTLTexture, commandBuffer: any MTLCommandBuffer) {
        guard source.pixelFormat == target.pixelFormat, source.width == target.width, source.height == target.height,
              let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        blit.copy(from: source, to: target)
        blit.endEncoding()
    }
}

private nonisolated extension MTLPixelFormat {
    var isDepth: Bool {
        switch self {
        case .depth16Unorm, .depth32Float, .depth32Float_stencil8: true
        default: false
        }
    }
}
