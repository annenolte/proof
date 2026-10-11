import Foundation
import simd

#if canImport(RoomPlan)
import RoomPlan
#endif

/// Turns a RoomPlan scan into a `ScannedRoom`.
///
/// This is the highest-risk correctness code in the app: every downstream number
/// — mass, slenderness, rocking threshold, strike zone, risk band — is computed
/// from geometry that starts here. The conventions it has to get right, all
/// verified in `docs/research/api-roomplan.md`:
///
/// * **Transforms are centred.** `transform.columns.3` is the bounding-box
///   centroid, not a corner and not the base. Off-by-half-height is the classic
///   RoomPlan bug and it would silently double every object's centre-of-mass
///   height.
/// * **`dimensions` are full extents**, not half-extents, in the element's local
///   frame: `x = width, y = height, z = depth`.
/// * **Walls are zero-thickness planes** — `dimensions.z ≈ 0`. RoomPlan never
///   measures wall thickness, so we substitute a documented nominal value rather
///   than pretend the zero is a measurement.
/// * **Floors use a rotated local frame** where local +Z is the vertical normal,
///   so their `dimensions.y` is a *horizontal* extent and must not be read as a
///   height.
/// * **The world origin is the device pose at session start**, so the floor sits
///   at negative Y, typically −1.2 to −1.6 m. Everything is rebased so the floor
///   plane is exactly `y = 0`, which is the convention `RoomFixtures` and the
///   solver already use.
/// * **`parentIdentifier` means "associated with", not "on top of"** — a chair
///   points at its table while standing beside it. Support is therefore
///   confirmed geometrically before it is recorded.
public enum CapturedRoomConverter {

    // MARK: - Options

    public struct Options: Sendable {
        /// Objects RoomPlan rated below this are dropped. `.low` scores 0.3 and
        /// `.medium` scores 0.7, so the default keeps medium and drops low.
        ///
        /// A spurious object is worse than a missing one here: it gets a mass, a
        /// risk band and a place in the ranked list, and it teaches the user the
        /// app is guessing. Surfaces are *not* dropped by confidence — a missing
        /// wall corrupts the room outline, which is worse than a shaky one.
        public var minimumObjectConfidence: Double
        /// Objects with any dimension below this are noise or fragments of a
        /// larger object; they are also below RealityKit's contact margin.
        public var minimumObjectDimension: Float
        /// Nominal thickness given to zero-thickness planes so downstream
        /// geometry has a solid to work with. Matches `RoomFixtures`.
        public var nominalSurfaceThickness: Float
        /// An object whose base is within this of the floor is floor-standing.
        public var floorContactTolerance: Double
        /// Vertical tolerance when confirming that one object rests on another.
        public var supportContactTolerance: Double
        /// Move the room so its floor plane is `y = 0` and its footprint is
        /// centred on the origin. Off only in tests that assert raw geometry.
        public var recentre: Bool

        public init(
            minimumObjectConfidence: Double = 0.5,
            minimumObjectDimension: Float = 0.02,
            nominalSurfaceThickness: Float = 0.01,
            floorContactTolerance: Double = 0.05,
            supportContactTolerance: Double = 0.15,
            recentre: Bool = true
        ) {
            self.minimumObjectConfidence = minimumObjectConfidence
            self.minimumObjectDimension = minimumObjectDimension
            self.nominalSurfaceThickness = nominalSurfaceThickness
            self.floorContactTolerance = floorContactTolerance
            self.supportContactTolerance = supportContactTolerance
            self.recentre = recentre
        }

        public static let `default` = Options()
        /// Keeps world coordinates exactly as RoomPlan reported them.
        public static let verbatim = Options(recentre: false)
    }

    // MARK: - Entry point

    /// Converts a RoomPlan-shaped scan into a `ScannedRoom`.
    public static func convert(
        _ raw: RawCapturedRoom,
        name: String,
        kind: RoomKind = .other,
        building: BuildingContext = BuildingContext(),
        createdAt: Date = Date(),
        options: Options = .default
    ) -> ConversionResult {

        let origin = self.origin(of: raw, options: options)

        // --- Surfaces -------------------------------------------------------
        var surfaces: [RoomSurface] = []
        surfaces.reserveCapacity(raw.allSurfaces.count)
        for element in raw.allSurfaces {
            surfaces.append(surface(from: element, origin: origin, options: options))
        }

        // --- Objects --------------------------------------------------------
        var draft: [DraftObject] = []
        var dropped = 0
        for element in raw.objects {
            if let d = draftObject(from: element, origin: origin, options: options) {
                draft.append(d)
            } else {
                dropped += 1
            }
        }

        let objects = resolveSupport(draft, options: options)

        var sourceIdentifiers: [UUID: UUID] = [:]
        var objectIDsBySource: [UUID: UUID] = [:]
        for d in draft {
            sourceIdentifiers[d.id] = d.sourceIdentifier
            objectIDsBySource[d.sourceIdentifier] = d.id
        }

        let room = ScannedRoom(
            id: ScanIdentity.derive(raw.identifier, salt: "room"),
            name: name,
            kind: kind,
            building: building,
            surfaces: surfaces,
            objects: objects,
            createdAt: createdAt,
            updatedAt: createdAt
        )

        let quality = self.quality(of: raw, room: room, droppedObjects: dropped, origin: origin)

        return ConversionResult(
            room: room,
            quality: quality,
            sourceIdentifiers: sourceIdentifiers,
            objectIDsBySource: objectIDsBySource
        )
    }

    // MARK: - Rebasing

    /// The translation applied to every element so the room lands in our frame:
    /// floor plane at `y = 0`, footprint centred on the origin.
    struct Origin {
        var floorY: Float
        var centreX: Float
        var centreZ: Float

        func apply(_ p: SIMD3<Float>) -> SIMD3<Float> {
            SIMD3(p.x - centreX, p.y - floorY, p.z - centreZ)
        }

        static let identity = Origin(floorY: 0, centreX: 0, centreZ: 0)
    }

    static func origin(of raw: RawCapturedRoom, options: Options) -> Origin {
        guard options.recentre else { return .identity }

        // Prefer the real floor plane; fall back to the bottom of the lowest
        // wall, which is what RoomPlan's own sample code does when floors are
        // missing (they are iOS 17+ and occasionally absent on a short scan).
        let floorY: Float
        if let floor = raw.floors.first {
            floorY = floor.transform.columns.3.y
        } else if let lowestWall = raw.walls.map({ $0.transform.columns.3.y - $0.dimensions.y / 2 }).min() {
            floorY = lowestWall
        } else if let lowestObject = raw.objects.map({ $0.transform.columns.3.y - $0.dimensions.y / 2 }).min() {
            floorY = lowestObject
        } else {
            floorY = 0
        }

        // Horizontal centre from the walls' extremes, which bound the room; the
        // floor bbox alone is unreliable on a partial scan.
        var minX = Float.greatestFiniteMagnitude, maxX = -Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude, maxZ = -Float.greatestFiniteMagnitude
        var sawAny = false
        for wall in raw.walls {
            let c = RawScanGeometry.centre(of: wall.transform)
            let half = wall.dimensions.x / 2
            let dir = SIMD2<Float>(wall.transform.columns.0.x, wall.transform.columns.0.z)
            let a = SIMD2(c.x, c.z) - dir * half
            let b = SIMD2(c.x, c.z) + dir * half
            minX = min(minX, a.x, b.x); maxX = max(maxX, a.x, b.x)
            minZ = min(minZ, a.y, b.y); maxZ = max(maxZ, a.y, b.y)
            sawAny = true
        }
        if !sawAny {
            for object in raw.objects {
                let c = RawScanGeometry.centre(of: object.transform)
                minX = min(minX, c.x); maxX = max(maxX, c.x)
                minZ = min(minZ, c.z); maxZ = max(maxZ, c.z)
                sawAny = true
            }
        }
        guard sawAny else { return Origin(floorY: floorY, centreX: 0, centreZ: 0) }
        return Origin(floorY: floorY, centreX: (minX + maxX) / 2, centreZ: (minZ + maxZ) / 2)
    }

    // MARK: - Surfaces

    static func surface(
        from raw: RawSurface, origin: Origin, options: Options
    ) -> RoomSurface {
        let centre = origin.apply(RawScanGeometry.centre(of: raw.transform))
        let yaw = RawScanGeometry.yaw(of: raw.transform)
        let t = options.nominalSurfaceThickness

        let extents: Extents
        switch raw.kind {
        case .floor, .ceiling:
            // The floor's local frame is rotated: +Z is the vertical normal, so
            // `dimensions.y` is a horizontal extent, not a height. Reading it as
            // a height would give a floor two metres thick.
            extents = Extents(
                width: max(raw.dimensions.x, t),
                height: t,
                depth: max(raw.dimensions.y, t)
            )
        case .wall, .door, .window, .opening:
            // Vertical planes: x = width, y = height, z ≈ 0. RoomPlan does not
            // measure wall thickness; the nominal value is ours, not a reading.
            extents = Extents(
                width: max(raw.dimensions.x, t),
                height: max(raw.dimensions.y, t),
                depth: max(raw.dimensions.z, t)
            )
        }

        return RoomSurface(
            id: ScanIdentity.derive(raw.identifier, salt: "surface"),
            kind: raw.kind,
            placement: Placement(centre: centre, yaw: yaw),
            extents: extents,
            isOpen: raw.isOpen,
            confidence: raw.confidence.score
        )
    }

    // MARK: - Objects

    struct DraftObject {
        var id: UUID
        var sourceIdentifier: UUID
        var parentIdentifier: UUID?
        var type: ObjectType
        var placement: Placement
        var extents: Extents
        var provenance: IdentificationProvenance
        var baseHeight: Double        // above the floor plane, metres
        var mounting: Mounting
    }

    static func draftObject(
        from raw: RawObject, origin: Origin, options: Options
    ) -> DraftObject? {
        guard raw.confidence.score >= options.minimumObjectConfidence else { return nil }
        let d = raw.dimensions
        guard d.x >= options.minimumObjectDimension,
              d.y >= options.minimumObjectDimension,
              d.z >= options.minimumObjectDimension,
              d.x.isFinite, d.y.isFinite, d.z.isFinite else { return nil }

        let centre = origin.apply(RawScanGeometry.centre(of: raw.transform))
        guard centre.x.isFinite, centre.y.isFinite, centre.z.isFinite else { return nil }

        let extents = Extents(d)
        // Centred transform → the base is half a height below the centroid.
        let baseHeight = Double(centre.y) - Double(extents.height) / 2

        let type = classify(
            category: raw.category, extents: extents, baseHeight: baseHeight)
        let mounting = type.defaultMounting

        return DraftObject(
            id: ScanIdentity.derive(raw.identifier, salt: "object"),
            sourceIdentifier: raw.identifier,
            parentIdentifier: raw.parentIdentifier,
            type: type,
            placement: Placement(centre: centre, yaw: RawScanGeometry.yaw(of: raw.transform)),
            extents: extents,
            provenance: IdentificationProvenance(
                source: .scanner,
                confidence: raw.confidence.score,
                scannerCategory: raw.category
            ),
            baseHeight: baseHeight,
            mounting: mounting
        )
    }

    /// Second pass: work out what each object stands on, then build the model
    /// objects. Needs every draft in hand, so it cannot be folded into the first
    /// pass.
    static func resolveSupport(_ draft: [DraftObject], options: Options) -> [ScannedObject] {
        var bySource: [UUID: DraftObject] = [:]
        for d in draft { bySource[d.sourceIdentifier] = d }

        // Host links are resolved from the *measured* geometry, because that is
        // the geometry the contact actually happened in.
        var hostOfDraft: [UUID: DraftObject] = [:]
        for object in draft {
            guard object.mounting != .wallMounted, object.mounting != .suspended else { continue }
            guard object.baseHeight > options.floorContactTolerance else { continue }
            if let host = supportHost(for: object, among: draft, bySource: bySource, options: options) {
                hostOfDraft[object.id] = host
            }
        }

        // Support heights are then resolved **bottom-up**, so a host that gets
        // snapped down to the floor carries whatever stands on it down too.
        //
        // Resolving each object independently against the host's *measured* top
        // is the bug this replaces. A dresser whose scanned base sits at 0.03 m
        // is inside `floorContactTolerance`, so it snaps to `supportHeight = 0`
        // and its centroid is re-seated 3 cm lower — but the television on it
        // would still take `hostTop` from the un-snapped draft and end up 3 cm
        // above a dresser that is no longer there. The report would then say the
        // television rests on the dresser while the stage drops it on the first
        // frame, and `MassEstimator.objectsStacked`, which links the pair with a
        // 0.12 m window on the *persisted* room, would eventually stop seeing a
        // stack at all — silently splitting a combined block into two.
        var resolvedSupport: [UUID: Double] = [:]
        var resolving: Set<UUID> = []

        func supportHeight(of object: DraftObject) -> Double {
            if let cached = resolvedSupport[object.id] { return cached }
            // A cycle cannot arise from a strict height ordering, but scan noise
            // plus a tolerance is not a strict ordering; refuse to recurse.
            guard !resolving.contains(object.id) else { return object.baseHeight }
            resolving.insert(object.id)
            defer { resolving.remove(object.id) }

            let value: Double
            if object.mounting == .wallMounted || object.mounting == .suspended {
                // Nothing holds these up from below. `RoomFixtures` records the
                // *centre* height for them, so match that convention exactly or
                // every wall-mounted object in the app is half a height out.
                value = Double(object.placement.centre.y)
            } else if object.baseHeight <= options.floorContactTolerance {
                value = 0
            } else if let host = hostOfDraft[object.id] {
                // Snap to the host's *resolved* top so a centimetre of scan
                // noise does not leave the object floating or embedded.
                value = supportHeight(of: host) + Double(host.extents.height)
            } else {
                value = object.baseHeight
            }
            resolvedSupport[object.id] = value
            return value
        }

        return draft.map { object -> ScannedObject in
            let isHungFromAbove = object.mounting == .wallMounted || object.mounting == .suspended
            let supportHeight = supportHeight(of: object)
            let supportedBy = hostOfDraft[object.id]?.id

            // Re-seat the centroid on the support we just resolved.
            //
            // `supportHeight` and `placement.centre` are two independent facts
            // about the same object, and two different halves of the app read
            // them: the analytic solver and the risk engine work from
            // `supportHeight` and `topHeight`, while `SceneBuilder` positions
            // the RealityKit body from `placement.centre`. Every branch above
            // moves `supportHeight` — snapping a near-floor object to zero, or a
            // stacked object to its host's top — without moving the centroid,
            // so leaving the centroid as measured lets the two drift apart by
            // the snap distance. That is how you get an object standing on the
            // floor in the report and floating (or sunk, and then popped out by
            // the contact solver on the first frame) in the video.
            //
            // `RoomFixtures.object(...)` derives the centroid from the support
            // in exactly this way, so this is not a new convention — it is the
            // convention the frozen core already ships, applied to the scan path.
            //
            // Only under `recentre`. `Options.verbatim` exists to hand back
            // RoomPlan's own world coordinates for inspection, where the floor
            // is at y ≈ −1.4 and `supportHeight` — defined as a height *above
            // the floor* — is not a position in that frame at all. Re-seating
            // there would teleport the room to the origin, which is exactly what
            // verbatim promises not to do.
            var placement = object.placement
            if !isHungFromAbove && options.recentre {
                placement.centre.y = Float(supportHeight) + object.extents.height / 2
            }

            return ScannedObject(
                id: object.id,
                type: object.type,
                placement: placement,
                extents: object.extents,
                provenance: object.provenance,
                mass: MassEstimator.mass(type: object.type, extents: object.extents),
                loading: .partial,
                mounting: object.mounting,
                supportHeight: supportHeight,
                supportedBy: supportedBy
            )
        }
    }

    static func hostTop(_ host: DraftObject) -> Double {
        Double(host.placement.centre.y) + Double(host.extents.height) / 2
    }

    /// Whichever object this one is genuinely resting on, or nil.
    ///
    /// RoomPlan's `parentIdentifier` is a semantic association, not a support
    /// relation — it links a chair to its table and a dishwasher to its cabinet
    /// run. Treating it as "on top of" would put a dining chair on a table top
    /// and hand the solver a 0.75 m fall height that does not exist. So the
    /// hint is checked geometrically, and when it fails we look for a real host.
    static func supportHost(
        for object: DraftObject,
        among draft: [DraftObject],
        bySource: [UUID: DraftObject],
        options: Options
    ) -> DraftObject? {
        func rests(on host: DraftObject) -> Bool {
            guard host.id != object.id else { return false }
            guard host.mounting != .suspended else { return false }
            guard abs(hostTop(host) - object.baseHeight) <= options.supportContactTolerance
            else { return false }
            // Horizontally inside the host's footprint, with a little slack for
            // an object that overhangs its shelf. The offset is rotated into the
            // host's own frame first — a dresser turned side-on to the room is
            // 1.4 m deep in world Z and 0.5 m wide in world X, and comparing
            // against its unrotated extents would reject its own television.
            let d = SIMD2<Float>(
                object.placement.centre.x - host.placement.centre.x,
                object.placement.centre.z - host.placement.centre.z)
            let c = cos(host.placement.yaw), s = sin(host.placement.yaw)
            let localX = abs(d.x * c + d.y * s)
            let localZ = abs(-d.x * s + d.y * c)
            let halfW = host.extents.width / 2 + object.extents.width / 4
            let halfD = host.extents.depth / 2 + object.extents.depth / 4
            return localX <= halfW && localZ <= halfD
        }

        if let parentID = object.parentIdentifier,
           let parent = bySource[parentID],
           rests(on: parent) {
            return parent
        }
        // Fall back to the largest plausible host — the largest, because a vase
        // on a nightstand beside a bed should choose the nightstand it sits on,
        // not a passing overlap.
        return draft
            .filter(rests)
            .max { $0.extents.volume < $1.extents.volume }
    }

    // MARK: - Category refinement

    /// Picks the most plausible `ObjectType` for a RoomPlan category and a
    /// measured box.
    ///
    /// RoomPlan reports sixteen coarse categories and calls a bookcase, a
    /// wardrobe and a dresser all "storage" — yet a dresser is the single
    /// most-reported tip-over fatality object and a wardrobe behaves completely
    /// differently. The vision and language passes refine this later; until they
    /// do, dimensions alone carry real information, and this ladder uses it.
    ///
    /// Every branch stays inside `ObjectType.candidates(forRoomPlanCategory:)`,
    /// so no amount of bad geometry can turn a sofa into a wardrobe.
    public static func classify(
        category: String, extents: Extents, baseHeight: Double
    ) -> ObjectType {
        let candidates = ObjectType.candidates(forRoomPlanCategory: category)
        guard candidates.count > 1 else { return candidates.first ?? .unknown }

        let h = Double(extents.height)
        let w = Double(extents.width)
        let depth = Double(extents.depth)
        let footprint = w * depth
        let shallowest = min(w, depth)

        let chosen: ObjectType
        switch category {
        case "storage":
            if baseHeight > 1.2 {
                chosen = .kitchenCabinetUpper          // hung above a worktop
            } else if h < 0.45 {
                chosen = .storageBin
            } else if h < 0.72 && w < 0.65 {
                chosen = .nightstand
            } else if h < 1.0 {
                chosen = shallowest < 0.40 ? .bookshelfShort : .dresser
            } else if h < 1.55 {
                chosen = shallowest < 0.40 ? .bookshelfShort : .highboy
            } else {
                chosen = shallowest < 0.45 ? .bookshelfTall : .wardrobe
            }

        case "table":
            if h < 0.55 {
                chosen = .coffeeTable
            } else if h < 0.80 && w < 0.70 && depth < 0.60 {
                chosen = .nightstand
            } else if footprint >= 1.4 {
                chosen = .diningTable
            } else {
                chosen = .desk
            }

        case "chair":
            if w >= 0.75 && depth >= 0.75 {
                chosen = .armchair
            } else {
                chosen = .diningChair
            }

        case "sofa":
            chosen = w >= 1.45 ? .sofa : .armchair

        case "bed":
            // A cot is short and narrow; a single bed is not.
            chosen = (max(w, depth) <= 1.45 && shallowest <= 0.95) ? .crib : .bed

        case "television":
            if baseHeight > 0.4 && depth < 0.12 {
                chosen = .televisionWallMounted
            } else if w < 0.70 {
                chosen = .computerMonitor
            } else {
                chosen = .television
            }

        case "oven":
            // A free-standing cooker is tall; a built-in oven sits in a run.
            chosen = h > 0.75 ? .rangeElectric : .oven

        default:
            chosen = candidates[0]
        }

        // Never leave the sanctioned list, whatever the ladder concluded.
        return candidates.contains(chosen) ? chosen : (candidates.first ?? .unknown)
    }

    // MARK: - Quality

    static func quality(
        of raw: RawCapturedRoom, room: ScannedRoom, droppedObjects: Int, origin: Origin
    ) -> ScanQualityReport {
        let walls = raw.walls
        let elements = raw.allSurfaces.map(\.confidence) + raw.objects.map(\.confidence)
        let total = max(elements.count, 1)
        let high = Double(elements.filter { $0 == .high }.count) / Double(total)
        let low = Double(elements.filter { $0 == .low }.count) / Double(total)
        let complete = walls.isEmpty
            ? 0
            : Double(walls.filter { $0.completedEdgeCount >= 4 }.count) / Double(walls.count)

        let area = floorArea(of: raw, room: room)

        var issues: [ScanQualityReport.Issue] = []
        if walls.count < 3 || raw.floors.isEmpty || area < 4 || area > 120 {
            issues.append(.roomShape)
        }
        if complete < 0.8 { issues.append(.wallCompleteness) }
        if high < 0.7 || low > 0.3 { issues.append(.confidence) }
        if room.objects.isEmpty { issues.append(.noObjects) }

        return ScanQualityReport(
            wallCount: walls.count,
            floorCount: raw.floors.count,
            openingCount: raw.doors.count + raw.windows.count + raw.openings.count,
            objectCount: room.objects.count,
            droppedObjectCount: droppedObjects,
            completeWallFraction: complete,
            highConfidenceFraction: high,
            lowConfidenceFraction: low,
            floorArea: area,
            issues: issues
        )
    }

    /// Floor area in m². Uses the real polygon when RoomPlan gave one, because
    /// `dimensions` on a floor is only its bounding box and an L-shaped room's
    /// bbox overstates it badly.
    static func floorArea(of raw: RawCapturedRoom, room: ScannedRoom) -> Double {
        if let floor = raw.floors.first, floor.polygonCorners.count >= 3 {
            let pts = floor.polygonCorners.map { local -> SIMD2<Double> in
                let w = RawScanGeometry.world(local, in: floor.transform)
                return SIMD2(Double(w.x), Double(w.z))
            }
            var twice = 0.0
            for i in 0..<pts.count {
                let a = pts[i], b = pts[(i + 1) % pts.count]
                twice += a.x * b.y - b.x * a.y
            }
            let area = abs(twice) / 2
            if area > 0.5 { return area }
        }
        if let floor = raw.floors.first {
            return Double(floor.dimensions.x) * Double(floor.dimensions.y)
        }
        return room.floorArea
    }
}

// MARK: - The RoomPlan bridge
//
// Deliberately thin: nothing here does arithmetic. Everything that could be
// wrong lives above, where it can be tested without LiDAR.

#if canImport(RoomPlan)
extension CapturedRoomConverter {

    /// Copies a real `CapturedRoom` into the constructible mirror.
    public static func raw(from room: CapturedRoom) -> RawCapturedRoom {
        RawCapturedRoom(
            identifier: room.identifier,
            walls: room.walls.map { rawSurface($0) },
            doors: room.doors.map { rawSurface($0) },
            windows: room.windows.map { rawSurface($0) },
            openings: room.openings.map { rawSurface($0) },
            floors: room.floors.map { rawSurface($0) },
            objects: room.objects.map { rawObject($0) }
        )
    }

    /// Converts a real `CapturedRoom` straight through to a `ScannedRoom`.
    public static func convert(
        _ room: CapturedRoom,
        name: String,
        kind: RoomKind = .other,
        building: BuildingContext = BuildingContext(),
        createdAt: Date = Date(),
        options: Options = .default
    ) -> ConversionResult {
        convert(raw(from: room), name: name, kind: kind, building: building,
                createdAt: createdAt, options: options)
    }

    static func rawSurface(_ s: CapturedRoom.Surface) -> RawSurface {
        var kind: RoomSurface.Kind = .wall
        var isOpen = false
        switch s.category {
        case .wall: kind = .wall
        case .opening: kind = .opening
        case .window: kind = .window
        case .door(let open): kind = .door; isOpen = open
        case .floor: kind = .floor
        @unknown default: kind = .wall
        }
        return RawSurface(
            identifier: s.identifier,
            kind: kind,
            isOpen: isOpen,
            confidence: rawConfidence(s.confidence),
            transform: s.transform,
            dimensions: s.dimensions,
            parentIdentifier: s.parentIdentifier,
            completedEdgeCount: s.completedEdges.count,
            polygonCorners: s.polygonCorners
        )
    }

    static func rawObject(_ o: CapturedRoom.Object) -> RawObject {
        RawObject(
            identifier: o.identifier,
            category: roomPlanCategoryName(o.category),
            confidence: rawConfidence(o.confidence),
            transform: o.transform,
            dimensions: o.dimensions,
            parentIdentifier: o.parentIdentifier
        )
    }

    static func rawConfidence(_ c: CapturedRoom.Confidence) -> RawConfidence {
        switch c {
        case .high: return .high
        case .medium: return .medium
        case .low: return .low
        // Every RoomPlan enum is non-frozen (library evolution is on), so this
        // is mandatory, not defensive style. An unrecognised confidence is
        // treated as the worst case.
        @unknown default: return .low
        }
    }

    /// The exact strings `ObjectType.candidates(forRoomPlanCategory:)` keys on.
    /// Spelled out rather than derived from `String(describing:)` so a change in
    /// Swift's reflection output cannot silently turn every object into
    /// `.unknown`.
    static func roomPlanCategoryName(_ category: CapturedRoom.Object.Category) -> String {
        switch category {
        case .storage: return "storage"
        case .refrigerator: return "refrigerator"
        case .stove: return "stove"
        case .bed: return "bed"
        case .sink: return "sink"
        case .washerDryer: return "washerDryer"
        case .toilet: return "toilet"
        case .bathtub: return "bathtub"
        case .oven: return "oven"
        case .dishwasher: return "dishwasher"
        case .table: return "table"
        case .sofa: return "sofa"
        case .chair: return "chair"
        case .fireplace: return "fireplace"
        case .television: return "television"
        case .stairs: return "stairs"
        @unknown default: return "unknown"
        }
    }
}
#endif
