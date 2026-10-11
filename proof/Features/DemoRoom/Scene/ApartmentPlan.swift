import Foundation
import simd

// The measured plan of the demo apartment.
//
// This is the single source of truth for where everything is. Every module — shell,
// kitchen, dining, living — reads its numbers from here, so nothing can drift out of
// alignment and a change to the room's width propagates everywhere at once.
//
// Dimensions were recovered from the reference walkthrough by scaling against fixtures of
// known size: a 762 mm slide-in range, 600 mm dishwasher, 610 mm base cabinet depth,
// 920 mm counter height, and an 863 × 2032 mm entry door. Those anchors fix the kitchen
// run, and the rest of the plan follows from the camera's traverse.
//
// Coordinates: X runs west → east, Z runs north → south, Y is up. Metres. The origin is
// the north-west floor corner, so every coordinate in the apartment is positive — which
// makes the numbers below directly readable as a floor plan.

enum Plan {

    // MARK: - Shell

    static let width: Float = 4.70          // X extent
    static let length: Float = 9.40         // Z extent
    static let ceilingHeight: Float = 2.82  // raw concrete soffit
    static let wallThickness: Float = 0.10
    static let baseboardHeight: Float = 0.11

    static var centre: SIMD3<Float> { SIMD3(width / 2, 0, length / 2) }

    /// Zone boundaries along Z, used for camera framing and the guided tour.
    enum Zone {
        static let kitchenEnd: Float = 2.55
        static let diningStart: Float = 2.55
        static let diningEnd: Float = 6.15
        static let livingStart: Float = 6.15
    }

    // MARK: - Kitchen (north wall, Z ≈ 0)

    enum Kitchen {
        static let counterHeight: Float = 0.92
        static let counterDepth: Float = 0.64
        static let baseDepth: Float = 0.60
        static let upperDepth: Float = 0.34
        static let upperBottom: Float = 1.46   // underside of the wall cabinets
        static let upperTop: Float = 2.34

        // Runs along the north wall, west → east.
        static let fridgeX: ClosedRange<Float> = 0.02...0.94
        static let fridgeHeight: Float = 1.82
        static let fridgeDepth: Float = 0.74

        /// The structural column that separates the fridge bay from the sink run. It
        /// carries the white technical print seen in the reference.
        static let columnX: ClosedRange<Float> = 0.94...1.60
        static let columnDepth: Float = 0.62

        static let dishwasherX: ClosedRange<Float> = 1.60...2.20
        static let sinkX: ClosedRange<Float> = 2.20...3.06
        static let sinkCentre: Float = 2.63

        static let rangeX: ClosedRange<Float> = 3.06...3.82
        static let rangeCentre: Float = 3.44
        static let hoodWidth: Float = 0.76
        static let hoodBottom: Float = 1.52

        static let microwaveX: ClosedRange<Float> = 3.82...4.42
        static let microwaveCentre: Float = 4.12

        /// Where the counter run ends and the entry return wall begins.
        static let runEnd: Float = 4.42

        static let backsplashTop: Float = 1.46

        /// Ceiling track light: a single rail running south from the kitchen.
        static let trackX: Float = 2.30
        static let trackZ: ClosedRange<Float> = 0.55...3.45
        static let trackHeadCount = 5
    }

    // MARK: - Entry

    enum Entry {
        static let doorZ: ClosedRange<Float> = 0.72...1.58
        static let doorHeight: Float = 2.10
        static let doorWall: Float = width   // east wall
    }

    // MARK: - Island / breakfast bar

    enum Island {
        /// The dark cabinet mass, which has open shelving on its south face.
        static let baseX: ClosedRange<Float> = 2.16...3.34
        static let baseZ: ClosedRange<Float> = 2.86...3.76
        static let baseHeight: Float = 0.88

        /// The quartz slab, which overhangs west to become a two-seat table.
        static let topX: ClosedRange<Float> = 1.24...3.48
        static let topZ: ClosedRange<Float> = 2.74...3.88
        static let topHeight: Float = 0.92
        static let topThickness: Float = 0.05

        /// Waterfall leg: the slab returns to the floor at the east end.
        static let waterfallX: Float = 3.44

        static let stoolA = SIMD2<Float>(1.72, 2.44)   // facing south
        static let stoolB = SIMD2<Float>(1.72, 4.18)   // facing north
        static let settingA = SIMD2<Float>(1.66, 3.06)
        static let settingB = SIMD2<Float>(1.66, 3.56)
    }

    // MARK: - Dining

    enum Dining {
        static let centre = SIMD2<Float>(2.16, 5.42)
        static let topRadius: Float = 0.58
        static let topHeight: Float = 0.74
        static let topThickness: Float = 0.04
        static let chairCount = 4
        static let chairRadius: Float = 0.86
        /// Chairs are rotated off the axes so the arrangement does not read as a grid.
        static let chairPhase: Float = 0.42
    }

    // MARK: - Storage

    enum Shelf {
        /// Black ladder shelving on the west wall, between dining and living.
        ///
        /// Stood 140 mm further into the room than it used to. The unit rakes back 220 mm
        /// over its height, so at 0.20 the top board's rear edge was at x = −0.07 — seven
        /// centimetres *inside* the west wall. A single bounding-box collider spanning the
        /// full depth hid that; per-plank colliders do not, and the solver's answer to a
        /// bookcase embedded in a wall is to fire it across the room.
        static let centre = SIMD2<Float>(0.34, 4.86)
        static let width: Float = 0.98
        static let height: Float = 2.32
        static let depth: Float = 0.34
        static let shelfCount = 5
        /// The unit stands square to the west wall, so its local +X runs along the wall.
        static let yaw: Float = .pi / 2

        /// How far the uprights lean back over the full height. The boards follow the rake
        /// and get shallower as they climb, which is what makes it read as a ladder.
        static let lean: Float = 0.22
        static let boardThickness: Float = 0.024

        /// Everything below is what a shelf *is* to the rest of the demo: where its boards
        /// are and how much room there is on each one. The unit's mesh, its per-plank
        /// collider and every object standing on it all read these, so a book cannot end up
        /// hovering a centimetre above a board that moved.

        /// Height of the centre line of board `i`, counting from the bottom.
        static func boardCentre(_ i: Int) -> Float {
            0.30 + Float(i) * (height - 0.44) / Float(shelfCount - 1)
        }

        /// The top face of board `i` — the surface objects actually stand on.
        static func deck(_ i: Int) -> Float { boardCentre(i) + boardThickness / 2 }

        /// Local Z of the front edge at height `y`, following the rake.
        static func frontZ(_ y: Float) -> Float { depth / 2 - lean * (y / height) }

        /// Front-to-back depth of the board at height `y`.
        static func boardDepth(_ y: Float) -> Float { depth - 0.11 * (y / height) }

        /// Local Z at which an object of the given depth stands centred on board `i`,
        /// nudged back from the front edge so nothing is authored teetering on the lip.
        static func standZ(_ i: Int, depth objectDepth: Float) -> Float {
            let y = boardCentre(i)
            return frontZ(y) - 0.026 - objectDepth / 2
        }
    }

    // MARK: - Living room

    enum Living {
        static let rugCentre = SIMD2<Float>(2.30, 7.80)
        static let rugSize = SIMD2<Float>(3.10, 3.90)
        static let rugThickness: Float = 0.028

        /// Sofa sits against the west wall, facing east into the room.
        static let sofaCentre = SIMD2<Float>(0.62, 7.66)
        static let sofaLength: Float = 2.18
        static let sofaDepth: Float = 0.92
        static let sofaYaw: Float = .pi / 2      // faces +X (east)

        static let coffeeCentre = SIMD2<Float>(2.16, 7.74)
        static let coffeeSize = SIMD2<Float>(1.28, 0.82)
        static let coffeeHeight: Float = 0.35
        static let coffeeYaw: Float = 0.16

        /// Cognac swivel chair, angled back toward the sofa.
        static let armchairCentre = SIMD2<Float>(3.42, 6.86)
        static let armchairYaw: Float = -2.25

        static let floorLampCentre = SIMD2<Float>(0.44, 6.42)
        static let floorLampHeight: Float = 1.58

        /// Console under the east window, carrying the television and the second table lamp.
        ///
        /// Pulled 14 cm north of where it used to sit: at 8.90 the 1.20 m carcass ran from
        /// z = 8.30 to z = 9.50, which is 10 cm through the south wall. Nobody had noticed
        /// because nothing stood on it near that end. Something does now.
        static let consoleCentre = SIMD2<Float>(4.42, 8.76)
        static let consoleWidth: Float = 1.20
        static let consoleDepth: Float = 0.34
        /// Top face of the console — the surface the television and the lamp stand on.
        static let consoleTop: Float = 0.796
        /// Along the console, north end to south end: lamp, then television.
        static let consoleLampZ: Float = 8.36
        static let tvCentre = SIMD2<Float>(4.46, 8.98)
        /// A 32-inch panel. The console is 1.20 m long and has to carry a lamp as well;
        /// anything larger is a television that does not fit the room it is in.
        static let tvSize = SIMD2<Float>(0.72, 0.42)

        static let poufCentre = SIMD2<Float>(3.94, 8.20)
    }

    // MARK: - Openings

    /// Windows on the east and south walls, meeting at the south-east corner. This is the
    /// corner-glazing that gives the reference room its light.
    enum Window {
        static let sill: Float = 0.44
        static let head: Float = 2.34

        /// (start, end) along Z on the east wall.
        static let eastA: ClosedRange<Float> = 6.36...7.92
        static let eastB: ClosedRange<Float> = 8.30...9.26
        /// Along X on the south wall.
        static let south: ClosedRange<Float> = 2.54...4.24

        static let frameThickness: Float = 0.055
        static let mullionWidth: Float = 0.05
    }

    // MARK: - Wall art

    enum Art {
        /// Large black-and-white abstract above the sofa, on the west wall.
        static let abstractCentre = SIMD2<Float>(0.06, 7.62)
        static let abstractSize = SIMD2<Float>(1.32, 1.02)
        static let abstractY: Float = 1.72

        /// Warm-toned abstract on the pier between the two east windows.
        static let pierCentre = SIMD2<Float>(width - 0.06, 8.12)
        static let pierSize = SIMD2<Float>(0.52, 0.74)
        static let pierY: Float = 1.62

        /// The white technical print on the south face of the kitchen column.
        static let columnPrintSize = SIMD2<Float>(0.44, 0.60)
        static let columnPrintY: Float = 1.56
    }

    // MARK: - Lighting anchors

    enum Light {
        /// Sun direction: late-afternoon light entering through the corner glazing.
        static let sunDirection = SIMD3<Float>(0.55, -0.62, -0.56)
        static let sunIntensity: Float = 3200
        static let skyIntensity: Float = 900

        /// Warm practicals, in world space.
        static let floorLamp = SIMD3<Float>(0.44, 1.48, 6.42)
        static let consoleLamp = SIMD3<Float>(4.36, 1.12, Living.consoleLampZ)
        static let kitchenUnderCabinet = SIMD3<Float>(2.60, 1.42, 0.40)
    }

    // MARK: - Camera

    enum Camera {
        /// Eye height for the walkthrough mode.
        static let eyeHeight: Float = 1.62

        /// Where the first-person mode starts: standing in the gap between the dining and
        /// living zones, looking north down the length of the flat past the dining table
        /// and into the kitchen.
        ///
        /// Moved from z = 5.90. The dining table is centred at z = 5.42 with a 0.58 m
        /// radius and its chairs ring it at 0.86 m, so the old eye point stood *inside* the
        /// table: the breakfast bar slab filled the lower third of the frame at near-plane
        /// distance and a stool clipped through the bottom edge. First person is the mode a
        /// viewer tries first, and it opened with the camera buried in the furniture.
        /// z = 6.80 clears the chair ring by 270 mm and is more than a metre from the
        /// armchair, the coffee table and the sofa.
        static let startPosition = SIMD3<Float>(2.30, eyeHeight, 6.80)
        static let startYaw: Float = .pi        // looking toward -Z (north)

        /// The establishing orbit shot. The ceiling and the near walls are cut away in
        /// this mode, so the camera can sit well above the room and look down into it.
        /// Distance is set so the full 9.4 m length fits the portrait viewport at a 46°
        /// vertical field of view, with a little margin.
        static let orbitTarget = SIMD3<Float>(2.35, 0.95, 5.20)
        static let orbitDistance: Float = 15.2
        static let orbitYaw: Float = 0.68
        static let orbitPitch: Float = 0.62

        /// Top-down plan view. Tall enough to fit the 9.4 m length in a 42° vertical FOV.
        static let planHeight: Float = 13.2
    }
}
