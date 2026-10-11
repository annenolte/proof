import Foundation
import simd

// MARK: - Where an answer came from

/// Which stage of the understanding pipeline produced a value.
///
/// Surfaced in the UI: SPEC §5.7 requires the report to badge an `AI-refined`
/// number differently from a looked-up one, because a user deserves to know
/// which figures came from a photograph and which from a table.
public enum ClassificationSource: String, Codable, CaseIterable, Sendable {
    /// The curated catalogue and the geometry pass alone. Always available,
    /// always offline, and defensible on its own — this is the anchor, not a
    /// fallback.
    case prior
    /// Refined by the on-device Vision classifier.
    case onDeviceRefined
    /// Refined by the cloud vision-language model, then clamped by the prior.
    case llmRefined
    /// Set by the user, which beats everything.
    case userOverride

    public var displayName: String {
        switch self {
        case .prior: return "Estimated"
        case .onDeviceRefined: return "Identified on device"
        case .llmRefined: return "AI-refined"
        case .userOverride: return "You set this"
        }
    }

    /// True when a photo was sent off the device to produce this value.
    public var isAIRefined: Bool { self == .llmRefined }

    /// The provenance source this maps onto in the shipped domain model.
    public var provenanceSource: IdentificationProvenance.Source {
        switch self {
        case .prior: return .scanner
        case .onDeviceRefined: return .onDeviceVision
        case .llmRefined: return .cloudVision
        case .userOverride: return .user
        }
    }
}

// MARK: - Materials and fragility

/// What an object is mostly made of. There is no on-device signal for this at
/// all, so it is one of the few fields the language model owns outright
/// (SPEC §5.1).
public enum MaterialClass: String, Codable, CaseIterable, Sendable {
    case solidWood = "solid_wood"
    case engineeredWood = "engineered_wood"
    case metal
    case plastic
    case glass
    case upholsteredFabric = "upholstered_fabric"
    case leather
    case stoneOrCeramic = "stone_or_ceramic"
    case composite
    case unknown

    public var displayName: String {
        switch self {
        case .solidWood: return "Solid wood"
        case .engineeredWood: return "Engineered wood"
        case .metal: return "Metal"
        case .plastic: return "Plastic"
        case .glass: return "Glass"
        case .upholsteredFabric: return "Upholstered"
        case .leather: return "Leather"
        case .stoneOrCeramic: return "Stone or ceramic"
        case .composite: return "Composite"
        case .unknown: return "Unknown"
        }
    }

    /// The wire values the strict JSON schema accepts for `material_secondary`,
    /// which deliberately excludes `unknown` — a sentinel inside an enum made
    /// the model emit self-contradictory answers like `["metal", "none"]`
    /// (research §4.5, a real bug found by testing).
    public static var secondaryWireValues: [String] {
        allCases.filter { $0 != .unknown }.map(\.rawValue)
    }

    public static var primaryWireValues: [String] {
        allCases.map(\.rawValue)
    }
}

/// How readily the object breaks. Ordered, so it can be clamped between an
/// archetype floor and an archetype ceiling.
public enum Fragility: String, Codable, CaseIterable, Sendable, Comparable {
    case robust
    case moderate
    case fragile
    case veryFragile = "very_fragile"

    private var order: Int {
        switch self {
        case .robust: return 0
        case .moderate: return 1
        case .fragile: return 2
        case .veryFragile: return 3
        }
    }

    public static func < (a: Fragility, b: Fragility) -> Bool { a.order < b.order }

    public var displayName: String {
        switch self {
        case .robust: return "Robust"
        case .moderate: return "Moderate"
        case .fragile: return "Fragile"
        case .veryFragile: return "Very fragile"
        }
    }
}

// MARK: - Mass with an honest interval

/// A mass estimate that carries its own uncertainty.
///
/// SPEC §5.7: the UI shows "about 86 kg (66–106 kg)", never "86 kg". Tracking
/// the interval is not decoration — it is what makes the inverse-variance
/// merge in `ObjectClassifier.mergeMass` possible at all.
public struct MassEstimate: Codable, Hashable, Sendable {
    /// Best point estimate, kg.
    public var kg: Double
    /// Low end of the plausible range, kg.
    public var low: Double
    /// High end of the plausible range, kg.
    public var high: Double
    public var source: ClassificationSource

    public init(kg: Double, low: Double, high: Double, source: ClassificationSource = .prior) {
        // A non-finite or inverted interval is never allowed to escape into the
        // physics. Everything downstream may assume `0 < low <= kg <= high`.
        let safeKg = kg.isFinite ? max(kg, 0.01) : 1.0
        let safeLow = low.isFinite ? max(min(low, safeKg), 0.001) : safeKg * 0.5
        let safeHigh = high.isFinite ? max(high, safeKg) : safeKg * 2
        self.kg = safeKg
        self.low = safeLow
        self.high = safeHigh
        self.source = source
    }

    /// Half-width of the ±2σ interval the merge treats this range as.
    public var sigma: Double { max((high - low) / 4, 1e-6) }

    /// "about 86 kg (66–106 kg)"
    public var displayString: String {
        let f = { (v: Double) -> String in
            v < 10 ? String(format: "%.1f", v) : String(format: "%.0f", v)
        }
        return "about \(f(kg)) kg (\(f(low))–\(f(high)) kg)"
    }
}

// MARK: - On-device vision evidence

public struct LabelledConfidence: Codable, Hashable, Sendable {
    public var label: String
    public var confidence: Double

    public init(label: String, confidence: Double) {
        self.label = label
        self.confidence = confidence.isFinite ? min(max(confidence, 0), 1) : 0
    }
}

/// What the on-device pass saw. Cheap, offline, deterministic, and — crucially
/// — the layer that still works with the cloud switched off.
public struct VisionEvidence: Codable, Hashable, Sendable {
    /// Precision/recall-gated, allow-listed, at most five.
    public var labels: [LabelledConfidence]
    /// Nameplate text: "SAMSUNG RF28…" pins an appliance model, and therefore
    /// its real mass, to within a few kg.
    public var ocrStrings: [String]
    /// Privacy guard. A crop containing a face is never uploaded.
    public var hasFace: Bool

    public init(labels: [LabelledConfidence] = [], ocrStrings: [String] = [], hasFace: Bool = false) {
        self.labels = labels
        self.ocrStrings = ocrStrings
        self.hasFace = hasFace
    }

    public static let empty = VisionEvidence()

    public var topLabel: LabelledConfidence? {
        labels.max { $0.confidence < $1.confidence }
    }
}

// MARK: - The language model's answer

/// The strict-Structured-Output payload, decoded verbatim.
///
/// Field-for-field the schema in SPEC §5.5.5, which was verified live against
/// the API. Nothing here is trusted: every value passes through the guards in
/// `ObjectClassifier` before it reaches the physics.
public struct LLMObjectProperties: Codable, Hashable, Sendable {
    public var objectID: String
    /// Free text, e.g. "tall open bookshelf". Matched against the geometry
    /// shortlist rather than used directly — the model chooses a *type*, and
    /// the type's own mass range then caps the mass.
    public var objectType: String
    public var materialPrimary: MaterialClass
    public var materialSecondary: [MaterialClass]
    public var massKgEstimate: Double
    public var massKgMin: Double
    public var massKgMax: Double
    public var centerOfMassHeightFraction: Double
    /// Advisory only. Geometry owns mounting (SPEC §5.1).
    public var mounting: String
    public var fragility: Fragility
    public var containsGlass: Bool
    public var contentsCanFallOut: Bool
    /// Stored for telemetry ONLY. The hazard verdict is ours, never the model's.
    public var tipOverRisk: String
    public var confidence: Double
    public var notes: String

    enum CodingKeys: String, CodingKey {
        case objectID = "object_id"
        case objectType = "object_type"
        case materialPrimary = "material_primary"
        case materialSecondary = "material_secondary"
        case massKgEstimate = "mass_kg_estimate"
        case massKgMin = "mass_kg_min"
        case massKgMax = "mass_kg_max"
        case centerOfMassHeightFraction = "center_of_mass_height_fraction"
        case mounting
        case fragility
        case containsGlass = "contains_glass"
        case contentsCanFallOut = "contents_can_fall_out"
        case tipOverRisk = "tip_over_risk"
        case confidence
        case notes
    }

    public init(
        objectID: String,
        objectType: String,
        materialPrimary: MaterialClass = .unknown,
        materialSecondary: [MaterialClass] = [],
        massKgEstimate: Double,
        massKgMin: Double,
        massKgMax: Double,
        centerOfMassHeightFraction: Double = 0.5,
        mounting: String = "unknown",
        fragility: Fragility = .moderate,
        containsGlass: Bool = false,
        contentsCanFallOut: Bool = false,
        tipOverRisk: String = "low",
        confidence: Double = 0.5,
        notes: String = ""
    ) {
        self.objectID = objectID
        self.objectType = objectType
        self.materialPrimary = materialPrimary
        self.materialSecondary = materialSecondary
        self.massKgEstimate = massKgEstimate
        self.massKgMin = massKgMin
        self.massKgMax = massKgMax
        self.centerOfMassHeightFraction = centerOfMassHeightFraction
        self.mounting = mounting
        self.fragility = fragility
        self.containsGlass = containsGlass
        self.contentsCanFallOut = contentsCanFallOut
        self.tipOverRisk = tipOverRisk
        self.confidence = confidence
        self.notes = notes
    }

    /// Decoding is tolerant of a model that drifts outside the enum — an
    /// unexpected `material_primary` or `fragility` string degrades to a safe
    /// default rather than throwing the whole answer away. `strict: true` makes
    /// this unlikely, but network middleboxes and future model revisions exist,
    /// and a usable partial answer beats no answer.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        objectID = (try? c.decode(String.self, forKey: .objectID)) ?? ""
        objectType = (try? c.decode(String.self, forKey: .objectType)) ?? ""
        materialPrimary = (try? c.decode(MaterialClass.self, forKey: .materialPrimary)) ?? .unknown
        let rawSecondary = (try? c.decode([String].self, forKey: .materialSecondary)) ?? []
        materialSecondary = rawSecondary.compactMap(MaterialClass.init(rawValue:))
        massKgEstimate = try c.decode(Double.self, forKey: .massKgEstimate)
        massKgMin = try c.decode(Double.self, forKey: .massKgMin)
        massKgMax = try c.decode(Double.self, forKey: .massKgMax)
        centerOfMassHeightFraction =
            (try? c.decode(Double.self, forKey: .centerOfMassHeightFraction)) ?? 0.5
        mounting = (try? c.decode(String.self, forKey: .mounting)) ?? "unknown"
        fragility = (try? c.decode(Fragility.self, forKey: .fragility)) ?? .moderate
        containsGlass = (try? c.decode(Bool.self, forKey: .containsGlass)) ?? false
        contentsCanFallOut = (try? c.decode(Bool.self, forKey: .contentsCanFallOut)) ?? false
        tipOverRisk = (try? c.decode(String.self, forKey: .tipOverRisk)) ?? "unknown"
        confidence = (try? c.decode(Double.self, forKey: .confidence)) ?? 0.0
        notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
    }

    /// True when every number the merge depends on is finite. A `NaN` or an
    /// infinity here means the whole answer is discarded and the prior stands.
    public var hasFiniteNumbers: Bool {
        massKgEstimate.isFinite && massKgMin.isFinite && massKgMax.isFinite
            && centerOfMassHeightFraction.isFinite && confidence.isFinite
    }

    /// Confidence clamped into 0…1, since `minimum`/`maximum` in a strict
    /// schema steer the decoder but are not enforced by it (research §4.5).
    public var clampedConfidence: Double {
        guard confidence.isFinite else { return 0 }
        return min(max(confidence, 0), 1)
    }
}

/// Everything that can go wrong in the cloud pass. Every case is recoverable:
/// the caller falls through to the prior and the app stays fully useful.
public enum LLMError: Error, Sendable, Equatable {
    /// `status != "completed"` — usually `max_output_tokens`. Retryable once
    /// with a doubled budget.
    case incomplete(reason: String)
    /// The response had no `message` item. Remember `output[0]` is a
    /// `reasoning` item, not the message.
    case noMessage
    case rateLimited(retryAfter: TimeInterval?)
    case server(status: Int)
    /// 400 / 401 / 403 — never retried; the cloud layer is disabled for the
    /// session.
    case permanent(status: Int)
    case unauthorized
    case noAPIKey
    case decoding(String)
    case timedOut
    case transport(String)
    /// A face was found in the crop, so it was never uploaded.
    case faceDetected

    /// Whether the whole cloud layer should be switched off for this session.
    public var disablesCloudLayer: Bool {
        switch self {
        case .unauthorized, .noAPIKey: return true
        case .permanent(let status): return status == 401 || status == 403 || status == 400
        default: return false
        }
    }
}

// MARK: - The merged answer

/// The output of the whole pipeline for one object: a confident physical
/// profile built from geometry, on-device vision, the curated catalogue and —
/// optionally — the cloud model, in that order of authority.
public struct ClassificationResult: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID { objectID }
    public var objectID: UUID

    /// The resolved catalogue type. Always a real `ObjectType`; the model can
    /// only ever pick from the shortlist its RoomPlan category allows.
    public var type: ObjectType
    public var provenance: IdentificationProvenance
    public var mass: MassEstimate
    /// Centre-of-mass height as a fraction of the object's own height, clamped
    /// to `[0.20, 0.75]` and never moved more than ±0.15 from the prior.
    public var centreOfMassFraction: Double
    /// Geometry's verdict, essentially never the model's.
    public var mounting: Mounting
    public var loading: LoadingState
    public var material: MaterialClass
    public var secondaryMaterials: [MaterialClass]
    public var fragility: Fragility
    public var containsGlass: Bool
    public var contentsCanFallOut: Bool
    /// Free-text hints from the geometry pass, shown in the object detail sheet.
    public var hints: [String]
    /// The model's own words about what drove its estimate, if it ran.
    public var notes: String?
    /// The model's `tip_over_risk`, retained purely as a telemetry
    /// disagreement signal. Never read by the risk engine.
    public var modelTipOverRisk: String?
    /// `|m_llm − m_prior| / m_prior`, the number that improves the catalogue
    /// over time. Nil when the cloud pass did not run.
    public var priorDisagreement: Double?
    public var source: ClassificationSource

    public init(
        objectID: UUID,
        type: ObjectType,
        provenance: IdentificationProvenance,
        mass: MassEstimate,
        centreOfMassFraction: Double,
        mounting: Mounting,
        loading: LoadingState = .partial,
        material: MaterialClass = .unknown,
        secondaryMaterials: [MaterialClass] = [],
        fragility: Fragility = .moderate,
        containsGlass: Bool = false,
        contentsCanFallOut: Bool = false,
        hints: [String] = [],
        notes: String? = nil,
        modelTipOverRisk: String? = nil,
        priorDisagreement: Double? = nil,
        source: ClassificationSource = .prior
    ) {
        self.objectID = objectID
        self.type = type
        self.provenance = provenance
        self.mass = mass
        self.centreOfMassFraction = centreOfMassFraction
        self.mounting = mounting
        self.loading = loading
        self.material = material
        self.secondaryMaterials = secondaryMaterials
        self.fragility = fragility
        self.containsGlass = containsGlass
        self.contentsCanFallOut = contentsCanFallOut
        self.hints = hints
        self.notes = notes
        self.modelTipOverRisk = modelTipOverRisk
        self.priorDisagreement = priorDisagreement
        self.source = source
    }

    /// Folds the profile into a scanned object, respecting the two things the
    /// user owns outright: a mass they set themselves, and an anchor they told
    /// us about. No later pass may overwrite either.
    public func applied(to object: ScannedObject) -> ScannedObject {
        var updated = object
        updated.type = type
        updated.provenance = provenance
        if !object.massIsUserSet {
            updated.mass = mass.kg
        }
        updated.loading = loading
        updated.mounting = object.isAnchored ? object.mounting : mounting
        updated.centreOfMassHeight = Double(object.extents.height) * centreOfMassFraction
        return updated
    }
}

// MARK: - Pipeline input

/// One object presented to the pipeline. Deliberately a value type with no
/// RoomPlan or ARKit dependency, so the whole of §5 is testable in the
/// Simulator, where RoomPlan cannot run.
public struct ClassificationRequest: Sendable, Equatable {
    public var objectID: UUID
    /// RoomPlan's own coarse category string, e.g. "storage".
    public var roomPlanCategory: String
    /// RoomPlan attributes as wire strings, e.g. `["StorageType.shelf"]`.
    public var roomPlanAttributes: [String]
    public var extents: Extents
    /// Height of the object's base above the floor, metres.
    public var baseHeightAboveFloor: Double
    /// True when the object sits on top of another object we identified.
    public var hasHostBelow: Bool
    /// Perpendicular distance from the object's back face to the nearest wall,
    /// metres. Nil when unknown.
    public var distanceToNearestWall: Double?
    /// True when a `sink` / `stove` / `dishwasher` sibling is within 1.5 m.
    public var nearCounterFixture: Bool
    public var roomKind: RoomKind
    /// The captured crop, JPEG. Nil when no usable frame was found, in which
    /// case the cloud pass is skipped for this object.
    public var cropJPEG: Data?
    /// A loading state the user already chose, which the pipeline must respect.
    public var userLoading: LoadingState?

    public init(
        objectID: UUID,
        roomPlanCategory: String,
        roomPlanAttributes: [String] = [],
        extents: Extents,
        baseHeightAboveFloor: Double = 0,
        hasHostBelow: Bool = false,
        distanceToNearestWall: Double? = nil,
        nearCounterFixture: Bool = false,
        roomKind: RoomKind = .other,
        cropJPEG: Data? = nil,
        userLoading: LoadingState? = nil
    ) {
        self.objectID = objectID
        self.roomPlanCategory = roomPlanCategory
        self.roomPlanAttributes = roomPlanAttributes
        self.extents = extents
        self.baseHeightAboveFloor = baseHeightAboveFloor
        self.hasHostBelow = hasHostBelow
        self.distanceToNearestWall = distanceToNearestWall
        self.nearCounterFixture = nearCounterFixture
        self.roomKind = roomKind
        self.cropJPEG = cropJPEG
        self.userLoading = userLoading
    }

    /// Builds a request from an already-scanned object, which is how the
    /// fixtures and the re-refinement flow drive the pipeline.
    public init(object: ScannedObject, in room: ScannedRoom, cropJPEG: Data? = nil) {
        // Wall-hung and suspended objects are positioned by their centre, since
        // they have no base resting on anything.
        let hangs = object.mounting == .wallMounted || object.mounting == .suspended
        let base = hangs
            ? Double(object.placement.centre.y)
            : Double(object.placement.centre.y) - Double(object.extents.height) / 2
        self.init(
            objectID: object.id,
            roomPlanCategory: object.provenance.scannerCategory,
            roomPlanAttributes: [],
            extents: object.extents,
            baseHeightAboveFloor: max(base, 0),
            // A support height on a hung object is how high it hangs, not
            // something standing underneath it.
            hasHostBelow: object.supportedBy != nil || (!hangs && object.supportHeight > 0.05),
            distanceToNearestWall: ClassificationRequest.wallGap(object, room),
            nearCounterFixture: room.objects.contains {
                ($0.type == .sink || $0.type == .rangeElectric || $0.type == .rangeGas
                    || $0.type == .dishwasher)
                    && simd_distance($0.groundPosition, object.groundPosition) < 1.5
            },
            roomKind: room.kind,
            cropJPEG: cropJPEG,
            userLoading: object.massIsUserSet ? object.loading : nil
        )
    }

    /// Perpendicular distance from the object's footprint centre to the nearest
    /// wall *plane*, considering only walls the object actually sits in front
    /// of. A wall's local X axis runs along its length and its local Z axis is
    /// its normal, which is what makes this a plane distance rather than a
    /// distance to an arbitrary point on the wall.
    private static func wallGap(_ object: ScannedObject, _ room: ScannedRoom) -> Double? {
        let p = object.groundPosition
        var best: Double?
        for wall in room.walls {
            let c = SIMD2(wall.placement.centre.x, wall.placement.centre.z)
            let yaw = wall.placement.yaw
            let along = SIMD2<Float>(cos(yaw), sin(yaw))
            let normal = SIMD2<Float>(-sin(yaw), cos(yaw))
            let delta = p - c
            let lateral = abs(simd_dot(delta, along))
            guard lateral <= wall.extents.width / 2 + 0.25 else { continue }
            let perpendicular = Double(abs(simd_dot(delta, normal)))
            best = min(best ?? .greatestFiniteMagnitude, perpendicular)
        }
        return best
    }
}

// MARK: - Progress

/// Streamed as the pipeline runs, so object cards can fill in progressively
/// rather than the room blocking on its slowest object (SPEC §5.5.2).
public enum UnderstandingProgress: Sendable, Equatable {
    case geometryComplete(objectCount: Int)
    case visionComplete(objectID: UUID, type: ObjectType)
    case priorComplete(objectID: UUID, massKg: Double)
    case cloudComplete(objectID: UUID, source: ClassificationSource)
    case cloudUnavailable(reason: String)
    case finished
}
