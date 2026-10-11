import Foundation
import RealityKit
import simd

// The kitchen run along the north wall.
//
// West → east: counter-depth French-door fridge, the structural column (built by the shell
// module), dishwasher, sink, slide-in gas range under a stainless chimney hood, then a
// short counter with an under-counter microwave. Everything faces south (+Z); the wall is
// at Z = 0.
//
// The run is authored in world coordinates and then re-based onto each prop's footprint
// centre at the end, because the plan reads in world X and translating twice is cheaper
// than doing the arithmetic in every call site.

enum KitchenModule: DemoModule {

    // MARK: - Shared constants

    private typealias K = Plan.Kitchen

    /// Door and drawer fronts stand this far proud of the carcass.
    private static let frontThickness: Float = 0.019
    /// The shadow line between adjacent fronts. Without it a cabinet run is one box.
    private static let reveal: Float = 0.003
    private static let toeHeight: Float = 0.09
    private static let toeSetback: Float = 0.06
    private static let counterThickness: Float = 0.04

    private static var carcassTop: Float { Plan.Kitchen.counterHeight - counterThickness }

    // MARK: - Build

    static func build(_ m: DemoMaterials) -> [DemoProp] {
        var props: [DemoProp] = []
        props.append(baseRun(m))
        props.append(countertop(m))
        props.append(backsplash(m))
        props.append(upperCabinets(m))
        props.append(underCabinetLight(m))
        props.append(fridge(m))
        props.append(range(m))
        props.append(hood(m))
        props.append(microwave(m))
        props.append(dishwasher(m))
        props.append(sink(m))
        props.append(trackLight(m))
        props.append(contentsOf: counterProps(m))
        return props
    }

    // MARK: - 1. Base cabinets

    /// The two runs of base cabinetry that survive between the appliance bays: under the
    /// sink, and under the microwave counter at the east end.
    private static func baseRun(_ m: DemoMaterials) -> DemoProp {
        var carcass = MeshAccumulator()
        var faces = MeshAccumulator()
        var kick = MeshAccumulator()

        let frontZ = K.baseDepth - frontThickness

        func bank(_ x0: Float, _ x1: Float) {
            carcass.append(block(x0, x1, toeHeight, carcassTop, 0, frontZ))
            kick.append(block(x0, x1, 0, toeHeight, 0, K.baseDepth - toeSetback))
        }

        // Sink bank: two tall doors, no drawer — the basin takes the space above.
        bank(K.sinkX.lowerBound, K.sinkX.upperBound)
        faces.append(fronts(
            K.sinkX.lowerBound, K.sinkX.upperBound,
            toeHeight, carcassTop, frontZ, K.baseDepth, count: 2
        ))

        // Microwave bank: the appliance occupies the upper half, so only a deep drawer below.
        bank(K.microwaveX.lowerBound, K.microwaveX.upperBound)
        let drawerTop: Float = 0.50
        faces.append(fronts(
            K.microwaveX.lowerBound, K.microwaveX.upperBound,
            toeHeight, drawerTop, frontZ, K.baseDepth, count: 1
        ))

        var pulls = MeshAccumulator()
        pulls.append(pullStrip(K.sinkX.lowerBound, K.sinkX.upperBound, top: carcassTop, frontZ: K.baseDepth))
        pulls.append(pullStrip(K.microwaveX.lowerBound, K.microwaveX.upperBound, top: drawerTop, frontZ: K.baseDepth))

        let origin = SIMD2<Float>((K.sinkX.lowerBound + K.microwaveX.upperBound) / 2, K.baseDepth / 2)
        return DemoProp(
            id: "kitchen.baseCabinets",
            name: "Base cabinets",
            parts: [
                DemoPart(rebase(carcass, origin), m.darkCabinet),
                DemoPart(rebase(faces, origin), m.darkCabinet),
                DemoPart(rebase(pulls, origin), m.matteBlackPaint),
                DemoPart(rebase(kick, origin), m.matteBlackPaint)
            ],
            transform: DemoProp.at(origin.x, origin.y),
            behaviour: .fixed,
            category: .cabinetry
        )
    }

    // MARK: - 2. Countertop

    private static func countertop(_ m: DemoMaterials) -> DemoProp {
        var slab = MeshAccumulator()
        let y0 = K.counterHeight - counterThickness
        let y1 = K.counterHeight

        // West segment spans the dishwasher and the sink, so it is split into four strips
        // around the undermount cut-out rather than modelled as one slab.
        let holeX: ClosedRange<Float> = (K.sinkCentre - 0.29)...(K.sinkCentre + 0.29)
        let holeZ: ClosedRange<Float> = 0.13...0.51
        let westStart = K.columnX.upperBound
        let westEnd = K.rangeX.lowerBound
        slab.append(block(westStart, westEnd, y0, y1, 0, holeZ.lowerBound))
        slab.append(block(westStart, westEnd, y0, y1, holeZ.upperBound, K.counterDepth))
        slab.append(block(westStart, holeX.lowerBound, y0, y1, holeZ.lowerBound, holeZ.upperBound))
        slab.append(block(holeX.upperBound, westEnd, y0, y1, holeZ.lowerBound, holeZ.upperBound))

        // East segment: solid, over the microwave bank.
        slab.append(block(K.rangeX.upperBound, K.runEnd, y0, y1, 0, K.counterDepth))

        // A short upstand where the stone dies into the tile, so the joint is not a raw line.
        slab.append(block(westStart, westEnd, y1, y1 + 0.035, 0.004, 0.024))
        slab.append(block(K.rangeX.upperBound, K.runEnd, y1, y1 + 0.035, 0.004, 0.024))

        let origin = SIMD2<Float>((westStart + K.runEnd) / 2, K.counterDepth / 2)

        // The counter's collider has to be declared, and this is the clearest case in the
        // room for why. Inferred, its bounding box ran from the underside of the slab up to
        // the top of the 35 mm upstand at the back — so the "surface" the solver offered
        // was 941 mm, while every object on the counter is authored at the real 920 mm.
        // Each of them therefore started 21 mm *inside* the counter and was thrown out of it
        // on the first frame of physics. Declared, the quartz is 920 mm where the quartz is,
        // the upstand is a separate strip against the tile, and the sink is a hole a mug can
        // fall into rather than a lid it skates over.
        let holeZLocal = (holeZ.lowerBound - origin.y)...(holeZ.upperBound - origin.y)
        let frontZ = K.counterDepth - origin.y
        let backZ = -origin.y
        func surface(_ x0: Float, _ x1: Float, _ z0: Float, _ z1: Float) -> DemoProp.ColliderBox {
            .surface(
                x: (x0 - origin.x)...(x1 - origin.x), z: z0...z1,
                top: K.counterHeight, thickness: counterThickness
            )
        }
        let boxes: [DemoProp.ColliderBox] = [
            surface(westStart, westEnd, backZ, holeZLocal.lowerBound),
            surface(westStart, westEnd, holeZLocal.upperBound, frontZ),
            surface(westStart, holeX.lowerBound, holeZLocal.lowerBound, holeZLocal.upperBound),
            surface(holeX.upperBound, westEnd, holeZLocal.lowerBound, holeZLocal.upperBound),
            surface(K.rangeX.upperBound, K.runEnd, backZ, frontZ),
            // The upstand where the stone dies into the tile.
            .span(
                x: (westStart - origin.x)...(K.runEnd - origin.x),
                y: K.counterHeight...(K.counterHeight + 0.035),
                z: (0.004 - origin.y)...(0.024 - origin.y)
            )
        ]

        return DemoProp(
            id: "kitchen.countertop",
            name: "Quartz countertop",
            mesh: rebase(slab, origin),
            material: m.quartz,
            transform: DemoProp.at(origin.x, origin.y),
            behaviour: .fixed,
            category: .structure,
            colliderBoxes: boxes
        )
    }

    // MARK: - 3. Backsplash

    private static func backsplash(_ m: DemoMaterials) -> DemoProp {
        let x0 = K.columnX.upperBound
        let x1 = K.runEnd
        let y0 = K.counterHeight
        let y1 = K.backsplashTop
        // 1 UV unit = 1.2 m, which lands the generated tile grid on a 200 × 100 mm subway tile.
        let tile = Mesh.wallPlane(width: x1 - x0, height: y1 - y0, uvScale: 1 / 1.2)
            .transformed(by: Xf.translate((x0 + x1) / 2, (y0 + y1) / 2, 0.005))

        let origin = SIMD2<Float>((x0 + x1) / 2, 0.005)
        return DemoProp(
            id: "kitchen.backsplash",
            name: "Subway tile backsplash",
            mesh: rebase(tile, origin),
            material: m.subwayTile,
            transform: DemoProp.at(origin.x, origin.y),
            behaviour: .fixed,
            category: .structure
        )
    }

    // MARK: - 4. Upper cabinets

    private static func upperCabinets(_ m: DemoMaterials) -> DemoProp {
        var carcass = MeshAccumulator()
        var faces = MeshAccumulator()
        var pulls = MeshAccumulator()

        let frontZ = K.upperDepth - frontThickness

        func bank(_ x0: Float, _ x1: Float, doors: Int) {
            carcass.append(block(x0, x1, K.upperBottom, K.upperTop, 0, frontZ))
            faces.append(fronts(x0, x1, K.upperBottom, K.upperTop, frontZ, K.upperDepth, count: doors))
            // Uppers are pulled from beneath, so the recess reads at the bottom edge.
            pulls.append(block(
                x0 + reveal, x1 - reveal,
                K.upperBottom + 0.004, K.upperBottom + 0.018,
                frontZ - 0.004, K.upperDepth - 0.006
            ))
        }

        bank(K.columnX.upperBound, K.rangeX.lowerBound, doors: 2)
        bank(K.rangeX.upperBound, K.runEnd, doors: 1)

        // Over the fridge the box is as deep as the appliance and stops short of the hood run.
        let overFridgeBottom = K.fridgeHeight + 0.06
        carcass.append(block(
            K.fridgeX.lowerBound, K.fridgeX.upperBound,
            overFridgeBottom, K.upperTop, 0, K.fridgeDepth - frontThickness
        ))
        faces.append(fronts(
            K.fridgeX.lowerBound, K.fridgeX.upperBound,
            overFridgeBottom, K.upperTop, K.fridgeDepth - frontThickness, K.fridgeDepth, count: 1
        ))

        let origin = SIMD2<Float>((K.fridgeX.lowerBound + K.runEnd) / 2, K.upperDepth / 2)

        // Three boxes, and this is a bug fix rather than a refinement.
        //
        // The wall cabinets are one prop spanning the whole run, but they are not one
        // solid: the shallow banks over the counter are 340 mm deep and start at 1.46 m,
        // while the box over the fridge is 740 mm deep and starts at 1.88 m — above the
        // appliance, which is the whole point of it. A single inferred bounding box is the
        // union of those, so it reached **down to 1.46 m across the full 740 mm depth**,
        // straight through the top 350 mm of a 1.82 m fridge.
        //
        // While loose props were kinematic that cost nothing, because nothing was ever
        // solved against it. The moment the room settles under gravity the solver has a
        // 120 kg body a third of the way inside a static one, and it resolves that the only
        // way it can: it fired the fridge across the apartment at about 6 m/s, where it
        // demolished the ladder shelving and a bar stool on the way past and left the
        // shelf's contents hanging in mid-air. Everything downstream of that looked like a
        // separate bug and none of it was.
        //
        // Declared per box, the cabinets stop where they actually stop and the fridge slides
        // under its own 60 mm of clearance.
        let boxes: [DemoProp.ColliderBox] = [
            .span(
                x: (K.columnX.upperBound - origin.x)...(K.rangeX.lowerBound - origin.x),
                y: K.upperBottom...K.upperTop,
                z: (0 - origin.y)...(K.upperDepth - origin.y)
            ),
            .span(
                x: (K.rangeX.upperBound - origin.x)...(K.runEnd - origin.x),
                y: K.upperBottom...K.upperTop,
                z: (0 - origin.y)...(K.upperDepth - origin.y)
            ),
            .span(
                x: (K.fridgeX.lowerBound - origin.x)...(K.fridgeX.upperBound - origin.x),
                y: overFridgeBottom...K.upperTop,
                z: (0 - origin.y)...(K.fridgeDepth - origin.y)
            )
        ]

        return DemoProp(
            id: "kitchen.upperCabinets",
            name: "Upper cabinets",
            parts: [
                DemoPart(rebase(carcass, origin), m.darkCabinet),
                DemoPart(rebase(faces, origin), m.darkCabinet),
                DemoPart(rebase(pulls, origin), m.matteBlackPaint)
            ],
            transform: DemoProp.at(origin.x, origin.y),
            behaviour: .fixed,
            category: .cabinetry,
            colliderBoxes: boxes
        )
    }

    // MARK: - 5. Under-cabinet lighting

    private static func underCabinetLight(_ m: DemoMaterials) -> DemoProp {
        var strip = MeshAccumulator()
        var wash = MeshAccumulator()

        func run(_ x0: Float, _ x1: Float) {
            strip.append(block(x0 + 0.06, x1 - 0.06, K.upperBottom - 0.014, K.upperBottom - 0.002, 0.05, 0.28))
            // A short card on the tile stands in for the bounce the strip would throw.
            wash.append(
                Mesh.wallPlane(width: (x1 - x0) - 0.12, height: 0.10)
                    .transformed(by: Xf.translate((x0 + x1) / 2, K.upperBottom - 0.07, 0.014))
            )
        }

        run(K.columnX.upperBound, K.rangeX.lowerBound)
        run(K.rangeX.upperBound, K.runEnd)

        let origin = SIMD2<Float>((K.columnX.upperBound + K.runEnd) / 2, 0.16)
        return DemoProp(
            id: "kitchen.underCabinetLight",
            name: "Under-cabinet lighting",
            parts: [
                DemoPart(rebase(strip, origin), m.bulbGlow, castsShadow: false),
                DemoPart(rebase(wash, origin), m.bulbGlow, castsShadow: false)
            ],
            transform: DemoProp.at(origin.x, origin.y),
            behaviour: .fixed,
            category: .lighting
        )
    }

    // MARK: - 6. Refrigerator

    private static func fridge(_ m: DemoMaterials) -> DemoProp {
        let w = K.fridgeX.upperBound - K.fridgeX.lowerBound
        let d = K.fridgeDepth
        let h = K.fridgeHeight
        let hw = w / 2, hd = d / 2

        var steel = MeshAccumulator()
        var dark = MeshAccumulator()

        // Cabinet, set back behind the door faces.
        steel.append(block(-hw, hw, 0.06, h, -hd, hd - 0.028))

        let freezerTop: Float = 0.62
        // Freezer drawer.
        steel.append(block(-hw + reveal, hw - reveal, 0.07, freezerTop - reveal, hd - 0.028, hd))
        // French doors, split on the centre line.
        steel.append(block(-hw + reveal, -reveal, freezerTop + reveal, h - reveal, hd - 0.028, hd))
        steel.append(block(reveal, hw - reveal, freezerTop + reveal, h - reveal, hd - 0.028, hd))

        // Slim tubular handles: vertical either side of the seam, horizontal on the drawer.
        func bar(_ mesh: MeshAccumulator, _ t: simd_float4x4) { steel.append(mesh, transform: t) }
        let vertical = Mesh.cylinder(radius: 0.012, height: 0.58, segments: 12)
        bar(vertical, Xf.translate(-0.075, 0.96, hd + 0.03))
        bar(vertical, Xf.translate(0.075, 0.96, hd + 0.03))
        let horizontal = Mesh.cylinder(radius: 0.012, height: w - 0.22, segments: 12)
        bar(horizontal, Xf.translate(-(w - 0.22) / 2, 0.44, hd + 0.03) * Xf.rotateZ(-.pi / 2))
        // Stand-offs so the handles do not float.
        for z in [SIMD3<Float>(-0.075, 0.70, hd), SIMD3<Float>(-0.075, 1.22, hd),
                  SIMD3<Float>(0.075, 0.70, hd), SIMD3<Float>(0.075, 1.22, hd)] {
            steel.append(Mesh.cylinder(radius: 0.008, height: 0.03, segments: 8),
                         transform: Xf.translate(z) * Xf.rotateX(-.pi / 2))
        }

        // Recessed base grille.
        dark.append(block(-hw + 0.02, hw - 0.02, 0, 0.06, -hd, hd - 0.012))

        return DemoProp(
            id: "kitchen.fridge",
            name: "Refrigerator",
            parts: [DemoPart(steel, m.stainless), DemoPart(dark, m.matteBlackPaint)],
            transform: DemoProp.at((K.fridgeX.lowerBound + K.fridgeX.upperBound) / 2, hd),
            behaviour: .movable(mass: 120),
            category: .appliance
        )
    }

    // MARK: - 7. Slide-in gas range

    private static func range(_ m: DemoMaterials) -> DemoProp {
        let w = K.rangeX.upperBound - K.rangeX.lowerBound
        let hw = w / 2
        let bodyDepth: Float = 0.62
        let hd = bodyDepth / 2
        let deck = K.counterHeight            // the cooktop sits flush with the quartz
        let deckTop = deck + 0.005

        var steel = MeshAccumulator()
        var black = MeshAccumulator()

        // Carcass.
        steel.append(block(-hw, hw, 0, deck - 0.02, -hd, hd - 0.012))

        // Warming drawer, oven door, handle, bullnose.
        steel.append(block(-hw + reveal, hw - reveal, 0.02, 0.20, hd - 0.012, hd))
        steel.append(block(-hw + reveal, hw - reveal, 0.22, 0.78, hd - 0.012, hd))
        black.append(block(-hw + 0.05, hw - 0.05, 0.28, 0.72, hd, hd + 0.004))
        steel.append(Mesh.cylinder(radius: 0.014, height: w - 0.06, segments: 12),
                     transform: Xf.translate(-(w - 0.06) / 2, 0.82, hd + 0.035) * Xf.rotateZ(-.pi / 2))
        for x in [-(w - 0.10) / 2, (w - 0.10) / 2] {
            steel.append(Mesh.cylinder(radius: 0.010, height: 0.035, segments: 8),
                         transform: Xf.translate(x, 0.82, hd) * Xf.rotateX(-.pi / 2))
        }
        steel.append(block(-hw, hw, 0.80, deck - 0.02, hd - 0.012, hd + 0.02))

        // Black glass cooktop, overhanging the counter front slightly as slide-ins do.
        black.append(block(-hw - 0.008, hw + 0.008, deck - 0.02, deckTop, -hd, hd + 0.02))

        // Cast-iron grates: two grids of bars, one per burner pair.
        func grate(_ x0: Float, _ x1: Float) {
            let z0: Float = -0.26, z1: Float = 0.26
            let bar: Float = 0.012
            let top = deckTop + 0.022
            for i in 0...3 {
                let x = x0 + (x1 - x0) * Float(i) / 3
                black.append(block(x - bar / 2, x + bar / 2, deckTop, top, z0, z1))
            }
            for i in 0...2 {
                let z = z0 + (z1 - z0) * Float(i) / 2
                black.append(block(x0, x1, deckTop, top - 0.004, z - bar / 2, z + bar / 2))
            }
        }
        grate(-hw + 0.05, -0.02)
        grate(0.02, hw - 0.05)

        // Five burners: four under the grates plus a small centre-rear one.
        let burner = Mesh.lathe(
            profile: [SIMD2(0.03, 0), SIMD2(0.055, 0.004), SIMD2(0.058, 0.014), SIMD2(0.030, 0.020), SIMD2(0, 0.016)],
            segments: 20
        )
        let burnerSpots: [SIMD2<Float>] = [
            SIMD2(-0.20, -0.14), SIMD2(-0.20, 0.14),
            SIMD2(0.20, -0.14), SIMD2(0.20, 0.14),
            SIMD2(0, 0.02)
        ]
        for s in burnerSpots {
            black.append(burner, transform: Xf.translate(s.x, deckTop, s.y))
        }

        // Front knobs.
        let knob = Mesh.lathe(
            profile: [SIMD2(0.019, 0), SIMD2(0.020, 0.014), SIMD2(0.016, 0.022), SIMD2(0, 0.024)],
            segments: 16
        )
        for i in 0..<5 {
            let x = -hw + 0.10 + Float(i) * (w - 0.20) / 4
            black.append(knob, transform: Xf.translate(x, 0.865, hd + 0.02) * Xf.rotateX(.pi / 2))
        }

        return DemoProp(
            id: "kitchen.range",
            name: "Gas range",
            parts: [DemoPart(steel, m.stainless), DemoPart(black, m.matteBlackPaint)],
            transform: DemoProp.at(K.rangeCentre, hd),
            behaviour: .movable(mass: 75),
            category: .appliance,
            // The pan stands on the grates, not on the glass, so the top of the collider is
            // the top of the grate bars. Inferred it came back 14 mm lower and the pan sat
            // half-sunk through the cast iron.
            colliderBoxes: [
                .span(x: (-hw - 0.008)...(hw + 0.008), y: 0...deckTop, z: -hd...(hd + 0.04)),
                .surface(
                    x: (-hw + 0.05)...(hw - 0.05), z: -0.26...0.26,
                    top: Self.grateTop, thickness: 0.024
                )
            ]
        )
    }

    /// Top of the cast-iron grates: what a pan on this range actually rests on.
    static let grateTop: Float = Plan.Kitchen.counterHeight + 0.005 + 0.022

    // MARK: - 8. Chimney hood

    private static func hood(_ m: DemoMaterials) -> DemoProp {
        let canopyDepth: Float = 0.50
        let canopyTop: Float = 1.96
        let duct = SIMD2<Float>(0.30, 0.26)

        var steel = MeshAccumulator()
        // A tapered loft rather than a stack of boxes: the silhouette is the whole point of
        // a chimney hood and stepped sides read as a staircase from the dining zone.
        steel.append(loft(
            bottom: SIMD2(K.hoodWidth, canopyDepth), top: duct,
            y0: K.hoodBottom, y1: canopyTop, capBottom: true, capTop: false
        ))
        steel.append(loft(
            bottom: duct, top: duct,
            y0: canopyTop, y1: Plan.ceilingHeight, capBottom: false, capTop: false
        ))
        // A short lip so the canopy underside has thickness.
        steel.append(loft(
            bottom: SIMD2(K.hoodWidth, canopyDepth), top: SIMD2(K.hoodWidth - 0.04, canopyDepth - 0.04),
            y0: K.hoodBottom, y1: K.hoodBottom + 0.03, capBottom: false, capTop: false
        ))

        var glow = MeshAccumulator()
        for x in [-0.17 as Float, 0.17] {
            glow.append(
                Mesh.cylinder(radius: 0.035, height: 0.008, segments: 16),
                transform: Xf.translate(x, K.hoodBottom - 0.006, 0.02)
            )
        }

        return DemoProp(
            id: "kitchen.hood",
            name: "Range hood",
            parts: [DemoPart(steel, m.stainless), DemoPart(glow, m.bulbGlow, castsShadow: false)],
            transform: DemoProp.at(K.rangeCentre, canopyDepth / 2),
            behaviour: .fixed,
            category: .appliance
        )
    }

    // MARK: - 9. Under-counter microwave

    private static func microwave(_ m: DemoMaterials) -> DemoProp {
        let w: Float = 0.56, h: Float = 0.34, d: Float = 0.42
        let hw = w / 2, hd = d / 2
        let base: Float = 0.51

        var steel = MeshAccumulator()
        var black = MeshAccumulator()

        steel.append(block(-hw, hw, base, base + h, -hd, hd - 0.01))
        // Door: dark glass across most of the face, control column on the right.
        black.append(block(-hw + 0.012, hw - 0.15, base + 0.03, base + h - 0.03, hd - 0.01, hd))
        steel.append(block(hw - 0.15, hw - 0.012, base + 0.02, base + h - 0.02, hd - 0.01, hd + 0.002))
        black.append(block(hw - 0.135, hw - 0.03, base + 0.20, base + h - 0.05, hd + 0.002, hd + 0.004))
        steel.append(Mesh.cylinder(radius: 0.010, height: h - 0.14, segments: 10),
                     transform: Xf.translate(-hw + 0.05, base + 0.07, hd + 0.028))

        return DemoProp(
            id: "kitchen.microwave",
            name: "Microwave",
            parts: [DemoPart(steel, m.stainless), DemoPart(black, m.matteBlackPaint)],
            transform: DemoProp.at(Plan.Kitchen.microwaveCentre, Plan.Kitchen.baseDepth - hd),
            behaviour: .movable(mass: 17),
            category: .appliance
        )
    }

    // MARK: - 10. Dishwasher

    private static func dishwasher(_ m: DemoMaterials) -> DemoProp {
        let w = K.dishwasherX.upperBound - K.dishwasherX.lowerBound
        let hw = w / 2
        let hd = K.baseDepth / 2

        var steel = MeshAccumulator()
        var black = MeshAccumulator()

        black.append(block(-hw, hw, toeHeight, carcassTop, -hd, hd - 0.02))
        steel.append(block(-hw + reveal, hw - reveal, toeHeight, carcassTop - 0.06, hd - 0.02, hd))
        // Controls live on a recessed strip at the top of the door, hidden when closed.
        black.append(block(-hw + reveal, hw - reveal, carcassTop - 0.06, carcassTop - 0.012, hd - 0.03, hd - 0.008))
        steel.append(block(-hw + reveal, hw - reveal, carcassTop - 0.012, carcassTop, hd - 0.03, hd))
        black.append(block(-hw + 0.02, hw - 0.02, 0, toeHeight, -hd, hd - 0.03))

        return DemoProp(
            id: "kitchen.dishwasher",
            name: "Dishwasher",
            parts: [DemoPart(steel, m.stainless), DemoPart(black, m.matteBlackPaint)],
            transform: DemoProp.at((K.dishwasherX.lowerBound + K.dishwasherX.upperBound) / 2, hd),
            behaviour: .movable(mass: 42),
            category: .appliance
        )
    }

    // MARK: - 11. Sink and faucet

    private static func sink(_ m: DemoMaterials) -> DemoProp {
        let originZ: Float = 0.32
        let rim = Plan.Kitchen.counterHeight - counterThickness
        let floorY = rim - 0.21
        let hw: Float = 0.29, hd: Float = 0.19
        let wall: Float = 0.014

        var steel = MeshAccumulator()
        steel.append(block(-hw, hw, floorY, floorY + 0.012, -hd, hd))
        steel.append(block(-hw, -hw + wall, floorY, rim, -hd, hd))
        steel.append(block(hw - wall, hw, floorY, rim, -hd, hd))
        steel.append(block(-hw, hw, floorY, rim, -hd, -hd + wall))
        steel.append(block(-hw, hw, floorY, rim, hd - wall, hd))

        // Gooseneck: a swept tube. A straight riser plus a half-turn arc, which is what
        // gives the spout its characteristic overhang above the basin.
        let baseZ: Float = -0.26
        var path: [SIMD3<Float>] = [
            SIMD3(0, Plan.Kitchen.counterHeight + 0.02, baseZ),
            SIMD3(0, 1.12, baseZ)
        ]
        let arcCentreZ = baseZ + 0.075
        for i in 0...12 {
            let t = Float(i) / 12 * .pi
            path.append(SIMD3(0, 1.16 + sin(t) * 0.15, arcCentreZ - cos(t) * 0.075))
        }
        path.append(SIMD3(0, 1.10, arcCentreZ + 0.075))

        var black = MeshAccumulator()
        black.append(Mesh.lathe(
            profile: [SIMD2(0.030, 0), SIMD2(0.030, 0.018), SIMD2(0.022, 0.030)],
            segments: 20
        ), transform: Xf.translate(0, Plan.Kitchen.counterHeight, baseZ))
        black.append(sweep(path, radius: 0.016))
        black.append(Mesh.cylinder(radius: 0.020, height: 0.022, segments: 16),
                     transform: Xf.translate(0, 1.086, arcCentreZ + 0.075))

        return DemoProp(
            id: "kitchen.sink",
            name: "Sink and faucet",
            parts: [DemoPart(steel, m.stainless), DemoPart(black, m.blackMetal)],
            transform: DemoProp.at(Plan.Kitchen.sinkCentre, originZ),
            behaviour: .fixed,
            category: .structure,
            // Basin walls and a faucet post, not a bounding box. The bounding box here runs
            // from the basin floor to the top of the gooseneck — a solid 640 mm block
            // standing on the counter, 290 mm of it above the quartz. Anything sliding
            // toward the sink climbed onto it and sat there. Declared, the sink is a hole
            // with something in the middle of it, which is what a sink is.
            colliderBoxes: [
                .surface(x: -hw...hw, z: -hd...hd, top: floorY + 0.012, thickness: 0.012),
                .span(x: -hw...(-hw + wall), y: floorY...rim, z: -hd...hd),
                .span(x: (hw - wall)...hw, y: floorY...rim, z: -hd...hd),
                .span(x: -hw...hw, y: floorY...rim, z: -hd...(-hd + wall)),
                .span(x: -hw...hw, y: floorY...rim, z: (hd - wall)...hd),
                .post(
                    at: SIMD2(0, -0.26), section: SIMD2(0.052, 0.052),
                    from: Plan.Kitchen.counterHeight, to: 1.31
                )
            ]
        )
    }

    // MARK: - 12. Ceiling track light

    private static func trackLight(_ m: DemoMaterials) -> DemoProp {
        let z0 = K.trackZ.lowerBound, z1 = K.trackZ.upperBound
        let originZ = (z0 + z1) / 2
        let railTop = Plan.ceilingHeight - 0.004
        let railBottom = railTop - 0.045

        var metal = MeshAccumulator()
        var glow = MeshAccumulator()

        metal.append(block(-0.026, 0.026, railBottom, railTop, z0 - originZ, z1 - originZ))
        // Two mounting pucks so the rail does not appear to float against the soffit.
        for t in [0.08 as Float, 0.92] {
            let z = (z0 + (z1 - z0) * t) - originZ
            metal.append(Mesh.cylinder(radius: 0.045, height: 0.012, segments: 16),
                         transform: Xf.translate(0, railTop, z))
        }

        let barrel = Mesh.cylinder(radius: 0.034, height: 0.11, segments: 16)
        let lens = Mesh.cylinder(radius: 0.030, height: 0.012, segments: 16)
            .transformed(by: Xf.translate(0, 0.104, 0))
        for i in 0..<K.trackHeadCount {
            let t = (Float(i) + 0.5) / Float(K.trackHeadCount)
            let z = (z0 + (z1 - z0) * t) - originZ
            metal.append(Mesh.cylinder(radius: 0.011, height: 0.05, segments: 10),
                         transform: Xf.translate(0, railBottom - 0.05, z))
            // Each head is aimed a little differently, as they are on the reference rail.
            let tilt = -0.26 + Float(i) * 0.13
            let frame = Xf.translate(0, railBottom - 0.04, z) * Xf.rotateX(tilt) * Xf.rotateZ(.pi)
            metal.append(barrel, transform: frame)
            glow.append(lens, transform: frame)
        }

        return DemoProp(
            id: "kitchen.trackLight",
            name: "Track lighting",
            parts: [
                DemoPart(metal, m.blackMetal),
                DemoPart(glow, m.bulbGlow, castsShadow: false)
            ],
            transform: DemoProp.at(K.trackX, originZ),
            behaviour: .fixed,
            category: .lighting
        )
    }

    // MARK: - 13. Counter props

    /// Everything loose on the counter and the cooktop.
    ///
    /// Each of these stands at exactly the height of the surface under it — 920 mm for the
    /// quartz, the top of the grates for the pan — because the colliders for those surfaces
    /// are now declared at exactly those heights. Author an object a centimetre high and it
    /// drops a centimetre when the room settles; author it a centimetre low and the solver
    /// spits it out. Neither is an earthquake.
    ///
    /// This is also the population the shake has to show. A kitchen with four things on the
    /// counter loses four things; a kitchen with ten loses ten, and the ones that break are
    /// the ones a person would actually have been standing next to.
    private static func counterProps(_ m: DemoMaterials) -> [DemoProp] {
        let counter = K.counterHeight

        // Sauté pan on the cooktop.
        var pan = MeshAccumulator()
        pan.append(Mesh.lathe(
            profile: [
                SIMD2(0, 0), SIMD2(0.085, 0), SIMD2(0.098, 0.012),
                SIMD2(0.104, 0.052), SIMD2(0.104, 0.058),
                SIMD2(0.096, 0.055), SIMD2(0.090, 0.016), SIMD2(0, 0.010)
            ],
            segments: 24
        ))
        pan.append(Mesh.taper(bottomRadius: 0.013, topRadius: 0.009, height: 0.20, segments: 10),
                   transform: Xf.translate(0.09, 0.042, 0) * Xf.rotateZ(-1.30))

        // Oil bottle.
        let bottle = Mesh.lathe(
            profile: [
                SIMD2(0, 0), SIMD2(0.032, 0), SIMD2(0.034, 0.014), SIMD2(0.034, 0.150),
                SIMD2(0.021, 0.190), SIMD2(0.013, 0.214), SIMD2(0.013, 0.252),
                SIMD2(0.017, 0.260), SIMD2(0, 0.266)
            ],
            segments: 20
        )

        // Spice rack: a shallow tray of four jars.
        var tray = MeshAccumulator()
        tray.append(block(-0.11, 0.11, 0, 0.022, -0.045, 0.045))
        tray.append(block(-0.11, 0.11, 0.022, 0.05, -0.045, -0.037))
        tray.append(block(-0.11, 0.11, 0.022, 0.05, 0.037, 0.045))
        var jars = MeshAccumulator()
        for i in 0..<4 {
            let x = -0.0825 + Float(i) * 0.055
            jars.append(Mesh.cylinder(radius: 0.022, height: 0.082, segments: 12),
                        transform: Xf.translate(x, 0.022, 0))
        }
        var caps = MeshAccumulator()
        for i in 0..<4 {
            let x = -0.0825 + Float(i) * 0.055
            caps.append(Mesh.cylinder(radius: 0.023, height: 0.012, segments: 12),
                        transform: Xf.translate(x, 0.104, 0))
        }

        // Cutting board, leaning on the tile.
        let board = Mesh.box(SIMD3(0.30, 0.42, 0.020), uvScale: 2)
            .transformed(by: Xf.rotateX(-0.22) * Xf.translate(0, 0.21, 0))

        // Stovetop kettle: body, shoulder, spout and a bail handle.
        var kettleSteel = MeshAccumulator()
        kettleSteel.append(Mesh.lathe(
            profile: [
                SIMD2(0.000, 0.000), SIMD2(0.082, 0.000), SIMD2(0.086, 0.008),
                SIMD2(0.086, 0.104), SIMD2(0.072, 0.140), SIMD2(0.044, 0.164),
                SIMD2(0.030, 0.172), SIMD2(0.030, 0.186), SIMD2(0.000, 0.190)
            ],
            segments: 26
        ))
        kettleSteel.append(
            Mesh.taper(bottomRadius: 0.024, topRadius: 0.012, height: 0.115, segments: 12),
            transform: Xf.translate(0.062, 0.070, 0) * Xf.rotateZ(-0.62)
        )
        var kettleHandle = MeshAccumulator()
        // A bail: five short bars stepped over the top, which reads as an arc at this size.
        for i in 0..<5 {
            let t = (Float(i) + 0.5) / 5
            let a = (t - 0.5) * 2.4
            kettleHandle.append(
                Mesh.box(SIMD3(0.046, 0.014, 0.014)),
                transform: Xf.translate(sin(a) * 0.086, 0.180 + cos(a) * 0.074, 0)
                    * Xf.rotateZ(-a)
            )
        }

        // A stack of four stoneware plates, the classic thing that comes out of a cupboard
        // and off a counter in one piece and lands in several.
        var plates = MeshAccumulator()
        let plate = Mesh.lathe(
            profile: [
                SIMD2(0.000, 0.000), SIMD2(0.042, 0.000), SIMD2(0.052, 0.004),
                SIMD2(0.104, 0.012), SIMD2(0.128, 0.020), SIMD2(0.126, 0.024),
                SIMD2(0.098, 0.022), SIMD2(0.056, 0.014), SIMD2(0.000, 0.011)
            ],
            segments: 34
        )
        for i in 0..<4 {
            plates.append(plate, transform: Xf.translate(0, Float(i) * 0.016, 0))
        }

        return [
            DemoProp(
                id: "kitchen.pan", name: "Sauté pan",
                mesh: pan, material: m.stainless,
                transform: DemoProp.at(K.rangeCentre - 0.19, 0.30, y: grateTop),
                behaviour: .movable(mass: 1.6), category: .tableware
            ),
            DemoProp(
                id: "kitchen.oilBottle", name: "Oil bottle",
                mesh: bottle, material: m.matteBlackPaint,
                transform: DemoProp.at(K.rangeX.upperBound + 0.14, 0.18, y: counter),
                behaviour: .movable(mass: 0.9), category: .tableware
            ),
            DemoProp(
                id: "kitchen.spiceRack", name: "Spice rack",
                parts: [
                    DemoPart(tray, m.darkWood),
                    DemoPart(jars, m.amberGlass),
                    DemoPart(caps, m.blackMetal)
                ],
                transform: DemoProp.at(K.rangeX.upperBound + 0.42, 0.20, y: counter),
                behaviour: .movable(mass: 1.2), category: .decor
            ),
            DemoProp(
                id: "kitchen.cuttingBoard", name: "Cutting board",
                mesh: board, material: m.darkWood,
                transform: DemoProp.at(1.78, 0.10, y: counter),
                behaviour: .movable(mass: 1.3), category: .tableware
            ),
            DemoProp(
                id: "kitchen.kettle", name: "Kettle",
                parts: [
                    DemoPart(kettleSteel, m.stainless),
                    DemoPart(kettleHandle, m.blackMetal)
                ],
                transform: DemoProp.at(2.14, 0.20, y: counter, yaw: 0.5),
                behaviour: .movable(mass: 1.3), category: .tableware
            ),
            DemoProp(
                id: "kitchen.plates", name: "Stack of plates",
                mesh: plates, material: m.ceramicWhite,
                transform: DemoProp.at(1.80, 0.36, y: counter),
                behaviour: .movable(mass: 2.4), category: .tableware
            ),
            mug(id: "kitchen.mug.a", at: SIMD2(2.10, 0.46), yaw: 0.9, material: m.ceramicWhite),
            mug(id: "kitchen.mug.b", at: SIMD2(1.98, 0.56), yaw: -1.7, material: m.terracotta)
        ]
    }

    /// A mug: barrel, foot ring and a handle swept as a short chain of bars.
    ///
    /// 340 g, 95 mm tall, standing on a 920 mm counter. It is the smallest movable thing in
    /// the room, and that is deliberate — small objects on high surfaces are what a real
    /// quake fills a kitchen floor with, and a demo that only moves the furniture is a demo
    /// that has quietly stopped simulating the interesting half of the room.
    private static func mug(
        id: String, at position: SIMD2<Float>,
        yaw: Float, material: PhysicallyBasedMaterial
    ) -> DemoProp {
        var mesh = MeshAccumulator()
        mesh.append(Mesh.lathe(
            profile: [
                SIMD2(0.000, 0.000), SIMD2(0.036, 0.000), SIMD2(0.040, 0.006),
                SIMD2(0.042, 0.088), SIMD2(0.042, 0.095), SIMD2(0.037, 0.095),
                SIMD2(0.036, 0.014), SIMD2(0.000, 0.012)
            ],
            segments: 26
        ))
        for i in 0..<4 {
            let t = (Float(i) + 0.5) / 4
            let a = (t - 0.5) * 2.5
            mesh.append(
                Mesh.box(SIMD3(0.011, 0.030, 0.011)),
                transform: Xf.translate(0.040 + cos(a) * 0.020, 0.052 + sin(a) * 0.030, 0)
                    * Xf.rotateZ(-a)
            )
        }
        return DemoProp(
            id: id, name: "Mug",
            mesh: mesh, material: material,
            transform: DemoProp.at(position.x, position.y, y: K.counterHeight, yaw: yaw),
            behaviour: .movable(mass: 0.34), category: .tableware
        )
    }

    // MARK: - Local geometry helpers

    /// An axis-aligned block given by its two corners. Everything in the run is authored
    /// this way so the code reads as the plan does — in absolute X, Y, Z.
    private static func block(
        _ x0: Float, _ x1: Float, _ y0: Float, _ y1: Float, _ z0: Float, _ z1: Float,
        uvScale: Float = 1
    ) -> MeshAccumulator {
        let size = SIMD3(abs(x1 - x0), abs(y1 - y0), abs(z1 - z0))
        return Mesh.box(size, uvScale: uvScale)
            .transformed(by: Xf.translate((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
    }

    /// Splits a span into `count` fronts separated by a 3 mm reveal.
    private static func fronts(
        _ x0: Float, _ x1: Float, _ y0: Float, _ y1: Float,
        _ z0: Float, _ z1: Float, count: Int
    ) -> MeshAccumulator {
        guard count > 0 else { return MeshAccumulator() }
        var m = MeshAccumulator()
        let width = ((x1 - x0) - reveal * Float(count + 1)) / Float(count)
        guard width > 0 else { return m }
        for i in 0..<count {
            let sx = x0 + reveal + Float(i) * (width + reveal)
            m.append(block(sx, sx + width, y0 + reveal, y1 - reveal, z0, z1))
        }
        return m
    }

    /// The thin dark line at the top of a base front. These cabinets have no hardware, so
    /// the pull is a shadow gap — modelling it is what stops the fronts reading as tiles.
    private static func pullStrip(_ x0: Float, _ x1: Float, top: Float, frontZ: Float) -> MeshAccumulator {
        block(x0 + reveal, x1 - reveal, top - 0.020, top - 0.004, frontZ - 0.026, frontZ - 0.004)
    }

    /// Moves world-authored geometry into a prop's local space, whose origin is the
    /// footprint centre on the floor.
    private static func rebase(_ mesh: MeshAccumulator, _ origin: SIMD2<Float>) -> MeshAccumulator {
        mesh.transformed(by: Xf.translate(-origin.x, 0, -origin.y))
    }

    /// A four-sided loft between two axis-aligned rectangles. `Mesh.extrude` only makes
    /// prisms, and the hood's taper is the one silhouette in the kitchen that must not be
    /// stepped.
    private static func loft(
        bottom: SIMD2<Float>, top: SIMD2<Float>,
        y0: Float, y1: Float,
        capBottom: Bool = true, capTop: Bool = false
    ) -> MeshAccumulator {
        var m = MeshAccumulator()
        let b = bottom / 2, t = top / 2
        let lo: [SIMD3<Float>] = [
            SIMD3(-b.x, y0, b.y), SIMD3(b.x, y0, b.y), SIMD3(b.x, y0, -b.y), SIMD3(-b.x, y0, -b.y)
        ]
        let hi: [SIMD3<Float>] = [
            SIMD3(-t.x, y1, t.y), SIMD3(t.x, y1, t.y), SIMD3(t.x, y1, -t.y), SIMD3(-t.x, y1, -t.y)
        ]
        for i in 0..<4 {
            let j = (i + 1) % 4
            m.addQuad(lo[i], lo[j], hi[j], hi[i])
        }
        if capBottom { m.addQuad(lo[3], lo[2], lo[1], lo[0], normal: SIMD3(0, -1, 0)) }
        if capTop { m.addQuad(hi[0], hi[1], hi[2], hi[3], normal: SIMD3(0, 1, 0)) }
        return m
    }

    /// Sweeps a circular section along a polyline, with parallel-transported frames so the
    /// tube does not twist through the bend.
    private static func sweep(
        _ path: [SIMD3<Float>], radius: Float, segments: Int = 14
    ) -> MeshAccumulator {
        guard path.count >= 2 else { return MeshAccumulator() }
        var m = MeshAccumulator()
        var reference = SIMD3<Float>(1, 0, 0)
        var rings: [[UInt32]] = []
        rings.reserveCapacity(path.count)

        for i in 0..<path.count {
            let raw: SIMD3<Float>
            if i == 0 {
                raw = path[1] - path[0]
            } else if i == path.count - 1 {
                raw = path[i] - path[i - 1]
            } else {
                raw = path[i + 1] - path[i - 1]
            }
            guard simd_length(raw) > 1e-6 else { continue }
            let tangent = simd_normalize(raw)

            var n = reference - tangent * simd_dot(reference, tangent)
            if simd_length(n) < 1e-4 {
                let alt = SIMD3<Float>(0, 0, 1)
                n = alt - tangent * simd_dot(alt, tangent)
            }
            n = simd_normalize(n)
            reference = n
            let bitangent = simd_normalize(simd_cross(tangent, n))

            var row: [UInt32] = []
            row.reserveCapacity(segments + 1)
            let v = Float(i) / Float(path.count - 1)
            for s in 0...segments {
                let theta = Float(s) / Float(segments) * 2 * .pi
                let dir = n * cos(theta) + bitangent * sin(theta)
                row.append(m.addVertex(
                    path[i] + dir * radius, normal: dir,
                    uv: SIMD2(Float(s) / Float(segments), v)
                ))
            }
            rings.append(row)
        }

        guard rings.count >= 2 else { return m }
        for i in 0..<(rings.count - 1) {
            for s in 0..<segments {
                let a = rings[i][s], b = rings[i][s + 1]
                let c = rings[i + 1][s + 1], d = rings[i + 1][s]
                m.addTriangle(a, b, c)
                m.addTriangle(a, c, d)
            }
        }
        return m
    }
}
