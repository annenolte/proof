import CoreGraphics
import Foundation
import RealityKit
import simd
#if canImport(UIKit)
import UIKit
#endif

// Procedurally generated textures for the demo room.
//
// Nothing here ships as an image asset. Every surface — the oak floor, the concrete
// ceiling, the quartz counters, the velvet sofa, the wool rug — is drawn at launch from a
// height/colour function. That keeps the app binary unchanged, lets a material be tuned by
// editing a number rather than round-tripping a paint program, and means every texture is
// generated at exactly the resolution the surface needs.
//
// Each material generally gets two maps:
//   • base colour — what it looks like
//   • normal — the surface relief, derived from the same height function
//
// The normal map is what actually sells these. A flat tinted plane reads as plastic no
// matter how good the colour is; grain direction and weave catching the light is the cue
// the eye uses to identify a material.

enum TextureFactory {

    // MARK: - Noise

    /// Seeded value noise with smooth interpolation. Deterministic, so the room looks
    /// identical on every launch — which matters when the demo is being rehearsed.
    struct Noise {
        private let permutation: [Int]

        init(seed: UInt64) {
            var rng = SplitMix64(seed: seed)
            var table = Array(0..<256)
            for i in stride(from: 255, to: 0, by: -1) {
                let j = Int(rng.next() % UInt64(i + 1))
                table.swapAt(i, j)
            }
            permutation = table + table
        }

        private func gradient(_ hash: Int, _ x: Float, _ y: Float) -> Float {
            switch hash & 3 {
            case 0: return x + y
            case 1: return -x + y
            case 2: return x - y
            default: return -x - y
            }
        }

        private static func fade(_ t: Float) -> Float { t * t * t * (t * (t * 6 - 15) + 10) }

        /// Perlin-style gradient noise in roughly [-1, 1].
        func value(_ x: Float, _ y: Float) -> Float {
            let xi = Int(floor(x)) & 255
            let yi = Int(floor(y)) & 255
            let xf = x - floor(x)
            let yf = y - floor(y)
            let u = Noise.fade(xf), v = Noise.fade(yf)

            let aa = permutation[permutation[xi] + yi]
            let ab = permutation[permutation[xi] + yi + 1]
            let ba = permutation[permutation[xi + 1] + yi]
            let bb = permutation[permutation[xi + 1] + yi + 1]

            let x1 = mix(gradient(aa, xf, yf), gradient(ba, xf - 1, yf), u)
            let x2 = mix(gradient(ab, xf, yf - 1), gradient(bb, xf - 1, yf - 1), u)
            return mix(x1, x2, v)
        }

        /// Fractal Brownian motion — layered noise, the standard way to get natural detail.
        func fbm(_ x: Float, _ y: Float, octaves: Int = 4, gain: Float = 0.5, lacunarity: Float = 2) -> Float {
            var sum: Float = 0, amplitude: Float = 1, frequency: Float = 1, norm: Float = 0
            for _ in 0..<octaves {
                sum += value(x * frequency, y * frequency) * amplitude
                norm += amplitude
                amplitude *= gain
                frequency *= lacunarity
            }
            return norm > 0 ? sum / norm : 0
        }

        private func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
    }

    struct SplitMix64: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    // MARK: - Raster helpers

    /// Builds an RGBA8 image from a per-pixel closure returning linear-ish sRGB components.
    static func image(
        width: Int, height: Int,
        _ body: (_ u: Float, _ v: Float, _ x: Int, _ y: Int) -> SIMD3<Float>
    ) -> CGImage? {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let v = Float(y) / Float(height)
            for x in 0..<width {
                let u = Float(x) / Float(width)
                let c = body(u, v, x, y)
                let i = (y * width + x) * 4
                pixels[i] = UInt8(clamping: Int(clampUnit(c.x) * 255))
                pixels[i + 1] = UInt8(clamping: Int(clampUnit(c.y) * 255))
                pixels[i + 2] = UInt8(clamping: Int(clampUnit(c.z) * 255))
                pixels[i + 3] = 255
            }
        }
        return makeImage(pixels: pixels, width: width, height: height)
    }

    /// Builds a tangent-space normal map by finite-differencing a height field.
    /// `strength` scales the relief; 1 is subtle, 6 is pronounced.
    static func normalMap(
        width: Int, height: Int, strength: Float = 2,
        _ heightAt: (_ u: Float, _ v: Float) -> Float
    ) -> CGImage? {
        // Sample the height field once so each texel costs one evaluation, not three.
        var field = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                field[y * width + x] = heightAt(Float(x) / Float(width), Float(y) / Float(height))
            }
        }
        func h(_ x: Int, _ y: Int) -> Float {
            let xx = ((x % width) + width) % width
            let yy = ((y % height) + height) % height
            return field[yy * width + xx]
        }

        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let dx = (h(x + 1, y) - h(x - 1, y)) * strength
                let dy = (h(x, y + 1) - h(x, y - 1)) * strength
                let n = simd_normalize(SIMD3<Float>(-dx, -dy, 1))
                let i = (y * width + x) * 4
                pixels[i] = UInt8(clamping: Int((n.x * 0.5 + 0.5) * 255))
                pixels[i + 1] = UInt8(clamping: Int((n.y * 0.5 + 0.5) * 255))
                pixels[i + 2] = UInt8(clamping: Int((n.z * 0.5 + 0.5) * 255))
                pixels[i + 3] = 255
            }
        }
        return makeImage(pixels: pixels, width: width, height: height)
    }

    /// Single-channel map packed as grey RGBA — used for roughness variation.
    static func scalarMap(
        width: Int, height: Int, _ body: (_ u: Float, _ v: Float) -> Float
    ) -> CGImage? {
        image(width: width, height: height) { u, v, _, _ in
            SIMD3(repeating: clampUnit(body(u, v)))
        }
    }

    private static func makeImage(pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        var data = pixels
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        return data.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                    data: base, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: space, bitmapInfo: info.rawValue
                  ) else { return nil }
            return context.makeImage()
        }
    }

    /// Draws into a CoreGraphics context — for anything easier to describe with strokes
    /// and fills than with a per-pixel function (artwork, book spines, appliance panels).
    static func draw(
        width: Int, height: Int, background: UIColor = .white,
        _ body: (CGContext, CGSize) -> Void
    ) -> CGImage? {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size, format: {
            let f = UIGraphicsImageRendererFormat.default()
            f.scale = 1
            f.opaque = true
            return f
        }())
        let uiImage = renderer.image { ctx in
            background.setFill()
            ctx.cgContext.fill(CGRect(origin: .zero, size: size))
            body(ctx.cgContext, size)
        }
        return uiImage.cgImage
    }

    // MARK: - Resource wrapping

    @MainActor
    static func texture(
        _ image: CGImage?, semantic: TextureResource.Semantic, name: String
    ) -> TextureResource? {
        guard let image else { return nil }
        return try? TextureResource.generate(
            from: image,
            withName: name,
            options: .init(semantic: semantic, mipmapsMode: .allocateAndGenerateAll)
        )
    }

    static func clampUnit(_ v: Float) -> Float { min(max(v, 0), 1) }

    /// Linear interpolation between two colours.
    static func lerp(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        a + (b - a) * clampUnit(t)
    }

    /// sRGB hex to a linear-ish component triple.
    static func rgb(_ hex: UInt32) -> SIMD3<Float> {
        SIMD3(
            Float((hex >> 16) & 0xFF) / 255,
            Float((hex >> 8) & 0xFF) / 255,
            Float(hex & 0xFF) / 255
        )
    }
}
