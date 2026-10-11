import Foundation
import RealityKit
import simd
#if canImport(UIKit)
import UIKit
#endif

// The two eating areas of the demo apartment: the breakfast-bar island at the south end of
// the kitchen, and the round dining table beyond it.
//
// These are the props the opening shot lives on — the camera starts in the dining zone
// looking north, so the bar chairs, the laid table and the wine bottle are all in frame
// before anything else is. They get more geometry than their size warrants for that reason.

enum DiningModule: DemoModule {

    static func build(_ m: DemoMaterials) -> [DemoProp] {
        var props: [DemoProp] = []
        props.append(islandBase(m))
        props.append(islandTop(m))
        props.append(contentsOf: barChairs(m))
        props.append(contentsOf: placeSettings(m))
        props.append(wineBottle(m))
        props.append(contentsOf: wineGlasses(m))
        props.append(contentsOf: barTop(m))
        props.append(diningTable(m))
        props.append(contentsOf: diningChairs(m))
        props.append(hurricane(m))
        props.append(contentsOf: tableTop(m))
        return props
    }

    // MARK: - Loose on the bar and the table

    /// The rest of what is laid on the breakfast bar: a fruit bowl, a stack of side plates
    /// and a tumbler.
    ///
    /// The bar is a 920 mm quartz slab with nothing on it holding anything else down, which
    /// makes it the single most productive surface in the room for the shake to work on.
    /// Everything here is authored *at* 920 mm, matching the slab's declared collider face,
    /// so it starts resting rather than starting embedded or starting in mid-air.
    private static func barTop(_ m: DemoMaterials) -> [DemoProp] {
        let deck = Plan.Island.topHeight

        let fruitBowl = Turned.revolve([
            SIMD2(0.0000, 0.0000), SIMD2(0.0420, 0.0000), SIMD2(0.0500, 0.0060),
            SIMD2(0.0900, 0.0400), SIMD2(0.1180, 0.0880), SIMD2(0.1210, 0.0960),
            SIMD2(0.1140, 0.0960), SIMD2(0.1090, 0.0870), SIMD2(0.0830, 0.0430),
            SIMD2(0.0430, 0.0110), SIMD2(0.0000, 0.0090)
        ], segments: 40)

        // Three oranges, sitting in it. Small, round and free — the first things out.
        var fruit = MeshAccumulator()
        for (i, offset) in [
            SIMD2<Float>(-0.035, -0.018), SIMD2<Float>(0.032, -0.026), SIMD2<Float>(0.004, 0.036)
        ].enumerated() {
            let r: Float = 0.036 + Float(i) * 0.002
            fruit.append(
                Turned.revolve(
                    (0...10).map { s in
                        let t = Float(s) / 10 * Float.pi
                        return SIMD2(sin(t) * r, r - cos(t) * r)
                    },
                    segments: 18
                ),
                transform: Xf.translate(offset.x, 0.040, offset.y)
            )
        }

        var plates = MeshAccumulator()
        let sidePlate = Turned.revolve([
            SIMD2(0.0000, 0.0000), SIMD2(0.0320, 0.0000), SIMD2(0.0400, 0.0030),
            SIMD2(0.0760, 0.0100), SIMD2(0.0930, 0.0160), SIMD2(0.0910, 0.0200),
            SIMD2(0.0700, 0.0180), SIMD2(0.0420, 0.0110), SIMD2(0.0000, 0.0090)
        ], segments: 34)
        for i in 0..<3 {
            plates.append(sidePlate, transform: Xf.translate(0, Float(i) * 0.014, 0))
        }

        let tumbler = Turned.revolve([
            SIMD2(0.0000, 0.0000), SIMD2(0.0330, 0.0000), SIMD2(0.0345, 0.0050),
            SIMD2(0.0360, 0.0940), SIMD2(0.0360, 0.0980), SIMD2(0.0330, 0.0980),
            SIMD2(0.0320, 0.0110), SIMD2(0.0000, 0.0100)
        ], segments: 32)

        return [
            DemoProp(
                id: "island.fruitBowl", name: "Fruit bowl",
                parts: [DemoPart(fruitBowl, m.ceramicWhite), DemoPart(fruit, m.mustard)],
                transform: DemoProp.at(2.90, 3.30, y: deck),
                behaviour: .movable(mass: 1.5),
                category: .tableware
            ),
            DemoProp(
                id: "island.sidePlates", name: "Side plates",
                mesh: plates, material: m.wallCool,
                transform: DemoProp.at(3.18, 3.02, y: deck),
                behaviour: .movable(mass: 1.4),
                category: .tableware
            ),
            DemoProp(
                id: "island.tumbler", name: "Tumbler",
                parts: [DemoPart(tumbler, m.glass, castsShadow: false)],
                transform: DemoProp.at(2.68, 3.63, y: deck),
                behaviour: .movable(mass: 0.26),
                category: .tableware
            )
        ]
    }

    /// A carafe and a serving bowl on the dining table, either side of the hurricane.
    /// Both are well inside the 500 mm the table's declared top reaches to.
    private static func tableTop(_ m: DemoMaterials) -> [DemoProp] {
        let deck = Plan.Dining.topHeight
        let centre = Plan.Dining.centre

        let carafe = Turned.revolve([
            SIMD2(0.0000, 0.0000), SIMD2(0.0520, 0.0000), SIMD2(0.0555, 0.0080),
            SIMD2(0.0560, 0.1180), SIMD2(0.0500, 0.1400), SIMD2(0.0320, 0.1620),
            SIMD2(0.0270, 0.1800), SIMD2(0.0290, 0.1960), SIMD2(0.0255, 0.1980),
            SIMD2(0.0240, 0.1810), SIMD2(0.0285, 0.1640), SIMD2(0.0460, 0.1420),
            SIMD2(0.0520, 0.1180), SIMD2(0.0515, 0.0110), SIMD2(0.0000, 0.0100)
        ], segments: 36)

        let servingBowl = Turned.revolve([
            SIMD2(0.0000, 0.0000), SIMD2(0.0480, 0.0000), SIMD2(0.0560, 0.0070),
            SIMD2(0.0980, 0.0460), SIMD2(0.1240, 0.0920), SIMD2(0.1270, 0.1000),
            SIMD2(0.1200, 0.1000), SIMD2(0.1150, 0.0910), SIMD2(0.0900, 0.0480),
            SIMD2(0.0490, 0.0130), SIMD2(0.0000, 0.0110)
        ], segments: 40)

        return [
            DemoProp(
                id: "dining.carafe", name: "Water carafe",
                parts: [DemoPart(carafe, m.glass, castsShadow: false)],
                transform: DemoProp.at(centre.x + 0.26, centre.y - 0.14, y: deck),
                behaviour: .movable(mass: 0.9),
                category: .tableware
            ),
            DemoProp(
                id: "dining.servingBowl", name: "Serving bowl",
                mesh: servingBowl, material: m.terracotta,
                transform: DemoProp.at(centre.x - 0.27, centre.y + 0.19, y: deck),
                behaviour: .movable(mass: 1.1),
                category: .tableware
            )
        ]
    }

    // MARK: - Island base

    /// The charcoal cabinet mass. Its south face is open shelving, so it is built as a real
    /// carcass — two gables, a back, a top and three shelves — rather than a solid block.
    /// You can see into it from the dining zone, which is exactly where the camera starts.
    private static func islandBase(_ m: DemoMaterials) -> DemoProp {
        let x = Plan.Island.baseX, z = Plan.Island.baseZ
        let w = x.upperBound - x.lowerBound
        let d = z.upperBound - z.lowerBound
        let h = Plan.Island.baseHeight

        let toe: Float = 0.09          // recessed plinth
        let panel: Float = 0.019       // carcass ply
        let shelf: Float = 0.022

        var mesh = MeshAccumulator()

        // Plinth, set back on every side so the carcass appears to float a little.
        mesh.append(Mesh.boxOnFloor(SIMD3(w - 0.10, toe, d - 0.10)))

        // Worktop-level closing panel, then the gables between it and the plinth.
        let carcassTop = h - 0.020
        mesh.append(Mesh.box(SIMD3(w, 0.020, d)), transform: Xf.translate(0, h - 0.010, 0))

        let gableHeight = carcassTop - toe
        let gable = Mesh.box(SIMD3(panel, gableHeight, d))
        let gableY = toe + gableHeight / 2
        mesh.append(gable, at: [
            Xf.translate(-(w / 2 - panel / 2), gableY, 0),
            Xf.translate(w / 2 - panel / 2, gableY, 0)
        ])

        // Back panel closes the north face; the south face is left open.
        let innerW = w - 2 * panel
        mesh.append(
            Mesh.box(SIMD3(innerW, gableHeight, 0.018)),
            transform: Xf.translate(0, gableY, -(d / 2 - 0.009))
        )

        // Three shelves, set back a little from the open face so the gable edges read.
        let shelfDepth = d - 0.018 - 0.030
        for i in 1...3 {
            let y = toe + gableHeight * Float(i) / 4
            mesh.append(
                Mesh.box(SIMD3(innerW, shelf, shelfDepth)),
                transform: Xf.translate(0, y, (d / 2 - 0.030) - shelfDepth / 2)
            )
        }

        return DemoProp(
            id: "island.base",
            name: "Kitchen island",
            mesh: mesh,
            material: m.darkCabinet,
            transform: DemoProp.at(mid(x), mid(z)),
            behaviour: .fixed,
            category: .cabinetry
        )
    }

    // MARK: - Quartz slab

    /// The slab, its waterfall return at the east end, and the two posts that carry the
    /// west overhang. Authored as one prop because the waterfall is literally the same
    /// piece of stone folded down.
    private static func islandTop(_ m: DemoMaterials) -> DemoProp {
        let x = Plan.Island.topX, z = Plan.Island.topZ
        let w = x.upperBound - x.lowerBound
        let d = z.upperBound - z.lowerBound
        let t = Plan.Island.topThickness
        let top = Plan.Island.topHeight
        let underside = top - t
        let originX = mid(x)

        var stone = MeshAccumulator()
        stone.append(Mesh.box(SIMD3(w, t, d)), transform: Xf.translate(0, top - t / 2, 0))
        stone.append(
            Mesh.box(SIMD3(t, underside, d)),
            transform: Xf.translate(Plan.Island.waterfallX - originX, underside / 2, 0)
        )

        // The overhang is a table for two, so it needs visible support. Two slim dark posts
        // just inboard of the west edge, matching the reference.
        var posts = MeshAccumulator()
        let postX = -(w / 2) + 0.10
        let post = Mesh.boxOnFloor(SIMD3(0.075, underside, 0.075))
        posts.append(post, at: [
            Xf.translate(postX, 0, -(d / 2 - 0.14)),
            Xf.translate(postX, 0, d / 2 - 0.14)
        ])
        // A stretcher between them stops the pair reading as two loose sticks.
        posts.append(
            Mesh.box(SIMD3(0.055, 0.055, d - 0.28 - 0.075)),
            transform: Xf.translate(postX, 0.16, 0)
        )

        let waterfallLocal = Plan.Island.waterfallX - originX
        let waterfall = (waterfallLocal - t / 2)...(waterfallLocal + t / 2)

        return DemoProp(
            id: "island.top",
            name: "Quartz breakfast bar",
            parts: [DemoPart(stone, m.quartz), DemoPart(posts, m.darkCabinet)],
            transform: DemoProp.at(originX, mid(z)),
            behaviour: .fixed,
            category: .cabinetry,
            // Declared so the slab's face is at exactly 920 mm — the height the place
            // settings, the bottle and the glasses are all authored at. Inferred, the box
            // ran the full height of the waterfall and came back 14 mm short at the top, so
            // everything laid on the bar spent the demo sunk into the stone. The waterfall
            // and the two posts are their own boxes, which also gives back the knee space
            // under the west overhang that the bounding box had filled in solid.
            colliderBoxes: [
                .surface(
                    x: (-w / 2)...(w / 2), z: (-d / 2)...(d / 2),
                    top: top, thickness: t
                ),
                .span(x: waterfall, y: 0...underside, z: (-d / 2)...(d / 2)),
                .post(
                    at: SIMD2(postX, -(d / 2 - 0.14)), section: SIMD2(0.075, 0.075),
                    from: 0, to: underside
                ),
                .post(
                    at: SIMD2(postX, d / 2 - 0.14), section: SIMD2(0.075, 0.075),
                    from: 0, to: underside
                )
            ]
        )
    }

    // MARK: - Bar chairs

    private static func barChairs(_ m: DemoMaterials) -> [DemoProp] {
        let shell = barChairShell()
        let frame = barChairFrame()
        let seats: [(String, SIMD2<Float>, Float)] = [
            ("island.stool.a", Plan.Island.stoolA, 0),      // north of the bar, facing south
            ("island.stool.b", Plan.Island.stoolB, .pi)     // south of the bar, facing north
        ]
        return seats.map { id, p, yaw in
            DemoProp(
                id: id,
                name: "Counter stool",
                parts: [DemoPart(shell, m.cognacLeather), DemoPart(frame, m.blackMetal)],
                transform: DemoProp.at(p.x, p.y, yaw: yaw),
                behaviour: .movable(mass: 7),
                category: .seating
            )
        }
    }

    /// Cognac leather bucket seat plus the back that wraps around it. The back is a lofted
    /// shell with real thickness — a flat panel here would kill the opening frame.
    private static func barChairShell() -> MeshAccumulator {
        var mesh = MeshAccumulator()

        let pad = Outline.superellipse(width: 0.44, depth: 0.42, exponent: 3.4, segments: 48)
        mesh.append(Turned.loft([
            (Outline.scaled(pad, 0.94, 0.94), 0.598),
            (pad, 0.618),
            (pad, 0.650),
            (Outline.scaled(pad, 0.985, 0.985), 0.666),
            (Outline.scaled(pad, 0.925, 0.925), 0.676)
        ]))

        // The shell leans back and closes in as it rises, which is what makes it read as
        // upholstery wrapped over a frame rather than as a curved wall.
        let back: [(radius: Float, thickness: Float, halfAngle: Float, y: Float, lean: Float)] = [
            (0.245, 0.028, 1.16, 0.585, 0.000),
            (0.245, 0.028, 1.14, 0.720, 0.014),
            (0.246, 0.027, 1.06, 0.860, 0.038),
            (0.248, 0.025, 0.94, 0.965, 0.066),
            (0.250, 0.018, 0.86, 1.015, 0.080)
        ]
        mesh.append(Turned.loft(back.map { level in
            (crescent(
                radius: level.radius, thickness: level.thickness,
                halfAngle: level.halfAngle, centreZ: 0.02 - level.lean
            ), level.y)
        }))

        return mesh
    }

    /// Four splayed tubular legs and a footrail ring.
    private static func barChairFrame() -> MeshAccumulator {
        var mesh = MeshAccumulator()

        let legHeight: Float = 0.62
        let splay: Float = 0.10                  // radians; ~6 cm of spread over the leg
        let baseX: Float = 0.230, baseZ: Float = 0.215
        let leg = Turned.revolve([SIMD2(0.0125, 0), SIMD2(0.0105, legHeight)], segments: 12)

        for sx in [Float(-1), 1] {
            for sz in [Float(-1), 1] {
                mesh.append(
                    leg,
                    transform: Xf.translate(sx * baseX, 0, sz * baseZ)
                        * Xf.rotateZ(sx * splay) * Xf.rotateX(-sz * splay)
                )
            }
        }

        // Footrail, at the height where the legs have already drawn in by ~2 cm.
        let railY: Float = 0.20
        let inset = railY * sin(splay)
        let rx = baseX - inset, rz = baseZ - inset
        let bar: Float = 0.016
        mesh.append(Mesh.box(SIMD3(2 * rx, bar, bar)), at: [
            Xf.translate(0, railY, rz), Xf.translate(0, railY, -rz)
        ])
        mesh.append(Mesh.box(SIMD3(bar, bar, 2 * rz)), at: [
            Xf.translate(rx, railY, 0), Xf.translate(-rx, railY, 0)
        ])

        return mesh
    }

    // MARK: - Place settings

    private static func placeSettings(_ m: DemoMaterials) -> [DemoProp] {
        // Woven mat, stoneware plate, salmon bowl, folded napkin. Built once and shared;
        // the two settings face each other across the bar.
        let mat = Turned.sweep(
            Outline.roundedRect(width: 0.42, depth: 0.30, cornerRadius: 0.010),
            from: 0, to: 0.005
        )

        // Rim, well and foot ring traced as one open profile, so the plate is a shell.
        let plate = Turned.revolve([
            SIMD2(0.000, 0.000), SIMD2(0.040, 0.000), SIMD2(0.048, 0.003),
            SIMD2(0.090, 0.008), SIMD2(0.118, 0.016), SIMD2(0.125, 0.021),
            SIMD2(0.120, 0.026), SIMD2(0.092, 0.024), SIMD2(0.060, 0.014),
            SIMD2(0.000, 0.011)
        ], segments: 44).transformed(by: Xf.translate(0, 0.005, 0))

        let bowl = Turned.revolve([
            SIMD2(0.000, 0.000), SIMD2(0.022, 0.000), SIMD2(0.030, 0.004),
            SIMD2(0.046, 0.020), SIMD2(0.055, 0.040), SIMD2(0.056, 0.046),
            SIMD2(0.050, 0.046), SIMD2(0.042, 0.024), SIMD2(0.027, 0.008),
            SIMD2(0.000, 0.006)
        ], segments: 40).transformed(by: Xf.translate(0, 0.020, 0))

        var napkin = MeshAccumulator()
        napkin.append(Mesh.boxOnFloor(SIMD3(0.165, 0.006, 0.115)))
        napkin.append(Mesh.boxOnFloor(SIMD3(0.150, 0.005, 0.052)), transform: Xf.translate(0, 0.006, 0.012))
        napkin = napkin.transformed(by: Xf.translate(-0.115, 0.005, 0.020) * Xf.rotateY(0.24))

        let parts = [
            DemoPart(mat, m.oakFloor),
            // No mid-grey in the library; the cool wall paint is the closest match to the
            // matte stoneware in the reference.
            DemoPart(plate, m.wallCool),
            DemoPart(bowl, m.terracotta),
            DemoPart(napkin, m.mustard)
        ]

        let placements: [(String, SIMD2<Float>, Float)] = [
            ("island.setting.a", Plan.Island.settingA, .pi),
            ("island.setting.b", Plan.Island.settingB, 0)
        ]
        return placements.map { id, p, yaw in
            DemoProp(
                id: id,
                name: "Place setting",
                parts: parts,
                transform: DemoProp.at(p.x, p.y, y: Plan.Island.topHeight, yaw: yaw),
                behaviour: .movable(mass: 1.4),
                category: .tableware
            )
        }
    }

    // MARK: - Wine

    private static func wineBottle(_ m: DemoMaterials) -> DemoProp {
        // Punt, body, shoulder, neck and lip in one profile; it closes to the axis at both
        // ends so the lathe needs no caps.
        let body = Turned.revolve([
            SIMD2(0.0000, 0.014), SIMD2(0.0140, 0.010), SIMD2(0.0260, 0.003),
            SIMD2(0.0340, 0.000), SIMD2(0.0375, 0.006), SIMD2(0.0375, 0.172),
            SIMD2(0.0372, 0.186), SIMD2(0.0350, 0.200), SIMD2(0.0300, 0.214),
            SIMD2(0.0232, 0.228), SIMD2(0.0175, 0.242), SIMD2(0.0148, 0.256),
            SIMD2(0.0140, 0.286), SIMD2(0.0158, 0.292), SIMD2(0.0160, 0.298),
            SIMD2(0.0128, 0.300), SIMD2(0.0000, 0.300)
        ], segments: 40)

        let capsule = Turned.revolve([
            SIMD2(0.0152, 0.248), SIMD2(0.0176, 0.252), SIMD2(0.0172, 0.288),
            SIMD2(0.0182, 0.294), SIMD2(0.0180, 0.301), SIMD2(0.0000, 0.301)
        ], segments: 40)

        // A band standing 0.5 mm proud of the glass, so it never z-fights the body.
        let label = Turned.revolve([
            SIMD2(0.0380, 0.046), SIMD2(0.0380, 0.138)
        ], segments: 40)

        return DemoProp(
            id: "island.wineBottle",
            name: "Wine bottle",
            parts: [
                DemoPart(body, bottleGlass()),
                DemoPart(capsule, m.matteBlackPaint),
                DemoPart(label, m.paperWhite)
            ],
            transform: DemoProp.at(2.44, 3.31, y: Plan.Island.topHeight),
            behaviour: .movable(mass: 1.2),
            category: .tableware
        )
    }

    private static func wineGlasses(_ m: DemoMaterials) -> [DemoProp] {
        // Foot, stem, bowl and back down the inside of the bowl — one continuous shell, so
        // the rim has real thickness when the quake tips it over.
        let glass = Turned.revolve([
            SIMD2(0.0000, 0.000), SIMD2(0.0380, 0.000), SIMD2(0.0400, 0.002),
            SIMD2(0.0370, 0.005), SIMD2(0.0110, 0.011), SIMD2(0.0076, 0.020),
            SIMD2(0.0072, 0.070), SIMD2(0.0092, 0.083), SIMD2(0.0200, 0.096),
            SIMD2(0.0320, 0.113), SIMD2(0.0400, 0.136), SIMD2(0.0425, 0.161),
            SIMD2(0.0405, 0.186), SIMD2(0.0375, 0.202), SIMD2(0.0362, 0.209),
            SIMD2(0.0344, 0.209), SIMD2(0.0360, 0.196), SIMD2(0.0384, 0.170),
            SIMD2(0.0374, 0.140), SIMD2(0.0280, 0.114), SIMD2(0.0142, 0.099),
            SIMD2(0.0072, 0.091)
        ], segments: 40)

        let spots: [(String, SIMD2<Float>)] = [
            ("island.wineGlass.a", SIMD2(2.22, 3.00)),
            ("island.wineGlass.b", SIMD2(2.22, 3.62))
        ]
        return spots.map { id, p in
            DemoProp(
                id: id,
                name: "Wine glass",
                parts: [DemoPart(glass, m.glass, castsShadow: false)],
                transform: DemoProp.at(p.x, p.y, y: Plan.Island.topHeight),
                behaviour: .movable(mass: 0.25),
                category: .tableware
            )
        }
    }

    // MARK: - Dining table

    private static func diningTable(_ m: DemoMaterials) -> DemoProp {
        let r = Plan.Dining.topRadius
        let t = Plan.Dining.topThickness
        let top = Plan.Dining.topHeight
        let disc = Outline.circle(radius: r, segments: 56)

        // Eased edge rather than a square one; on a white top the highlight along that
        // radius is most of what sells the material.
        let slab = Turned.loft([
            (Outline.scaled(disc, 0.976, 0.976), top - t),
            (disc, top - t + 0.010),
            (disc, top - 0.010),
            (Outline.scaled(disc, 0.976, 0.976), top)
        ])

        let pedestalTop = top - t
        let pedestal = Turned.revolve([
            SIMD2(0.000, 0.000), SIMD2(0.248, 0.000), SIMD2(0.252, 0.011),
            SIMD2(0.244, 0.024), SIMD2(0.196, 0.090), SIMD2(0.150, 0.190),
            SIMD2(0.113, 0.300), SIMD2(0.091, 0.400), SIMD2(0.078, 0.500),
            SIMD2(0.071, 0.600), SIMD2(0.069, pedestalTop - 0.038),
            SIMD2(0.086, pedestalTop - 0.020), SIMD2(0.086, pedestalTop),
            SIMD2(0.000, pedestalTop)
        ], segments: 48)

        return DemoProp(
            id: "dining.table",
            name: "Dining table",
            parts: [DemoPart(slab, m.ceramicWhite), DemoPart(pedestal, m.stainless)],
            transform: DemoProp.at(Plan.Dining.centre.x, Plan.Dining.centre.y),
            behaviour: .movable(mass: 32),
            category: .table,
            // Three boxes: the foot, the column and the top. The point of declaring them is
            // the middle one — a bounding box would give this table a 1.16 m square
            // footprint sitting flat on the floor, which is a table that can never move on
            // a pedestal that does not exist. Real pedestal tables rock on their foot, and
            // this one now can.
            //
            // The top is three overlapping rectangles standing in for the disc, not one
            // square. RealityKit has no cylinder collision shape, and the square this used
            // to be was described as "inscribed at 0.50 m against the real 0.58 m radius"
            // — but a half-width of 0.50 m puts the *corners* at 0.707 m, 127 mm out over
            // thin air, while the edge midpoints fell 80 mm short of the glass. An object
            // could come to rest visibly floating off a diagonal. Every corner of the three
            // boxes below lies inside 0.58 m, and together they cover the disc to within
            // about 40 mm anywhere on it.
            colliderBoxes: [
                .surface(x: -0.24...0.24, z: -0.24...0.24, top: 0.024, thickness: 0.024),
                .span(x: -0.09...0.09, y: 0...pedestalTop, z: -0.09...0.09),
                .surface(x: -0.55...0.55, z: -0.18...0.18, top: top, thickness: t),
                .surface(x: -0.18...0.18, z: -0.55...0.55, top: top, thickness: t),
                .surface(x: -0.41...0.41, z: -0.41...0.41, top: top, thickness: t)
            ]
        )
    }

    // MARK: - Dining chairs

    private static func diningChairs(_ m: DemoMaterials) -> [DemoProp] {
        let mesh = diningChairMesh()
        let count = Plan.Dining.chairCount
        return (0..<count).map { i in
            let a = Plan.Dining.chairPhase + Float(i) * 2 * .pi / Float(count)
            let x = Plan.Dining.centre.x + cos(a) * Plan.Dining.chairRadius
            let z = Plan.Dining.centre.y + sin(a) * Plan.Dining.chairRadius
            // Chairs are authored facing +Z, so the yaw is whatever turns +Z inward.
            let yaw = atan2(-cos(a), -sin(a))
            return DemoProp(
                id: "dining.chair.\(i)",
                name: "Dining chair",
                mesh: mesh,
                material: m.darkWood,
                transform: DemoProp.at(x, z, yaw: yaw),
                behaviour: .movable(mass: 6),
                category: .seating
            )
        }
    }

    private static func diningChairMesh() -> MeshAccumulator {
        var mesh = MeshAccumulator()

        let seatTop: Float = 0.452
        let legHeight: Float = 0.44
        let splay: Float = 0.045
        let leg = Turned.revolve([
            SIMD2(0.021, 0), SIMD2(0.019, 0.30), SIMD2(0.0135, legHeight)
        ], segments: 12)
        for sx in [Float(-1), 1] {
            for sz in [Float(-1), 1] {
                mesh.append(
                    leg,
                    transform: Xf.translate(sx * 0.190, 0, sz * 0.180)
                        * Xf.rotateZ(sx * splay) * Xf.rotateX(-sz * splay)
                )
            }
        }

        // Seat: a rounded slab whose top face dishes in by 8 mm.
        let pad = Outline.roundedRect(width: 0.44, depth: 0.42, cornerRadius: 0.055, cornerSegments: 6)
        mesh.append(Turned.loft([
            (Outline.scaled(pad, 0.955, 0.955), 0.400),
            (pad, 0.412),
            (pad, 0.442),
            (Outline.scaled(pad, 0.965, 0.965), seatTop)
        ], capTop: false))
        mesh.append(Turned.loft([
            (Outline.scaled(pad, 0.965, 0.965), seatTop),
            (Outline.scaled(pad, 0.800, 0.800), 0.4475),
            (Outline.scaled(pad, 0.450, 0.450), 0.4445),
            (Outline.scaled(pad, 0.120, 0.120), 0.4435)
        ], capBottom: false))

        // Two uprights raked back, carrying a shaped rail and a lumbar rail. The rails bow
        // away from the sitter at the centre and come forward at the ends.
        let rake: Float = 0.155
        let upright = Mesh.boxOnFloor(SIMD3(0.030, 0.455, 0.034))
        for sx in [Float(-1), 1] {
            mesh.append(
                upright,
                transform: Xf.translate(sx * 0.185, 0.400, -0.175) * Xf.rotateX(-rake)
            )
        }

        let railRadius: Float = 0.350
        let railCentre: Float = 0.050
        mesh.append(Turned.loft([
            (crescent(radius: railRadius, thickness: 0.024, halfAngle: 0.60, centreZ: railCentre), 0.520),
            (crescent(radius: railRadius, thickness: 0.024, halfAngle: 0.60, centreZ: railCentre), 0.578)
        ]))
        mesh.append(Turned.loft([
            (crescent(radius: railRadius, thickness: 0.031, halfAngle: 0.60, centreZ: railCentre), 0.734),
            (crescent(radius: railRadius, thickness: 0.031, halfAngle: 0.60, centreZ: railCentre), 0.826),
            (crescent(radius: railRadius, thickness: 0.022, halfAngle: 0.585, centreZ: railCentre), 0.845)
        ]))

        return mesh
    }

    // MARK: - Hurricane candle

    private static func hurricane(_ m: DemoMaterials) -> DemoProp {
        let coaster = Turned.loft([
            (Outline.scaled(Outline.circle(radius: 0.105, segments: 44), 0.94, 0.94), 0.000),
            (Outline.circle(radius: 0.105, segments: 44), 0.004),
            (Outline.circle(radius: 0.105, segments: 44), 0.010),
            (Outline.scaled(Outline.circle(radius: 0.105, segments: 44), 0.94, 0.94), 0.013)
        ])

        // One profile up the outside, over the rim and back down the inside — an open
        // vessel with a thick base, which is what catches the light in the reference.
        let vessel = Turned.revolve([
            SIMD2(0.0000, 0.013), SIMD2(0.0820, 0.013), SIMD2(0.0850, 0.019),
            SIMD2(0.0850, 0.228), SIMD2(0.0845, 0.235), SIMD2(0.0805, 0.235),
            SIMD2(0.0810, 0.228), SIMD2(0.0810, 0.034), SIMD2(0.0000, 0.030)
        ], segments: 48)

        let candle = Turned.revolve([
            SIMD2(0.0000, 0.030), SIMD2(0.0700, 0.030), SIMD2(0.0700, 0.166),
            SIMD2(0.0680, 0.173), SIMD2(0.0300, 0.177), SIMD2(0.0160, 0.171),
            SIMD2(0.0000, 0.172)
        ], segments: 44)

        let flame = Turned.revolve([
            SIMD2(0.0000, 0.171), SIMD2(0.0055, 0.177), SIMD2(0.0062, 0.185),
            SIMD2(0.0040, 0.195), SIMD2(0.0000, 0.201)
        ], segments: 16)

        return DemoProp(
            id: "dining.hurricane",
            name: "Hurricane candle",
            parts: [
                DemoPart(coaster, m.darkWood),
                DemoPart(vessel, m.glass, castsShadow: false),
                DemoPart(candle, m.creamFabric),
                DemoPart(flame, m.bulbGlow, castsShadow: false)
            ],
            transform: DemoProp.at(
                Plan.Dining.centre.x, Plan.Dining.centre.y, y: Plan.Dining.topHeight
            ),
            behaviour: .movable(mass: 1.8),
            category: .decor
        )
    }

    // MARK: - Local helpers

    private static func mid(_ r: ClosedRange<Float>) -> Float {
        (r.lowerBound + r.upperBound) / 2
    }

    /// A curved band in the XZ plane whose convex side faces away from `centreZ`.
    ///
    /// Both chair backs are made of these: stacked at different radii, wraps and leans they
    /// loft into a shell that tapers and rakes the way a real moulded back does. The vertex
    /// count depends only on `segments`, so levels can differ in every other parameter and
    /// still loft together.
    private static func crescent(
        radius: Float, thickness: Float, halfAngle: Float, centreZ: Float, segments: Int = 20
    ) -> [SIMD2<Float>] {
        let outer = radius + thickness / 2
        let inner = radius - thickness / 2
        func arc(_ r: Float, _ s: Int) -> SIMD2<Float> {
            let f = -halfAngle + Float(s) / Float(segments) * 2 * halfAngle
            return SIMD2(r * sin(f), centreZ - r * cos(f))
        }
        var points = [SIMD2<Float>]()
        points.reserveCapacity(2 * (segments + 1))
        for s in 0...segments { points.append(arc(outer, s)) }
        for s in stride(from: segments, through: 0, by: -1) { points.append(arc(inner, s)) }
        return points
    }

    /// The library has clear and amber glass but no bottle green, and the wine bottle is
    /// the one small prop the opening shot lingers on.
    private static func bottleGlass() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.13, green: 0.20, blue: 0.09, alpha: 1))
        material.roughness = .init(floatLiteral: 0.09)
        material.metallic = .init(floatLiteral: 0)
        material.specular = .init(floatLiteral: 0.9)
        return material
    }
}

// MARK: - Swept and revolved surfaces

/// Lofting and revolving with smooth per-vertex normals.
///
/// `Mesh.extrude` and `Mesh.lathe` supply outward normals but wind their side walls the
/// other way, so with back-face culling on their curved surfaces render inside-out. These
/// build the same forms with winding and shading in agreement, and `loft` additionally
/// interpolates between differing outlines, which is what the chair shells need.
///
/// Outlines are read as (x, z) and must be counter-clockwise in those numeric coordinates —
/// which is what every `Outline` helper produces.
private enum Turned {

    static func loft(
        _ levels: [(outline: [SIMD2<Float>], y: Float)],
        capBottom: Bool = true,
        capTop: Bool = true,
        uvScale: Float = 1
    ) -> MeshAccumulator {
        guard levels.count >= 2, let n = levels.first?.outline.count, n >= 3 else {
            return MeshAccumulator()
        }
        guard levels.allSatisfy({ $0.outline.count == n }) else { return MeshAccumulator() }

        let rings: [[SIMD3<Float>]] = levels.map { level in
            level.outline.map { SIMD3($0.x, level.y, $0.y) }
        }
        let levelCount = rings.count

        // Cumulative arc length along the outline, and up the surface, so tiled materials
        // are not stretched on tapered forms.
        var u = [Float](repeating: 0, count: n + 1)
        for j in 0..<n {
            u[j + 1] = u[j] + simd_distance(rings[0][j], rings[0][(j + 1) % n])
        }
        var v = [Float](repeating: 0, count: levelCount)
        for i in 1..<levelCount {
            v[i] = v[i - 1] + simd_distance(rings[i][0], rings[i - 1][0])
        }

        var mesh = MeshAccumulator(
            reservingVertices: levelCount * (n + 1) + 2 * n,
            triangles: (levelCount - 1) * n * 2 + 2 * n
        )
        var grid = [[UInt32]]()
        grid.reserveCapacity(levelCount)

        for i in 0..<levelCount {
            var row = [UInt32]()
            row.reserveCapacity(n + 1)
            for j in 0...n {
                let k = j % n
                let tangentU = rings[i][(k + 1) % n] - rings[i][(k + n - 1) % n]
                let tangentV = rings[min(i + 1, levelCount - 1)][k] - rings[max(i - 1, 0)][k]
                var normal = cross(tangentV, tangentU)
                if simd_length(normal) < 1e-7 {
                    normal = SIMD3(tangentU.z, 0, -tangentU.x)
                }
                row.append(mesh.addVertex(
                    rings[i][k],
                    normal: normal,
                    uv: SIMD2(u[j] * uvScale, v[i] * uvScale)
                ))
            }
            grid.append(row)
        }

        for i in 0..<(levelCount - 1) {
            for j in 0..<n {
                let a = grid[i][j], b = grid[i + 1][j]
                let c = grid[i + 1][j + 1], d = grid[i][j + 1]
                mesh.addTriangle(a, b, c)
                mesh.addTriangle(a, c, d)
            }
        }

        if capBottom { cap(&mesh, levels[0].outline, y: levels[0].y, up: false, uvScale: uvScale) }
        if capTop {
            let last = levels[levelCount - 1]
            cap(&mesh, last.outline, y: last.y, up: true, uvScale: uvScale)
        }
        return mesh
    }

    static func sweep(
        _ outline: [SIMD2<Float>], from bottom: Float, to top: Float, uvScale: Float = 1
    ) -> MeshAccumulator {
        loft([(outline, bottom), (outline, top)], uvScale: uvScale)
    }

    /// Revolves a `(radius, y)` polyline around the Y axis, bottom to top. Ends that reach
    /// the axis need no cap, which is how the bottle punt and the candle flame close.
    static func revolve(
        _ profile: [SIMD2<Float>], segments: Int = 40, uvScale: Float = 1
    ) -> MeshAccumulator {
        guard profile.count >= 2, segments >= 3 else { return MeshAccumulator() }

        var profileNormals = [SIMD2<Float>](repeating: SIMD2(1, 0), count: profile.count)
        for i in 0..<profile.count {
            let tangent = profile[min(i + 1, profile.count - 1)] - profile[max(i - 1, 0)]
            let candidate = SIMD2(tangent.y, -tangent.x)
            let length = simd_length(candidate)
            profileNormals[i] = length > 1e-6 ? candidate / length : SIMD2(1, 0)
        }

        var arc = [Float](repeating: 0, count: profile.count)
        for i in 1..<profile.count {
            arc[i] = arc[i - 1] + simd_distance(profile[i], profile[i - 1])
        }
        let totalArc = max(arc.last ?? 1, 1e-5)

        var mesh = MeshAccumulator(
            reservingVertices: (segments + 1) * profile.count + 2 * (segments + 2),
            triangles: segments * (profile.count - 1) * 2 + 2 * segments
        )
        var rings = [[UInt32]]()
        rings.reserveCapacity(profile.count)
        for (i, point) in profile.enumerated() {
            var row = [UInt32]()
            row.reserveCapacity(segments + 1)
            for s in 0...segments {
                let theta = Float(s) / Float(segments) * 2 * .pi
                let ct = cos(theta), st = sin(theta)
                row.append(mesh.addVertex(
                    SIMD3(point.x * ct, point.y, point.x * st),
                    normal: SIMD3(profileNormals[i].x * ct, profileNormals[i].y, profileNormals[i].x * st),
                    uv: SIMD2(Float(s) / Float(segments) * uvScale, arc[i] / totalArc * uvScale)
                ))
            }
            rings.append(row)
        }

        for i in 0..<(profile.count - 1) {
            for s in 0..<segments {
                let a = rings[i][s], b = rings[i + 1][s]
                let c = rings[i + 1][s + 1], d = rings[i][s + 1]
                mesh.addTriangle(a, b, c)
                mesh.addTriangle(a, c, d)
            }
        }

        if let first = profile.first, first.x > 1e-5 {
            discCap(&mesh, radius: first.x, y: first.y, segments: segments, up: false)
        }
        if let last = profile.last, last.x > 1e-5 {
            discCap(&mesh, radius: last.x, y: last.y, segments: segments, up: true)
        }
        return mesh
    }

    // MARK: Caps

    private static func cap(
        _ mesh: inout MeshAccumulator, _ outline: [SIMD2<Float>],
        y: Float, up: Bool, uvScale: Float
    ) {
        let normal = SIMD3<Float>(0, up ? 1 : -1, 0)
        var map = [UInt32](repeating: 0, count: outline.count)
        for (i, p) in outline.enumerated() {
            map[i] = mesh.addVertex(
                SIMD3(p.x, y, p.y), normal: normal,
                uv: SIMD2(p.x * uvScale, p.y * uvScale)
            )
        }
        // Ear clipping returns numerically counter-clockwise triples, which face -Y; the
        // top cap therefore takes them reversed.
        for t in Triangulator.earClip(outline) {
            if up {
                mesh.addTriangle(map[Int(t.0)], map[Int(t.2)], map[Int(t.1)])
            } else {
                mesh.addTriangle(map[Int(t.0)], map[Int(t.1)], map[Int(t.2)])
            }
        }
    }

    private static func discCap(
        _ mesh: inout MeshAccumulator, radius: Float, y: Float, segments: Int, up: Bool
    ) {
        let normal = SIMD3<Float>(0, up ? 1 : -1, 0)
        let centre = mesh.addVertex(SIMD3(0, y, 0), normal: normal, uv: SIMD2(0.5, 0.5))
        var rim = [UInt32]()
        rim.reserveCapacity(segments + 1)
        for s in 0...segments {
            let theta = Float(s) / Float(segments) * 2 * .pi
            rim.append(mesh.addVertex(
                SIMD3(radius * cos(theta), y, radius * sin(theta)),
                normal: normal,
                uv: SIMD2(0.5 + 0.5 * cos(theta), 0.5 + 0.5 * sin(theta))
            ))
        }
        for s in 0..<segments {
            if up {
                mesh.addTriangle(centre, rim[s + 1], rim[s])
            } else {
                mesh.addTriangle(centre, rim[s], rim[s + 1])
            }
        }
    }
}
