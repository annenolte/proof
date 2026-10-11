import Foundation

/// Stage 1: what the bounding box alone already tells us.
///
/// This runs before any machine learning, and it is the safety net for when the
/// rest of the pipeline is unavailable. Two findings drive its design:
///
/// * **Geometry beats ML wherever geometry can answer.** `mounting` derived
///   from LiDAR is right essentially always; the language model contradicted
///   itself on the *same photograph*, calling a television `wall_mounted` in
///   one run and `on_top_of_furniture` in the next (research §7.3). So we never
///   ask a model for something the depth sensor already knows.
/// * **RoomPlan's `storage` category is useless on its own** — it covers a
///   bookcase, a dresser, a wardrobe, a TV unit and a filing cabinet, a 3×
///   spread in mass on the same box. But those five differ *dimensionally* in
///   ways anyone can write down: a 1.9 m tall, 0.3 m deep unit is a bookcase,
///   not a dresser. Encoding that explicitly is free, instant and offline.
///
/// The output is a *ranked shortlist*, never a single answer. Later stages
/// choose from the shortlist rather than from the full 50-type taxonomy, which
/// is what stops a model renaming a sofa into a wardrobe.
public enum GeometryPrior {

    // MARK: - Output

    public struct Output: Sendable, Equatable {
        /// Authoritative. The language model may only break a tie inside the
        /// 5–15 cm ambiguity band, and even then only when it is confident.
        public var mounting: Mounting
        /// Ranked, always at least one entry.
        public var shortlist: [ObjectType]
        /// Human-readable reasons, shown in the object detail sheet so the app
        /// can explain itself rather than assert.
        public var hints: [String]
        /// Height ÷ the larger horizontal dimension. Above ~2.5 an object is an
        /// anchor-it candidate whatever it turns out to be.
        public var aspect: Double
        /// w × d, m².
        public var footprint: Double
        /// Below RealityKit's contact margin — merge into its host and exclude
        /// it from the 3D stage.
        public var isTooSmallToSimulate: Bool
        /// How much the dimensions alone pin the type down, 0…1. Used as the
        /// provenance confidence when nothing else runs.
        public var confidence: Double

        /// The best guess, which is always defined.
        public var bestGuess: ObjectType { shortlist.first ?? .unknown }
    }

    // MARK: - Thresholds
    //
    // Every number here is from research §2.6 / SPEC §5.2 and is deliberately a
    // named constant rather than a literal buried in a branch, because these
    // are the values that will need tuning against real scans.

    /// Base-to-floor gap below which an object is standing on the floor.
    public static let floorContactTolerance = 0.05
    /// Base-to-floor gap above which an object with no host must be hung.
    public static let wallMountedMinimumBase = 0.40
    /// Wall-hung objects are shallow.
    public static let wallMountedMaximumDepth = 0.25
    /// …and their back face is close to a wall plane.
    public static let wallProximity = 0.15
    /// Countertop band.
    public static let counterHeightBand = 0.80...1.20
    /// Slenderness above which anything free-standing is worth anchoring.
    public static let anchorCandidateAspect = 2.5
    /// Any dimension below this is below RealityKit's contact margin.
    public static let minimumSimulableDimension = 0.02

    /// The scanner categories that are plumbed or built in and cannot move,
    /// whatever their dimensions say.
    public static let fixtureCategories: Set<String> = [
        "sink", "toilet", "bathtub", "dishwasher", "oven", "fireplace", "stairs",
    ]

    // MARK: - Entry points

    public static func evaluate(_ request: ClassificationRequest) -> Output {
        let e = request.extents
        let w = Double(e.width), h = Double(e.height), d = Double(e.depth)
        let footprint = w * d
        let aspect = h / max(w, d)
        var hints: [String] = []

        let mounting = resolveMounting(request, hints: &hints)
        let shortlist = resolveShortlist(request, hints: &hints)

        if mounting == .freestanding && request.baseHeightAboveFloor <= floorContactTolerance
            && aspect > anchorCandidateAspect {
            hints.append(
                "Tall and narrow for its base — worth anchoring whatever it turns out to be.")
        }

        let tooSmall = min(w, min(h, d)) < minimumSimulableDimension

        return Output(
            mounting: mounting,
            shortlist: shortlist,
            hints: hints,
            aspect: aspect,
            footprint: footprint,
            isTooSmallToSimulate: tooSmall,
            confidence: confidence(for: shortlist, category: request.roomPlanCategory))
    }

    public static func evaluate(object: ScannedObject, in room: ScannedRoom) -> Output {
        evaluate(ClassificationRequest(object: object, in: room))
    }

    // MARK: - Mounting

    /// Rules in priority order, exactly as SPEC §5.2 lists them.
    ///
    /// Note that the shipped `Mounting` enum has five cases, not the seven the
    /// language model's schema uses: `on_top_of_furniture` and `countertop` are
    /// both *free-standing on a raised support*, which is a `supportHeight` on
    /// `ScannedObject`, not a distinct mounting. `built_in_fixed` maps to
    /// `.anchored`.
    private static func resolveMounting(
        _ request: ClassificationRequest, hints: inout [String]
    ) -> Mounting {
        let base = request.baseHeightAboveFloor
        let depth = Double(request.extents.depth)

        if fixtureCategories.contains(request.roomPlanCategory) {
            hints.append("Plumbed or built in, so it cannot move.")
            return .anchored
        }
        if base <= floorContactTolerance {
            return .freestanding
        }
        if request.hasHostBelow {
            hints.append(
                String(format: "Standing on something %.2f m above the floor, so it can slide off.",
                       base))
            return .freestanding
        }
        if request.nearCounterFixture && counterHeightBand.contains(base) {
            hints.append("On a worktop.")
            return .freestanding
        }
        if base >= wallMountedMinimumBase && depth < wallMountedMaximumDepth
            && (request.distanceToNearestWall ?? .greatestFiniteMagnitude) < wallProximity {
            hints.append("Hung on the wall — it fails by its fixing pulling out, not by tipping.")
            return .wallMounted
        }
        if base >= wallMountedMinimumBase && depth < wallMountedMaximumDepth {
            // Off the floor, shallow, no host, no wall evidence. Hanging is the
            // only physical explanation left.
            hints.append("Off the floor with nothing under it — treated as wall-mounted.")
            return .wallMounted
        }
        // 5–15 cm off the floor with nothing else to go on: the one genuinely
        // ambiguous band, and the only place the language model is allowed a
        // say (SPEC §5.1).
        return .freestanding
    }

    /// True inside the narrow band where the model may override geometry.
    public static func mountingIsAmbiguous(_ request: ClassificationRequest) -> Bool {
        let base = request.baseHeightAboveFloor
        return base > floorContactTolerance && base < wallProximity && !request.hasHostBelow
    }

    // MARK: - Shortlist

    /// The dimensional heuristics. These are the whole point of this file.
    private static func resolveShortlist(
        _ request: ClassificationRequest, hints: inout [String]
    ) -> [ObjectType] {
        let e = request.extents
        let w = Double(e.width), h = Double(e.height), d = Double(e.depth)
        let footprint = w * d
        let candidates = ObjectType.candidates(forRoomPlanCategory: request.roomPlanCategory)
        let attributes = Set(request.roomPlanAttributes.map { $0.lowercased() })

        var ranked: [ObjectType]

        switch request.roomPlanCategory {
        case "storage":
            ranked = storageShortlist(
                width: w, height: h, depth: d, footprint: footprint,
                attributes: attributes, room: request.roomKind, hints: &hints)

        case "television":
            // A flat panel is a panel: its mass comes from screen area, not
            // from a volume that is mostly empty air behind it.
            if d < 0.15 {
                hints.append("Flat panel — mass estimated from screen area, not from volume.")
                ranked = request.baseHeightAboveFloor >= wallMountedMinimumBase
                    && !request.hasHostBelow
                    ? [.televisionWallMounted, .television, .computerMonitor]
                    : [.television, .computerMonitor, .televisionWallMounted]
            } else {
                ranked = [.television, .computerMonitor]
            }
            if w < 0.65 { ranked = [.computerMonitor] + ranked.filter { $0 != .computerMonitor } }

        case "table":
            if h < 0.55 {
                hints.append("Low enough to be a coffee table.")
                ranked = [.coffeeTable, .diningTable, .desk]
            } else if h < 0.70 && footprint < 0.40 {
                ranked = [.nightstand, .coffeeTable, .desk]
            } else if d > 0.60 && w > 1.20 {
                ranked = [.diningTable, .desk, .coffeeTable]
            } else {
                ranked = [.desk, .diningTable, .coffeeTable]
            }

        case "chair":
            ranked = h > 0.95 ? [.officeChair, .diningChair, .armchair]
                              : [.diningChair, .officeChair, .armchair]

        case "sofa":
            ranked = w < 1.20 ? [.armchair, .sofa] : [.sofa, .armchair]

        case "bed":
            ranked = (w < 0.90 && d < 1.50) ? [.crib, .bed] : [.bed, .crib]

        case "washerDryer":
            ranked = [.washingMachine, .clothesDryer]

        case "stove", "oven":
            // Gas ranges are heavier and carry a legally mandated anti-tip
            // bracket, so when we cannot tell we assume gas: it is the
            // conservative direction for a safety app.
            ranked = candidates

        default:
            ranked = candidates
        }

        // Anything genuinely tiny is decor, not furniture, whatever the
        // scanner called it.
        if max(w, max(h, d)) < 0.12 && ranked.first != .unknown {
            hints.append("Small enough to be a loose object rather than furniture.")
        }

        if ranked.isEmpty { ranked = candidates }
        if ranked.isEmpty { ranked = [.unknown] }
        return ranked
    }

    /// The one that actually matters.
    ///
    /// | Signal | Verdict |
    /// |---|---|
    /// | h ≥ 1.40, d < 0.45 | tall + shallow → **bookcase** |
    /// | h ≥ 1.50, d ≥ 0.50 | tall + deep → **wardrobe** (it has to hold a coat hanger, which is 0.5 m across) |
    /// | h ≥ 1.40, d 0.45–0.50 | tall + medium → **tall chest of drawers** |
    /// | h 0.70–1.40, d ≥ 0.40 | waist-high + deep → **dresser** |
    /// | h 0.70–1.40, d < 0.40 | waist-high + shallow → low bookcase |
    /// | h < 0.70, footprint > 0.5 | low + wide → TV unit / sideboard |
    /// | h < 0.70, small | → nightstand / bin |
    ///
    /// The wardrobe/bookcase split on depth is the load-bearing one: a wardrobe
    /// must be deep enough for a hanger (≈ 0.55 m) and a bookcase deep enough
    /// only for a book (≈ 0.30 m). That single number separates a 110 kg/m³
    /// archetype from a 200 kg/m³ one.
    private static func storageShortlist(
        width w: Double, height h: Double, depth d: Double, footprint: Double,
        attributes: Set<String>, room: RoomKind, hints: inout [String]
    ) -> [ObjectType] {
        let isShelf = attributes.contains { $0.contains("shelf") }
        let isCabinet = attributes.contains { $0.contains("cabinet") }
        var ranked: [ObjectType]

        if h >= 1.40 {
            if d >= 0.50 {
                hints.append(String(
                    format: "%.2f m tall and %.2f m deep — deep enough to hang clothes in.", h, d))
                ranked = [.wardrobe, .highboy, .chinaCabinet, .bookshelfTall]
            } else if d >= 0.45 {
                hints.append(String(format: "%.2f m tall and %.2f m deep — a tall chest.", h, d))
                ranked = [.highboy, .wardrobe, .bookshelfTall, .chinaCabinet]
            } else {
                hints.append(String(
                    format: "%.2f m tall but only %.2f m deep — too shallow for clothes, so shelving.",
                    h, d))
                ranked = [.bookshelfTall, .chinaCabinet, .wardrobe, .highboy]
            }
        } else if h >= 0.70 {
            if d >= 0.40 {
                hints.append(String(
                    format: "Waist-high at %.2f m and %.2f m deep — drawer proportions.", h, d))
                ranked = w < 0.60
                    ? [.filingCabinet, .dresser, .nightstand, .trunk]
                    : [.dresser, .filingCabinet, .bookshelfShort, .trunk]
            } else {
                hints.append(String(format: "Waist-high at %.2f m and shallow — open shelving.", h))
                ranked = [.bookshelfShort, .bookshelfTall, .dresser]
            }
        } else {
            if footprint > 0.50 {
                hints.append("Low and wide — a media unit or sideboard.")
                ranked = [.bookshelfShort, .trunk, .dresser]
            } else if w < 0.70 && d < 0.60 {
                hints.append("Small and low — a bedside or a box.")
                ranked = [.nightstand, .storageBin, .trunk]
            } else {
                ranked = [.storageBin, .trunk, .bookshelfShort]
            }
        }

        // RoomPlan's only storage sub-attribute, used as a tie-break rather
        // than as a verdict: `shelf` means open shelving, `cabinet` means doors.
        if isShelf {
            ranked = ranked.stablePartition { $0 == .bookshelfTall || $0 == .bookshelfShort }
        } else if isCabinet {
            ranked = ranked.stablePartition {
                $0 == .wardrobe || $0 == .chinaCabinet || $0 == .kitchenCabinetUpper
                    || $0 == .filingCabinet
            }
        }

        // A room prior is weak but free: a bedside table in a bedroom is a
        // nightstand; the same box in an office is a filing cabinet.
        switch room {
        case .bedroom, .nursery:
            ranked = ranked.stablePartition { $0 != .filingCabinet }
        case .office:
            ranked = ranked.stablePartition { $0 != .nightstand }
        default:
            break
        }

        return ranked
    }

    // MARK: - Confidence

    /// How much the dimensions alone pin the answer down. A one-entry shortlist
    /// from an unambiguous category is near-certain; the eleven-way `storage`
    /// split narrowed to four is not.
    private static func confidence(for shortlist: [ObjectType], category: String) -> Double {
        if shortlist == [.unknown] { return 0.25 }
        let breadth = ObjectType.candidates(forRoomPlanCategory: category).count
        switch shortlist.count {
        case 1: return breadth <= 1 ? 0.90 : 0.72
        case 2: return 0.62
        case 3: return 0.55
        default: return 0.48
        }
    }
}

private extension Array {
    /// Moves every element matching `predicate` to the front, preserving the
    /// relative order of both groups. Used so a tie-break re-ranks the
    /// shortlist without ever discarding a candidate.
    func stablePartition(_ predicate: (Element) -> Bool) -> [Element] {
        filter(predicate) + filter { !predicate($0) }
    }
}
