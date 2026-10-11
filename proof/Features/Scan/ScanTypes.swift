import Foundation
import simd

// MARK: - A RoomPlan-shaped scan, without RoomPlan
//
// `RoomPlan.CapturedRoom` cannot be constructed: it has no public initialiser,
// and the only way to obtain one is `RoomBuilder`, which requires LiDAR and
// throws `deviceNotSupported` in the Simulator. That makes the single
// highest-risk piece of code in the scanning path — the geometry conversion —
// impossible to test directly against the SDK type.
//
// So the conversion is defined over `RawCapturedRoom`: a faithful, *constructible*
// mirror of `CapturedRoom` using exactly RoomPlan's own conventions (centred
// transforms, full extents, metres, Y-up, zero-thickness planes). The bridge from
// the real `CapturedRoom` is a few lines of field copying in
// `CapturedRoomConverter+RoomPlan`; everything that can be wrong — axis
// conventions, floor rebasing, parent resolution, category refinement — lives in
// the tested path.

/// RoomPlan's three-level confidence, mirrored so the model layer never has to
/// import RoomPlan.
public enum RawConfidence: String, Codable, Sendable, CaseIterable {
    case high, medium, low

    /// 0…1, the number we record in `IdentificationProvenance` and
    /// `RoomSurface.confidence`.
    public var score: Double {
        switch self {
        case .high: return 1.0
        case .medium: return 0.7
        case .low: return 0.3
        }
    }
}

/// A planar element of the room — wall, door, window, opening or floor — in
/// RoomPlan's conventions.
///
/// `transform` is **centred** (column 3 is the bounding-box centroid) and
/// orthonormal with no scale; `dimensions` are **full extents** in the element's
/// local frame. For walls, doors, windows and openings the local frame is
/// `x = width, y = height, z = thickness ≈ 0`. For floors the local frame is
/// rotated so that `z` is the (vertical) normal and `x`/`y` span the floor plane.
public struct RawSurface: Sendable {
    public var identifier: UUID
    public var kind: RoomSurface.Kind
    public var isOpen: Bool
    public var confidence: RawConfidence
    public var transform: simd_float4x4
    public var dimensions: SIMD3<Float>
    public var parentIdentifier: UUID?
    /// How many of the four edges the user scanned to completion, 0…4. Drives
    /// the "wall completeness" quality gate.
    public var completedEdgeCount: Int
    /// The true, possibly non-rectangular outline, in the element's **local**
    /// frame. Empty when RoomPlan reported none.
    public var polygonCorners: [SIMD3<Float>]

    public init(
        identifier: UUID = UUID(),
        kind: RoomSurface.Kind,
        isOpen: Bool = false,
        confidence: RawConfidence = .high,
        transform: simd_float4x4,
        dimensions: SIMD3<Float>,
        parentIdentifier: UUID? = nil,
        completedEdgeCount: Int = 4,
        polygonCorners: [SIMD3<Float>] = []
    ) {
        self.identifier = identifier
        self.kind = kind
        self.isOpen = isOpen
        self.confidence = confidence
        self.transform = transform
        self.dimensions = dimensions
        self.parentIdentifier = parentIdentifier
        self.completedEdgeCount = completedEdgeCount
        self.polygonCorners = polygonCorners
    }
}

/// A furniture/appliance cuboid, in RoomPlan's conventions.
///
/// `category` is the raw RoomPlan category string — one of the sixteen listed in
/// `docs/research/api-roomplan.md` §2.1 — because that is the key
/// `ObjectType.candidates(forRoomPlanCategory:)` takes.
public struct RawObject: Sendable {
    public var identifier: UUID
    public var category: String
    public var confidence: RawConfidence
    public var transform: simd_float4x4
    public var dimensions: SIMD3<Float>
    public var parentIdentifier: UUID?

    public init(
        identifier: UUID = UUID(),
        category: String,
        confidence: RawConfidence = .high,
        transform: simd_float4x4,
        dimensions: SIMD3<Float>,
        parentIdentifier: UUID? = nil
    ) {
        self.identifier = identifier
        self.category = category
        self.confidence = confidence
        self.transform = transform
        self.dimensions = dimensions
        self.parentIdentifier = parentIdentifier
    }
}

/// The whole scan. The arrays are kept disjoint exactly as `CapturedRoom` keeps
/// them, so the bridge is a straight copy and nothing is silently merged.
public struct RawCapturedRoom: Sendable {
    public var identifier: UUID
    public var walls: [RawSurface]
    public var doors: [RawSurface]
    public var windows: [RawSurface]
    public var openings: [RawSurface]
    public var floors: [RawSurface]
    public var objects: [RawObject]

    public init(
        identifier: UUID = UUID(),
        walls: [RawSurface] = [],
        doors: [RawSurface] = [],
        windows: [RawSurface] = [],
        openings: [RawSurface] = [],
        floors: [RawSurface] = [],
        objects: [RawObject] = []
    ) {
        self.identifier = identifier
        self.walls = walls
        self.doors = doors
        self.windows = windows
        self.openings = openings
        self.floors = floors
        self.objects = objects
    }

    public var allSurfaces: [RawSurface] {
        walls + doors + windows + openings + floors
    }

    public var isEmpty: Bool { allSurfaces.isEmpty && objects.isEmpty }
}

// MARK: - Building RoomPlan-shaped transforms

/// Constructors for the centred, orthonormal, scale-free matrices RoomPlan emits.
///
/// These exist so tests (and the replay path) can state geometry the way a human
/// thinks about it — "a 4 m wall running east, centred here" — and get back
/// exactly the matrix the SDK would have produced.
public enum RawScanGeometry {

    /// A vertical planar element (wall/door/window/opening).
    ///
    /// - Parameters:
    ///   - centre: the bounding-box centroid, world metres.
    ///   - widthDirection: the direction the element's **local +X** points, in
    ///     the world XZ plane. Need not be normalised.
    public static func planeTransform(
        centre: SIMD3<Float>, widthDirection: SIMD2<Float>
    ) -> simd_float4x4 {
        let d = simd_length(widthDirection) > 1e-6
            ? simd_normalize(widthDirection)
            : SIMD2<Float>(1, 0)
        let right = SIMD3<Float>(d.x, 0, d.y)                // local +X
        let up = SIMD3<Float>(0, 1, 0)                        // local +Y
        let normal = simd_cross(right, up)                    // local +Z
        return simd_float4x4(
            SIMD4(right.x, right.y, right.z, 0),
            SIMD4(up.x, up.y, up.z, 0),
            SIMD4(normal.x, normal.y, normal.z, 0),
            SIMD4(centre.x, centre.y, centre.z, 1)
        )
    }

    /// A vertical planar element whose width axis lies at `yaw` radians, using
    /// the same yaw convention `Placement(transform:)` recovers — that is,
    /// `atan2(z, x)` of the width direction.
    public static func planeTransform(centre: SIMD3<Float>, yaw: Float) -> simd_float4x4 {
        planeTransform(centre: centre, widthDirection: SIMD2(cos(yaw), sin(yaw)))
    }

    /// A floor: local +Z is the (upward) normal, local +X and +Y span the plane.
    public static func floorTransform(centre: SIMD3<Float>, yaw: Float = 0) -> simd_float4x4 {
        let right = SIMD3<Float>(cos(yaw), 0, sin(yaw))       // local +X
        let normal = SIMD3<Float>(0, 1, 0)                    // local +Z
        let depth = simd_cross(normal, right)                 // local +Y
        return simd_float4x4(
            SIMD4(right.x, right.y, right.z, 0),
            SIMD4(depth.x, depth.y, depth.z, 0),
            SIMD4(normal.x, normal.y, normal.z, 0),
            SIMD4(centre.x, centre.y, centre.z, 1)
        )
    }

    /// A gravity-aligned cuboid object.
    public static func objectTransform(centre: SIMD3<Float>, yaw: Float) -> simd_float4x4 {
        planeTransform(centre: centre, yaw: yaw)
    }

    /// Yaw about world +Y, in the convention `Placement` stores: `atan2` of the
    /// local +X axis's z over its x.
    public static func yaw(of m: simd_float4x4) -> Float {
        atan2(m.columns.0.z, m.columns.0.x)
    }

    /// Translation column.
    public static func centre(of m: simd_float4x4) -> SIMD3<Float> {
        SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z)
    }

    /// A world-space point from a point in the element's local frame.
    public static func world(_ local: SIMD3<Float>, in m: simd_float4x4) -> SIMD3<Float> {
        let p = m * SIMD4<Float>(local.x, local.y, local.z, 1)
        return SIMD3(p.x, p.y, p.z)
    }
}

// MARK: - Quality

/// The S-10 quality gate: whether this scan is good enough to build a report on.
///
/// Tremor refuses to put a confident number on a bad scan, so this is computed on
/// every conversion and travels with the result.
public struct ScanQualityReport: Codable, Hashable, Sendable {

    public enum Issue: String, Codable, Hashable, Sendable, CaseIterable {
        case roomShape
        case wallCompleteness
        case confidence
        case noObjects

        public var title: String {
            switch self {
            case .roomShape: return "Room shape"
            case .wallCompleteness: return "Wall coverage"
            case .confidence: return "Confidence"
            case .noObjects: return "Furniture"
            }
        }

        public var message: String {
            switch self {
            case .roomShape: return "We couldn't close the room outline."
            case .wallCompleteness: return "Some walls weren't fully scanned."
            case .confidence: return "Parts of the scan are low confidence."
            case .noObjects: return "No furniture was detected."
            }
        }
    }

    public var wallCount: Int
    public var floorCount: Int
    public var openingCount: Int
    public var objectCount: Int
    /// Objects dropped for low confidence or implausible size.
    public var droppedObjectCount: Int
    /// Fraction of walls whose four edges were all scanned, 0…1.
    public var completeWallFraction: Double
    /// Fraction of all elements RoomPlan rated `.high`, 0…1.
    public var highConfidenceFraction: Double
    /// Fraction of all elements RoomPlan rated `.low`, 0…1.
    public var lowConfidenceFraction: Double
    /// m², from the floor polygon when there is one.
    public var floorArea: Double
    public var issues: [Issue]

    public init(
        wallCount: Int = 0,
        floorCount: Int = 0,
        openingCount: Int = 0,
        objectCount: Int = 0,
        droppedObjectCount: Int = 0,
        completeWallFraction: Double = 0,
        highConfidenceFraction: Double = 0,
        lowConfidenceFraction: Double = 0,
        floorArea: Double = 0,
        issues: [Issue] = []
    ) {
        self.wallCount = wallCount
        self.floorCount = floorCount
        self.openingCount = openingCount
        self.objectCount = objectCount
        self.droppedObjectCount = droppedObjectCount
        self.completeWallFraction = completeWallFraction
        self.highConfidenceFraction = highConfidenceFraction
        self.lowConfidenceFraction = lowConfidenceFraction
        self.floorArea = floorArea
        self.issues = issues
    }

    /// Every check passed — offer "Build my report" as the primary action.
    public var passes: Bool { issues.isEmpty }

    /// Something failed but the user chose to continue anyway. Set by the UI, not
    /// by the converter; the report carries a permanent caveat when it is true.
    public var isDegraded: Bool { !issues.isEmpty }

    /// A room with no walls and no objects is not a scan at all.
    public var isUsable: Bool { objectCount > 0 || wallCount >= 3 }
}

// MARK: - Progress

/// How far along a live scan is. Four independent tracks, because a single
/// spinner tells the user nothing about what to point the phone at next.
public struct ScanProgress: Codable, Hashable, Sendable {
    /// 0…1 each.
    public var walls: Double
    public var floor: Double
    public var openings: Double
    public var objects: Double
    public var objectCount: Int
    public var elapsed: TimeInterval
    /// Enough of a room exists that "Done scanning" can be enabled.
    public var isReadyToFinish: Bool

    public init(
        walls: Double = 0, floor: Double = 0, openings: Double = 0,
        objects: Double = 0, objectCount: Int = 0, elapsed: TimeInterval = 0,
        isReadyToFinish: Bool = false
    ) {
        self.walls = walls
        self.floor = floor
        self.openings = openings
        self.objects = objects
        self.objectCount = objectCount
        self.elapsed = elapsed
        self.isReadyToFinish = isReadyToFinish
    }

    /// A single 0…1 number for the coverage bar's aggregate fill.
    public var overall: Double {
        min(1, max(0, walls * 0.40 + floor * 0.15 + openings * 0.15 + objects * 0.30))
    }

    /// The scan has run long enough that thermal throttling starts to degrade it
    /// (RoomPlan research §9.2: keep scans under ~5 minutes).
    public var isOverlong: Bool { elapsed > 270 }
}

// MARK: - Crops

/// One camera crop kept for a detected object, ready for the vision pipeline.
///
/// The geometry travels with the bytes because RoomPlan **regenerates every
/// identifier** when `RoomBuilder` produces the final room, so crops collected
/// during the live scan cannot be joined to the final objects by UUID. They are
/// re-keyed geometrically instead (`ScanCropIndex.rekey`).
public struct ScanCrop: Sendable {
    /// The live-scan RoomPlan identifier this crop was captured for.
    public var sourceIdentifier: UUID
    /// World-space centre of the object at capture time, metres.
    public var centre: SIMD3<Float>
    /// Full extents of the object at capture time, metres.
    public var extents: SIMD3<Float>
    /// JPEG bytes, EXIF-free (re-encoded from the pixel buffer, never forwarded).
    public var jpeg: Data
    /// The framing score that won this crop its slot, 0…1.
    public var score: Double

    public init(
        sourceIdentifier: UUID,
        centre: SIMD3<Float>,
        extents: SIMD3<Float>,
        jpeg: Data,
        score: Double
    ) {
        self.sourceIdentifier = sourceIdentifier
        self.centre = centre
        self.extents = extents
        self.jpeg = jpeg
        self.score = score
    }
}

// MARK: - Result

/// Everything one finished scan produces, in the app's own vocabulary. Nothing
/// downstream of the scanner sees a RoomPlan type.
public struct ScanResult: Sendable {
    public var room: ScannedRoom
    public var quality: ScanQualityReport
    /// JPEG crops keyed by `ScannedObject.id`.
    public var crops: [UUID: Data]
    /// `ScannedObject.id` → the RoomPlan identifier it came from, for joining
    /// against anything else collected during the same session.
    public var sourceIdentifiers: [UUID: UUID]
    public var elapsed: TimeInterval

    public init(
        room: ScannedRoom,
        quality: ScanQualityReport,
        crops: [UUID: Data] = [:],
        sourceIdentifiers: [UUID: UUID] = [:],
        elapsed: TimeInterval = 0
    ) {
        self.room = room
        self.quality = quality
        self.crops = crops
        self.sourceIdentifiers = sourceIdentifiers
        self.elapsed = elapsed
    }
}

/// What the converter produced, plus the bookkeeping the scanner needs.
public struct ConversionResult: Sendable {
    public var room: ScannedRoom
    public var quality: ScanQualityReport
    /// `ScannedObject.id` → RoomPlan identifier.
    public var sourceIdentifiers: [UUID: UUID]
    /// RoomPlan identifier → `ScannedObject.id`, the direction the crop
    /// re-keying needs.
    public var objectIDsBySource: [UUID: UUID]

    public init(
        room: ScannedRoom,
        quality: ScanQualityReport,
        sourceIdentifiers: [UUID: UUID] = [:],
        objectIDsBySource: [UUID: UUID] = [:]
    ) {
        self.room = room
        self.quality = quality
        self.sourceIdentifiers = sourceIdentifiers
        self.objectIDsBySource = objectIDsBySource
    }
}

// MARK: - Errors

/// Every way a scan can fail, with copy a person can act on. RoomPlan's own
/// errors carry no user-facing text, so this is where it lives.
public enum ScanError: Error, Hashable, Sendable {
    /// No LiDAR, or the Simulator.
    case deviceNotSupported
    case sceneTooLarge
    case trackingLost
    case deviceTooHot
    case invalidConfiguration
    /// `RoomBuilder` could not turn the raw scan into a room.
    case buildFailed(String)
    /// The scan produced nothing usable — no walls, no objects.
    case nothingCaptured
    case cancelled
    case unknown(String)

    public var title: String {
        switch self {
        case .deviceNotSupported: return "This iPhone can't scan"
        case .sceneTooLarge: return "This space is too large"
        case .trackingLost: return "We lost track of the room"
        case .deviceTooHot: return "Your iPhone needs to cool down"
        case .invalidConfiguration: return "Scanning couldn't start"
        case .buildFailed: return "We couldn't finish the room"
        case .nothingCaptured: return "Nothing was captured"
        case .cancelled: return "Scan cancelled"
        case .unknown: return "Something went wrong"
        }
    }

    public var message: String {
        switch self {
        case .deviceNotSupported:
            return "Scanning needs the LiDAR scanner, which is on iPhone 12 Pro and later Pro models. You can still explore a demo room."
        case .sceneTooLarge:
            return "Scan one room at a time — that's also where the results are most accurate."
        case .trackingLost:
            return "Start again from a corner and move slowly around the room."
        case .deviceTooHot:
            return "Give it a couple of minutes somewhere cool, then try again."
        case .invalidConfiguration:
            return "Close the app and open it again. If it keeps happening, restart your iPhone."
        case .buildFailed:
            return "The scan didn't have enough detail to build a room. Try again, moving slowly along every wall."
        case .nothingCaptured:
            return "We didn't see any walls or furniture. Point the camera at a wall and walk the room."
        case .cancelled:
            return "You stopped before the room was finished."
        case .unknown(let detail):
            return detail.isEmpty ? "Try scanning again." : detail
        }
    }

    /// Whether offering a demo room instead is the honest next step.
    public var suggestsDemoRoom: Bool {
        switch self {
        case .deviceNotSupported: return true
        default: return false
        }
    }
}

// MARK: - Events

/// The single stream every scanner emits. The rest of the app consumes this and
/// never learns whether a LiDAR sensor or a fixture produced it.
public enum ScanEvent: Sendable {
    /// The session is configured and the camera is live.
    case started
    /// Coaching copy changed. Emitted only on change, not per frame.
    case coaching(ScanCoaching)
    /// The live room, converted into our model. Partial, and cheap enough to
    /// render at RoomPlan's update rate.
    case geometry(ScannedRoom)
    /// A camera crop was kept for an object. `objectID` is the RoomPlan
    /// identifier of the *live* object; the final result re-keys it.
    case capturedFrame(objectID: UUID, jpeg: Data)
    case progress(ScanProgress)
    case finished(ScanResult)
    case failed(ScanError)

    /// True for the two terminal cases, after which the stream finishes.
    public var isTerminal: Bool {
        switch self {
        case .finished, .failed: return true
        default: return false
        }
    }
}

// MARK: - Deterministic identity

/// Derives our own stable identifiers from RoomPlan's.
///
/// RoomPlan's UUIDs are regenerated by `RoomBuilder` and are not stable across
/// scans, so they must never become our persistent keys. Deriving ours by hash
/// rather than minting random ones means converting the same scan twice produces
/// the same `ScannedRoom` — which is what makes conversion testable and saved
/// demo rooms survive relaunch.
enum ScanIdentity {
    static func derive(_ source: UUID, salt: String) -> UUID {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325            // FNV-1a offset basis
        func mix(_ bytes: [UInt8]) {
            for byte in bytes {
                hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
            }
        }
        let u = source.uuid
        mix([u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7,
             u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15])
        mix(Array(salt.utf8))
        var second = hash
        for byte in Array(salt.utf8).reversed() {
            second = (second ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        var bytes = [UInt8]()
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((hash >> UInt64(shift)) & 0xFF))
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((second >> UInt64(shift)) & 0xFF))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
