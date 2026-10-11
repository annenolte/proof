import CoreGraphics
import Foundation
import ImageIO

/// The whole of §5: geometry → on-device vision → curated catalogue → cloud
/// model → merge.
///
/// Each stage is a *fallback for the one after it*, so the pipeline degrades
/// smoothly rather than failing: with no network and no key it still returns a
/// defensible profile for every object, because the catalogue is the anchor and
/// the model is only ever a bounded correction to it.
public protocol ObjectClassifying: Sendable {
    /// Never throws. A per-object failure yields the prior, never an error.
    func classify(_ request: ClassificationRequest, allowCloud: Bool) async -> ClassificationResult

    /// Classifies a whole room, in parallel, streaming progress.
    func classify(
        room: ScannedRoom,
        crops: [UUID: Data],
        allowCloud: Bool,
        progress: @Sendable @escaping (UnderstandingProgress) -> Void
    ) async -> [UUID: ClassificationResult]
}

public struct ObjectClassifier: ObjectClassifying {

    public struct Configuration: Sendable {
        /// Below this the model's answer is discarded outright.
        public var massConfidenceFloor: Double
        /// The model owns the *type* only when it is at least this sure.
        public var typeConfidenceFloor: Double
        /// Two-sided hard clamp on mass, as multiples of the prior's interval.
        public var massClampLow: Double
        public var massClampHigh: Double
        /// Floor on the model's own σ, as a fraction of its estimate.
        public var minimumRelativeSigma: Double
        /// Cap on the model's weight, as a multiple of the prior's.
        public var maximumWeightRatio: Double
        /// The most the model may move the centre-of-mass fraction.
        public var comDeltaLimit: Double
        /// And the absolute envelope it is clamped into afterwards.
        public var comBounds: ClosedRange<Double>
        /// Parallel cloud requests. Eight is comfortably inside default rate
        /// limits and keeps the radio in one continuous burst.
        public var maxConcurrentCloudRequests: Int
        /// Whole-room wall clock for the cloud stage.
        public var roomBudget: TimeInterval

        public init(
            massConfidenceFloor: Double = 0.35,
            typeConfidenceFloor: Double = 0.50,
            massClampLow: Double = 0.40,
            massClampHigh: Double = 2.50,
            minimumRelativeSigma: Double = 0.15,
            maximumWeightRatio: Double = 2.0,
            comDeltaLimit: Double = 0.15,
            comBounds: ClosedRange<Double> = 0.20...0.75,
            maxConcurrentCloudRequests: Int = 8,
            roomBudget: TimeInterval = 20
        ) {
            self.massConfidenceFloor = massConfidenceFloor
            self.typeConfidenceFloor = typeConfidenceFloor
            self.massClampLow = massClampLow
            self.massClampHigh = massClampHigh
            self.minimumRelativeSigma = minimumRelativeSigma
            self.maximumWeightRatio = maximumWeightRatio
            self.comDeltaLimit = comDeltaLimit
            self.comBounds = comBounds
            self.maxConcurrentCloudRequests = maxConcurrentCloudRequests
            self.roomBudget = roomBudget
        }

        public static let `default` = Configuration()
    }

    public var configuration: Configuration
    private let vision: (any VisionClassifying)?
    private let llm: (any ObjectLLMClienting)?

    public init(
        vision: (any VisionClassifying)? = nil,
        llm: (any ObjectLLMClienting)? = nil,
        configuration: Configuration = .default
    ) {
        self.vision = vision
        self.llm = llm
        self.configuration = configuration
    }

    // MARK: - Stage 3: the prior, which is the anchor

    /// The catalogue's effective-density spread, as multiples of the point
    /// prior.
    ///
    /// The published archetype table quotes an explicit ρ_min/ρ_max per row,
    /// and across the whole table those brackets sit at a strikingly constant
    /// ratio — 200→150–280, 160→110–220, 110→80–160, 320→240–450, 55→40–80 —
    /// i.e. about 0.73× and 1.42×. Deriving the interval from the shipped point
    /// prior rather than duplicating a second table keeps one source of truth
    /// (`ObjectType.densityPrior`) and reproduces the published brackets to
    /// within a couple of kilograms.
    public static let densitySpreadLow = 0.73
    public static let densitySpreadHigh = 1.42

    /// `m = ρ_eff · V_bbox`, clamped to the type's plausible envelope.
    ///
    /// The clamp is what makes this pipeline safe to put a language model in
    /// front of: the model only ever chooses a *type*, and the type caps the
    /// mass, so a hallucinated 800 kg bookshelf is not merely unlikely — it is
    /// unrepresentable.
    public static func priorMass(
        type: ObjectType, extents: Extents, loading: LoadingState = .partial
    ) -> MassEstimate {
        let range = type.massRange
        let clamp = { (v: Double) in min(max(v, range.lowerBound), range.upperBound) }

        // A flat panel is not a volume. A 0.08 m-deep television is mostly the
        // air behind the glass, so the volume model reports a small fraction of
        // the truth; screen area is the right predictor and matches real 50″
        // sets at 11–14 kg.
        if type == .television || type == .televisionWallMounted || type == .computerMonitor,
           Double(extents.depth) < 0.15 {
            let area = Double(extents.width) * Double(extents.height)
            let kg = clamp(11 * area + 2)
            return MassEstimate(kg: kg, low: clamp(kg * 0.75), high: clamp(kg * 1.35))
        }

        let kg = MassEstimator.mass(type: type, extents: extents, loading: loading)
        let loadFactor = type.respondsToLoading ? loading.multiplier : 1.0
        let raw = type.densityPrior * extents.volume * loadFactor
        return MassEstimate(
            kg: kg,
            low: clamp(raw * densitySpreadLow),
            high: clamp(raw * densitySpreadHigh))
    }

    // MARK: - Stage 5: the merge, and its three guards

    /// Blends the model's mass into the prior's.
    ///
    /// Three guards, none optional, each individually unit-tested:
    ///
    /// 1. **Hard clamp** to `[0.40 · prior.low, 2.50 · prior.high]`. Generous
    ///    enough for a real archetype correction (bookshelf→dresser ≈ 0.8×,
    ///    empty→loaded ≈ 3×), tight enough that a hallucinated 5 kg or 900 kg
    ///    bookcase is impossible.
    /// 2. **Confidence floor** of 0.35, plus a sanity gate on the model's own
    ///    interval: inverted, non-positive or absurdly wide (>20×) means the
    ///    whole answer is untrustworthy, not merely imprecise.
    /// 3. **Weight cap** at 2× the prior's, with the model's σ floored at 15 %
    ///    of its estimate. Without these, the measured gpt-4o answer — 40 kg,
    ///    ±5 kg, confidence 0.95 — carries 33× the prior's weight and drags an
    ///    86 kg estimate to 41.5 kg. With them it lands at ≈ 74 kg: noticeably
    ///    worse, never absurd. **That is the property we are buying.**
    ///
    /// 4. **The archetype's own envelope**, `envelope` — normally
    ///    `type.massRange`. Guards 1–3 alone are *relative* to the prior, and a
    ///    relative bound is not a bound: `prior.high` is itself as large as the
    ///    archetype's maximum, so `2.50 · prior.high` sits at 2.5× the heaviest
    ///    example of the type that exists. Feed the merge a confident, tight
    ///    "this bookshelf weighs 500 kg" and the weight cap still lets it pull
    ///    the answer to ≈ 230 kg — above the catalogue's own 220 kg ceiling for
    ///    the heaviest bookcase ever made, and 2.7× the truth. Clamping the
    ///    blended result back into the archetype's range is what actually makes
    ///    the docstring above literally true. It costs nothing in the honest
    ///    case: the prior is always inside the envelope already, so this only
    ///    ever bites a merge the model dragged out of it.
    public static func mergeMass(
        prior: MassEstimate,
        llm: LLMObjectProperties?,
        configuration: Configuration = .default,
        envelope: ClosedRange<Double>? = nil
    ) -> MassEstimate {
        // Applied on *every* return path, including the ones that discard the
        // model's answer, so the postcondition holds unconditionally.
        func bounded(_ estimate: MassEstimate) -> MassEstimate {
            guard let envelope else { return estimate }
            let fit = { (v: Double) in min(max(v, envelope.lowerBound), envelope.upperBound) }
            return MassEstimate(
                kg: fit(estimate.kg), low: fit(estimate.low), high: fit(estimate.high),
                source: estimate.source)
        }

        guard let llm,
              llm.hasFiniteNumbers,
              llm.clampedConfidence >= configuration.massConfidenceFloor
        else { return bounded(prior) }

        // Guard 1 — hard clamp, relative to the prior's interval.
        let floor = prior.low * configuration.massClampLow
        let ceiling = prior.high * configuration.massClampHigh
        let clamped = min(max(llm.massKgEstimate, floor), ceiling)

        // Guard 2 — sanity-gate the model's own interval.
        guard llm.massKgMin > 0,
              llm.massKgMax >= llm.massKgMin,
              llm.massKgMax / max(llm.massKgMin, 0.1) < 20
        else { return bounded(prior) }

        // Guard 3 — inverse-variance blend with a σ floor and a weight cap.
        let sPrior = max((prior.high - prior.low) / 4, 1e-6)
        let sLLM = max((llm.massKgMax - llm.massKgMin) / 4,
                       configuration.minimumRelativeSigma * clamped)
        guard sLLM > 0 else { return bounded(prior) }
        let wPrior = 1 / (sPrior * sPrior)
        let wLLM = min(llm.clampedConfidence / (sLLM * sLLM),
                       configuration.maximumWeightRatio * wPrior)

        let mu = (prior.kg * wPrior + clamped * wLLM) / (wPrior + wLLM)
        let sigma = (1 / (wPrior + wLLM)).squareRoot()
        guard mu.isFinite, sigma.isFinite else { return bounded(prior) }

        return bounded(MassEstimate(
            kg: mu,
            low: max(mu - 2 * sigma, floor),
            high: min(mu + 2 * sigma, ceiling),
            source: .llmRefined))
    }

    /// The model may nudge the centre of mass, never relocate it.
    ///
    /// This value multiplies the tip-over torque directly, so an unbounded one
    /// is a safety bug rather than an inaccuracy: it is the difference between
    /// "anchor this" and "leave it". Bounded to ±0.15 of the catalogue prior
    /// and then clamped into `[0.20, 0.75]`.
    public static func mergeCentreOfMassFraction(
        prior: Double,
        llm: LLMObjectProperties?,
        configuration: Configuration = .default
    ) -> Double {
        let bounds = configuration.comBounds
        let anchored = min(max(prior, bounds.lowerBound), bounds.upperBound)
        guard let llm,
              llm.hasFiniteNumbers,
              llm.clampedConfidence >= configuration.massConfidenceFloor
        else { return anchored }

        let requested = llm.centerOfMassHeightFraction
        guard requested.isFinite else { return anchored }
        let delta = min(max(requested - prior, -configuration.comDeltaLimit),
                        configuration.comDeltaLimit)
        return min(max(prior + delta, bounds.lowerBound), bounds.upperBound)
    }

    /// Resolves the catalogue type from all four stages.
    ///
    /// Order of authority, from SPEC §5.6.4: the model wins when it is at least
    /// 0.5 sure *and* its free-text name matches something the geometry
    /// shortlist allows; otherwise the on-device label; otherwise the geometry
    /// shortlist's own first entry; otherwise the RoomPlan category default.
    ///
    /// Note what this construction rules out. The model never picks from the
    /// full 50-type taxonomy — only from the handful its RoomPlan category and
    /// bounding box permit — so it cannot rename a sofa into a wardrobe, and a
    /// type it invents that matches nothing simply loses.
    public static func mergeType(
        geometry: GeometryPrior.Output,
        vision: VisionEvidence?,
        llm: LLMObjectProperties?,
        roomPlanCategory: String,
        configuration: Configuration = .default
    ) -> (type: ObjectType, source: ClassificationSource, confidence: Double) {
        if let llm, llm.clampedConfidence >= configuration.typeConfidenceFloor,
           let matched = ObjectTypeMatcher.match(
            freeText: llm.objectType, within: geometry.shortlist) {
            return (matched, .llmRefined, llm.clampedConfidence)
        }
        if let vision, let refined = OnDeviceVision.refine(
            shortlist: geometry.shortlist, with: vision) {
            return (refined.type, .onDeviceRefined, refined.confidence)
        }
        if let best = geometry.shortlist.first {
            return (best, .prior, geometry.confidence)
        }
        return (ObjectType.fallback(forRoomPlanCategory: roomPlanCategory), .prior, 0.3)
    }

    /// Fragility is the model's, bounded by what the archetype makes possible:
    /// a refrigerator is never `very_fragile` however the photo looks, and a
    /// wall of unlaminated glass is never `robust`.
    public static func mergeFragility(type: ObjectType, llm: LLMObjectProperties?) -> Fragility {
        let floor = fragilityFloor(for: type)
        let ceiling = fragilityCeiling(for: type)
        guard let llm else { return min(max(defaultFragility(for: type), floor), ceiling) }
        return min(max(llm.fragility, floor), ceiling)
    }

    public static func defaultFragility(for type: ObjectType) -> Fragility {
        switch type.breakage {
        case .largeGlass: return .fragile
        case .mediumGlass: return .fragile
        case .smallGlass: return .moderate
        case .ceramic: return .fragile
        case .none: return .moderate
        }
    }

    public static func fragilityFloor(for type: ObjectType) -> Fragility {
        switch type.breakage {
        case .largeGlass: return .fragile
        case .mediumGlass, .ceramic: return .moderate
        case .smallGlass, .none: return .robust
        }
    }

    public static func fragilityCeiling(for type: ObjectType) -> Fragility {
        type.breakage == .none ? .moderate : .veryFragile
    }

    /// Which loading state the merged mass implies, so the object card can show
    /// "Packed" rather than a bare number — and so the user can correct it in
    /// one tap, which is the single highest-value correction they can make.
    public static func inferLoading(
        type: ObjectType, extents: Extents, mass: Double, userChoice: LoadingState?
    ) -> LoadingState {
        if let userChoice { return userChoice }
        guard type.respondsToLoading else { return .partial }
        let typical = type.densityPrior * extents.volume
        guard typical > 0, mass.isFinite else { return .partial }
        let ratio = mass / typical
        if ratio >= 1.25 { return .full }
        if ratio <= 0.60 { return .empty }
        return .partial
    }

    // MARK: - Per-object pipeline

    public func classify(
        _ request: ClassificationRequest, allowCloud: Bool
    ) async -> ClassificationResult {
        let geometry = GeometryPrior.evaluate(request)

        // Stage 2. Failure here is not an error the caller sees — it just means
        // we have geometry and the catalogue, which is still a real answer.
        var evidence: VisionEvidence?
        if let vision, let jpeg = request.cropJPEG, let image = Self.decodeImage(jpeg) {
            evidence = try? await vision.analyse(crop: image)
        }

        // Stage 4, opt-in. A face in the crop stops the upload outright: that
        // is what makes the privacy copy literally true rather than nearly.
        var properties: LLMObjectProperties?
        if allowCloud, let llm, let jpeg = request.cropJPEG, evidence?.hasFace != true {
            let llmRequest = LLMObjectRequest(
                objectID: request.objectID,
                roomPlanCategory: request.roomPlanCategory,
                roomPlanAttributes: request.roomPlanAttributes,
                extents: request.extents,
                floorContact: request.baseHeightAboveFloor <= GeometryPrior.floorContactTolerance,
                roomKind: request.roomKind,
                jpeg: jpeg)
            properties = try? await llm.refine(llmRequest)
        }

        return Self.merge(
            request: request,
            geometry: geometry,
            vision: evidence,
            llm: properties,
            configuration: configuration)
    }

    /// The pure function at the centre of everything: given the four stages'
    /// outputs, produce the profile. No I/O, fully deterministic, and the thing
    /// the adversarial tests hammer.
    public static func merge(
        request: ClassificationRequest,
        geometry: GeometryPrior.Output,
        vision: VisionEvidence?,
        llm: LLMObjectProperties?,
        configuration: Configuration = .default
    ) -> ClassificationResult {
        let resolved = mergeType(
            geometry: geometry, vision: vision, llm: llm,
            roomPlanCategory: request.roomPlanCategory, configuration: configuration)
        let type = resolved.type

        // The catalogue's density priors already describe a *typically loaded*
        // example, so `.partial` reproduces the published mass exactly and is
        // the right assumption for a lived-in home. Only the user may say
        // otherwise; guessing "empty" would understate the hazard on precisely
        // the object most likely to kill someone.
        let assumedLoading = request.userLoading ?? .partial

        let prior = priorMass(type: type, extents: request.extents, loading: assumedLoading)
        let mass = mergeMass(
            prior: prior, llm: llm, configuration: configuration,
            envelope: type.massRange)

        let com = mergeCentreOfMassFraction(
            prior: type.centreOfMassFraction, llm: llm, configuration: configuration)

        // Geometry owns mounting, except inside the one genuinely ambiguous
        // band, and even there only when the model is confident.
        var mounting = geometry.mounting
        if GeometryPrior.mountingIsAmbiguous(request), let llm,
           llm.clampedConfidence >= configuration.typeConfidenceFloor,
           let suggested = Self.mounting(fromWireValue: llm.mounting) {
            mounting = suggested
        }

        // Open shelving always spills, whatever a photo suggests.
        let isOpenShelf = request.roomPlanAttributes
            .contains { $0.lowercased().contains("shelf") }
        let contentsCanFallOut = isOpenShelf
            || (llm?.contentsCanFallOut ?? type.hasSpillableContents)

        let containsGlass = llm?.containsGlass
            ?? (type.breakage != .none && type.breakage != .ceramic)

        let source: ClassificationSource
        if mass.source == .llmRefined || resolved.source == .llmRefined {
            source = .llmRefined
        } else if resolved.source == .onDeviceRefined {
            source = .onDeviceRefined
        } else {
            source = .prior
        }

        var disagreement: Double?
        if let llm, llm.hasFiniteNumbers, prior.kg > 0 {
            disagreement = abs(llm.massKgEstimate - prior.kg) / prior.kg
        }

        return ClassificationResult(
            objectID: request.objectID,
            type: type,
            provenance: IdentificationProvenance(
                source: source.provenanceSource,
                confidence: min(max(resolved.confidence, 0), 1),
                scannerCategory: request.roomPlanCategory),
            mass: MassEstimate(kg: mass.kg, low: mass.low, high: mass.high, source: source),
            centreOfMassFraction: com,
            mounting: mounting,
            loading: inferLoading(
                type: type, extents: request.extents, mass: mass.kg,
                userChoice: request.userLoading),
            material: llm?.materialPrimary ?? .unknown,
            secondaryMaterials: llm?.materialSecondary ?? [],
            fragility: mergeFragility(type: type, llm: llm),
            containsGlass: containsGlass,
            contentsCanFallOut: contentsCanFallOut,
            hints: geometry.hints,
            notes: llm?.notes.isEmpty == false ? llm?.notes : nil,
            modelTipOverRisk: llm?.tipOverRisk,
            priorDisagreement: disagreement,
            source: source)
    }

    /// The model's seven-case mounting enum onto our five-case one.
    /// `on_top_of_furniture` and `countertop` are both "free-standing on a
    /// raised support", which is a support height, not a mounting.
    public static func mounting(fromWireValue value: String) -> Mounting? {
        switch value {
        case "freestanding_floor", "on_top_of_furniture", "countertop": return .freestanding
        case "wall_mounted": return .wallMounted
        case "ceiling_suspended": return .suspended
        case "built_in_fixed": return .anchored
        default: return nil
        }
    }

    // MARK: - Whole-room pipeline

    /// Classifies every object, in parallel, with a concurrency cap.
    ///
    /// Objects are ranked by risk first — tall and slender, heavy, televisions,
    /// anything the scanner called `storage` — so the most consequential
    /// answers land first and the report's headline is right even if the tail
    /// times out. Nothing blocks on the slowest object.
    public func classify(
        room: ScannedRoom,
        crops: [UUID: Data],
        allowCloud: Bool,
        progress: @Sendable @escaping (UnderstandingProgress) -> Void
    ) async -> [UUID: ClassificationResult] {
        let requests = Self.rankedByRisk(room.objects).map {
            ClassificationRequest(object: $0, in: room, cropJPEG: crops[$0.id])
        }
        progress(.geometryComplete(objectCount: requests.count))

        var results: [UUID: ClassificationResult] = [:]
        var cloudAnswers = 0
        var budgetExpired = false
        let cap = max(1, configuration.maxConcurrentCloudRequests)

        // `roomBudget` was declared and then never read, so the knob a caller
        // sets did nothing. Per-request timeouts alone do not bound the room:
        // forty objects at eight-way concurrency is five waves, each of which
        // can burn a full `OpenAIClassifier.Configuration.timeout` plus its
        // backoffs. The budget stops *starting* new cloud calls once it is
        // spent; anything already in flight is bounded by its own timeout, and
        // every object that misses the window still returns its prior — which
        // is the whole point of the catalogue being the anchor.
        let deadline = Date().addingTimeInterval(max(configuration.roomBudget, 0))

        await withTaskGroup(of: ClassificationResult.self) { group in
            var issued = 0
            var inFlight = 0

            while issued < requests.count || inFlight > 0 {
                while inFlight < cap && issued < requests.count {
                    let request = requests[issued]
                    issued += 1
                    inFlight += 1
                    let withinBudget = allowCloud && Date() < deadline
                    if allowCloud && !withinBudget { budgetExpired = true }
                    group.addTask {
                        await self.classify(request, allowCloud: withinBudget)
                    }
                }
                if let result = await group.next() {
                    inFlight -= 1
                    results[result.objectID] = result
                    progress(.priorComplete(objectID: result.objectID, massKg: result.mass.kg))
                    switch result.source {
                    case .onDeviceRefined:
                        progress(.visionComplete(objectID: result.objectID, type: result.type))
                    case .llmRefined:
                        cloudAnswers += 1
                        progress(.cloudComplete(objectID: result.objectID, source: result.source))
                    case .prior, .userOverride:
                        break
                    }
                } else {
                    break
                }
            }
        }

        // One honest signal rather than a per-object error storm: if the cloud
        // was switched on and nothing came back, the UI shows a single
        // non-modal toast and everything still renders from prior-only data.
        if allowCloud && llm != nil && !requests.isEmpty && cloudAnswers == 0 {
            progress(.cloudUnavailable(reason: budgetExpired
                ? "Identification took too long, so proof used its own estimates."
                : "No object could be refined."))
        } else if budgetExpired {
            progress(.cloudUnavailable(reason:
                "Some objects used proof’s own estimates to keep things moving."))
        }

        progress(.finished)
        return results
    }

    /// Tall and slender first, then heavy, then televisions, then storage.
    public static func rankedByRisk(_ objects: [ScannedObject]) -> [ScannedObject] {
        objects.sorted { a, b in
            let sa = riskPriority(a), sb = riskPriority(b)
            if sa != sb { return sa > sb }
            return a.id.uuidString < b.id.uuidString   // stable, deterministic
        }
    }

    private static func riskPriority(_ object: ScannedObject) -> Double {
        var score = object.slenderness
        score += min(object.mass / 100, 2)
        if object.type == .television || object.type == .televisionWallMounted { score += 1 }
        if object.provenance.scannerCategory == "storage" { score += 1 }
        return score
    }

    // MARK: - Image decoding

    /// JPEG bytes to a `CGImage`, without going through UIKit — this file must
    /// remain usable from a background actor and from tests.
    static func decodeImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

// MARK: - Free text to catalogue type

/// Maps the model's free-text `object_type` onto the catalogue.
///
/// The schema deliberately asks for a natural name ("tall open bookshelf")
/// rather than one of our enum cases: constraining a vision model to an
/// unfamiliar 50-case vocabulary measurably degrades its reasoning, and it
/// invites casing drift (`tall_open_bookshelf` was observed from gpt-5-nano).
/// Matching afterwards, against a shortlist the geometry already vetted, gets
/// the accuracy without the brittleness — and a name that matches nothing
/// simply falls through to the next stage.
public enum ObjectTypeMatcher {

    /// Keywords per catalogue type, longest-first within a type so that
    /// "chest of drawers" beats a bare "chest".
    public static func keywords(for type: ObjectType) -> [String] {
        switch type {
        case .bookshelfTall, .bookshelfShort:
            return ["bookshelf", "bookcase", "book case", "book shelf", "shelving unit",
                    "shelf unit", "etagere", "shelving", "bookshelves"]
        case .wardrobe:
            return ["wardrobe", "armoire", "closet", "clothes cupboard"]
        case .dresser:
            return ["chest of drawers", "dresser", "chest-of-drawers", "bureau", "commode",
                    "drawer unit", "chest"]
        case .nightstand:
            return ["nightstand", "night stand", "bedside table", "bedside cabinet",
                    "night table"]
        case .highboy:
            return ["highboy", "tallboy", "tall chest", "tall dresser"]
        case .chinaCabinet:
            return ["china cabinet", "china hutch", "display cabinet", "curio cabinet",
                    "glass cabinet", "hutch", "dresser with glass"]
        case .filingCabinet:
            return ["filing cabinet", "file cabinet", "office cabinet"]
        case .kitchenCabinetUpper:
            return ["upper cabinet", "wall cabinet", "kitchen cabinet", "cupboard"]
        case .trunk: return ["trunk", "chest box", "blanket box", "toy box"]
        case .storageBin: return ["storage bin", "plastic bin", "crate", "basket"]
        case .desk: return ["desk", "writing table", "workstation"]
        case .diningTable: return ["dining table", "kitchen table", "dining-room table"]
        case .coffeeTable: return ["coffee table", "side table", "end table", "low table"]
        case .diningChair: return ["dining chair", "stool", "bench", "chair"]
        case .officeChair: return ["office chair", "desk chair", "swivel chair", "task chair"]
        case .sofa: return ["sofa", "couch", "settee", "loveseat"]
        case .armchair: return ["armchair", "recliner", "easy chair", "accent chair"]
        case .bed: return ["bed", "mattress", "bed frame"]
        case .crib: return ["crib", "cot", "cradle", "toddler bed"]
        case .television: return ["television", "flat-screen tv", "flat screen tv", "tv on stand",
                                  "tv", "flat-panel"]
        case .televisionWallMounted: return ["wall-mounted tv", "wall mounted tv", "wall-mounted television"]
        case .computerMonitor: return ["monitor", "computer monitor", "display screen"]
        case .speaker: return ["speaker", "loudspeaker", "subwoofer", "sound bar"]
        case .refrigerator: return ["refrigerator", "fridge", "freezer"]
        case .dishwasher: return ["dishwasher"]
        case .rangeElectric: return ["electric range", "electric stove", "induction hob",
                                     "electric cooker"]
        case .rangeGas: return ["gas range", "gas stove", "gas cooker", "range cooker"]
        case .oven: return ["oven", "wall oven", "built-in oven"]
        case .microwave: return ["microwave"]
        case .washingMachine: return ["washing machine", "washer"]
        case .clothesDryer: return ["dryer", "tumble dryer", "clothes dryer"]
        case .waterHeater: return ["water heater", "hot water cylinder", "boiler"]
        case .waterHeaterGas: return ["gas water heater"]
        case .sink: return ["sink", "basin", "washbasin"]
        case .toilet: return ["toilet", "wc", "lavatory"]
        case .bathtub: return ["bathtub", "bath tub", "bath"]
        case .fireplace: return ["fireplace", "hearth", "wood burner"]
        case .stairs: return ["stairs", "staircase", "steps"]
        case .floorLamp: return ["floor lamp", "standing lamp", "torchiere"]
        case .tableLamp: return ["table lamp", "desk lamp", "bedside lamp"]
        case .mirrorWall: return ["wall mirror", "hanging mirror"]
        case .mirrorLeaning: return ["leaning mirror", "full-length mirror", "floor mirror",
                                     "cheval mirror", "mirror"]
        case .framedPicture: return ["framed picture", "picture frame", "painting", "artwork",
                                     "photo frame"]
        case .vaseCeramic: return ["ceramic vase", "pottery", "urn", "vase"]
        case .vaseGlass: return ["glass vase"]
        case .plantPotLarge: return ["large plant", "potted tree", "planter"]
        case .plantPotSmall: return ["small plant", "potted plant", "houseplant", "plant"]
        case .books: return ["books", "stack of books"]
        case .aquarium: return ["aquarium", "fish tank"]
        case .pianoUpright: return ["piano", "upright piano"]
        case .unknown: return []
        }
    }

    /// Finds the best match for `freeText` **within the shortlist**.
    ///
    /// Ties are broken by shortlist order, which means geometry decides between
    /// members of a family the words cannot separate — "bookshelf" says nothing
    /// about tall versus low, but the bounding box already knows.
    public static func match(freeText: String, within shortlist: [ObjectType]) -> ObjectType? {
        guard !shortlist.isEmpty else { return nil }
        let haystack = freeText.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        guard !haystack.isEmpty else { return nil }

        var best: (type: ObjectType, score: Int, rank: Int)?
        for (rank, type) in shortlist.enumerated() {
            var score = 0
            for keyword in keywords(for: type) where haystack.contains(keyword) {
                // Longer phrases are more specific evidence, so they win:
                // "chest of drawers" must beat "chest".
                score = max(score, keyword.count)
            }
            guard score > 0 else { continue }
            if let current = best {
                if score > current.score || (score == current.score && rank < current.rank) {
                    best = (type, score, rank)
                }
            } else {
                best = (type, score, rank)
            }
        }
        return best?.type
    }
}
