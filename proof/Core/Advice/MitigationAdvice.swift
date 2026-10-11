import Foundation
import simd

// MARK: - Supporting vocabulary

/// How hard a fix is for the person who has to do it. The app never tells
/// someone to "just anchor it" without telling them whether that means a strip
/// of putty or a gas fitter.
public enum MitigationDifficulty: String, Codable, CaseIterable, Sendable, Comparable, Identifiable {
    /// Costs nothing and needs no tools: move it, or put the heavy things lower.
    case free
    /// A screwdriver, a drill, and a stud finder.
    case basic
    /// Drilling into masonry, working behind an appliance, lifting help.
    case moderate
    /// Gas or water connections. Get a licensed trade in.
    case professional

    public var id: String { rawValue }

    var order: Int {
        switch self {
        case .free: return 0
        case .basic: return 1
        case .moderate: return 2
        case .professional: return 3
        }
    }

    public static func < (a: MitigationDifficulty, b: MitigationDifficulty) -> Bool {
        a.order < b.order
    }

    public var displayName: String {
        switch self {
        case .free: return "Free"
        case .basic: return "Basic tools"
        case .moderate: return "Some DIY"
        case .professional: return "Get a pro"
        }
    }

    public var symbolName: String {
        switch self {
        case .free: return "hand.raised.fill"
        case .basic: return "screwdriver.fill"
        case .moderate: return "wrench.and.screwdriver.fill"
        case .professional: return "person.fill.checkmark"
        }
    }
}

/// A coarse price bracket. Deliberately coarse: hardware prices move, and a
/// false-precision "$12.47" reads as a quote rather than as guidance.
public enum CostBand: String, Codable, CaseIterable, Sendable, Comparable, Identifiable {
    case free
    case under15
    case under40
    case under120
    case over120

    public var id: String { rawValue }

    var order: Int {
        switch self {
        case .free: return 0
        case .under15: return 1
        case .under40: return 2
        case .under120: return 3
        case .over120: return 4
        }
    }

    public static func < (a: CostBand, b: CostBand) -> Bool { a.order < b.order }

    public init(estimatedUSD range: ClosedRange<Double>) {
        let mid = (range.lowerBound + range.upperBound) / 2
        switch mid {
        case ..<0.01: self = .free
        case ..<15: self = .under15
        case ..<40: self = .under40
        case ..<120: self = .under120
        default: self = .over120
        }
    }

    public var displayName: String {
        switch self {
        case .free: return "Free"
        case .under15: return "Under $15"
        case .under40: return "$15–40"
        case .under120: return "$40–120"
        case .over120: return "$120+"
        }
    }
}

/// Where the user gets the parts. Used to group the plan into single trips, so
/// six fixes become one Saturday morning instead of six errands.
public enum SupplyVenue: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Nothing to buy — rearranging, locking castors, latching what is already there.
    case nothingToBuy
    /// Any hardware store: brackets, lag screws, straps, latches, mats.
    case hardwareStore
    /// Specialist or online: museum putty, earthquake hangers, safety film,
    /// proprietary water-heater strapping kits.
    case online
    /// A licensed plumber or gas fitter.
    case professional

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .nothingToBuy: return "Nothing to buy"
        case .hardwareStore: return "Hardware store"
        case .online: return "Order online"
        case .professional: return "Book a pro"
        }
    }

    public var detail: String {
        switch self {
        case .nothingToBuy: return "You already have everything you need."
        case .hardwareStore: return "One trip covers all of these."
        case .online: return "Not usually stocked in a general hardware store."
        case .professional: return "Gas and water connections are not a DIY job."
        }
    }

    public var symbolName: String {
        switch self {
        case .nothingToBuy: return "hand.raised.fill"
        case .hardwareStore: return "cart.fill"
        case .online: return "shippingbox.fill"
        case .professional: return "person.fill.checkmark"
        }
    }

    var order: Int {
        switch self {
        case .nothingToBuy: return 0
        case .hardwareStore: return 1
        case .online: return 2
        case .professional: return 3
        }
    }
}

/// One thing the user has to buy, with the specification that actually matters.
///
/// The specification is never vague. "Some screws" is how a bookcase ends up
/// attached to plasterboard; "two 6 mm × 65 mm (¼″ × 2½″) lag screws into studs"
/// is how it ends up attached to the building.
public struct HardwareItem: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// The dimension, standard, or rating that makes this part the right part.
    public var specification: String
    public var quantity: Int
    /// Rough unit price in US dollars.
    public var approxUnitCostUSD: Double

    public init(
        id: String, name: String, specification: String,
        quantity: Int, approxUnitCostUSD: Double
    ) {
        self.id = id
        self.name = name
        self.specification = specification
        self.quantity = quantity
        self.approxUnitCostUSD = approxUnitCostUSD
    }

    public var totalCostUSD: Double { Double(quantity) * approxUnitCostUSD }

    public var displayLine: String {
        quantity > 1 ? "\(quantity) × \(name) — \(specification)"
                     : "\(name) — \(specification)"
    }
}

/// How a fix changes the physics, so the "after this fix" number is computed
/// rather than asserted.
///
/// Only the effects the rigid-block model can honestly represent are marked
/// `isModelled`. A positive latch on a cabinet door genuinely stops the china
/// coming out, but nothing in a rigid-block solution knows about china, so the
/// app says "this does not change the score, it changes what lands on the
/// floor" rather than inventing an improvement.
public struct MitigationEffect: Codable, Hashable, Sendable {
    /// The object becomes restrained: `L × 0.10` in the risk engine.
    public var setsAnchored: Bool
    /// Change in the centre-of-mass height as a fraction of the object's own
    /// height. Negative lowers it — "heavy things on the bottom shelf" is
    /// −0.08, which raises the rocking threshold by about 37%.
    public var centreOfMassFractionDelta: Double?
    /// The object is moved out from under, over, or beside a person.
    public var relocates: Bool
    /// Contents are restrained but the object itself is unchanged.
    public var restrainsContents: Bool
    /// Sliding friction is improved but rocking is not — an anti-slip mat.
    /// Recorded for honesty; the block model takes friction from the object's
    /// footing, which a `ScannedObject` cannot override, so this is not scored.
    public var frictionMultiplier: Double?

    public init(
        setsAnchored: Bool = false,
        centreOfMassFractionDelta: Double? = nil,
        relocates: Bool = false,
        restrainsContents: Bool = false,
        frictionMultiplier: Double? = nil
    ) {
        self.setsAnchored = setsAnchored
        self.centreOfMassFractionDelta = centreOfMassFractionDelta
        self.relocates = relocates
        self.restrainsContents = restrainsContents
        self.frictionMultiplier = frictionMultiplier
    }

    public static let none = MitigationEffect()

    /// Whether re-running the risk engine with this effect applied produces a
    /// different number. Only these fixes get an "after" score.
    public var isModelled: Bool {
        setsAnchored || relocates || centreOfMassFractionDelta != nil
    }
}

// MARK: - Mitigation

/// One piece of advice: what to do, exactly what to buy, how long it takes,
/// what it costs, and where FEMA says it.
public struct Mitigation: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    /// One line. This is what the card shows before the user taps.
    public var summary: String
    /// Ordered, imperative, and specific enough to follow without a second tab open.
    public var steps: [String]
    public var hardware: [HardwareItem]
    public var estimatedCostUSD: ClosedRange<Double>
    public var difficulty: MitigationDifficulty
    public var minutes: Int
    /// The FEMA E-74 section this comes from.
    public var femaReference: String
    public var symbolName: String
    public var venue: SupplyVenue
    /// The thing people get wrong, stated plainly. Most often: a drywall anchor
    /// where a lag screw into a stud is required.
    public var warning: String?
    public var effect: MitigationEffect
    /// Tie-break ordering within a single object's advice, low first. Context
    /// (above a bed, a legal requirement) overrides this.
    public var basePriority: Int

    public init(
        id: String, title: String, summary: String, steps: [String],
        hardware: [HardwareItem] = [],
        estimatedCostUSD: ClosedRange<Double>,
        difficulty: MitigationDifficulty, minutes: Int,
        femaReference: String, symbolName: String,
        venue: SupplyVenue, warning: String? = nil,
        effect: MitigationEffect = .none, basePriority: Int = 50
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.steps = steps
        self.hardware = hardware
        self.estimatedCostUSD = estimatedCostUSD
        self.difficulty = difficulty
        self.minutes = minutes
        self.femaReference = femaReference
        self.symbolName = symbolName
        self.venue = venue
        self.warning = warning
        self.effect = effect
        self.basePriority = basePriority
    }

    public var costBand: CostBand { CostBand(estimatedUSD: estimatedCostUSD) }

    public var isFree: Bool { estimatedCostUSD.upperBound < 0.01 }

    /// "10 min · Under $15 · basic tools" — the chip under every card title.
    public var chipSummary: String {
        "\(timeSummary) · \(costBand.displayName) · \(difficulty.displayName.lowercased())"
    }

    public var timeSummary: String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = Double(minutes) / 60
        return hours == hours.rounded()
            ? "\(Int(hours)) hr"
            : String(format: "%.1f hr", hours)
    }

    /// The shopping line for this fix alone.
    public var hardwareSummary: String {
        hardware.isEmpty
            ? "Nothing to buy"
            : hardware.map(\.displayLine).joined(separator: "\n")
    }

    /// Every piece of text in the mitigation, for search and for tests that
    /// assert a specific instruction is present.
    public var searchableText: String {
        ([title, summary, warning ?? ""] + steps + hardware.map { "\($0.name) \($0.specification)" })
            .joined(separator: " ")
    }
}

// MARK: - Library

/// The FEMA E-74 Chapter 6 mitigation table, turned into advice the app can
/// hand to one specific object in one specific room.
///
/// Everything here is sourced from `docs/research/science-seismic.md` §7.3 (the
/// mitigation table) and §7.3.1 (anchorage design forces), which in turn come
/// from FEMA E-74 *Reducing the Risks of Nonstructural Earthquake Damage* and
/// the FEMA 528 *Earthquake Home Hazard Hunt* material.
public enum MitigationLibrary {

    // MARK: Hardware parts

    private static let lagScrew65 = HardwareItem(
        id: "lag-screw-6x65", name: "Lag screw",
        specification: "6 mm × 65 mm (¼″ × 2½″), hex head, with washers — into the stud, not the plasterboard",
        quantity: 4, approxUnitCostUSD: 0.85)

    private static let lagScrew75 = HardwareItem(
        id: "lag-screw-6x75", name: "Lag screw",
        specification: "6 mm × 75 mm (¼″ × 3″), hex head, with washers",
        quantity: 4, approxUnitCostUSD: 0.95)

    private static let lBracket = HardwareItem(
        id: "l-bracket-steel", name: "Steel L-bracket / angle clip",
        specification: "50 × 50 mm, 2 mm steel, 7 mm fixing holes — one per stud at 400 mm (16″) centres",
        quantity: 2, approxUnitCostUSD: 3.50)

    private static let nylonFurnitureStrap = HardwareItem(
        id: "furniture-strap-nylon", name: "Flexible nylon furniture strap",
        specification: "Rated ≥ 45 kg (100 lb) per strap, with steel wall and furniture plates",
        quantity: 2, approxUnitCostUSD: 6.00)

    private static let studFinder = HardwareItem(
        id: "stud-finder", name: "Stud finder",
        specification: "Any electronic or magnetic finder — studs are at 400 mm (16″) centres",
        quantity: 1, approxUnitCostUSD: 20.00)

    private static let antiTipKit = HardwareItem(
        id: "anti-tip-kit-astm", name: "Anti-tip kit",
        specification: "ASTM F2057 compliant strap or bracket kit (the standard clothing-storage units are tested to)",
        quantity: 1, approxUnitCostUSD: 12.00)

    private static let rangeAntiTipBracket = HardwareItem(
        id: "range-anti-tip-bracket", name: "Range anti-tip bracket",
        specification: "ANSI Z21.1 / UL 858 rear-foot bracket — usually shipped with the range and left in the box",
        quantity: 1, approxUnitCostUSD: 15.00)

    private static let flexibleGasConnector = HardwareItem(
        id: "flexible-gas-connector", name: "Flexible gas connector",
        specification: "CSST or corrugated stainless steel appliance connector, 12 mm (½″) minimum bore, sized to the appliance — never rigid pipe",
        quantity: 1, approxUnitCostUSD: 30.00)

    private static let flexibleWaterConnector = HardwareItem(
        id: "flexible-water-connector", name: "Flexible water connector",
        specification: "Braided stainless steel, 19 mm (¾″) at a water heater, with a 100 mm loop of slack",
        quantity: 2, approxUnitCostUSD: 14.00)

    private static let applianceStrap = HardwareItem(
        id: "appliance-strap", name: "Appliance strap",
        specification: "Nylon or steel body strap rated ≥ 90 kg (200 lb), with lag anchors",
        quantity: 2, approxUnitCostUSD: 9.00)

    private static let plumbersTape = HardwareItem(
        id: "plumbers-tape-24ga", name: "Plumber's tape (steel strapping)",
        specification: "24-gauge × 19 mm (¾″), at least two full wraps per strap",
        quantity: 1, approxUnitCostUSD: 8.00)

    private static let waterHeaterKit = HardwareItem(
        id: "water-heater-eq-kit", name: "Earthquake water-heater strapping kit",
        specification: "Two-strap kit certified to the state plumbing code (IRC P2801.8 / CA H&SC §19211)",
        quantity: 1, approxUnitCostUSD: 30.00)

    private static let tvStrap = HardwareItem(
        id: "tv-safety-strap", name: "TV safety strap / tether",
        specification: "Two nylon straps rated ≥ 2× the TV's weight, bolted through the VESA holes",
        quantity: 2, approxUnitCostUSD: 8.00)

    private static let tvWallMount = HardwareItem(
        id: "tv-wall-mount", name: "VESA wall mount",
        specification: "Rated ≥ 4× the TV's weight, fixed with lag screws into studs",
        quantity: 1, approxUnitCostUSD: 45.00)

    private static let velcroStrap = HardwareItem(
        id: "hook-loop-strap", name: "Hook-and-loop equipment strap",
        specification: "25 mm wide, long enough to pass round the base and through a desk grommet",
        quantity: 4, approxUnitCostUSD: 2.00)

    private static let museumPutty = HardwareItem(
        id: "museum-putty", name: "Museum putty / quake gel",
        specification: "A 70 g pack does about 30 objects. Holds roughly 4–5 kg at 1–2 g — small items only",
        quantity: 1, approxUnitCostUSD: 8.00)

    private static let shelfLip = HardwareItem(
        id: "shelf-lip", name: "Shelf lip, restraining bar or bungee",
        specification: "20 mm timber lip, a wire restraining bar, or a bungee across the shelf front",
        quantity: 4, approxUnitCostUSD: 4.00)

    private static let positiveLatch = HardwareItem(
        id: "positive-latch", name: "Positive latch",
        specification: "Child-safety push latch, magnetic touch latch, or 50 mm barrel bolt — NOT an ordinary magnetic catch",
        quantity: 4, approxUnitCostUSD: 3.00)

    private static let closedHook = HardwareItem(
        id: "closed-hook", name: "Closed hook / earthquake hanger",
        specification: "Closed-eye or locking picture hook, rated ≥ 2× the frame weight, two of them",
        quantity: 2, approxUnitCostUSD: 4.00)

    private static let screwEyeAndWire = HardwareItem(
        id: "screw-eye-wire", name: "Screw eyes and picture wire",
        specification: "Two screw eyes into the frame's stiles, braided steel wire rated ≥ 2× the frame weight",
        quantity: 1, approxUnitCostUSD: 6.00)

    private static let safetyFilm = HardwareItem(
        id: "safety-film", name: "Safety film",
        specification: "100 micron (4 mil) clear shatter-resistant film, cut to the glass",
        quantity: 1, approxUnitCostUSD: 25.00)

    private static let mirrorClip = HardwareItem(
        id: "mirror-clip", name: "Mirror J-clip set",
        specification: "Bottom J-channel plus two 25 mm top clips, screwed into studs with 4 mm × 40 mm screws",
        quantity: 1, approxUnitCostUSD: 12.00)

    private static let antiSlipMat = HardwareItem(
        id: "anti-slip-mat", name: "Anti-slip mat",
        specification: "Silicone or TPE mat, μ ≈ 1.1, cut to the footprint",
        quantity: 1, approxUnitCostUSD: 10.00)

    private static let castorCups = HardwareItem(
        id: "castor-cups", name: "Castor cups or wheel chocks",
        specification: "Hardwood or high-density rubber cups, 50–75 mm internal diameter, sized to the wheel",
        quantity: 4, approxUnitCostUSD: 4.00)

    private static let safetyCable = HardwareItem(
        id: "fixture-safety-cable", name: "Fixture safety cable",
        specification: "1.5 mm steel aircraft cable with a closed loop, back to a joist or the outlet box strap",
        quantity: 1, approxUnitCostUSD: 9.00)

    private static let cabinetScrews = HardwareItem(
        id: "cabinet-screw", name: "Cabinet screw",
        specification: "5 mm × 65 mm (#10 × 2½″) screw with a washer — screws, never nails",
        quantity: 4, approxUnitCostUSD: 0.60)

    // MARK: Standard warnings

    /// The single most common way a correct fix is installed incorrectly.
    public static let drywallWarning =
        "Find the stud. A 6 mm × 65 mm lag screw into a stud holds about 2,700 N; "
        + "a plasterboard toggle holds 200–350 N. That is a factor of ten, and it is "
        + "the difference between a bookcase that stays on the wall and one that takes "
        + "a piece of the wall with it."

    // MARK: Catalogue

    /// Move it out from above where someone sleeps. FEMA's single highest-value
    /// piece of advice, and the only one that is free.
    public static let removeAboveBed = Mitigation(
        id: "remove-above-bed",
        title: "Take it down from above the bed",
        summary: "Nothing heavy goes above a bed or a crib. No shelf, no picture, no mirror, no TV.",
        steps: [
            "Take it off the wall above the bed. This is the one piece of advice FEMA gives above all the others.",
            "Rehang it on a wall you do not sleep under — ideally opposite the bed, or at least below shoulder height.",
            "If it has to stay in the room, put it where a fall lands on floor, not on a pillow.",
            "Re-hang it on two closed hooks or a two-point wire into studs, never a single open hook.",
        ],
        estimatedCostUSD: 0...0,
        difficulty: .free, minutes: 10,
        femaReference: "FEMA E-74 §6.4",
        symbolName: "bed.double.fill",
        venue: .nothingToBuy,
        warning: "A person asleep cannot duck. Anchoring something above a bed is second best; "
            + "moving it is the fix.",
        effect: MitigationEffect(relocates: true),
        basePriority: 0)

    /// The rearrange-it-instead class: free, and often better than anchoring.
    public static let relocateAwayFromBed = Mitigation(
        id: "relocate-away-from-bed",
        title: "Move it away from the bed",
        summary: "Rearranging the room is free, and it beats anchoring: if it cannot reach you, it cannot hurt you.",
        steps: [
            "Measure the piece. Anything within its own height of the head of the bed can land on the pillow.",
            "Move it to a wall where a full-height fall clears the bed and the walking route to the door.",
            "Swap it with something low and heavy — a chest of drawers under waist height, a low bench.",
            "If it genuinely cannot move, anchor it to studs instead, and do that today.",
        ],
        estimatedCostUSD: 0...0,
        difficulty: .free, minutes: 20,
        femaReference: "FEMA E-74 §6.4",
        symbolName: "arrow.left.arrow.right",
        venue: .nothingToBuy,
        warning: nil,
        effect: MitigationEffect(relocates: true),
        basePriority: 1)

    public static let relocateAwayFromPath = Mitigation(
        id: "relocate-away-from-path",
        title: "Move it out of the way out",
        summary: "Fallen, this lands across your route to the door. Standing it somewhere else costs nothing.",
        steps: [
            "Stand where you sleep or sit and look at the line to the door.",
            "Move anything taller than a metre off that line — a fallen piece reaches out by its own height.",
            "Keep at least 815 mm (32″) of clear width at the doorway, the code minimum for an exit.",
        ],
        estimatedCostUSD: 0...0,
        difficulty: .free, minutes: 15,
        femaReference: "FEMA E-74 §6.4",
        symbolName: "figure.walk.departure",
        venue: .nothingToBuy,
        effect: MitigationEffect(relocates: true),
        basePriority: 6)

    public static let anchorTallFurniture = Mitigation(
        id: "anchor-tall-furniture",
        title: "Anchor the top to the wall studs",
        summary: "Two steel L-brackets and four lag screws into studs. Twenty minutes, and the piece stops being a hazard.",
        steps: [
            "Find the studs behind the piece with a stud finder. They are at 400 mm (16″) centres.",
            "Empty the top two shelves so you can lift and tilt the unit, and so the fixing is not fighting a full load.",
            "Screw one steel L-bracket to the top rail of the unit over each stud — two brackets minimum, at the top corners.",
            "Fix each bracket to the stud with a 6 mm × 65 mm (¼″ × 2½″) lag screw and a washer, driven at least 40 mm into solid timber.",
            "Alternatively use flexible nylon furniture straps at the top corners: they let the unit rock a little and absorb energy, and they are easier on rented walls.",
            "Load the heavy things back on the bottom shelves, not the top.",
        ],
        hardware: [lBracket, lagScrew65, studFinder],
        estimatedCostUSD: 12...35,
        difficulty: .basic, minutes: 30,
        femaReference: "FEMA E-74 §6.4.1",
        symbolName: "wrench.and.screwdriver.fill",
        venue: .hardwareStore,
        warning: drywallWarning,
        effect: MitigationEffect(setsAnchored: true),
        basePriority: 10)

    public static let antiTipKitAdvice = Mitigation(
        id: "anti-tip-kit",
        title: "Fit an ASTM F2057 anti-tip kit",
        summary: "The strap kit that comes with every chest of drawers, and that almost nobody installs.",
        steps: [
            "Check the drawers first: pull them all out at once and see whether the unit wants to come with them. That is the failure mode.",
            "Find the stud behind the unit with a stud finder.",
            "Screw the wall plate of the anti-tip kit into the stud with the lag screw supplied — into timber, not plasterboard.",
            "Screw the furniture plate into the top rail or the back panel's solid frame, not into the thin backing board.",
            "Tighten the strap so the unit sits about 10 mm off the wall with no slack.",
            "Fit drawer stops so the drawers cannot launch out of the carcass.",
        ],
        hardware: [antiTipKit, studFinder],
        estimatedCostUSD: 10...32,
        difficulty: .basic, minutes: 25,
        femaReference: "FEMA E-74 §6.4.1",
        symbolName: "cabinet.fill",
        venue: .hardwareStore,
        warning: drywallWarning,
        effect: MitigationEffect(setsAnchored: true),
        basePriority: 10)

    public static let loadBottomFirst = Mitigation(
        id: "load-bottom-first",
        title: "Put the heavy things on the bottom shelf",
        summary: "Free, takes ten minutes, and raises the shaking it takes to tip this over by about a third.",
        steps: [
            "Move the heaviest items — reference books, records, boxes, appliances — to the bottom two shelves.",
            "Put the light things up top: paperbacks, photographs, empty boxes.",
            "Do not stack anything on top of the unit itself.",
        ],
        estimatedCostUSD: 0...0,
        difficulty: .free, minutes: 10,
        femaReference: "FEMA E-74 §6.4.1",
        symbolName: "arrow.down.to.line",
        venue: .nothingToBuy,
        warning: nil,
        // Moves h_cm from about 0.55 H to about 0.47 H, which raises the rocking
        // threshold b/h_cm by roughly 17%. The published −0.08 figure.
        effect: MitigationEffect(centreOfMassFractionDelta: -0.08),
        basePriority: 20)

    public static let shelfLipAdvice = Mitigation(
        id: "shelf-lip",
        title: "Stop the contents coming off the shelves",
        summary: "The shelves empty before the unit falls, and that is usually what hits you first.",
        steps: [
            "Fit a 20 mm timber lip, a wire restraining bar, or a bungee cord across the front of each open shelf.",
            "Hook the bungee onto screw eyes at each end of the shelf so it can be unhooked and re-hooked in a second.",
            "For the shelf at head height, do this first.",
        ],
        hardware: [shelfLip],
        estimatedCostUSD: 8...25,
        difficulty: .basic, minutes: 25,
        femaReference: "FEMA E-74 §6.4.1",
        symbolName: "books.vertical.fill",
        venue: .hardwareStore,
        warning: nil,
        effect: MitigationEffect(restrainsContents: true),
        basePriority: 25)

    public static let doorLatches = Mitigation(
        id: "door-latches",
        title: "Fit positive latches to the doors",
        summary: "An ordinary magnetic catch releases under shaking. A positive latch does not.",
        steps: [
            "Buy child-safety push latches, magnetic touch latches, or small barrel bolts — anything that needs a deliberate action to open.",
            "Fit one to each door of the cabinet, at the top inside corner.",
            "Test it by shaking the door hard. If it pops open, it is the wrong catch.",
            "Do the glazed doors first: those are the ones that scatter glass.",
        ],
        hardware: [positiveLatch],
        estimatedCostUSD: 8...25,
        difficulty: .basic, minutes: 30,
        femaReference: "FEMA E-74 §6.4.3",
        symbolName: "lock.fill",
        venue: .hardwareStore,
        warning: "Ordinary magnetic catches and roller catches release under shaking. They are not a fix.",
        effect: MitigationEffect(restrainsContents: true),
        basePriority: 26)

    public static let upperCabinetAnchor = Mitigation(
        id: "upper-cabinet-anchor",
        title: "Screw the cabinet back into the studs",
        summary: "Wall cabinets fail at their fixings. Screws into studs, never nails, never plasterboard plugs.",
        steps: [
            "Empty the cabinet and look inside at the back panel: you should see screw heads on the top and bottom rails.",
            "If you see nails, or nothing, add 5 mm × 65 mm (#10 × 2½″) screws with washers through the rails into each stud.",
            "Two screws per stud, top rail and bottom rail.",
            "While the doors are open, fit positive latches — an upper cabinet that stays on the wall still empties itself onto the counter.",
        ],
        hardware: [cabinetScrews, studFinder],
        estimatedCostUSD: 5...25,
        difficulty: .basic, minutes: 40,
        femaReference: "FEMA E-74 §6.4.1",
        symbolName: "cabinet.fill",
        venue: .hardwareStore,
        warning: drywallWarning,
        effect: MitigationEffect(setsAnchored: true),
        basePriority: 12)

    public static let rangeAntiTip = Mitigation(
        id: "range-anti-tip",
        title: "Fit the anti-tip bracket and a flexible gas connector",
        summary: "A freestanding range tips forward when a child stands on the open door — and in a quake, on its own.",
        steps: [
            "Pull the range out. The anti-tip bracket is required by ANSI Z21.1 and UL 858 and is normally taped inside the packaging — most ranges are installed without it.",
            "Screw the bracket to the floor or the rear wall so the rear foot or the rear leg sits captured inside it.",
            "Slide the range back and check it: lean on the open oven door. It must not lift at the back.",
            "If it is gas, have the rigid pipe replaced with a CSST or corrugated stainless flexible appliance connector, sized correctly by a licensed gas fitter. A rigid connector snapping is a house fire.",
            "Fit an accessible gas shut-off valve at the appliance while the fitter is there.",
        ],
        hardware: [rangeAntiTipBracket, flexibleGasConnector],
        estimatedCostUSD: 15...180,
        difficulty: .professional, minutes: 60,
        femaReference: "FEMA E-74 §6.5",
        symbolName: "flame.fill",
        venue: .professional,
        warning: "Never work on a gas connection yourself. A rigid gas pipe on a range that moves is the "
            + "single most common cause of post-earthquake fire after water heaters.",
        effect: MitigationEffect(setsAnchored: true),
        basePriority: 5)

    public static let applianceStrapAdvice = Mitigation(
        id: "appliance-strap",
        title: "Strap it to the wall studs",
        summary: "Two straps, one across the top third and one across the bottom third, into studs.",
        steps: [
            "Find the studs behind the appliance.",
            "Pass a nylon or steel appliance strap round the body at the upper third and lag-screw both ends into studs.",
            "Repeat at the lower third. Two straps, not one — a single strap lets the body pivot about it.",
            "Lock or chock the castors so it cannot walk out from under the straps.",
            "Check the water line at the back is a braided flexible connector with a loop of slack, not a rigid tube.",
        ],
        hardware: [applianceStrap, lagScrew65, studFinder],
        estimatedCostUSD: 18...45,
        difficulty: .moderate, minutes: 45,
        femaReference: "FEMA E-74 §6.4.2",
        symbolName: "refrigerator.fill",
        venue: .hardwareStore,
        warning: drywallWarning,
        effect: MitigationEffect(setsAnchored: true),
        basePriority: 10)

    public static let washerDryerStrap = Mitigation(
        id: "washer-dryer-strap",
        title: "Strap it, and lock the feet",
        summary: "A washing machine walks on its own at spin speed. Under an earthquake it walks into the room.",
        steps: [
            "Level the machine and lock the levelling feet so it sits solid on all four.",
            "Strap the body back to studs with a nylon appliance strap at the upper third.",
            "For a stacked pair, strap the dryer to the washer with the manufacturer's stacking kit, then strap the stack to the wall.",
            "Check the hoses: braided stainless steel supply hoses with a loop of slack, and a dryer vent that can flex.",
        ],
        hardware: [applianceStrap, lagScrew65],
        estimatedCostUSD: 15...40,
        difficulty: .moderate, minutes: 40,
        femaReference: "FEMA E-74 §6.4.2",
        symbolName: "washer.fill",
        venue: .hardwareStore,
        warning: drywallWarning,
        effect: MitigationEffect(setsAnchored: true),
        basePriority: 10)

    public static let waterHeaterStraps = Mitigation(
        id: "water-heater-straps",
        title: "Two straps, upper and lower third — this one is the law",
        summary: "Over half the residential fires after Northridge started at an unstrapped water heater. "
            + "California requires strapping, and so does the plumbing code in every seismic-D area.",
        steps: [
            "Buy a two-strap earthquake strapping kit, or make it up from 24-gauge × 19 mm (¾″) plumber's tape with at least two full wraps per strap.",
            "Fit the first strap around the UPPER third of the tank and the second around the LOWER third. Two straps. One is not compliant and does not work — the tank pivots about it.",
            "Keep both straps at least 100 mm clear of the controls, the thermostat and the gas valve.",
            "Anchor each strap into wall studs with 6 mm × 75 mm (¼″ × 3″) lag screws, or into masonry with the appropriate sleeve anchors. Take the strap all the way round and back to the wall on both sides.",
            "Replace the rigid water lines with flexible braided stainless connectors, both inlet and outlet.",
            "If it is gas, have a licensed fitter replace the gas line with a flexible connector and fit an accessible shut-off. Flexible water AND gas connectors are mandatory, not optional.",
            "While you are there: nothing flammable stored within a metre of it.",
        ],
        hardware: [waterHeaterKit, plumbersTape, lagScrew75, flexibleWaterConnector, flexibleGasConnector],
        estimatedCostUSD: 45...220,
        difficulty: .professional, minutes: 120,
        femaReference: "FEMA E-74 §6.5.1",
        symbolName: "drop.fill",
        venue: .professional,
        warning: "This is a legal requirement in California (Health & Safety Code §19211) and under "
            + "IRC P2801.8 in seismic design category D. An unstrapped heater is also 190 litres of "
            + "emergency drinking water you are about to lose.",
        effect: MitigationEffect(setsAnchored: true),
        basePriority: 2)

    public static let tvTether = Mitigation(
        id: "tv-tether",
        title: "Tether the TV to the furniture — or better, to the wall",
        summary: "A television on a dresser is a 20 kg block on a moving base. It goes first, and it goes furthest.",
        steps: [
            "Find the four VESA holes on the back of the TV.",
            "Bolt two nylon safety straps rated at twice the TV's weight through the VESA holes.",
            "Screw the other end into the solid timber frame at the back of the furniture, or better, into a wall stud behind it.",
            "Anchor the furniture itself as well — a tethered TV on an unanchored dresser goes over with the dresser.",
            "Better still: wall-mount the TV and take it off the furniture entirely.",
        ],
        hardware: [tvStrap, lagScrew65],
        estimatedCostUSD: 12...30,
        difficulty: .basic, minutes: 30,
        femaReference: "FEMA E-74 §6.4.5",
        symbolName: "tv.fill",
        venue: .hardwareStore,
        warning: "CPSC tip-over data is dominated by televisions on furniture falling onto children.",
        effect: MitigationEffect(setsAnchored: true),
        basePriority: 8)

    public static let tvWallMountAdvice = Mitigation(
        id: "tv-wall-mount",
        title: "Check the mount is in studs, and add a tether",
        summary: "Full-motion mounts put a big lever on their fixings. Drywall anchors do not survive it.",
        steps: [
            "Check the mount's rating: it must carry at least four times the TV's weight, and a full-motion arm needs more.",
            "Take the cover plate off and look at what the wall plate is screwed into. It must be lag screws into studs.",
            "If you find plasterboard toggles, stop and refit it — a toggle carries 200–350 N, a lag into a stud carries about 2,700 N.",
            "Add a safety tether from the TV back to a stud as a second line of defence.",
            "If it is above a bed, a sofa or a crib, move it. No mount rating fixes that.",
        ],
        hardware: [tvWallMount, lagScrew65, studFinder],
        estimatedCostUSD: 25...120,
        difficulty: .moderate, minutes: 60,
        femaReference: "FEMA E-74 §6.4.5",
        symbolName: "tv.fill",
        venue: .hardwareStore,
        warning: drywallWarning,
        effect: MitigationEffect(setsAnchored: true),
        basePriority: 9)

    public static let avEquipmentStrap = Mitigation(
        id: "av-equipment-strap",
        title: "Strap the equipment down and leave slack in the cables",
        summary: "Computers and AV gear survive being shaken. They do not survive being dragged off the desk by their own cables.",
        steps: [
            "Strap the base of each unit to the desk with hook-and-loop straps through a grommet, or a nylon strap round the leg.",
            "Leave a deliberate loop of slack in every cable so a unit that moves 100 mm does not tear its connector out.",
            "Put a monitor arm's clamp on the far side of the desk from where you sit.",
            "Back up off-site. The strap protects the hardware; it does nothing for the data.",
        ],
        hardware: [velcroStrap],
        estimatedCostUSD: 5...20,
        difficulty: .basic, minutes: 20,
        femaReference: "FEMA E-74 §6.4.6",
        symbolName: "desktopcomputer",
        venue: .hardwareStore,
        warning: nil,
        effect: MitigationEffect(setsAnchored: true),
        basePriority: 14)

    public static let museumPuttyAdvice = Mitigation(
        id: "museum-putty",
        title: "Museum putty under the base",
        summary: "A pea of putty under each corner holds a small object through shaking that would throw it across the room.",
        steps: [
            "Clean and dry the base and the shelf.",
            "Roll a pea-sized ball of museum putty or quake gel for each corner of the base — three or four per object.",
            "Press down and twist a quarter turn so the putty grips both surfaces.",
            "Only for small things: putty holds roughly 4–5 kg at 1–2 g. Above that it is decoration, and the object needs a lip, a latch, or a strap.",
        ],
        hardware: [museumPutty],
        estimatedCostUSD: 6...15,
        difficulty: .basic, minutes: 15,
        femaReference: "FEMA E-74 §6.4.7",
        symbolName: "circle.grid.cross.fill",
        venue: .online,
        warning: "Putty is rated for the small stuff only. Do not trust it above about 5 kg.",
        effect: MitigationEffect(setsAnchored: true),
        basePriority: 22)

    public static let closedHooks = Mitigation(
        id: "closed-hooks",
        title: "Two closed hooks, never one open hook",
        summary: "An open hook only has to be lifted 10 mm to let go. That is the first thing shaking does.",
        steps: [
            "Take it down and look at the hanger. A single open picture hook is the failure mode — the wire lifts off it.",
            "Fit two closed-eye hooks, locking earthquake hangers, or screw eyes and wire into the frame's stiles, spread wide.",
            "Fix into studs where the piece is heavier than about 5 kg; into good plasterboard anchors only for light frames.",
            "Hang from two points, level, so the piece cannot swing and unhook itself.",
            "For anything large and unlaminated, apply safety film to the back of the glass so a break stays in one piece.",
        ],
        hardware: [closedHook, screwEyeAndWire],
        estimatedCostUSD: 8...25,
        difficulty: .basic, minutes: 20,
        femaReference: "FEMA E-74 §6.4.4",
        symbolName: "photo.fill",
        venue: .hardwareStore,
        warning: "Never a single open hook. Two-point mounting, closed hooks, and into studs for anything heavy.",
        effect: MitigationEffect(setsAnchored: true),
        basePriority: 12)

    public static let leaningMirrorAnchor = Mitigation(
        id: "leaning-mirror-anchor",
        title: "Fix the mirror to the wall, or take it out of the bedroom",
        summary: "A leaning full-length mirror is a square metre of unlaminated glass falling at head height, held up by friction alone.",
        steps: [
            "Decide first whether it needs to be in this room at all. A leaning mirror in a bedroom is a documented injury source.",
            "If it stays, fix it: a bottom J-channel screwed to the floor or skirting, and two clips or a French cleat at the top into studs.",
            "Apply safety film to the back of the glass so a break holds together.",
            "Never leave it simply resting against the wall. Its base slides out at far less shaking than a free-standing block needs.",
        ],
        hardware: [mirrorClip, safetyFilm, lagScrew65],
        estimatedCostUSD: 20...60,
        difficulty: .moderate, minutes: 45,
        femaReference: "FEMA E-74 §6.4.4",
        symbolName: "rectangle.portrait.on.rectangle.portrait.fill",
        venue: .hardwareStore,
        warning: drywallWarning,
        effect: MitigationEffect(setsAnchored: true),
        basePriority: 4)

    public static let aquariumStrap = Mitigation(
        id: "aquarium-strap",
        title: "Strap the tank and its stand, and move it away from the bed",
        summary: "Glass, water and a mains heater, at chest height, on a stand that was built for a still room.",
        steps: [
            "Move it away from beds, seating and electronics first. Water finds the sockets.",
            "Strap the stand to wall studs with nylon appliance straps, top and bottom.",
            "Strap the tank to the stand — a tank that walks off its stand is the usual failure, not the stand tipping.",
            "Leave 25 mm of freeboard and fit a lid, so sloshing does not empty it.",
            "Put the heater and the pump on their own RCD/GFCI circuit.",
        ],
        hardware: [applianceStrap, lagScrew65],
        estimatedCostUSD: 20...50,
        difficulty: .moderate, minutes: 45,
        femaReference: "FEMA E-74 §6.4",
        symbolName: "fish.fill",
        venue: .hardwareStore,
        warning: drywallWarning,
        effect: MitigationEffect(setsAnchored: true),
        basePriority: 8)

    public static let lockCastors = Mitigation(
        id: "lock-castors",
        title: "Lock or remove the castors",
        summary: "On wheels it rolls at almost any shaking. A 250 kg piano rolling across a room is not something you stop.",
        steps: [
            "Lock every castor that has a brake. If it has no brake, replace the wheels with fixed glides or a solid foot.",
            "Drop each wheel into a hardwood or high-density rubber castor cup so it cannot roll out.",
            "For a piano, add a strap from the back frame to studs as well: it is tall enough and heavy enough to be a life-safety item.",
            "Keep it away from the route to the door.",
        ],
        hardware: [castorCups, nylonFurnitureStrap],
        estimatedCostUSD: 10...45,
        difficulty: .basic, minutes: 30,
        femaReference: "FEMA E-74 §6.4",
        symbolName: "pianokeys",
        venue: .hardwareStore,
        warning: nil,
        effect: MitigationEffect(setsAnchored: true),
        basePriority: 8)

    public static let relocateTallLightObject = Mitigation(
        id: "relocate-tall-light",
        title: "Move it away from where people are, and weight the base",
        summary: "Tall and light is the easiest thing in the room to knock over — and it usually has a cable attached.",
        steps: [
            "Move it out of the walking route and away from the head of any bed or sofa.",
            "Put a weight in or on the base: a sandbag, a paving slab under the base plate, a heavier base plate.",
            "Tether the upper part to the wall with a thin nylon strap or a screw eye and wire if it stands taller than 1.5 m.",
            "Route the cable so a fall does not pull the plug half out of the socket.",
        ],
        hardware: [nylonFurnitureStrap],
        estimatedCostUSD: 0...20,
        difficulty: .free, minutes: 15,
        femaReference: "FEMA E-74 §6.4",
        symbolName: "lamp.floor.fill",
        venue: .nothingToBuy,
        warning: nil,
        effect: MitigationEffect(relocates: true),
        basePriority: 16)

    public static let antiSlipMatAdvice = Mitigation(
        id: "anti-slip-mat",
        title: "Put it on an anti-slip mat",
        summary: "A silicone mat roughly triples the shaking it takes to start sliding.",
        steps: [
            "Cut a silicone or TPE anti-slip mat to the footprint.",
            "Lift one end at a time and slide the mat underneath, covering every foot.",
            "This stops it sliding. It does not stop it tipping — anything tall still needs anchoring.",
        ],
        hardware: [antiSlipMat],
        estimatedCostUSD: 6...20,
        difficulty: .basic, minutes: 10,
        femaReference: "FEMA E-74 §6.4",
        symbolName: "square.grid.3x3.fill",
        venue: .hardwareStore,
        warning: "A mat raises the sliding threshold only. A slender object will now rock instead of slide, "
            + "which for a tall bookcase is worse. Anchor tall things; mat squat ones.",
        effect: MitigationEffect(frictionMultiplier: 1.10),
        basePriority: 24)

    public static let hangingFixtureCable = Mitigation(
        id: "hanging-fixture-safety-cable",
        title: "Add a safety cable above the fixture",
        summary: "Pendants and chandeliers swing hard, and the fitting is usually the weakest part.",
        steps: [
            "Turn the power off at the consumer unit, not just at the switch.",
            "Run a 1.5 mm steel safety cable from the fixture body up to the joist or the outlet-box strap, with a closed loop at each end.",
            "Leave just enough slack that the cable is not carrying the load, but catches it if the fitting lets go.",
            "Replace any open hook with a closed one.",
            "Nothing heavy hangs directly over a bed, a crib, or the dining table's head seat.",
        ],
        hardware: [safetyCable],
        estimatedCostUSD: 8...25,
        difficulty: .moderate, minutes: 30,
        femaReference: "FEMA E-74 §6.3",
        symbolName: "lightbulb.fill",
        venue: .hardwareStore,
        warning: nil,
        effect: MitigationEffect(setsAnchored: true),
        basePriority: 14)

    public static let flexibleSupplyLines = Mitigation(
        id: "flexible-supply-lines",
        title: "Check the supply lines are flexible",
        summary: "A fixture that barely moves still shears a rigid supply pipe, and a slow flood does more damage than the quake.",
        steps: [
            "Look under and behind it. Rigid copper or steel tube straight into the fitting is the problem.",
            "Replace with braided stainless flexible connectors, sized correctly, with a gentle loop of slack.",
            "Know where the whole-house water shut-off is, and keep the key with it.",
            "Any gas connection is a licensed job. Do not touch it yourself.",
        ],
        hardware: [flexibleWaterConnector],
        estimatedCostUSD: 15...80,
        difficulty: .professional, minutes: 45,
        femaReference: "FEMA E-74 §6.5",
        symbolName: "pipe.and.drop.fill",
        venue: .professional,
        warning: nil,
        effect: .none,
        basePriority: 30)

    public static let builtInFixingCheck = Mitigation(
        id: "built-in-fixing-check",
        title: "Check what is actually holding it in",
        summary: "Built in is not the same as anchored. Half of these are held by two screws into a cabinet side.",
        steps: [
            "Open the door and look for the mounting brackets at the top or the sides.",
            "If you find nothing, add the manufacturer's anti-tip or mounting bracket into the cabinet frame or a stud.",
            "Check the supply lines behind it are flexible and have slack.",
        ],
        hardware: [cabinetScrews],
        estimatedCostUSD: 0...20,
        difficulty: .basic, minutes: 20,
        femaReference: "FEMA E-74 §6.5",
        symbolName: "wrench.adjustable.fill",
        venue: .hardwareStore,
        warning: nil,
        effect: .none,
        basePriority: 32)

    public static let keepAboveBedClear = Mitigation(
        id: "keep-above-bed-clear",
        title: "Keep the wall above it bare",
        summary: "The single highest-value thing you can do in a bedroom: nothing heavy above a bed or a crib. Ever.",
        steps: [
            "Stand at the foot of the bed and look at the wall above the pillow. It should be empty.",
            "No shelf, no picture, no mirror, no television, no hanging light. A sleeping person cannot move.",
            "Check the wall beside the head of the bed too: anything taller than the mattress is high enough to reach it.",
            "Anything that must stay in the room goes on the far wall, low.",
        ],
        estimatedCostUSD: 0...0,
        difficulty: .free, minutes: 10,
        femaReference: "FEMA E-74 §6.4",
        symbolName: "bed.double.fill",
        venue: .nothingToBuy,
        warning: nil,
        effect: .none,
        basePriority: 3)

    public static let keepSeatingClear = Mitigation(
        id: "keep-seating-clear",
        title: "Look at what is above where you sit",
        summary: "The furniture itself is fine. What is on the wall behind it is the question.",
        steps: [
            "Sit down and look up. Shelves, framed art, mirrors and televisions above seating all land in the same place.",
            "Move anything heavy off that wall, or anchor it into studs with two-point fixings.",
            "Keep the route from here to the door clear of anything tall.",
        ],
        estimatedCostUSD: 0...0,
        difficulty: .free, minutes: 10,
        femaReference: "FEMA E-74 §6.4",
        symbolName: "sofa.fill",
        venue: .nothingToBuy,
        warning: nil,
        effect: .none,
        basePriority: 34)

    public static let clearTabletop = Mitigation(
        id: "clear-tabletop",
        title: "Clear the top, or stick down what is on it",
        summary: "The tabletop is a launch pad. Everything on it slides off before the table itself does anything.",
        steps: [
            "Take the breakables off the top, or move them to a closed cabinet.",
            "Putty down anything that stays, up to about 5 kg.",
            "Nothing glass or heavy on a surface above waist height.",
        ],
        hardware: [museumPutty],
        estimatedCostUSD: 0...15,
        difficulty: .basic, minutes: 15,
        femaReference: "FEMA E-74 §6.4.7",
        symbolName: "table.furniture.fill",
        venue: .online,
        warning: nil,
        effect: .none,
        basePriority: 28)

    public static let keepStairsClear = Mitigation(
        id: "keep-stairs-clear",
        title: "Keep the stairs and landings clear",
        summary: "The stairs are how you get out. Nothing tall stands beside them and nothing hangs over them.",
        steps: [
            "Move anything taller than a metre off the landings and away from the top of the flight.",
            "Take pictures and mirrors off the stairwell wall, or refit them on closed hooks into studs.",
            "Check the handrail is screwed into studs, not into plasterboard.",
            "Keep a torch and shoes where you can reach them without crossing the room.",
        ],
        estimatedCostUSD: 0...0,
        difficulty: .free, minutes: 15,
        femaReference: "FEMA E-74 §6.4",
        symbolName: "stairs",
        venue: .nothingToBuy,
        warning: nil,
        effect: .none,
        basePriority: 30)

    public static let fireplaceCheck = Mitigation(
        id: "fireplace-check",
        title: "Clear the mantel and have the chimney looked at",
        summary: "Unreinforced masonry chimneys are one of the most reliably damaged parts of a house, and the mantel is a shelf at head height.",
        steps: [
            "Take the heavy ornaments off the mantel, or putty down the small ones.",
            "No mirror or large framed piece directly above the hearth unless it is on two closed hooks into studs, with safety film.",
            "Have an unreinforced masonry chimney inspected and, if it is tall, braced or strapped at the roofline by a contractor.",
            "Keep the hearth itself clear so a fallen chimney flue has somewhere to land that is not your floor.",
        ],
        hardware: [museumPutty],
        estimatedCostUSD: 0...15,
        difficulty: .moderate, minutes: 30,
        femaReference: "FEMA E-74 §6.3",
        symbolName: "fireplace.fill",
        venue: .online,
        warning: nil,
        effect: .none,
        basePriority: 30)

    public static let genericAnchorAdvice = Mitigation(
        id: "generic-secure",
        title: "Secure it the way its shape demands",
        summary: "We are not sure exactly what this is, so here is the rule that always applies.",
        steps: [
            "If it is taller than it is wide: anchor the top to a stud with a bracket or a strap.",
            "If it is small and sits on a surface: a pea of museum putty under each corner.",
            "If it hangs on a wall: two closed hooks, never one open hook.",
            "If it is on wheels: lock them.",
            "If you can tell us what it is, tap the name and we will give you the specific fix.",
        ],
        hardware: [nylonFurnitureStrap, museumPutty],
        estimatedCostUSD: 5...30,
        difficulty: .basic, minutes: 25,
        femaReference: "FEMA E-74 §6.4",
        symbolName: "questionmark.circle.fill",
        venue: .hardwareStore,
        warning: drywallWarning,
        effect: MitigationEffect(setsAnchored: true),
        basePriority: 40)

    // MARK: All

    public static let all: [Mitigation] = [
        removeAboveBed, relocateAwayFromBed, relocateAwayFromPath,
        anchorTallFurniture, antiTipKitAdvice, loadBottomFirst, shelfLipAdvice,
        doorLatches, upperCabinetAnchor, rangeAntiTip, applianceStrapAdvice,
        washerDryerStrap, waterHeaterStraps, tvTether, tvWallMountAdvice,
        avEquipmentStrap, museumPuttyAdvice, closedHooks, leaningMirrorAnchor,
        aquariumStrap, lockCastors, relocateTallLightObject, antiSlipMatAdvice,
        hangingFixtureCable, flexibleSupplyLines, builtInFixingCheck,
        keepAboveBedClear, keepSeatingClear, clearTabletop, keepStairsClear,
        fireplaceCheck, genericAnchorAdvice,
    ]

    private static let byID: [String: Mitigation] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func mitigation(id: String) -> Mitigation? { byID[id] }

    // MARK: - Advice

    /// The ordered, deduplicated advice for one object.
    ///
    /// Ordering is not cosmetic. The first card is what the user will actually
    /// do, so the free rearrangement that removes the hazard outright must come
    /// before the bracket that merely restrains it, and a legal requirement must
    /// come before both.
    ///
    /// - Parameters:
    ///   - object: the object to advise on.
    ///   - risk: its verdict, if the room has been assessed. Advice is still
    ///     produced without one — the user may be browsing before simulating —
    ///     but a risk lets the ordering respond to what actually happened.
    ///   - room: the room it stands in, which decides what is above a bed and
    ///     what blocks the door.
    public static func advice(
        for object: ScannedObject,
        risk: ObjectRisk? = nil,
        in room: ScannedRoom
    ) -> [Mitigation] {
        var scored: [(mitigation: Mitigation, rank: Int)] = []
        var seen = Set<String>()

        func add(_ mitigation: Mitigation, rank: Int? = nil) {
            guard !seen.contains(mitigation.id) else { return }
            seen.insert(mitigation.id)
            scored.append((mitigation, rank ?? mitigation.basePriority))
        }

        // ---- Context that outranks everything the type says ----

        // FEMA's strongest single piece of advice, and the app's too.
        if isAboveSleepingPlace(object, in: room) {
            add(removeAboveBed, rank: -100)
        }

        // "Rearrange it instead": free, and better than anchoring, because an
        // anchored bookcase beside a bed still empties its shelves onto it.
        if reachesSleepingPlace(object, in: room) && !object.type.isSleepingPlace {
            add(relocateAwayFromBed, rank: -80)
        }

        // Legally required, regardless of what the physics said.
        switch object.type {
        case .waterHeater, .waterHeaterGas:
            add(waterHeaterStraps, rank: -90)
        case .rangeGas, .rangeElectric:
            add(rangeAntiTip, rank: -60)
        case .mirrorLeaning:
            add(leaningMirrorAnchor, rank: -60)
        default:
            break
        }

        // ---- What the type itself needs ----

        for mitigation in baseAdvice(for: object) {
            add(mitigation)
        }

        // ---- What the verdict and the room add ----

        if let risk {
            if risk.consequence.egressBlockage >= 0.6, object.canMove,
               Double(object.extents.height) > 0.9 {
                add(relocateAwayFromPath, rank: 6)
            }
            // A regulatory override means the object is dangerous for reasons
            // the room geometry cannot see. Pull its primary fix to the front.
            if risk.hasRegulatoryOverride,
               let leadIndex = scored.indices.min(by: { scored[$0].rank < scored[$1].rank }) {
                scored[leadIndex].rank = min(scored[leadIndex].rank, -70)
            }
            // Something that slides but cannot tip wants a mat, not a bracket.
            if risk.dominantBehaviour == .slid, object.slenderness < 3,
               object.type.footing != .castor {
                add(antiSlipMatAdvice, rank: 18)
            }
        }

        if object.type.footing == .castor {
            add(lockCastors, rank: 8)
        }

        // Anything standing on a surface above the floor can be puttied down if
        // it is light enough — the spec refuses putty above 5 kg.
        if object.supportHeight > 0.05 && object.mass <= 5.0 {
            add(museumPuttyAdvice, rank: 20)
        }

        if object.type.hasSpillableContents {
            add(loadBottomFirst)
        }

        // Never leave an object with nothing to say.
        if scored.isEmpty {
            add(genericAnchorAdvice)
        }

        // Already anchored: the structural fixes are done, so lead with what is
        // left — the contents, the glass, and the cables.
        if !object.canMove {
            for index in scored.indices where scored[index].mitigation.effect.setsAnchored {
                scored[index].rank += 200
            }
        }

        return scored
            .enumerated()
            .sorted { a, b in
                a.element.rank != b.element.rank
                    ? a.element.rank < b.element.rank
                    : a.offset < b.offset
            }
            .map(\.element.mitigation)
    }

    /// The advice that follows from the object's type alone, before the room
    /// has any say. Every `ObjectType` returns at least one entry.
    private static func baseAdvice(for object: ScannedObject) -> [Mitigation] {
        switch object.type {

        // Tall case goods: anchor, then restrain the contents.
        case .bookshelfTall, .bookshelfShort:
            return [anchorTallFurniture, shelfLipAdvice, loadBottomFirst]

        case .wardrobe, .chinaCabinet:
            return [anchorTallFurniture, doorLatches, loadBottomFirst]

        case .highboy, .dresser:
            return [antiTipKitAdvice, loadBottomFirst, clearTabletop]

        case .filingCabinet:
            return [anchorTallFurniture, doorLatches, loadBottomFirst]

        case .nightstand:
            return [clearTabletop, antiSlipMatAdvice]

        case .kitchenCabinetUpper:
            return [upperCabinetAnchor, doorLatches]

        case .trunk, .storageBin:
            return [loadBottomFirst, antiSlipMatAdvice]

        // Tables, desks and seating.
        case .desk:
            return [avEquipmentStrap, clearTabletop, antiSlipMatAdvice]

        case .diningTable, .coffeeTable:
            return [clearTabletop, antiSlipMatAdvice]

        case .diningChair, .armchair, .sofa:
            return [keepSeatingClear]

        case .officeChair:
            return [lockCastors, keepSeatingClear]

        case .bed, .crib:
            return [keepAboveBedClear]

        // Displays and electronics.
        case .television:
            return [tvTether, avEquipmentStrap]

        case .televisionWallMounted:
            return [tvWallMountAdvice]

        case .computerMonitor, .speaker:
            return [avEquipmentStrap, museumPuttyAdvice]

        // Appliances.
        case .refrigerator:
            return [applianceStrapAdvice, flexibleSupplyLines]

        case .washingMachine, .clothesDryer:
            return [washerDryerStrap, flexibleSupplyLines]

        case .rangeGas, .rangeElectric:
            return [rangeAntiTip, doorLatches]

        case .oven, .dishwasher:
            return [builtInFixingCheck, flexibleSupplyLines]

        case .microwave:
            return [antiSlipMatAdvice, avEquipmentStrap]

        case .waterHeater, .waterHeaterGas:
            return [waterHeaterStraps, flexibleSupplyLines]

        // Plumbing fixtures: anchored by construction, but their connections
        // are not, and a slow flood outlasts the earthquake.
        case .sink, .toilet, .bathtub:
            return [flexibleSupplyLines, clearTabletop]

        case .fireplace:
            return [fireplaceCheck]

        case .stairs:
            return [keepStairsClear]

        // Decor.
        case .floorLamp, .plantPotLarge:
            return [relocateTallLightObject]

        case .tableLamp, .plantPotSmall, .vaseCeramic, .vaseGlass:
            return [museumPuttyAdvice, clearTabletop]

        case .mirrorWall, .framedPicture:
            return [closedHooks]

        case .mirrorLeaning:
            return [leaningMirrorAnchor]

        case .books:
            return [shelfLipAdvice, loadBottomFirst]

        case .aquarium:
            return [aquariumStrap, flexibleSupplyLines]

        case .pianoUpright:
            return [lockCastors, anchorTallFurniture]

        case .unknown:
            return [genericAnchorAdvice]
        }
    }

    // MARK: - Spatial helpers

    /// Mirrors `RiskEngine`'s own test: is this mounted or stacked directly
    /// above a bed or crib? Kept here rather than shared because the advice
    /// layer must not reach into the risk engine's private reasoning, and
    /// because advice has to work before an assessment exists.
    public static func isAboveSleepingPlace(_ object: ScannedObject, in room: ScannedRoom) -> Bool {
        guard !object.type.isSleepingPlace,
              object.topHeight > 0.9,
              object.mass > 2.0,
              object.mounting == .wallMounted || object.supportHeight > 0.5
        else { return false }
        let position = object.groundPosition
        return room.objects.contains { bed in
            guard bed.type.isSleepingPlace else { return false }
            let dx = abs(position.x - bed.groundPosition.x)
            let dz = abs(position.y - bed.groundPosition.y)
            return dx < bed.extents.width / 2 + 0.4 && dz < bed.extents.depth / 2 + 0.4
        }
    }

    /// Can this object, standing where it stands, reach a bed or a crib if it
    /// goes over? A fallen piece reaches out by about its own height.
    public static func reachesSleepingPlace(_ object: ScannedObject, in room: ScannedRoom) -> Bool {
        guard object.canMove, Double(object.extents.height) > 0.6 else { return false }
        let reach = Double(object.extents.height) + 0.3
        let position = object.groundPosition
        return room.objects.contains { bed in
            guard bed.type.isSleepingPlace, bed.id != object.id else { return false }
            let half = Double(max(bed.extents.width, bed.extents.depth)) / 2
            return Double(simd_distance(position, bed.groundPosition)) - half < reach
        }
    }
}
