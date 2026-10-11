import Foundation

/// Modified Mercalli Intensity — what shaking *feels* like and does, as opposed
/// to magnitude, which describes the earthquake at its source. MMI is the right
/// primary control for this app: it is local, it maps directly onto observed
/// damage to household contents, and it is what USGS ShakeMap publishes, so the
/// numbers the app shows are numbers a user can look up after a real quake.
public enum MercalliIntensity: Int, Codable, CaseIterable, Sendable, Comparable, Identifiable {
    case iii = 3, iv = 4, v = 5, vi = 6, vii = 7, viii = 8, ix = 9, x = 10

    public var id: Int { rawValue }

    public static func < (a: MercalliIntensity, b: MercalliIntensity) -> Bool {
        a.rawValue < b.rawValue
    }

    /// Roman numeral, as the scale is conventionally written.
    public var roman: String {
        ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"][rawValue]
    }

    /// USGS ShakeMap "perceived shaking" label.
    public var shakingLabel: String {
        switch self {
        case .iii: return "Weak"
        case .iv: return "Light"
        case .v: return "Moderate"
        case .vi: return "Strong"
        case .vii: return "Very strong"
        case .viii: return "Severe"
        case .ix: return "Violent"
        case .x: return "Extreme"
        }
    }

    /// USGS ShakeMap "potential damage" label.
    public var damageLabel: String {
        switch self {
        case .iii, .iv: return "None"
        case .v: return "Very light"
        case .vi: return "Light"
        case .vii: return "Moderate"
        case .viii: return "Moderate to heavy"
        case .ix: return "Heavy"
        case .x: return "Very heavy"
        }
    }

    /// Plain-English description of what happens to a room's contents, narrowed
    /// from the USGS intensity descriptions to the nonstructural effects this
    /// app is about.
    public var contentsDescription: String {
        switch self {
        case .iii:
            return "Hanging lamps sway. Most people indoors notice it. Nothing moves."
        case .iv:
            return "Dishes and windows rattle. Objects vibrate in place but stay put."
        case .v:
            return "Small unstable objects tip over. Liquids spill, pictures swing, doors swing open."
        case .vi:
            return "Books come off shelves. Pictures fall off walls. Furniture slides. Some heavy pieces topple."
        case .vii:
            return "Most tall unsecured furniture overturns. Contents are thrown off shelves. Water heaters topple."
        case .viii:
            return "Heavy furniture is overturned and moved metres. Appliances walk across the floor."
        case .ix:
            return "Almost everything unanchored is displaced or thrown. Objects leave the ground."
        case .x:
            return "Objects are launched through the air. Vertical shaking exceeds 1 g."
        }
    }

    /// A reference event most people will recognise.
    public var reference: String {
        switch self {
        case .iii: return "A distant quake, barely noticed"
        case .iv: return "Like a heavy truck passing"
        case .v: return "Strong enough to wake you up"
        case .vi: return "The strongest most people ever feel"
        case .vii: return "Northridge 1994, outer suburbs"
        case .viii: return "Loma Prieta 1989, San Francisco"
        case .ix: return "Northridge 1994, at the epicentre"
        case .x: return "Kobe 1995, worst-hit districts"
        }
    }

    /// The PGA bin edges USGS prints on every ShakeMap, in %g:
    /// 0.17 / 1.4 / 3.9 / 9.2 / 18 / 34 / 65 / 124. Using these verbatim means
    /// the numbers in the app match the ones a user sees on a real ShakeMap.
    public var pgaRangeInG: ClosedRange<Double> {
        switch self {
        case .iii: return 0.0017...0.014
        case .iv:  return 0.014...0.039
        case .v:   return 0.039...0.092
        case .vi:  return 0.092...0.18
        case .vii: return 0.18...0.34
        case .viii: return 0.34...0.65
        case .ix:  return 0.65...1.24
        case .x:   return 1.24...2.00
        }
    }

    /// The representative PGA for the bin, in g — the value the simulation
    /// actually runs at. Geometric midpoint of the ShakeMap bin, because the
    /// scale is logarithmic; the arithmetic mean would bias every level high.
    public var representativePGAInG: Double {
        let r = pgaRangeInG
        return (r.lowerBound * r.upperBound).squareRoot()
    }

    /// Representative peak ground velocity, cm/s, from the ShakeMap table.
    public var representativePGVInCmPerS: Double {
        switch self {
        case .iii: return 0.5
        case .iv:  return 2.2
        case .v:   return 5.5
        case .vi:  return 11.5
        case .vii: return 22.0
        case .viii: return 43.0
        case .ix:  return 83.0
        case .x:   return 140.0
        }
    }
}

/// Conversions between intensity, ground-motion amplitude, and source
/// magnitude. Every relation here is a published regression, cited inline, and
/// each has a unit test pinning it to the published sanity values.
public enum IntensityScale {

    // MARK: - Worden et al. (2012) GMICE
    //
    // Worden, Gerstenberger, Rhoades & Wald (2012), "Probabilistic
    // Relationships between Ground-Motion Parameters and Modified Mercalli
    // Intensity in California", BSSA 102(1), 204–221. This is the ground-motion
    // to intensity conversion USGS ShakeMap itself uses (`wgrw12`), and it
    // supersedes the older Wald et al. (1999) relations.
    //
    // Piecewise-linear in log10(amplitude), amplitude in cm/s² (PGA) or cm/s (PGV).

    private struct GMICE {
        let c1, c2, c3, c4: Double      // mid and high segments
        let c1p, c2p: Double            // low-amplitude segment
        let t1: Double                  // log10(amplitude) hinge, mid → high
        let t1p: Double                 // log10(amplitude) hinge, low → mid
        let t2: Double                  // MMI hinge, mid → high
        let t2p: Double                 // MMI hinge, low → mid
    }

    private static let pgaGMICE = GMICE(
        c1: 1.78, c2: 1.55, c3: -1.60, c4: 3.70,
        c1p: 1.71, c2p: 2.08, t1: 1.57, t1p: 0.14, t2: 4.22, t2p: 2.0
    )

    private static let pgvGMICE = GMICE(
        c1: 3.78, c2: 1.47, c3: 2.89, c4: 3.16,
        c1p: 4.62, c2p: 2.17, t1: 0.53, t1p: -1.21, t2: 4.56, t2p: 2.0
    )

    private static func mmi(fromLogAmplitude l: Double, using g: GMICE) -> Double {
        let m: Double
        if l <= g.t1p {
            m = g.c1p + g.c2p * l
        } else if l <= g.t1 {
            m = g.c1 + g.c2 * l
        } else {
            m = g.c3 + g.c4 * l
        }
        return min(max(m, 1.0), 10.0)
    }

    private static func logAmplitude(fromMMI m: Double, using g: GMICE) -> Double {
        if m <= g.t2p { return (m - g.c1p) / g.c2p }
        if m <= g.t2 { return (m - g.c1) / g.c2 }
        return (m - g.c3) / g.c4
    }

    /// MMI from peak ground acceleration in m/s².
    public static func mmi(fromPGA pga: Double) -> Double {
        mmi(fromLogAmplitude: log10(max(pga * 100.0, 1e-4)), using: pgaGMICE)
    }

    /// MMI from peak ground velocity in m/s.
    public static func mmi(fromPGV pgv: Double) -> Double {
        mmi(fromLogAmplitude: log10(max(pgv * 100.0, 1e-4)), using: pgvGMICE)
    }

    /// Peak ground acceleration in g for a (possibly fractional) MMI.
    public static func pgaInG(forMMI m: Double) -> Double {
        pow(10.0, logAmplitude(fromMMI: m, using: pgaGMICE)) / 100.0 / Physics.g
    }

    /// Peak ground velocity in m/s for a (possibly fractional) MMI.
    public static func pgvInMetresPerSecond(forMMI m: Double) -> Double {
        pow(10.0, logAmplitude(fromMMI: m, using: pgvGMICE)) / 100.0
    }

    /// The intensity bin a ground motion falls in. ShakeMap blends the PGA and
    /// PGV estimators, leaning on PGV at high intensity because acceleration
    /// saturates while velocity keeps tracking damage; this reproduces that.
    public static func intensity(for motion: GroundMotion) -> MercalliIntensity {
        let fromA = mmi(fromPGA: motion.pga)
        let fromV = mmi(fromPGV: motion.pgv)
        let blended = fromA > 7.0 ? (0.35 * fromA + 0.65 * fromV) : (0.65 * fromA + 0.35 * fromV)
        return bin(forMMI: blended)
    }

    /// The nearest whole intensity level the app can present, clamped to the
    /// range the simulation supports.
    public static func bin(forMMI m: Double) -> MercalliIntensity {
        MercalliIntensity(rawValue: min(max(Int(m.rounded()), 3), 10)) ?? .v
    }

    /// The intensity bin containing a given PGA in g, using the ShakeMap bin
    /// edges rather than the regression, so it agrees exactly with the ranges
    /// the UI displays.
    public static func bin(forPGAInG pga: Double) -> MercalliIntensity {
        for level in MercalliIntensity.allCases where pga < level.pgaRangeInG.upperBound {
            return level
        }
        return .x
    }

    // MARK: - Magnitude + distance → PGA
    //
    // Joyner & Boore (1981) / Boore, Joyner & Fumal (1997), random horizontal
    // component, PGA coefficients, all-mechanism set:
    //
    //   ln Y = b1 + b2(M−6) + b3(M−6)² + b5·ln r + bV·ln(Vs30/VA),  r = √(r_jb² + h²)

    private static let bjf = (b1: -0.242, b2: 0.527, b3: 0.0,
                              b5: -0.778, bV: -0.371, vA: 1396.0, h: 5.57)

    /// Shear-wave velocity in the top 30 m, m/s — the site term of the GMPE,
    /// with values at the centre of the matching NEHRP site class.
    public static func vs30(for soil: SoilClass) -> Double {
        switch soil {
        case .rock: return 900     // NEHRP B
        case .firm: return 500     // NEHRP C
        case .medium: return 300   // NEHRP D
        case .soft: return 180     // NEHRP E
        }
    }

    /// Estimated peak ground acceleration in g for a moment magnitude, a
    /// Joyner–Boore distance in km, and a site class.
    public static func pgaInG(magnitude: Double, distanceKm: Double, soil: SoilClass) -> Double {
        let m = magnitude - 6.0
        let r = (distanceKm * distanceKm + bjf.h * bjf.h).squareRoot()
        let magnitudeTerm: Double = bjf.b1 + bjf.b2 * m + bjf.b3 * m * m
        let pathTerm: Double = bjf.b5 * Foundation.log(r)
        let siteTerm: Double = bjf.bV * Foundation.log(vs30(for: soil) / bjf.vA)
        // The regression is unbounded at very short distance; cap at 2.0 g,
        // above the largest free-field PGA ever recorded.
        return min(exp(magnitudeTerm + pathTerm + siteTerm), 2.0)
    }

    /// Median significant duration D_5-95 in seconds. Source duration scales
    /// with the inverse corner frequency (∝ 10^(0.5M) at constant stress drop);
    /// the path term adds scattering-induced lengthening with distance.
    public static func significantDuration(magnitude: Double, distanceKm: Double) -> Double {
        let source = pow(10.0, 0.5 * magnitude - 2.9)
        return min(max(source + 0.07 * distanceKm, 3.0), 60.0)
    }

    // MARK: - Floor amplification
    //
    // The ground shakes; the building filters it; the furniture feels the
    // filtered version. Getting this factor wrong scales every verdict in the
    // app, so it uses the current code form rather than the legacy one.
    //
    // **ASCE 7-22 §13.3.1** replaced the old linear height factor with a
    // mode-shape-aware one:
    //
    //     H_f = 1 + a₁·(z/h) + a₂·(z/h)¹⁰
    //     a₁  = min(1/T_a, 2.5)
    //     a₂  = max(1 − (0.4/T_a)², 0)
    //
    // This captures something the linear form gets backwards: a stiff low-rise
    // house whips *harder* at its roof (H_f ≈ 3.5) than a tall flexible tower
    // does (H_f ≈ 2.6), because the short building's fundamental period is far
    // from the ground motion's. Most people live in low-rise buildings, so this
    // is not an academic distinction — the legacy formula understates the
    // hazard for the majority of this app's users.
    //
    // The component ductility reduction R_μ and the strength factor R_po are
    // deliberately NOT applied. Those exist to size anchorage hardware against a
    // yielding load path. We are simulating the acceleration an unanchored
    // object actually experiences, and dividing it down would understate what
    // the user watches happen.

    /// Amplification from ground acceleration to the acceleration felt at the
    /// occupant's floor, per ASCE 7-22 §13.3.1.
    ///
    /// - Parameters:
    ///   - floor: the storey the room is on, 0 for ground.
    ///   - totalStoreys: the number of storeys in the building.
    ///   - storeyHeightMetres: floor-to-floor height, for the period estimate.
    public static func floorAmplification(
        floor: Int, totalStoreys: Int, storeyHeightMetres: Double = 3.0
    ) -> Double {
        guard totalStoreys > 0, floor > 0 else { return 1.0 }
        return floorAmplification(
            heightRatio: Double(min(floor, totalStoreys)) / Double(totalStoreys),
            fundamentalPeriod: fundamentalPeriod(
                storeys: totalStoreys, storeyHeightMetres: storeyHeightMetres))
    }

    /// The bare ASCE 7-22 H_f factor, for a height ratio z/h and a known
    /// building period. Exposed separately because the period estimate and the
    /// amplification formula are independent choices, and only the formula is
    /// fixed by the code — the period depends on a structural system the app
    /// cannot see and must assume.
    public static func floorAmplification(
        heightRatio: Double, fundamentalPeriod period: Double
    ) -> Double {
        let ratio = min(max(heightRatio, 0), 1)
        let t = max(period, 0.01)
        let a1 = min(1.0 / t, 2.5)
        let a2 = max(1.0 - pow(0.4 / t, 2), 0.0)
        return 1.0 + a1 * ratio + a2 * pow(ratio, 10)
    }

    /// The legacy ASCE 7-16 linear form, kept so the app can show the user how
    /// the two compare and so the change is reviewable rather than silent.
    public static func floorAmplificationASCE716(floor: Int, totalStoreys: Int) -> Double {
        guard totalStoreys > 0, floor > 0 else { return 1.0 }
        return 1.0 + 2.0 * (Double(min(floor, totalStoreys)) / Double(totalStoreys))
    }

    /// Approximate fundamental period of the building, seconds.
    ///
    /// ASCE 7-16 Eq. 12.8-7: T = C_t·h^x. The app cannot know whether a user's
    /// building is a steel moment frame or a timber-framed house, so it uses the
    /// "all other structural systems" coefficients (C_t = 0.0488, x = 0.75 in
    /// SI). Those give the *shortest* period of the available sets, and a
    /// shorter period means a larger H_f — so the assumption errs towards
    /// reporting more shaking rather than less, which is the right direction for
    /// a safety tool to be wrong in.
    public static func fundamentalPeriod(storeys: Int, storeyHeightMetres: Double = 3.0) -> Double {
        let h = Double(max(storeys, 1)) * storeyHeightMetres
        return 0.0488 * pow(h, 0.75)
    }
}
