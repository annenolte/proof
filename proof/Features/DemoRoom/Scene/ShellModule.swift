import CoreGraphics
import Foundation
import RealityKit
import simd
#if canImport(UIKit)
import UIKit
#endif

// The building shell: floor, ceiling, walls, baseboards, the kitchen column, the three
// window assemblies, the city beyond them, and the entry door.
//
// Unlike the furniture modules, the shell is authored directly in world space and left on
// an identity transform. A prop's local origin exists so that it topples about its own
// base during the quake; the shell never moves, so the indirection would only make every
// coordinate here one subtraction away from the plan it is supposed to mirror.
//
// Openings are made by *omission* rather than by subtraction: each wall is emitted as the
// set of rectangles that survive around its doors and windows — piers either side, a head
// piece over, a sill piece under. No CSG, no degenerate triangles, and the seams land
// exactly on the numbers in `Plan`.

@MainActor
enum ShellModule: DemoModule {

    static func build(_ m: DemoMaterials) -> [DemoProp] {
        var props: [DemoProp] = [floorProp(m), ceilingProp(m)]
        props.append(contentsOf: wallProps(m))
        props.append(baseboardProp(m))
        props.append(columnProp(m))
        props.append(contentsOf: windowProps(m))
        props.append(contentsOf: backdropProps(m))
        props.append(entryDoorProp(m))
        return props
    }

    // MARK: - Tuning

    /// The oak tile covers about 2 m, so half a UV per metre puts the planks at real width.
    private static let floorUV: Float = 0.5
    private static let ceilingUV: Float = 0.34
    private static let wallUV: Float = 0.5

    /// How far the baseboard stands out from the wall face.
    private static let baseboardProud: Float = 0.018

    /// Thickness of the plaster lining inside an opening.
    private static let lining: Float = 0.014

    // MARK: - Floor and ceiling

    private static func floorProp(_ m: DemoMaterials) -> DemoProp {
        let mesh = Mesh.floorPlane(width: Plan.width, depth: Plan.length, uvScale: floorUV)
            .transformed(by: Xf.translate(Plan.width / 2, 0, Plan.length / 2))
        return DemoProp(
            id: "shell.floor", name: "Floor", mesh: mesh, material: m.oakFloor,
            behaviour: .fixed, category: .structure,
            // The floor is a single plane, so its bounding box has no thickness at all —
            // inferred, it became a 20 mm slab straddling y = 0, and the whole apartment
            // stood 10 mm in the air on it. Declared as a real slab hanging *below* y = 0,
            // the floor's top face is the floor, and a chair leg authored at y = 0 rests on
            // it exactly.
            colliderBoxes: [
                .surface(
                    x: -0.25...(Plan.width + 0.25),
                    z: -0.25...(Plan.length + 0.25),
                    top: 0, thickness: 0.30
                )
            ]
        )
    }

    private static func ceilingProp(_ m: DemoMaterials) -> DemoProp {
        // A floor plane spun about X so its normal points down into the room. The rotation
        // has a positive determinant, so the winding stays consistent with the flipped normal.
        let mesh = Mesh.floorPlane(width: Plan.width, depth: Plan.length, uvScale: ceilingUV)
            .transformed(by: Xf.translate(Plan.width / 2, Plan.ceilingHeight, Plan.length / 2)
                * Xf.rotateX(.pi))
        return DemoProp(
            id: "shell.ceiling", name: "Ceiling", mesh: mesh, material: m.concreteCeiling,
            behaviour: .fixed, category: .structure
        )
    }

    // MARK: - Walls

    private static func wallProps(_ m: DemoMaterials) -> [DemoProp] {
        let door = Opening(span: Plan.Entry.doorZ, bottom: 0, top: Plan.Entry.doorHeight)
        let eastA = windowOpening(Plan.Window.eastA)
        let eastB = windowOpening(Plan.Window.eastB)
        let south = windowOpening(Plan.Window.south)

        // The reference splits tone at the kitchen: cool grey around the entry and the
        // cabinetry, warm greige from the dining zone south through the living room.
        let split = Plan.Zone.kitchenEnd

        func wall(
            _ id: String, _ name: String, _ side: Side,
            _ from: Float, _ to: Float, _ openings: [Opening],
            _ material: PhysicallyBasedMaterial
        ) -> DemoProp {
            var mesh = MeshAccumulator()
            addPanel(&mesh, side, from: from, to: to, openings: openings)
            return DemoProp(
                id: id, name: name, mesh: mesh, material: material,
                behaviour: .fixed, category: .structure
            )
        }

        return [
            wall("shell.wall.north", "North wall", .north, 0, Plan.width, [], m.wallCool),
            wall("shell.wall.west.kitchen", "West wall, kitchen", .west, 0, split, [], m.wallCool),
            wall("shell.wall.west.living", "West wall", .west, split, Plan.length, [], m.wallWarm),
            wall("shell.wall.east.entry", "East wall, entry", .east, 0, split, [door], m.wallCool),
            wall("shell.wall.east.living", "East wall", .east, split, Plan.length, [eastA, eastB], m.wallWarm),
            wall("shell.wall.south", "South wall", .south, 0, Plan.width, [south], m.wallWarm)
        ]
    }

    private static func windowOpening(_ span: ClosedRange<Float>) -> Opening {
        Opening(span: span, bottom: Plan.Window.sill, top: Plan.Window.head)
    }

    // MARK: - Baseboards

    /// One prop for every run in the apartment: the baseboard is a continuous line of trim
    /// and reads as one object, and merging it keeps a dozen slivers out of the draw list.
    private static func baseboardProp(_ m: DemoMaterials) -> DemoProp {
        var mesh = MeshAccumulator()

        // North wall is interrupted where the structural column lands on it.
        mesh.append(baseboardRun(.north, from: 0, to: Plan.Kitchen.columnX.lowerBound))
        mesh.append(baseboardRun(.north, from: Plan.Kitchen.columnX.upperBound, to: Plan.width))

        mesh.append(baseboardRun(.south, from: 0, to: Plan.width))
        mesh.append(baseboardRun(.west, from: 0, to: Plan.length))

        // Broken at the door; the window sills all sit well above the trim.
        mesh.append(baseboardRun(.east, from: 0, to: Plan.Entry.doorZ.lowerBound))
        mesh.append(baseboardRun(.east, from: Plan.Entry.doorZ.upperBound, to: Plan.length))

        // Four thin runs, one per wall — and this one is not a refinement, it is a bug fix.
        //
        // The baseboard is a single prop covering all four walls, so its *bounding box* is
        // the entire apartment footprint, 110 mm high. Inferred, that put an invisible
        // 4.70 × 9.40 m plinth across the whole floor: every piece of furniture in the room
        // was standing 96 mm in the air on a skirting board. It was invisible only because
        // the loose objects used to be kinematic and never fell onto it; the moment they are
        // allowed to settle under gravity, the whole room stands on a step.
        let h = Plan.baseboardHeight
        let t = baseboardProud
        let boxes: [DemoProp.ColliderBox] = [
            .span(x: 0...Plan.width, y: 0...h, z: 0...t),
            .span(x: 0...Plan.width, y: 0...h, z: (Plan.length - t)...Plan.length),
            .span(x: 0...t, y: 0...h, z: 0...Plan.length),
            .span(x: (Plan.width - t)...Plan.width, y: 0...h, z: 0...Plan.length)
        ]

        return DemoProp(
            id: "shell.baseboard", name: "Baseboard", mesh: mesh, material: m.baseboard,
            behaviour: .fixed, category: .structure,
            colliderBoxes: boxes
        )
    }

    private static func baseboardRun(_ side: Side, from s0: Float, to s1: Float) -> MeshAccumulator {
        guard s1 - s0 > 1e-4 else { return MeshAccumulator() }
        let t = baseboardProud
        let h = Plan.baseboardHeight
        let size: SIMD3<Float>
        switch side {
        case .north, .south: size = SIMD3(s1 - s0, h, t)
        case .west, .east: size = SIMD3(t, h, s1 - s0)
        }
        let centre = side.point((s0 + s1) / 2, h / 2, out: -t / 2)
        return Mesh.box(size).transformed(by: Xf.translate(centre))
    }

    // MARK: - Structural column

    private static func columnProp(_ m: DemoMaterials) -> DemoProp {
        let x = Plan.Kitchen.columnX
        let depth = Plan.Kitchen.columnDepth
        let t = baseboardProud

        // Buried 20 mm into the wall so the two coplanar faces cannot z-fight.
        let shaft = boxBetween(
            SIMD3(x.lowerBound, 0, -0.02),
            SIMD3(x.upperBound, Plan.ceilingHeight, depth)
        )

        // The trim wraps the three exposed faces and mitres round the front corners.
        var trim = MeshAccumulator()
        trim.append(boxBetween(
            SIMD3(x.lowerBound - t, 0, depth), SIMD3(x.upperBound + t, Plan.baseboardHeight, depth + t)
        ))
        trim.append(boxBetween(
            SIMD3(x.lowerBound - t, 0, 0), SIMD3(x.lowerBound, Plan.baseboardHeight, depth)
        ))
        trim.append(boxBetween(
            SIMD3(x.upperBound, 0, 0), SIMD3(x.upperBound + t, Plan.baseboardHeight, depth)
        ))

        return DemoProp(
            id: "shell.column", name: "Structural column",
            parts: [DemoPart(shaft, m.wallCool), DemoPart(trim, m.baseboard)],
            behaviour: .fixed, category: .structure
        )
    }

    // MARK: - Windows

    private static func windowProps(_ m: DemoMaterials) -> [DemoProp] {
        [
            (id: "shell.window.eastA", name: "East window", side: Side.east, span: Plan.Window.eastA),
            (id: "shell.window.eastB", name: "East window", side: Side.east, span: Plan.Window.eastB),
            (id: "shell.window.south", name: "South window", side: Side.south, span: Plan.Window.south)
        ].map { windowProp(id: $0.id, name: $0.name, side: $0.side, span: $0.span, m) }
    }

    private static func windowProp(
        id: String, name: String, side: Side, span: ClosedRange<Float>, _ m: DemoMaterials
    ) -> DemoProp {
        let sill = Plan.Window.sill
        let head = Plan.Window.head
        let wt = Plan.wallThickness
        let ft = Plan.Window.frameThickness

        // A reveal is what tells the eye the wall has thickness. Without it the glazing
        // reads as a picture hung on a plane, which is the single biggest tell in a
        // procedural interior. It is painted the cool tone, as in the reference, so it
        // separates from the warm wall it is cut through.
        var reveal = MeshAccumulator()
        reveal.append(sideBox(side, span.lowerBound, span.upperBound, head - lining, head, 0, wt))
        reveal.append(sideBox(side, span.lowerBound, span.upperBound, sill, sill + lining, 0, wt))
        reveal.append(sideBox(side, span.lowerBound, span.lowerBound + lining, sill, head, 0, wt))
        reveal.append(sideBox(side, span.upperBound - lining, span.upperBound, sill, head, 0, wt))

        // Glazing sits deep in the opening, close to the outer wall face.
        let frameBack = wt * 0.42
        let frameFront = frameBack + 0.055
        let s0 = span.lowerBound + lining, s1 = span.upperBound - lining
        let y0 = sill + lining, y1 = head - lining

        var frame = MeshAccumulator()
        frame.append(sideBox(side, s0, s1, y1 - ft, y1, frameBack, frameFront))
        frame.append(sideBox(side, s0, s1, y0, y0 + ft, frameBack, frameFront))
        frame.append(sideBox(side, s0, s0 + ft, y0 + ft, y1 - ft, frameBack, frameFront))
        frame.append(sideBox(side, s1 - ft, s1, y0 + ft, y1 - ft, frameBack, frameFront))

        let mid = (s0 + s1) / 2
        let mw = Plan.Window.mullionWidth
        frame.append(sideBox(side, mid - mw / 2, mid + mw / 2, y0 + ft, y1 - ft, frameBack, frameFront))

        var glass = MeshAccumulator()
        addFace(&glass, side, s0: s0, s1: s1, y0: y0, y1: y1, out: (frameBack + frameFront) / 2, uvScale: 1)

        return DemoProp(
            id: id, name: name,
            parts: [
                DemoPart(reveal, m.wallCool),
                DemoPart(frame, m.blackMetal),
                DemoPart(glass, m.glass, castsShadow: false)
            ],
            behaviour: .fixed, category: .glazing
        )
    }

    // MARK: - City backdrop

    /// Distance the painted city stands beyond the wall. Far enough that walking across the
    /// room shifts the skyline by a believable amount rather than swinging it like a poster.
    private static let backdropDistance: Float = 14
    private static let backdropTop: Float = 20
    private static let backdropBottom: Float = -24
    /// Where sky meets city in the drawn image, tuned so the horizon lands just above a
    /// standing eye — the apartment is several floors up, looking over rooftops.
    private static let horizonV: CGFloat = 0.42

    /// The exterior is emissive rather than lit. A daylit city is orders of magnitude
    /// brighter than an interior, and an unlit plane behind glass looks like grey card;
    /// pushing emission past 1 is what makes the window read as a hole in the wall.
    private static func backdropProps(_ m: DemoMaterials) -> [DemoProp] {
        // The two planes meet exactly at the outer corner so the corner glazing sees a
        // continuous city rather than a gap or an overlap.
        let cornerZ = Plan.length + backdropDistance
        let cornerX = Plan.width + backdropDistance

        let east = backdropQuad(
            .east, s0: -20, s1: cornerZ, y0: backdropBottom, y1: backdropTop, out: backdropDistance
        )
        let south = backdropQuad(
            .south, s0: -20, s1: cornerX, y0: backdropBottom, y1: backdropTop, out: backdropDistance
        )

        let eastMaterial = m.imageMaterial(
            cityImage(seed: 90210, craneAt: 0.34), roughness: 1, emissive: 0.85, name: "city.east"
        )
        let southMaterial = m.imageMaterial(
            cityImage(seed: 41773, craneAt: 0.71), roughness: 1, emissive: 0.85, name: "city.south"
        )

        return [
            DemoProp(
                id: "shell.backdrop.east", name: "City beyond",
                parts: [DemoPart(east, eastMaterial, castsShadow: false)],
                behaviour: .fixed, category: .glazing
            ),
            DemoProp(
                id: "shell.backdrop.south", name: "City beyond",
                parts: [DemoPart(south, southMaterial, castsShadow: false)],
                behaviour: .fixed, category: .glazing
            )
        ]
    }

    /// One depth slice of the skyline. Each is darker, taller and less hazed than the one
    /// behind it — the layering, not the silhouettes, is what creates distance.
    private struct CityLayer {
        var roof: ClosedRange<CGFloat>
        var towerChance: CGFloat
        var towerRoof: ClosedRange<CGFloat>
        var grey: ClosedRange<CGFloat>
        var lit: CGFloat
        var haze: CGFloat
        var width: ClosedRange<CGFloat>
        var clutter: CGFloat
    }

    /// Roof heights straddle the horizon rather than sitting above it: the apartment is
    /// several floors up, so most of the neighbouring stock reads as rooftops seen from
    /// slightly above, with only the occasional tower breaking the skyline.
    private static let cityLayers: [CityLayer] = [
        CityLayer(roof: -0.005...0.045, towerChance: 0.12, towerRoof: 0.06...0.115,
                  grey: 0.50...0.62, lit: 0.03, haze: 0.55, width: 0.030...0.075, clutter: 0),
        CityLayer(roof: -0.030...0.075, towerChance: 0.10, towerRoof: 0.09...0.160,
                  grey: 0.28...0.42, lit: 0.14, haze: 0.30, width: 0.035...0.095, clutter: 0.25),
        CityLayer(roof: -0.055...0.105, towerChance: 0.08, towerRoof: 0.12...0.200,
                  grey: 0.18...0.34, lit: 0.26, haze: 0.10, width: 0.040...0.110, clutter: 0.45)
    ]

    /// The reference view is not a monochrome skyline: brick red, painted green, sand and
    /// cool concrete all stay distinct through the haze. Each building borrows a hue from
    /// this stock and keeps whatever luminance its depth layer asked for.
    private static let cityStock: [(r: CGFloat, g: CGFloat, b: CGFloat)] = [
        (0.78, 0.76, 0.74), (0.86, 0.60, 0.48), (0.62, 0.70, 0.62),
        (0.70, 0.74, 0.84), (0.88, 0.80, 0.62), (0.80, 0.62, 0.58)
    ]

    private static func tinted(_ luminance: CGFloat, _ index: Int) -> UIColor {
        let t = cityStock[min(max(index, 0), cityStock.count - 1)]
        let k = luminance / max((t.r + t.g + t.b) / 3, 0.001)
        return UIColor(red: min(t.r * k, 1), green: min(t.g * k, 1), blue: min(t.b * k, 1), alpha: 1)
    }

    private static func cityImage(seed: UInt64, craneAt: CGFloat) -> CGImage? {
        let side = 1536
        return TextureFactory.draw(width: side, height: side, background: .black) { ctx, size in
            var rng = TextureFactory.SplitMix64(seed: seed)
            func rand(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { .random(in: lo...hi, using: &rng) }

            let w = size.width, h = size.height
            let horizon = h * horizonV

            // Dusk sky: cold overhead, warming steeply into the last of the light.
            fillGradient(
                ctx, CGRect(x: 0, y: 0, width: w, height: horizon),
                [hex(0x16233C), hex(0x33486F), hex(0x7C86A0), hex(0xC79470), hex(0xEEBC86)],
                [0, 0.30, 0.60, 0.86, 1]
            )
            fillGradient(
                ctx, CGRect(x: 0, y: horizon, width: w, height: h - horizon),
                [hex(0xB08163), hex(0x5C5158), hex(0x26242C)],
                [0, 0.30, 1]
            )

            for (index, layer) in cityLayers.enumerated() {
                var x: CGFloat = -w * 0.05
                while x < w * 1.05 {
                    let bw = w * rand(layer.width.lowerBound, layer.width.upperBound)
                    let tall = rand(0, 1) < layer.towerChance
                    let rise = tall
                        ? rand(layer.towerRoof.lowerBound, layer.towerRoof.upperBound)
                        : rand(layer.roof.lowerBound, layer.roof.upperBound)
                    let roof = horizon - h * rise
                    // Facades run off the bottom of the image; a shared base line would
                    // draw a hard rule straight across the middle of the view.
                    let rect = CGRect(x: x, y: roof, width: bw, height: h - roof)

                    let g = rand(layer.grey.lowerBound, layer.grey.upperBound)
                    ctx.setFillColor(tinted(g, Int(rand(0, CGFloat(cityStock.count) - 0.001))).cgColor)
                    ctx.fill(rect)

                    // A parapet lip catching the last of the sky.
                    ctx.setFillColor(tinted(min(g + 0.16, 1), 0).cgColor)
                    ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h * 0.0035))

                    // Lift overruns and tanks, which is what stops a roofline reading as a bar chart.
                    if layer.clutter > 0, rand(0, 1) < layer.clutter {
                        let cw = bw * rand(0.16, 0.34), ch = h * rand(0.008, 0.022)
                        let cx = rect.minX + rand(0.1, 0.62) * bw
                        ctx.setFillColor(tinted(g * 0.88, 0).cgColor)
                        ctx.fill(CGRect(x: cx, y: roof - ch, width: cw, height: ch))
                    }

                    if layer.lit > 0 {
                        drawLitWindows(ctx, in: rect, density: layer.lit, rand: rand)
                    }
                    x += bw + w * rand(0.001, 0.009)
                }

                // Aerial perspective, pooling on the horizon and thinning out into the sky.
                // A flat veil over the whole frame would wash the dusk out of the sky too.
                fillGradient(
                    ctx, CGRect(x: 0, y: 0, width: w, height: h),
                    [UIColor(red: 0.90, green: 0.75, blue: 0.60, alpha: 0),
                     UIColor(red: 0.90, green: 0.75, blue: 0.60, alpha: layer.haze * 0.30),
                     UIColor(red: 0.90, green: 0.75, blue: 0.60, alpha: layer.haze),
                     UIColor(red: 0.86, green: 0.70, blue: 0.56, alpha: layer.haze * 0.30)],
                    [0, max(horizonV - 0.22, 0.01), horizonV, 1]
                )

                // The crane belongs behind the nearest stock, not pasted over everything.
                if index == 1 { drawCrane(ctx, size: size, horizon: horizon, at: craneAt) }
            }

            // Streets and lower floors are already in shadow.
            fillGradient(
                ctx, CGRect(x: 0, y: horizon, width: w, height: h - horizon),
                [UIColor(white: 0.04, alpha: 0), UIColor(white: 0.04, alpha: 0.35),
                 UIColor(white: 0.03, alpha: 0.72)],
                [0, 0.30, 1]
            )

            // Final band of haze pooling on the horizon line itself.
            fillGradient(
                ctx, CGRect(x: 0, y: horizon - h * 0.13, width: w, height: h * 0.20),
                [UIColor(red: 0.97, green: 0.82, blue: 0.63, alpha: 0),
                 UIColor(red: 0.97, green: 0.82, blue: 0.63, alpha: 0.34),
                 UIColor(red: 0.92, green: 0.74, blue: 0.56, alpha: 0.06)],
                [0, 0.62, 1]
            )
        }
    }

    private static func drawLitWindows(
        _ ctx: CGContext, in rect: CGRect, density: CGFloat, rand: (CGFloat, CGFloat) -> CGFloat
    ) {
        let cell: CGFloat = 13
        let pane = CGSize(width: 5, height: 7)
        var y = rect.minY + 9
        while y < rect.maxY - 6 {
            var x = rect.minX + 5
            while x < rect.maxX - pane.width - 3 {
                if rand(0, 1) < density {
                    let warmth = rand(0.55, 1.0)
                    ctx.setFillColor(UIColor(
                        red: 1.0, green: 0.82 + warmth * 0.10, blue: 0.52 + warmth * 0.20,
                        alpha: 0.45 + warmth * 0.5
                    ).cgColor)
                    ctx.fill(CGRect(origin: CGPoint(x: x, y: y), size: pane))
                }
                x += cell
            }
            y += cell + 3
        }
    }

    /// The crane is the one landmark in the reference view; it is what makes the backdrop
    /// look like a photograph of somewhere rather than generic stock skyline.
    private static func drawCrane(_ ctx: CGContext, size: CGSize, horizon: CGFloat, at fraction: CGFloat) {
        let w = size.width, h = size.height
        let mastX = w * fraction
        let mastTop = horizon - h * 0.175
        let mastBottom = horizon + h * 0.02
        let mastWidth = w * 0.0065

        ctx.saveGState()
        ctx.setStrokeColor(UIColor(red: 0.92, green: 0.88, blue: 0.76, alpha: 0.82).cgColor)
        ctx.setLineWidth(max(w * 0.0016, 1.2))
        ctx.setLineCap(.round)

        // Mast: two legs plus a zig-zag lattice.
        ctx.move(to: CGPoint(x: mastX - mastWidth, y: mastTop))
        ctx.addLine(to: CGPoint(x: mastX - mastWidth, y: mastBottom))
        ctx.move(to: CGPoint(x: mastX + mastWidth, y: mastTop))
        ctx.addLine(to: CGPoint(x: mastX + mastWidth, y: mastBottom))
        var y = mastTop
        var leftFirst = true
        while y < mastBottom {
            let next = min(y + mastWidth * 2.4, mastBottom)
            ctx.move(to: CGPoint(x: mastX + (leftFirst ? -mastWidth : mastWidth), y: y))
            ctx.addLine(to: CGPoint(x: mastX + (leftFirst ? mastWidth : -mastWidth), y: next))
            leftFirst.toggle()
            y = next
        }

        // Jib and counter-jib, slung from an A-frame over the slewing ring.
        let jibY = mastTop + h * 0.014
        let jibEnd = mastX + w * 0.135
        let counterEnd = mastX - w * 0.048
        let apex = CGPoint(x: mastX, y: mastTop - h * 0.028)
        ctx.move(to: CGPoint(x: counterEnd, y: jibY))
        ctx.addLine(to: CGPoint(x: jibEnd, y: jibY))
        ctx.move(to: CGPoint(x: counterEnd, y: jibY - h * 0.008))
        ctx.addLine(to: CGPoint(x: jibEnd, y: jibY - h * 0.008))
        ctx.move(to: apex)
        ctx.addLine(to: CGPoint(x: jibEnd, y: jibY - h * 0.004))
        ctx.move(to: apex)
        ctx.addLine(to: CGPoint(x: counterEnd, y: jibY - h * 0.004))
        ctx.move(to: apex)
        ctx.addLine(to: CGPoint(x: mastX, y: jibY))

        // Hoist trolley and its cable.
        let trolleyX = mastX + w * 0.085
        ctx.move(to: CGPoint(x: trolleyX, y: jibY))
        ctx.addLine(to: CGPoint(x: trolleyX, y: jibY + h * 0.052))
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Entry door

    private static func entryDoorProp(_ m: DemoMaterials) -> DemoProp {
        let span = Plan.Entry.doorZ
        let height = Plan.Entry.doorHeight
        let wt = Plan.wallThickness
        let side = Side.east

        // Jamb lining plus a flat casing standing proud of the wall face.
        let casingWidth: Float = 0.072
        let casingProud: Float = 0.018
        var casing = MeshAccumulator()
        casing.append(sideBox(side, span.lowerBound, span.upperBound, height - lining, height, 0, wt))
        casing.append(sideBox(side, span.lowerBound, span.lowerBound + lining, 0, height, 0, wt))
        casing.append(sideBox(side, span.upperBound - lining, span.upperBound, 0, height, 0, wt))
        casing.append(sideBox(
            side, span.lowerBound - casingWidth, span.lowerBound, 0, height + casingWidth, -casingProud, 0
        ))
        casing.append(sideBox(
            side, span.upperBound, span.upperBound + casingWidth, 0, height + casingWidth, -casingProud, 0
        ))
        casing.append(sideBox(
            side, span.lowerBound - casingWidth, span.upperBound + casingWidth,
            height, height + casingWidth, -casingProud, 0
        ))

        // The slab hangs back from the casing so the opening keeps its depth.
        let gap: Float = 0.010
        let s0 = span.lowerBound + gap, s1 = span.upperBound - gap
        let y0 = gap, y1 = height - gap
        let back: Float = 0.030, front: Float = 0.075
        var slab = sideBox(side, s0, s1, y0, y1, back, front)

        // A raised stile-and-rail border, which is how a recessed panel reads from inside.
        let inset: Float = 0.115
        let lip: Float = 0.006
        slab.append(sideBox(side, s0, s1, y0, y0 + inset, back - lip, back))
        slab.append(sideBox(side, s0, s1, y1 - inset, y1, back - lip, back))
        slab.append(sideBox(side, s0, s0 + inset, y0 + inset, y1 - inset, back - lip, back))
        slab.append(sideBox(side, s1 - inset, s1, y0 + inset, y1 - inset, back - lip, back))

        // Handle. Authored straight in world space: the plan only ever puts a door on the
        // east wall, and a generic rotation here would obscure a very simple placement.
        let faceX = Plan.width + back - lip
        let handleY: Float = 1.04
        let handleZ = span.upperBound - 0.095
        var hardware = Mesh.cylinder(radius: 0.033, height: 0.015, segments: 24)
            .transformed(by: Xf.translate(faceX, handleY, handleZ) * Xf.rotateZ(.pi / 2))
        hardware.append(
            Mesh.box(SIMD3(0.026, 0.024, 0.125)),
            transform: Xf.translate(faceX - 0.032, handleY, handleZ - 0.055)
        )

        return DemoProp(
            id: "shell.door.entry", name: "Entry door",
            parts: [
                DemoPart(casing, m.baseboard),
                DemoPart(slab, m.matteBlackPaint),
                DemoPart(hardware, m.stainless)
            ],
            behaviour: .fixed, category: .structure
        )
    }

    // MARK: - Wall geometry

    /// A rectangular hole in a wall, measured along that wall's own axis.
    private struct Opening {
        var span: ClosedRange<Float>
        var bottom: Float
        var top: Float
    }

    /// The four walls, each with its own axis (`s`) and an outward direction. Expressing
    /// them this way lets one panel builder, one baseboard builder and one box builder
    /// serve all four without a switch at every call site.
    private enum Side {
        case north, south, west, east

        /// Points into the room.
        var normal: SIMD3<Float> {
            switch self {
            case .north: return SIMD3(0, 0, 1)
            case .south: return SIMD3(0, 0, -1)
            case .west: return SIMD3(1, 0, 0)
            case .east: return SIMD3(-1, 0, 0)
            }
        }

        /// `out` is measured from the interior face, positive going away from the room.
        func point(_ s: Float, _ y: Float, out: Float = 0) -> SIMD3<Float> {
            switch self {
            case .north: return SIMD3(s, y, -out)
            case .south: return SIMD3(s, y, Plan.length + out)
            case .west: return SIMD3(-out, y, s)
            case .east: return SIMD3(Plan.width + out, y, s)
            }
        }

        /// On two of the walls, increasing `s` runs against the counter-clockwise winding.
        var reversedWinding: Bool {
            switch self {
            case .north, .east: return false
            case .south, .west: return true
            }
        }
    }

    private static func addFace(
        _ mesh: inout MeshAccumulator, _ side: Side,
        s0: Float, s1: Float, y0: Float, y1: Float, out: Float = 0, uvScale: Float
    ) {
        guard s1 - s0 > 1e-4, y1 - y0 > 1e-4 else { return }
        let a = side.point(s0, y0, out: out)
        let b = side.point(s1, y0, out: out)
        let c = side.point(s1, y1, out: out)
        let d = side.point(s0, y1, out: out)
        let ua = SIMD2<Float>(s0 * uvScale, y0 * uvScale)
        let ub = SIMD2<Float>(s1 * uvScale, y0 * uvScale)
        let uc = SIMD2<Float>(s1 * uvScale, y1 * uvScale)
        let ud = SIMD2<Float>(s0 * uvScale, y1 * uvScale)
        if side.reversedWinding {
            mesh.addQuad(b, a, d, c, normal: side.normal, uv: (ub, ua, ud, uc))
        } else {
            mesh.addQuad(a, b, c, d, normal: side.normal, uv: (ua, ub, uc, ud))
        }
    }

    private static func addPanel(
        _ mesh: inout MeshAccumulator, _ side: Side,
        from s0: Float, to s1: Float, openings: [Opening]
    ) {
        let top = Plan.ceilingHeight
        let inRange = openings
            .filter { $0.span.lowerBound < s1 && $0.span.upperBound > s0 }
            .sorted { $0.span.lowerBound < $1.span.lowerBound }

        var cursor = s0
        for opening in inRange {
            let lo = max(opening.span.lowerBound, s0)
            let hi = min(opening.span.upperBound, s1)
            addFace(&mesh, side, s0: cursor, s1: lo, y0: 0, y1: top, uvScale: wallUV)
            addFace(&mesh, side, s0: lo, s1: hi, y0: 0, y1: opening.bottom, uvScale: wallUV)
            addFace(&mesh, side, s0: lo, s1: hi, y0: opening.top, y1: top, uvScale: wallUV)
            cursor = hi
        }
        addFace(&mesh, side, s0: cursor, s1: s1, y0: 0, y1: top, uvScale: wallUV)
    }

    private static func backdropQuad(
        _ side: Side, s0: Float, s1: Float, y0: Float, y1: Float, out: Float
    ) -> MeshAccumulator {
        var mesh = MeshAccumulator()
        let a = side.point(s0, y0, out: out)
        let b = side.point(s1, y0, out: out)
        let c = side.point(s1, y1, out: out)
        let d = side.point(s0, y1, out: out)
        // v = 0 at the top of the plane, so the drawn sky lands overhead.
        let ua = SIMD2<Float>(0, 1), ub = SIMD2<Float>(1, 1)
        let uc = SIMD2<Float>(1, 0), ud = SIMD2<Float>(0, 0)
        if side.reversedWinding {
            mesh.addQuad(b, a, d, c, normal: side.normal, uv: (ub, ua, ud, uc))
        } else {
            mesh.addQuad(a, b, c, d, normal: side.normal, uv: (ua, ub, uc, ud))
        }
        return mesh
    }

    /// An axis-aligned box expressed in a wall's own frame.
    private static func sideBox(
        _ side: Side, _ s0: Float, _ s1: Float, _ y0: Float, _ y1: Float,
        _ out0: Float, _ out1: Float
    ) -> MeshAccumulator {
        boxBetween(side.point(s0, y0, out: out0), side.point(s1, y1, out: out1))
    }

    private static func boxBetween(_ p: SIMD3<Float>, _ q: SIMD3<Float>) -> MeshAccumulator {
        let lo = simd_min(p, q), hi = simd_max(p, q)
        let size = hi - lo
        guard size.x > 1e-5, size.y > 1e-5, size.z > 1e-5 else { return MeshAccumulator() }
        return Mesh.box(size).transformed(by: Xf.translate((lo + hi) / 2))
    }

    // MARK: - Drawing helpers

    private static func hex(_ value: UInt32) -> UIColor {
        let c = TextureFactory.rgb(value)
        return UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }

    private static func fillGradient(
        _ ctx: CGContext, _ rect: CGRect, _ colours: [UIColor], _ locations: [CGFloat]
    ) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colours.map { $0.cgColor } as CFArray,
            locations: locations
        ) else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.minY),
            end: CGPoint(x: rect.minX, y: rect.maxY),
            options: []
        )
        ctx.restoreGState()
    }
}
