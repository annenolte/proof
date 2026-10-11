import CoreGraphics
import Foundation
import Vision

/// Stage 2: the free, offline, ~50 ms classifier.
///
/// iOS ships no general object *detector* — `RecognizeObjectsRequest` does not
/// exist and never has. It does not need to: RoomPlan already localises every
/// object in 3D at 91 % precision / 90 % recall, so all we need is a classifier
/// on the crop, which removes the entire YOLO/AGPL/model-size problem.
public protocol VisionClassifying: Sendable {
    /// Never throws for a per-object failure the caller can survive; throwing
    /// means the image itself was unusable.
    func analyse(crop: CGImage) async throws -> VisionEvidence
}

/// `ClassifyImageRequest` + `RecognizeTextRequest` + a face guard, all in one
/// pass over the image.
public struct OnDeviceVision: VisionClassifying {

    /// The precision/recall gate. `ClassifyImageRequest` is multi-label and its
    /// raw confidences are *not* calibrated across labels, so an ungated top-1
    /// on furniture crops is noise. This gate is the difference between a
    /// usable signal and no signal (research §2.2).
    public var minimumPrecision: Float
    public var atRecall: Float
    public var maximumLabels: Int
    /// Allow-list. Everything outside it is discarded even if confident.
    public var allowedLabels: Set<String>
    /// Run the face detector before anything is uploaded.
    public var detectsFaces: Bool

    public init(
        minimumPrecision: Float = 0.6,
        atRecall: Float = 0.3,
        maximumLabels: Int = 5,
        allowedLabels: Set<String> = OnDeviceVision.furnitureLabels,
        detectsFaces: Bool = true
    ) {
        self.minimumPrecision = minimumPrecision
        self.atRecall = atRecall
        self.maximumLabels = maximumLabels
        self.allowedLabels = allowedLabels
        self.detectsFaces = detectsFaces
    }

    public func analyse(crop: CGImage) async throws -> VisionEvidence {
        let handler = ImageRequestHandler(crop, orientation: .up)

        var classify = ClassifyImageRequest()
        // Furniture is not square; centre-cropping a 2 m bookcase to a square
        // throws away the part that tells you it is a bookcase.
        classify.cropAndScaleAction = .scaleToFit

        var ocr = RecognizeTextRequest()
        ocr.recognitionLevel = .fast          // we want a nameplate, not prose
        ocr.minimumTextHeightFraction = 0.03
        ocr.usesLanguageCorrection = false

        let faces = DetectFaceRectanglesRequest()

        // One variadic perform → both models run in a single pass.
        let (labels, text, faceObservations) = try await handler.perform(classify, ocr, faces)

        let gated = labels
            .filter { $0.hasMinimumPrecision(minimumPrecision, forRecall: atRecall) }
            .filter { allowedLabels.contains($0.identifier) }
            .prefix(maximumLabels)
            .map { LabelledConfidence(label: $0.identifier, confidence: Double($0.confidence)) }

        let strings = text
            .compactMap { $0.topCandidates(1).first?.string }
            .filter { $0.count >= 3 }

        return VisionEvidence(
            labels: Array(gated),
            ocrStrings: strings,
            hasFace: detectsFaces && !faceObservations.isEmpty)
    }

    /// Logged on first launch and never hard-coded into a decision: the
    /// published 1303-label list is `revision1` while the Swift API exposes
    /// `revision2`, so if `dresser` ever appears the mapping below should widen
    /// on its own rather than by a code change.
    public static func supportedIdentifiers() -> [String] {
        ClassifyImageRequest().supportedIdentifiers
    }

    // MARK: - The allow-list

    /// Identifiers that are meaningful for furniture triage. Everything else in
    /// the ~1300-label taxonomy is noise for our purposes.
    public static let furnitureLabels: Set<String> = [
        "furniture", "bookshelf", "cabinet", "table", "desk", "chair", "chair_other",
        "armchair", "swivel_chair", "folding_chair", "high_chair", "stool", "bench",
        "sofa", "bed", "bedding", "television", "computer_monitor", "monitor",
        "speakers_music", "lamp", "clock", "curtain", "frame", "vase",
        "decorative_plant", "plant", "piano", "electric_fan", "refrigerator", "oven",
        "kitchen_oven", "brick_oven", "toaster_oven", "stove", "microwave",
        "dishwasher", "kitchen_sink", "bathroom_faucet", "toilet_seat", "bath",
        "turntable", "computer", "computer_keyboard", "computer_tower", "aquarium",
        "mirror", "fireplace", "stairs",
    ]

    // MARK: - Label → catalogue mapping
    //
    // Deliberately *not* a data file in v1: the taxonomy is fixed by the OS and
    // the catalogue is fixed by us, so a compile-time table is checkable by the
    // compiler and by tests. The notable holes — `dresser`, `wardrobe`,
    // `nightstand`, `chest_of_drawers`, `sideboard`, `TV_stand` — are absent
    // from the OS taxonomy entirely, and a dresser is the single most-reported
    // furniture tip-over fatality object. That gap is precisely why the cloud
    // stage exists.

    /// Catalogue types a Vision identifier is evidence for, best first.
    public static func objectTypes(forVisionLabel label: String) -> [ObjectType] {
        switch label {
        case "bookshelf": return [.bookshelfTall, .bookshelfShort]
        case "cabinet": return [.wardrobe, .chinaCabinet, .filingCabinet, .kitchenCabinetUpper,
                                .dresser]
        case "table": return [.diningTable, .coffeeTable, .desk, .nightstand]
        case "desk": return [.desk, .diningTable]
        case "chair", "chair_other", "folding_chair", "high_chair": return [.diningChair]
        case "swivel_chair": return [.officeChair]
        case "armchair": return [.armchair]
        case "stool", "bench": return [.diningChair]
        case "sofa": return [.sofa, .armchair]
        case "bed", "bedding": return [.bed, .crib]
        case "television": return [.television, .televisionWallMounted]
        case "computer_monitor", "monitor": return [.computerMonitor]
        case "speakers_music": return [.speaker]
        case "lamp": return [.floorLamp, .tableLamp]
        case "frame": return [.framedPicture]
        case "mirror": return [.mirrorWall, .mirrorLeaning]
        case "vase": return [.vaseCeramic, .vaseGlass]
        case "decorative_plant", "plant": return [.plantPotLarge, .plantPotSmall]
        case "piano": return [.pianoUpright]
        case "refrigerator": return [.refrigerator]
        case "oven", "kitchen_oven", "brick_oven", "toaster_oven": return [.oven]
        case "stove": return [.rangeElectric, .rangeGas]
        case "microwave": return [.microwave]
        case "dishwasher": return [.dishwasher]
        case "kitchen_sink": return [.sink]
        case "toilet_seat": return [.toilet]
        case "bath": return [.bathtub]
        case "aquarium": return [.aquarium]
        case "fireplace": return [.fireplace]
        case "stairs": return [.stairs]
        case "clock", "curtain", "computer", "computer_keyboard", "computer_tower",
             "turntable", "electric_fan", "bathroom_faucet", "furniture":
            // Real labels, but none of them narrows the catalogue usefully.
            return []
        default: return []
        }
    }

    /// Folds the on-device evidence into the geometry shortlist.
    ///
    /// The shortlist wins on *ordering within a family* — Vision cannot tell a
    /// tall bookcase from a low one, but the bounding box can and already did.
    /// Vision wins on *which family*, which is the thing a box cannot see.
    ///
    /// - Returns: the refined type and a confidence, or nil when the evidence
    ///   said nothing about anything on the shortlist.
    public static func refine(
        shortlist: [ObjectType], with evidence: VisionEvidence
    ) -> (type: ObjectType, confidence: Double)? {
        guard !shortlist.isEmpty else { return nil }
        let shortlistSet = Set(shortlist)

        for label in evidence.labels.sorted(by: { $0.confidence > $1.confidence }) {
            let mapped = objectTypes(forVisionLabel: label.label)
            guard !mapped.isEmpty else { continue }
            let intersection = shortlist.filter { mapped.contains($0) }
            if let best = intersection.first {
                // Vision agreed with something geometry already allowed. The
                // confidence is the model's own, floored so a weak-but-agreeing
                // label still beats geometry alone, and capped because a
                // single-label multi-label classifier is not proof.
                return (best, min(max(label.confidence, 0.55), 0.80))
            }
            // Vision named a family geometry did not list. That happens when
            // the scanner's category was wrong — trust Vision's family but
            // stay inside what the box can support.
            if let fallback = mapped.first, !shortlistSet.contains(fallback) {
                return (fallback, min(max(label.confidence * 0.8, 0.45), 0.65))
            }
        }
        return nil
    }
}

/// A vision stage that is always unavailable. Used on devices without the
/// framework, in tests, and whenever the crop pipeline produced nothing —
/// which must degrade to geometry + catalogue, never to an error.
public struct NoVision: VisionClassifying {
    public init() {}
    public func analyse(crop: CGImage) async throws -> VisionEvidence { .empty }
}
