import Foundation

/// The surface an object stands on.
public enum FloorSurface: String, Codable, CaseIterable, Sendable, Identifiable {
    case hardwood
    case laminate        // laminate, vinyl, LVT
    case tile            // glazed ceramic / porcelain
    case carpet
    case rug             // a rug over a hard floor: the rug itself can slide
    case concrete        // polished or sealed concrete
    case woodShelf       // the top of a bookcase, table, dresser
    case glassShelf
    case stoneCounter    // granite, quartz, marble

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .hardwood: return "Hardwood"
        case .laminate: return "Laminate or vinyl"
        case .tile: return "Tile"
        case .carpet: return "Carpet"
        case .rug: return "Rug over hard floor"
        case .concrete: return "Concrete"
        case .woodShelf: return "Wooden shelf or tabletop"
        case .glassShelf: return "Glass shelf"
        case .stoneCounter: return "Stone countertop"
        }
    }

    /// True for the surfaces a room's *floor* can plausibly be, as opposed to
    /// the surfaces an object can sit on top of. Drives the floor picker.
    public var isFloorType: Bool {
        switch self {
        case .hardwood, .laminate, .tile, .carpet, .rug, .concrete: return true
        case .woodShelf, .glassShelf, .stoneCounter: return false
        }
    }
}

/// What the object actually touches the surface with. Furniture almost never
/// contacts the floor with its bulk material — it contacts it with feet, glides,
/// castors or pads, and that contact dominates the friction.
public enum Footing: String, Codable, CaseIterable, Sendable {
    case wood            // bare wood or particleboard base
    case rubber          // rubber feet: appliances, washing machines
    case felt            // felt furniture pads — an anti-mitigation
    case plasticGlide    // moulded plastic glides, most flat-pack furniture
    case ptfeGlide       // PTFE / nylon glides — the worst case
    case metal           // steel or aluminium feet
    case ceramic         // a ceramic object's own base
    case glass           // a glass object's own base
    case plasticBody     // a plastic object sitting directly on its body
    case paper           // books, cardboard boxes
    case castor          // wheels — effectively frictionless in translation
    case antiSlipMat     // silicone/TPE mat: a mitigation
    case museumPutty     // museum putty or wax: a strong mitigation

    public var displayName: String {
        switch self {
        case .wood: return "Wooden feet"
        case .rubber: return "Rubber feet"
        case .felt: return "Felt pads"
        case .plasticGlide: return "Plastic glides"
        case .ptfeGlide: return "PTFE glides"
        case .metal: return "Metal feet"
        case .ceramic: return "Ceramic base"
        case .glass: return "Glass base"
        case .plasticBody: return "Plastic base"
        case .paper: return "Paper or card"
        case .castor: return "Castors"
        case .antiSlipMat: return "Anti-slip mat"
        case .museumPutty: return "Museum putty"
        }
    }
}

/// A static/kinetic friction pair.
public struct FrictionPair: Sendable, Equatable {
    public let staticCoefficient: Double
    public let kineticCoefficient: Double

    public init(_ staticCoefficient: Double, _ kineticCoefficient: Double? = nil) {
        self.staticCoefficient = staticCoefficient
        // Where only one value is measured, μ_k ≈ 0.85·μ_s is the standard
        // modelling assumption (Marks' Handbook; Chaudhuri & Hutchinson 2005).
        self.kineticCoefficient = kineticCoefficient ?? staticCoefficient * 0.85
    }
}

/// Design friction coefficients for the contact pairs that occur in a home.
///
/// Values are the "μ_design" column of the compiled table in
/// `docs/research/science-seismic.md` §5, which draws on:
///
/// - Marks' *Standard Handbook for Mechanical Engineers*, 12th ed., Table 3.2.1
/// - Chaudhuri & Hutchinson (2005), *Characterizing frictional behavior for use
///   in predicting the seismic response of unattached equipment*, SDEE 25(7–10)
/// - López García & Soong (2003), *Sliding fragility of block-type
///   non-structural components*, EESD 32(1)
/// - Bowden & Tabor, *The Friction and Lubrication of Solids*
///
/// Friction is the single largest source of uncertainty in the whole model,
/// because the slide-or-rock branch turns on the hard comparison μ_s ≶ b/h.
/// That is why `sample(_:variability:)` exists: the risk verdict is computed
/// over an ensemble that perturbs μ, rather than from one nominal value.
public enum FrictionDatabase {

    /// The measured/compiled anchors. Everything not listed here is derived by
    /// `coefficient(footing:on:)` from the closest documented pair.
    private static let table: [Footing: [FloorSurface: FrictionPair]] = [
        .wood: [
            .hardwood: FrictionPair(0.35, 0.30),      // wood on wood, dry & clean
            .laminate: FrictionPair(0.33, 0.29),
            .tile: FrictionPair(0.35, 0.30),
            .carpet: FrictionPair(0.70, 0.62),        // pile interlock
            .rug: FrictionPair(0.65, 0.57),
            .concrete: FrictionPair(0.42, 0.36),
            .woodShelf: FrictionPair(0.35, 0.30),
            .glassShelf: FrictionPair(0.28, 0.24),
            .stoneCounter: FrictionPair(0.38, 0.33),
        ],
        .rubber: [
            .hardwood: FrictionPair(0.85, 0.75),
            .laminate: FrictionPair(0.75, 0.66),
            .tile: FrictionPair(0.75, 0.66),
            .carpet: FrictionPair(0.90, 0.80),
            .rug: FrictionPair(0.85, 0.75),
            .concrete: FrictionPair(0.75, 0.66),
            .woodShelf: FrictionPair(0.85, 0.75),
            .glassShelf: FrictionPair(0.65, 0.57),
            .stoneCounter: FrictionPair(0.70, 0.62),
        ],
        .felt: [
            // Felt pads exist to let furniture slide. They are an
            // anti-mitigation and the app should say so.
            .hardwood: FrictionPair(0.22, 0.19),
            .laminate: FrictionPair(0.20, 0.17),
            .tile: FrictionPair(0.24, 0.20),
            .carpet: FrictionPair(0.55, 0.48),
            .rug: FrictionPair(0.50, 0.44),
            .concrete: FrictionPair(0.28, 0.24),
            .woodShelf: FrictionPair(0.22, 0.19),
            .glassShelf: FrictionPair(0.18, 0.15),
            .stoneCounter: FrictionPair(0.22, 0.19),
        ],
        .plasticGlide: [
            .hardwood: FrictionPair(0.30, 0.26),
            .laminate: FrictionPair(0.28, 0.24),
            .tile: FrictionPair(0.30, 0.26),
            .carpet: FrictionPair(0.65, 0.57),
            .rug: FrictionPair(0.60, 0.53),
            .concrete: FrictionPair(0.35, 0.30),
            .woodShelf: FrictionPair(0.28, 0.24),
            .glassShelf: FrictionPair(0.22, 0.19),
            .stoneCounter: FrictionPair(0.30, 0.26),
        ],
        .ptfeGlide: [
            .hardwood: FrictionPair(0.15, 0.13),
            .laminate: FrictionPair(0.14, 0.12),
            .tile: FrictionPair(0.16, 0.14),
            .carpet: FrictionPair(0.45, 0.39),
            .rug: FrictionPair(0.40, 0.35),
            .concrete: FrictionPair(0.20, 0.17),
            .woodShelf: FrictionPair(0.14, 0.12),
            .glassShelf: FrictionPair(0.12, 0.10),
            .stoneCounter: FrictionPair(0.15, 0.13),
        ],
        .metal: [
            .hardwood: FrictionPair(0.30, 0.26),
            .laminate: FrictionPair(0.35, 0.30),
            .tile: FrictionPair(0.40, 0.34),
            .carpet: FrictionPair(0.60, 0.53),
            .rug: FrictionPair(0.55, 0.48),
            .concrete: FrictionPair(0.45, 0.39),
            .woodShelf: FrictionPair(0.30, 0.26),
            .glassShelf: FrictionPair(0.25, 0.21),
            .stoneCounter: FrictionPair(0.40, 0.34),
        ],
        .ceramic: [
            .hardwood: FrictionPair(0.38, 0.33),
            .laminate: FrictionPair(0.35, 0.30),
            .tile: FrictionPair(0.42, 0.36),
            .carpet: FrictionPair(0.70, 0.62),
            .rug: FrictionPair(0.65, 0.57),
            .concrete: FrictionPair(0.45, 0.39),
            .woodShelf: FrictionPair(0.38, 0.33),
            .glassShelf: FrictionPair(0.38, 0.33),
            .stoneCounter: FrictionPair(0.45, 0.39),
        ],
        .glass: [
            .hardwood: FrictionPair(0.28, 0.24),
            .laminate: FrictionPair(0.26, 0.22),
            .tile: FrictionPair(0.38, 0.32),
            .carpet: FrictionPair(0.60, 0.53),
            .rug: FrictionPair(0.55, 0.48),
            .concrete: FrictionPair(0.40, 0.34),
            .woodShelf: FrictionPair(0.28, 0.24),
            .glassShelf: FrictionPair(0.90, 0.40),   // glass on glass: high static, low kinetic
            .stoneCounter: FrictionPair(0.38, 0.32),
        ],
        .plasticBody: [
            .hardwood: FrictionPair(0.30, 0.26),
            .laminate: FrictionPair(0.28, 0.24),
            .tile: FrictionPair(0.32, 0.27),
            .carpet: FrictionPair(0.65, 0.57),
            .rug: FrictionPair(0.60, 0.53),
            .concrete: FrictionPair(0.38, 0.33),
            .woodShelf: FrictionPair(0.28, 0.24),
            .glassShelf: FrictionPair(0.24, 0.20),
            .stoneCounter: FrictionPair(0.30, 0.26),
        ],
        .paper: [
            .hardwood: FrictionPair(0.38, 0.33),
            .laminate: FrictionPair(0.35, 0.30),
            .tile: FrictionPair(0.38, 0.33),
            .carpet: FrictionPair(0.70, 0.62),
            .rug: FrictionPair(0.65, 0.57),
            .concrete: FrictionPair(0.45, 0.39),
            .woodShelf: FrictionPair(0.38, 0.33),
            .glassShelf: FrictionPair(0.30, 0.26),
            .stoneCounter: FrictionPair(0.38, 0.33),
        ],
        .castor: [
            // Unlocked castors roll. Rolling resistance is one to two orders of
            // magnitude below sliding friction, so a castored object starts
            // moving at almost any perceptible shaking. Locked castors are
            // modelled as rubber, not as this.
            .hardwood: FrictionPair(0.02, 0.02),
            .laminate: FrictionPair(0.02, 0.02),
            .tile: FrictionPair(0.02, 0.02),
            .carpet: FrictionPair(0.10, 0.09),
            .rug: FrictionPair(0.08, 0.07),
            .concrete: FrictionPair(0.03, 0.03),
            .woodShelf: FrictionPair(0.02, 0.02),
            .glassShelf: FrictionPair(0.02, 0.02),
            .stoneCounter: FrictionPair(0.02, 0.02),
        ],
        .antiSlipMat: [
            .hardwood: FrictionPair(1.10, 0.95),
            .laminate: FrictionPair(1.10, 0.95),
            .tile: FrictionPair(1.05, 0.90),
            .carpet: FrictionPair(1.00, 0.87),
            .rug: FrictionPair(1.00, 0.87),
            .concrete: FrictionPair(1.05, 0.90),
            .woodShelf: FrictionPair(1.10, 0.95),
            .glassShelf: FrictionPair(1.00, 0.87),
            .stoneCounter: FrictionPair(1.05, 0.90),
        ],
        .museumPutty: [
            // Museum putty and wax bond rather than rub. Manufacturer test data
            // and FEMA E-74 §6.4.7 put the effective hold at 2–5 g for objects
            // under about 5 kg. Modelled as an effective μ of 3.0, which the
            // block solver treats as "will not slide at any realistic shaking".
            .hardwood: FrictionPair(3.0, 3.0),
            .laminate: FrictionPair(3.0, 3.0),
            .tile: FrictionPair(3.0, 3.0),
            .carpet: FrictionPair(1.0, 0.9),      // putty cannot bond to pile
            .rug: FrictionPair(1.0, 0.9),
            .concrete: FrictionPair(3.0, 3.0),
            .woodShelf: FrictionPair(3.0, 3.0),
            .glassShelf: FrictionPair(3.0, 3.0),
            .stoneCounter: FrictionPair(3.0, 3.0),
        ],
    ]

    /// The design friction pair for a contact.
    public static func coefficient(footing: Footing, on surface: FloorSurface) -> FrictionPair {
        table[footing]?[surface] ?? FrictionPair(0.35, 0.30)
    }

    /// A friction pair perturbed for one realisation of the risk ensemble.
    ///
    /// Friction in the field varies by roughly ±25% around the handbook value
    /// (dust, wax, wear, humidity, contact area). Because the slide-or-rock
    /// branch is a hard switch on μ, running a single nominal value produces a
    /// confident answer that is sometimes simply the wrong branch. The ensemble
    /// samples a lognormal so the reported likelihood reflects that.
    ///
    /// - Parameter variability: coefficient of variation. 0.25 is the
    ///   recommended value; pass 0 for a deterministic nominal run.
    public static func sample(
        footing: Footing,
        on surface: FloorSurface,
        variability: Double = 0.25,
        using rng: inout SeededGenerator
    ) -> FrictionPair {
        let nominal = coefficient(footing: footing, on: surface)
        guard variability > 0 else { return nominal }
        // Lognormal with median = nominal, so friction can never go negative.
        let sigma = (Foundation.log(1.0 + variability * variability)).squareRoot()
        let factor = exp(rng.nextGaussian() * sigma)
        // Clamp to a plausible physical envelope: no household contact is
        // frictionless, and none exceeds a bonded adhesive.
        let s = min(max(nominal.staticCoefficient * factor, 0.01), 3.0)
        let k = min(max(nominal.kineticCoefficient * factor, 0.01), s)
        return FrictionPair(s, k)
    }
}
