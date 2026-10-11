import Foundation
import Metal
import RealityKit
import simd

// Drives the compute passes in PostProcess.metal from RealityKit's post-process callback.

/// Every term of the grade, so each can be dialled back or switched off without touching
/// the shader. Zero disables a term outright.
struct PostProcessSettings: Equatable, Sendable {
    /// Luminance above which a pixel contributes to the bloom.
    var bloomThreshold: Float = 0.62
    var bloomSoftKnee: Float = 0.32
    var bloomStrength: Float = 0.42
    /// Where the renormalised ACES curve is anchored. Lower deepens the toe and hardens the
    /// shoulder; it is a contrast control, not a brightness one, because the curve is
    /// rescaled so white stays white.
    var filmicExposure: Float = 0.50
    var filmicStrength: Float = 0.90
    var contrast: Float = 1.06
    var saturation: Float = 1.04
    var shadowWarmth: Float = 0.020
    var highlightCool: Float = 0.026
    var vignetteStrength: Float = 0.34
    var vignetteRadius: Float = 0.42
    var grainStrength: Float = 0.034
    /// Radial channel split at the frame edge, in normalised units.
    var aberration: Float = 0.0035

    static let photoreal = PostProcessSettings()
    static let off = PostProcessSettings(
        bloomStrength: 0, filmicStrength: 0, contrast: 1, saturation: 1,
        shadowWarmth: 0, highlightCool: 0, vignetteStrength: 0,
        grainStrength: 0, aberration: 0
    )

    /// `-tremorPostFX off` renders the frame ungraded. Comparing the two is the only honest
    /// way to judge the grade, because the room itself changes as the modules are built.
    static var launchSelected: PostProcessSettings {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-proofPostFX"),
           let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-proofPostFX"),
           index + 1 < ProcessInfo.processInfo.arguments.count,
           ProcessInfo.processInfo.arguments[index + 1] == "off" {
            return .off
        }
        #endif
        return .photoreal
    }
}

private struct PostUniforms {
    var texelSize = SIMD2<Float>(0, 0)
    var bloomTexelSize = SIMD2<Float>(0, 0)
    var time: Float = 0
    var bloomThreshold: Float = 0
    var bloomSoftKnee: Float = 0
    var bloomStrength: Float = 0
    var filmicExposure: Float = 0.5
    var filmicStrength: Float = 0
    var contrast: Float = 1
    var saturation: Float = 1
    var shadowWarmth: Float = 0
    var highlightCool: Float = 0
    var vignetteStrength: Float = 0
    var vignetteRadius: Float = 0
    var grainStrength: Float = 0
    var aberration: Float = 0
    var decodeSRGB: UInt32 = 0
    var encodeSRGB: UInt32 = 0
}

/// Not main-actor isolated on purpose: RealityKit invokes the post-process callback on its
/// own render thread, once per frame, and never concurrently with itself.
final class PostProcessPipeline: @unchecked Sendable {

    var settings: PostProcessSettings = .photoreal

    private let brightPass: MTLComputePipelineState
    private let blur: MTLComputePipelineState
    private let composite: MTLComputePipelineState

    private var bloomA: MTLTexture?
    private var bloomB: MTLTexture?
    private var output: MTLTexture?
    private var frame: Float = 0

    /// Bloom runs at an eighth of each axis — a sixty-fourth of the pixels — which is what
    /// keeps a wide blur affordable inside a 16 ms budget on a phone, and incidentally
    /// widens the kernel by the same factor for free.
    private static let bloomDivisor = 8

    init?(device: MTLDevice) {
        guard let library = try? device.makeDefaultLibrary(bundle: .main),
              let brightFunction = library.makeFunction(name: "pfxBrightPass"),
              let blurFunction = library.makeFunction(name: "pfxBlur"),
              let compositeFunction = library.makeFunction(name: "pfxComposite"),
              let brightState = try? device.makeComputePipelineState(function: brightFunction),
              let blurState = try? device.makeComputePipelineState(function: blurFunction),
              let compositeState = try? device.makeComputePipelineState(function: compositeFunction)
        else { return nil }

        brightPass = brightState
        blur = blurState
        composite = compositeState
    }

    // MARK: - Per frame

    func run(_ context: ARView.PostProcessContext) {
        let source = context.sourceColorTexture
        let target = context.targetColorTexture
        prepare(
            device: context.device,
            width: source.width, height: source.height,
            targetFormat: target.pixelFormat
        )

        guard source.width == target.width, source.height == target.height,
              let bloomA, let bloomB, let output,
              let encoder = context.commandBuffer.makeComputeCommandEncoder()
        else {
            passthrough(context)
            return
        }

        if frame == 0 {
            NSLog("[postfx] source=%d target=%d size=%dx%d", source.pixelFormat.rawValue, target.pixelFormat.rawValue, source.width, source.height)
        }
        frame = frame >= 4096 ? 0 : frame + 1
        var uniforms = makeUniforms(source: source, target: target, bloom: bloomA)

        encoder.setBytes(&uniforms, length: MemoryLayout<PostUniforms>.stride, index: 0)

        encoder.setComputePipelineState(brightPass)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(bloomA, index: 1)
        dispatch(encoder, brightPass, width: bloomA.width, height: bloomA.height)

        // Two separable passes rather than one. A single five-tap Gaussian is a tight halo
        // that reads as a rendering artefact; a lamp needs a wide, low glow before it looks
        // like light spilling into a lens.
        encoder.setComputePipelineState(blur)
        for pass in 0..<2 {
            var horizontal = SIMD2<Float>(Float(1 + pass), 0)
            var vertical = SIMD2<Float>(0, Float(1 + pass))

            encoder.setTexture(bloomA, index: 0)
            encoder.setTexture(bloomB, index: 1)
            encoder.setBytes(&horizontal, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
            dispatch(encoder, blur, width: bloomB.width, height: bloomB.height)

            encoder.setTexture(bloomB, index: 0)
            encoder.setTexture(bloomA, index: 1)
            encoder.setBytes(&vertical, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
            dispatch(encoder, blur, width: bloomA.width, height: bloomA.height)
        }

        encoder.setComputePipelineState(composite)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(bloomA, index: 1)
        encoder.setTexture(output, index: 2)
        dispatch(encoder, composite, width: output.width, height: output.height)

        encoder.endEncoding()

        // The drawable is often an sRGB texture, which a compute kernel cannot write to, so
        // the result lands in a linear-format twin and is copied across. Blit treats the two
        // as the same format, and the copy is free next to the shading.
        guard let blit = context.commandBuffer.makeBlitCommandEncoder() else { return }
        blit.copy(from: output, to: target)
        blit.endEncoding()
    }

    /// Called before `run` so the callback itself never allocates.
    func prepare(device: MTLDevice, width: Int, height: Int, targetFormat: MTLPixelFormat) {
        let outputFormat = Self.writableFormat(for: targetFormat)
        if let output, output.width == width, output.height == height,
           output.pixelFormat == outputFormat {
            return
        }

        let bloomWidth = max(width / Self.bloomDivisor, 1)
        let bloomHeight = max(height / Self.bloomDivisor, 1)

        bloomA = Self.makeTexture(device, .rgba16Float, bloomWidth, bloomHeight)
        bloomB = Self.makeTexture(device, .rgba16Float, bloomWidth, bloomHeight)
        output = Self.makeTexture(device, outputFormat, width, height)
    }

    // MARK: - Plumbing

    private func makeUniforms(
        source: MTLTexture, target: MTLTexture, bloom: MTLTexture
    ) -> PostUniforms {
        var uniforms = PostUniforms()
        uniforms.texelSize = SIMD2(1 / Float(source.width), 1 / Float(source.height))
        uniforms.bloomTexelSize = SIMD2(1 / Float(bloom.width), 1 / Float(bloom.height))
        // Stepped by an irrational so successive frames land far apart in the hash.
        uniforms.time = frame * 0.618034
        uniforms.bloomThreshold = settings.bloomThreshold
        uniforms.bloomSoftKnee = settings.bloomSoftKnee
        uniforms.bloomStrength = settings.bloomStrength
        uniforms.filmicExposure = settings.filmicExposure
        uniforms.filmicStrength = settings.filmicStrength
        uniforms.contrast = settings.contrast
        uniforms.saturation = settings.saturation
        uniforms.shadowWarmth = settings.shadowWarmth
        uniforms.highlightCool = settings.highlightCool
        uniforms.vignetteStrength = settings.vignetteStrength
        uniforms.vignetteRadius = settings.vignetteRadius
        uniforms.grainStrength = settings.grainStrength
        uniforms.aberration = settings.aberration
        // A sampler linearises sRGB formats for us; a plain 8-bit format carries the same
        // gamma-encoded values with no such courtesy.
        uniforms.decodeSRGB = Self.isEightBitLinearFormat(source.pixelFormat) ? 1 : 0
        uniforms.encodeSRGB = Self.isEightBitFormat(target.pixelFormat) ? 1 : 0
        return uniforms
    }

    private func dispatch(
        _ encoder: MTLComputeCommandEncoder,
        _ state: MTLComputePipelineState,
        width: Int, height: Int
    ) {
        let threadgroup = MTLSize(width: 8, height: 8, depth: 1)
        let groups = MTLSize(
            width: (width + threadgroup.width - 1) / threadgroup.width,
            height: (height + threadgroup.height - 1) / threadgroup.height,
            depth: 1
        )
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threadgroup)
    }

    /// The demo is shown live in front of people, so a broken pass shows the untouched
    /// frame rather than a black screen.
    private func passthrough(_ context: ARView.PostProcessContext) {
        guard let blit = context.commandBuffer.makeBlitCommandEncoder() else { return }
        blit.copy(from: context.sourceColorTexture, to: context.targetColorTexture)
        blit.endEncoding()
    }

    private static func makeTexture(
        _ device: MTLDevice, _ format: MTLPixelFormat, _ width: Int, _ height: Int
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }

    private static func writableFormat(for format: MTLPixelFormat) -> MTLPixelFormat {
        switch format {
        case .bgra8Unorm_srgb: return .bgra8Unorm
        case .rgba8Unorm_srgb: return .rgba8Unorm
        default: return format
        }
    }

    private static func isEightBitFormat(_ format: MTLPixelFormat) -> Bool {
        switch format {
        case .bgra8Unorm, .rgba8Unorm, .bgra8Unorm_srgb, .rgba8Unorm_srgb: return true
        default: return false
        }
    }

    private static func isEightBitLinearFormat(_ format: MTLPixelFormat) -> Bool {
        format == .bgra8Unorm || format == .rgba8Unorm
    }
}
