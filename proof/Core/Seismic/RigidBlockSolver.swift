import Foundation

/// The analytic ground-truth solver for a free-standing rigid body on a floor
/// subjected to horizontal base excitation.
///
/// This is deliberately **separate from the 3D physics engine**. RealityKit
/// produces the visual simulation, which has to look right at 60 fps with
/// dozens of bodies and therefore makes accuracy compromises (contact
/// softening, solver iteration limits, sleeping). The verdict the user acts on —
/// "this bookcase will fall on your bed" — is instead computed here, from the
/// classical equations, at a fine fixed timestep, with no such compromises. It
/// is fully deterministic and unit-testable against closed-form results.
///
/// ## The physics
///
/// A rectangular block of half-width `b`, half-height `h`, mass `m`, standing on
/// a floor with static friction `μs` and kinetic friction `μk`, subject to
/// horizontal ground acceleration `a(t)` and vertical `a_v(t)`.
///
/// **Slenderness** (Housner 1963):
///
///     α = atan(b / h)          critical tilt angle — beyond this it topples
///     R = √(b² + h²)           distance from a bottom corner to the centroid
///     p = √(3g / 4R)           the block's rocking frequency parameter
///
/// **Initiation.** With `a` the horizontal base acceleration and `n = 1 + a_v/g`
/// the normal-force modulation factor:
///
///     sliding starts when   |a| > μs · g · n
///     rocking starts when   |a| > g · n · tan α  =  g · n · b/h
///
/// Whichever threshold is lower is reached first, so a block with `μ < b/h`
/// slides before it rocks, and one with `μ > b/h` rocks before it slides. This
/// is Shenton's (1996) mode classification, and it is why a heavy dresser on
/// carpet walks across the floor while a tall thin bookcase on tile tips over.
///
/// **Rocking.** Once rocking, with rotation θ about the trailing bottom corner
/// (Housner's equation, exact, no small-angle assumption):
///
///     θ̈ = −p² [ sin(α·sgn θ − θ) + (a/g)·cos(α·sgn θ − θ) ]
///
/// **Impact.** When θ returns to zero the block slaps down and the rotation axis
/// jumps to the opposite corner. Angular momentum about the new corner is
/// conserved through the impact, giving the classical restitution coefficient
///
///     r = 1 − (3/2)·sin²α
///
/// so the post-impact angular velocity is `θ̇⁺ = r·θ̇⁻`. This energy loss is
/// what makes real objects usually *not* topple even when the static criterion
/// says they should.
///
/// **Overturning** occurs when `|θ| ≥ α`: the centre of mass has passed over the
/// pivoting corner and gravity finishes the job. Critically, this dynamic
/// criterion is far more forgiving than the naive static one (`a > g·b/h`),
/// because a brief acceleration spike does not have time to rotate the block
/// through α. Using the static criterion alone would make this app cry wolf on
/// nearly every object in the room.
public struct RigidBlockSolver {

    // MARK: - Input

    public struct Block: Sendable, Equatable {
        /// Half-width along the direction of shaking, m. The *smaller*
        /// horizontal half-dimension governs, since a block tips about its
        /// weakest axis.
        public var halfWidth: Double
        /// Height of the centre of mass above the floor, m. For a uniform body
        /// this is half the total height, but a loaded bookcase or a
        /// top-heavy cabinet sits higher, and that dominates the outcome.
        public var comHeight: Double
        /// Mass, kg. Does not affect rocking or sliding *initiation* (both
        /// thresholds are mass-independent), but sets the impact energy and so
        /// the consequence severity.
        public var mass: Double
        /// Static friction coefficient at the floor contact.
        public var staticFriction: Double
        /// Kinetic friction coefficient at the floor contact.
        public var kineticFriction: Double
        /// True if the object is fixed to a wall or floor (bolted, strapped,
        /// built in). A restrained object cannot slide or overturn.
        public var isRestrained: Bool
        /// Height of the supporting surface above the floor, m. Zero for
        /// floor-standing; the shelf height for an object on a shelf. Objects
        /// on elevated supports receive amplified motion and fall further.
        public var supportHeight: Double
        /// Distance from the object to the edge of its support, m. Used to
        /// decide whether a sliding object slides *off*.
        public var distanceToSupportEdge: Double

        public init(
            halfWidth: Double,
            comHeight: Double,
            mass: Double,
            staticFriction: Double,
            kineticFriction: Double,
            isRestrained: Bool = false,
            supportHeight: Double = 0,
            distanceToSupportEdge: Double = .greatestFiniteMagnitude
        ) {
            self.halfWidth = max(halfWidth, 1e-4)
            self.comHeight = max(comHeight, 1e-4)
            self.mass = max(mass, 1e-4)
            self.staticFriction = max(staticFriction, 0)
            self.kineticFriction = max(min(kineticFriction, staticFriction), 0)
            self.isRestrained = isRestrained
            self.supportHeight = max(supportHeight, 0)
            self.distanceToSupportEdge = max(distanceToSupportEdge, 0)
        }

        /// Slenderness angle α = atan(b/h). Small α means tall and thin, which
        /// means easy to topple.
        public var alpha: Double { atan(halfWidth / comHeight) }

        /// Aspect ratio b/h. Also the static rocking threshold in units of g.
        public var aspectRatio: Double { halfWidth / comHeight }

        /// Distance from the pivot corner to the centre of mass, m.
        public var pivotRadius: Double {
            (halfWidth * halfWidth + comHeight * comHeight).squareRoot()
        }

        /// Housner frequency parameter p = √(3g / 4R), rad/s.
        public var frequencyParameter: Double {
            (3.0 * Physics.g / (4.0 * pivotRadius)).squareRoot()
        }

        /// Coefficient of restitution at rocking impact, r = 1 − (3/2)sin²α.
        /// Clamped at zero: for α > ~54.7° (a very squat block) the formula
        /// goes negative, which physically means the block cannot sustain
        /// rocking at all.
        public var restitution: Double {
            max(1.0 - 1.5 * pow(sin(alpha), 2), 0.0)
        }

        /// Ground acceleration in g at which rocking begins, on a level floor.
        public var rockingThresholdInG: Double { aspectRatio }

        /// Ground acceleration in g at which sliding begins, on a level floor.
        public var slidingThresholdInG: Double { staticFriction }
    }

    // MARK: - Output

    /// The dominant behaviour the object exhibited during the record.
    public enum Behaviour: String, Codable, Sendable {
        /// Never moved.
        case stable
        /// Slid across its support without tipping.
        case slid
        /// Rocked back and forth but recovered.
        case rocked
        /// Rocked past the point of no return and fell.
        case overturned
        /// Slid entirely off its supporting surface and fell.
        case fellOffSupport
        /// Restrained — bolted, strapped or built in — and so did not move.
        case restrained
    }

    public struct Result: Sendable, Equatable {
        public var behaviour: Behaviour
        /// Total sliding displacement, m.
        public var slidingDisplacement: Double
        /// Largest rotation reached, radians.
        public var peakRotation: Double
        /// Peak rotation as a fraction of the toppling angle α. Values near 1
        /// mean the object came close to falling: the honest way to express
        /// "this nearly went over".
        public var rotationRatio: Double
        /// Time at which it overturned or fell off, seconds. Nil if it survived.
        public var timeOfFailure: Double?
        /// Kinetic energy at the moment of impact with the floor, joules.
        /// This is what determines whether being hit by it is survivable.
        public var impactEnergy: Double
        /// Speed of the centre of mass at impact, m/s.
        public var impactSpeed: Double
        /// How far the object's topmost point travels horizontally when it
        /// falls, m — its "strike zone" reach from its own footprint.
        public var falloverReach: Double

        public static let stable = Result(
            behaviour: .stable, slidingDisplacement: 0, peakRotation: 0,
            rotationRatio: 0, timeOfFailure: nil, impactEnergy: 0,
            impactSpeed: 0, falloverReach: 0
        )
    }

    public init() {}

    // MARK: - Solve

    /// Integrates the block's response to a ground-motion record.
    ///
    /// - Parameters:
    ///   - block: the object's geometry, mass and contact properties.
    ///   - motion: the ground acceleration history at the object's support.
    ///   - substeps: integration substeps per record sample. The rocking
    ///     equation is stiff near impact, so we integrate finer than the record
    ///     is sampled. 8 substeps at 200 Hz gives a 0.625 ms step.
    public func solve(block: Block, motion: GroundMotion, substeps: Int = 8) -> Result {
        guard !block.isRestrained else {
            var r = Result.stable
            r.behaviour = .restrained
            return r
        }

        let dt = motion.dt / Double(substeps)
        let alpha = block.alpha
        let p2 = block.frequencyParameter * block.frequencyParameter
        let R = block.pivotRadius
        let r = block.restitution

        var theta = 0.0          // rocking angle, rad
        var thetaDot = 0.0       // rocking angular velocity, rad/s
        var isRocking = false
        // Which bottom corner the block is currently pivoting about, as the
        // sign of the rotation. This must be tracked explicitly rather than
        // read back from `sgn(theta)`: at the start of a half-cycle theta is
        // exactly zero, and deriving the side from it there makes the very
        // first integration step look like a corner impact.
        var pivotSide = 1.0

        var slipVelocity = 0.0   // block velocity relative to floor, m/s
        var slipPosition = 0.0   // signed net displacement relative to floor, m
        var slipDisplacement = 0.0  // largest net offset reached, m
        var isSliding = false

        var peakRotation = 0.0
        var didSlide = false
        var didRock = false

        for sample in 0..<motion.sampleCount {
            // Signed horizontal excitation. The block tips about whichever axis
            // is weakest, so we drive it with the resultant magnitude carrying
            // the sign of the dominant component — this is the conservative
            // planar reduction of a 2-component motion.
            let axv = motion.ax[sample]
            let azv = motion.az[sample]
            let magnitude = (axv * axv + azv * azv).squareRoot()
            let sign: Double = (abs(axv) >= abs(azv) ? axv : azv) >= 0 ? 1 : -1
            let aNext = magnitude * sign

            // Vertical modulation of the normal force. Upward ground
            // acceleration presses the block down (more friction, harder to
            // rock); downward acceleration unloads it. Clamped at 0.1 so a
            // free-fall instant does not produce a zero or negative normal.
            let n = max(1.0 + motion.ay[sample] / Physics.g, 0.1)

            for _ in 0..<substeps {
                let a = aNext

                // ---- Rocking ----
                if isRocking {
                    // Housner's exact equation, integrated with velocity Verlet
                    // (symplectic — it conserves the rocking energy budget far
                    // better than forward Euler, which artificially pumps
                    // energy in and would topple objects that were only nudged).
                    //
                    //     θ̈ = −p²·[ sin(α·sgn θ − θ) + (a/g)·cos(α·sgn θ − θ) ]
                    //
                    func angularAccel(_ th: Double) -> Double {
                        let phi = alpha * pivotSide - th
                        return -p2 * (sin(phi) + (a / (Physics.g * n)) * cos(phi))
                    }

                    let acc0 = angularAccel(theta)
                    theta += thetaDot * dt + 0.5 * acc0 * dt * dt
                    let acc1 = angularAccel(theta)
                    thetaDot += 0.5 * (acc0 + acc1) * dt

                    peakRotation = max(peakRotation, abs(theta))

                    // Overturned: the centre of mass has passed over the pivot
                    // corner and gravity takes it the rest of the way.
                    if abs(theta) >= alpha {
                        return overturnResult(
                            block: block, alpha: alpha, R: R,
                            thetaDot: thetaDot, peakRotation: abs(theta),
                            time: Double(sample) * motion.dt,
                            slid: slipDisplacement
                        )
                    }

                    // Impact: θ has swung back through zero. The block slaps
                    // down, the rotation axis jumps to the opposite corner, and
                    // a fraction (1 − r) of the rotational energy is lost.
                    if theta * pivotSide <= 0 {
                        thetaDot *= r
                        theta = 0
                        if abs(thetaDot) < 1e-4 {
                            // Rocking has died out; the block is flat again.
                            isRocking = false
                            thetaDot = 0
                        } else {
                            pivotSide = thetaDot >= 0 ? 1 : -1
                        }
                    }
                } else {
                    // ---- Flat on its base: has the rocking threshold been
                    // reached? Uplift begins when the overturning moment of the
                    // inertial force m·a about the leading bottom corner exceeds
                    // the restoring moment of the weight, i.e. |a| > g·n·(b/h).
                    if abs(a) > Physics.g * n * block.aspectRatio {
                        isRocking = true
                        didRock = true
                        theta = 0
                        thetaDot = 0
                        // The block lags the floor, so it rotates *opposite* to
                        // the ground acceleration: the floor slides out from
                        // under it in the +a direction and it tips towards −a.
                        pivotSide = a >= 0 ? -1 : 1
                    }
                }

                // ---- Sliding (Newmark rigid sliding block) ----
                // A rocking block is up on a corner and its sliding behaviour is
                // governed by the rocking solution, so only integrate sliding
                // while the block is flat on its base.
                if !isRocking {
                    let frictionAccel = block.kineticFriction * Physics.g * n
                    if isSliding {
                        // Relative acceleration = −a_ground + friction, with the
                        // friction always opposing the *relative* velocity. At
                        // the instant of release the relative velocity is still
                        // zero, so friction opposes the impending motion, which
                        // is directed opposite to the ground acceleration.
                        let opposing: Double
                        if slipVelocity > 0 { opposing = -frictionAccel }
                        else if slipVelocity < 0 { opposing = frictionAccel }
                        else { opposing = (a >= 0 ? 1.0 : -1.0) * frictionAccel }

                        let relAccel = -a + opposing
                        let newVelocity = slipVelocity + relAccel * dt
                        // Friction cannot reverse the slip direction, only bring
                        // it to rest — the classic Newmark sticking condition.
                        if slipVelocity != 0 && (newVelocity > 0) != (slipVelocity > 0) {
                            slipVelocity = 0
                            isSliding = false
                        } else {
                            slipVelocity = newVelocity
                            slipPosition += slipVelocity * dt
                            slipDisplacement = max(slipDisplacement, abs(slipPosition))
                        }
                    } else if abs(a) > block.staticFriction * Physics.g * n {
                        isSliding = true
                        didSlide = true
                    }

                    // Slid off its support entirely. This uses the *net* offset,
                    // not the total path length: an object that shuffles back
                    // and forth by a centimetre a hundred times has not
                    // travelled a metre towards the edge.
                    if abs(slipPosition) > block.distanceToSupportEdge {
                        return fellOffResult(
                            block: block, peakRotation: peakRotation,
                            alpha: alpha, time: Double(sample) * motion.dt,
                            slid: slipDisplacement, slipSpeed: abs(slipVelocity)
                        )
                    }
                }
            }
        }

        // Survived the record.
        var result = Result.stable
        result.slidingDisplacement = slipDisplacement
        result.peakRotation = peakRotation
        result.rotationRatio = alpha > 0 ? min(peakRotation / alpha, 1.0) : 0
        if didRock && peakRotation > 0.01 {
            result.behaviour = .rocked
        } else if didSlide && slipDisplacement > 0.01 {
            result.behaviour = .slid
        } else {
            result.behaviour = .stable
        }
        return result
    }

    // MARK: - Failure outcomes

    private func overturnResult(
        block: Block, alpha: Double, R: Double,
        thetaDot: Double, peakRotation: Double, time: Double, slid: Double
    ) -> Result {
        // From the point of no return (θ = α) the block free-falls through the
        // remaining rotation to horizontal (π/2 − α), converting the drop of the
        // centre of mass into kinetic energy, on top of whatever rotational
        // energy it already had.
        //
        //   drop of COM = R·(1 − sin α)   as it rotates from θ=α to flat
        //
        // Rotational KE about the pivot with I_O = (4/3)mR²:
        let inertia = (4.0 / 3.0) * block.mass * R * R
        let rotationalKE = 0.5 * inertia * thetaDot * thetaDot
        let comDrop = R * (1.0 - sin(alpha))
        let potentialRelease = block.mass * Physics.g * max(comDrop, 0)
        // Objects on a shelf or table also fall the height of their support.
        let supportDrop = block.mass * Physics.g * block.supportHeight

        let energy = rotationalKE + potentialRelease + supportDrop
        // Equivalent centre-of-mass impact speed, from ½mv² = E.
        let speed = (2.0 * energy / block.mass).squareRoot()

        // How far its top lands from its base: the full height of the object,
        // measured from the pivot corner. For a uniform block that is 2·comHeight.
        let reach = 2.0 * block.comHeight

        return Result(
            behaviour: .overturned,
            slidingDisplacement: slid,
            peakRotation: peakRotation,
            rotationRatio: 1.0,
            timeOfFailure: time,
            impactEnergy: energy,
            impactSpeed: speed,
            falloverReach: reach
        )
    }

    private func fellOffResult(
        block: Block, peakRotation: Double, alpha: Double, time: Double,
        slid: Double, slipSpeed: Double
    ) -> Result {
        // The centre of mass falls the height of the support *plus* its own
        // height above that support, and the object carries the horizontal
        // speed it had when it left the edge. Counting only the support height
        // understates the impact — and, worse, made the reported consequence
        // non-monotonic: an object that slid off at high intensity would score
        // lower than the same object that tipped over at a lower one.
        let drop = max(block.supportHeight + block.comHeight, 0.01)
        let energy = block.mass * Physics.g * drop + 0.5 * block.mass * slipSpeed * slipSpeed
        let speed = (2.0 * energy / block.mass).squareRoot()
        // Horizontal reach while falling: it leaves the edge with its slip speed
        // and falls for t = √(2·drop/g).
        let fallTime = (2.0 * drop / Physics.g).squareRoot()
        return Result(
            behaviour: .fellOffSupport,
            slidingDisplacement: slid,
            peakRotation: peakRotation,
            rotationRatio: alpha > 0 ? min(peakRotation / alpha, 1.0) : 0,
            timeOfFailure: time,
            impactEnergy: energy,
            impactSpeed: speed,
            falloverReach: slipSpeed * fallTime
        )
    }

    // MARK: - Closed-form references (used by tests and by the UI's explanations)

    /// The ground acceleration in g at which this block *begins* to rock. This
    /// is the exact static criterion and is used only for explanation — the
    /// verdict always comes from the full time-history integration.
    public static func rockingInitiationInG(block: Block) -> Double {
        block.aspectRatio
    }

    /// Housner's (1963) closed-form estimate of the minimum *constant*
    /// acceleration, applied for a long enough time, that will overturn a block:
    /// this is simply the rocking threshold, because a sustained acceleration
    /// above it rotates the block monotonically past α. Real records are pulses,
    /// so this is a lower bound on what actually topples things.
    public static func sustainedOverturningInG(block: Block) -> Double {
        block.aspectRatio
    }

    /// The minimum single-pulse velocity change that will overturn the block,
    /// from the Housner energy balance: the pulse must inject enough rotational
    /// kinetic energy to lift the centre of mass from θ=0 to θ=α.
    ///
    ///     ½·I_O·θ̇² ≥ m·g·R·(1 − cos α)  … with θ̇ imparted by the pulse
    ///
    /// Widely used as the "overturning velocity" screening criterion.
    public static func overturningVelocity(block: Block) -> Double {
        let R = block.pivotRadius
        let alpha = block.alpha
        // I_O = (4/3)mR²  →  θ̇_min = √( (3g/2R)·(1 − cos α) )
        let thetaDotMin = ((3.0 * Physics.g / (2.0 * R)) * (1.0 - cos(alpha))).squareRoot()
        // Convert to the equivalent ground velocity pulse at the centre of mass.
        return thetaDotMin * R
    }
}
