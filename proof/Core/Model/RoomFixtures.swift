import Foundation
import simd

/// Hand-built rooms with realistic dimensions and furniture.
///
/// These exist for three reasons, all of them load-bearing:
///
/// 1. **RoomPlan does not run in the simulator, and needs LiDAR on device.**
///    Without fixtures, none of the app past the scan screen could be developed,
///    reviewed or automatically tested. Every fixture flows through exactly the
///    same pipeline as a real scan — the same `ScannedRoom`, the same mass
///    estimation, the same solver — so testing against them tests the real code.
/// 2. **They are the physics regression suite.** A bedroom with a tall bookcase
///    beside the bed must always come back Severe; a room of low, heavy, squat
///    furniture must always come back Low. Those are assertions about the whole
///    stack, not about one function.
/// 3. **They are the demo.** A user who opens the app without scanning anything
///    should still be able to watch a room shake, because that is what convinces
///    them to go and scan their own.
///
/// Dimensions are drawn from the same manufacturer-spec table as the mass
/// catalogue, so the fixtures are dimensionally realistic rather than
/// convenient.
///
/// Every object here is provenanced as `.scanner`, never `.cloudVision`. These
/// rooms were authored by hand; nothing identified them. Labelling a bundled
/// demo "identified by Tremor" would put an AI-refined badge on a value a human
/// typed, which is a small lie in the one part of the interface whose whole job
/// is telling the user how much to trust a number.
public enum RoomFixtures {

    // MARK: - Stable identity
    //
    // These are computed properties, so every read rebuilds the room. If the
    // identifiers were freshly random each time, `RoomFixtures.bedroom.objects`
    // would not match the IDs in an assessment computed from another read — a
    // trap that silently breaks any caller holding one and looking up the other.
    // Deriving the UUID from the room and object name makes every read
    // byte-identical, and makes saved demo rooms survive relaunch.

    /// A UUID derived deterministically from a string, so a fixture element
    /// always has the same identity.
    static func stableID(_ name: String) -> UUID {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325            // FNV-1a offset basis
        for byte in Array(name.utf8) {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        var second = hash
        for byte in Array(name.utf8).reversed() {
            second = (second ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        var bytes = [UInt8]()
        for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8((hash >> UInt64(shift)) & 0xFF)) }
        for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8((second >> UInt64(shift)) & 0xFF)) }
        // Stamp the RFC 4122 version and variant bits so this is a well-formed
        // version-4-shaped UUID rather than arbitrary bytes.
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    // MARK: - Builders

    private static func wall(
        _ name: String, from a: SIMD2<Float>, to b: SIMD2<Float>, height: Float
    ) -> RoomSurface {
        let mid = (a + b) / 2
        let delta = b - a
        return RoomSurface(
            id: stableID(name),
            kind: .wall,
            placement: Placement(
                centre: SIMD3(mid.x, height / 2, mid.y),
                yaw: atan2(delta.y, delta.x)
            ),
            extents: Extents(width: simd_length(delta), height: height, depth: 0.01)
        )
    }

    /// A rectangular shell of four walls and a floor.
    private static func shell(_ room: String, width: Float, depth: Float, height: Float = 2.45) -> [RoomSurface] {
        let hw = width / 2, hd = depth / 2
        return [
            wall("\(room).wall.north", from: SIMD2(-hw, -hd), to: SIMD2(hw, -hd), height: height),
            wall("\(room).wall.east", from: SIMD2(hw, -hd), to: SIMD2(hw, hd), height: height),
            wall("\(room).wall.south", from: SIMD2(hw, hd), to: SIMD2(-hw, hd), height: height),
            wall("\(room).wall.west", from: SIMD2(-hw, hd), to: SIMD2(-hw, -hd), height: height),
            RoomSurface(
                id: stableID("\(room).floor"),
                kind: .floor,
                placement: Placement(centre: SIMD3(0, 0, 0), yaw: 0),
                extents: Extents(width: width, height: 0.01, depth: depth)
            ),
        ]
    }

    private static func door(_ name: String, at position: SIMD2<Float>, yaw: Float) -> RoomSurface {
        RoomSurface(
            id: stableID(name),
            kind: .door,
            placement: Placement(centre: SIMD3(position.x, 1.02, position.y), yaw: yaw),
            extents: Extents(width: 0.86, height: 2.04, depth: 0.01),
            isOpen: false
        )
    }

    private static func window(_ name: String, at position: SIMD2<Float>, yaw: Float) -> RoomSurface {
        RoomSurface(
            id: stableID(name),
            kind: .window,
            placement: Placement(centre: SIMD3(position.x, 1.35, position.y), yaw: yaw),
            extents: Extents(width: 1.20, height: 1.30, depth: 0.01)
        )
    }

    /// Places an object with its base on the floor (or on a support), given its
    /// footprint centre. Callers think in "where does it stand", not "where is
    /// its centroid", which is what makes these fixtures readable.
    private static func object(
        _ id: String,
        _ type: ObjectType,
        at position: SIMD2<Float>,
        size: (w: Float, h: Float, d: Float),
        yaw: Float = 0,
        loading: LoadingState = .partial,
        on supportHeight: Double = 0,
        supportedBy: UUID? = nil,
        mounting: Mounting? = nil,
        anchored: Bool = false,
        confidence: Double = 0.9,
        source: IdentificationProvenance.Source = .scanner,
        scannerCategory: String = "storage"
    ) -> ScannedObject {
        let extents = Extents(width: size.w, height: size.h, depth: size.d)
        let baseY = Float(supportHeight)
        let resolvedMounting = mounting ?? type.defaultMounting
        // Wall-mounted and suspended objects are positioned by their centre
        // directly, since they have no base resting on anything.
        let centreY: Float = resolvedMounting == .wallMounted || resolvedMounting == .suspended
            ? baseY
            : baseY + size.h / 2

        return ScannedObject(
            id: stableID(id),
            type: type,
            placement: Placement(centre: SIMD3(position.x, centreY, position.y), yaw: yaw),
            extents: extents,
            provenance: IdentificationProvenance(
                source: source, confidence: confidence, scannerCategory: scannerCategory),
            mass: MassEstimator.mass(type: type, extents: extents, loading: loading),
            loading: loading,
            mounting: resolvedMounting,
            supportHeight: supportHeight,
            supportedBy: supportedBy,
            isAnchored: anchored
        )
    }

    // MARK: - Fixtures

    /// A bedroom laid out the way FEMA E-74 warns against: a tall loaded
    /// bookcase standing right beside the head of the bed, a framed picture
    /// hung above it, and a dresser carrying a television.
    ///
    /// This is the app's headline scenario and its most important regression:
    /// the bookcase must come back Severe at any strong shaking, because it is
    /// the archetypal furniture-tipover fatality.
    public static var dangerousBedroom: ScannedRoom {
        var surfaces = shell("bedroom", width: 4.2, depth: 3.6)
        surfaces.append(door("bedroom.door", at: SIMD2(-1.4, 1.8), yaw: 0))
        surfaces.append(window("bedroom.window", at: SIMD2(1.0, -1.8), yaw: 0))

        let dresser = object(
            "bedroom.dresser", .dresser, at: SIMD2(1.5, 1.0), size: (1.40, 0.85, 0.50), yaw: .pi / 2,
            loading: .full, scannerCategory: "storage")

        var objects: [ScannedObject] = [
            // The bed, head against the far wall.
            object("bedroom.bed.1", .bed, at: SIMD2(0.0, -0.9), size: (1.55, 0.60, 2.05),
                   loading: .empty, scannerCategory: "bed"),

            // The killer: a 1.9 m loaded bookcase within tipping distance of the
            // pillow. b/h ≈ 0.15 → it starts rocking at 0.15 g, which is MMI VI.
            object("bedroom.bookshelfTall.2", .bookshelfTall, at: SIMD2(-1.55, -1.2), size: (0.80, 1.90, 0.30),
                   yaw: .pi / 2, loading: .full, scannerCategory: "storage"),

            object("bedroom.nightstand.3", .nightstand, at: SIMD2(-0.95, -1.55), size: (0.45, 0.60, 0.40),
                   loading: .partial, scannerCategory: "table"),

            dresser,

            // A 55" television on top of the dresser: a block on a moving base,
            // and the pairing is worse than either piece alone.
            object("bedroom.television.4", .television, at: SIMD2(1.5, 1.0), size: (1.23, 0.78, 0.25),
                   yaw: .pi / 2, loading: .empty, on: 0.85, supportedBy: dresser.id,
                   scannerCategory: "television"),

            // Hung directly above the bed — the single thing FEMA tells you not
            // to do.
            object("bedroom.framedPicture.5", .framedPicture, at: SIMD2(0.0, -1.75), size: (0.60, 0.80, 0.04),
                   on: 1.70, mounting: .wallMounted, scannerCategory: "unknown"),

            // A full-length mirror leaning against the wall.
            object("bedroom.mirrorLeaning.6", .mirrorLeaning, at: SIMD2(1.9, -0.6), size: (0.60, 1.70, 0.05),
                   yaw: .pi / 2, mounting: .leaning, scannerCategory: "unknown"),

            object("bedroom.floorLamp.7", .floorLamp, at: SIMD2(-1.8, 0.9), size: (0.35, 1.65, 0.35),
                   scannerCategory: "unknown"),
        ]
        // A vase perched near the edge of the nightstand.
        objects.append(object(
            "bedroom.vase", .vaseCeramic, at: SIMD2(-0.95, -1.55), size: (0.15, 0.35, 0.15),
            on: 0.60, supportedBy: objects[2].id, scannerCategory: "unknown"))

        return ScannedRoom(
            id: stableID("room.bedroom"),
            name: "Bedroom",
            kind: .bedroom,
            building: BuildingContext(
                floor: 1, totalStoreys: 2, soil: .firm, floorSurface: .hardwood),
            surfaces: surfaces,
            objects: objects
        )
    }

    /// A living room of low, heavy, squat furniture. Almost nothing here can
    /// tip: a sofa is 1.9 times as wide as its centre of mass is high. The
    /// regression this protects is the app's credibility in the other
    /// direction — it must not cry wolf about a coffee table.
    public static var safeLivingRoom: ScannedRoom {
        var surfaces = shell("living", width: 5.0, depth: 4.0)
        surfaces.append(door("living.door", at: SIMD2(-2.0, 1.2), yaw: .pi / 2))
        surfaces.append(window("living.window", at: SIMD2(0.5, -2.0), yaw: 0))

        let objects: [ScannedObject] = [
            object("living.sofa.1", .sofa, at: SIMD2(0.0, 1.2), size: (2.10, 0.85, 0.90),
                   loading: .empty, scannerCategory: "sofa"),
            object("living.armchair.2", .armchair, at: SIMD2(-1.7, 0.0), size: (0.95, 0.95, 0.90),
                   loading: .empty, scannerCategory: "chair"),
            object("living.coffeeTable.3", .coffeeTable, at: SIMD2(0.0, 0.0), size: (1.10, 0.45, 0.60),
                   loading: .empty, scannerCategory: "table"),
            object("living.bookshelfShort.4", .bookshelfShort, at: SIMD2(2.0, -0.5), size: (0.80, 0.90, 0.30),
                   yaw: .pi / 2, loading: .full, scannerCategory: "storage"),
            // Wall-mounted television — correctly installed, so it is not a
            // tipping problem.
            object("living.televisionWallMounted.5", .televisionWallMounted, at: SIMD2(0.0, -1.95), size: (1.23, 0.72, 0.07),
                   on: 1.35, mounting: .wallMounted, scannerCategory: "television"),
            object("living.plantPotLarge.6", .plantPotLarge, at: SIMD2(1.9, 1.5), size: (0.40, 0.45, 0.40),
                   scannerCategory: "unknown"),
        ]

        return ScannedRoom(
            id: stableID("room.living"),
            name: "Living room",
            kind: .livingRoom,
            building: BuildingContext(
                floor: 0, totalStoreys: 2, soil: .firm, floorSurface: .carpet),
            surfaces: surfaces,
            objects: objects
        )
    }

    /// A kitchen: heavy appliances, a gas range, glass, and a doorway that a
    /// falling refrigerator would block. Exercises the regulatory overrides.
    public static var kitchen: ScannedRoom {
        var surfaces = shell("kitchen", width: 3.8, depth: 3.2)
        surfaces.append(door("kitchen.door", at: SIMD2(0.0, 1.6), yaw: 0))

        let objects: [ScannedObject] = [
            object("kitchen.refrigerator.1", .refrigerator, at: SIMD2(-1.3, -1.1), size: (0.91, 1.78, 0.78),
                   scannerCategory: "refrigerator"),
            object("kitchen.rangeGas.2", .rangeGas, at: SIMD2(0.2, -1.25), size: (0.76, 0.92, 0.66),
                   scannerCategory: "stove"),
            object("kitchen.dishwasher.3", .dishwasher, at: SIMD2(1.2, -1.25), size: (0.60, 0.85, 0.60),
                   anchored: true, scannerCategory: "dishwasher"),
            object("kitchen.sink.4", .sink, at: SIMD2(1.6, 0.0), size: (0.80, 0.25, 0.55),
                   on: 0.75, mounting: .anchored, scannerCategory: "sink"),
            object("kitchen.kitchenCabinetUpper.5", .kitchenCabinetUpper, at: SIMD2(-0.5, -1.5), size: (0.90, 0.75, 0.35),
                   loading: .full, on: 1.45, mounting: .wallMounted,
                   scannerCategory: "storage"),
            object("kitchen.microwave.6", .microwave, at: SIMD2(1.2, 0.0), size: (0.50, 0.30, 0.40),
                   on: 0.90, scannerCategory: "unknown"),
        ]

        return ScannedRoom(
            id: stableID("room.kitchen"),
            name: "Kitchen",
            kind: .kitchen,
            building: BuildingContext(
                floor: 0, totalStoreys: 1, soil: .medium, floorSurface: .tile),
            surfaces: surfaces,
            objects: objects
        )
    }

    /// A nursery. Same physics as any other room, but the consequence weighting
    /// is the highest in the app, because tip-over fatalities recorded by the
    /// CPSC are overwhelmingly children.
    public static var nursery: ScannedRoom {
        var surfaces = shell("nursery", width: 3.2, depth: 3.0)
        surfaces.append(door("nursery.door", at: SIMD2(-1.2, 1.5), yaw: 0))

        let objects: [ScannedObject] = [
            object("nursery.crib.1", .crib, at: SIMD2(0.0, -0.9), size: (1.35, 0.95, 0.75),
                   loading: .empty, scannerCategory: "bed"),
            // A tall chest of drawers next to a crib: the exact configuration
            // ASTM F2057 anti-tip kits exist to prevent.
            object("nursery.highboy.2", .highboy, at: SIMD2(1.1, -1.0), size: (0.90, 1.40, 0.45),
                   yaw: .pi / 2, loading: .full, scannerCategory: "storage"),
            object("nursery.bookshelfShort.3", .bookshelfShort, at: SIMD2(-1.2, -0.3), size: (0.80, 0.90, 0.30),
                   yaw: .pi / 2, loading: .full, scannerCategory: "storage"),
            object("nursery.tableLamp.4", .tableLamp, at: SIMD2(-1.2, -0.3), size: (0.30, 0.55, 0.30),
                   on: 0.90, scannerCategory: "unknown"),
        ]

        return ScannedRoom(
            id: stableID("room.nursery"),
            name: "Nursery",
            kind: .nursery,
            building: BuildingContext(
                floor: 1, totalStoreys: 2, soil: .soft, floorSurface: .carpet),
            surfaces: surfaces,
            objects: objects
        )
    }

    /// A garage with an unstrapped gas water heater — the object that started
    /// more than half the residential fires after Northridge 1994, and the one
    /// California law specifically requires you to strap.
    public static var garage: ScannedRoom {
        var surfaces = shell("garage", width: 6.0, depth: 6.0, height: 2.6)
        surfaces.append(door("garage.door", at: SIMD2(0.0, 3.0), yaw: 0))

        let objects: [ScannedObject] = [
            object("garage.waterHeaterGas.1", .waterHeaterGas, at: SIMD2(-2.4, -2.4), size: (0.56, 1.50, 0.56),
                   scannerCategory: "unknown"),
            object("garage.washingMachine.2", .washingMachine, at: SIMD2(-1.5, -2.5), size: (0.68, 0.85, 0.66),
                   scannerCategory: "washerDryer"),
            object("garage.clothesDryer.3", .clothesDryer, at: SIMD2(-0.7, -2.5), size: (0.68, 0.95, 0.68),
                   scannerCategory: "washerDryer"),
            object("garage.filingCabinet.4", .filingCabinet, at: SIMD2(2.4, -2.2), size: (0.46, 1.32, 0.72),
                   loading: .full, scannerCategory: "storage"),
            object("garage.storageBin.5", .storageBin, at: SIMD2(2.4, -2.2), size: (0.60, 0.35, 0.40),
                   loading: .full, on: 1.32, scannerCategory: "storage"),
        ]

        return ScannedRoom(
            id: stableID("room.garage"),
            name: "Garage",
            kind: .garage,
            building: BuildingContext(
                floor: 0, totalStoreys: 2, soil: .firm, floorSurface: .concrete),
            surfaces: surfaces,
            objects: objects
        )
    }

    /// Every fixture, for the demo library and for sweeping tests.
    public static var all: [ScannedRoom] {
        [dangerousBedroom, safeLivingRoom, kitchen, nursery, garage]
    }

    /// A single object standing alone in a bare room, for focused tests of one
    /// object's behaviour without any spatial context confounding the score.
    public static func isolated(
        _ type: ObjectType,
        size: (w: Float, h: Float, d: Float),
        loading: LoadingState = .partial,
        floor: FloorSurface = .hardwood,
        kind: RoomKind = .other
    ) -> ScannedRoom {
        ScannedRoom(
            id: stableID("room.isolated.\(type.rawValue)"),
            name: type.displayName,
            kind: kind,
            building: BuildingContext(floorSurface: floor),
            surfaces: shell("isolated.\(type.rawValue)", width: 4, depth: 4),
            objects: [object("isolated.\(type.rawValue)", type, at: SIMD2(0, 0), size: size, loading: loading)]
        )
    }
}
