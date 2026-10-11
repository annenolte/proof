import Foundation
import simd

/// Bounded corrective control that keeps the 3D stage from contradicting the
/// analytic verdict (SPEC §4.7.4).
///
/// The engine is known to over-damp rocking and therefore under-predict
/// overturning. Rather than tune it — which would silently change what the user
/// is told — we let it run and apply a **saturating proportional correction**
/// towards the trajectory Track A demands. The correction is hard-capped at
/// `DisplayContract.maxAllowedAssistFraction` (0.35) of the body's own
/// overturning moment m·g·b, and at the same fraction of its own friction
/// capacity μ_s·m·g for the sliding channel.
///
/// That cap is the whole argument for legitimacy: 0.35·m·g·b cannot rotate a
/// stable block past α on its own, and it cannot hold up a block whose weight
/// has already passed its pivot. It can only *time-align* and *complete* a
/// motion the correct physics says happens.
public struct OutcomeReconciler: Sendable {

    /// Controller gains. SPEC §4.7.4: tuned so a correction settles in ~0.3 s
    /// without visible snapping.
    public struct Gains: Sendable, Equatable {
        /// Rotational gain, s⁻².
        public var kTheta: Double
        /// Translational gain, s⁻².
        public var kD: Double
        /// Scales `kTheta` by how much more the analytic model rocks than the
        /// engine does. 1.0 until `StageCalibration` measures otherwise.
        public var rockingGain: Double

        public init(kTheta: Double = 12.0, kD: Double = 20.0, rockingGain: Double = 1.0) {
            self.kTheta = kTheta
            self.kD = kD
            self.rockingGain = max(rockingGain, 0)
        }

        public static let `default` = Gains()
    }

    /// What the engine currently reports for one body.
    public struct Observation: Sendable, Equatable {
        /// Tilt of the body's own up axis away from world up, radians.
        public var tiltRadians: Double
        /// Net horizontal displacement from its starting position, metres.
        public var displacementM: Double
        /// Unit horizontal direction the body has moved in. Zero if it has not
        /// moved yet, in which case the excitation direction is used.
        public var slideDirection: SIMD3<Float>
        /// Unit horizontal direction the body is tipping towards.
        public var tipDirection: SIMD3<Float>

        public init(
            tiltRadians: Double,
            displacementM: Double,
            slideDirection: SIMD3<Float>,
            tipDirection: SIMD3<Float>
        ) {
            self.tiltRadians = tiltRadians
            self.displacementM = displacementM
            self.slideDirection = slideDirection
            self.tipDirection = tipDirection
        }
    }

    /// The capped effort for one physics step.
    public struct Correction: Sendable, Equatable {
        public var torque: SIMD3<Float>
        public var force: SIMD3<Float>
        /// True when either channel hit its cap. Logged, per SPEC §4.7.6(4).
        public var didSaturate: Bool

        public static let none = Correction(torque: .zero, force: .zero, didSaturate: false)
    }

    public var gains: Gains
    public var isEnabled: Bool

    public init(gains: Gains = .default, isEnabled: Bool = true) {
        self.gains = gains
        self.isEnabled = isEnabled
    }

    // MARK: - Caps

    /// The maximum corrective torque for a body, N·m. `fraction · m · g · b`.
    public static func torqueCap(body: BodySpec, contract: DisplayContract) -> Double {
        contract.maxAssistFraction * body.overturningMomentNm
    }

    /// The maximum corrective force for a body, N. `fraction · μ_s · m · g`.
    public static func forceCap(body: BodySpec, contract: DisplayContract) -> Double {
        contract.maxAssistFraction * body.staticFriction * body.massKg * Physics.g
    }

    // MARK: - The controller

    /// One step of correction. Pure: it reads an observation and returns capped
    /// effort, so it is fully unit-testable without a physics engine.
    public func correction(
        body: BodySpec,
        contract: DisplayContract,
        trajectory: DisplayTrajectory,
        observation: Observation,
        time: Double
    ) -> Correction {
        guard isEnabled else { return .none }

        var torque = SIMD3<Float>.zero
        var force = SIMD3<Float>.zero
        var saturated = false

        // ---- Rotation ----------------------------------------------------
        let targetTilt = trajectory.tilt(at: time)
        let tiltError = targetTilt - observation.tiltRadians
        // Only ever *help* the rotation Track A demands. We never apply a
        // righting torque: preventing a fall is a verdict, and verdicts are
        // Track A's alone.
        if tiltError > 1e-4, contract.ending != .stays {
            let cap = Self.torqueCap(body: body, contract: contract)
            let desired = gains.kTheta * gains.rockingGain * tiltError * body.pivotInertiaKgM2
            let magnitude = min(desired, cap)
            if desired > cap { saturated = true }
            // Rotating about `up × d` by a positive angle carries the body's up
            // axis towards `d` — i.e. tips it in the direction it is falling.
            let axis = simd_cross(SIMD3<Float>(0, 1, 0), normalisedHorizontal(observation.tipDirection))
            if simd_length(axis) > 1e-5 {
                torque = simd_normalize(axis) * Float(magnitude)
            }
        }

        // ---- Translation --------------------------------------------------
        let targetSlide = trajectory.slide(at: time)
        let slideError = targetSlide - observation.displacementM
        if abs(slideError) > 1e-4, contract.ending != .stays {
            let cap = Self.forceCap(body: body, contract: contract)
            let desired = gains.kD * slideError * body.massKg
            let magnitude = min(abs(desired), cap)
            if abs(desired) > cap { saturated = true }
            let direction = normalisedHorizontal(observation.slideDirection)
            if simd_length(direction) > 1e-5 {
                force = direction * Float(magnitude) * (slideError >= 0 ? 1 : -1)
            }
        }

        return Correction(torque: torque, force: force, didSaturate: saturated)
    }

    private func normalisedHorizontal(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let flat = SIMD3<Float>(v.x, 0, v.z)
        let length = simd_length(flat)
        return length > 1e-5 ? flat / length : .zero
    }
}
