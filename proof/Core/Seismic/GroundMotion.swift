import Foundation

/// Physical constants used across the seismic engine. SI units throughout:
/// metres, kilograms, seconds. Accelerations are in m/s² unless a symbol is
/// explicitly suffixed `G` (multiples of standard gravity).
public enum Physics {
    /// Standard gravity, m/s². CODATA / ISO 80000-3.
    public static let g: Double = 9.80665
}

// MARK: - Deterministic RNG

/// SplitMix64. Seeded, portable and reproducible across platforms and OS
/// releases — unlike `SystemRandomNumberGenerator`, which would make the
/// generated accelerograms (and therefore the whole risk verdict)
/// non-reproducible and untestable.
public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        // Avoid the degenerate all-zero state.
        self.state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Standard normal deviate via the Box–Muller transform.
    public mutating func nextGaussian() -> Double {
        // Draw u1 in (0, 1] so log() is finite.
        let u1 = Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
        let u2 = Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
        let a = max(u1, .leastNormalMagnitude)
        return (-2.0 * Foundation.log(a)).squareRoot() * Foundation.cos(2.0 * .pi * u2)
    }
}

// MARK: - Soil / site conditions

/// Site soil class, which controls the dominant frequency and damping of the
/// Kanai–Tajimi filter that shapes the synthetic ground motion. Parameter
/// values follow the classical Kanai–Tajimi / Clough–Penzien literature
/// (Kanai 1957; Tajimi 1960; Clough & Penzien, *Dynamics of Structures*).
public enum SoilClass: String, Codable, CaseIterable, Sendable {
    /// Rock / very dense soil. High dominant frequency, low damping.
    case rock
    /// Firm / stiff soil — the default assumption for a typical residence.
    case firm
    /// Medium / deep cohesionless soil.
    case medium
    /// Soft clay. Low dominant frequency, heavy damping, long-period energy.
    case soft

    /// Dominant circular frequency ω_g of the ground filter, rad/s.
    public var omegaG: Double {
        switch self {
        case .rock: return 8.0 * .pi      //  4.0 Hz
        case .firm: return 5.0 * .pi      //  2.5 Hz
        case .medium: return 3.0 * .pi    //  1.5 Hz
        case .soft: return 1.6 * .pi      //  0.8 Hz
        }
    }

    /// Damping ratio ζ_g of the ground filter.
    public var zetaG: Double {
        switch self {
        case .rock: return 0.65
        case .firm: return 0.60
        case .medium: return 0.55
        case .soft: return 0.45
        }
    }

    /// Clough–Penzien second-filter corner frequency, rad/s. This high-pass
    /// stage removes the unphysical low-frequency (near-DC) energy that the
    /// bare Kanai–Tajimi spectrum contains, which would otherwise integrate
    /// into an unbounded ground displacement drift.
    public var omegaF: Double { omegaG * 0.1 }

    /// Clough–Penzien second-filter damping ratio.
    public var zetaF: Double { zetaG }

    public var displayName: String {
        switch self {
        case .rock: return "Rock"
        case .firm: return "Firm soil"
        case .medium: return "Medium soil"
        case .soft: return "Soft soil"
        }
    }

    public var detail: String {
        switch self {
        case .rock: return "Bedrock or very dense soil. Sharp, high-frequency shaking."
        case .firm: return "Stiff soil. The typical case for most homes."
        case .medium: return "Deeper sandy or gravelly soil. Shaking lasts longer."
        case .soft: return "Soft clay or landfill. Slow, rolling motion that amplifies."
        }
    }
}

// MARK: - Ground motion record

/// A uniformly sampled horizontal ground-acceleration time history.
///
/// The engine is planar-horizontal: `x` and `y` are the two orthogonal
/// horizontal components in the room's world frame. Vertical acceleration is
/// carried separately because it modulates the normal force (and therefore the
/// available friction) rather than driving horizontal response directly.
public struct GroundMotion: Sendable {
    /// Sample interval, seconds.
    public let dt: Double
    /// Horizontal component along world X, m/s².
    public let ax: [Double]
    /// Horizontal component along world Z, m/s².
    public let az: [Double]
    /// Vertical component along world Y, m/s². Positive is up.
    public let ay: [Double]
    /// Human-facing name of the underlying record or synthesis.
    public let name: String

    public init(dt: Double, ax: [Double], az: [Double], ay: [Double], name: String) {
        precondition(dt > 0, "sample interval must be positive")
        precondition(ax.count == az.count && ax.count == ay.count,
                     "ground motion components must be the same length")
        self.dt = dt
        self.ax = ax
        self.az = az
        self.ay = ay
        self.name = name
    }

    public var sampleCount: Int { ax.count }
    public var duration: Double { Double(ax.count) * dt }

    /// Peak ground acceleration: the largest horizontal resultant over the
    /// record, m/s². This is the quantity the intensity scales are keyed to.
    public var pga: Double {
        var peak = 0.0
        for i in 0..<ax.count {
            peak = max(peak, (ax[i] * ax[i] + az[i] * az[i]).squareRoot())
        }
        return peak
    }

    /// Peak ground acceleration expressed in multiples of g.
    public var pgaInG: Double { pga / Physics.g }

    /// Horizontal acceleration resultant at a sample index, m/s².
    public func horizontalMagnitude(at index: Int) -> Double {
        guard ax.indices.contains(index) else { return 0 }
        return (ax[index] * ax[index] + az[index] * az[index]).squareRoot()
    }

    /// Linearly interpolated acceleration at an arbitrary time, m/s².
    /// Samples outside the record read as zero (the ground is at rest).
    public func acceleration(at time: Double) -> SIMD3<Double> {
        guard time >= 0 else { return .zero }
        let s = time / dt
        let i = Int(s.rounded(.down))
        guard i >= 0, i + 1 < ax.count else {
            if i == ax.count - 1 { return SIMD3(ax[i], ay[i], az[i]) }
            return .zero
        }
        let f = s - Double(i)
        return SIMD3(
            ax[i] + (ax[i + 1] - ax[i]) * f,
            ay[i] + (ay[i + 1] - ay[i]) * f,
            az[i] + (az[i + 1] - az[i]) * f
        )
    }

    /// Peak ground velocity, m/s, by trapezoidal integration of the horizontal
    /// resultant components. PGV is the better predictor of damage to flexible
    /// and rocking objects, and feeds the intensity conversion.
    public var pgv: Double {
        var vx = 0.0, vz = 0.0, peak = 0.0
        for i in 1..<max(ax.count, 1) {
            vx += 0.5 * (ax[i] + ax[i - 1]) * dt
            vz += 0.5 * (az[i] + az[i - 1]) * dt
            peak = max(peak, (vx * vx + vz * vz).squareRoot())
        }
        return peak
    }

    /// Arias intensity, m/s — the energy content of the record.
    /// I_A = (π / 2g) ∫ a(t)² dt (Arias 1970).
    public var ariasIntensity: Double {
        var sum = 0.0
        for i in 0..<ax.count {
            sum += (ax[i] * ax[i] + az[i] * az[i]) * dt
        }
        return .pi * sum / (2.0 * Physics.g)
    }

    /// Significant duration D_5-95: the interval over which the Arias intensity
    /// builds from 5% to 95% of its total (Trifunac & Brady 1975).
    public var significantDuration: Double {
        guard ax.count > 1 else { return 0 }
        var cumulative = [Double](repeating: 0, count: ax.count)
        var sum = 0.0
        for i in 0..<ax.count {
            sum += (ax[i] * ax[i] + az[i] * az[i]) * dt
            cumulative[i] = sum
        }
        guard sum > 0 else { return 0 }
        let lo = 0.05 * sum, hi = 0.95 * sum
        var start = 0, end = ax.count - 1
        for i in 0..<ax.count where cumulative[i] >= lo { start = i; break }
        for i in 0..<ax.count where cumulative[i] >= hi { end = i; break }
        return Double(end - start) * dt
    }

    /// A record of all zeros — the "no shaking" baseline, useful as a control
    /// in tests and as the idle state of the simulator.
    public static func quiet(dt: Double = 0.005, duration: Double = 1.0) -> GroundMotion {
        let n = max(Int(duration / dt), 1)
        let zeros = [Double](repeating: 0, count: n)
        return GroundMotion(dt: dt, ax: zeros, az: zeros, ay: zeros, name: "At rest")
    }
}
