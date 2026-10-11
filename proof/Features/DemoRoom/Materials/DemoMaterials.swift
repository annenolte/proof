import CoreGraphics
import Foundation
import RealityKit
import simd
#if canImport(UIKit)
import UIKit
#endif

// The material library for the demo apartment.
//
// Every material in the reference footage is described here as a height function plus a
// colour function, and turned into a `PhysicallyBasedMaterial` with a base colour map, a
// normal map, and where it matters a roughness map.
//
// The reference room's look comes from a small number of surfaces doing a lot of work:
// blonde wide-plank oak underfoot, raw concrete overhead, matte charcoal cabinet fronts,
// white quartz, and three fabrics (navy velvet, cognac leather, cream wool). Getting those
// six right matters far more than adding a seventh.
//
// ## Why this is split in two
//
// Rasterising the maps is a few million noise evaluations, which in a debug build is
// seconds of pure CPU. `RenderedMaps` does that work and is deliberately free of any
// RealityKit or main-actor dependency, so `make()` can run it on a background thread. Only
// the GPU upload — `TextureResource.generate` — has to come back to the main actor.

/// The rasterised maps, before they become GPU resources.
///
/// `CGImage` is immutable and thread-safe in practice but is not marked `Sendable`, hence
/// the unchecked conformance; nothing here is mutated after construction.
struct RenderedMaps: @unchecked Sendable {
    var oakBase, oakNormal, oakRough, oakAO: CGImage?
    var tileAO, cabinetAO: CGImage?
    var concreteBase, concreteNormal: CGImage?
    var wallWarmBase, wallWarmNormal: CGImage?
    var wallCoolBase, wallCoolNormal: CGImage?
    var cabinetBase, cabinetNormal: CGImage?
    var quartzBase, quartzNormal: CGImage?
    var tileBase, tileNormal: CGImage?
    var steelBase, steelRough: CGImage?
    var woodBase, woodNormal: CGImage?
    var velvetBase, velvetNormal, velvetRough: CGImage?
    var leatherBase, leatherNormal, leatherRough: CGImage?
    var rugBase, rugNormal: CGImage?
    var shadeBase: CGImage?
}

@MainActor
final class DemoMaterials {

    // MARK: - Named materials

    private(set) var oakFloor = PhysicallyBasedMaterial()
    private(set) var concreteCeiling = PhysicallyBasedMaterial()
    private(set) var wallWarm = PhysicallyBasedMaterial()
    private(set) var wallCool = PhysicallyBasedMaterial()
    private(set) var baseboard = PhysicallyBasedMaterial()

    private(set) var darkCabinet = PhysicallyBasedMaterial()
    private(set) var quartz = PhysicallyBasedMaterial()
    private(set) var subwayTile = PhysicallyBasedMaterial()
    private(set) var stainless = PhysicallyBasedMaterial()
    private(set) var blackMetal = PhysicallyBasedMaterial()
    private(set) var brass = PhysicallyBasedMaterial()
    private(set) var darkWood = PhysicallyBasedMaterial()

    private(set) var navyVelvet = PhysicallyBasedMaterial()
    private(set) var cognacLeather = PhysicallyBasedMaterial()
    private(set) var woolRug = PhysicallyBasedMaterial()
    private(set) var linenShade = PhysicallyBasedMaterial()
    private(set) var creamFabric = PhysicallyBasedMaterial()

    private(set) var ceramicWhite = PhysicallyBasedMaterial()
    private(set) var glass = PhysicallyBasedMaterial()
    private(set) var matteBlackPaint = PhysicallyBasedMaterial()
    private(set) var paperWhite = PhysicallyBasedMaterial()
    private(set) var terracotta = PhysicallyBasedMaterial()
    private(set) var amberGlass = PhysicallyBasedMaterial()
    private(set) var mustard = PhysicallyBasedMaterial()

    /// Warm glow used for lit lamp shades and the track-light lenses.
    private(set) var bulbGlow = PhysicallyBasedMaterial()

    // MARK: - Construction

    /// Rasterises off the main actor, then uploads. This is the entry point the app uses.
    static func make() async -> DemoMaterials {
        let maps = await Task.detached(priority: .userInitiated) {
            MapRenderer.renderAll()
        }.value
        return DemoMaterials(maps: maps)
    }

    /// Synchronous construction, for previews and tests where a stall does not matter.
    convenience init() {
        self.init(maps: MapRenderer.renderAll())
    }

    init(maps: RenderedMaps) {
        // A finished oak floor is wood *under a varnish*. The clearcoat is that varnish:
        // it puts a sharp second highlight over the diffuse grain, which is exactly how a
        // real floor picks up a window.
        oakFloor = pbr(
            base: maps.oakBase, normal: maps.oakNormal, roughnessMap: maps.oakRough,
            ambientOcclusion: maps.oakAO,
            roughness: 0.45, metallic: 0,
            clearcoat: 0.42, clearcoatRoughness: 0.26, name: "oak"
        )
        concreteCeiling = pbr(
            base: maps.concreteBase, normal: maps.concreteNormal,
            roughness: 0.88, metallic: 0, name: "concrete"
        )
        // Painted drywall carries no normal map. It is genuinely flat, and even a gentle
        // relief reads as stucco once a wall is several metres across.
        wallWarm = pbr(
            base: maps.wallWarmBase, normal: nil,
            roughness: 0.92, metallic: 0, name: "wallWarm"
        )
        wallCool = pbr(
            base: maps.wallCoolBase, normal: nil,
            roughness: 0.92, metallic: 0, name: "wallCool"
        )
        baseboard = solid(0xE8E6E1, roughness: 0.6, metallic: 0)

        darkCabinet = pbr(
            base: maps.cabinetBase, normal: maps.cabinetNormal,
            ambientOcclusion: maps.cabinetAO,
            roughness: 0.62, metallic: 0,
            clearcoat: 0.18, clearcoatRoughness: 0.42, name: "cabinet"
        )
        // Polished engineered stone. The clearcoat is most of what makes a countertop
        // read as stone rather than as painted board.
        quartz = pbr(
            base: maps.quartzBase, normal: maps.quartzNormal,
            roughness: 0.22, metallic: 0,
            clearcoat: 0.55, clearcoatRoughness: 0.09, name: "quartz"
        )
        subwayTile = pbr(
            base: maps.tileBase, normal: maps.tileNormal,
            ambientOcclusion: maps.tileAO,
            roughness: 0.18, metallic: 0,
            clearcoat: 0.6, clearcoatRoughness: 0.08, name: "tile"
        )
        stainless = pbr(
            base: maps.steelBase, normal: nil, roughnessMap: maps.steelRough,
            roughness: 0.3, metallic: 1, name: "stainless"
        )
        blackMetal = solid(0x24262A, roughness: 0.44, metallic: 0.85)
        brass = solid(0xB99A5B, roughness: 0.28, metallic: 1)
        darkWood = pbr(
            base: maps.woodBase, normal: maps.woodNormal,
            roughness: 0.5, metallic: 0, name: "walnut"
        )

        // Velvet's whole character is retroreflection: the pile catches light at grazing
        // angles and the cushion crowns glow against a dark body. That is the sheen term,
        // and without it a navy sofa is just a navy box.
        navyVelvet = pbr(
            base: maps.velvetBase, normal: maps.velvetNormal, roughnessMap: maps.velvetRough,
            roughness: 0.5, metallic: 0,
            sheenTint: UIColor(red: 0.44, green: 0.56, blue: 0.78, alpha: 1), name: "velvet"
        )
        cognacLeather = pbr(
            base: maps.leatherBase, normal: maps.leatherNormal, roughnessMap: maps.leatherRough,
            roughness: 0.44, metallic: 0,
            clearcoat: 0.22, clearcoatRoughness: 0.55, name: "leather"
        )
        woolRug = pbr(
            base: maps.rugBase, normal: maps.rugNormal,
            roughness: 0.96, metallic: 0,
            sheenTint: UIColor(red: 0.92, green: 0.88, blue: 0.80, alpha: 1), name: "rug"
        )

        var shade = pbr(base: maps.shadeBase, normal: nil, roughness: 0.85, metallic: 0, name: "linen")
        shade.emissiveColor = .init(color: UIColor(red: 1.0, green: 0.88, blue: 0.66, alpha: 1))
        shade.emissiveIntensity = 1.9
        linenShade = shade

        creamFabric = solid(0xEDE6D8, roughness: 0.85, metallic: 0)
        ceramicWhite = solid(0xF6F4F0, roughness: 0.14, metallic: 0)
        matteBlackPaint = solid(0x1C1D20, roughness: 0.7, metallic: 0)
        paperWhite = solid(0xFBFAF6, roughness: 0.8, metallic: 0)
        terracotta = solid(0xC1663C, roughness: 0.55, metallic: 0)
        mustard = solid(0xD9A62B, roughness: 0.72, metallic: 0)

        var g = PhysicallyBasedMaterial()
        g.baseColor = .init(tint: UIColor(red: 0.80, green: 0.86, blue: 0.90, alpha: 1))
        g.roughness = .init(floatLiteral: 0.03)
        g.metallic = .init(floatLiteral: 0)
        g.blending = .transparent(opacity: .init(floatLiteral: 0.22))
        g.faceCulling = .none
        glass = g

        amberGlass = solid(0xA85C21, roughness: 0.12, metallic: 0)

        var glow = PhysicallyBasedMaterial()
        glow.baseColor = .init(tint: UIColor(red: 1.0, green: 0.92, blue: 0.78, alpha: 1))
        glow.roughness = .init(floatLiteral: 0.4)
        glow.emissiveColor = .init(color: UIColor(red: 1.0, green: 0.90, blue: 0.72, alpha: 1))
        glow.emissiveIntensity = 8
        bulbGlow = glow
    }

    // MARK: - Helpers

    /// Wraps generated maps into a `PhysicallyBasedMaterial`, tolerating a nil map by
    /// falling back to the scalar value — a texture that fails to rasterise degrades to a
    /// flat surface rather than taking the demo down.
    private func pbr(
        base: CGImage?,
        normal: CGImage?,
        roughnessMap: CGImage? = nil,
        ambientOcclusion: CGImage? = nil,
        roughness: Float,
        metallic: Float,
        /// A second specular lobe over the base surface. Every lacquered, glazed or
        /// varnished thing in a real room has one, and its absence is a large part of why
        /// untreated PBR reads as clay.
        clearcoat: Float = 0,
        clearcoatRoughness: Float = 0.1,
        /// Retroreflection at grazing angles. This is the term that makes velvet look like
        /// velvet and wool look like wool rather than like coloured plastic.
        sheenTint: UIColor? = nil,
        name: String
    ) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()

        if let tex = TextureFactory.texture(base, semantic: .color, name: "\(name).base") {
            m.baseColor = .init(tint: .white, texture: .init(tex))
        } else {
            m.baseColor = .init(tint: .gray)
        }
        if let tex = TextureFactory.texture(normal, semantic: .normal, name: "\(name).normal") {
            m.normal = .init(texture: .init(tex))
        }
        if let tex = TextureFactory.texture(roughnessMap, semantic: .raw, name: "\(name).rough") {
            m.roughness = .init(scale: 1, texture: .init(tex))
        } else {
            m.roughness = .init(floatLiteral: roughness)
        }
        if let tex = TextureFactory.texture(ambientOcclusion, semantic: .raw, name: "\(name).ao") {
            m.ambientOcclusion = .init(texture: .init(tex))
        }
        m.metallic = .init(floatLiteral: metallic)
        m.specular = .init(floatLiteral: 0.5)
        if clearcoat > 0 {
            m.clearcoat = .init(floatLiteral: clearcoat)
            m.clearcoatRoughness = .init(floatLiteral: clearcoatRoughness)
        }
        if let sheenTint {
            m.sheen = .init(tint: sheenTint)
        }
        return m
    }

    private func solid(_ hex: UInt32, roughness: Float, metallic: Float) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        let c = TextureFactory.rgb(hex)
        m.baseColor = .init(tint: UIColor(
            red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1
        ))
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: metallic)
        m.specular = .init(floatLiteral: 0.5)
        return m
    }

    // MARK: - Breakage

    /// The surface of a fresh fracture.
    ///
    /// The naive move is to give a shard the material of the object it came from. Doing
    /// that with the wine glass produced thirteen perfectly transparent slivers, which is
    /// to say nothing on screen at all — the glass material is 22% opaque and 0.03 rough,
    /// which is right for an intact vessel with a rim to catch the window and completely
    /// wrong for a 3 cm splinter tumbling across an oak floor.
    ///
    /// The physical answer is also the legible one. Glass fails conchoidally: the fracture
    /// surface is a field of ripples and hackle marks far coarser than the polished
    /// original, so it *scatters* where the intact wall transmitted. That is why real
    /// broken glass is white along its edges, why a smashed windscreen goes opaque, and
    /// why you can see a broken tumbler on a floor you could not see the intact one on.
    /// So a shard here is:
    ///
    /// * pulled most of the way to white, keeping a trace of the parent's tint so a shard
    ///   of the amber vase is still amber;
    /// * only lightly transparent, not the parent's 22% — enough to read as glass, opaque
    ///   enough to be a shape;
    /// * rough enough to scatter, under a hard clearcoat. The clearcoat is what does the
    ///   real work: it is a second, sharp specular lobe over a diffuse base, which is
    ///   exactly the bright edge that makes a piece of glass read as a piece of glass and
    ///   not as a chip of plaster;
    /// * faintly emissive, so shards that end up in the shadow under the island still
    ///   glint rather than disappearing into it. Ceramic gets none of this.
    ///
    /// Ceramic is the opposite of all of it: a fired body breaks to a matte, chalky,
    /// completely opaque face, and the tell is that the glazed *outside* still shines while
    /// the break does not.
    static func shard(
        failure: PhysicalMaterial.Failure, tint: UIColor
    ) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        tint.getRed(&r, green: &g, blue: &b, alpha: &a)

        switch failure {
        case .glass:
            // 78% of the way to white. Below about two thirds the amber vase's shards go
            // brown and stop reading as glass at all.
            let k: CGFloat = 0.78
            m.baseColor = .init(tint: UIColor(
                red: r + (1 - r) * k, green: g + (1 - g) * k, blue: b + (1 - b) * k, alpha: 1
            ))
            m.roughness = .init(floatLiteral: 0.24)
            m.metallic = .init(floatLiteral: 0)
            m.specular = .init(floatLiteral: 1.0)
            m.clearcoat = .init(floatLiteral: 1.0)
            m.clearcoatRoughness = .init(floatLiteral: 0.04)
            // Two-sided: a shard is a wedge a few millimetres thick and it tumbles, so it
            // is seen edge-on and from behind constantly. Culling its back faces makes it
            // flicker out of existence twice a revolution.
            m.faceCulling = .none
            m.blending = .transparent(opacity: .init(floatLiteral: 0.86))
            m.emissiveColor = .init(color: UIColor(red: 0.86, green: 0.93, blue: 1.0, alpha: 1))
            m.emissiveIntensity = 0.35
        case .ceramic:
            // Barely lightened: a stoneware break is the body colour, which is the point —
            // the glaze is only on the outside.
            let k: CGFloat = 0.22
            m.baseColor = .init(tint: UIColor(
                red: r + (1 - r) * k, green: g + (1 - g) * k, blue: b + (1 - b) * k, alpha: 1
            ))
            m.roughness = .init(floatLiteral: 0.82)
            m.metallic = .init(floatLiteral: 0)
            m.specular = .init(floatLiteral: 0.35)
            m.faceCulling = .none
        }
        return m
    }

    /// The white flash at the instant of failure. Unlit on purpose: this is not a surface
    /// being lit, it is the light itself, and letting the scene's own lighting darken it
    /// defeats the entire point of a flash.
    static let impactFlash: UnlitMaterial = unlit(.white, opacity: 0.9)

    /// Fine glitter thrown off the fracture. Unlit and near-white, so it survives being
    /// two millimetres across at four metres, which nothing shaded ever does.
    static let glitter: UnlitMaterial = unlit(
        UIColor(red: 0.97, green: 0.99, blue: 1.0, alpha: 1), opacity: 0.85
    )

    /// The puff at the fracture origin. Deliberately *not* the prop's own material — a
    /// puff of clear glass is a puff of nothing — and deliberately dust-coloured rather
    /// than white, because what an impact actually throws up is the dust that was on the
    /// surface it hit.
    /// The puff a break throws up, at a given opacity.
    ///
    /// A function rather than a constant because the puff has to *fade*. Eight spheres at a
    /// fixed 0.20 alpha overlap to something near 0.83 — opaque grey bubbles — and then, at
    /// the end of their life, vanish at full size and full alpha, which reads as a pop
    /// rather than as dust settling. `BreakageSystem` rebuilds this per frame for the few
    /// puffs alive at any moment; it is a handful of material writes over 0.7 s.
    static func breakDust(opacity: Float) -> UnlitMaterial {
        unlit(UIColor(white: 0.88, alpha: 1), opacity: max(opacity, 0.001))
    }

    /// The opacity a puff starts at. Deliberately faint: several of them overlap.
    static let breakDustOpacity: Float = 0.10

    /// `UnlitMaterial` has no colour initialiser in the iOS 18 SDK — only the empty, the
    /// tone-map and the texture forms — so the tint goes on afterwards.
    private static func unlit(_ colour: UIColor, opacity: Float) -> UnlitMaterial {
        var m = UnlitMaterial()
        m.color = .init(tint: colour)
        m.blending = .transparent(opacity: .init(floatLiteral: opacity))
        m.faceCulling = .none
        return m
    }

    /// Pulls a representative colour out of whatever the prop was made of, so a shard of
    /// the amber vase is amber and a shard of the plate is not. Textured materials carry a
    /// white tint by construction (`pbr` puts the colour in the map, not the tint), which
    /// is the correct answer for them anyway: a fracture face has no woodgrain on it.
    static func tint(of material: RealityKit.Material) -> UIColor {
        if let pbr = material as? PhysicallyBasedMaterial { return pbr.baseColor.tint }
        if let simple = material as? SimpleMaterial { return simple.color.tint }
        return .white
    }

    /// Builds a one-off material from an arbitrary image — artwork, the city backdrop,
    /// appliance control panels — where the content is drawn rather than tiled.
    func imageMaterial(
        _ image: CGImage?,
        roughness: Float = 0.6,
        metallic: Float = 0,
        emissive: Float = 0,
        name: String
    ) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        if let tex = TextureFactory.texture(image, semantic: .color, name: name) {
            m.baseColor = .init(tint: .white, texture: .init(tex))
            if emissive > 0 {
                m.emissiveColor = .init(color: .white, texture: .init(tex))
                m.emissiveIntensity = emissive
            }
        } else {
            m.baseColor = .init(tint: .lightGray)
        }
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: metallic)
        return m
    }
}

// MARK: - Rasterisation

/// Pure CPU work. Deliberately isolated to nothing so it can run off the main actor.
enum MapRenderer {

    static func renderAll() -> RenderedMaps {
        var maps = RenderedMaps()
        renderFloor(into: &maps)
        renderCeilingAndWalls(into: &maps)
        renderKitchen(into: &maps)
        renderSoftGoods(into: &maps)
        return maps
    }

    // MARK: Floor

    private static func renderFloor(into maps: inout RenderedMaps) {
        // Planks run along U. Board seams are hard steps in height; grain is stretched
        // fbm — high frequency across the board, low frequency along it, which is what
        // makes wood read as wood rather than as marble.
        let noise = TextureFactory.Noise(seed: 41)
        let plankRows: Float = 6          // boards across the tile
        let plankLength: Float = 1.0      // butt joints every 2 m of board

        func board(_ u: Float, _ v: Float) -> (row: Float, inRow: Float, along: Float, seed: Float) {
            let row = v * plankRows
            let rowIndex = floor(row)
            let inRow = row - rowIndex
            // Stagger successive rows so butt joints never line up across the floor.
            let stagger = rowIndex.truncatingRemainder(dividingBy: 2) * 0.5
            let along = u * plankLength + stagger
            return (rowIndex, inRow, along, rowIndex * 13.7 + floor(along) * 4.1)
        }

        func height(_ u: Float, _ v: Float) -> Float {
            let b = board(u, v)
            let edge = min(b.inRow, 1 - b.inRow)
            let butt = min(b.along - floor(b.along), 1 - (b.along - floor(b.along)))
            let seam = min(smoothstep(0, 0.035, edge), smoothstep(0, 0.02, butt))
            let grain = noise.fbm(b.along * 5 + b.seed, b.inRow * 42 + b.seed, octaves: 4)
            return seam * 0.82 + grain * 0.18
        }

        maps.oakBase = TextureFactory.image(width: 384, height: 384) { u, v, _, _ in
            let b = board(u, v)
            // Each board gets its own tone — real floors are never one colour.
            let tone = noise.value(b.seed * 0.37, b.seed * 0.71) * 0.5 + 0.5
            var colour = TextureFactory.lerp(
                TextureFactory.rgb(0xC4AE92), TextureFactory.rgb(0xD8C7AE), tone
            )
            let grain = noise.fbm(b.along * 5 + b.seed, b.inRow * 42 + b.seed, octaves: 5)
            colour = TextureFactory.lerp(
                colour, TextureFactory.rgb(0xA98F72),
                TextureFactory.clampUnit(grain * 0.55 + 0.22)
            )
            let edge = min(b.inRow, 1 - b.inRow)
            let butt = min(b.along - floor(b.along), 1 - (b.along - floor(b.along)))
            let seam = min(smoothstep(0, 0.03, edge), smoothstep(0, 0.016, butt))
            return TextureFactory.lerp(TextureFactory.rgb(0x6E5B47), colour, seam)
        }
        maps.oakNormal = TextureFactory.normalMap(width: 384, height: 384, strength: 3.2, height)

        // Traffic wear: the varnish is duller where people walk. A floor with one uniform
        // roughness value reads as a material sample rather than as a floor someone lives on.
        maps.oakRough = TextureFactory.scalarMap(width: 256, height: 256) { u, v in
            let wear = noise.fbm(u * 2.2, v * 2.2, octaves: 3) * 0.5 + 0.5
            return 0.38 + noise.fbm(u * 9, v * 9, octaves: 3) * 0.10 + wear * 0.16
        }

        // Light does not reach into a board joint. Darkening the seams is the cheapest
        // ambient occlusion there is, and it is what stops the floor looking printed.
        maps.oakAO = TextureFactory.scalarMap(width: 256, height: 256) { u, v in
            let b = board(u, v)
            let edge = min(b.inRow, 1 - b.inRow)
            let butt = min(b.along - floor(b.along), 1 - (b.along - floor(b.along)))
            let seam = min(smoothstep(0, 0.030, edge), smoothstep(0, 0.016, butt))
            return 0.55 + 0.45 * seam
        }
    }

    // MARK: Ceiling and walls

    private static func renderCeilingAndWalls(into maps: inout RenderedMaps) {
        // The reference ceiling is raw structural concrete with faint form-board seams and
        // blotchy curing marks. Almost flat, but the blotches stop it reading as grey card.
        let cn = TextureFactory.Noise(seed: 907)
        maps.concreteBase = TextureFactory.image(width: 256, height: 256) { u, v, _, _ in
            let blotch = cn.fbm(u * 3.5, v * 3.5, octaves: 5) * 0.5 + 0.5
            let fine = cn.fbm(u * 30, v * 30, octaves: 3) * 0.5 + 0.5
            var c = TextureFactory.lerp(
                TextureFactory.rgb(0xB6B7B6), TextureFactory.rgb(0xCFD1D1), blotch
            )
            c = TextureFactory.lerp(c, TextureFactory.rgb(0xA5A7A8), fine * 0.28)
            // The reference soffit is a poured slab with occasional construction joints,
            // not regular board forming. Frequent hard seams read as timber planking.
            let seam = abs(sin(v * .pi * 1.5))
            return TextureFactory.lerp(TextureFactory.rgb(0xA9ABAC), c, smoothstep(0, 0.22, seam))
        }
        maps.concreteNormal = TextureFactory.normalMap(width: 256, height: 256, strength: 1.4) { u, v in
            smoothstep(0, 0.16, abs(sin(v * .pi * 1.5))) * 0.35 + cn.fbm(u * 26, v * 26, octaves: 3) * 0.65
        }

        // Painted drywall: a warm greige in the living room, a cooler grey by the entry.
        let wn = TextureFactory.Noise(seed: 5150)
        func paint(_ hex: UInt32) -> (CGImage?, CGImage?) {
            let base = TextureFactory.image(width: 256, height: 256) { u, v, _, _ in
                // Very light orange-peel mottling; enough to break up a flat fill.
                let n = wn.fbm(u * 24, v * 24, octaves: 3) * 0.5 + 0.5
                let c = TextureFactory.rgb(hex)
                return TextureFactory.lerp(c, c * 0.955, n * 0.5)
            }
            // No normal map: painted drywall is flat, and the materials pass nil.
            return (base, nil)
        }
        (maps.wallWarmBase, maps.wallWarmNormal) = paint(0xCFC6B8)
        (maps.wallCoolBase, maps.wallCoolNormal) = paint(0xD3D2CE)
    }

    // MARK: Kitchen

    private static func renderKitchen(into maps: inout RenderedMaps) {
        // Matte dark-stained oak. The grain is only just visible, which is exactly why it
        // needs a normal map — with a flat colour these fronts read as plastic.
        let n = TextureFactory.Noise(seed: 2211)
        maps.cabinetBase = TextureFactory.image(width: 256, height: 256) { u, v, _, _ in
            let grain = n.fbm(u * 3, v * 60, octaves: 5)
            return TextureFactory.lerp(
                TextureFactory.rgb(0x3B3733), TextureFactory.rgb(0x4E4844),
                TextureFactory.clampUnit(grain * 0.6 + 0.45)
            )
        }
        maps.cabinetNormal = TextureFactory.normalMap(width: 256, height: 256, strength: 1.1) { u, v in
            n.fbm(u * 3, v * 70, octaves: 4)
        }

        // Engineered stone: a bright near-white field with sparse soft veining and a fine
        // speckle. Low roughness, so it picks up the windows.
        let qn = TextureFactory.Noise(seed: 77)
        maps.quartzBase = TextureFactory.image(width: 384, height: 384) { u, v, _, _ in
            // Domain-warped ridged noise makes vein-like filaments rather than blobs.
            let wx = u * 2.2 + qn.fbm(u * 1.6, v * 1.6, octaves: 3) * 0.9
            let wy = v * 2.2 + qn.fbm(u * 1.6 + 5, v * 1.6 + 5, octaves: 3) * 0.9
            let ridge = 1 - abs(qn.fbm(wx * 2.4, wy * 2.4, octaves: 4))
            // Engineered quartz is nearly plain. Heavy veining reads as Calacatta marble,
            // which is a different — and much louder — material than the reference.
            let vein = pow(TextureFactory.clampUnit(ridge), 26) * 0.32
            let speck = qn.value(u * 340, v * 340) * 0.5 + 0.5
            var c = TextureFactory.rgb(0xF4F2ED)
            c = TextureFactory.lerp(c, TextureFactory.rgb(0xD5D2CB), vein)
            return TextureFactory.lerp(c, TextureFactory.rgb(0xDCD9D2), speck * 0.16)
        }
        maps.quartzNormal = TextureFactory.normalMap(width: 256, height: 256, strength: 0.5) { u, v in
            qn.value(u * 200, v * 200) * 0.5 + 0.5
        }

        func tileMask(_ u: Float, _ v: Float) -> Float {
            let cols: Float = 6, rows: Float = 12
            let row = floor(v * rows)
            let offset = row.truncatingRemainder(dividingBy: 2) * 0.5
            let cx = (u * cols + offset).truncatingRemainder(dividingBy: 1)
            let cy = (v * rows).truncatingRemainder(dividingBy: 1)
            return min(
                min(smoothstep(0, 0.045, cx), smoothstep(0, 0.045, 1 - cx)),
                min(smoothstep(0, 0.08, cy), smoothstep(0, 0.08, 1 - cy))
            )
        }
        maps.tileBase = TextureFactory.image(width: 256, height: 256) { u, v, _, _ in
            TextureFactory.lerp(
                TextureFactory.rgb(0xCFCCC6), TextureFactory.rgb(0xF2F0EC), tileMask(u, v)
            )
        }
        maps.tileNormal = TextureFactory.normalMap(width: 256, height: 256, strength: 4, tileMask)
        // Grout sits below the tile face and is correspondingly shadowed.
        maps.tileAO = TextureFactory.scalarMap(width: 256, height: 256) { u, v in
            0.62 + 0.38 * tileMask(u, v)
        }

        // Brushed stainless. `PhysicallyBasedMaterial` has no anisotropy, so the brush
        // direction is carried by streaks in the base and roughness maps instead.
        let sn = TextureFactory.Noise(seed: 314)
        maps.steelBase = TextureFactory.image(width: 128, height: 256) { u, v, _, _ in
            let streak = sn.fbm(u * 2, v * 260, octaves: 2) * 0.5 + 0.5
            return TextureFactory.lerp(
                TextureFactory.rgb(0x9A9CA0), TextureFactory.rgb(0xC2C4C8), streak
            )
        }
        maps.steelRough = TextureFactory.scalarMap(width: 128, height: 256) { u, v in
            0.26 + (sn.fbm(u * 2, v * 300, octaves: 2) * 0.5 + 0.5) * 0.16
        }

        let dn = TextureFactory.Noise(seed: 6060)
        maps.woodBase = TextureFactory.image(width: 256, height: 256) { u, v, _, _ in
            let grain = dn.fbm(u * 2.5, v * 44, octaves: 5)
            let c = TextureFactory.lerp(
                TextureFactory.rgb(0x4A3A2E), TextureFactory.rgb(0x6B5340),
                TextureFactory.clampUnit(grain * 0.7 + 0.4)
            )
            let ring = sin((v * 18 + dn.fbm(u * 3, v * 3, octaves: 2) * 5) * .pi)
            return TextureFactory.lerp(
                c, TextureFactory.rgb(0x3A2C22), TextureFactory.clampUnit(ring) * 0.2
            )
        }
        maps.woodNormal = TextureFactory.normalMap(width: 256, height: 256, strength: 1.3) { u, v in
            dn.fbm(u * 2.5, v * 50, octaves: 4)
        }
    }

    // MARK: Soft goods

    private static func renderSoftGoods(into maps: inout RenderedMaps) {
        // Velvet's signature is a sheen that shifts with view angle. Without a custom
        // shader the closest honest approximation is a lowish roughness plus a fine pile
        // normal, which at least catches the window light along the cushion crowns.
        let vn = TextureFactory.Noise(seed: 8801)
        maps.velvetBase = TextureFactory.image(width: 256, height: 256) { u, v, _, _ in
            let pile = vn.fbm(u * 150, v * 150, octaves: 3) * 0.5 + 0.5
            return TextureFactory.lerp(
                TextureFactory.rgb(0x1F2C42), TextureFactory.rgb(0x35486B), pile * 0.85
            )
        }
        maps.velvetNormal = TextureFactory.normalMap(width: 256, height: 256, strength: 1.6) { u, v in
            vn.fbm(u * 170, v * 170, octaves: 3)
        }
        maps.velvetRough = TextureFactory.scalarMap(width: 256, height: 256) { u, v in
            0.44 + (vn.fbm(u * 60, v * 60, octaves: 2) * 0.5 + 0.5) * 0.2
        }

        // Layered fine noise gives a convincing pebbled hide without a Worley basis.
        let ln = TextureFactory.Noise(seed: 4242)
        func leather(_ u: Float, _ v: Float) -> Float {
            ln.fbm(u * 90, v * 90, octaves: 2) * 0.65 + ln.fbm(u * 220, v * 220, octaves: 2) * 0.35
        }
        maps.leatherBase = TextureFactory.image(width: 256, height: 256) { u, v, _, _ in
            let pebble = leather(u, v) * 0.5 + 0.5
            let broad = ln.fbm(u * 4, v * 4, octaves: 3) * 0.5 + 0.5
            let c = TextureFactory.lerp(
                TextureFactory.rgb(0x8A4A2C), TextureFactory.rgb(0xB9714A), broad
            )
            return TextureFactory.lerp(c, TextureFactory.rgb(0x6E3720), (1 - pebble) * 0.5)
        }
        maps.leatherNormal = TextureFactory.normalMap(width: 256, height: 256, strength: 2.6, leather)
        maps.leatherRough = TextureFactory.scalarMap(width: 256, height: 256) { u, v in
            0.38 + (leather(u, v) * 0.5 + 0.5) * 0.24
        }

        // Deep pile: strong high-frequency normal, very high roughness, no specular to
        // speak of. The rug is a large bright area, so its texture carries a lot of frame.
        let rn = TextureFactory.Noise(seed: 1357)
        func shag(_ u: Float, _ v: Float) -> Float {
            rn.fbm(u * 110, v * 110, octaves: 4) * 0.7 + rn.fbm(u * 300, v * 300, octaves: 2) * 0.3
        }
        maps.rugBase = TextureFactory.image(width: 384, height: 384) { u, v, _, _ in
            let pile = shag(u, v) * 0.5 + 0.5
            let broad = rn.fbm(u * 5, v * 5, octaves: 3) * 0.5 + 0.5
            let c = TextureFactory.lerp(
                TextureFactory.rgb(0xE4DED2), TextureFactory.rgb(0xF3EEE5), broad
            )
            return TextureFactory.lerp(c, TextureFactory.rgb(0xC5BCAC), (1 - pile) * 0.55)
        }
        maps.rugNormal = TextureFactory.normalMap(width: 384, height: 384, strength: 4.5, shag)

        // The linen weave is visible precisely because the shade is backlit.
        let sn = TextureFactory.Noise(seed: 2468)
        maps.shadeBase = TextureFactory.image(width: 256, height: 256) { u, v, _, _ in
            let warp = abs(sin(u * .pi * 90)) * 0.5
            let weft = abs(sin(v * .pi * 90)) * 0.5
            let weave = (warp + weft) * 0.5 + sn.fbm(u * 60, v * 60, octaves: 2) * 0.2
            return TextureFactory.lerp(
                TextureFactory.rgb(0xF2E4C6), TextureFactory.rgb(0xFFF6E2), weave
            )
        }
    }
}

// MARK: - Small maths

func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = TextureFactory.clampUnit((x - edge0) / max(edge1 - edge0, 1e-6))
    return t * t * (3 - 2 * t)
}
