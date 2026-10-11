import Foundation
import Observation
import RealityKit
import simd

/// The observable object the simulation UI binds to.
///
/// It owns the scene, the playback clock, the current `RoomAssessment`, the live
/// per-object state, and the timeline of when each object failed. Everything a
/// scrubber, a per-object highlight and a "what just happened" caption need is
/// on this type; the surrounding UI does not talk to RealityKit at all.
@MainActor
@Observable
public final class SimulationController {

    // MARK: Content

    public private(set) var room: ScannedRoom?
    public private(set) var assessment: RoomAssessment?
    public private(set) var scenario: SimulationScenario?
    public private(set) var stage: SceneBuilder.Stage?

    /// Options the scene was built with. Change before `load` to restyle.
    public var sceneOptions: SceneBuilder.Options = .default

    /// Corrective control. Off in the physics-agreement tests.
    public var isReconciliationEnabled = true {
        didSet { simulator?.reconciler.isEnabled = isReconciliationEnabled }
    }

    @ObservationIgnored
    private var simulator: EarthquakeSimulator?

    // MARK: Playback state

    public private(set) var time: Double = 0
    public private(set) var duration: Double = 0
    public private(set) var isPlaying = false
    public private(set) var isFinished = false
    public private(set) var rate: PlaybackRate = .normal

    public var progress: Double {
        duration > 0 ? min(max(time / duration, 0), 1) : 0
    }

    /// Elapsed / total, formatted for the transport bar.
    public var elapsedLabel: String { Self.timeLabel(time) }
    public var durationLabel: String { Self.timeLabel(duration) }

    // MARK: Live object state

    public private(set) var states: [UUID: ObjectMotionState] = [:]
    /// Objects currently doing something, worth highlighting.
    public var movingObjectIDs: [UUID] {
        states.filter { $0.value.phase.isMoving }.map(\.key)
    }

    public var selectedObjectID: UUID? {
        didSet { stage?.setSelection(selectedObjectID) }
    }

    // MARK: Timeline

    /// When each object failed, in chronological order, straight from Track A.
    public private(set) var markers: [FailureMarker] = []
    /// Markers whose time has passed at the current playhead.
    public private(set) var firedMarkers: [FailureMarker] = []
    /// The most recent three failures, newest first — the impact ticker.
    public var recentEvents: [FailureMarker] {
        Array(firedMarkers.suffix(3).reversed())
    }

    /// The "what just happened" line. Empty until something happens.
    public private(set) var caption: String = ""

    /// True when the stage could not satisfy one or more display contracts. The
    /// UI shows "Playback simplified"; the report is untouched.
    public private(set) var didDiverge = false

    // MARK: Motion read-outs (from the accelerogram, never from the engine)

    public private(set) var currentAccelerationInG: Double = 0
    public var peakAccelerationInG: Double { scenario?.peakAccelerationInG ?? 0 }
    public var intensity: MercalliIntensity? { scenario?.intensity }

    public init() {}

    // MARK: - Loading

    /// Builds the scenario and the scene for a room.
    ///
    /// - Parameters:
    ///   - room: the scanned room.
    ///   - assessment: the ensemble verdict. Pass nil for the idle room viewer,
    ///     where nothing is tinted and nothing shakes.
    ///   - intensity: overrides the assessment's intensity for a preview.
    ///
    /// This overload does **all** of its work on the main actor, including
    /// `SimulationScenario.build`, which synthesises a ~27 s accelerogram and
    /// integrates the rigid-block solver once per object. Prefer
    /// ``loadOffMain(room:assessment:intensity:seed:)`` from UI code; this one
    /// exists for tests, previews and anything already off the hot path.
    public func load(
        room: ScannedRoom,
        assessment: RoomAssessment?,
        intensity: MercalliIntensity? = nil,
        seed: UInt64 = 0x1ED6E
    ) {
        let scenario = SimulationScenario.build(
            room: room, assessment: assessment, intensity: intensity, seed: seed)
        load(room: room, scenario: scenario)
    }

    /// The same load with the arithmetic moved off the main actor.
    ///
    /// Everything before `SceneBuilder` is pure computation over `Sendable`
    /// values and has no business blocking the run loop: on a 20-object room the
    /// accelerogram synthesis plus twenty solver integrations is tens of
    /// milliseconds — several dropped frames on the transition *into* the
    /// simulation screen, which is the first thing the user sees. `SceneBuilder`
    /// and everything after it genuinely must be main-actor: they build
    /// RealityKit entities.
    public func loadOffMain(
        room: ScannedRoom,
        assessment: RoomAssessment?,
        intensity: MercalliIntensity? = nil,
        seed: UInt64 = 0x1ED6E
    ) async {
        let scenario = await Task.detached(priority: .userInitiated) {
            SimulationScenario.build(
                room: room, assessment: assessment, intensity: intensity, seed: seed)
        }.value
        load(room: room, scenario: scenario)
    }

    /// The main-actor half, shared by both entry points.
    ///
    /// The assessment is taken from the **scenario**, not from the caller.
    /// `SimulationScenario.build` drops an assessment belonging to a different
    /// room rather than captioning bodies with another room's verdict; storing
    /// the caller's copy here would put that verdict straight back into the
    /// object cards the controller feeds, which is exactly what the drop was
    /// protecting against.
    private func load(room: ScannedRoom, scenario: SimulationScenario) {
        teardown()

        let assessment = scenario.assessment
        var options = sceneOptions
        options.tintByRisk = options.tintByRisk && assessment != nil
        let stage = SceneBuilder.build(room: room, scenario: scenario, options: options)

        let simulator = EarthquakeSimulator(stage: stage, scenario: scenario)
        simulator.reconciler.isEnabled = isReconciliationEnabled
        simulator.onEvent = { [weak self] event in
            self?.handle(event)
        }

        self.room = room
        self.assessment = assessment
        self.scenario = scenario
        self.stage = stage
        self.simulator = simulator

        duration = scenario.duration
        markers = scenario.failureTimeline
        firedMarkers = []
        states = Dictionary(
            uniqueKeysWithValues: scenario.bodies.map { ($0.id, ObjectMotionState.atRest) })
        time = 0
        isPlaying = false
        isFinished = false
        didDiverge = false
        caption = ""
        currentAccelerationInG = 0
        stage.setSelection(selectedObjectID)
    }

    /// Connects the simulator to a live RealityKit scene. `SimulationView` calls
    /// this from `RealityView`'s make closure.
    public func attach(to scene: RealityKit.Scene) {
        simulator?.attach(to: scene)
    }

    public func detach() {
        simulator?.detach()
    }

    private func teardown() {
        simulator?.pause()
        simulator?.detach()
        simulator = nil
        stage = nil
    }

    // MARK: - Transport

    public func play() {
        simulator?.play()
        syncPlaybackFlags()
    }

    public func pause() {
        simulator?.pause()
        syncPlaybackFlags()
    }

    public func togglePlayback() {
        simulator?.togglePlayback()
        syncPlaybackFlags()
    }

    public func restart() {
        simulator?.restart()
        firedMarkers = []
        caption = ""
        didDiverge = false
        time = 0
        currentAccelerationInG = 0
        states = states.mapValues { _ in ObjectMotionState.atRest }
        syncPlaybackFlags()
    }

    /// Scrubs. Returns the time actually landed on — forward seeks snap to the
    /// last simulated keyframe, because the engine cannot outrun real time.
    @discardableResult
    public func seek(to target: Double) -> Double {
        guard let simulator else { return 0 }
        let landed = simulator.seek(to: target)
        time = landed
        states = simulator.states
        firedMarkers = markers.filter { $0.time <= landed }
        caption = firedMarkers.last?.caption ?? ""
        currentAccelerationInG = simulator.currentAccelerationInG
        syncPlaybackFlags()
        return landed
    }

    public func setRate(_ newRate: PlaybackRate) {
        rate = newRate
        simulator?.setRate(newRate)
    }

    // MARK: - Queries for the UI

    public func state(for objectID: UUID) -> ObjectMotionState {
        states[objectID] ?? .atRest
    }

    public func marker(for objectID: UUID) -> FailureMarker? {
        markers.first { $0.objectID == objectID }
    }

    public func body(for objectID: UUID) -> BodySpec? {
        scenario?.body(id: objectID)
    }

    public func contract(for objectID: UUID) -> DisplayContract? {
        scenario?.contract(for: objectID)
    }

    public func risk(for objectID: UUID) -> ObjectRisk? {
        assessment?.risk(for: objectID)
    }

    /// The object id behind a tapped entity.
    public func objectID(for entity: Entity?) -> UUID? {
        stage?.objectID(for: entity)
    }

    /// A one-line description of the selected object's fate, for the caption
    /// area when nothing has just happened.
    public func summary(for objectID: UUID) -> String? {
        guard let body = scenario?.body(id: objectID),
              let contract = scenario?.contract(for: objectID) else { return nil }
        return "\(body.displayName) \(contract.ending.presentTense)"
    }

    // MARK: - Events

    private func handle(_ event: StageEvent) {
        guard let simulator else { return }
        switch event {
        case .stepped(let t):
            time = t
            currentAccelerationInG = simulator.currentAccelerationInG
            states = simulator.states
        case .objectFailed(let objectID, let failureTime):
            if let marker = markers.first(where: { $0.objectID == objectID }) {
                firedMarkers.append(marker)
                caption = marker.caption
            } else if let body = scenario?.body(id: objectID) {
                caption = String(format: "%@ failed — %.1f s", body.displayName, failureTime)
            }
        case .finished:
            isPlaying = false
            isFinished = true
            didDiverge = !simulator.divergences.isEmpty
            states = simulator.states
        case .contractViolated:
            didDiverge = true
        }
    }

    private func syncPlaybackFlags() {
        guard let simulator else {
            isPlaying = false
            return
        }
        isPlaying = simulator.isPlaying
        isFinished = simulator.isFinished
        rate = simulator.rate
    }

    // MARK: - Formatting

    static func timeLabel(_ seconds: Double) -> String {
        let clamped = max(seconds, 0)
        return String(format: "%d:%04.1f", Int(clamped) / 60, clamped.truncatingRemainder(dividingBy: 60))
    }
}
