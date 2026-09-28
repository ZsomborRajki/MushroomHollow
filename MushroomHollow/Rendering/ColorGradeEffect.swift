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

/// RealityKit post-process pass: a Metal compute kernel that color grades the frame for
/// the time of day and adds depth-based forest haze.
nonisolated struct ColorGradeEffect: PostProcessEffect, @unchecked Sendable {
    let settings: GradeSettings
    private var fogPipeline: (any MTLComputePipelineState)?
    private var plainPipeline: (any MTLComputePipelineState)?

    init(settings: GradeSettings) {
        self.settings = settings
    }

    mutating func prepare(for device: any MTLDevice) {
        guard let library = device.makeDefaultLibrary() else { return }
        if let function = library.makeFunction(name: "colorGradeFog") {
            fogPipeline = try? device.makeComputePipelineState(function: function)
        }
        if let function = library.makeFunction(name: "colorGrade") {
            plainPipeline = try? device.makeComputePipelineState(function: function)
        }
    }

    mutating func postProcess(context: borrowing PostProcessEffectContext<any MTLCommandBuffer>) {
        let depth = context.sourceDepthTexture
        let canFog = depth.textureType == .type2D && depth.pixelFormat.isDepth
        guard let pipeline = (canFog ? fogPipeline : nil) ?? plainPipeline,
              let encoder = context.commandBuffer.makeComputeCommandEncoder()
        else { return }

        var uniforms = settings.get()
        uniforms.settings.z = context.projection.columns.2.z
        uniforms.settings.w = context.projection.columns.3.z

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(context.sourceColorTexture, index: 0)
        if canFog { encoder.setTexture(depth, index: 1) }
        encoder.setTexture(context.targetColorTexture, index: 2)
        encoder.setBytes(&uniforms, length: MemoryLayout<GradeUniforms>.stride, index: 0)

        let width = pipeline.threadExecutionWidth
        let height = max(1, pipeline.maxTotalThreadsPerThreadgroup / width)
        let target = context.targetColorTexture
        encoder.dispatchThreads(MTLSize(width: target.width, height: target.height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1))
        encoder.endEncoding()
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
