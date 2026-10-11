import Foundation

/// Generates realistic, reproducible earthquake ground-motion time histories.
///
/// The method is the standard engineering synthesis for nonstationary strong
/// motion:
///
/// 1. Gaussian white noise, from a seeded generator so a given room + intensity
///    always produces the *same* earthquake. Reproducibility matters here: the
///    user's risk verdict must not change when they re-run the simulation.
/// 2. Passed through a **Kanai–Tajimi** second-order filter, which imposes the
///    frequency content of the site's soil column (Kanai 1957, Tajimi 1960):
///
///        S(ω) = S₀ · [1 + 4ζ_g²(ω/ω_g)²] / { [1 − (ω/ω_g)²]² + 4ζ_g²(ω/ω_g)² }
///
/// 3. Passed through the **Clough–Penzien** high-pass correction, which removes
///    the spurious near-DC energy of the bare Kanai–Tajimi spectrum. Without
///    this the record integrates to an unbounded ground displacement, which
///    would visibly translate the whole room off-screen.
/// 4. Modulated by a **Jennings–Housner–Tsai** envelope: a quadratic build-up,
///    a strong-motion plateau, then exponential decay. Real earthquakes are
///    strongly nonstationary and a stationary record both looks and behaves
///    wrong — objects that would survive a real pulse train topple under
///    sustained sinusoidal shaking.
/// 5. Baseline-corrected and scaled so the peak horizontal resultant matches the
///    requested PGA exactly.
///
/// Two horizontal components are generated from independent noise streams (real
/// horizontal components are close to uncorrelated), plus a vertical component
/// at the customary 2/3 amplitude ratio with higher-frequency content.
public struct AccelerogramSynthesizer {

    public struct Parameters: Sendable, Equatable {
        /// Target peak ground acceleration, in multiples of g.
        public var targetPGAInG: Double
        /// Site soil class, which sets the filter's dominant frequency.
        public var soil: SoilClass
        /// Total record length in seconds.
        public var duration: Double
        /// Significant (5–95% Arias) duration in seconds — the length of the
        /// strong-motion plateau.
        public var strongMotionDuration: Double
        /// Sample interval. 200 Hz resolves everything up to the 25 Hz ceiling
        /// of engineering interest with a wide margin.
        public var dt: Double
        /// Seed for the noise streams.
        public var seed: UInt64

        public init(
            targetPGAInG: Double,
            soil: SoilClass = .firm,
            duration: Double = 30.0,
            strongMotionDuration: Double = 12.0,
            dt: Double = 0.005,
            seed: UInt64 = 0x5EED_C0DE
        ) {
            self.targetPGAInG = targetPGAInG
            self.soil = soil
            self.duration = duration
            self.strongMotionDuration = strongMotionDuration
            self.dt = dt
            self.seed = seed
        }
    }

    public init() {}

    public func generate(_ p: Parameters, name: String) -> GroundMotion {
        let n = max(Int((p.duration / p.dt).rounded()), 2)
        var rng = SeededGenerator(seed: p.seed)

        let envelope = jenningsEnvelope(count: n, dt: p.dt,
                                        strongMotion: p.strongMotionDuration,
                                        total: p.duration)

        // Two independent horizontal components, and a vertical component whose
        // soil filter is stiffened because vertical motion is P-wave dominated
        // and therefore richer in high frequency.
        var ax = filteredNoise(count: n, dt: p.dt, soil: p.soil, rng: &rng)
        var az = filteredNoise(count: n, dt: p.dt, soil: p.soil, rng: &rng)
        var ay = filteredNoise(count: n, dt: p.dt, soil: p.soil, verticalStiffening: 1.8, rng: &rng)

        for i in 0..<n {
            ax[i] *= envelope[i]
            az[i] *= envelope[i]
            ay[i] *= envelope[i]
        }

        baselineCorrect(&ax)
        baselineCorrect(&az)
        baselineCorrect(&ay)

        // Scale so the peak horizontal *resultant* is the requested PGA.
        let targetPGA = p.targetPGAInG * Physics.g
        var peak = 0.0
        for i in 0..<n { peak = max(peak, (ax[i] * ax[i] + az[i] * az[i]).squareRoot()) }
        let scale = peak > 1e-12 ? targetPGA / peak : 0

        for i in 0..<n {
            ax[i] *= scale
            az[i] *= scale
            // Vertical is conventionally taken as 2/3 of horizontal in codes
            // (ASCE 7 uses 0.2·S_DS vertical vs 0.4·S_DS horizontal in the
            // component force equations; 2/3 is the classic Newmark ratio).
            ay[i] *= scale * (2.0 / 3.0)
        }

        return GroundMotion(dt: p.dt, ax: ax, az: az, ay: ay, name: name)
    }

    /// Convenience: a record for a target Mercalli intensity.
    public func generate(
        intensity: MercalliIntensity,
        soil: SoilClass = .firm,
        seed: UInt64 = 0x5EED_C0DE
    ) -> GroundMotion {
        // Longer, more energetic shaking at higher intensity — the magnitude
        // needed to produce MMI IX shakes for far longer than one that produces
        // MMI IV, and duration matters as much as amplitude for toppling.
        let strong = min(4.0 + Double(intensity.rawValue - 3) * 2.2, 26.0)
        let params = Parameters(
            targetPGAInG: intensity.representativePGAInG,
            soil: soil,
            duration: strong + 12.0,
            strongMotionDuration: strong,
            dt: 0.005,
            seed: seed
        )
        return generate(params, name: "Intensity \(intensity.roman) · \(soil.displayName)")
    }

    // MARK: - Stages

    /// Jennings, Housner & Tsai (1968) intensity envelope: t² rise, flat
    /// plateau, exponential decay.
    private func jenningsEnvelope(count: Int, dt: Double, strongMotion: Double, total: Double) -> [Double] {
        // Rise occupies the first ~15% of the record but never more than 4 s.
        let t1 = min(max(total * 0.15, 1.0), 4.0)
        let t2 = min(t1 + strongMotion, total)
        // Decay constant chosen so the envelope has fallen to ~5% by the end.
        let tail = max(total - t2, 0.5)
        let c = -Foundation.log(0.05) / tail

        var e = [Double](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) * dt
            if t < t1 {
                let r = t / t1
                e[i] = r * r
            } else if t <= t2 {
                e[i] = 1.0
            } else {
                e[i] = exp(-c * (t - t2))
            }
        }
        return e
    }

    /// White noise driven through the Kanai–Tajimi soil filter and then the
    /// Clough–Penzien high-pass corrector, integrated with the semi-implicit
    /// Euler scheme (unconditionally stable for these damping ratios at 200 Hz).
    private func filteredNoise(
        count: Int,
        dt: Double,
        soil: SoilClass,
        verticalStiffening: Double = 1.0,
        rng: inout SeededGenerator
    ) -> [Double] {
        let wg = soil.omegaG * verticalStiffening
        let zg = soil.zetaG
        let wf = soil.omegaF * verticalStiffening
        let zf = soil.zetaF

        // Kanai–Tajimi state (ground filter).
        var xg = 0.0, vg = 0.0
        // Clough–Penzien state (high-pass corrector).
        var xf = 0.0, vf = 0.0

        var out = [Double](repeating: 0, count: count)
        // Scale the white-noise increment by 1/√dt so the resulting process is
        // independent of the sample rate.
        let noiseScale = 1.0 / dt.squareRoot()

        for i in 0..<count {
            let w = rng.nextGaussian() * noiseScale

            // ẍ_g + 2ζ_g ω_g ẋ_g + ω_g² x_g = −w
            let ag = -w - 2.0 * zg * wg * vg - wg * wg * xg
            vg += ag * dt
            xg += vg * dt

            // The Kanai–Tajimi output acceleration.
            let ktAccel = 2.0 * zg * wg * vg + wg * wg * xg

            // ẍ_f + 2ζ_f ω_f ẋ_f + ω_f² x_f = −(KT output)
            let af = -ktAccel - 2.0 * zf * wf * vf - wf * wf * xf
            vf += af * dt
            xf += vf * dt

            // Clough–Penzien total: the KT signal minus its low-frequency part.
            out[i] = ktAccel - (2.0 * zf * wf * vf + wf * wf * xf)
        }

        // Discard the filter start-up transient by zeroing the first 0.5 s;
        // the envelope is near zero there anyway.
        let warmup = min(Int(0.5 / dt), count)
        for i in 0..<warmup { out[i] *= Double(i) / Double(max(warmup, 1)) }
        return out
    }

    /// Removes any residual mean so the record integrates to a bounded velocity
    /// and the ground finishes where it started. Real accelerograms are always
    /// baseline-corrected before use, and skipping this makes a room drift.
    private func baselineCorrect(_ a: inout [Double]) {
        guard !a.isEmpty else { return }
        let mean = a.reduce(0, +) / Double(a.count)
        for i in a.indices { a[i] -= mean }

        // Remove any linear trend in the integrated velocity, so the final
        // ground velocity is zero (the ground must come to rest).
        var v = 0.0
        for i in a.indices { v += a[i] }
        let correction = v / Double(a.count)
        for i in a.indices { a[i] -= correction }
    }
}
