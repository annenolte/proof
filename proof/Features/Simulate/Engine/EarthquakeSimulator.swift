import Foundation
import Combine
import RealityKit
import simd

// MARK: - Live state

/// What one object is doing right now, as the stage sees it. This is display
/// state: it drives highlights and captions. It is never a verdict.
public struct ObjectMotionState: Sendable, Equatable {

    public enum Phase: String, Sendable {
        case atRest
        case moving
        case tipping
        case fallen

        public var isMoving: Bool { self != .atRest }
    }

    public var phase: Phase
    /// Net horizontal displacement from the starting position, metres.
    public var displacementM: Double
    /// Tilt of the body's own up axis away from world up, radians.
    public var tiltRadians: Double
    /// Speed of the body, m/s.
    public var speedMPerS: Double
    /// True once Track A's failure time for this object has passed.
    public var hasFailed: Bool

    public static let atRest = ObjectMotionState(
        phase: .atRest, displacementM: 0, tiltRadians: 0, speedMPerS: 0, hasFailed: false)

    public var tiltDegrees: Double { tiltRadians * 180 / .pi }
}

/// Things the stage reports upwards. None of them carry a physics read-out that
/// the user sees as a number.
public enum StageEvent: Sendable {
    case stepped(time: Double)
    /// Mirrors Track A's timeline, not a collision event.
    case objectFailed(objectID: UUID, time: Double)
    case finished
    case contractViolated(objectID: UUID)
}

// MARK: - Simulator

/// Drives base excitation on the RealityKit stage and keeps it honest.
///
/// - Floor and walls are `.static` and never move.
/// - Every dynamic body gets `F = −m·a_g(t)` once per **physics** step, applied
///   from `PhysicsSimulationEvents.WillSimulate`. Never from
///   `SceneEvents.Update`, which fires at display rate and was measured to
///   double the force on a 120 Hz panel.
/// - The vertical component of the record is folded into
///   `PhysicsSimulationComponent.gravity`, which is exact and free.
/// - Anchored, wall-mounted and built-in bodies start `.kinematic` and are
///   released only at the instant Track A says their fixing fails.
@MainActor
public final class EarthquakeSimulator {

    /// How the shared accelerogram is mapped onto each body.
    public enum ExcitationMode: String, Sendable, CaseIterable {
        /// The excitation each body receives is the record's horizontal
        /// **resultant magnitude**, signed the way `RigidBlockSolver` signs it,
        /// applied along that body's own weak axis.
        ///
        /// This is not a licence taken with the physics — it is what Track A
        /// integrated. `RigidBlockSolver` reduces the two-component motion to
        /// `magnitude · sign` and evaluates it against `governingHalfWidth`,
        /// i.e. the smaller footprint dimension, because "a block tips about its
        /// weakest axis". Driving the RealityKit body with the true world
        /// vector instead makes the two tracks solve *different problems*: a
        /// 0.8 × 0.3 m bookcase shaken along its 0.8 m face has a restoring
        /// moment 2.7× larger than the one the report is based on, so it slides
        /// where the report says it topples — and no capped corrective torque
        /// can bridge that, nor should it have to.
        case weakAxisAligned
        /// The true world-space vector. Physically literal, but it does not
        /// reproduce the analytic model. Used by physics-agreement work where
        /// the two engines are compared on identical, axis-aligned setups.
        case trueVector
    }

    /// Defaults to `.weakAxisAligned` so the stage reproduces the verdict from
    /// physics rather than from corrective control.
    public var excitationMode: ExcitationMode = .weakAxisAligned

    // MARK: Runtime record per body

    private final class Runtime {
        let spec: BodySpec
        let entity: ModelEntity
        let contract: DisplayContract
        let trajectory: DisplayTrajectory
        let startPosition: SIMD3<Float>
        /// The world-space axis this body tips most easily about, cached so the
        /// hot loop does no maths it does not have to.
        let weakAxis: SIMD3<Float>
        var isDynamic: Bool
        var wasReleased: Bool = false
        var state: ObjectMotionState = .atRest

        init(
            spec: BodySpec, entity: ModelEntity,
            contract: DisplayContract, trajectory: DisplayTrajectory
        ) {
            self.spec = spec
            self.entity = entity
            self.contract = contract
            self.trajectory = trajectory
            self.startPosition = entity.position
            self.weakAxis = spec.weakAxisDirection
            self.isDynamic = spec.startsDynamic
        }
    }

    // MARK: Stored

    public let scenario: SimulationScenario
    public let stage: SceneBuilder.Stage
    public let clock: PlaybackClock

    /// Bounded corrective control. Disabled in the physics-agreement tests so
    /// the raw agreement between the two engines can be measured.
    public var reconciler: OutcomeReconciler

    private var runtimes: [UUID: Runtime] = [:]
    private var orderedRuntimes: [Runtime] = []
    private var subscription: (any Cancellable)?

    /// Simulation time in seconds, advanced by the physics step — never by the
    /// wall clock.
    public private(set) var time: Double = 0
    public private(set) var stepCount: Int = 0
    public private(set) var isPlaying = false
    public private(set) var didFinish = false
    /// Objects whose `DisplayContract` was not satisfied by the end of the run.
    public private(set) var divergences: Set<UUID> = []
    /// How many steps the reconciler saturated on. Telemetry, per SPEC §4.7.6.
    public private(set) var saturationCount = 0

    public var onEvent: ((StageEvent) -> Void)?

    /// Keyframed transforms for backwards scrubbing, every `keyframeInterval`
    /// of simulation time.
    private var keyframes: [(time: Double, transforms: [UUID: Transform])] = []
    private let keyframeInterval: Double = 0.5
    private var nextKeyframeTime: Double = 0
    private var firedMarkers: Set<UUID> = []

    public var duration: Double { scenario.duration }
    public var isFinished: Bool { didFinish || time >= duration }
    public var progress: Double {
        duration > 0 ? min(max(time / duration, 0), 1) : 0
    }

    // MARK: Init

    public init(
        stage: SceneBuilder.Stage,
        scenario: SimulationScenario,
        reconciler: OutcomeReconciler = OutcomeReconciler()
    ) {
        self.stage = stage
        self.scenario = scenario
        self.reconciler = reconciler
        self.clock = PlaybackClock()

        for spec in scenario.bodies {
            guard let entity = stage.bodies[spec.id] else { continue }
            let contract = scenario.contracts[spec.id] ?? DisplayContract(ending: .stays)
            let trajectory = DisplayTrajectory(
                contract: contract, body: spec, duration: scenario.duration)
            let runtime = Runtime(
                spec: spec, entity: entity, contract: contract, trajectory: trajectory)
            runtimes[spec.id] = runtime
            orderedRuntimes.append(runtime)
        }
        recordKeyframe(at: 0)
    }

    // MARK: Attach

    /// Subscribes to the per-physics-step hook. Call once the stage's anchor is
    /// in a live `RealityKit.Scene`.
    public func attach(to scene: RealityKit.Scene) {
        detach()
        clock.attach(to: stage.simulationRoot)
        subscription = scene.subscribe(
            to: PhysicsSimulationEvents.WillSimulate.self,
            on: stage.simulationRoot
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.step(deltaTime: event.deltaTime)
            }
        }
    }

    public func detach() {
        subscription?.cancel()
        subscription = nil
    }

    // MARK: Transport

    public func play() {
        guard !isFinished else { return }
        isPlaying = true
        clock.start()
    }

    public func pause() {
        isPlaying = false
        clock.stop()
    }

    public func togglePlayback() {
        isPlaying ? pause() : play()
    }

    public func setRate(_ rate: PlaybackRate) {
        clock.setRate(rate)
    }

    public var rate: PlaybackRate { clock.rate }

    /// Back to t = 0 with every body where it started.
    public func restart() {
        pause()
        time = 0
        stepCount = 0
        didFinish = false
        divergences.removeAll()
        firedMarkers.removeAll()
        saturationCount = 0
        keyframes.removeAll()
        nextKeyframeTime = 0
        stage.resetTransforms()
        for runtime in orderedRuntimes {
            runtime.state = .atRest
            runtime.wasReleased = false
            runtime.isDynamic = runtime.spec.startsDynamic
            setMode(runtime.spec.startsDynamic ? .dynamic : .kinematic, on: runtime)
        }
        clock.rewind()
        recordKeyframe(at: 0)
        resetSimulationGravity()
    }

    /// Scrubs to a time.
    ///
    /// Sim time cannot outrun wall time, so seeking *forward* past what has
    /// already been simulated is not possible; the stage snaps to the nearest
    /// keyframe at or before the target and reports the time it actually landed
    /// on. Backwards scrubbing is exact to the keyframe grid (0.5 s).
    @discardableResult
    public func seek(to target: Double) -> Double {
        let clamped = min(max(target, 0), duration)
        guard let frame = keyframes.last(where: { $0.time <= clamped + 1e-9 }) else {
            restart()
            return 0
        }
        let wasPlaying = isPlaying
        pause()
        for (id, transform) in frame.transforms {
            guard let runtime = runtimes[id] else { continue }
            runtime.entity.transform = transform
            if runtime.entity.components.has(PhysicsMotionComponent.self) {
                runtime.entity.components.set(PhysicsMotionComponent())
            }
            runtime.entity.resetPhysicsTransform(recursive: false)
        }
        time = frame.time
        didFinish = time >= duration
        firedMarkers = Set(
            scenario.failureTimeline.filter { $0.time <= time }.map(\.objectID))
        // Drop keyframes that are now in the future: they describe a run we are
        // about to replace.
        keyframes.removeAll { $0.time > frame.time }
        nextKeyframeTime = frame.time + keyframeInterval
        refreshStates()
        if wasPlaying { play() }
        return time
    }

    // MARK: Queries

    public func state(for id: UUID) -> ObjectMotionState {
        runtimes[id]?.state ?? .atRest
    }

    public var states: [UUID: ObjectMotionState] {
        runtimes.mapValues(\.state)
    }

    /// Ground acceleration in g at the current simulation time, read from the
    /// accelerogram — never from the engine.
    public var currentAccelerationInG: Double {
        scenario.accelerationInG(at: time)
    }

    // MARK: - The per-physics-step hook

    func step(deltaTime: TimeInterval) {
        guard isPlaying, !didFinish else { return }

        let acceleration = scenario.motion.acceleration(at: time)
        applyVerticalComponent(acceleration.y)

        // The planar reduction `RigidBlockSolver` performs, reproduced exactly:
        // resultant magnitude, carrying the sign of the dominant component.
        let horizontal = SIMD3<Float>(Float(acceleration.x), 0, Float(acceleration.z))
        let magnitude = simd_length(horizontal)
        let dominant = abs(acceleration.x) >= abs(acceleration.z)
            ? acceleration.x : acceleration.z
        let signedMagnitude = magnitude * (dominant >= 0 ? 1 : -1)

        for runtime in orderedRuntimes {
            releaseIfDue(runtime)
            guard runtime.isDynamic else { continue }

            // d'Alembert inertial force. This, and only this, is the excitation.
            let applied: SIMD3<Float>
            switch excitationMode {
            case .weakAxisAligned: applied = runtime.weakAxis * signedMagnitude
            case .trueVector: applied = horizontal
            }
            if applied != .zero {
                runtime.entity.addForce(
                    -Float(runtime.spec.massKg) * applied, relativeTo: nil)
            }

            // The body lags the floor, so it moves and tips *opposite* to the
            // applied ground acceleration.
            let excitationDirection = simd_length(applied) > 1e-6
                ? -simd_normalize(applied) : SIMD3<Float>.zero
            let observation = observe(runtime, excitationDirection: excitationDirection)
            runtime.state = phase(from: observation, runtime: runtime)

            let correction = reconciler.correction(
                body: runtime.spec,
                contract: runtime.contract,
                trajectory: runtime.trajectory,
                observation: observation,
                time: time)
            if correction.didSaturate { saturationCount += 1 }
            if correction.torque != .zero {
                runtime.entity.addTorque(correction.torque, relativeTo: nil)
            }
            if correction.force != .zero {
                runtime.entity.addForce(correction.force, relativeTo: nil)
            }
        }

        fireDueMarkers()

        time += PlaybackClock.simulationAdvance(
            deltaTime: deltaTime, rate: clock.rate,
            isTimebaseActive: clock.isTimebaseActive)
        stepCount += 1

        if time >= nextKeyframeTime {
            recordKeyframe(at: time)
            nextKeyframeTime = time + keyframeInterval
        }

        onEvent?(.stepped(time: time))

        if time >= duration {
            finish()
        }
    }

    // MARK: - Pieces

    private func applyVerticalComponent(_ verticalAcceleration: Double) {
        guard var simulation = stage.simulationRoot
            .components[PhysicsSimulationComponent.self] else { return }
        simulation.gravity = SIMD3(0, Float(-(Physics.g + verticalAcceleration)), 0)
        stage.simulationRoot.components.set(simulation)
    }

    private func resetSimulationGravity() {
        guard var simulation = stage.simulationRoot
            .components[PhysicsSimulationComponent.self] else { return }
        simulation.gravity = SIMD3(0, Float(-Physics.g), 0)
        stage.simulationRoot.components.set(simulation)
    }

    /// Anchored, wall-mounted and built-in objects hold still until the analytic
    /// verdict says their fixing let go. Then, and only then, they become
    /// dynamic and fall like anything else.
    private func releaseIfDue(_ runtime: Runtime) {
        guard !runtime.isDynamic, !runtime.wasReleased else { return }
        guard runtime.contract.ending.isFailure,
              let failureTime = runtime.contract.expectedFailureTimeS,
              time >= failureTime
        else { return }
        runtime.wasReleased = true
        runtime.isDynamic = true
        setMode(.dynamic, on: runtime)
        // A fixing that lets go does not start from rest in the ground frame:
        // it starts with the wall's own velocity. A small outward nudge reads
        // far better than a body that simply begins to sag.
        var motion = PhysicsMotionComponent()
        motion.linearVelocity = SIMD3(0, -0.05, 0)
        runtime.entity.components.set(motion)
    }

    private func setMode(_ mode: PhysicsBodyMode, on runtime: Runtime) {
        guard var body = runtime.entity.components[PhysicsBodyComponent.self] else { return }
        body.mode = mode
        runtime.entity.components.set(body)
        if mode == .dynamic, !runtime.entity.components.has(PhysicsMotionComponent.self) {
            runtime.entity.components.set(PhysicsMotionComponent())
        }
    }

    private func observe(
        _ runtime: Runtime, excitationDirection: SIMD3<Float>
    ) -> OutcomeReconciler.Observation {
        let orientation = runtime.entity.orientation(relativeTo: nil)
        let up = orientation.act(SIMD3<Float>(0, 1, 0))
        let tilt = Double(acos(min(max(up.y, -1), 1)))

        let offset = runtime.entity.position(relativeTo: nil) - runtime.startPosition
        let flat = SIMD3<Float>(offset.x, 0, offset.z)
        let displacement = Double(simd_length(flat))

        let slideDirection = displacement > 1e-3
            ? simd_normalize(flat) : excitationDirection

        let upFlat = SIMD3<Float>(up.x, 0, up.z)
        let tipDirection = simd_length(upFlat) > 1e-4
            ? simd_normalize(upFlat) : excitationDirection

        return OutcomeReconciler.Observation(
            tiltRadians: tilt,
            displacementM: displacement,
            slideDirection: slideDirection,
            tipDirection: tipDirection)
    }

    private func phase(
        from observation: OutcomeReconciler.Observation, runtime: Runtime
    ) -> ObjectMotionState {
        let speed = Double(simd_length(
            runtime.entity.components[PhysicsMotionComponent.self]?.linearVelocity ?? .zero))
        let hasFailed = firedMarkers.contains(runtime.spec.id)

        let phase: ObjectMotionState.Phase
        if observation.tiltRadians > 70 * .pi / 180 {
            phase = .fallen
        } else if observation.tiltRadians > max(runtime.spec.alphaRadians * 0.35, 0.06) {
            phase = .tipping
        } else if observation.displacementM > 0.01 || speed > 0.05 {
            phase = .moving
        } else {
            phase = .atRest
        }

        return ObjectMotionState(
            phase: phase,
            displacementM: observation.displacementM,
            tiltRadians: observation.tiltRadians,
            speedMPerS: speed,
            hasFailed: hasFailed)
    }

    private func refreshStates() {
        for runtime in orderedRuntimes {
            let observation = observe(runtime, excitationDirection: .zero)
            runtime.state = phase(from: observation, runtime: runtime)
        }
    }

    /// Emits `objectFailed` on Track A's timeline. The impact ticker in S-14 is
    /// driven by this, not by `CollisionEvents`.
    private func fireDueMarkers() {
        for marker in scenario.failureTimeline
        where marker.time <= time && !firedMarkers.contains(marker.objectID) {
            firedMarkers.insert(marker.objectID)
            onEvent?(.objectFailed(objectID: marker.objectID, time: marker.time))
        }
    }

    private func recordKeyframe(at time: Double) {
        var transforms: [UUID: Transform] = [:]
        for runtime in orderedRuntimes {
            transforms[runtime.spec.id] = runtime.entity.transform
        }
        keyframes.append((time: time, transforms: transforms))
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        isPlaying = false
        clock.stop()
        auditContracts()
        onEvent?(.finished)
    }

    /// Compares the settled scene against every contract. A violation changes
    /// the playback caption and **nothing in the report**.
    private func auditContracts() {
        for runtime in orderedRuntimes {
            let observation = observe(runtime, excitationDirection: .zero)
            let satisfied = runtime.contract.isSatisfied(
                byTilt: observation.tiltRadians,
                displacement: observation.displacementM,
                alpha: runtime.spec.alphaRadians)
            if !satisfied {
                divergences.insert(runtime.spec.id)
                onEvent?(.contractViolated(objectID: runtime.spec.id))
            }
        }
    }
}
