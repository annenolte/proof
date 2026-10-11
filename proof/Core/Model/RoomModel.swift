import Foundation
import simd

// MARK: - Geometry

/// A right-handed, Y-up, gravity-aligned transform in room space, in metres —
/// the same convention RoomPlan uses, so scan output needs no conversion.
///
/// Stored as the translation plus a yaw about the vertical axis rather than as a
/// full 4×4. Every object RoomPlan reports is a gravity-aligned cuboid, so yaw
/// is the only rotation that carries information, and reducing it makes the
/// model trivially `Codable` and diffable.
public struct Placement: Codable, Hashable, Sendable {
    /// Centre of the object's bounding box, metres.
    public var centre: SIMD3<Float>
    /// Rotation about the world Y axis, radians.
    public var yaw: Float

    public init(centre: SIMD3<Float>, yaw: Float) {
        self.centre = centre
        self.yaw = yaw
    }

    /// The model→world matrix.
    ///
    /// `yaw` means: the object's local +X (its width axis) points along
    /// `(cos yaw, 0, sin yaw)` in world space. That is the convention RoomPlan's
    /// own matrices use, and therefore the one `init(transform:)` reads, so the
    /// two must agree — `Placement(transform: p.transform) == p` for every `p`,
    /// which `PlacementTests` asserts.
    ///
    /// (An earlier version negated the sign here, which made the round trip
    /// return −yaw. Nothing in the core noticed, because it only ever built
    /// matrices from stored yaws rather than comparing the two. It would have
    /// mirrored every angled object on the 3D stage the first time someone
    /// scanned a room with furniture at an angle to the walls.)
    public var transform: simd_float4x4 {
        let c = cos(yaw), s = sin(yaw)
        return simd_float4x4(
            SIMD4<Float>( c, 0, s, 0),      // local +X — width
            SIMD4<Float>( 0, 1, 0, 0),      // local +Y — up
            SIMD4<Float>(-s, 0, c, 0),      // local +Z — depth
            SIMD4<Float>(centre.x, centre.y, centre.z, 1)
        )
    }

    /// The rotation alone, for placing an entity in a 3D scene.
    public var rotation: simd_quatf {
        let c = cos(yaw), s = sin(yaw)
        return simd_quatf(simd_float3x3(
            SIMD3<Float>( c, 0, s),
            SIMD3<Float>( 0, 1, 0),
            SIMD3<Float>(-s, 0, c)))
    }

    /// Recovers a placement from a RoomPlan transform, discarding the tilt that
    /// RoomPlan never reports as meaningful for cuboid objects.
    public init(transform m: simd_float4x4) {
        self.centre = SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        self.yaw = atan2(m.columns.0.z, m.columns.0.x)
    }
}

/// Full extents of a bounding box in the element's local frame, metres, using
/// RoomPlan's axis convention: x = width, y = height, z = depth.
public struct Extents: Codable, Hashable, Sendable {
    public var width: Float
    public var height: Float
    public var depth: Float

    public init(width: Float, height: Float, depth: Float) {
        self.width = max(width, 0.001)
        self.height = max(height, 0.001)
        self.depth = max(depth, 0.001)
    }

    public init(_ v: SIMD3<Float>) {
        self.init(width: v.x, height: v.y, depth: v.z)
    }

    public var volume: Double {
        Double(width) * Double(height) * Double(depth)
    }

    /// The smaller horizontal half-dimension. A block tips about its weakest
    /// axis, so this is the `b` that governs the rocking threshold.
    public var governingHalfWidth: Double {
        Double(min(width, depth)) / 2.0
    }

    public var simd: SIMD3<Float> { SIMD3(width, height, depth) }
}

// MARK: - Surfaces

/// A wall, window, door or opening from the scan.
public struct RoomSurface: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case wall, window, door, opening, floor, ceiling
    }

    public var id: UUID
    public var kind: Kind
    public var placement: Placement
    public var extents: Extents
    /// For doors: whether the scan saw it standing open.
    public var isOpen: Bool
    /// Confidence RoomPlan assigned, 0…1.
    public var confidence: Double

    public init(
        id: UUID = UUID(), kind: Kind, placement: Placement, extents: Extents,
        isOpen: Bool = false, confidence: Double = 1.0
    ) {
        self.id = id
        self.kind = kind
        self.placement = placement
        self.extents = extents
        self.isOpen = isOpen
        self.confidence = confidence
    }

    /// True for the openings a person escapes through. Blocking one of these is
    /// an egress hazard in its own right, independent of anyone being hit.
    public var isEgress: Bool { kind == .door || kind == .opening }
}

// MARK: - Objects

/// How sure the pipeline is about an object's identity, and where that
/// confidence came from. Surfaced in the UI, because a user deserves to know
/// when the app is guessing.
public struct IdentificationProvenance: Codable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable {
        /// Straight from RoomPlan's own coarse category.
        case scanner
        /// Refined by the on-device Vision pass.
        case onDeviceVision
        /// Refined by the cloud vision-language model.
        case cloudVision
        /// Set explicitly by the user, which always wins.
        case user
    }

    public var source: Source
    /// 0…1.
    public var confidence: Double
    /// The raw RoomPlan category string this started from.
    public var scannerCategory: String

    public init(source: Source, confidence: Double, scannerCategory: String) {
        self.source = source
        self.confidence = confidence
        self.scannerCategory = scannerCategory
    }

    public var isUncertain: Bool { confidence < 0.6 && source != .user }

    public var displayName: String {
        switch source {
        case .scanner: return "Detected by the scanner"
        case .onDeviceVision: return "Identified on device"
        case .cloudVision: return "Identified by proof"
        case .user: return "You set this"
        }
    }
}

/// How full a piece of storage is. Mass changes by a factor of three between
/// empty and full, which moves a bookcase across two risk bands, so this is the
/// one question worth inferring carefully — and the one the user can correct in
/// a single tap.
public enum LoadingState: String, Codable, CaseIterable, Sendable {
    case empty, partial, full

    /// Mass multiplier relative to the catalogue's density prior, which is
    /// quoted for a typically-loaded example of that object. A tall bookcase
    /// with a 307 kg/m³ prior comes out at 35 kg empty, 140 kg typical and
    /// 210 kg packed — which brackets the manufacturer-spec values for an empty
    /// and a fully loaded unit of that size.
    public var multiplier: Double {
        switch self {
        case .empty: return 0.25
        case .partial: return 1.0
        case .full: return 1.5
        }
    }

    public var displayName: String {
        switch self {
        case .empty: return "Empty"
        case .partial: return "Half full"
        case .full: return "Packed"
        }
    }
}

/// One thing in the room, with everything needed to simulate and score it.
public struct ScannedObject: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var type: ObjectType
    public var placement: Placement
    public var extents: Extents
    public var provenance: IdentificationProvenance

    /// Mass in kg. Estimated from the density prior and bounding-box volume,
    /// then clamped to the type's plausible envelope; overridable by the user.
    public var mass: Double
    /// True once the user has set the mass themselves, so no later pass
    /// overwrites it.
    public var massIsUserSet: Bool

    public var loading: LoadingState
    public var mounting: Mounting
    /// Height of the surface this object stands on above the floor, metres.
    /// Zero for floor-standing.
    public var supportHeight: Double
    /// The object this one sits on top of, if any. A TV on a dresser is a block
    /// on a moving base, and both the physics and the advice differ.
    public var supportedBy: UUID?

    /// Centre-of-mass height above the object's own base, metres. Defaults to
    /// the type's prior fraction of the height but is adjusted when something
    /// heavy sits on top.
    public var centreOfMassHeight: Double

    /// Explicitly marked as strapped, bolted or built in by the user. Overrides
    /// the type's default mounting.
    public var isAnchored: Bool

    /// A free-text note the user attached.
    public var note: String?

    public init(
        id: UUID = UUID(),
        type: ObjectType,
        placement: Placement,
        extents: Extents,
        provenance: IdentificationProvenance,
        mass: Double,
        massIsUserSet: Bool = false,
        loading: LoadingState = .partial,
        mounting: Mounting? = nil,
        supportHeight: Double = 0,
        supportedBy: UUID? = nil,
        centreOfMassHeight: Double? = nil,
        isAnchored: Bool = false,
        note: String? = nil
    ) {
        self.id = id
        self.type = type
        self.placement = placement
        self.extents = extents
        self.provenance = provenance
        self.mass = mass
        self.massIsUserSet = massIsUserSet
        self.loading = loading
        self.mounting = mounting ?? type.defaultMounting
        self.supportHeight = supportHeight
        self.supportedBy = supportedBy
        self.centreOfMassHeight = centreOfMassHeight
            ?? Double(extents.height) * type.centreOfMassFraction
        self.isAnchored = isAnchored
        self.note = note
    }

    /// Height of the object's topmost point above the floor, metres.
    public var topHeight: Double {
        supportHeight + Double(extents.height)
    }

    /// Horizontal footprint centre in room space.
    public var groundPosition: SIMD2<Float> {
        SIMD2(placement.centre.x, placement.centre.z)
    }

    /// Slenderness ratio h_cm / b. Above about 3 an object is at real risk of
    /// tipping in a strong quake; above 6 it tips in a moderate one.
    public var slenderness: Double {
        centreOfMassHeight / max(extents.governingHalfWidth, 1e-4)
    }

    /// Whether the object can move at all under the current mounting.
    public var canMove: Bool {
        !isAnchored && mounting != .anchored
    }
}

// MARK: - Room

/// What the room is used for. Drives the occupancy weighting in the risk score:
/// a bookcase beside a bed is a different proposition from the same bookcase in
/// a garage.
public enum RoomKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case bedroom, livingRoom, kitchen, diningRoom, office, bathroom
    case hallway, garage, basement, nursery, other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bedroom: return "Bedroom"
        case .livingRoom: return "Living room"
        case .kitchen: return "Kitchen"
        case .diningRoom: return "Dining room"
        case .office: return "Office"
        case .bathroom: return "Bathroom"
        case .hallway: return "Hallway"
        case .garage: return "Garage"
        case .basement: return "Basement"
        case .nursery: return "Nursery"
        case .other: return "Room"
        }
    }

    public var symbolName: String {
        switch self {
        case .bedroom: return "bed.double.fill"
        case .livingRoom: return "sofa.fill"
        case .kitchen: return "cooktop.fill"
        case .diningRoom: return "table.furniture.fill"
        case .office: return "desktopcomputer"
        case .bathroom: return "bathtub.fill"
        case .hallway: return "door.left.hand.open"
        case .garage: return "car.fill"
        case .basement: return "stairs"
        case .nursery: return "figure.and.child.holdinghands"
        case .other: return "square.split.bottomrightquarter"
        }
    }

    /// Multiplier on the consequence score. People sleep in bedrooms and
    /// nurseries and cannot react; nobody stands in a garage for eight hours.
    public var occupancyWeight: Double {
        switch self {
        case .bedroom: return 1.10
        case .nursery: return 1.20
        case .livingRoom, .office, .kitchen, .diningRoom: return 1.0
        case .bathroom, .hallway: return 0.95
        case .garage, .basement: return 0.85
        case .other: return 1.0
        }
    }

    /// Rooms where a child is the likely occupant, which raises consequence:
    /// tip-over fatalities recorded by the CPSC are overwhelmingly children.
    public var isChildOccupied: Bool { self == .nursery }
}

/// Where the room sits in the building, which sets how much the ground motion
/// is amplified before it reaches the furniture.
public struct BuildingContext: Codable, Hashable, Sendable {
    /// Storey the room is on. 0 is ground level.
    public var floor: Int
    /// Total storeys in the building.
    public var totalStoreys: Int
    /// Soil the building stands on.
    public var soil: SoilClass
    /// The floor's own surface material, which sets the friction under every
    /// free-standing object in the room.
    public var floorSurface: FloorSurface

    public init(
        floor: Int = 0,
        totalStoreys: Int = 1,
        soil: SoilClass = .firm,
        floorSurface: FloorSurface = .hardwood
    ) {
        self.floor = max(floor, 0)
        self.totalStoreys = max(totalStoreys, self.floor + 1)
        self.soil = soil
        self.floorSurface = floorSurface
    }

    /// ASCE 7-22 §13.3.1 amplification from ground motion to this floor.
    public var floorAmplification: Double {
        IntensityScale.floorAmplification(floor: floor, totalStoreys: totalStoreys)
    }

    public var summary: String {
        let storey: String
        switch floor {
        case 0: storey = "Ground floor"
        case 1: storey = "1st floor"
        case 2: storey = "2nd floor"
        case 3: storey = "3rd floor"
        default: storey = "\(floor)th floor"
        }
        return "\(storey) · \(soil.displayName) · \(floorSurface.displayName)"
    }
}

/// A complete scanned room: geometry, contents, and the context needed to judge
/// it. This is the document the app saves, shares, and re-simulates.
public struct ScannedRoom: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: RoomKind
    public var building: BuildingContext
    public var surfaces: [RoomSurface]
    public var objects: [ScannedObject]
    public var createdAt: Date
    public var updatedAt: Date
    /// Relative path, inside the room store, of the USDZ the scanner exported.
    public var usdzFileName: String?
    /// Relative paths of the thumbnail and per-object crops the scan captured.
    public var thumbnailFileName: String?

    public init(
        id: UUID = UUID(),
        name: String,
        kind: RoomKind = .other,
        building: BuildingContext = BuildingContext(),
        surfaces: [RoomSurface] = [],
        objects: [ScannedObject] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        usdzFileName: String? = nil,
        thumbnailFileName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.building = building
        self.surfaces = surfaces
        self.objects = objects
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.usdzFileName = usdzFileName
        self.thumbnailFileName = thumbnailFileName
    }

    public var walls: [RoomSurface] { surfaces.filter { $0.kind == .wall } }
    public var doors: [RoomSurface] { surfaces.filter { $0.kind == .door } }
    public var egressOpenings: [RoomSurface] { surfaces.filter(\.isEgress) }

    public func object(id: UUID) -> ScannedObject? {
        objects.first { $0.id == id }
    }

    /// Approximate floor area in m², from the extent of the walls. Used for the
    /// library card subtitle and nothing load-bearing.
    public var floorArea: Double {
        let xs = surfaces.flatMap { [$0.placement.centre.x] }
        let zs = surfaces.flatMap { [$0.placement.centre.z] }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minZ = zs.min(), let maxZ = zs.max() else { return 0 }
        return Double(maxX - minX) * Double(maxZ - minZ)
    }

    /// Ceiling height in metres, taken as the tallest wall.
    public var ceilingHeight: Double {
        Double(walls.map(\.extents.height).max() ?? 2.4)
    }

    /// Objects that can actually move, and so are worth simulating.
    public var movableObjects: [ScannedObject] {
        objects.filter(\.canMove)
    }

    /// The places a person is likely to be, used to compute strike zones.
    public var occupantZones: [ScannedObject] {
        objects.filter { $0.type.isOccupantZone }
    }
}
