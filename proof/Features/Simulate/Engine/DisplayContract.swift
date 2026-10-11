import Foundation

/// What Track A requires the 3D stage to show for one object.
///
/// SPEC §4.7.3. The contract flows analytic → stage and never the other way.
/// The stage may time-align and complete a motion; it may never invent one or
/// prevent one, which is what `maxAssistFraction` exists to guarantee.
public struct DisplayContract: Codable, Sendable, Equatable {

    public enum Ending: String, Codable, Sendable, CaseIterable {
        /// Must not translate more than `toleranceM` or tilt more than 5°.
        case stays
        /// Must translate to within ±35 % of `targetSlideM`, and must not topple.
        case slides
        /// Must visibly tilt to at least 0.35·α at some point, without toppling.
        case rocks
        /// Must reach ≥ 80° of tilt inside [t*−0.5, t*+1.5] s.
        case topples
        /// Must leave its support and land.
        case fallsOff
        /// Wall-mounted: must separate from the wall and fall.
        case detaches

        /// True for the endings that put something on the floor.
        public var isFailure: Bool {
            switch self {
            case .stays, .slides, .rocks: return false
            case .topples, .fallsOff, .detaches: return true
            }
        }

        /// The verb the caption and the impact ticker use. Every verdict word
        /// the user reads originates here, i.e. in Track A.
        public var pastTense: String {
            switch self {
            case .stays: return "stayed put"
            case .slides: return "slid"
            case .rocks: return "rocked"
            case .topples: return "toppled"
            case .fallsOff: return "fell off its shelf"
            case .detaches: return "came off the wall"
            }
        }

        public var presentTense: String {
            switch self {
            case .stays: return "stays put"
            case .slides: return "slides"
            case .rocks: return "rocks"
            case .topples: return "topples"
            case .fallsOff: return "falls off"
            case .detaches: return "comes off the wall"
            }
        }
    }

    /// The hard ceiling on corrective effort, as a fraction of the body's own
    /// overturning moment m·g·b. Beyond this we would be animating rather than
    /// simulating. Nothing may raise it — `init` clamps.
    public static let maxAllowedAssistFraction: Double = 0.35

    public var ending: Ending
    /// Net sliding displacement Track A reported, metres.
    public var targetSlideM: Double
    /// Peak rotation as a fraction of α, from Track A.
    public var targetTipRatio: Double
    /// t* — when Track A says the object failed, seconds into the record.
    public var expectedFailureTimeS: Double?
    /// The first instant the record exceeds this object's movement threshold.
    /// Used to shape the corrective trajectory; also derived from Track A.
    public var onsetTimeS: Double
    /// Positional tolerance for `.stays`, metres.
    public var toleranceM: Double
    public var maxAssistFraction: Double

    public init(
        ending: Ending,
        targetSlideM: Double = 0,
        targetTipRatio: Double = 0,
        expectedFailureTimeS: Double? = nil,
        onsetTimeS: Double = 0,
        toleranceM: Double = 0.02,
        maxAssistFraction: Double = DisplayContract.maxAllowedAssistFraction
    ) {
        self.ending = ending
        self.targetSlideM = max(targetSlideM, 0)
        self.targetTipRatio = min(max(targetTipRatio, 0), 1)
        self.expectedFailureTimeS = expectedFailureTimeS
        self.onsetTimeS = max(onsetTimeS, 0)
        self.toleranceM = max(toleranceM, 0)
        // The cap is not negotiable, and it is enforced here rather than at the
        // call site so no future caller can widen it.
        self.maxAssistFraction = min(
            max(maxAssistFraction, 0), DisplayContract.maxAllowedAssistFraction)
    }

    // MARK: Derivation

    /// Builds the contract for one object.
    ///
    /// The **ending** comes from the ensemble (`ObjectRisk.dominantBehaviour`),
    /// which is what the report tells the user. The **timing** comes from the
    /// unperturbed realisation, which is the only run that has a `t*`. Where the
    /// ensemble says something fails but the unperturbed run survived, `t*`
    /// falls back to the record's own threshold-crossing time, which is still a
    /// Track A quantity.
    public static func derive(
        risk: ObjectRisk?,
        outcome: RigidBlockSolver.Result,
        body: BodySpec,
        onsetTime: Double,
        motionDuration: Double
    ) -> DisplayContract {

        let behaviour = risk?.dominantBehaviour ?? outcome.behaviour
        var ending: Ending

        if body.analyticBlock.isRestrained {
            ending = .stays
        } else if body.mounting == .wallMounted || body.mounting == .suspended {
            let fails = behaviour == .fellOffSupport
                || behaviour == .overturned
                || (risk?.likelihood ?? 0) > 0.5
            ending = fails ? .detaches : .stays
        } else {
            switch behaviour {
            case .restrained, .stable: ending = .stays
            case .slid: ending = .slides
            case .rocked: ending = .rocks
            case .overturned: ending = .topples
            case .fellOffSupport: ending = .fallsOff
            }
        }

        // An object on a shelf that the ensemble says topples has, in practice,
        // come off the shelf: it cannot rotate to horizontal in 30 cm of depth.
        if ending == .topples, body.supportHeightM > 0.05 {
            ending = .fallsOff
        }

        let slide = max(risk?.slidingDisplacement ?? 0, outcome.slidingDisplacement)
        let tipRatio: Double
        switch ending {
        case .topples: tipRatio = 1.0
        case .rocks: tipRatio = max(risk?.closenessToToppling ?? 0, outcome.rotationRatio, 0.35)
        default: tipRatio = min(risk?.closenessToToppling ?? outcome.rotationRatio, 1)
        }

        var failureTime: Double?
        if ending.isFailure {
            let fallback = min(onsetTime + 0.6, max(motionDuration - 0.5, 0))
            failureTime = outcome.timeOfFailure ?? fallback
        }

        return DisplayContract(
            ending: ending,
            targetSlideM: ending == .stays ? 0 : slide,
            targetTipRatio: tipRatio,
            expectedFailureTimeS: failureTime,
            onsetTimeS: onsetTime,
            toleranceM: 0.02
        )
    }

    // MARK: Verification

    /// Does an observed end state satisfy this contract? Used at the end of a
    /// run to flag divergence — which changes the playback caption and nothing
    /// in the report.
    public func isSatisfied(byTilt tilt: Double, displacement: Double, alpha: Double) -> Bool {
        switch ending {
        case .stays:
            return displacement <= max(toleranceM, 0.05) && tilt <= 5 * .pi / 180
        case .slides:
            guard tilt < 60 * .pi / 180 else { return false }
            guard targetSlideM > 0.005 else { return displacement < 0.35 }
            return abs(displacement - targetSlideM) <= 0.35 * targetSlideM + 0.05
        case .rocks:
            return tilt >= 0.35 * alpha && tilt < 80 * .pi / 180
        case .topples, .detaches:
            return tilt >= 80 * .pi / 180
        case .fallsOff:
            return displacement > 0.05 || tilt >= 45 * .pi / 180
        }
    }
}

// MARK: - Target trajectory

/// The reference trajectory the reconciler steers towards.
///
/// **Deviation from SPEC §4.7.4, stated plainly.** The spec assumes Track A
/// stores a 100 Hz per-body time history. `RigidBlockSolver.Result` does not
/// expose one and `Core/` is frozen, so the trajectory is *reconstructed* from
/// the contract's Track A summary values — `t*`, `targetSlideM`,
/// `targetTipRatio`, `onsetTimeS` — using the same shapes the analytic solution
/// produces (a quiet period, then a monotone rotation past α once the point of
/// no return is passed). Every number in it still originates in Track A; only
/// the interpolation between them is synthesised, and the 35 % assist cap means
/// an inaccurate interpolation can only mistime a motion, never create one.
public struct DisplayTrajectory: Sendable, Equatable {

    public let contract: DisplayContract
    /// Critical tilt angle of the body, radians.
    public let alpha: Double
    public let duration: Double

    /// How long the object takes to rotate from upright to the point of no
    /// return, and from there to flat. Both are shaped to the object's own
    /// rocking frequency parameter rather than being global constants.
    public let riseSeconds: Double
    public let falloverSeconds: Double

    public init(contract: DisplayContract, body: BodySpec, duration: Double) {
        self.contract = contract
        self.alpha = body.alphaRadians
        self.duration = max(duration, 0.001)
        // Housner's frequency parameter sets the natural timescale of the
        // rotation; a big wardrobe goes over visibly slower than a small vase.
        let p = max(body.analyticBlock.frequencyParameter, 0.2)
        self.riseSeconds = min(max(0.9 / p, 0.15), 1.2)
        self.falloverSeconds = min(max(2.2 / p, 0.35), 2.4)
    }

    /// Target tilt **magnitude** at a simulation time, radians.
    ///
    /// A magnitude rather than a signed angle on purpose: RealityKit picks the
    /// tipping direction from the contact and the excitation, and fighting it
    /// with a signed target would produce visible snapping. The reconciler only
    /// ever helps the rotation the engine already chose.
    public func tilt(at time: Double) -> Double {
        switch contract.ending {
        case .stays, .slides:
            return 0
        case .rocks:
            guard time >= contract.onsetTimeS else { return 0 }
            let ramp = smoothstep((time - contract.onsetTimeS) / max(riseSeconds, 1e-3))
            return contract.targetTipRatio * alpha * ramp
        case .topples, .detaches, .fallsOff:
            guard let star = contract.expectedFailureTimeS else { return 0 }
            if time < star - riseSeconds { return 0 }
            if time < star {
                return alpha * smoothstep((time - (star - riseSeconds)) / max(riseSeconds, 1e-3))
            }
            if contract.ending == .fallsOff { return alpha }
            let flat = Double.pi / 2
            let progress = min(max((time - star) / max(falloverSeconds, 1e-3), 0), 1)
            return alpha + (flat - alpha) * progress
        }
    }

    /// Target net displacement **magnitude** relative to the floor, metres.
    public func slide(at time: Double) -> Double {
        switch contract.ending {
        case .stays, .rocks, .detaches:
            return 0
        case .slides:
            guard contract.targetSlideM > 0 else { return 0 }
            let start = contract.onsetTimeS
            let end = max(start + 0.5, duration * 0.85)
            let progress = smoothstep((time - start) / (end - start))
            return contract.targetSlideM * progress
        case .topples:
            // Sliding stops once it is up on a corner.
            let star = contract.expectedFailureTimeS ?? duration
            let start = contract.onsetTimeS
            let end = max(start + 0.25, star)
            return contract.targetSlideM * smoothstep((time - start) / (end - start))
        case .fallsOff:
            guard let star = contract.expectedFailureTimeS else { return 0 }
            let start = contract.onsetTimeS
            let end = max(start + 0.25, star)
            return max(contract.targetSlideM, 0.02) * smoothstep((time - start) / (end - start))
        }
    }

    private func smoothstep(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
