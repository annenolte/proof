import CoreGraphics
import Foundation
import RealityKit
import simd

// The image-based light for the demo room.
//
// Direct lights alone make an interior look like a stage set: every surface is either lit
// or black, and metal and glass have nothing to reflect. Real rooms are mostly lit by
// light that has bounced — off the ceiling, off the floor, off the walls — and the
// brightest thing in this particular room by far is the corner glazing.
//
// So rather than shipping an HDR panorama, the environment is synthesised to match this
// apartment: a bright daylight wedge where the windows actually are, a warm bounce from
// the oak floor below, a neutral ceiling above, and the wall tone everywhere else. The
// quartz counters, the stainless appliances and the brass chair base all get something
// plausible to reflect, and the whole room gains the soft ambient fill that reads as
// "photographed" rather than "rendered".

enum EnvironmentFactory {

    /// Builds the equirectangular latitude/longitude image the IBL is baked from.
    ///
    /// `u` maps to azimuth (0…2π) and `v` to polar angle, v = 0 at the zenith. The window
    /// azimuth is derived from the plan so that moving a window in `Plan` moves its
    /// reflection too.
    static func makeEquirectangular(width: Int = 512, height: Int = 256) -> CGImage? {
        // The room's bright side: the corner glazing on the east and south walls. In world
        // terms that is roughly +X through to +Z, so the wedge is centred between them.
        let windowAzimuth: Float = .pi * 0.25   // between +X (east) and +Z (south)
        let windowHalfWidth: Float = .pi * 0.42

        // These are deliberately far apart. In a real room the glazing is one to two orders
        // of magnitude brighter than the wall beside it, and an environment map whose
        // window is only 1.6x the wall gives reflections no punch at all — every polished
        // surface ends up a flat grey. An 8-bit map cannot exceed 1.0, so the contrast has
        // to be bought by pushing everything that is not a window down instead.
        // A balance, and it is worth being explicit about which way each direction hurts.
        // The window must be much brighter than the walls or polished surfaces have nothing
        // worth reflecting. But this map is also the scene's ambient diffuse: crushing the
        // non-window tones to buy reflection contrast takes the room's fill light with it
        // and everything goes muddy. These sit between the two failure modes — roughly a
        // 3:1 window-to-wall ratio, which reads as contrast without going dark.
        let sky = TextureFactory.rgb(0xC2D4E8)      // cool daylight through glass
        let skyHot = TextureFactory.rgb(0xFFFFFF)   // the window itself, blown out
        let ceiling = TextureFactory.rgb(0x86847F)  // concrete soffit
        let wall = TextureFactory.rgb(0x6F675B)     // greige wall in shadow
        let floorBounce = TextureFactory.rgb(0x74604A) // warm oak returning light upward

        let noise = TextureFactory.Noise(seed: 3301)

        return TextureFactory.image(width: width, height: height) { u, v, _, _ in
            let azimuth = u * 2 * .pi
            // v = 0 is straight up, v = 1 straight down.
            let elevation = (0.5 - v) * .pi   // +π/2 up, -π/2 down

            // Vertical blend: ceiling above, wall at the horizon, floor bounce below.
            var colour: SIMD3<Float>
            if elevation >= 0 {
                colour = TextureFactory.lerp(wall, ceiling, smoothstep(0, 0.9, elevation))
            } else {
                colour = TextureFactory.lerp(wall, floorBounce, smoothstep(0, 0.8, -elevation))
            }

            // The window wedge, strongest around the horizon and falling off with height.
            var delta = abs(atan2(sin(azimuth - windowAzimuth), cos(azimuth - windowAzimuth)))
            delta = min(delta, .pi)
            let horizontal = 1 - smoothstep(windowHalfWidth * 0.45, windowHalfWidth, delta)
            // Windows run from sill to head, so the glow is banded, not a full column.
            let vertical = smoothstep(-0.55, -0.18, elevation) * (1 - smoothstep(0.30, 0.72, elevation))
            let windowMask = horizontal * vertical

            colour = TextureFactory.lerp(colour, sky, windowMask)
            colour = TextureFactory.lerp(colour, skyHot, windowMask * windowMask * 0.9)

            // Break up the banding so the reflections are not perfectly smooth gradients.
            let grain = noise.fbm(u * 8, v * 8, octaves: 3) * 0.04
            return colour * (1 + grain)
        }
    }

    /// Generates the runtime IBL. Returns nil if generation fails, in which case the scene
    /// falls back to direct lighting only rather than failing to load.
    @MainActor
    static func makeEnvironment() -> EnvironmentResource? {
        guard let image = makeEquirectangular() else { return nil }
        return try? EnvironmentResource(equirectangular: image, withName: "demoRoomIBL")
    }
}
