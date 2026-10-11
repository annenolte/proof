import Foundation
import simd

/// The four bands the app reports. The band is the headline; the number is
/// secondary, because the underlying uncertainty (±25% on friction, ±30% on
/// mass) does not justify presenting a score to the unit.
public enum RiskBand: String, Codable, CaseIterable, Sendable, Comparable, Identifiable {
    case low, moderate, high, severe

    public var id: String { rawValue }

    public static func < (a: RiskBand, b: RiskBand) -> Bool {
        a.order < b.order
    }

    var order: Int {
        switch self {
        case .low: return 0
        case .moderate: return 1
        case .high: return 2
        case .severe: return 3
        }
    }

    public init(score: Double) {
        switch score {
        case ..<25: self = .low
        case ..<50: self = .moderate
        case ..<75: self = .high
        default: self = .severe
        }
    }

    public var displayName: String {
        switch self {
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .high: return "High"
        case .severe: return "Severe"
        }
    }

    /// What the user should actually do.
    public var action: String {
        switch self {
        case .low: return "No action needed"
        case .moderate: return "Worth securing"
        case .high: return "Anchor this"
        case .severe: return "Anchor this first"
        }
    }

    public var detail: String {
        switch self {
        case .low:
            return "This should stay put. Nothing to do here."
        case .moderate:
            return "This will move, and its contents may come out. Cheap fixes make a real difference."
        case .high:
            return "This is likely to fall, and likely to hurt someone or block your way out."
        case .severe:
            return "This is a life-safety item. Secure it before you sleep in this room again."
        }
    }

    public var symbolName: String {
        switch self {
        case .low: return "checkmark.circle.fill"
        case .moderate: return "exclamationmark.circle.fill"
        case .high: return "exclamationmark.triangle.fill"
        case .severe: return "exclamationmark.octagon.fill"
        }
    }
}

/// The consequence factors, kept as a named breakdown rather than a single
/// number so the app can show the user exactly why something scored what it
/// scored. Publishing the reasoning is a deliberate design commitment: a safety
/// tool that says "trust me, it's a 90" is not usable advice.
public struct ConsequenceBreakdown: Codable, Hashable, Sendable {
    public var impactEnergy: Double      // f₁, weight 0.28
    public var occupantExposure: Double  // f₂, weight 0.22
    public var fallHeight: Double        // f₃, weight 0.14
    public var egressBlockage: Double    // f₄, weight 0.12
    public var breakage: Double          // f₅, weight 0.10
    public var mass: Double              // f₆, weight 0.08
    public var secondaryHazard: Double   // f₇, weight 0.06

    public static let weights = (
        impactEnergy: 0.28, occupantExposure: 0.22, fallHeight: 0.14,
        egressBlockage: 0.12, breakage: 0.10, mass: 0.08, secondaryHazard: 0.06
    )

    public var total: Double {
        let w = Self.weights
        let sum = impactEnergy * w.impactEnergy
            + occupantExposure * w.occupantExposure
            + fallHeight * w.fallHeight
            + egressBlockage * w.egressBlockage
            + breakage * w.breakage
            + mass * w.mass
            + secondaryHazard * w.secondaryHazard
        return min(max(sum, 0), 1)
    }

    /// The factors in descending order of contribution, for the "why" list.
    public var rankedContributions: [(label: String, contribution: Double)] {
        let w = Self.weights
        return [
            ("Impact energy", impactEnergy * w.impactEnergy),
            ("Who's in the way", occupantExposure * w.occupantExposure),
            ("How far it falls", fallHeight * w.fallHeight),
            ("Blocks your way out", egressBlockage * w.egressBlockage),
            ("Broken glass", breakage * w.breakage),
            ("Sheer weight", mass * w.mass),
            ("Fire or flood risk", secondaryHazard * w.secondaryHazard),
        ].filter { $0.contribution > 0.001 }.sorted { $0.contribution > $1.contribution }
    }
}

/// The full verdict for one object.
public struct ObjectRisk: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID { objectID }
    public var objectID: UUID

    /// 0…100.
    public var score: Double
    public var band: RiskBand

    /// Probability of failure, from the ensemble.
    public var likelihood: Double
    public var consequence: ConsequenceBreakdown

    /// The behaviour seen in the majority of ensemble runs.
    public var dominantBehaviour: RigidBlockSolver.Behaviour
    /// Fraction of runs that ended in each behaviour.
    public var behaviourDistribution: [String: Double]

    /// Peak rotation as a fraction of the toppling angle, averaged over runs
    /// that did not topple. Lets the UI say "it came within 20% of going over".
    public var closenessToToppling: Double
    /// Median net sliding displacement, metres.
    public var slidingDisplacement: Double
    /// Median impact energy when it fell, joules.
    public var impactEnergy: Double
    /// The ground acceleration in g at which this object first starts to move,
    /// and how that compares to the shaking it was tested against.
    public var movementThresholdInG: Double
    public var testedAccelerationInG: Double

    /// Plain-language reasons, ordered, for the UI.
    public var reasons: [String]
    /// What is inside this object's strike zone, by name.
    public var endangers: [String]
    /// True when a code or standard forces a minimum band regardless of the
    /// computed score — an unstrapped gas water heater, for instance.
    public var hasRegulatoryOverride: Bool
    public var overrideReason: String?

    public init(
        objectID: UUID, score: Double, likelihood: Double,
        consequence: ConsequenceBreakdown,
        dominantBehaviour: RigidBlockSolver.Behaviour,
        behaviourDistribution: [String: Double],
        closenessToToppling: Double, slidingDisplacement: Double,
        impactEnergy: Double, movementThresholdInG: Double,
        testedAccelerationInG: Double, reasons: [String], endangers: [String],
        hasRegulatoryOverride: Bool = false, overrideReason: String? = nil
    ) {
        self.objectID = objectID
        self.score = score
        self.band = RiskBand(score: score)
        self.likelihood = likelihood
        self.consequence = consequence
        self.dominantBehaviour = dominantBehaviour
        self.behaviourDistribution = behaviourDistribution
        self.closenessToToppling = closenessToToppling
        self.slidingDisplacement = slidingDisplacement
        self.impactEnergy = impactEnergy
        self.movementThresholdInG = movementThresholdInG
        self.testedAccelerationInG = testedAccelerationInG
        self.reasons = reasons
        self.endangers = endangers
        self.hasRegulatoryOverride = hasRegulatoryOverride
        self.overrideReason = overrideReason
    }
}

/// Everything the app knows after simulating a room at one intensity.
public struct RoomAssessment: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var roomID: UUID
    public var intensity: MercalliIntensity
    public var soil: SoilClass
    public var seed: UInt64
    public var createdAt: Date

    public var objectRisks: [ObjectRisk]
    /// Peak floor acceleration the objects actually experienced, in g — ground
    /// motion times the building amplification.
    public var floorAccelerationInG: Double
    public var groundAccelerationInG: Double

    public init(
        id: UUID = UUID(), roomID: UUID, intensity: MercalliIntensity,
        soil: SoilClass, seed: UInt64, createdAt: Date = Date(),
        objectRisks: [ObjectRisk], floorAccelerationInG: Double,
        groundAccelerationInG: Double
    ) {
        self.id = id
        self.roomID = roomID
        self.intensity = intensity
        self.soil = soil
        self.seed = seed
        self.createdAt = createdAt
        self.objectRisks = objectRisks
        self.floorAccelerationInG = floorAccelerationInG
        self.groundAccelerationInG = groundAccelerationInG
    }

    public func risk(for objectID: UUID) -> ObjectRisk? {
        objectRisks.first { $0.objectID == objectID }
    }

    /// The room's headline band — the worst single object, because a room is
    /// only as safe as the thing most likely to land on you.
    public var overallBand: RiskBand {
        objectRisks.map(\.band).max() ?? .low
    }

    /// A 0…100 room score, weighted towards the worst offenders rather than
    /// averaged, so ten safe chairs cannot dilute one lethal bookcase.
    public var overallScore: Double {
        guard !objectRisks.isEmpty else { return 0 }
        let sorted = objectRisks.map(\.score).sorted(by: >)
        // Root-mean-cube: dominated by the top scores but not purely the max.
        let sum = sorted.reduce(0.0) { $0 + pow($1, 3) }
        return min(pow(sum / Double(sorted.count), 1.0 / 3.0) * 1.35, 100)
    }

    public var counts: [RiskBand: Int] {
        Dictionary(grouping: objectRisks, by: \.band).mapValues(\.count)
    }

    public var risksNeedingAction: [ObjectRisk] {
        objectRisks.filter { $0.band >= .high }.sorted { $0.score > $1.score }
    }
}

/// Computes the risk verdict for a room.
///
/// The verdict comes from an **ensemble** of analytic rigid-block solutions, not
/// from a single run and not from the 3D physics engine. Three reasons:
///
/// 1. The slide-or-rock branch turns on the hard comparison `μs ≶ b/h`, and
///    friction is only known to ±25%. One nominal run gives a confident answer
///    that is sometimes simply the wrong branch. Sampling gives a probability.
/// 2. Overturning is genuinely non-monotonic in pulse amplitude for near-fault
///    motion (Makris & Roussos 2000). Several ground-motion realisations are the
///    only honest way to summarise that.
/// 3. The analytic solver is deterministic and unit-tested against closed-form
///    results. The RealityKit simulation is tuned to look right at 60 fps and
///    makes contact-softening compromises, so it must never be the thing that
///    decides whether the app tells someone their child's room is safe.
public struct RiskEngine {

    /// Number of ensemble realisations. Twenty is the point where the failure
    /// fractions stop moving by more than a percent between runs, measured
    /// across the test fixtures.
    public var ensembleSize: Int
    /// Coefficient of variation applied to friction in the ensemble.
    public var frictionVariability: Double

    private let solver = RigidBlockSolver()
    private let synthesizer = AccelerogramSynthesizer()

    public init(ensembleSize: Int = 20, frictionVariability: Double = 0.25) {
        self.ensembleSize = max(ensembleSize, 1)
        self.frictionVariability = max(frictionVariability, 0)
    }

    // MARK: - Assessment

    public func assess(
        room: ScannedRoom,
        intensity: MercalliIntensity,
        seed: UInt64 = 0x1ED6E
    ) -> RoomAssessment {
        let amplification = room.building.floorAmplification
        let groundPGA = intensity.representativePGAInG
        let floorPGA = groundPGA * amplification

        var risks: [ObjectRisk] = []
        for object in room.objects {
            risks.append(assess(
                object: object, in: room, intensity: intensity,
                floorPGAInG: floorPGA, groundPGAInG: groundPGA, seed: seed
            ))
        }

        return RoomAssessment(
            roomID: room.id, intensity: intensity, soil: room.building.soil,
            seed: seed, objectRisks: risks,
            floorAccelerationInG: floorPGA, groundAccelerationInG: groundPGA
        )
    }

    /// The ground motion an object at floor level actually experiences.
    /// Generated once per realisation and shared by every object in the room, so
    /// the whole room is shaken by *one* earthquake rather than by N unrelated
    /// ones — which is both physically right and what makes the 3D view and the
    /// verdict agree.
    public func floorMotion(
        for room: ScannedRoom, intensity: MercalliIntensity, realisation: Int, seed: UInt64
    ) -> GroundMotion {
        let amplification = room.building.floorAmplification
        let params = AccelerogramSynthesizer.Parameters(
            targetPGAInG: intensity.representativePGAInG * amplification,
            soil: room.building.soil,
            duration: min(4.0 + Double(intensity.rawValue - 3) * 2.2, 26.0) + 12.0,
            strongMotionDuration: min(4.0 + Double(intensity.rawValue - 3) * 2.2, 26.0),
            dt: 0.005,
            seed: seed &+ UInt64(realisation) &* 0x9E37_79B9
        )
        return synthesizer.generate(
            params, name: "Intensity \(intensity.roman) · \(room.building.soil.displayName)")
    }

    // MARK: - Per object

    private func assess(
        object: ScannedObject, in room: ScannedRoom, intensity: MercalliIntensity,
        floorPGAInG: Double, groundPGAInG: Double, seed: UInt64
    ) -> ObjectRisk {
        let stacked = MassEstimator.objectsStacked(on: object, in: room)
        let nominalBlock = MassEstimator.block(for: object, in: room, stacked: stacked)

        // Seed from the UUID's own bytes, never from `hashValue`: Swift seeds
        // its hasher randomly per process, so using it here would make the risk
        // verdict change every time the app was relaunched.
        var rng = SeededGenerator(seed: seed &+ object.id.stableSeed)
        var results: [RigidBlockSolver.Result] = []
        results.reserveCapacity(ensembleSize)

        let surface: FloorSurface = object.supportHeight > 0.05
            ? .woodShelf : room.building.floorSurface

        for realisation in 0..<ensembleSize {
            let friction = FrictionDatabase.sample(
                footing: object.type.footing, on: surface,
                variability: frictionVariability, using: &rng)
            let block = MassEstimator.block(
                for: object, in: room, friction: friction, stacked: stacked)
            let motion = floorMotion(
                for: room, intensity: intensity, realisation: realisation, seed: seed)
            results.append(solver.solve(block: block, motion: motion))
        }

        return score(
            object: object, room: room, block: nominalBlock, results: results,
            stacked: stacked, floorPGAInG: floorPGAInG, intensity: intensity)
    }

    // MARK: - Scoring

    private func score(
        object: ScannedObject, room: ScannedRoom,
        block: RigidBlockSolver.Block, results: [RigidBlockSolver.Result],
        stacked: [ScannedObject], floorPGAInG: Double, intensity: MercalliIntensity
    ) -> ObjectRisk {
        let n = Double(results.count)

        // ---- Likelihood, straight from the ensemble ----
        // Likelihood is the probability the object fails *in any way*, not the
        // largest single failure mode. Taking a max was wrong: an object that
        // topples in half the runs and slides off its shelf in the other half
        // fails every time, but a max would report it as 50% likely — and worse,
        // it made risk fall as intensity rose, because stronger shaking spreads
        // failures across more modes.
        let failed = results.filter {
            $0.behaviour == .overturned || $0.behaviour == .fellOffSupport
        }.count
        // "Walking" — enough displacement to block a path or tear a gas or water
        // connection, without the object actually going over.
        let walked = results.filter {
            $0.behaviour != .overturned && $0.behaviour != .fellOffSupport
                && $0.slidingDisplacement > 0.15
        }.count

        let pFail = Double(failed) / n
        let pSlide = Double(walked) / n
        var likelihood = min(pFail + 0.5 * pSlide, 1.0)

        // Wall-mounted and leaning objects are not block problems, so neither
        // their likelihood nor their reported behaviour may come from the block
        // ensemble — a correctly mounted TV is not "overturning".
        var behaviourOverride: RigidBlockSolver.Behaviour?
        if object.mounting == .wallMounted {
            likelihood = wallMountedLikelihood(object: object, floorPGAInG: floorPGAInG)
            behaviourOverride = likelihood > 0.5 ? .fellOffSupport : .stable
        } else if object.mounting == .leaning {
            // A leaning mirror fails when its base slides out. The effective
            // threshold is well below the flat-block value because the wall
            // reaction reduces the normal force at the base.
            let pair = FrictionDatabase.coefficient(
                footing: object.type.footing, on: room.building.floorSurface)
            likelihood = min(max(floorPGAInG / max(pair.staticCoefficient * 0.6, 0.05), 0), 1)
            behaviourOverride = likelihood > 0.5 ? .overturned : .stable
        }

        // Anchoring suppresses but does not eliminate risk: an anchor is
        // designed for a ductility-reduced force and can still fail.
        if !object.canMove { likelihood *= 0.10 }
        // Unlocked castors make everything worse.
        if object.type.footing == .castor { likelihood = min(likelihood * 1.6, 1.0) }

        // ---- Consequence ----
        // Consequence answers "if this fails, how bad is it?" — a property of
        // the object's mass and geometry, not of the shaking. It is computed
        // deterministically rather than from the ensemble.
        //
        // Taking it from the ensemble was subtly wrong: conditioning on the runs
        // that failed introduces a selection effect that runs *against*
        // intensity. At low shaking only the unluckiest friction draws fail, and
        // those tend to be violent failures; as shaking rises, milder failures
        // join the sample and pull the median down. The result was an object
        // whose reported consequence fell as the earthquake got stronger.
        // Likelihood already carries everything the intensity should influence.
        let failureEnergy = self.failureEnergy(object: object, stacked: stacked)
        let strikeTargets = endangeredObjects(object: object, in: room)
        var consequence = ConsequenceBreakdown(
            impactEnergy: energyFactor(failureEnergy),
            occupantExposure: exposureFactor(object: object, room: room, targets: strikeTargets),
            fallHeight: fallHeightFactor(object: object),
            egressBlockage: egressFactor(object: object, in: room),
            breakage: breakageFactor(object: object),
            mass: massFactor(object.mass + stacked.reduce(0) { $0 + $1.mass }),
            secondaryHazard: object.type.secondaryHazard.severity
        )

        var c = consequence.total * room.kind.occupancyWeight
        if room.kind.isChildOccupied { c *= 1.20 }
        // A trivially light object that only blocks a path is not a real hazard.
        if object.mass < 3.0 && consequence.egressBlockage > 0 && consequence.impactEnergy < 0.2 {
            c *= 0.6
        }
        c = min(max(c, 0), 1)

        // ---- Combine ----
        // The 0.7 exponent on likelihood keeps genuinely lethal but unlikely
        // items — a 250 kg piano, a full water heater — from scoring near zero,
        // which is how practitioners actually triage.
        var raw = 100.0 * pow(likelihood, 0.7) * c

        // ---- Regulatory and code overrides ----
        var overrideReason: String?
        if (object.type == .waterHeaterGas || object.type == .waterHeater),
           object.canMove {
            // California Health & Safety Code §19211 and IRC P2801.8 require
            // strapping in seismic design category D. Over half the residential
            // fires after Northridge 1994 started at an unstrapped water heater
            // whose gas connector tore — a consequence no in-room injury model
            // captures.
            raw = max(raw, 55)
            overrideReason = "Water heaters are legally required to be strapped in seismic areas. An unstrapped one is a fire and flood risk far beyond the room it stands in."
        }
        if object.type == .rangeGas, object.canMove {
            raw = max(raw, 55)
            overrideReason = "Gas ranges need an anti-tip bracket and a flexible gas connector. A rigid connector snapping is a fire risk."
        }
        if object.mounting == .leaning, object.type == .mirrorLeaning {
            // Large unlaminated glass falling at head height in a bedroom.
            raw = max(raw, 55)
            overrideReason = "A leaning mirror is a documented injury source: it is large glass, it falls at head height, and nothing holds it up."
        }
        if object.type.isSleepingPlace == false, isAboveSleepingPlace(object: object, in: room) {
            raw = max(raw, 60)
            overrideReason = "This is above a bed. FEMA's strongest single piece of advice is that nothing heavy should be mounted or stacked above where someone sleeps."
        }

        let score = min(max(raw, 0), 100)

        return ObjectRisk(
            objectID: object.id,
            score: score,
            likelihood: likelihood,
            consequence: consequence,
            dominantBehaviour: behaviourOverride ?? dominant(results),
            behaviourDistribution: distribution(results),
            closenessToToppling: closeness(results),
            slidingDisplacement: median(results.map(\.slidingDisplacement)) ?? 0,
            impactEnergy: failureEnergy,
            movementThresholdInG: min(block.rockingThresholdInG, block.slidingThresholdInG),
            testedAccelerationInG: floorPGAInG,
            reasons: reasons(
                object: object, block: block, likelihood: likelihood,
                consequence: consequence, results: results, targets: strikeTargets,
                floorPGAInG: floorPGAInG, stacked: stacked,
                behaviour: behaviourOverride ?? dominant(results), energy: failureEnergy),
            endangers: strikeTargets.map { $0.type.displayName },
            hasRegulatoryOverride: overrideReason != nil,
            overrideReason: overrideReason
        )
    }

    // MARK: - Consequence factors

    /// f₁. Log-scaled between 5 J (harmless) and 500 J (severe). The midpoint
    /// lands near 50 J, which is the industrial helmet impact limit
    /// (EN 397 tests at 49 J, EN 812 at 50 J) — a defensible "this hurts" line.
    private func energyFactor(_ joules: Double) -> Double {
        guard joules > 5 else { return 0 }
        return min(max(log10(joules / 5.0) / log10(500.0 / 5.0), 0), 1)
    }

    /// f₆. Crush and pinning risk, independent of impact energy.
    private func massFactor(_ kg: Double) -> Double {
        guard kg > 5 else { return 0 }
        return min(max(log10(kg / 5.0) / log10(250.0 / 5.0), 0), 1)
    }

    /// f₃. Height of the object's top above the floor, saturating at 2 m, with a
    /// bump for the head-strike band.
    private func fallHeightFactor(object: ScannedObject) -> Double {
        var f = min(max(object.topHeight / 2.0, 0), 1)
        if (1.3...2.0).contains(object.topHeight) { f = min(f * 1.15, 1.0) }
        return f
    }

    /// f₅.
    private func breakageFactor(object: ScannedObject) -> Double {
        var severity = object.type.breakage.severity
        // Large glass only matters if it is high enough to fall on someone.
        if object.type.breakage == .largeGlass && object.topHeight < 1.0 {
            severity *= 0.6
        }
        return severity
    }

    /// f₂. Is a person in the way, and can they react?
    private func exposureFactor(
        object: ScannedObject, room: ScannedRoom, targets: [ScannedObject]
    ) -> Double {
        guard !targets.isEmpty else {
            // Nothing occupied in the strike zone. Still non-zero if it lands in
            // the middle of the room where someone might be standing.
            return isNearRoomCentre(object: object, in: room) ? 0.5 : 0.15
        }
        // A bed or crib is the worst case: the person is prone and asleep.
        if targets.contains(where: { $0.type.isSleepingPlace }) { return 1.0 }
        return 0.8
    }

    /// f₄. Does the toppled object block the way out?
    private func egressFactor(object: ScannedObject, in room: ScannedRoom) -> Double {
        let exits = room.egressOpenings
        guard !exits.isEmpty else { return 0 }
        // The toppled footprint reaches out from the object by its own height.
        let reach = Double(object.extents.height)
        let position = object.groundPosition

        var worst = 0.0
        for exit in exits {
            let exitPosition = SIMD2(exit.placement.centre.x, exit.placement.centre.z)
            let distance = Double(simd_distance(position, exitPosition))
            // The IBC requires 0.815 m (32 in) of clear width at a door. If the
            // fallen object reaches the doorway at all, treat the path as lost.
            if distance < reach + 0.815 {
                worst = max(worst, exits.count == 1 ? 1.0 : 0.6)
            } else if distance < reach + 1.6 {
                worst = max(worst, 0.3)
            }
        }
        return worst
    }

    // MARK: - Spatial reasoning

    /// Objects a person occupies that lie within this object's strike zone —
    /// the region it can reach when it falls, which is its own height plus a
    /// margin, measured from its footprint.
    private func endangeredObjects(object: ScannedObject, in room: ScannedRoom) -> [ScannedObject] {
        guard object.canMove else { return [] }
        let reach = Double(object.extents.height) + 0.3
        let position = object.groundPosition
        return room.occupantZones.filter { zone in
            guard zone.id != object.id else { return false }
            // Distance between footprint edges, not centres: a bed is two
            // metres long and being beside it is what matters.
            let zoneHalf = Double(max(zone.extents.width, zone.extents.depth)) / 2
            let distance = Double(simd_distance(position, zone.groundPosition))
            return distance - zoneHalf < reach
        }
    }

    /// Is this object mounted or stacked *directly over* a bed or crib?
    ///
    /// This forces a minimum band, so it has to mean literally above — over the
    /// sleeping surface, high enough to fall onto it. An earlier version padded
    /// the bed's footprint by 40 cm and caught a vase on the nightstand *beside*
    /// the bed, which is a different and much smaller hazard. A rule that fires
    /// on things that are merely nearby teaches users to ignore it.
    private func isAboveSleepingPlace(object: ScannedObject, in room: ScannedRoom) -> Bool {
        guard object.mass > 2.0,
              object.mounting == .wallMounted || object.supportHeight > 0.5
        else { return false }
        let position = object.groundPosition
        return room.objects.contains { bed in
            guard bed.type.isSleepingPlace else { return false }
            // Its footprint must overlap the sleeping surface itself.
            let dx = abs(position.x - bed.groundPosition.x)
            let dz = abs(position.y - bed.groundPosition.y)
            guard dx < bed.extents.width / 2, dz < bed.extents.depth / 2 else { return false }
            // And it must sit clear above that surface, so it can actually fall
            // onto a sleeping person rather than merely stand next to them.
            let bedTop = bed.supportHeight + Double(bed.extents.height)
            return object.supportHeight > bedTop + 0.2
        }
    }

    private func isNearRoomCentre(object: ScannedObject, in room: ScannedRoom) -> Bool {
        let walls = room.walls
        guard !walls.isEmpty else { return true }
        let xs = walls.map(\.placement.centre.x)
        let zs = walls.map(\.placement.centre.z)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minZ = zs.min(), let maxZ = zs.max() else { return true }
        let centre = SIMD2((minX + maxX) / 2, (minZ + maxZ) / 2)
        let halfSpan = Double(max(maxX - minX, maxZ - minZ)) / 2
        return Double(simd_distance(object.groundPosition, centre)) < halfSpan * 0.5
    }

    // MARK: - Wall fixings

    /// For a wall-mounted object, failure is the fixing pulling out rather than
    /// the object tipping. ASCE 7-16 Eq. 13.3-1 with a_p = 1.0, R_p = 1.5
    /// (a non-ductile anchor into wood) and I_p = 1.0 gives the demand; the
    /// capacity depends entirely on whether it went into a stud or into drywall.
    private func wallMountedLikelihood(object: ScannedObject, floorPGAInG: Double) -> Double {
        let weight = object.mass * Physics.g
        let demand = 0.4 * floorPGAInG * weight * 1.0 / 1.5
        let bounded = max(demand, 0.30 * floorPGAInG * weight)
        // Assume the common case: two fixings, and no way to know whether they
        // found studs. A 1/4" lag into a stud carries about 2700 N in
        // withdrawal; a drywall toggle carries 200–350 N. Take the
        // pessimistic-but-typical middle of 600 N per fixing.
        let assumedCapacityNewtons = 2.0 * 600.0
        return min(max(bounded / assumedCapacityNewtons, 0), 1)
    }

    // MARK: - Explanations

    private func reasons(
        object: ScannedObject, block: RigidBlockSolver.Block, likelihood: Double,
        consequence: ConsequenceBreakdown, results: [RigidBlockSolver.Result],
        targets: [ScannedObject], floorPGAInG: Double, stacked: [ScannedObject],
        behaviour: RigidBlockSolver.Behaviour, energy: Double
    ) -> [String] {
        var out: [String] = []

        if !object.canMove {
            out.append("It's anchored, so it stays where it is.")
            return out
        }

        // Every sentence below has to agree with the verdict. An earlier version
        // generated them from the nominal thresholds alone, which produced
        // things like a dresser that "would land with 244 joules" directly under
        // a verdict of "stable, 0% likely". Copy that argues with its own
        // conclusion is worse than no copy.
        let fails = likelihood > 0.15

        switch object.mounting {
        case .wallMounted:
            // ASCE 7-16 Eq. 13.3-1 with a_p = 1.0, R_p = 1.5, I_p = 1.0, bounded
            // below by 0.30·S_DS·W_p. The floor amplification is already in
            // `floorPGAInG`, so it is not applied twice.
            let weight = object.mass * Physics.g
            let demand = max(0.4 * floorPGAInG * weight / 1.5, 0.30 * floorPGAInG * weight)
            out.append(String(
                format: "It's fixed to the wall, so what matters is the fixings, not its shape. This quake pulls on them with about %.0f newtons.",
                demand))
            // Two 1/4" lags into studs carry ~5400 N between them; two drywall
            // toggles carry ~600 N. Only say the toggles are inadequate when
            // they actually are — telling someone their picture hook is
            // underspecified for a 7 N load reads as nonsense and costs the
            // app its credibility on the cases that matter.
            if demand > 600 {
                out.append("Two screws into studs hold about 5400 N between them. Two drywall anchors hold about 600 N, which is not enough here — this one has to reach studs.")
            } else if demand > 150 {
                out.append("Two screws into studs handle that easily. Drywall anchors are marginal — use a closed hook and find a stud if you can.")
            } else {
                out.append("That's well within what an ordinary fixing holds. The thing to check is that it's on a closed hook rather than an open one it can jump off.")
            }
        case .leaning:
            out.append("It isn't attached to anything — it's just resting against the wall, and it only takes its base sliding out for it to come down.")
        default:
            let threshold = min(block.rockingThresholdInG, block.slidingThresholdInG)
            let tips = block.rockingThresholdInG < block.slidingThresholdInG
            let ratio = floorPGAInG / max(threshold, 0.001)

            switch behaviour {
            case .overturned:
                out.append(String(
                    format: "It starts to tip at %.2fg and this quake reaches %.2fg — %.1f times what it takes — so it goes over.",
                    block.rockingThresholdInG, floorPGAInG,
                    floorPGAInG / max(block.rockingThresholdInG, 0.001)))
            case .fellOffSupport:
                out.append(String(
                    format: "It starts sliding at %.2fg and this quake reaches %.2fg, which is enough to walk it off the edge.",
                    block.slidingThresholdInG, floorPGAInG))
            case .slid:
                out.append(String(
                    format: "It slides at %.2fg and this quake reaches %.2fg, so it moves — but it's too low and wide to tip.",
                    block.slidingThresholdInG, floorPGAInG))
            case .rocked:
                out.append(String(
                    format: "It rocks at %.2fg and this quake reaches %.2fg. It lifts onto its edge and settles back down.",
                    block.rockingThresholdInG, floorPGAInG))
            case .stable, .restrained:
                if ratio > 1 {
                    out.append(String(
                        format: "It would start to %@ at %.2fg and this quake reaches %.2fg, but the shaking reverses too quickly to move it far.",
                        tips ? "tip" : "slide", threshold, floorPGAInG))
                } else {
                    out.append(String(
                        format: "It needs %.2fg to move at all, and this quake only reaches %.2fg.",
                        threshold, floorPGAInG))
                }
            }

            // Shape only explains a rocking failure, so only mention it there.
            if object.slenderness > 5, behaviour == .overturned || behaviour == .rocked {
                out.append(String(
                    format: "It's tall and narrow — %.0f times as high as it is wide at the base — and that's the shape that goes over first.",
                    object.slenderness))
            }

            if object.type.footing == .castor {
                out.append("It's on castors, so it rolls at almost any shaking. Lock them or chock the wheels.")
            } else if object.type.footing == .felt || object.type.footing == .ptfeGlide, fails {
                out.append("Its glides are made to slide easily, which works against you here.")
            }
        }

        // A stack raises the centre of gravity whatever the outcome, so it is
        // always worth naming — but phrase it as a fact, not as a prediction.
        if !stacked.isEmpty {
            let names = stacked.map { $0.type.displayName.lowercased() }
                .formattedList()
            out.append("The \(names) on top sits high and makes it easier to tip than it would be on its own.")
        }

        guard fails else { return out }

        if let target = targets.first(where: { $0.type.isSleepingPlace }) {
            out.append("It reaches the \(target.type.displayName.lowercased()) when it comes down.")
        } else if let target = targets.first {
            out.append("It reaches the \(target.type.displayName.lowercased()) when it comes down.")
        }

        if consequence.egressBlockage >= 0.6 {
            out.append("Once it's down it blocks your way out of the room.")
        }

        if consequence.impactEnergy > 0.5 {
            out.append(String(
                format: "It lands with about %.0f joules. A hard hat is rated to stop 50.",
                energy))
        }

        if object.type.hasSpillableContents {
            out.append("Its contents come out before it does — that's usually what hits you first.")
        }

        if object.type.breakage == .largeGlass {
            out.append("It's a large sheet of glass, so it doesn't just fall, it breaks.")
        }

        return out
    }

    // MARK: - Statistics

    private func dominant(_ results: [RigidBlockSolver.Result]) -> RigidBlockSolver.Behaviour {
        let counts = Dictionary(grouping: results, by: \.behaviour).mapValues(\.count)
        // Prefer the worst outcome among ties: reporting "it slid" when half the
        // runs toppled would understate the hazard.
        let severity: [RigidBlockSolver.Behaviour: Int] = [
            .restrained: 0, .stable: 1, .slid: 2, .rocked: 3,
            .fellOffSupport: 4, .overturned: 5,
        ]
        return counts.max { a, b in
            a.value != b.value ? a.value < b.value
                : (severity[a.key] ?? 0) < (severity[b.key] ?? 0)
        }?.key ?? .stable
    }

    private func distribution(_ results: [RigidBlockSolver.Result]) -> [String: Double] {
        let n = Double(results.count)
        return Dictionary(grouping: results, by: \.behaviour)
            .reduce(into: [:]) { $0[$1.key.rawValue] = Double($1.value.count) / n }
    }

    private func closeness(_ results: [RigidBlockSolver.Result]) -> Double {
        let survivors = results.filter { $0.behaviour != .overturned }
        guard !survivors.isEmpty else { return 1.0 }
        return survivors.map(\.rotationRatio).max() ?? 0
    }

    /// The energy released if this object fails, in joules — the height its
    /// centre of mass falls, times its weight.
    ///
    /// An object that topples does not drop its centre of mass all the way to
    /// the floor: once it is lying down the centre of mass sits at roughly the
    /// object's half-depth. An object that slides off a shelf does fall the
    /// whole way. Taking the larger of the two is both conservative and the
    /// right answer for whichever failure mode actually occurs.
    func failureEnergy(object: ScannedObject, stacked: [ScannedObject]) -> Double {
        let mass = object.mass + stacked.reduce(0) { $0 + $1.mass }
        let restingHeight = object.extents.governingHalfWidth
        let toppleDrop = max(object.centreOfMassHeight - restingHeight,
                             object.centreOfMassHeight * 0.3)
        let fallDrop = object.supportHeight > 0.05 ? object.centreOfMassHeight : 0
        let drop = object.supportHeight + max(toppleDrop, fallDrop)
        return mass * Physics.g * drop
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
    }
}


extension UUID {
    /// A process-independent 64-bit seed derived from the UUID's bytes, so a
    /// given object always draws the same ensemble.
    var stableSeed: UInt64 {
        let b = uuid
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325          // FNV-1a offset basis
        for byte in [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7,
                     b.8, b.9, b.10, b.11, b.12, b.13, b.14, b.15] {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}


private extension Array where Element == String {
    /// "the television", "the lamp and the books", "the lamp, the books and the vase".
    func formattedList() -> String {
        switch count {
        case 0: return ""
        case 1: return self[0]
        case 2: return "\(self[0]) and \(self[1])"
        default: return "\(dropLast().joined(separator: ", ")) and \(self[count - 1])"
        }
    }
}
