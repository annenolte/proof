import CoreGraphics
import Foundation
import RealityKit
import simd
#if canImport(UIKit)
import UIKit
#endif

// The living room: sofa, coffee table, swivel chair, ladder shelf, lamps and the artwork.
//
// This is the end of the apartment the camera lingers on, so it carries the most modelling
// effort in the demo. Two things do most of the work: soft-edged upholstery (nothing in a
// real room has a knife edge) and the button-tufted sofa back, which is real displaced
// geometry rather than a normal map because it is the surface the window light rakes across.

enum LivingModule: DemoModule {

    static func build(_ m: DemoMaterials) -> [DemoProp] {
        var props: [DemoProp] = [
            rug(m),
            sofa(m),
            sofaCushion(m, id: "living.sofa.cushionA", localX: -0.70, twist: 0.10),
            sofaCushion(m, id: "living.sofa.cushionB", localX: 0.68, twist: -0.14),
            coffeeTable(m),
            armchair(m),
            ladderShelf(m),
            floorLamp(m),
            console(m),
            consoleLamp(m),
            television(m),
            pouf(m),
            abstractArt(m),
            pierArt(m)
        ]
        props.append(contentsOf: coffeeTableTop(m))
        props.append(contentsOf: shelfContents(m))
        return props
    }

    // MARK: - Rug

    private static func rug(_ m: DemoMaterials) -> DemoProp {
        let outline = Outline.roundedRect(
            width: Plan.Living.rugSize.x,
            depth: Plan.Living.rugSize.y,
            cornerRadius: 0.05
        )
        // A shag rug has no crisp edge — the pile rolls over. A tiny fillet on a 28 mm slab
        // is the difference between "rug" and "sheet of paper".
        let mesh = Soft.extrude(
            outline, bottom: 0, top: Plan.Living.rugThickness,
            topFillet: 0.012, filletSegments: 3, uvScale: 0.6
        )
        return DemoProp(
            id: "living.rug", name: "Wool shag rug",
            mesh: mesh, material: m.woolRug,
            transform: Xf.translate(Plan.Living.rugCentre.x, 0, Plan.Living.rugCentre.y),
            behaviour: .fixed, category: .softFurnishing
        )
    }

    // MARK: - Sofa

    // Local frame: length along X, depth along Z, front face toward +Z. `sofaYaw` swings
    // that front to face east, into the room.
    private enum SofaGeom {
        static let length = Plan.Living.sofaLength
        static let depth = Plan.Living.sofaDepth
        static let legHeight: Float = 0.13
        static let plinthTop: Float = 0.30
        static let seatTop: Float = 0.45
        static let armWidth: Float = 0.155
        static let armTop: Float = 0.62
        static let backTop: Float = 0.80
        static let backThickness: Float = 0.16
        /// Z of the tufted face — the plane the seat cushions butt up against.
        static var backFace: Float { -depth / 2 + backThickness }
        static var backCentreZ: Float { -depth / 2 + backThickness / 2 }
    }

    private static func sofa(_ m: DemoMaterials) -> DemoProp {
        let g = SofaGeom.self
        var velvet = MeshAccumulator()
        var wood = MeshAccumulator()

        // Legs: slim, tapered, splayed to the corners.
        let leg = Mesh.taper(bottomRadius: 0.019, topRadius: 0.028, height: g.legHeight, segments: 12)
        let legX = g.length / 2 - 0.16
        let legZ = g.depth / 2 - 0.13
        for sx in [-legX, legX] {
            for sz in [-legZ, legZ] {
                wood.append(leg, transform: Xf.translate(sx, 0, sz))
            }
        }

        // Plinth: the upholstered frame the cushions sit in.
        let plinth = Outline.roundedRect(width: g.length, depth: g.depth, cornerRadius: 0.05)
        velvet.append(Soft.extrude(
            plinth, bottom: g.legHeight, top: g.plinthTop,
            bottomFillet: 0.035, topFillet: 0.03, uvScale: 1.4
        ))

        // Arms: full-depth rounded blocks. The generous top fillet is the whole silhouette.
        let armProfile = Outline.roundedRect(width: g.armWidth, depth: g.depth, cornerRadius: 0.06)
        let armX = g.length / 2 - g.armWidth / 2
        let arm = Soft.extrude(
            armProfile, bottom: g.legHeight, top: g.armTop,
            bottomFillet: 0.02, topFillet: 0.072, filletSegments: 5, uvScale: 1.4
        )
        velvet.append(arm, transform: Xf.translate(-armX, 0, 0))
        velvet.append(arm, transform: Xf.translate(armX, 0, 0))

        // Back panel, then the tufting laid over its front face.
        let backProfile = Outline.roundedRect(
            width: g.length, depth: g.backThickness, cornerRadius: 0.05
        )
        velvet.append(
            Soft.extrude(
                backProfile, bottom: g.legHeight, top: g.backTop,
                bottomFillet: 0.02, topFillet: 0.06, filletSegments: 5, uvScale: 1.4
            ),
            transform: Xf.translate(0, 0, g.backCentreZ)
        )

        let tuftWidth = g.length - 2 * g.armWidth - 0.02
        let tuftHeight = g.backTop - g.plinthTop - 0.10
        let tuftCentreY = g.plinthTop + 0.02 + tuftHeight / 2
        velvet.append(
            Soft.tuftedPanel(
                width: tuftWidth, height: tuftHeight,
                bulge: 0.026, columns: 6, rows: 3
            ),
            transform: Xf.translate(0, tuftCentreY, g.backFace)
        )

        // Seat cushions: three, with a real gap so the joints catch shadow.
        let innerWidth = g.length - 2 * g.armWidth - 0.02
        let gap: Float = 0.016
        let cushionWidth = (innerWidth - 2 * gap) / 3
        let cushionDepth = g.depth / 2 - g.backFace - 0.03
        let cushionZ = g.backFace + cushionDepth / 2
        let cushionProfile = Outline.superellipse(
            width: cushionWidth, depth: cushionDepth, exponent: 5.5, segments: 56
        )
        let cushion = Soft.extrude(
            cushionProfile, bottom: g.plinthTop - 0.01, top: g.seatTop,
            bottomFillet: 0.02, topFillet: 0.055, filletSegments: 5, uvScale: 1.4
        )
        for i in 0..<3 {
            let x = (Float(i) - 1) * (cushionWidth + gap)
            velvet.append(cushion, transform: Xf.translate(x, 0, cushionZ))
        }

        return DemoProp(
            id: "living.sofa", name: "Navy tufted sofa",
            parts: [DemoPart(velvet, m.navyVelvet), DemoPart(wood, m.darkWood)],
            transform: Xf.place(
                Plan.Living.sofaCentre.x, 0, Plan.Living.sofaCentre.y, yaw: Plan.Living.sofaYaw
            ),
            behaviour: .movable(mass: 68), category: .seating
        )
    }

    /// A cream throw cushion leaning back against the sofa. `localX` is along the sofa's
    /// own length axis; the prop is placed in world space so it topples about its own base.
    private static func sofaCushion(
        _ m: DemoMaterials, id: String, localX: Float, twist: Float
    ) -> DemoProp {
        let g = SofaGeom.self
        let localZ = g.backFace + 0.16
        let world = sofaLocalToWorld(localX, localZ)

        let profile = Outline.superellipse(width: 0.44, depth: 0.16, exponent: 3.4, segments: 48)
        var mesh = Soft.extrude(
            profile, bottom: -0.21, top: 0.21,
            bottomFillet: 0.075, topFillet: 0.075, filletSegments: 5, uvScale: 2
        )
        // Leaned back against the tufting, resting on the seat.
        mesh = mesh.transformed(by:
            Xf.translate(0, g.seatTop + 0.20, 0) * Xf.rotateX(-0.30) * Xf.rotateZ(twist * 0.6)
        )

        return DemoProp(
            id: id, name: "Cream cushion",
            mesh: mesh, material: m.creamFabric,
            transform: Xf.place(world.x, 0, world.y, yaw: Plan.Living.sofaYaw + twist),
            behaviour: .movable(mass: 0.8), category: .softFurnishing
        )
    }

    private static func sofaLocalToWorld(_ x: Float, _ z: Float) -> SIMD2<Float> {
        let c = cos(Plan.Living.sofaYaw), s = sin(Plan.Living.sofaYaw)
        return Plan.Living.sofaCentre + SIMD2(x * c + z * s, -x * s + z * c)
    }

    // MARK: - Coffee table

    private static func coffeeTable(_ m: DemoMaterials) -> DemoProp {
        let outline = Outline.pebble(
            width: Plan.Living.coffeeSize.x, depth: Plan.Living.coffeeSize.y, segments: 9
        )
        let top = Plan.Living.coffeeHeight
        var mesh = MeshAccumulator()

        // Three stacked shells rather than one slab: a recessed foot, a soft shoulder that
        // reads as a shadow gap, and the crowned body. That is what stops it looking extruded.
        mesh.append(Soft.extrude(
            Outline.scaled(outline, 0.80, 0.74), bottom: 0, top: 0.045,
            bottomFillet: 0.012, topFillet: 0.015, filletSegments: 3
        ))
        mesh.append(Soft.extrude(
            Outline.scaled(outline, 0.94, 0.92), bottom: 0.035, top: 0.085,
            bottomFillet: 0.028, filletSegments: 4
        ))
        mesh.append(Soft.extrude(
            outline, bottom: 0.07, top: top,
            bottomFillet: 0.045, topFillet: 0.085, filletSegments: 6, uvScale: 0.8
        ))

        return DemoProp(
            id: "living.coffeeTable", name: "Pebble coffee table",
            mesh: mesh, material: m.ceramicWhite,
            transform: Xf.place(
                Plan.Living.coffeeCentre.x, 0, Plan.Living.coffeeCentre.y,
                yaw: Plan.Living.coffeeYaw
            ),
            behaviour: .movable(mass: 40), category: .table,
            // The tabletop is declared so its face is exactly at `coffeeHeight`. Inferred,
            // it came back 14 mm short — the inset — and everything on the table spent the
            // demo sunk into it by the thickness of a fingernail, which reads as objects
            // *embedded in* furniture rather than resting on it. The recessed foot is
            // declared too, so the table can rock on it rather than on its full silhouette.
            colliderBoxes: [
                .span(x: -0.45...0.45, y: 0...0.085, z: -0.27...0.27),
                .surface(
                    x: -0.56...0.56, z: -0.35...0.35,
                    top: top, thickness: top - 0.07
                )
            ]
        )
    }

    /// What is on the coffee table: a vase, a stack of books, a bowl and the remotes.
    ///
    /// All four are placed *at* the tabletop height rather than at y = 0 with the height
    /// baked into their meshes. That matters: a prop's origin is its footprint on its own
    /// floor, and honouring that is what lets it topple about its base instead of about a
    /// point 350 mm underneath it.
    private static func coffeeTableTop(_ m: DemoMaterials) -> [DemoProp] {
        let deck = Plan.Living.coffeeHeight
        let centre = Plan.Living.coffeeCentre
        return [
            vase(m, transform: DemoProp.at(centre.x - 0.14, centre.y - 0.06, y: deck)),
            books(m, transform: DemoProp.at(centre.x + 0.30, centre.y + 0.10, y: deck, yaw: 0.22)),
            DemoProp(
                id: "living.coffee.bowl", name: "Ceramic bowl",
                mesh: bowl(foot: 0.042, rim: 0.115, height: 0.078),
                material: m.ceramicWhite,
                transform: DemoProp.at(centre.x - 0.36, centre.y + 0.16, y: deck),
                behaviour: .movable(mass: 0.65), category: .tableware
            ),
            remotes(m, transform: DemoProp.at(centre.x - 0.06, centre.y + 0.20, y: deck, yaw: -0.34))
        ]
    }

    /// Two remote controls lying side by side. Small, light, and the first things off a
    /// table — which is the point: a demo where only the heavy objects move is a demo that
    /// has quietly stopped simulating the light ones.
    private static func remotes(_ m: DemoMaterials, transform: simd_float4x4) -> DemoProp {
        var dark = MeshAccumulator()
        var keys = MeshAccumulator()
        for (i, yaw) in [Float(0.06), -0.11].enumerated() {
            let at = Xf.translate(Float(i) * 0.058 - 0.029, 0, 0) * Xf.rotateY(yaw)
            dark.append(Mesh.boxOnFloor(SIMD3(0.046, 0.018, 0.175)), transform: at)
            keys.append(
                Mesh.box(SIMD3(0.030, 0.002, 0.090)),
                transform: at * Xf.translate(0, 0.018, 0.020)
            )
        }
        return DemoProp(
            id: "living.coffee.remotes", name: "Remote controls",
            parts: [DemoPart(dark, m.matteBlackPaint), DemoPart(keys, m.blackMetal)],
            transform: transform,
            behaviour: .movable(mass: 0.28), category: .decor
        )
    }

    private static func vase(_ m: DemoMaterials, transform: simd_float4x4) -> DemoProp {
        // Bulbous shouldered vessel with a short collar, matching the amber piece on the table.
        let profile: [SIMD2<Float>] = [
            SIMD2(0.045, 0.000),
            SIMD2(0.056, 0.014),
            SIMD2(0.072, 0.048),
            SIMD2(0.084, 0.094),
            SIMD2(0.086, 0.132),
            SIMD2(0.078, 0.168),
            SIMD2(0.060, 0.204),
            SIMD2(0.047, 0.232),
            SIMD2(0.044, 0.252),
            SIMD2(0.047, 0.264)
        ]
        // Authored standing on y = 0, not on the tabletop. Baking the table height into the
        // mesh put the prop's origin 350 mm below its own base, so it pivoted about a point
        // in mid-air under the table instead of about the foot it is standing on.
        let mesh = Mesh.lathe(profile: profile, segments: 40)

        return DemoProp(
            id: "living.vase.amber", name: "Amber vase",
            mesh: mesh, material: m.amberGlass,
            transform: transform,
            behaviour: .movable(mass: 1.4), category: .decor
        )
    }

    private static func books(_ m: DemoMaterials, transform: simd_float4x4) -> DemoProp {
        var paper = MeshAccumulator()
        var black = MeshAccumulator()

        // Lower book: dark cover, the one carrying the stack.
        black.append(Mesh.boxOnFloor(SIMD3(0.28, 0.036, 0.215)))
        // Page block of the lower book, inset so a light seam shows under the cover.
        paper.append(
            Mesh.box(SIMD3(0.268, 0.026, 0.203)),
            transform: Xf.translate(0, 0.018, 0)
        )
        black.append(
            Mesh.box(SIMD3(0.245, 0.030, 0.185)),
            transform: Xf.rotateY(-0.33) * Xf.translate(0, 0.051, 0.012)
        )
        paper.append(
            Mesh.box(SIMD3(0.236, 0.021, 0.176)),
            transform: Xf.rotateY(-0.33) * Xf.translate(0, 0.051, 0.012)
        )

        return DemoProp(
            id: "living.books.coffee", name: "Books",
            parts: [DemoPart(black, m.matteBlackPaint), DemoPart(paper, m.paperWhite)],
            transform: transform,
            behaviour: .movable(mass: 0.9), category: .decor
        )
    }

    // MARK: - Swivel armchair

    /// Local frame: origin on the floor at the footprint centre, opening toward +Z, which is
    /// the same "front is +Z" convention the sofa uses. `armchairYaw` swings it into place.
    private enum ChairGeom {
        static let baseRadius: Float = 0.30
        static let baseTop: Float = 0.05
        static let columnTop: Float = 0.22
        static let seatBottom: Float = 0.34
        static let seatTop: Float = 0.44
        /// Inner and outer radius of the barrel. The gap between them is real wall
        /// thickness, so the back and arms are a solid rather than a single surface.
        static let shellInner: Float = 0.250
        static let shellOuter: Float = 0.350
        static let shellBottom: Float = 0.24
        static let backTop: Float = 0.78
        static let armTop: Float = 0.53
        /// 200° of sweep centred on the back leaves the front 160° open for the sitter.
        static let shellSweep: Float = 200 * .pi / 180
    }

    private static func armchair(_ m: DemoMaterials) -> DemoProp {
        let g = ChairGeom.self
        var leather = MeshAccumulator()
        var metal = MeshAccumulator()

        // Polished brass coin: a shallow flare, widest where it meets the floor.
        metal.append(Mesh.lathe(profile: [
            SIMD2(g.baseRadius, 0.000),
            SIMD2(g.baseRadius, 0.010),
            SIMD2(g.baseRadius - 0.024, 0.028),
            SIMD2(0.150, 0.043),
            SIMD2(0.106, g.baseTop)
        ], segments: 44))
        metal.append(
            Mesh.taper(
                bottomRadius: 0.100, topRadius: 0.094,
                height: g.columnTop - g.baseTop, segments: 24
            ),
            transform: Xf.translate(0, g.baseTop, 0)
        )

        // Seat pan: the upholstered block that skirts from the column out to the barrel. Its
        // waist is wider than `shellInner` at every angle, which is what buries the barrel's
        // bottom edge instead of leaving it visible as a floating rim.
        leather.append(Soft.extrude(
            Outline.superellipse(width: 0.56, depth: 0.54, exponent: 3.4, segments: 48),
            bottom: 0.20, top: g.seatBottom + 0.02,
            bottomFillet: 0.06, topFillet: 0.02, filletSegments: 4, uvScale: 1.6
        ))
        leather.append(Soft.extrude(
            Outline.superellipse(width: 0.62, depth: 0.60, exponent: 4.0, segments: 48),
            bottom: g.seatBottom, top: g.seatTop,
            bottomFillet: 0.02, topFillet: 0.05, filletSegments: 5, uvScale: 1.6
        ))

        // Back and arms as one swept ring. The top eases down from the back to the arm
        // fronts, which is the whole silhouette of a tub chair.
        leather.append(ringSegment(
            innerRadius: g.shellInner, outerRadius: g.shellOuter,
            startAngle: -.pi / 2 - g.shellSweep / 2, sweep: g.shellSweep,
            steps: 44, bottom: g.shellBottom
        ) { t in
            let u = abs(2 * t - 1)                  // 0 at the back, 1 at the arm fronts
            return g.backTop + (g.armTop - g.backTop) * (u * u * (3 - 2 * u))
        })

        // Cream scatter cushion, leaned into the back of the barrel.
        let cushion = Soft.extrude(
            Outline.superellipse(width: 0.34, depth: 0.13, exponent: 3.2, segments: 44),
            bottom: -0.15, top: 0.15,
            bottomFillet: 0.055, topFillet: 0.055, filletSegments: 4, uvScale: 2
        ).transformed(by:
            Xf.translate(0.02, 0.58, -0.15) * Xf.rotateX(-0.32) * Xf.rotateZ(-0.06)
        )

        return DemoProp(
            id: "living.armchair", name: "Cognac swivel chair",
            parts: [
                DemoPart(leather, m.cognacLeather),
                DemoPart(metal, m.brass),
                DemoPart(cushion, m.creamFabric)
            ],
            transform: Xf.place(
                Plan.Living.armchairCentre.x, 0, Plan.Living.armchairCentre.y,
                yaw: Plan.Living.armchairYaw
            ),
            behaviour: .movable(mass: 22), category: .seating
        )
    }

    /// Sweeps a thick ring segment about the Y axis: outer wall, inner wall, top and bottom
    /// caps, and a cap at each cut end. `height` gives the top of the wall at each point of
    /// the sweep, 0 at the start end and 1 at the finish.
    ///
    /// The barrel back is built this way rather than by extruding a C-shaped outline because
    /// every face is generated explicitly. There is no concave, near-self-touching polygon
    /// for `Triangulator.earClip` to fail on, and the result is closed from every angle.
    private static func ringSegment(
        innerRadius: Float, outerRadius: Float,
        startAngle: Float, sweep: Float, steps: Int,
        bottom: Float, height: (Float) -> Float
    ) -> MeshAccumulator {
        guard steps >= 2, outerRadius > innerRadius else { return MeshAccumulator() }
        var m = MeshAccumulator(
            reservingVertices: (steps + 1) * 8 + 8, triangles: steps * 8 + 4
        )

        var outerBot = [UInt32](), outerTop = [UInt32]()
        var innerBot = [UInt32](), innerTop = [UInt32]()
        var deckOut = [UInt32](), deckIn = [UInt32]()
        var soleOut = [UInt32](), soleIn = [UInt32]()

        let arcRate = (innerRadius + outerRadius) / 2 * sweep
        let dt = 0.5 / Float(steps)

        for i in 0...steps {
            let t = Float(i) / Float(steps)
            let a = startAngle + t * sweep
            let c = cos(a), s = sin(a)
            let top = height(t)
            let outward = SIMD3(c, 0, s)
            let uOut = t * sweep * outerRadius, uIn = t * sweep * innerRadius

            outerBot.append(m.addVertex(
                SIMD3(c * outerRadius, bottom, s * outerRadius),
                normal: outward, uv: SIMD2(uOut, 0)
            ))
            outerTop.append(m.addVertex(
                SIMD3(c * outerRadius, top, s * outerRadius),
                normal: outward, uv: SIMD2(uOut, top - bottom)
            ))
            innerBot.append(m.addVertex(
                SIMD3(c * innerRadius, bottom, s * innerRadius),
                normal: -outward, uv: SIMD2(uIn, 0)
            ))
            innerTop.append(m.addVertex(
                SIMD3(c * innerRadius, top, s * innerRadius),
                normal: -outward, uv: SIMD2(uIn, top - bottom)
            ))

            // The top cap falls away toward the arms, so its normal has to lean with that
            // slope — otherwise the roll over the arm tops shades as a flat band.
            let t0 = max(t - dt, 0), t1 = min(t + dt, 1)
            let slope = (height(t1) - height(t0)) / max(t1 - t0, 1e-5)
            let deckNormal = SIMD3(0, arcRate, 0) - SIMD3(-s, 0, c) * slope
            deckOut.append(m.addVertex(
                SIMD3(c * outerRadius, top, s * outerRadius),
                normal: deckNormal, uv: SIMD2(uOut, outerRadius)
            ))
            deckIn.append(m.addVertex(
                SIMD3(c * innerRadius, top, s * innerRadius),
                normal: deckNormal, uv: SIMD2(uIn, innerRadius)
            ))
            soleOut.append(m.addVertex(
                SIMD3(c * outerRadius, bottom, s * outerRadius),
                normal: SIMD3(0, -1, 0), uv: SIMD2(uOut, outerRadius)
            ))
            soleIn.append(m.addVertex(
                SIMD3(c * innerRadius, bottom, s * innerRadius),
                normal: SIMD3(0, -1, 0), uv: SIMD2(uIn, innerRadius)
            ))
        }

        for i in 0..<steps {
            m.addTriangle(outerBot[i], outerTop[i], outerTop[i + 1])
            m.addTriangle(outerBot[i], outerTop[i + 1], outerBot[i + 1])

            m.addTriangle(innerBot[i], innerBot[i + 1], innerTop[i + 1])
            m.addTriangle(innerBot[i], innerTop[i + 1], innerTop[i])

            m.addTriangle(deckIn[i], deckIn[i + 1], deckOut[i + 1])
            m.addTriangle(deckIn[i], deckOut[i + 1], deckOut[i])

            m.addTriangle(soleOut[i], soleOut[i + 1], soleIn[i + 1])
            m.addTriangle(soleOut[i], soleIn[i + 1], soleIn[i])
        }

        // The two cut ends, each facing away from the sweep.
        func endCap(angle: Float, top: Float, forward: Bool) {
            let c = cos(angle), s = sin(angle)
            let tangent = SIMD3(-s, 0, c)
            let ob = SIMD3(c * outerRadius, bottom, s * outerRadius)
            let ot = SIMD3(c * outerRadius, top, s * outerRadius)
            let ib = SIMD3(c * innerRadius, bottom, s * innerRadius)
            let it = SIMD3(c * innerRadius, top, s * innerRadius)
            if forward {
                m.addQuad(ib, ob, ot, it, normal: tangent)
            } else {
                m.addQuad(ob, ib, it, ot, normal: -tangent)
            }
        }
        endCap(angle: startAngle, top: height(0), forward: false)
        endCap(angle: startAngle + sweep, top: height(1), forward: true)

        return m
    }

    // MARK: - Ladder shelf

    /// The unit itself: two raked stiles on sled feet, five boards, two rear braces.
    ///
    /// **Nothing that stands on it is part of it any more.** Every book, vase and frame used
    /// to be appended into this prop's own mesh, binned by material to save draw calls. That
    /// was cheap and it was a lie: welded into the shelf's geometry, they were rigidly one
    /// body with it, so no amount of shaking could ever knock a single one off. The whole
    /// point of a bookshelf in an earthquake demo is that the books come off it. They are
    /// now separate rigid bodies resting on real planks — see `shelfContents`.
    ///
    /// The sled feet are new geometry, and they are here because the unit as drawn could not
    /// stand up. The stiles rake backwards, so the boards — and therefore most of the mass —
    /// sit *behind* the only two points touching the floor. Given an honest per-plank
    /// collider the thing simply fell over backwards on the first frame of gravity, which is
    /// the correct answer to the geometry it had. Real ladder shelving has a foot that
    /// reaches back under the load; this now has one, and it is drawn, not merely collided
    /// with. A collider that is not geometry is a way of hiding a modelling error.
    private static func ladderShelf(_ m: DemoMaterials) -> DemoProp {
        let s = Plan.Shelf.self
        let w = s.width
        let h = s.height
        let count = s.shelfCount

        var metal = MeshAccumulator()
        var boards = MeshAccumulator()

        let stileX = w / 2 - 0.026
        let stileLength = sqrt(h * h + s.lean * s.lean)
        let stile = Mesh.box(SIMD3(0.048, stileLength, 0.040))
        for sx in [-stileX, stileX] {
            metal.append(
                stile,
                transform: Xf.translate(sx, h / 2, s.frontZ(0) - s.lean / 2)
                    * Xf.rotateX(-atan(s.lean / h))
            )
        }

        // Sled feet: a bar under each stile reaching back to the rear of the base board.
        let footFront = s.frontZ(0) + 0.010
        let footBack = s.frontZ(0) - s.boardDepth(0) + 0.030
        let footDepth = footFront - footBack
        for sx in [-stileX, stileX] {
            metal.append(
                Mesh.boxOnFloor(SIMD3(0.048, 0.026, footDepth)),
                transform: Xf.translate(sx, 0, (footFront + footBack) / 2)
            )
        }
        metal.append(
            Mesh.boxOnFloor(SIMD3(w - 0.05, 0.022, 0.020)),
            transform: Xf.translate(0, 0, footBack + 0.010)
        )

        for i in 0..<count {
            let y = s.boardCentre(i)
            let sd = s.boardDepth(y)
            boards.append(
                Mesh.box(SIMD3(w - 0.012, s.boardThickness, sd), uvScale: 1.5),
                transform: Xf.translate(0, y, s.frontZ(y) - sd / 2)
            )
        }
        // Rear cross-braces, so the frame does not read as floating boards.
        for y in [s.boardCentre(0) - 0.20, s.boardCentre(count - 1) + 0.10] {
            metal.append(
                Mesh.box(SIMD3(w - 0.05, 0.020, 0.018)),
                transform: Xf.translate(0, y, s.frontZ(y) - s.boardDepth(y) + 0.02)
            )
        }

        return DemoProp(
            id: "living.ladderShelf", name: "Ladder shelving",
            parts: [DemoPart(metal, m.blackMetal), DemoPart(boards, m.matteBlackPaint)],
            transform: shelfFrame,
            behaviour: .movable(mass: 26), category: .storage,
            colliderBoxes: shelfColliders()
        )
    }

    /// One box per plank, one per upright, one per foot.
    ///
    /// A single bounding box here would be a solid 0.98 × 2.32 × 0.34 slab of shelving —
    /// no gaps, no surfaces, nothing to stand anything on. The compound is what turns the
    /// boards into places and the frame into something that can rock on its feet.
    private static func shelfColliders() -> [DemoProp.ColliderBox] {
        let s = Plan.Shelf.self
        let stileX = s.width / 2 - 0.026
        var boxes: [DemoProp.ColliderBox] = []

        // Each stile in two halves, so the rake is followed rather than swept into one
        // box — a swept box would hand the unit a 26 cm deep footprint it does not have,
        // and a bookshelf that cannot topple is the opposite of what this demo is for.
        for sx in [-stileX, stileX] {
            for half in 0..<2 {
                let y0 = Float(half) * s.height / 2
                let y1 = y0 + s.height / 2
                let z = s.frontZ((y0 + y1) / 2)
                boxes.append(.span(
                    x: (sx - 0.024)...(sx + 0.024),
                    y: y0...y1,
                    z: (z - 0.032)...(z + 0.032)
                ))
            }
            let footFront = s.frontZ(0) + 0.010
            let footBack = s.frontZ(0) - s.boardDepth(0) + 0.030
            boxes.append(.span(
                x: (sx - 0.024)...(sx + 0.024), y: 0...0.026, z: footBack...footFront
            ))
        }

        for i in 0..<s.shelfCount {
            let y = s.boardCentre(i)
            let front = s.frontZ(y)
            boxes.append(.surface(
                x: (-s.width / 2 + 0.006)...(s.width / 2 - 0.006),
                z: (front - s.boardDepth(y))...front,
                top: s.deck(i), thickness: s.boardThickness
            ))
        }
        return boxes
    }

    /// The prop-to-world frame of the shelving unit. Everything standing on it is placed
    /// through this, so a change to where the shelf is moves its contents with it.
    private static var shelfFrame: simd_float4x4 {
        Xf.place(Plan.Shelf.centre.x, 0, Plan.Shelf.centre.y, yaw: Plan.Shelf.yaw)
    }

    /// Where an object of the given depth stands on board `i`, in world space.
    private static func onShelf(
        _ i: Int, x: Float, depth: Float, yaw: Float = 0
    ) -> simd_float4x4 {
        shelfFrame
            * Xf.translate(x, Plan.Shelf.deck(i), Plan.Shelf.standZ(i, depth: depth))
            * Xf.rotateY(yaw)
    }

    // MARK: - What is on the shelf

    /// Fourteen loose objects on five boards, each its own rigid body with an honest mass.
    ///
    /// These are what the earthquake actually throws. Without them the shelf is a piece of
    /// furniture that either stands or falls, and the shake has one thing to show instead
    /// of fifteen. Masses are what the object would really weigh — a hardback is about
    /// 600 g, a 265 mm stoneware vase about 1.6 kg — because the d'Alembert force the quake
    /// applies is −m·a and a mass invented to look good is a lie about the acceleration.
    private static func shelfContents(_ m: DemoMaterials) -> [DemoProp] {
        var props: [DemoProp] = []

        // --- Board 0: a run of books with one leaning on the end of it, and a vase.
        props.append(bookRun(
            m, id: "living.shelf.books.lower", name: "Books",
            spec: [(0.034, 0.235, .paper), (0.022, 0.215, .dark),
                   (0.030, 0.250, .clay), (0.019, 0.205, .wood)],
            depth: 0.160, mass: 2.4,
            transform: onShelf(0, x: -0.30, depth: 0.160)
        ))
        props.append(DemoProp(
            id: "living.shelf.book.leaning", name: "Book",
            mesh: Mesh.boxOnFloor(SIMD3(0.030, 0.222, 0.155)),
            material: m.darkCabinet,
            transform: onShelf(0, x: -0.12, depth: 0.155),
            behaviour: .movable(mass: 0.6), category: .decor
        ))
        props.append(DemoProp(
            id: "living.shelf.vase.terracotta", name: "Terracotta vase",
            mesh: vessel(foot: 0.036, belly: 0.062, neck: 0.030, lip: 0.036, height: 0.185),
            material: m.terracotta,
            transform: onShelf(0, x: 0.30, depth: 0.124),
            behaviour: .movable(mass: 1.1), category: .decor
        ))

        // --- Board 1: a tall vase, a bookshelf speaker, two books lying flat.
        props.append(DemoProp(
            id: "living.shelf.vase.tall", name: "Stoneware vase",
            mesh: vessel(
                foot: 0.042, belly: 0.078, neck: 0.032, lip: 0.040,
                height: 0.265, bellyAt: 0.38
            ),
            material: m.ceramicWhite,
            transform: onShelf(1, x: -0.32, depth: 0.156),
            behaviour: .movable(mass: 1.6), category: .decor
        ))
        props.append(speaker(m, transform: onShelf(1, x: 0.24, depth: 0.190, yaw: -0.06)))
        props.append(flatBooks(
            m, id: "living.shelf.books.flat", transform: onShelf(1, x: -0.03, depth: 0.160)
        ))

        // --- Board 2: a framed photograph leaning back, and a lidded box.
        props.append(framedPhoto(
            m, transform: onShelf(2, x: -0.29, depth: 0.100)
        ))
        props.append(lidded(m, transform: onShelf(2, x: 0.26, depth: 0.162)))

        // --- Board 3: a shallow bowl, two upright books, a brass dish.
        props.append(DemoProp(
            id: "living.shelf.bowl", name: "Stoneware bowl",
            mesh: bowl(foot: 0.030, rim: 0.082, height: 0.062),
            material: m.ceramicWhite,
            transform: onShelf(3, x: -0.30, depth: 0.164),
            behaviour: .movable(mass: 0.5), category: .tableware
        ))
        props.append(bookRun(
            m, id: "living.shelf.books.upper", name: "Books",
            spec: [(0.030, 0.210, .paper), (0.024, 0.190, .clay)],
            depth: 0.150, mass: 1.1,
            transform: onShelf(3, x: 0.26, depth: 0.150)
        ))
        props.append(DemoProp(
            id: "living.shelf.brassDish", name: "Brass dish",
            mesh: Mesh.lathe(profile: [
                SIMD2(0.052, 0), SIMD2(0.056, 0.008), SIMD2(0.044, 0.020), SIMD2(0.012, 0.026)
            ], segments: 32),
            material: m.brass,
            transform: onShelf(3, x: 0.03, depth: 0.112),
            behaviour: .movable(mass: 0.45), category: .decor
        ))

        // --- Board 4: two vases and nothing else. It is the top shelf, it reads mostly as
        // silhouette — and it is the one whose contents have the furthest to fall.
        props.append(DemoProp(
            id: "living.shelf.vase.clay", name: "Clay vase",
            mesh: vessel(
                foot: 0.046, belly: 0.072, neck: 0.028, lip: 0.038,
                height: 0.235, bellyAt: 0.36
            ),
            material: m.terracotta,
            transform: onShelf(4, x: -0.28, depth: 0.144),
            behaviour: .movable(mass: 1.2), category: .decor
        ))
        props.append(DemoProp(
            id: "living.shelf.vase.squat", name: "Squat vase",
            mesh: vessel(
                foot: 0.040, belly: 0.058, neck: 0.038, lip: 0.046,
                height: 0.120, bellyAt: 0.46
            ),
            material: m.ceramicWhite,
            transform: onShelf(4, x: 0.26, depth: 0.116),
            behaviour: .movable(mass: 0.7), category: .decor
        ))

        return props
    }

    private enum BookCover { case paper, dark, clay, wood }

    private static func coverMaterial(_ cover: BookCover, _ m: DemoMaterials) -> PhysicallyBasedMaterial {
        switch cover {
        case .paper: return m.paperWhite
        case .dark: return m.darkCabinet
        case .clay: return m.terracotta
        case .wood: return m.darkWood
        }
    }

    /// A row of upright books, authored as one prop.
    ///
    /// One body rather than one per volume, because that is how a packed row behaves: books
    /// wedged upright between their neighbours go over as a block, and modelling four
    /// 600 g slabs stacked face-to-face gives the solver four near-coincident contacts to
    /// fight over for no visible gain.
    private static func bookRun(
        _ m: DemoMaterials, id: String, name: String,
        spec: [(width: Float, height: Float, cover: BookCover)],
        depth: Float, mass: Double, transform: simd_float4x4
    ) -> DemoProp {
        let total = spec.reduce(Float(0)) { $0 + $1.width } + Float(max(spec.count - 1, 0)) * 0.004
        var x = -total / 2
        var bins: [BookCover: MeshAccumulator] = [:]
        for book in spec {
            var bin = bins[book.cover] ?? MeshAccumulator()
            bin.append(
                Mesh.boxOnFloor(SIMD3(book.width, book.height, depth)),
                transform: Xf.translate(x + book.width / 2, 0, 0)
            )
            bins[book.cover] = bin
            x += book.width + 0.004
        }
        let parts = [BookCover.paper, .dark, .clay, .wood].compactMap { cover in
            bins[cover].map { DemoPart($0, coverMaterial(cover, m)) }
        }
        return DemoProp(
            id: id, name: name, parts: parts, transform: transform,
            behaviour: .movable(mass: mass), category: .decor
        )
    }

    private static func flatBooks(
        _ m: DemoMaterials, id: String, transform: simd_float4x4
    ) -> DemoProp {
        var dark = MeshAccumulator()
        var paper = MeshAccumulator()
        dark.append(Mesh.boxOnFloor(SIMD3(0.230, 0.032, 0.160)))
        paper.append(
            Mesh.boxOnFloor(SIMD3(0.205, 0.026, 0.150)),
            transform: Xf.translate(0, 0.032, 0) * Xf.rotateY(-0.09)
        )
        return DemoProp(
            id: id, name: "Books",
            parts: [DemoPart(dark, m.darkCabinet), DemoPart(paper, m.paperWhite)],
            transform: transform,
            behaviour: .movable(mass: 1.3), category: .decor
        )
    }

    /// A glazed photo frame on a strut, leaning back the way one stands on a shelf.
    ///
    /// Local origin is the bottom edge, so it pivots about the edge it is standing on. It
    /// carries glass, which is the point of it: a frame that comes off a 1.25 m shelf is a
    /// breakage, not a tidy-up.
    private static func framedPhoto(_ m: DemoMaterials, transform: simd_float4x4) -> DemoProp {
        let width: Float = 0.19, height: Float = 0.26
        let lean: Float = 0.19
        let upright = Xf.rotateX(-lean) * Xf.translate(0, height / 2, 0)

        var frame = MeshAccumulator()
        frame.append(
            Mesh.frame(outerWidth: width, outerHeight: height, thickness: 0.012, depth: 0.014),
            transform: upright
        )
        // The strut behind it, raked further back than the frame is, which is what actually
        // holds one of these up.
        frame.append(
            Mesh.boxOnFloor(SIMD3(0.020, height * 0.62, 0.006)),
            transform: Xf.rotateX(-0.46)
        )
        var print = MeshAccumulator()
        print.append(
            Mesh.box(SIMD3(width - 0.024, height - 0.024, 0.004)),
            transform: upright * Xf.translate(0, 0, -0.004)
        )
        var glazing = MeshAccumulator()
        glazing.append(
            Mesh.box(SIMD3(width - 0.024, height - 0.024, 0.002)),
            transform: upright * Xf.translate(0, 0, 0.005)
        )

        return DemoProp(
            id: "living.shelf.framedPhoto", name: "Framed photograph",
            parts: [
                DemoPart(frame, m.blackMetal),
                DemoPart(print, m.paperWhite),
                DemoPart(glazing, m.glass, castsShadow: false)
            ],
            transform: transform,
            behaviour: .movable(mass: 0.5), category: .decor
        )
    }

    private static func lidded(_ m: DemoMaterials, transform: simd_float4x4) -> DemoProp {
        var body = MeshAccumulator()
        var lid = MeshAccumulator()
        body.append(Mesh.boxOnFloor(SIMD3(0.200, 0.090, 0.150)))
        // Lid overhanging the body on all four sides — the lip is what makes it a container.
        lid.append(Mesh.boxOnFloor(SIMD3(0.212, 0.020, 0.162)), transform: Xf.translate(0, 0.090, 0))
        return DemoProp(
            id: "living.shelf.box", name: "Lidded box",
            parts: [DemoPart(body, m.darkCabinet), DemoPart(lid, m.ceramicWhite)],
            transform: transform,
            behaviour: .movable(mass: 1.0), category: .decor
        )
    }

    /// A small sealed bookshelf speaker: 3.2 kg of MDF and magnet on a shelf 780 mm up.
    /// One of the more dangerous things in the room by consequence, which is exactly why it
    /// is worth having in the scene.
    private static func speaker(_ m: DemoMaterials, transform: simd_float4x4) -> DemoProp {
        let w: Float = 0.160, h: Float = 0.260, d: Float = 0.190
        var box = MeshAccumulator()
        var cloth = MeshAccumulator()
        var cone = MeshAccumulator()

        box.append(Mesh.boxOnFloor(SIMD3(w, h, d)))
        // Baffle, recessed a hair so the cabinet edge catches a highlight around it.
        cloth.append(
            Mesh.box(SIMD3(w - 0.014, h - 0.014, 0.004)),
            transform: Xf.translate(0, h / 2, d / 2 - 0.001)
        )
        cone.append(
            Mesh.lathe(profile: [
                SIMD2(0.000, 0.000), SIMD2(0.048, 0.000), SIMD2(0.050, 0.006),
                SIMD2(0.046, 0.010), SIMD2(0.016, 0.032), SIMD2(0.000, 0.034)
            ], segments: 24),
            transform: Xf.translate(0, h * 0.34, d / 2 + 0.001) * Xf.rotateX(.pi / 2)
        )
        cone.append(
            Mesh.lathe(profile: [
                SIMD2(0.000, 0.000), SIMD2(0.024, 0.000), SIMD2(0.020, 0.012), SIMD2(0.000, 0.014)
            ], segments: 20),
            transform: Xf.translate(0, h * 0.74, d / 2 + 0.001) * Xf.rotateX(.pi / 2)
        )

        return DemoProp(
            id: "living.shelf.speaker", name: "Bookshelf speaker",
            parts: [
                DemoPart(box, m.darkWood),
                DemoPart(cloth, m.matteBlackPaint),
                DemoPart(cone, m.blackMetal)
            ],
            transform: transform,
            behaviour: .movable(mass: 3.2), category: .appliance
        )
    }

    // MARK: - Shelf decor

    /// A turned vessel described by the five points of its silhouette: foot, belly,
    /// shoulder, neck and a lip that flares back out.
    ///
    /// Naming the silhouette rather than hand-listing radii is what stops these reading as
    /// lumps — a shelf vase is only 60-80 mm across, so a soft shoulder or a missing lip is
    /// the entire difference between "vase" and "potato". 36 segments is where the rim stops
    /// looking faceted at the distance the orbit camera sees the shelf from.
    private static func vessel(
        foot: Float, belly: Float, neck: Float, lip: Float,
        height h: Float, bellyAt: Float = 0.42
    ) -> MeshAccumulator {
        func between(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
        let shoulder = bellyAt + (1 - bellyAt) * 0.42
        let neckY = bellyAt + (1 - bellyAt) * 0.80
        return Mesh.lathe(profile: [
            SIMD2(foot, 0),
            SIMD2(foot, h * 0.03),                                  // straight foot, sits flat
            SIMD2(between(foot, belly, 0.72), h * bellyAt * 0.5),
            SIMD2(belly, h * bellyAt),
            SIMD2(between(belly, neck, 0.55), h * shoulder),
            SIMD2(neck, h * neckY),
            SIMD2(neck * 0.98, h * 0.955),
            SIMD2(lip, h)
        ], segments: 36)
    }

    /// An open bowl: the profile climbs the outside, crosses the rim and comes back down the
    /// inside, so the rim has visible wall thickness instead of a knife edge.
    private static func bowl(foot: Float, rim: Float, height h: Float) -> MeshAccumulator {
        let wall: Float = 0.008
        return Mesh.lathe(profile: [
            SIMD2(foot, 0),
            SIMD2(foot, h * 0.10),
            SIMD2(rim * 0.78, h * 0.52),
            SIMD2(rim, h),
            SIMD2(rim - wall, h),
            SIMD2(rim * 0.70, h * 0.34),
            SIMD2(foot * 0.65, h * 0.16)
        ], segments: 34)
    }

    // MARK: - Lighting

    private static func floorLamp(_ m: DemoMaterials) -> DemoProp {
        let height = Plan.Living.floorLampHeight
        let shadeHeight: Float = 0.30
        var metal = MeshAccumulator()

        metal.append(Mesh.lathe(profile: [
            SIMD2(0.140, 0.000), SIMD2(0.148, 0.006), SIMD2(0.146, 0.016),
            SIMD2(0.040, 0.022), SIMD2(0.016, 0.030)
        ], segments: 36))
        metal.append(
            Mesh.taper(bottomRadius: 0.014, topRadius: 0.011, height: height - shadeHeight - 0.02, segments: 16),
            transform: Xf.translate(0, 0.028, 0)
        )

        // Drum shade, open at the bottom so the glow card inside reads as the source.
        let shade = Mesh.lathe(
            profile: [SIMD2(0.185, 0), SIMD2(0.203, shadeHeight)],
            segments: 40, capBottom: false, capTop: true
        ).transformed(by: Xf.translate(0, height - shadeHeight, 0))

        let glow = Mesh.cylinder(radius: 0.16, height: 0.10, segments: 24)
            .transformed(by: Xf.translate(0, height - shadeHeight + 0.03, 0))

        return DemoProp(
            id: "living.floorLamp", name: "Floor lamp",
            parts: [
                DemoPart(metal, m.blackMetal),
                DemoPart(shade, m.linenShade),
                DemoPart(glow, m.bulbGlow, castsShadow: false)
            ],
            transform: Xf.translate(
                Plan.Living.floorLampCentre.x, 0, Plan.Living.floorLampCentre.y
            ),
            behaviour: .movable(mass: 5), category: .lighting
        )
    }

    // MARK: - Console

    private static func console(_ m: DemoMaterials) -> DemoProp {
        let w = Plan.Living.consoleWidth
        let d = Plan.Living.consoleDepth
        let topY = Plan.Living.consoleTop - 0.036
        var wood = MeshAccumulator()
        var metal = MeshAccumulator()

        wood.append(
            Mesh.box(SIMD3(w, 0.036, d), uvScale: 1.2),
            transform: Xf.translate(0, topY + 0.018, 0)
        )
        wood.append(
            Mesh.box(SIMD3(w - 0.16, 0.020, d - 0.09), uvScale: 1.2),
            transform: Xf.translate(0, 0.24, 0)
        )
        let legX = w / 2 - 0.06, legZ = d / 2 - 0.05
        let leg = Mesh.taper(bottomRadius: 0.011, topRadius: 0.014, height: topY, segments: 12)
        for sx in [-legX, legX] {
            for sz in [-legZ, legZ] {
                metal.append(leg, transform: Xf.translate(sx, 0, sz))
            }
        }

        var boxes: [DemoProp.ColliderBox] = [
            .surface(
                x: (-w / 2)...(w / 2), z: (-d / 2)...(d / 2),
                top: Plan.Living.consoleTop, thickness: 0.036
            ),
            .surface(
                x: (-(w - 0.16) / 2)...((w - 0.16) / 2),
                z: (-(d - 0.09) / 2)...((d - 0.09) / 2),
                top: 0.25, thickness: 0.02
            )
        ]
        // Four legs, not one box. It is what makes the console able to go over sideways —
        // a 240 mm footprint under a 796 mm top — which is how a television ends up on the
        // floor rather than merely sliding along a plinth.
        for sx in [-legX, legX] {
            for sz in [-legZ, legZ] {
                boxes.append(.post(
                    at: SIMD2(sx, sz), section: SIMD2(0.028, 0.028), from: 0, to: topY
                ))
            }
        }

        return DemoProp(
            id: "living.console", name: "Console table",
            parts: [DemoPart(wood, m.darkWood), DemoPart(metal, m.blackMetal)],
            transform: Xf.place(
                Plan.Living.consoleCentre.x, 0, Plan.Living.consoleCentre.y, yaw: .pi / 2
            ),
            behaviour: .movable(mass: 24), category: .table,
            colliderBoxes: boxes
        )
    }

    /// A 32-inch panel on a two-foot pedestal stand, standing loose on the console.
    ///
    /// Nothing holds it down. That is the honest model of almost every television in a
    /// rented apartment, and it is the single object in this room whose behaviour people
    /// recognise from earthquake footage: it walks toward the front edge of whatever it is
    /// on, and then it goes over. The screen is glass and the stand is a narrow foot under
    /// a wide, top-heavy panel — the centre of mass is 300 mm above a 140 mm footprint.
    private static func television(_ m: DemoMaterials) -> DemoProp {
        let size = Plan.Living.tvSize
        let standHeight: Float = 0.055
        let bezel: Float = 0.012

        var shell = MeshAccumulator()
        var screen = MeshAccumulator()

        // Feet: two flat blades, splayed toward the ends of the panel as current sets are.
        for sx in [-size.x * 0.34, size.x * 0.34] {
            shell.append(
                Mesh.boxOnFloor(SIMD3(0.070, 0.014, 0.150)),
                transform: Xf.translate(sx, 0, 0)
            )
            shell.append(
                Mesh.boxOnFloor(SIMD3(0.030, standHeight, 0.040)),
                transform: Xf.translate(sx, 0.014, 0)
            )
        }
        // Panel: a thin slab standing on the feet, and a slightly thicker electronics
        // housing across its lower back, which is where a flat panel's mass really is.
        shell.append(
            Mesh.box(SIMD3(size.x, size.y, 0.022)),
            transform: Xf.translate(0, standHeight + size.y / 2, 0)
        )
        shell.append(
            Mesh.box(SIMD3(size.x * 0.62, size.y * 0.44, 0.026)),
            transform: Xf.translate(0, standHeight + size.y * 0.30, -0.023)
        )
        screen.append(
            Mesh.box(SIMD3(size.x - 2 * bezel, size.y - 2 * bezel, 0.003)),
            transform: Xf.translate(0, standHeight + size.y / 2, 0.012)
        )

        return DemoProp(
            id: "living.tv", name: "Television",
            parts: [
                DemoPart(shell, m.matteBlackPaint),
                DemoPart(screen, m.glass, castsShadow: false)
            ],
            // Faces west, back into the room, with its back to the east window.
            transform: DemoProp.at(
                Plan.Living.tvCentre.x, Plan.Living.tvCentre.y,
                y: Plan.Living.consoleTop, yaw: -.pi / 2
            ),
            behaviour: .movable(mass: 5.0), category: .appliance,
            // The panel and the feet, declared separately. The inferred box would be a
            // 0.72 × 0.48 × 0.15 solid — a television that cannot tip because its collider
            // stands on the full depth of its stand rather than on the two small blades
            // that actually touch the console.
            colliderBoxes: [
                .post(
                    at: SIMD2(-size.x * 0.34, 0), section: SIMD2(0.070, 0.150),
                    from: 0, to: 0.014
                ),
                .post(
                    at: SIMD2(size.x * 0.34, 0), section: SIMD2(0.070, 0.150),
                    from: 0, to: 0.014
                ),
                .span(
                    x: (-size.x / 2)...(size.x / 2),
                    y: standHeight...(standHeight + size.y),
                    z: -0.030...0.014
                )
            ]
        )
    }

    /// Authored standing on y = 0 and *placed* on the console, rather than modelled with
    /// the console's height baked into every vertex. The lamp now topples about its own
    /// base, and if the console goes over it goes with it.
    private static func consoleLamp(_ m: DemoMaterials) -> DemoProp {
        let shadeHeight: Float = 0.215
        var body = MeshAccumulator()

        body.append(Mesh.lathe(profile: [
            SIMD2(0.070, 0.000), SIMD2(0.078, 0.012), SIMD2(0.086, 0.052),
            SIMD2(0.080, 0.108), SIMD2(0.060, 0.150), SIMD2(0.030, 0.176),
            SIMD2(0.016, 0.190)
        ], segments: 34))
        body.append(
            Mesh.cylinder(radius: 0.010, height: 0.056, segments: 12),
            transform: Xf.translate(0, 0.188, 0)
        )
        let shade = Mesh.lathe(
            profile: [SIMD2(0.128, 0), SIMD2(0.148, shadeHeight)],
            segments: 36, capBottom: false, capTop: true
        ).transformed(by: Xf.translate(0, 0.238, 0))
        let glow = Mesh.cylinder(radius: 0.11, height: 0.08, segments: 20)
            .transformed(by: Xf.translate(0, 0.262, 0))

        return DemoProp(
            id: "living.consoleLamp", name: "Table lamp",
            parts: [
                DemoPart(body, m.ceramicWhite),
                DemoPart(shade, m.linenShade),
                DemoPart(glow, m.bulbGlow, castsShadow: false)
            ],
            transform: DemoProp.at(
                Plan.Light.consoleLamp.x, Plan.Living.consoleLampZ,
                y: Plan.Living.consoleTop
            ),
            behaviour: .movable(mass: 2.6), category: .lighting
        )
    }

    // MARK: - Pouf

    private static func pouf(_ m: DemoMaterials) -> DemoProp {
        let profile = Outline.superellipse(width: 0.50, depth: 0.50, exponent: 3.0, segments: 52)
        let mesh = Soft.extrude(
            profile, bottom: 0, top: 0.37,
            bottomFillet: 0.05, topFillet: 0.14, filletSegments: 7, uvScale: 2
        )
        return DemoProp(
            id: "living.pouf", name: "Mustard pouf",
            mesh: mesh, material: m.mustard,
            transform: Xf.place(Plan.Living.poufCentre.x, 0, Plan.Living.poufCentre.y, yaw: 0.4),
            behaviour: .movable(mass: 4), category: .seating
        )
    }

    // MARK: - Wall art

    private static func abstractArt(_ m: DemoMaterials) -> DemoProp {
        let size = Plan.Art.abstractSize
        let canvas = m.imageMaterial(
            abstractCanvasImage(), roughness: 0.52, name: "living.art.abstract"
        )
        // West wall: the piece must face +X (east, into the room), so +Z swings to +X.
        return framedArt(
            id: "living.art.abstract", name: "Abstract painting",
            size: size, canvas: canvas, frame: m.matteBlackPaint,
            transform: Xf.translate(
                Plan.Art.abstractCentre.x, Plan.Art.abstractY, Plan.Art.abstractCentre.y
            ) * Xf.rotateY(.pi / 2),
            mass: 6
        )
    }

    private static func pierArt(_ m: DemoMaterials) -> DemoProp {
        let size = Plan.Art.pierSize
        let canvas = m.imageMaterial(pierCanvasImage(), roughness: 0.52, name: "living.art.pier")
        // East wall: faces -X, back into the room.
        return framedArt(
            id: "living.art.pier", name: "Warm abstract",
            size: size, canvas: canvas, frame: m.matteBlackPaint,
            transform: Xf.translate(
                Plan.Art.pierCentre.x, Plan.Art.pierY, Plan.Art.pierCentre.y
            ) * Xf.rotateY(-.pi / 2),
            mass: 3
        )
    }

    /// A canvas on a backing board inside a slim dark frame. The local origin is the centre
    /// of the piece, since wall art pivots about its hanger rather than about a footprint.
    private static func framedArt(
        id: String, name: String, size: SIMD2<Float>,
        canvas: PhysicallyBasedMaterial, frame: PhysicallyBasedMaterial,
        transform: simd_float4x4, mass: Double
    ) -> DemoProp {
        let bar: Float = 0.028
        let depth: Float = 0.046
        var dark = MeshAccumulator()
        dark.append(Mesh.frame(
            outerWidth: size.x, outerHeight: size.y, thickness: bar, depth: depth
        ))
        dark.append(
            Mesh.box(SIMD3(size.x - bar, size.y - bar, 0.012)),
            transform: Xf.translate(0, 0, -depth / 2 + 0.006)
        )
        let face = Mesh.wallPlane(width: size.x - 2 * bar, height: size.y - 2 * bar)
            .transformed(by: Xf.translate(0, 0, depth / 2 - 0.004))

        return DemoProp(
            id: id, name: name,
            parts: [DemoPart(dark, frame), DemoPart(face, canvas)],
            transform: transform,
            behaviour: .mounted(mass: mass), category: .art
        )
    }

    // MARK: - Drawn canvases

    /// Five thick, irregular near-black verticals on white with a wide mount.
    ///
    /// The wobble comes from an integer hash rather than `Double.random`, so the painting is
    /// bit-identical on every launch — the demo gets rehearsed, and a canvas that repaints
    /// itself each run is a bug nobody notices until the room is on a projector.
    private static func abstractCanvasImage() -> CGImage? {
        TextureFactory.draw(width: 1024, height: 780, background: UIColor(white: 0.985, alpha: 1)) { ctx, size in
            let w = size.width, h = size.height
            let left = 0.095 * w, right = 0.905 * w
            let span = right - left

            let widths: [CGFloat] = [0.138, 0.113, 0.126, 0.147, 0.118]
            let leans: [CGFloat] = [0.012, -0.020, 0.008, -0.014, 0.022]
            let tops: [CGFloat] = [0.150, 0.128, 0.170, 0.134, 0.158]
            let bottoms: [CGFloat] = [0.862, 0.884, 0.848, 0.876, 0.840]
            let inks: [CGFloat] = [0.115, 0.095, 0.135, 0.088, 0.120]

            let gap = (1 - widths.reduce(0, +)) / CGFloat(widths.count - 1)
            var cursor = left

            for i in 0..<widths.count {
                let sw = widths[i] * span
                let x0 = cursor, x1 = cursor + sw
                let y0 = tops[i] * h, y1 = bottoms[i] * h
                let lean = leans[i] * span

                let path = CGMutablePath()
                let steps = 16
                var points = [CGPoint]()
                for s in 0...steps {
                    let t = CGFloat(s) / CGFloat(steps)
                    let y = y0 + (y1 - y0) * t
                    let jitter = wave(i * 7 + 1, Double(t) * 4.5) * sw * 0.085
                    points.append(CGPoint(x: x0 + lean * t + jitter, y: y))
                }
                for s in stride(from: steps, through: 0, by: -1) {
                    let t = CGFloat(s) / CGFloat(steps)
                    let y = y0 + (y1 - y0) * t
                    let jitter = wave(i * 7 + 53, Double(t) * 4.5) * sw * 0.085
                    points.append(CGPoint(x: x1 + lean * t + jitter, y: y))
                }
                path.addLines(between: points)
                path.closeSubpath()

                ctx.setFillColor(UIColor(white: inks[i], alpha: 1).cgColor)
                ctx.addPath(path)
                ctx.fillPath()

                cursor += sw + gap * span
            }

            // Two dry-brush bites out of the ink, which the reference has and which stop the
            // strokes reading as five rectangles.
            ctx.setFillColor(UIColor(white: 0.985, alpha: 1).cgColor)
            let bite = CGMutablePath()
            bite.addEllipse(in: CGRect(x: 0.128 * w, y: 0.560 * h, width: 0.042 * w, height: 0.290 * h))
            bite.addEllipse(in: CGRect(x: 0.742 * w, y: 0.330 * h, width: 0.030 * w, height: 0.210 * h))
            ctx.addPath(bite)
            ctx.fillPath()

            // A faint warm ghost under the first stroke — thinned paint over the ground.
            ctx.setFillColor(UIColor(red: 0.36, green: 0.28, blue: 0.22, alpha: 0.30).cgColor)
            ctx.fill(CGRect(x: 0.104 * w, y: 0.560 * h, width: 0.034 * w, height: 0.290 * h))
        }
    }

    /// Soft rounded terracotta and blush forms on a cream ground.
    private static func pierCanvasImage() -> CGImage? {
        TextureFactory.draw(width: 620, height: 880, background: UIColor(red: 0.945, green: 0.925, blue: 0.895, alpha: 1)) { ctx, size in
            let w = size.width, h = size.height

            func blob(
                cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, seed: Int, colour: UIColor
            ) {
                let path = CGMutablePath()
                let steps = 40
                var points = [CGPoint]()
                for s in 0...steps {
                    let t = CGFloat(s) / CGFloat(steps)
                    let a = t * 2 * .pi
                    let wob = 1 + wave(seed, Double(t) * 5) * 0.055
                    points.append(CGPoint(x: cx + cos(a) * rx * wob, y: cy + sin(a) * ry * wob))
                }
                path.addLines(between: points)
                path.closeSubpath()
                ctx.setFillColor(colour.cgColor)
                ctx.addPath(path)
                ctx.fillPath()
            }

            blob(
                cx: 0.60 * w, cy: 0.46 * h, rx: 0.215 * w, ry: 0.320 * h, seed: 11,
                colour: UIColor(red: 0.84, green: 0.66, blue: 0.60, alpha: 1)
            )
            blob(
                cx: 0.36 * w, cy: 0.62 * h, rx: 0.130 * w, ry: 0.245 * h, seed: 29,
                colour: UIColor(red: 0.74, green: 0.45, blue: 0.34, alpha: 1)
            )
            blob(
                cx: 0.44 * w, cy: 0.26 * h, rx: 0.085 * w, ry: 0.110 * h, seed: 47,
                colour: UIColor(red: 0.30, green: 0.26, blue: 0.24, alpha: 1)
            )

            // A single thin ink line tying the forms together.
            ctx.setStrokeColor(UIColor(white: 0.22, alpha: 0.75).cgColor)
            ctx.setLineWidth(3)
            ctx.move(to: CGPoint(x: 0.30 * w, y: 0.20 * h))
            ctx.addCurve(
                to: CGPoint(x: 0.70 * w, y: 0.82 * h),
                control1: CGPoint(x: 0.18 * w, y: 0.52 * h),
                control2: CGPoint(x: 0.82 * w, y: 0.54 * h)
            )
            ctx.strokePath()
        }
    }

    // MARK: - Deterministic wobble

    private nonisolated static func hash(_ i: Int) -> Double {
        var x = UInt32(truncatingIfNeeded: i &* 2_654_435_761)
        x ^= x >> 15
        x = x &* 2_246_822_519
        x ^= x >> 13
        x = x &* 3_266_489_917
        x ^= x >> 16
        return Double(x) / Double(UInt32.max) * 2 - 1
    }

    /// Smoothly interpolated integer-hash noise. Integer maths only, so a brushstroke has
    /// exactly the same edge on every launch and on every device.
    private nonisolated static func wave(_ seed: Int, _ t: Double) -> CGFloat {
        let i = Int(t.rounded(.down))
        let f = t - Double(i)
        let s = f * f * (3 - 2 * f)
        let a = hash(seed &* 131 &+ i)
        let b = hash(seed &* 131 &+ i &+ 1)
        return CGFloat(a + (b - a) * s)
    }
}

// MARK: - Soft-edged geometry

/// Filleted extrusion and pillowed panels.
///
/// `Mesh.extrude` gives a slab with knife edges, which is right for a shelf board and wrong
/// for everything upholstered. These build the same shapes with a rolled edge and smooth
/// vertex normals, which is most of what separates furniture from a bounding box.
private enum Soft {

    /// Outward unit normals for a closed polygon, averaged across each vertex's two edges.
    static func outwardNormals(_ p: [SIMD2<Float>]) -> [SIMD2<Float>] {
        let n = p.count
        var edge = [SIMD2<Float>](repeating: SIMD2(1, 0), count: n)
        for i in 0..<n {
            let e = p[(i + 1) % n] - p[i]
            let len = simd_length(e)
            if len > 1e-6 { edge[i] = SIMD2(e.y, -e.x) / len }
        }
        return (0..<n).map { i in
            let s = edge[(i + n - 1) % n] + edge[i]
            let len = simd_length(s)
            return len > 1e-6 ? s / len : edge[i]
        }
    }

    /// Extrudes a closed outline along Y with a rounded edge at either end.
    ///
    /// Each ring is the outline offset inward along its own normals by the fillet inset at
    /// that height; the vertex normal tilts by the fillet's slope, so the rounded edge shades
    /// as a continuous curve rather than as a stack of bands.
    static func extrude(
        _ profile: [SIMD2<Float>],
        bottom: Float, top: Float,
        bottomFillet: Float = 0, topFillet: Float = 0,
        filletSegments: Int = 4,
        capBottom: Bool = true, capTop: Bool = true,
        uvScale: Float = 1
    ) -> MeshAccumulator {
        guard profile.count >= 3, top > bottom + 1e-5 else { return MeshAccumulator() }
        let n = profile.count
        let normals = outwardNormals(profile)
        let height = top - bottom

        // Rows of (y, inset), sampled by angle so the curve gets even coverage.
        let bf = min(max(bottomFillet, 0), height * 0.49)
        let tf = min(max(topFillet, 0), height * 0.49)
        var rows = [SIMD2<Float>]()
        if bf > 1e-4 {
            for i in 0...filletSegments {
                let t = Float(i) / Float(filletSegments) * .pi / 2
                rows.append(SIMD2(bottom + bf * (1 - cos(t)), bf * (1 - sin(t))))
            }
        } else {
            rows.append(SIMD2(bottom, 0))
        }
        if tf > 1e-4 {
            for i in 0...filletSegments {
                let t = Float(i) / Float(filletSegments) * .pi / 2
                let y = top - tf * (1 - sin(t))
                if let last = rows.last, y <= last.x + 1e-5 { continue }
                rows.append(SIMD2(y, tf * (1 - cos(t))))
            }
        } else if let last = rows.last, top > last.x + 1e-5 {
            rows.append(SIMD2(top, 0))
        }
        guard rows.count >= 2 else { return MeshAccumulator() }

        var arc = [Float](repeating: 0, count: n + 1)
        for i in 0..<n {
            arc[i + 1] = arc[i] + simd_distance(profile[(i + 1) % n], profile[i])
        }
        let totalArc = max(arc[n], 1e-5)

        var m = MeshAccumulator(
            reservingVertices: rows.count * (n + 1) + 2 * n,
            triangles: (rows.count - 1) * n * 2 + 2 * n
        )
        var rings = [[UInt32]]()
        rings.reserveCapacity(rows.count)

        for (ri, row) in rows.enumerated() {
            let y = row.x, inset = row.y
            let prev = rows[max(ri - 1, 0)]
            let next = rows[min(ri + 1, rows.count - 1)]
            let dy = next.x - prev.x
            let slope = abs(dy) > 1e-6 ? (next.y - prev.y) / dy : 0
            var ring = [UInt32]()
            ring.reserveCapacity(n + 1)
            for s in 0...n {
                let i = s % n
                let p = profile[i] - normals[i] * inset
                let nrm = SIMD3(normals[i].x, slope, normals[i].y)
                ring.append(m.addVertex(
                    SIMD3(p.x, y, p.y), normal: nrm,
                    uv: SIMD2(arc[s] / totalArc * uvScale, (y - bottom) * uvScale)
                ))
            }
            rings.append(ring)
        }

        for r in 0..<(rings.count - 1) {
            for s in 0..<n {
                let a = rings[r][s], b = rings[r][s + 1]
                let c = rings[r + 1][s + 1], d = rings[r + 1][s]
                m.addTriangle(a, b, c)
                m.addTriangle(a, c, d)
            }
        }

        guard capBottom || capTop else { return m }
        let triangles = Triangulator.earClip(profile)

        if capTop, let row = rows.last {
            var map = [UInt32](repeating: 0, count: n)
            for i in 0..<n {
                let p = profile[i] - normals[i] * row.y
                map[i] = m.addVertex(
                    SIMD3(p.x, row.x, p.y), normal: SIMD3(0, 1, 0),
                    uv: SIMD2(p.x * uvScale, p.y * uvScale)
                )
            }
            for t in triangles { m.addTriangle(map[Int(t.0)], map[Int(t.2)], map[Int(t.1)]) }
        }

        if capBottom, let row = rows.first {
            var map = [UInt32](repeating: 0, count: n)
            for i in 0..<n {
                let p = profile[i] - normals[i] * row.y
                map[i] = m.addVertex(
                    SIMD3(p.x, row.x, p.y), normal: SIMD3(0, -1, 0),
                    uv: SIMD2(p.x * uvScale, p.y * uvScale)
                )
            }
            for t in triangles { m.addTriangle(map[Int(t.0)], map[Int(t.1)], map[Int(t.2)]) }
        }

        return m
    }

    /// A button-tufted upholstery panel in the XY plane, facing +Z.
    ///
    /// The surface bulges outward everywhere except at the buttons, which pull it back to the
    /// base plane — that is what tufting physically is, and modelling it that way means the
    /// panel never dips behind the box it is laid over. The buttons themselves are small caps
    /// sunk at each pull point.
    static func tuftedPanel(
        width: Float, height: Float, bulge: Float,
        columns: Int, rows: Int, resolution: Int = 44
    ) -> MeshAccumulator {
        guard columns > 0, rows > 0, width > 0, height > 0 else { return MeshAccumulator() }

        // Diamond layout: alternate rows are offset half a column, as in the reference.
        var buttons = [SIMD2<Float>]()
        for r in 0..<rows {
            let v = (Float(r) + 0.5) / Float(rows)
            let stagger: Float = r % 2 == 0 ? 0 : 0.5
            for c in 0..<columns {
                let u = (Float(c) + 0.5 + stagger) / Float(columns)
                if u > 1 { continue }
                buttons.append(SIMD2(u, v))
            }
        }

        let aspect = Float(columns) / Float(max(rows, 1))
        func surface(_ u: Float, _ v: Float) -> Float {
            var pull: Float = 0
            for b in buttons {
                let dx = (u - b.x) * Float(columns) * 1.05
                let dy = (v - b.y) * Float(rows) * 1.05 / max(aspect, 0.2) * aspect
                pull = max(pull, exp(-(dx * dx + dy * dy) * 3.4))
            }
            let edge = min(min(u, 1 - u) * 2, min(v, 1 - v) * 2)
            return bulge * (1 - min(pull, 1)) * smoothstep(0, 0.30, edge)
        }

        let cols = max(resolution, 8)
        let rowsGrid = max(Int(Float(cols) * height / width), 8)
        let eps: Float = 0.0006
        var m = MeshAccumulator(
            reservingVertices: (cols + 1) * (rowsGrid + 1),
            triangles: cols * rowsGrid * 2
        )
        var grid = [[UInt32]]()
        grid.reserveCapacity(rowsGrid + 1)

        let du = 1 / Float(cols), dv = 1 / Float(rowsGrid)
        for j in 0...rowsGrid {
            let v = Float(j) * dv
            var line = [UInt32]()
            line.reserveCapacity(cols + 1)
            for i in 0...cols {
                let u = Float(i) * du
                let z = surface(u, v) + eps
                let dzdx = (surface(u + du, v) - surface(u - du, v)) / (2 * du * width)
                let dzdy = (surface(u, v + dv) - surface(u, v - dv)) / (2 * dv * height)
                line.append(m.addVertex(
                    SIMD3((u - 0.5) * width, (v - 0.5) * height, z),
                    normal: SIMD3(-dzdx, -dzdy, 1),
                    uv: SIMD2(u * width, v * height)
                ))
            }
            grid.append(line)
        }
        for j in 0..<rowsGrid {
            for i in 0..<cols {
                let a = grid[j][i], b = grid[j][i + 1]
                let c = grid[j + 1][i + 1], d = grid[j + 1][i]
                m.addTriangle(a, b, c)
                m.addTriangle(a, c, d)
            }
        }

        let button = sphere(radius: 0.019, segments: 14, rings: 7)
        for b in buttons {
            m.append(button, transform: Xf.translate(
                (b.x - 0.5) * width, (b.y - 0.5) * height, eps - 0.013
            ))
        }
        return m
    }

    static func sphere(radius: Float, segments: Int = 20, rings: Int = 10) -> MeshAccumulator {
        var profile = [SIMD2<Float>]()
        profile.reserveCapacity(rings + 1)
        for i in 0...rings {
            let t = Float(i) / Float(rings) * .pi
            profile.append(SIMD2(sin(t) * radius, -cos(t) * radius))
        }
        return Mesh.lathe(profile: profile, segments: segments, capBottom: false, capTop: false)
    }
}
