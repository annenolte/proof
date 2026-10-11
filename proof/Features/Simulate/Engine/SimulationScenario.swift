import Foundation
import simd

// MARK: - Which way is a yawed object facing?

extension Placement {

    /// The world basis a stored `yaw` denotes, as every writer in the app
    /// writes it:
    ///
    ///     local +X = ( cos yaw, 0, sin yaw )     // the object's width axis
    ///
    /// Every `yaw` on disk is written by `RoomFixtures` (`atan2(dz, dx)` of the
    /// object's facing vector) or by `CapturedRoomConverter` (which uses
    /// `Placement(transform:)` on RoomPlan's own matrix, recovering
    /// `atan2(m[0].z, m[0].x)`). Both mean the line above, and `Placement`'s own
    /// `transform` / `rotation` now agree with it — `Placement.transform` used
    /// to negate the sign, which drew every angled object mirrored and shoved it
    /// on the mirrored face.
    ///
    /// This stays as the stage's one stated definition of the convention rather
    /// than reaching for `Placement.rotation` directly, because it is the thing
    /// `SceneBuilder` and `BodySpec.weakAxisDirection` must not drift apart on.
    /// `IntegrationTests.testAYawedObjectFacesTheSameWayOnTheStageAsItWasMeasured`
    /// pins all four spellings — this one, the core round trip, the rendered
    /// entity and the excitation axis — to the same sign.
    var stageBasis: simd_float3x3 {
        let c = cos(yaw), s = sin(yaw)
        return simd_float3x3(
            SIMD3<Float>( c, 0, s),     // local +X, the object's width axis
            SIMD3<Float>( 0, 1, 0),     // local +Y, up
            SIMD3<Float>(-s, 0, c))     // local +Z, its depth axis
    }

    var stageRotation: simd_quatf { simd_quatf(stageBasis) }
}

/// Everything the 3D stage needs to know about one object, derived **once** from
/// the same `MassEstimator` / `FrictionDatabase` values the analytic solver used.
///
/// This is the single-scenario rule of SPEC §4.7.6 made concrete: there is no
/// second mass table and no second friction table anywhere in
/// `Features/Simulate/Engine`. `analyticBlock` is literally the
/// `RigidBlockSolver.Block` Track A integrates, carried along so a test can
/// assert the two tracks agree by construction rather than by inspection.
public struct BodySpec: Sendable, Equatable, Identifiable {

    // MARK: Identity

    public let id: UUID
    public let displayName: String
    public let type: ObjectType

    // MARK: Geometry

    /// Full extents in the object's local frame, metres (RoomPlan convention:
    /// x = width, y = height, z = depth).
    public let sizeM: SIMD3<Float>
    public let placement: Placement

    // MARK: Physics — the *only* place these numbers are written

    /// The mass of this body alone, kg. Stacked objects are separate bodies in
    /// the 3D scene, so the stage never double-counts them; `analyticBlock.mass`
    /// is the combined figure Track A uses for the tipping verdict.
    public let massKg: Double
    /// Centre-of-mass height above the object's own base, metres.
    public let comHeightM: Double
    public let staticFriction: Double
    public let kineticFriction: Double

    /// The friction to hand RealityKit, which is **not** the same number.
    ///
    /// Measured on device-class simulators (see `SimulationEngineTests`):
    /// RealityKit combines the two contacting materials' coefficients by
    /// **multiplication**. A block on μ = 0.35 resting on a floor also set to
    /// μ = 0.35 therefore behaves as μ = 0.1225 — which is below most tipping
    /// thresholds and silently converts every rocking object into a sliding
    /// one. The stage compensates: supporting surfaces are given a neutral
    /// μ = 1.0 and each body carries the analytic pair, so the product is the
    /// analytic pair exactly. For an object stacked on another object, the
    /// host's own coefficient is divided out here.
    public internal(set) var stageStaticFriction: Double
    public internal(set) var stageKineticFriction: Double

    /// Housner impact restitution, r = 1 − 1.5·sin²α.
    public let restitution: Double

    public let mounting: Mounting
    public let isAnchored: Bool
    public let supportHeightM: Double
    public let distanceToSupportEdgeM: Double
    public let hostID: UUID?

    /// The rigid block Track A integrated for this object, verbatim.
    public let analyticBlock: RigidBlockSolver.Block

    // MARK: Stage-only

    /// False for anchored, built-in and wall-mounted objects, which start
    /// kinematic and are released only when the analytic verdict says so.
    public let startsDynamic: Bool
    public let riskBand: RiskBand?

    public init(
        id: UUID,
        displayName: String,
        type: ObjectType,
        sizeM: SIMD3<Float>,
        placement: Placement,
        massKg: Double,
        comHeightM: Double,
        staticFriction: Double,
        kineticFriction: Double,
        restitution: Double,
        mounting: Mounting,
        isAnchored: Bool,
        supportHeightM: Double,
        distanceToSupportEdgeM: Double,
        hostID: UUID?,
        analyticBlock: RigidBlockSolver.Block,
        startsDynamic: Bool,
        riskBand: RiskBand?
    ) {
        self.id = id
        self.displayName = displayName
        self.type = type
        self.sizeM = sizeM
        self.placement = placement
        self.massKg = massKg
        self.comHeightM = comHeightM
        self.staticFriction = staticFriction
        self.kineticFriction = kineticFriction
        self.stageStaticFriction = staticFriction
        self.stageKineticFriction = kineticFriction
        self.restitution = restitution
        self.mounting = mounting
        self.isAnchored = isAnchored
        self.supportHeightM = supportHeightM
        self.distanceToSupportEdgeM = distanceToSupportEdgeM
        self.hostID = hostID
        self.analyticBlock = analyticBlock
        self.startsDynamic = startsDynamic
        self.riskBand = riskBand
    }

    // MARK: Derived

    /// Half of the smaller horizontal dimension — the axis the block tips about.
    public var halfWidthM: Double { analyticBlock.halfWidth }

    /// Critical tilt angle α, radians. Past this the object is going over.
    public var alphaRadians: Double { analyticBlock.alpha }

    /// Fraction of the object's own height at which its centre of mass sits.
    public var comHeightFraction: Double {
        min(max(comHeightM / max(Double(sizeM.y), 1e-4), 0.05), 0.95)
    }

    /// Exact diagonal inertia of a uniform box about its centre of mass, kg·m².
    /// A box collider gives RealityKit an exact contact manifold, so the only
    /// thing left to get right is the inertia tensor.
    public var inertiaKgM2: SIMD3<Float> {
        let m = Float(massKg)
        let s = sizeM
        let k = m / 12
        return SIMD3(
            k * (s.y * s.y + s.z * s.z),
            k * (s.x * s.x + s.z * s.z),
            k * (s.x * s.x + s.y * s.y)
        )
    }

    /// The offset of the centre of mass from the geometric centre, in the body's
    /// local frame. A loaded bookcase is not a uniform solid.
    public var centreOfMassOffset: SIMD3<Float> {
        SIMD3(0, sizeM.y * (Float(comHeightFraction) - 0.5), 0)
    }

    /// The horizontal direction, in world space, that this object tips most
    /// easily in: along its **smaller** footprint dimension.
    ///
    /// `Extents.governingHalfWidth` is `min(width, depth) / 2`, so the analytic
    /// solver always evaluates the block against its weakest axis. This is the
    /// same axis expressed as a world vector, so the stage can drive the body
    /// the way the solver drove the block.
    public var weakAxisDirection: SIMD3<Float> {
        let local: SIMD3<Float> = sizeM.x <= sizeM.z ? SIMD3(1, 0, 0) : SIMD3(0, 0, 1)
        // `stageBasis`, not `placement.transform` — see the note on `Placement`
        // above. The stage draws the body with `stageRotation`, so the axis the
        // earthquake pushes along has to be expressed in the same frame or the
        // shove lands on the wrong face of a yawed object.
        var world = placement.stageBasis * local
        world.y = 0
        let length = simd_length(world)
        return length > 1e-5 ? world / length : SIMD3(1, 0, 0)
    }

    /// The object's own overturning moment, m·g·b. Every corrective effort the
    /// reconciler is allowed to apply is a bounded fraction of this.
    public var overturningMomentNm: Double {
        massKg * Physics.g * halfWidthM
    }

    /// Moment of inertia about the pivoting bottom corner, I_O = (4/3)·m·R².
    public var pivotInertiaKgM2: Double {
        let r = analyticBlock.pivotRadius
        return (4.0 / 3.0) * massKg * r * r
    }
}

// MARK: - Timeline

/// One entry on the "what failed, and when" timeline the scrubber draws.
public struct FailureMarker: Sendable, Equatable, Identifiable {
    public var id: UUID { objectID }
    public let objectID: UUID
    public let displayName: String
    /// Seconds into the record, from the analytic solver.
    public let time: Double
    public let ending: DisplayContract.Ending
    public let band: RiskBand?

    public init(
        objectID: UUID, displayName: String, time: Double,
        ending: DisplayContract.Ending, band: RiskBand?
    ) {
        self.objectID = objectID
        self.displayName = displayName
        self.time = time
        self.ending = ending
        self.band = band
    }

    /// The one-line caption S-14 shows when this marker passes under the
    /// playhead.
    public var caption: String {
        String(format: "%@ %@ — %.1f s", displayName, ending.pastTense, time)
    }
}

// MARK: - Scenario

/// The complete, deterministic description of one simulated earthquake in one
/// room. Both tracks read this; nothing flows back from the 3D stage.
public struct SimulationScenario: Sendable {

    public let roomID: UUID
    public let roomName: String
    public let intensity: MercalliIntensity
    public let seed: UInt64
    public let floorSurface: FloorSurface

    /// The one accelerogram. Track A integrated it; Track B interpolates the
    /// same array.
    public let motion: GroundMotion

    /// Sorted by `id.uuidString` so solver island ordering is stable across
    /// runs (SPEC §4.8).
    public let bodies: [BodySpec]
    public let contracts: [UUID: DisplayContract]
    /// The unperturbed analytic outcome per object.
    public let outcomes: [UUID: RigidBlockSolver.Result]
    /// The ensemble verdict, when one was supplied.
    public let assessment: RoomAssessment?

    public var duration: Double { motion.duration }

    /// Failure markers in chronological order.
    public let failureTimeline: [FailureMarker]

    public func body(id: UUID) -> BodySpec? { bodies.first { $0.id == id } }
    public func contract(for id: UUID) -> DisplayContract? { contracts[id] }

    /// Peak floor acceleration in g — read from the accelerogram, never from the
    /// physics engine (SPEC §4.7.6 guarantee 5).
    public var peakAccelerationInG: Double { motion.pgaInG }

    /// Instantaneous horizontal acceleration in g at a simulation time.
    public func accelerationInG(at time: Double) -> Double {
        let a = motion.acceleration(at: time)
        return (a.x * a.x + a.z * a.z).squareRoot() / Physics.g
    }

    // MARK: Construction

    /// Builds the scenario from a room and its ensemble assessment.
    ///
    /// - Parameters:
    ///   - room: the scanned room.
    ///   - assessment: the ensemble verdict. Its `dominantBehaviour` decides
    ///     *what* happens to each object; it is authoritative.
    ///   - motion: the floor motion to display. Defaults to realisation 0 of the
    ///     same synthesiser the risk engine used, so the room is shaken by the
    ///     same earthquake the report describes.
    public static func build(
        room: ScannedRoom,
        assessment suppliedAssessment: RoomAssessment?,
        intensity: MercalliIntensity? = nil,
        seed: UInt64 = 0x1ED6E,
        motion suppliedMotion: GroundMotion? = nil
    ) -> SimulationScenario {
        // An assessment is looked up by object UUID, and object UUIDs are stable
        // across rooms in a library. Handing this an assessment of a *different*
        // room therefore does not fail loudly — it silently finds nothing for
        // most objects and, for any id that does collide, captions a body with
        // another room's verdict. The video and the report would then disagree,
        // which is the one failure this app cannot have. Drop it: an uncaptioned
        // but physically correct simulation is always better than a confidently
        // mislabelled one.
        //
        // The same argument applies to the *intensity*. A caller may override it
        // to preview another shake, and `DisplayContract.derive` takes the
        // ending from the ensemble verdict while the motion comes from the
        // displayed intensity — so an MMI IX assessment shown over an MMI V
        // shake contracts the stage to topple a bookcase that this record cannot
        // topple, and the reconciler's 35 % assist cap provably cannot bridge
        // the gap. The result is a half-hearted wobble captioned "toppled". Risk
        // bands are intensity-specific anyway: they are not a property of the
        // room that survives being shown against a different earthquake. So an
        // assessment from another intensity is dropped exactly like one from
        // another room, and the contracts fall back to the physics of the record
        // actually being displayed.
        let requestedIntensity = intensity
        let assessment = suppliedAssessment.flatMap { candidate -> RoomAssessment? in
            guard candidate.roomID == room.id else { return nil }
            guard requestedIntensity == nil || requestedIntensity == candidate.intensity
            else { return nil }
            return candidate
        }
        let resolvedIntensity = intensity ?? assessment?.intensity ?? .vii
        let resolvedSeed = assessment?.seed ?? seed
        let engine = RiskEngine()
        let motion = suppliedMotion ?? engine.floorMotion(
            for: room, intensity: resolvedIntensity, realisation: 0, seed: resolvedSeed)

        let solver = RigidBlockSolver()
        var bodies: [BodySpec] = []
        var contracts: [UUID: DisplayContract] = [:]
        var outcomes: [UUID: RigidBlockSolver.Result] = [:]

        // Deterministic insertion order (SPEC §4.8).
        let ordered = room.objects.sorted { $0.id.uuidString < $1.id.uuidString }

        for object in ordered {
            let stacked = MassEstimator.objectsStacked(on: object, in: room)
            let block = MassEstimator.block(for: object, in: room, stacked: stacked)
            let result = solver.solve(block: block, motion: motion)

            let risk = assessment?.risk(for: object.id)

            // Friction is read *off the block the solver integrated*, not
            // re-derived here. It used to be a second copy of
            // `MassEstimator.block`'s rule — same footing, same "on a shelf you
            // rub against the shelf, not the floor" threshold — which is exactly
            // the shape of divergence this app cannot afford: change the rule in
            // one place and the video and the verdict quietly stop agreeing.
            // One number, one origin.
            let startsDynamic = object.canMove
                && object.mounting != .wallMounted
                && object.mounting != .suspended

            let spec = BodySpec(
                id: object.id,
                displayName: object.type.displayName,
                type: object.type,
                sizeM: object.extents.simd,
                placement: object.placement,
                massKg: object.mass,
                comHeightM: object.centreOfMassHeight,
                staticFriction: block.staticFriction,
                kineticFriction: block.kineticFriction,
                restitution: block.restitution,
                mounting: object.mounting,
                isAnchored: object.isAnchored,
                supportHeightM: object.supportHeight,
                distanceToSupportEdgeM: block.distanceToSupportEdge,
                hostID: object.supportedBy,
                analyticBlock: block,
                startsDynamic: startsDynamic,
                riskBand: risk?.band
            )

            let contract = DisplayContract.derive(
                risk: risk,
                outcome: result,
                body: spec,
                onsetTime: onsetTime(for: block, in: motion),
                motionDuration: motion.duration
            )

            bodies.append(spec)
            outcomes[object.id] = result
            contracts[object.id] = contract
        }

        // RealityKit multiplies contact friction, so a body resting on another
        // body would see the product of the two. Divide the host's coefficient
        // out, so the contact the engine actually solves is the analytic pair.
        let byID = Dictionary(uniqueKeysWithValues: bodies.map { ($0.id, $0) })
        for index in bodies.indices {
            guard let hostID = bodies[index].hostID, let host = byID[hostID] else { continue }
            bodies[index].stageStaticFriction = clampFriction(
                bodies[index].staticFriction / max(host.staticFriction, 0.05))
            bodies[index].stageKineticFriction = clampFriction(
                bodies[index].kineticFriction / max(host.kineticFriction, 0.05))
        }

        let timeline: [FailureMarker] = bodies.compactMap { spec in
            guard let contract = contracts[spec.id],
                  contract.ending.isFailure,
                  let time = contract.expectedFailureTimeS
            else { return nil }
            return FailureMarker(
                objectID: spec.id, displayName: spec.displayName,
                time: time, ending: contract.ending, band: spec.riskBand)
        }.sorted { $0.time < $1.time }

        return SimulationScenario(
            roomID: room.id,
            roomName: room.name,
            intensity: resolvedIntensity,
            seed: resolvedSeed,
            floorSurface: room.building.floorSurface,
            motion: motion,
            bodies: bodies,
            contracts: contracts,
            outcomes: outcomes,
            assessment: assessment,
            failureTimeline: timeline
        )
    }

    /// RealityKit accepts a wide range but behaves poorly outside this one.
    static func clampFriction(_ value: Double) -> Double {
        min(max(value, 0.01), 3.0)
    }

    /// The first instant the record exceeds the object's own movement threshold.
    ///
    /// This is a property of the analytic block and the shared accelerogram —
    /// not of the 3D engine — so it is a legitimate stand-in for `t*` when the
    /// unperturbed realisation happens not to fail but the ensemble says the
    /// object does.
    static func onsetTime(for block: RigidBlockSolver.Block, in motion: GroundMotion) -> Double {
        let threshold = min(block.rockingThresholdInG, block.slidingThresholdInG) * Physics.g
        for index in 0..<motion.sampleCount
        where motion.horizontalMagnitude(at: index) > threshold {
            return Double(index) * motion.dt
        }
        // Never exceeded: fall back to the strongest instant in the record.
        var peakIndex = 0
        var peak = 0.0
        for index in 0..<motion.sampleCount {
            let value = motion.horizontalMagnitude(at: index)
            if value > peak { peak = value; peakIndex = index }
        }
        return Double(peakIndex) * motion.dt
    }
}
