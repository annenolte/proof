import Foundation
import simd

// Turns a finished demo earthquake into a structured safety report.
//
// This file exists because the payoff of the whole flow is not "you watched your sofa
// move" — it is "here is what is dangerous, here is what to do about it, and here is a
// number you can act on". That has to be *derived*, and every line of it has to trace
// back to something the simulation actually produced.
//
// The division of labour matters, and it is the same two-track rule the shipping product
// follows (see docs/handoff/01-CURRENT-STATE.md §4):
//
//   * `DemoQuake` decides **what happened**. It ran a real Clough–Penzien accelerogram
//     through a real rigid-body solver and recorded which props toppled, slid or broke,
//     and when. Nothing in this file re-litigates that verdict or invents a new one.
//   * `ApartmentScene` holds **where everything ended up**: each prop's rest transform and
//     its live transform, so displacement is measured rather than guessed.
//   * This file **presents** the two. It ranks, scores, explains, and attaches the fix.
//
// Where a threshold or a piece of advice is needed it comes from the frozen Core modules —
// `RiskBand` for the four-step ramp and its vocabulary, `MitigationLibrary` for the FEMA
// E-74 fixes and their real hardware, times and references. No seismic physics is invented
// here, and no advice is written here.
//
// The one thing this file does author is the *weighting*: how much a given outcome ought
// to count against a room. Those weights are named constants in `Weight` below, each with
// the reason it has the value it has. They are a presentation policy, not a physical
// claim, and they are documented as such.

// MARK: - A single finding

/// One object, one verdict. The unit the report is built out of.
struct RoomFinding: Identifiable, Equatable {

    /// The prop's stable scene id, so a row can be tied back to the 3D object.
    let id: String
    /// The name the room itself uses — "Ladder shelf", "Wine glass".
    let name: String
    let category: DemoProp.Category

    /// The frozen four-step band. Reused rather than reinvented so the demo speaks the
    /// same language as the shipping findings screens.
    let band: RiskBand
    /// 0–100, this object's risk. Higher is worse, matching `RiskBand(score:)`.
    let score: Int

    /// What the simulation observed. "Toppled and travelled 1.4 m, ending within reach of
    /// the sofa."
    let outcome: String
    /// One plain sentence naming the properties that caused it.
    let why: String
    /// The concrete fix — the title of a real `Mitigation` from `Core/Advice`.
    let action: String
    /// How long that fix takes, from the same `Mitigation`.
    let effortMinutes: Int

    /// Straight-line horizontal travel from where it was placed, in metres.
    let displacementMetres: Double
    /// The prop's authored mass, in kilograms.
    let massKg: Double

    /// Seconds after onset at which it failed.
    let timeSeconds: Double
    /// Toppled / slid / broke, kept so the view can pick a glyph without parsing prose.
    let kind: DemoQuake.Displacement.Kind
    /// True when the object came to rest within arm's reach of somewhere a person sits or
    /// stands. This is the single biggest term in both scores, so it is exposed.
    let reachesOccupiedSpace: Bool
    /// The full mitigation, so the expanded row can show the steps, the hardware and the
    /// FEMA reference without this file paraphrasing any of it.
    let mitigation: Mitigation

    static func == (a: RoomFinding, b: RoomFinding) -> Bool { a.id == b.id && a.score == b.score }
}

/// An object that came through the shaking unmoved. Reporting these is not padding: a
/// report that only ever lists hazards reads as fear-mongering, and a user who is told
/// everything is dangerous learns to ignore all of it.
struct RoomSurvivor: Identifiable, Equatable {
    let id: String
    let name: String
    let category: DemoProp.Category
    let massKg: Double
    /// Why it held — "Low and heavy, 62 kg over a 0.92 m base."
    let note: String
}

// MARK: - The room's headline band

/// The three-step band on the room score. Deliberately *not* `RiskBand`: this number runs
/// the other way (higher is safer) and a user reading "Severe" next to a big number would
/// have to invert it in their head.
enum RoomSafetyBand: String, CaseIterable, Identifiable {
    case needsWork, reasonable, wellSecured

    var id: String { rawValue }

    var title: String {
        switch self {
        case .needsWork: return "Needs work"
        case .reasonable: return "Reasonable"
        case .wellSecured: return "Well secured"
        }
    }

    var detail: String {
        switch self {
        case .needsWork:
            return "Several things in here would move far enough to hurt someone or block the way out."
        case .reasonable:
            return "The big pieces held. What moved is worth an afternoon."
        case .wellSecured:
            return "Nothing here would put someone in hospital. Keep it that way."
        }
    }

    var symbolName: String {
        switch self {
        case .needsWork: return "exclamationmark.triangle.fill"
        case .reasonable: return "hand.raised.fill"
        case .wellSecured: return "checkmark.seal.fill"
        }
    }

    /// The colour band the score is drawn in. The dial is a `RiskBand` component, so the
    /// safety score is mirrored back into risk space for it: 82 safe ⇒ 18 risk ⇒ low.
    var riskEquivalent: RiskBand {
        switch self {
        case .wellSecured: return .low
        case .reasonable: return .moderate
        case .needsWork: return .high
        }
    }

    init(safetyScore: Int) {
        switch safetyScore {
        case ..<55: self = .needsWork
        case ..<80: self = .reasonable
        default: self = .wellSecured
        }
    }
}

// MARK: - The model

/// Everything the analysis screen shows, derived once from the quake and the scene.
///
/// It is a value, built in a single pass, and it holds no references to the scene beyond
/// the numbers it read out of it — so it can be handed to a share sheet, a snapshot test
/// or a preview without dragging RealityKit along.
@MainActor
struct RoomAnalysisModel {

    // MARK: Inputs, as reported

    let roomName: String
    /// False when the earthquake has not finished. The screen has a real empty state for
    /// this rather than showing a report full of zeroes.
    let didRun: Bool
    let intensity: MercalliIntensity
    /// Peak horizontal ground acceleration actually reached, in g. Measured by `DemoQuake`
    /// as the record played, not looked up from the intensity bin.
    let peakAccelerationG: Double
    /// How long the record ran, in seconds.
    let durationSeconds: Double

    // MARK: Derived

    /// Everything that moved, worst first.
    let findings: [RoomFinding]
    /// `.severe` and `.high` — the "Move these first" section.
    let urgent: [RoomFinding]
    /// `.moderate` and `.low` — the "Also worth doing" section.
    let secondary: [RoomFinding]
    /// Movable objects that did not move, most consequential first.
    let survivors: [RoomSurvivor]
    /// How many movable objects there were in total, so "9 of 47 moved" is sayable.
    let movableCount: Int

    let toppledCount: Int
    let slidCount: Int
    let brokeCount: Int

    /// 0–100, **higher is safer**.
    let safetyScore: Int
    let band: RoomSafetyBand
    /// One sentence naming what dominates the score.
    let headline: String
    /// Total time to work through every fix listed, in minutes.
    let totalEffortMinutes: Int
    /// One entry per distinct fix, best value first. See `RetrofitOption`.
    let retrofit: [RetrofitOption]

    // MARK: - Weighting policy
    //
    // These are presentation weights, not physics. They answer "how much should this count
    // against the room", which is a judgement, and they are gathered here so the judgement
    // is inspectable in one place instead of scattered through string interpolation.

    private enum Weight {
        /// Outcome floors. Toppling leads because a piece that comes over lands on
        /// something; breakage is close behind because it is the outcome you cannot undo
        /// by standing the object back up; sliding is real but recoverable.
        static let toppled = 0.70
        static let broke = 0.60
        static let slid = 0.30
        /// How far a slide has to go before it collects the whole `slid` floor. 0.30 m is
        /// the point at which an object has left the footprint it was standing on — below
        /// it the object is still, recognisably, where you put it.
        static let slidReference = 0.30

        /// Travel adds up to this much, saturating at `travelReference` metres. Something
        /// that crossed the room is a different event from something that shuffled.
        ///
        /// Raised from 0.14/1.5 m after a table lamp that travelled 1.8 m came back
        /// **Low**. Distance is the one term a reader can check against what they just
        /// watched, so a report whose bands ignore it loses the argument on sight; and
        /// 1.5 m saturated so early that "slid 1.5 m" and "slid 2.4 m" scored identically.
        static let travel = 0.24
        static let travelReference = 2.4

        /// Height adds up to this much, saturating at `heightReference` metres — the
        /// fall-height term, in the same spirit as the frozen engine's f₃.
        static let height = 0.10
        static let heightReference = 2.0

        /// Coming to rest within reach of a person is the single largest modifier, which
        /// is the frozen engine's occupant-exposure factor (f₂, weight 0.22) expressed in
        /// the only way this demo can measure it.
        static let reach = 0.18

        /// Mass scales the whole thing rather than adding to it, because a shattered
        /// tumbler and a toppled bookcase are the same *event* at wildly different
        /// consequence. Below `massReference` the score is scaled down toward `massFloor`.
        static let massFloor = 0.42
        static let massReference = 40.0

        /// How far from a seat or a standing position still counts as "reaches them":
        /// arm's length plus a step.
        static let reachRadiusMetres: Float = 1.0

        /// The most of its own footprint an object may discount when its distance to a
        /// seat is measured.
        ///
        /// Reach is measured edge-to-edge rather than centre-to-centre, which is right for
        /// a lamp and absurd for a sofa: subtracting a 1.05 m half-length made *every*
        /// large piece "within reach" of something, and every large piece therefore
        /// collected the biggest modifier in the model. Capping the discount at a hand's
        /// span keeps the edge-to-edge intent without letting size buy exposure.
        static let reachEdgeAllowance: Float = 0.30

        /// Exposure multiplier applied to a finding's contribution to the room score when
        /// it ended up within reach of someone.
        static let occupiedExposure = 1.6

        /// The room score halves for every this-much accumulated hazard load. A single
        /// severe finding beside the sofa costs roughly a third of the score; a room full
        /// of shuffled crockery costs a few points.
        static let halvingLoad = 2.5

        /// A report that reads 0 is not information. The floor keeps the number honest at
        /// the bad end without pretending the room is salvageable.
        static let minimumSafetyScore = 4
    }

    /// Below this slenderness (height ÷ narrowest base dimension) an object is squat
    /// enough that sliding, not toppling, is its failure mode — the same distinction
    /// Shenton's mode selection makes in the frozen solver.
    private static let slendernessThreshold = 2.2

    /// Objects lighter than this are hand-held things; the copy calls them out differently
    /// from furniture.
    private static let handHeldMassKg = 3.0

    /// A thing has to clear this before slenderness earns it the phrase "tall and narrow".
    /// 0.45 m is roughly the height at which an object stops being something you set down
    /// and starts being something that can fall *onto* you.
    private static let tallEnoughMetres = 0.45

    /// How many survivors to name before collapsing the rest into a count.
    private static let survivorsShown = 6

    // MARK: - Construction

    init(roomName: String, quake: DemoQuake, scene: ApartmentScene?) {
        self.roomName = roomName
        self.intensity = quake.intensity
        self.peakAccelerationG = quake.peakAccelerationG
        self.durationSeconds = quake.duration
        self.didRun = quake.state == .finished

        self.toppledCount = quake.toppledCount
        self.slidCount = quake.slidCount
        self.brokeCount = quake.brokeCount

        let props = scene?.props ?? [:]
        self.movableCount = props.values.filter(\.isMovable).count

        // ── Findings, one per object the quake recorded ─────────────────────────────
        var built: [RoomFinding] = []
        for event in quake.displaced {
            guard let prop = props[event.propID] else { continue }
            built.append(Self.finding(for: event, prop: prop, in: props))
        }
        built.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.name < $1.name
        }
        self.findings = built
        self.urgent = built.filter { $0.band >= .high }
        self.secondary = built.filter { $0.band < .high }
        self.totalEffortMinutes = built.reduce(0) { $0 + $1.effortMinutes }

        // ── Survivors, for the "What held up" section ───────────────────────────────
        let moved = Set(quake.displaced.map(\.propID))
        let stayed = props.values
            .filter { $0.isMovable && !moved.contains($0.id) }
            // Most consequential first: what could have hurt someone and did not. Mass ×
            // height is the crude stand-in for potential energy, which is exactly what the
            // reassurance is about.
            .sorted { Self.consequencePotential($0) > Self.consequencePotential($1) }
        self.survivors = stayed.prefix(Self.survivorsShown).map(Self.survivor(for:))

        // ── The room score ──────────────────────────────────────────────────────────
        let score = Self.safetyScore(for: built)
        self.safetyScore = score
        self.band = RoomSafetyBand(safetyScore: score)
        self.retrofit = RetrofitOption.ranked(findings: built, currentScore: score)

        self.headline = Self.headline(
            findings: built,
            survivorCount: stayed.count,
            movableCount: movableCount,
            intensity: quake.intensity
        )
    }

    /// The room's 0–100 safety score for a set of findings. Static so the retrofit ranking
    /// can ask "what would the score be without these" with exactly the same arithmetic.
    nonisolated static func safetyScore(for findings: [RoomFinding]) -> Int {
        let load = findings.reduce(0.0) { total, finding in
            let normalised = Double(finding.score) / 100
            let exposure = finding.reachesOccupiedSpace ? Weight.occupiedExposure : 1.0
            // Squared, so a dozen shuffled tumblers cannot outweigh one toppled bookcase.
            return total + normalised * normalised * exposure
        }
        let raw = 100 * pow(0.5, load / Weight.halvingLoad)
        return max(Weight.minimumSafetyScore, min(100, Int(raw.rounded())))
    }

    // MARK: - One finding

    private static func finding(for event: DemoQuake.Displacement,
                                prop: ApartmentScene.PropEntity,
                                in props: [String: ApartmentScene.PropEntity]) -> RoomFinding {
        let travel = travelMetres(prop)
        let height = Double(prop.halfExtents.y * 2)
        let base = Double(min(prop.halfExtents.x, prop.halfExtents.z) * 2)
        let mass = prop.mass.isFinite ? prop.mass : 0
        // Name as well as id, and for a reason: this must be the *same* answer the
        // breakage system reached, or the report will name a material the user did not
        // watch break. The keyword tier reads both fields, so passing only the id
        // silently classified anything whose noun lives in the display name — a
        // "Terracotta vase" with the id `living.shelf.vase.terracotta` happens to carry
        // it in both, but "Stack of plates" (`kitchen.plates`) does not.
        let material = MaterialAssignment.material(
            forPropID: prop.id, name: prop.name, category: prop.category
        )
        let nearest = nearestOccupiedPlace(to: prop)
        let support = support(of: prop, in: props)

        // Score. Outcome floor, plus the three additive terms, scaled by mass.
        var severity: Double
        switch event.kind {
        case .toppled: severity = Weight.toppled
        case .broke:   severity = Weight.broke
        case .slid:
            // Sliding is the one outcome with no natural floor: the same verdict covers a
            // sofa that shuffled 20 mm and a lamp that crossed the room. Charging both the
            // full floor put a 2 cm nudge in the same band as a toppled bookcase, which is
            // the single fastest way to teach a reader that the bands mean nothing. So the
            // floor is earned by travel, and only a slide that has actually gone somewhere
            // — `slidReference`, about the width of a walkway — collects all of it.
            severity = Weight.slid * min(travel / Weight.slidReference, 1)
        }
        severity += Weight.travel * min(travel / Weight.travelReference, 1)
        severity += Weight.height * min(height / Weight.heightReference, 1)
        if nearest != nil { severity += Weight.reach }
        let massScale = Weight.massFloor
            + (1 - Weight.massFloor) * min(mass / Weight.massReference, 1)
        let score = Int((100 * min(max(severity, 0), 1) * massScale).rounded())

        let mitigation = mitigation(for: prop, kind: event.kind,
                                    material: material,
                                    slenderness: base > 0 ? height / base : 0,
                                    height: height, support: support)

        return RoomFinding(
            id: prop.id,
            name: prop.name,
            category: prop.category,
            band: RiskBand(score: Double(score)),
            score: score,
            outcome: outcomeSentence(kind: event.kind, travel: travel,
                                     nearest: nearest, material: material),
            why: whySentence(prop: prop, kind: event.kind, material: material,
                             height: height, base: base, mass: mass, support: support),
            action: mitigation.title,
            effortMinutes: mitigation.minutes,
            displacementMetres: travel,
            massKg: mass,
            timeSeconds: event.time,
            kind: event.kind,
            reachesOccupiedSpace: nearest != nil,
            mitigation: mitigation
        )
    }

    private static func survivor(for prop: ApartmentScene.PropEntity) -> RoomSurvivor {
        let height = Double(prop.halfExtents.y * 2)
        let base = Double(min(prop.halfExtents.x, prop.halfExtents.z) * 2)
        let mass = prop.mass.isFinite ? prop.mass : 0
        let slenderness = base > 0 ? height / base : 0

        let note: String
        if slenderness >= slendernessThreshold {
            note = "Tall at \(metres(height)), and it still did not come over."
        } else if mass >= Weight.massReference {
            note = "Low and heavy — \(kilograms(mass)) over a \(metres(base)) base."
        } else if mass < handHeldMassKg {
            note = "Light, but its footprint held it."
        } else {
            note = "\(kilograms(mass)) on a \(metres(base)) base. It stayed put."
        }
        return RoomSurvivor(id: prop.id, name: prop.name, category: prop.category,
                            massKg: mass, note: note)
    }

    // MARK: - Measurement

    /// Straight-line horizontal distance from where the prop was placed to where it came
    /// to rest. Measured off the scene, never estimated.
    private static func travelMetres(_ prop: ApartmentScene.PropEntity) -> Double {
        let delta = prop.entity.transform.translation - prop.restTransform.translation
        return Double(simd_length(SIMD2(delta.x, delta.z)))
    }

    /// Rough potential-consequence ordering for the survivors list: mass × height.
    private static func consequencePotential(_ prop: ApartmentScene.PropEntity) -> Double {
        let mass = prop.mass.isFinite ? prop.mass : 0
        return mass * Double(prop.halfExtents.y * 2)
    }

    // MARK: - Where people are

    /// The places in this apartment where a person actually sits or stands, taken straight
    /// from `Plan` so they cannot drift away from the geometry.
    ///
    /// This is what makes "dangerous" mean something more than "moved". An object that
    /// slid two metres across an empty corner of the floor is not the same finding as one
    /// that slid two metres into the sofa.
    /// Each place carries the id of the prop it *is*, where there is one. Without that the
    /// sofa came to rest "within reach of the sofa" — true, unavoidable, and the sort of
    /// sentence that costs a report its credibility on the first card.
    private static var occupiedPlaces: [(name: String, point: SIMD2<Float>, owner: String?)] {
        var places: [(String, SIMD2<Float>, String?)] = [
            ("the sofa", Plan.Living.sofaCentre, "living.sofa"),
            ("the armchair", Plan.Living.armchairCentre, "living.armchair"),
            ("the pouf", Plan.Living.poufCentre, "living.pouf"),
            ("the breakfast bar", Plan.Island.stoolA, "island.stool.a"),
            ("the breakfast bar", Plan.Island.stoolB, "island.stool.b"),
            ("where you stand at the range",
             SIMD2(Plan.Kitchen.rangeCentre, Plan.Kitchen.counterDepth + 0.30), nil),
            ("where you stand at the sink",
             SIMD2(Plan.Kitchen.sinkCentre, Plan.Kitchen.counterDepth + 0.30), nil),
            ("the way out to the front door",
             SIMD2(Plan.width - 0.70,
                   (Plan.Entry.doorZ.lowerBound + Plan.Entry.doorZ.upperBound) / 2), nil),
        ]
        // The dining chairs sit on a ring, phased off the axes exactly as the module
        // places them.
        let step = 2 * Float.pi / Float(Plan.Dining.chairCount)
        for index in 0..<Plan.Dining.chairCount {
            let angle = Plan.Dining.chairPhase + Float(index) * step
            let offset = SIMD2(cos(angle), sin(angle)) * Plan.Dining.chairRadius
            places.append(("the dining table", Plan.Dining.centre + offset,
                           "dining.chair.\(index)"))
        }
        return places.map { (name: $0.0, point: $0.1, owner: $0.2) }
    }

    /// The occupied place a prop came to rest within reach of, if any.
    private static func nearestOccupiedPlace(to prop: ApartmentScene.PropEntity) -> String? {
        let position = prop.entity.transform.translation
        let here = SIMD2(position.x, position.z)
        // Reach is measured from the object's edge, not its centre, so a long sofa table
        // that stops with one end against the armchair counts — but the discount is capped
        // so that being large is not by itself a way of being close to everything.
        let halfFootprint = min(max(prop.halfExtents.x, prop.halfExtents.z),
                                Weight.reachEdgeAllowance)
        var best: (name: String, distance: Float)?
        for place in occupiedPlaces {
            // A seat is not within reach of itself.
            if let owner = place.owner, owner == prop.id { continue }
            let distance = simd_distance(here, place.point) - halfFootprint
            if best == nil || distance < best!.distance {
                best = (place.name, distance)
            }
        }
        guard let best, best.distance <= Weight.reachRadiusMetres else { return nil }
        return best.name
    }

    // MARK: - What it was standing on

    /// Where an object was before the shaking — which surface, and how far up.
    ///
    /// This exists because the report used to assert that every hazardous object had been
    /// "standing free on the bare floor". Fourteen of them were on the ladder shelving,
    /// several more on the island and the counters, and the one screen whose entire value
    /// is being right about where a dangerous object was, was wrong about all of them.
    enum Support: Equatable {
        case floor
        case rug
        /// On top of another prop — the shelving, the island, a table. The height is the
        /// object's own base, above the floor.
        case on(name: String, heightMetres: Double)
        /// Off the ground with nothing underneath it that this model can name.
        case elevated(heightMetres: Double)

        var heightMetres: Double {
            switch self {
            case .floor, .rug: return 0
            case .on(_, let h), .elevated(let h): return h
            }
        }

        var isElevated: Bool { heightMetres >= Support.elevatedThreshold }

        /// 0.35 m — knee height. Below it "up on" is not a fact worth a clause, and the
        /// floor and a low plinth are the same story.
        static let elevatedThreshold: Double = 0.35
    }

    /// Anything resting lower than this counts as being on the floor itself.
    private static let floorThreshold: Double = 0.06

    /// A support has to have at least this many times the object's own footprint. Two is
    /// enough to rule out neighbours of a similar size while still letting a stack of books
    /// hold a paperback.
    private static let supportFootprintRatio: Float = 2

    /// How far an object may stand from the middle of its support and still count as on it.
    private static let supportSlack: Float = 0.15

    /// How close a candidate's top face has to be to the object's base to count as the
    /// surface it is standing on rather than merely something it stands inside.
    private static let supportFlushTolerance: Float = 0.06

    /// Finds the prop a given prop was resting on, by matching its rest pose against every
    /// other prop's collider volume.
    ///
    /// Deliberately geometric rather than a lookup table: the apartment is authored in four
    /// module files and a table of "what is on what" would be a fifth place to forget to
    /// update. The candidate is the *smallest* prop whose footprint contains this one and
    /// whose vertical span reaches its base, which is what picks the shelving over the wall
    /// behind it and the island over the floor under it.
    private static func support(of prop: ApartmentScene.PropEntity,
                                in props: [String: ApartmentScene.PropEntity]) -> Support {
        let base = prop.restTransform.translation
        let height = Double(base.y)

        if height < floorThreshold {
            return onRug(prop) ? .rug : .floor
        }

        let ownFootprint = prop.halfExtents.x * prop.halfExtents.z

        // Two tiers, because two different things count as "supporting".
        //
        // A counter, a table or a cabinet has its *top face* at the object's base, so the
        // strongest evidence is a collider whose top matches. Shelving does not: its
        // collider spans the whole unit, floor to 2.32 m, and the object stands part-way up
        // inside it. So a containment test is the fallback, never the first answer — it
        // would otherwise let the tallest thing in the room claim everything standing in
        // front of it.
        var flush: (name: String, footprint: Float)?
        var enclosing: (name: String, footprint: Float)?

        for other in props.values where other.id != prop.id {
            // The envelope is not furniture: a chopping board is on the counter, not "on
            // the south wall". Excluded by module rather than by category, because the
            // quartz countertop — the single most-used surface in the flat — is authored
            // as `.structure` too, and excluding the category hid it behind the wall
            // cabinets that happen to enclose the same volume higher up.
            guard !other.id.hasPrefix("shell."), other.category != .glazing else { continue }
            let footprint = other.halfExtents.x * other.halfExtents.z
            // A thing cannot be held up by something its own size: a mug does not sit on a
            // mug, and a vase beside a bowl is not sitting in it.
            guard footprint >= ownFootprint * supportFootprintRatio else { continue }
            guard !other.mass.isFinite || other.mass > prop.mass else { continue }

            // Measured off the collider's real span, not off "origin plus twice the
            // half-extent". A countertop's collider is authored at 0.92…0.955 m and never
            // touches the floor; the shorthand put its top face at 3.5 cm and handed every
            // mug in the kitchen to the wall cabinets above it instead.
            let origin = other.restTransform.translation
            let bottom = origin.y + other.localLow.y
            let top = origin.y + other.localHigh.y
            let centreX = origin.x + (other.localLow.x + other.localHigh.x) / 2
            let centreZ = origin.z + (other.localLow.z + other.localHigh.z) / 2
            guard bottom <= base.y + 0.02, top >= base.y - Float(floorThreshold) else { continue }
            // Slack, because an object may sit near the lip of the board it is on.
            guard abs(base.x - centreX) <= other.halfExtents.x + supportSlack,
                  abs(base.z - centreZ) <= other.halfExtents.z + supportSlack else { continue }

            // Widest wins within a tier: the counter, not the dishwasher under it.
            if abs(top - base.y) <= supportFlushTolerance {
                if flush == nil || footprint > flush!.footprint { flush = (other.name, footprint) }
            } else if enclosing == nil || footprint > enclosing!.footprint {
                enclosing = (other.name, footprint)
            }
        }

        if let best = flush ?? enclosing {
            return .on(name: best.name.lowercased(), heightMetres: height)
        }
        return .elevated(heightMetres: height)
    }

    // MARK: - Copy

    private static func outcomeSentence(kind: DemoQuake.Displacement.Kind,
                                        travel: Double,
                                        nearest: String?,
                                        material: PhysicalMaterial) -> String {
        let landing = nearest.map { ", ending within reach of \($0)" } ?? ""
        switch kind {
        case .toppled:
            return travel < 0.05
                ? "Toppled where it stood\(landing)."
                : "Toppled and travelled \(distance(travel))\(landing)."
        case .slid:
            return "Slid \(distance(travel))\(landing)."
        case .broke:
            let noun = material.failure == .glass ? "Shattered" : "Broke"
            return travel < 0.05
                ? "\(noun) where it stood\(landing)."
                : "\(noun) after moving \(distance(travel))\(landing)."
        }
    }

    private static func whySentence(prop: ApartmentScene.PropEntity,
                                    kind: DemoQuake.Displacement.Kind,
                                    material: PhysicalMaterial,
                                    height: Double,
                                    base: Double,
                                    mass: Double,
                                    support: Support) -> String {
        var clauses: [String] = []

        let slenderness = base > 0 ? height / base : 0
        // Slenderness alone is not enough to call something "tall and narrow": a paperback
        // lying open-side-up is 0.21 m over a 0.02 m spine, a ratio of ten, and it was
        // outranking most of the furniture on the strength of it. A thing has to actually
        // be tall as well as slender before the phrase means anything.
        if slenderness >= slendernessThreshold, height >= tallEnoughMetres {
            clauses.append("tall and narrow — \(metres(height)) over a \(metres(base)) base")
        } else if mass >= Weight.massReference {
            clauses.append("heavy at \(kilograms(mass))")
        } else if mass < handHeldMassKg {
            clauses.append("light enough to be thrown about")
        }

        if material.isBrittle {
            clauses.append("\(materialNoun(material, name: prop.name)) with nothing to stop it")
        }

        clauses.append(supportClause(support))

        // Nothing the earthquake is allowed to move in this room is fixed down. That is the
        // recurring cause and it is the last clause, because it is the one the fix
        // addresses — but *what* it is not held to depends on what it was standing on.
        clauses.append(holdClause(kind: kind, support: support))

        return sentence(clauses)
    }

    private static func supportClause(_ support: Support) -> String {
        switch support {
        case .floor:
            return "standing free on the bare floor"
        case .rug:
            return "standing on the rug, which is not enough to hold it"
        case .on(let name, let height):
            return height >= Support.elevatedThreshold
                ? "sitting on the \(name), \(metres(height)) up"
                : "sitting on the \(name)"
        case .elevated(let height):
            return "sitting \(metres(height)) off the floor with nothing around it"
        }
    }

    private static func holdClause(kind: DemoQuake.Displacement.Kind,
                                   support: Support) -> String {
        switch support {
        case .on(let name, _) where support.isElevated:
            return "and nothing holding it to the \(name)"
        case .floor, .rug, .on, .elevated:
            return kind == .toppled
                ? "and nothing holding it to the wall"
                : "and nothing holding it down"
        }
    }

    /// True when the prop's resting footprint centre lies on the living-room rug. Taken
    /// from `Plan`, so it stays true if the rug moves.
    private static func onRug(_ prop: ApartmentScene.PropEntity) -> Bool {
        let p = prop.restTransform.translation
        let c = Plan.Living.rugCentre
        let half = Plan.Living.rugSize / 2
        return abs(p.x - c.x) <= half.x && abs(p.z - c.y) <= half.y
    }

    /// Assembles clauses into one sentence, capitalised, with an Oxford-free join —
    /// the last clause already carries its own "and".
    private static func sentence(_ clauses: [String]) -> String {
        guard var first = clauses.first else { return "" }
        first = first.prefix(1).uppercased() + String(first.dropFirst())
        var rest = Array(clauses.dropFirst())
        let tail = rest.last.map { $0.hasPrefix("and ") } ?? false
        let last = tail ? rest.removeLast() : nil
        var text = ([first] + rest).joined(separator: ", ")
        if let last { text += ", \(last)" }
        return text + "."
    }

    private static func headline(findings: [RoomFinding],
                                 survivorCount: Int,
                                 movableCount: Int,
                                 intensity: MercalliIntensity) -> String {
        guard let dominant = findings.first else {
            return movableCount == 0
                ? "Nothing loose was simulated, so there is nothing to report."
                : "Nothing moved at intensity \(intensity.roman). All \(movableCount) loose "
                    + "objects finished where they started."
        }
        let inReach = findings.filter(\.reachesOccupiedSpace).count
        let restated = dominant.outcome.prefix(1).lowercased()
            + String(dominant.outcome.dropFirst())
        var text = "Most of this score is \(dominant.name.lowercased()): it \(restated)"
        if inReach > 1 {
            text += " \(inReach) of the \(findings.count) things that moved finished within "
                + "reach of somewhere you sit or stand."
        } else if survivorCount > 0 {
            text += " The other \(survivorCount) loose objects stayed put."
        }
        return text
    }

    // MARK: - Advice
    //
    // Every one of these is a real `Mitigation` from `Core/Advice`, with its own FEMA
    // E-74 reference, hardware list, cost and time. Nothing here writes advice; it only
    // chooses which piece of existing advice applies.

    private static func mitigation(for prop: ApartmentScene.PropEntity,
                                   kind: DemoQuake.Displacement.Kind,
                                   material: PhysicalMaterial,
                                   slenderness: Double,
                                   height: Double,
                                   support: Support) -> Mitigation {
        let isTall = slenderness >= slendernessThreshold && height >= tallEnoughMetres
        let isLight = prop.mass.isFinite && prop.mass < handHeldMassKg

        switch prop.category {
        case .storage, .cabinetry:
            if isTall { return MitigationLibrary.anchorTallFurniture }
            return kind == .toppled
                ? MitigationLibrary.antiTipKitAdvice
                : MitigationLibrary.loadBottomFirst

        case .appliance:
            // The range is the one appliance with its own code-referenced fix.
            return prop.id.contains("range") || prop.id.contains("oven")
                ? MitigationLibrary.rangeAntiTip
                : MitigationLibrary.applianceStrapAdvice

        case .lighting:
            if isTall { return MitigationLibrary.relocateTallLightObject }
            return MitigationLibrary.hangingFixtureCable

        case .art:
            return MitigationLibrary.closedHooks

        case .tableware, .decor:
            // The fix has to follow the *situation*, not just the object. Everything small
            // and brittle in this apartment used to come back "museum putty under the
            // base, 15 min" — eleven identical cards in a row, which trains a reader to
            // stop reading and is also wrong: putty on a board 2 m up does not address the
            // fact that the board has no lip and the thing is over head height.
            if support.isElevated, case .on = support {
                return height >= tallEnoughMetres
                    ? MitigationLibrary.relocateTallLightObject
                    : MitigationLibrary.shelfLipAdvice
            }
            if isTall { return MitigationLibrary.relocateTallLightObject }
            if material.isBrittle || isLight { return MitigationLibrary.museumPuttyAdvice }
            return MitigationLibrary.antiSlipMatAdvice

        case .table:
            return MitigationLibrary.clearTabletop

        case .seating, .softFurnishing:
            return MitigationLibrary.keepSeatingClear

        case .glazing, .structure:
            return MitigationLibrary.builtInFixingCheck
        }
    }

    // MARK: - Formatting
    //
    // Distances are the only quantity the shared `FindingsFormat` has no rule for, because
    // no other screen reports how far something travelled. Everything else defers.

    /// "22 cm" under a metre, "1.4 m" over it — the precision people can picture.
    ///
    /// `nonisolated` because it is pure arithmetic on a `Double` and row views call it
    /// while formatting; there is nothing here that needs the main actor.
    nonisolated static func distance(_ metres: Double) -> String {
        metres < 1
            ? "\(Int((metres * 100).rounded())) cm"
            : String(format: "%.1f m", metres)
    }

    private static func metres(_ value: Double) -> String {
        UnitFormatter.length(value, in: .metric, decimals: 2)
    }

    /// Mass, with the precision the object deserves.
    ///
    /// `UnitFormatter.mass` defaults to whole kilograms, which is right for a fridge and
    /// useless below it: a 0.4 kg brass dish printed as "0 kg", and a 0.6 kg hardback and a
    /// 1.6 kg vase both printed as "1 kg". The frozen `ReportBuilder.mass` already switches
    /// to one decimal under 10 kg for exactly this reason; this is the same rule, applied
    /// on the screen that had missed it.
    private static func kilograms(_ value: Double) -> String {
        UnitFormatter.mass(value, in: .metric, decimals: value < 10 ? 1 : 0)
    }

    /// What to call the stuff the object is made of.
    ///
    /// The prop's own name wins whenever it already names a material, because the room said
    /// "Terracotta vase" out loud and the report saying "stoneware" three words later reads
    /// as the report describing a different object. `MaterialAssignment` groups terracotta,
    /// earthenware and stoneware under one physical id on purpose — they fracture the same
    /// way — and that grouping is a physics fact, not a vocabulary.
    private static func materialNoun(_ material: PhysicalMaterial, name: String) -> String {
        let lowered = name.lowercased()
        for noun in namedMaterials where lowered.contains(noun) { return noun }
        switch material.id {
        case "glass", "stemware": return "glass"
        case "ceramic": return "ceramic"
        case "porcelain": return "porcelain"
        case "stone": return "stone"
        default: return "brittle"
        }
    }

    /// Material words a prop's display name may already carry. Longest-first so
    /// "earthenware" is not matched as "stone" would be by a shorter substring.
    private static let namedMaterials = [
        "terracotta", "earthenware", "stoneware", "porcelain", "ceramic",
        "marble", "crystal", "glass", "stone", "clay"
    ]

    // MARK: - Export

    /// The report as plain text, for the share sheet.
    ///
    /// The product's real export path (`Core/Report`) builds a PDF from a `ScannedRoom` and
    /// a `RoomAssessment`, and the demo apartment is neither — it is a hand-authored scene,
    /// not a scan. Rather than fabricate those two values to satisfy the type, the demo
    /// shares what it can honestly produce: the same findings, in text.
    var shareText: String {
        var lines: [String] = []
        lines.append("\(roomName) — earthquake analysis")
        lines.append("Intensity \(intensity.roman) (\(intensity.shakingLabel)), "
            + String(format: "peak ground acceleration %.2f g", peakAccelerationG))
        lines.append("Room score \(safetyScore)/100 — \(band.title)")
        lines.append(headline)
        lines.append("")
        lines.append("What happened: \(toppledCount) toppled, \(slidCount) slid, "
            + "\(brokeCount) broke, out of \(movableCount) loose objects.")

        if !urgent.isEmpty {
            lines.append("")
            lines.append("MOVE THESE FIRST")
            for finding in urgent {
                lines.append("• \(finding.name) — \(finding.band.displayName) \(finding.score)/100")
                lines.append("  \(finding.outcome)")
                lines.append("  \(finding.why)")
                lines.append("  Fix: \(finding.action) (\(FindingsFormat.duration(finding.effortMinutes)), "
                    + "\(finding.mitigation.femaReference))")
            }
        }
        if !secondary.isEmpty {
            lines.append("")
            lines.append("ALSO WORTH DOING")
            for finding in secondary {
                lines.append("• \(finding.name) — \(finding.outcome) Fix: \(finding.action)")
            }
        }
        if !survivors.isEmpty {
            lines.append("")
            lines.append("WHAT HELD UP")
            for survivor in survivors {
                lines.append("• \(survivor.name) — \(survivor.note)")
            }
        }
        lines.append("")
        lines.append("Simulated in proof. Ground motion after Clough–Penzien; "
            + "advice after FEMA E-74.")
        return lines.joined(separator: "\n")
    }
}
