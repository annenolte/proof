import Foundation

/// A specific piece of fixing hardware, with a published withdrawal capacity.
///
/// Capacities are single-fastener working values into the material named, taken
/// from the ranges quoted in `docs/research/science-seismic.md` §7.3.1 and from
/// standard fastener tables. They are deliberately conservative: the point of
/// this list is to let the app say "that is not enough" with confidence, not to
/// certify an installation.
public enum FixingType: String, Codable, CaseIterable, Sendable, Identifiable {
    /// A plastic expansion plug in plasterboard. Included because it is what
    /// people reach for, not because it works.
    case drywallPlug
    /// A metal toggle or butterfly anchor in 12.5 mm plasterboard.
    case drywallToggle
    /// A heavy-duty snap-toggle in plasterboard.
    case drywallSnapToggle
    /// 6 mm × 65 mm (¼″ × 2½″) lag screw into a timber stud — the reference
    /// fixing every FEMA E-74 detail assumes.
    case lagScrewIntoStud
    /// 8 mm × 75 mm (5⁄16″ × 3″) lag screw into a timber stud.
    case heavyLagScrewIntoStud
    /// A proprietary structural wood screw into a stud.
    case structuralWoodScrew
    /// A 6 mm sleeve or wedge anchor into solid concrete or filled masonry.
    case concreteAnchor

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .drywallPlug: return "Plastic plug in plasterboard"
        case .drywallToggle: return "Toggle bolt in plasterboard"
        case .drywallSnapToggle: return "Heavy-duty snap toggle"
        case .lagScrewIntoStud: return "6 mm × 65 mm lag screw into a stud"
        case .heavyLagScrewIntoStud: return "8 mm × 75 mm lag screw into a stud"
        case .structuralWoodScrew: return "Structural wood screw into a stud"
        case .concreteAnchor: return "6 mm sleeve anchor into concrete"
        }
    }

    /// Working capacity of one fastener in newtons.
    public var capacityNewtons: Double {
        switch self {
        case .drywallPlug: return 90
        case .drywallToggle: return 200
        case .drywallSnapToggle: return 350
        case .lagScrewIntoStud: return 2700
        case .heavyLagScrewIntoStud: return 4000
        case .structuralWoodScrew: return 3100
        case .concreteAnchor: return 4500
        }
    }

    public var capacityPoundsForce: Double {
        AnchorageCalculator.poundsForce(fromNewtons: capacityNewtons)
    }

    /// True when the fixing lands in structure rather than in the paper face of
    /// a sheet of plasterboard.
    public var reachesStructure: Bool {
        switch self {
        case .drywallPlug, .drywallToggle, .drywallSnapToggle: return false
        case .lagScrewIntoStud, .heavyLagScrewIntoStud,
             .structuralWoodScrew, .concreteAnchor: return true
        }
    }

    /// The fixings the app offers as candidates, worst first, so the verdict
    /// list reads as an argument rather than a catalogue.
    public static var commonCandidates: [FixingType] {
        [.drywallPlug, .drywallToggle, .drywallSnapToggle,
         .lagScrewIntoStud, .heavyLagScrewIntoStud, .concreteAnchor]
    }
}

/// Whether one kind of fixing is up to the job.
public struct FixingVerdict: Codable, Hashable, Sendable, Identifiable {
    public var id: String { fixing.rawValue }
    public var fixing: FixingType
    public var capacityNewtons: Double
    public var capacityPoundsForce: Double
    /// Capacity divided by the demand on one fixing. Above 1.0 it holds.
    public var utilisation: Double
    public var isAdequate: Bool
    public var note: String

    public init(fixing: FixingType, demandPerFixingNewtons: Double) {
        self.fixing = fixing
        self.capacityNewtons = fixing.capacityNewtons
        self.capacityPoundsForce = fixing.capacityPoundsForce
        let ratio = fixing.capacityNewtons / max(demandPerFixingNewtons, 0.001)
        self.utilisation = ratio
        self.isAdequate = ratio >= 1.0
        if ratio >= 3 {
            note = "Comfortably adequate."
        } else if ratio >= 1 {
            note = String(format: "Adequate, with %.1f× margin.", ratio)
        } else if fixing.reachesStructure {
            note = "Not enough on its own — use more fixings or a heavier screw."
        } else {
            note = "Not adequate. This is a plasterboard fixing; the load needs structure."
        }
    }
}

/// The anchorage demand for one object, in the units the hardware is sold in.
public struct AnchorageRequirement: Codable, Hashable, Sendable {
    /// Operating weight of the component, W_p, in newtons.
    public var weightNewtons: Double
    public var massKg: Double
    /// Height ratio z/h used in ASCE 7-16 Eq. 13.3-1.
    public var heightRatio: Double
    /// Short-period design spectral acceleration, S_DS.
    public var sds: Double
    /// F_p / W_p — the seismic coefficient actually applied, after the bounds.
    public var seismicCoefficient: Double
    /// F_p, the total design force in newtons.
    public var designForceNewtons: Double
    public var designForcePoundsForce: Double
    /// How many fixings the force is split across.
    public var fixingCount: Int
    public var forcePerFixingNewtons: Double
    public var forcePerFixingPoundsForce: Double
    /// Whether the lower bound 0.3·S_DS·I_p·W_p governed rather than the
    /// height-dependent term. Reported because a user on the ground floor
    /// otherwise wonders why the number did not go to zero.
    public var lowerBoundGoverned: Bool
    public var upperBoundGoverned: Bool
    public var verdicts: [FixingVerdict]

    /// The hardware the app recommends: the cheapest candidate that works.
    public var recommendedFixing: FixingType? {
        verdicts.first(where: \.isAdequate)?.fixing
    }

    /// One sentence, in both unit systems, for the detail sheet.
    public var summary: String {
        String(
            format: "%.0f kg on this floor needs anchorage for %.0f N (%.0f lbf) in total — "
                + "%.0f N (%.0f lbf) at each of %d fixings.",
            massKg, designForceNewtons, designForcePoundsForce,
            forcePerFixingNewtons, forcePerFixingPoundsForce, fixingCount)
    }

    /// The line that stops the most common mistake.
    public var plasterboardWarning: String? {
        let toggle = FixingType.drywallToggle
        guard toggle.capacityNewtons < forcePerFixingNewtons else { return nil }
        return String(
            format: "A plasterboard toggle carries about %.0f N (%.0f lbf). This fixing has to carry "
                + "%.0f N (%.0f lbf). Find the stud — a 6 mm × 65 mm lag screw into one carries "
                + "about 2,700 N (610 lbf).",
            toggle.capacityNewtons, toggle.capacityPoundsForce,
            forcePerFixingNewtons, forcePerFixingPoundsForce)
    }

    /// The working shown, for the "how did you get that" disclosure.
    public var derivation: String {
        String(
            format: "ASCE 7-16 Eq. 13.3-1: F_p = 0.4 · a_p · S_DS · W_p · (1 + 2z/h) / (R_p/I_p) "
                + "with a_p = 1.0, R_p = 1.5, I_p = 1.0, S_DS = %.2f, z/h = %.2f "
                + "→ F_p = %.3f · W_p = %.0f N.",
            sds, heightRatio, seismicCoefficient, designForceNewtons)
    }
}

/// Sizes the hardware, using ASCE 7-16 Eq. 13.3-1 exactly as
/// `docs/research/science-seismic.md` §7.3.1 sets it out.
///
/// **This is the only place `R_p` may appear.** `R_p` is a design ductility
/// allowance for sizing anchors, not a physical quantity; dividing the motion by
/// it anywhere in the simulation path would under-predict what the furniture
/// actually experiences by a factor of 1.5 to 6.
public enum AnchorageCalculator {

    /// Newtons per pound-force. The user buys hardware labelled in pounds, so
    /// every number in this file is reported both ways.
    public static let newtonsPerPoundForce: Double = 4.4482216152605

    public static func poundsForce(fromNewtons n: Double) -> Double {
        n / newtonsPerPoundForce
    }

    public static func newtons(fromPoundsForce lbf: Double) -> Double {
        lbf * newtonsPerPoundForce
    }

    /// z/h for a room: the height of its floor above grade over the total
    /// height of the building. Storey heights cancel, so this is just the
    /// storey index over the storey count.
    public static func heightRatio(for context: BuildingContext) -> Double {
        let total = max(context.totalStoreys, 1)
        return min(max(Double(context.floor) / Double(total), 0), 1)
    }

    /// F_p / W_p, the seismic coefficient, after the code's own bounds.
    ///
    /// `F_p = 0.4 · a_p · S_DS · (1 + 2z/h) / (R_p / I_p) · W_p`,
    /// bounded by `0.3 · S_DS · I_p ≤ F_p/W_p ≤ 1.6 · S_DS · I_p`.
    public static func seismicCoefficient(
        heightRatio: Double, sds: Double = 1.0,
        ap: Double = 1.0, rp: Double = 1.5, ip: Double = 1.0
    ) -> (coefficient: Double, lowerBoundGoverned: Bool, upperBoundGoverned: Bool) {
        let raw = 0.4 * ap * sds * (1 + 2 * heightRatio) / (rp / ip)
        let lower = 0.3 * sds * ip
        let upper = 1.6 * sds * ip
        if raw < lower { return (lower, true, false) }
        if raw > upper { return (upper, false, true) }
        return (raw, false, false)
    }

    /// The total design force in newtons for a mass on a given floor.
    public static func designForceNewtons(
        massKg: Double, context: BuildingContext, sds: Double = 1.0,
        ap: Double = 1.0, rp: Double = 1.5, ip: Double = 1.0
    ) -> Double {
        let z = heightRatio(for: context)
        let c = seismicCoefficient(heightRatio: z, sds: sds, ap: ap, rp: rp, ip: ip).coefficient
        return c * massKg * Physics.g
    }

    /// The full requirement, split across fixings, with a verdict on each of the
    /// fixings a person might actually use.
    public static func requirement(
        massKg: Double,
        context: BuildingContext,
        sds: Double = 1.0,
        fixings: Int = 2,
        ap: Double = 1.0, rp: Double = 1.5, ip: Double = 1.0,
        candidates: [FixingType] = FixingType.commonCandidates
    ) -> AnchorageRequirement {
        let mass = max(massKg, 0.1)
        let count = max(fixings, 1)
        let z = heightRatio(for: context)
        let c = seismicCoefficient(heightRatio: z, sds: sds, ap: ap, rp: rp, ip: ip)
        let weight = mass * Physics.g
        let force = c.coefficient * weight
        let perFixing = force / Double(count)

        return AnchorageRequirement(
            weightNewtons: weight,
            massKg: mass,
            heightRatio: z,
            sds: sds,
            seismicCoefficient: c.coefficient,
            designForceNewtons: force,
            designForcePoundsForce: poundsForce(fromNewtons: force),
            fixingCount: count,
            forcePerFixingNewtons: perFixing,
            forcePerFixingPoundsForce: poundsForce(fromNewtons: perFixing),
            lowerBoundGoverned: c.lowerBoundGoverned,
            upperBoundGoverned: c.upperBoundGoverned,
            verdicts: candidates.map {
                FixingVerdict(fixing: $0, demandPerFixingNewtons: perFixing)
            })
    }

    /// The requirement for a scanned object in a scanned room, using the
    /// recommended number of fixings for its size.
    public static func requirement(
        for object: ScannedObject,
        in room: ScannedRoom,
        sds: Double = 1.0,
        fixings: Int? = nil
    ) -> AnchorageRequirement {
        requirement(
            massKg: object.mass,
            context: room.building,
            sds: sds,
            fixings: fixings ?? recommendedFixingCount(for: object))
    }

    /// How many fixings the app tells the user to install.
    ///
    /// Two is the FEMA E-74 minimum for a piece of furniture — one bracket per
    /// stud at the top corners. Wide or heavy pieces get more, because studs are
    /// at 400 mm centres and a 1.6 m wide unit crosses four of them, and because
    /// splitting the load is how you get a lag screw back inside its capacity.
    public static func recommendedFixingCount(for object: ScannedObject) -> Int {
        var count = 2
        // One fixing per stud the piece spans, capped at something sane.
        let widthMetres = Double(max(object.extents.width, object.extents.depth))
        let studsSpanned = Int((widthMetres / 0.4).rounded(.down)) + 1
        count = max(count, min(studsSpanned, 4))
        if object.mass > 150 { count = max(count, 4) }
        if object.mounting == .suspended { count = max(count, 2) }
        return count
    }

    /// The worked example from §7.3.1, kept as a named value so the UI can show
    /// the app's arithmetic against a published one.
    public static var worked140kgBookcaseOnSecondFloor: AnchorageRequirement {
        requirement(
            massKg: 140,
            context: BuildingContext(floor: 1, totalStoreys: 2),
            sds: 1.0,
            fixings: 2)
    }
}
