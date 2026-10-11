//
//  StageModel.swift
//  Tremor — S-12 / S-13 / S-14 / S-15
//
//  SPEC §1.1 principle 5 and §1.4 S-12: the room viewer, the earthquake
//  configurator, the running simulation and the report are **one screen**. The
//  3D stage is persistent; only the sheet over it changes size and content.
//
//  `AppState` owns what has to outlive this screen — the open room, the latest
//  assessment, which of the four sheet states is showing, what is selected.
//  This model owns everything that is *only* about the stage:
//
//    • the `SimulationController` and the scene built into it,
//    • the orbit camera and the automatic director that moves it,
//    • the configurator's inputs (intensity, magnitude, distance, seed, record),
//    • the run lifecycle: countdown → playing → settle → results,
//    • the plain-language copy every one of those states shows.
//
//  Everything a test can reach without a window server is a `static` pure
//  function at the bottom of the file. That is deliberate: the copy the user
//  reads under stress is the part of this screen most worth pinning down.
//

import Foundation
import Observation
import SwiftUI
import simd

// MARK: - Ground-motion record

/// Which accelerogram the stage shakes with (SPEC §1.4 S-13 item 5).
///
/// v1 synthesises every record from the same site-conditioned synthesiser, so
/// the historical entries select a **seed and a duration character**, not a
/// digitised archive file. The picker still earns its place: it is the honest
/// way to show that overturning is non-monotonic — the same room at the same
/// intensity does not always fail the same way.
enum StageGroundMotion: String, CaseIterable, Identifiable, Hashable, Sendable {
    case synthetic
    case elCentro
    case northridge
    case kobe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .synthetic: return "Synthetic"
        case .elCentro: return "El Centro 1940"
        case .northridge: return "Northridge 1994"
        case .kobe: return "Kobe 1995"
        }
    }

    var detail: String {
        switch self {
        case .synthetic:
            return "Built for your soil and your intensity. The recommended choice."
        case .elCentro:
            return "The long, even shaking of the 1940 Imperial Valley record."
        case .northridge:
            return "A short, violent pulse — the Sylmar station, 1994."
        case .kobe:
            return "A near-field jolt with one very large swing, JMA station, 1995."
        }
    }

    /// The seed offset this record contributes. Mixed with the user's own seed
    /// so "shuffle" still re-rolls inside a chosen record.
    var seedOffset: UInt64 {
        switch self {
        case .synthetic: return 0
        case .elCentro: return 0x1940_0518
        case .northridge: return 0x1994_0117
        case .kobe: return 0x1995_0117
        }
    }
}

// MARK: - Palette bridge

/// `Core/` may not import SwiftUI and the design system may not import the
/// domain, so the two have to be bridged somewhere. The design system bridges
/// them **file-privately** inside each component file, deliberately, so that
/// concurrent work cannot collide on the name — which means this feature needs
/// its own bridge rather than borrowing one.
///
/// Named `stage…` for the same reason: nothing else in the app can clash with
/// it, and a reader can see at a glance which bridge is in play.
extension RiskBand {

    var stageTremorBand: TremorRiskBand {
        switch self {
        case .low: return .low
        case .moderate: return .moderate
        case .high: return .high
        case .severe: return .severe
        }
    }

    /// Saturated colour: numerals, icons, bar fills, rules.
    var stageMark: Color { stageTremorBand.mark }

    /// Soft tinted fill: chips, thumbnails, card washes.
    var stageSurface: Color { stageTremorBand.surface }
}

// MARK: - The model

/// The stage's own state. One per pushed `Route.stage`.
@MainActor
@Observable
final class StageModel {

    /// How the 3D scene itself is doing. Distinct from `AppState.loadPhase`,
    /// which is about the *room document*: a room can load perfectly and still
    /// fail to build a mesh, and SPEC S-12 says that case falls back to a flat
    /// plan rather than to an error screen.
    enum SceneState: Equatable {
        case idle
        case building
        case ready
        /// Carries a sentence a person can act on.
        case failed(String)

        var isBuilding: Bool { self == .building }
        var isReady: Bool { self == .ready }
        var failureMessage: String? {
            if case .failed(let message) = self { return message }
            return nil
        }
    }

    /// S-13's segmented selector.
    enum ConfiguratorMode: String, CaseIterable, Identifiable, Hashable, Sendable {
        case intensity
        case magnitude

        var id: String { rawValue }

        var title: String {
            switch self {
            case .intensity: return "By intensity"
            case .magnitude: return "By magnitude"
            }
        }
    }

    /// Where a run is in its lifecycle. `countdown` carries the number still on
    /// screen, so 3-2-1 is one state rather than three.
    enum RunPhase: Equatable, Sendable {
        case idle
        case countdown(Int)
        case playing
        case paused
        /// The 500 ms after the motion stops, before the report rises.
        case settling
        case finished

        var isCounting: Bool {
            if case .countdown = self { return true }
            return false
        }
    }

    // MARK: Scene

    let controller = SimulationController()

    private(set) var sceneState: SceneState = .idle
    private(set) var runPhase: RunPhase = .idle

    /// The orbit camera. Bound straight into `SimulationView`.
    var camera = StageCameraState()

    /// False once the user drags; the "Auto camera" pill puts it back.
    var isAutoCameraEnabled = true

    /// True when the device asked us to spend less: no shadows, fewer solver
    /// iterations. **The verdict is unaffected** — it comes from the analytic
    /// engine, not from the stage (SPEC §1.4 S-14).
    private(set) var isReducedFidelity = false

    /// Set when the stage could not honour one or more display contracts.
    var didPlaybackDiverge: Bool { controller.didDiverge }

    // MARK: Configurator inputs

    var mode: ConfiguratorMode = .intensity
    /// MMI as a `Double` so `TremorSlider` can drive it with its detents.
    var intensityValue: Double = 8
    var magnitude: Double = 6.5
    var distanceKm: Double = 12
    var record: StageGroundMotion = .synthetic
    var isAdvancedExpanded = false
    private(set) var seed: UInt64 = 0x1ED6E

    /// The intensity the CTA will actually shake with, in either mode.
    var selectedIntensity: MercalliIntensity {
        switch mode {
        case .intensity:
            return Self.intensity(fromSliderValue: intensityValue)
        case .magnitude:
            return derivedIntensity
        }
    }

    // MARK: Room context

    private(set) var room: ScannedRoom?

    /// The building's own amplification, ground → this floor.
    var floorAmplification: Double { room?.building.floorAmplification ?? 1 }

    /// Peak ground acceleration for the selected intensity, in g.
    var groundPGAInG: Double {
        switch mode {
        case .intensity: return selectedIntensity.representativePGAInG
        case .magnitude: return derivedGroundPGAInG
        }
    }

    /// What the floor this room sits on actually reaches, in g.
    var floorPGAInG: Double { groundPGAInG * floorAmplification }

    private var derivedGroundPGAInG: Double {
        IntensityScale.pgaInG(
            magnitude: magnitude,
            distanceKm: distanceKm,
            soil: room?.building.soil ?? .firm)
    }

    private var derivedIntensity: MercalliIntensity {
        IntensityScale.bin(forPGAInG: derivedGroundPGAInG)
    }

    // MARK: Run read-outs

    /// Live acceleration, read off the accelerogram — never off the physics
    /// engine (SPEC §4.7.6 guarantee 5).
    var liveAccelerationInG: Double { controller.currentAccelerationInG }
    var peakAccelerationInG: Double { controller.peakAccelerationInG }

    /// The highest live value reached so far, for the meter's peak tick.
    private(set) var reachedAccelerationInG: Double = 0

    /// The impact ticker: at most three, newest first.
    var recentFailures: [FailureMarker] { controller.recentEvents }

    /// The "what just happened" line, in the present progressive.
    private(set) var liveCaption: String = ""

    // MARK: Tasks

    @ObservationIgnored private var cameraTask: Task<Void, Never>?
    @ObservationIgnored private var directorTask: Task<Void, Never>?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var lastCaptionedMarker: UUID?

    init() {}

    deinit {
        cameraTask?.cancel()
        directorTask?.cancel()
        runTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Seeds the configurator from the room and from whatever the user last
    /// asked for, then builds the idle scene.
    ///
    /// Idempotent per room: re-entering S-12 for a room already on the stage
    /// does not rebuild the meshes, which is what "Run again returns to S-13
    /// with state preserved and no reprocessing" depends on.
    func prepare(room: ScannedRoom,
                 assessment: RoomAssessment?,
                 defaultIntensity: MercalliIntensity) async {
        applyDeviceBudget()

        if self.room?.id != room.id {
            self.room = room
            intensityValue = Double((assessment?.intensity ?? defaultIntensity).rawValue)
            seed = assessment?.seed ?? 0x1ED6E
        } else {
            self.room = room
        }

        guard controller.room?.id != room.id || sceneState == .idle else { return }

        sceneState = .building
        // The idle stage is deliberately built with **no** assessment: SPEC
        // S-12 says nothing is tinted and nothing shakes until the user asks.
        await controller.loadOffMain(room: room, assessment: nil, intensity: nil, seed: seed)
        sceneState = controller.stage == nil
            ? .failed("We couldn't build the 3D view of this room. Your report is unaffected — here's the floor plan instead.")
            : .ready
        resetRunReadouts()
    }

    /// Loads the settled stage for a room that has already been simulated, so
    /// "See the report" lands on a risk-tinted room rather than a blank one.
    func prepareResults(room: ScannedRoom, assessment: RoomAssessment) async {
        applyDeviceBudget()
        self.room = room
        intensityValue = Double(assessment.intensity.rawValue)
        seed = assessment.seed
        sceneState = .building
        await controller.loadOffMain(
            room: room,
            assessment: assessment,
            intensity: assessment.intensity,
            seed: assessment.seed)
        sceneState = controller.stage == nil
            ? .failed("We couldn't build the 3D view of this room. Your report is unaffected — here's the floor plan instead.")
            : .ready
        runPhase = .finished
        resetRunReadouts()
    }

    /// Builds the scenario for the chosen earthquake and plays it, countdown
    /// first. `onFinish` fires once the motion has stopped and settled.
    ///
    /// The assessment handed in must already be for this intensity — the
    /// scenario builder drops one that is not, on purpose, rather than
    /// captioning a body with another earthquake's verdict.
    func run(room: ScannedRoom,
             assessment: RoomAssessment?,
             reduceMotion: Bool,
             hapticsEnabled: Bool,
             onFinish: @escaping () -> Void) {
        runTask?.cancel()
        // Set synchronously, before the task exists: callers key off `runPhase`
        // to decide whether a run is already under way, and leaving it `.idle`
        // until the task's first suspension point makes "start a run if nothing
        // is running" start two.
        runPhase = .countdown(3)
        runTask = Task { [weak self] in
            guard let self else { return }
            await self.performRun(
                room: room,
                assessment: assessment,
                reduceMotion: reduceMotion,
                hapticsEnabled: hapticsEnabled,
                onFinish: onFinish)
        }
    }

    private func performRun(room: ScannedRoom,
                            assessment: RoomAssessment?,
                            reduceMotion: Bool,
                            hapticsEnabled: Bool,
                            onFinish: @escaping () -> Void) async {
        applyDeviceBudget()
        sceneState = .building
        resetRunReadouts()
        controller.selectedObjectID = nil

        await controller.loadOffMain(
            room: room,
            assessment: assessment,
            intensity: selectedIntensity,
            seed: resolvedSeed)

        guard !Task.isCancelled else { return }
        guard controller.stage != nil else {
            sceneState = .failed("We couldn't build the 3D view of this room. Your report is unaffected — here's the floor plan instead.")
            onFinish()
            return
        }
        sceneState = .ready

        // Wide establishing shot before the count, so the first thing the user
        // sees is the whole room they are about to lose. Same framing rule as
        // the viewer — the sheet is gone, so the fraction is zero.
        reframe(forSheetFraction: 0, animated: !reduceMotion)

        for step in [3, 2, 1] {
            guard !Task.isCancelled else { return }
            runPhase = .countdown(step)
            if hapticsEnabled { TremorHaptic.light.play() }
            try? await Task.sleep(nanoseconds: UInt64(Self.countdownStepSeconds * 1_000_000_000))
        }
        guard !Task.isCancelled else { return }

        runPhase = .playing
        controller.play()
        if hapticsEnabled { TremorHaptic.medium.play() }
        startDirector(reduceMotion: reduceMotion)

        // Poll rather than subscribe: the controller is `@Observable` and has no
        // completion callback, and a 20 Hz poll on the main actor is free next
        // to a live RealityKit scene.
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 50_000_000)
            updateLiveReadouts(hapticsEnabled: hapticsEnabled)
            if controller.isFinished { break }
        }
        guard !Task.isCancelled else { return }

        runPhase = .settling
        directorTask?.cancel()
        try? await Task.sleep(nanoseconds: UInt64(Self.settleSeconds * 1_000_000_000))
        guard !Task.isCancelled else { return }

        controller.selectedObjectID = nil
        runPhase = .finished
        onFinish()
    }

    /// Replays the motion already loaded. No rebuild, no re-solve.
    func replay(reduceMotion: Bool, hapticsEnabled: Bool) {
        runTask?.cancel()
        controller.restart()
        resetRunReadouts()
        runPhase = .playing
        controller.play()
        startDirector(reduceMotion: reduceMotion)
        runTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                self.updateLiveReadouts(hapticsEnabled: hapticsEnabled)
                if self.controller.isFinished { break }
            }
            guard !Task.isCancelled else { return }
            self.runPhase = .finished
        }
    }

    func togglePlayback() {
        controller.togglePlayback()
        runPhase = controller.isPlaying ? .playing : .paused
    }

    func seek(to time: Double) {
        controller.seek(to: time)
        reachedAccelerationInG = max(reachedAccelerationInG, controller.currentAccelerationInG)
        liveCaption = controller.firedMarkers.last.map(Self.liveCaption(for:)) ?? ""
    }

    func setRate(_ rate: PlaybackRate) {
        controller.setRate(rate)
    }

    /// Abandons whatever is running and puts the stage back to rest. Called
    /// when the user leaves the screen mid-shake.
    func cancelRun() {
        runTask?.cancel()
        directorTask?.cancel()
        cameraTask?.cancel()
        controller.pause()
        runPhase = .idle
        resetRunReadouts()
    }

    func teardown() {
        cancelRun()
        controller.detach()
    }

    // MARK: - Seeds

    /// The seed the next run uses: the user's own, mixed with the chosen
    /// record so switching records genuinely re-rolls the motion.
    var resolvedSeed: UInt64 { seed &+ record.seedOffset }

    /// Re-rolls the accelerogram. SPEC §1.4 S-13: this is the honest way to
    /// show that a larger pulse can leave standing what a smaller one topples.
    func shuffleSeed() {
        seed = UInt64.random(in: 1...UInt64(UInt32.max))
    }

    // MARK: - Camera

    /// Frames the whole room, and tells the director it may drive again.
    func recentre(animated: Bool) {
        isAutoCameraEnabled = true
        guard let bounds = controller.stage?.roomBounds else { return }
        var target = StageCameraState.framing(bounds: bounds)
        target.isUserControlled = false
        move(to: target, animated: animated)
    }

    /// Adjusts the framing for how much of the screen the sheet is covering.
    ///
    /// The camera looks at a point; the point lands in the middle of the
    /// display. As the sheet grows, the *visible* middle rises, so the look-at
    /// point drops and the camera pulls back a little to keep the room whole.
    func reframe(forSheetFraction fraction: Double, animated: Bool) {
        guard let bounds = controller.stage?.roomBounds, !camera.isUserControlled else { return }
        var target = StageCameraState.framing(bounds: bounds)
        // A little higher than the default framing pitch: from 24° the near wall
        // of a scanned room cuts across the bottom of the shot, and the user is
        // looking at the *contents*, not the architecture.
        target.pitch = StageCameraState.clampPitch(Self.viewerPitch)
        target.distance *= Float(Self.cameraPullback(forSheetFraction: fraction))
        target.target.y -= Self.cameraDrop(
            forSheetFraction: fraction, distance: Double(target.distance))
        move(to: target, animated: animated)
    }

    /// Tweens the camera. `StageCameraState` is not `Animatable`, so SwiftUI
    /// cannot interpolate it for us — the tween is explicit and cancellable.
    func move(to destination: StageCameraState, animated: Bool, duration: Double = 0.55) {
        cameraTask?.cancel()
        guard animated else {
            camera = destination
            return
        }
        let start = camera
        cameraTask = Task { [weak self] in
            let steps = max(Int(duration * 60), 1)
            for step in 1...steps {
                guard !Task.isCancelled else { return }
                let t = Self.easeOut(Double(step) / Double(steps))
                self?.camera = Self.interpolate(start, destination, t)
                try? await Task.sleep(nanoseconds: 16_666_666)
            }
        }
    }

    /// The automatic director (SPEC §1.4 S-14): whole room for 2 s, a medium
    /// shot of the first object to fail for 2.5 s, then back to a wide. A
    /// manual drag takes over permanently; Reduce Motion disables it outright.
    private func startDirector(reduceMotion: Bool) {
        directorTask?.cancel()
        guard !reduceMotion, isAutoCameraEnabled else { return }
        directorTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(Self.directorWideSeconds * 1_000_000_000))
            guard !Task.isCancelled, self.isAutoCameraEnabled, !self.camera.isUserControlled else { return }

            if let marker = self.controller.markers.first,
               let body = self.controller.body(for: marker.objectID) {
                self.move(to: Self.mediumShot(of: body, from: self.camera), animated: true)
                try? await Task.sleep(nanoseconds: UInt64(Self.directorCloseSeconds * 1_000_000_000))
            }
            guard !Task.isCancelled, self.isAutoCameraEnabled, !self.camera.isUserControlled
            else { return }
            self.reframe(forSheetFraction: 0, animated: true)
        }
    }

    /// Called by the view when the user drags the stage.
    func userTookCamera() {
        guard isAutoCameraEnabled else { return }
        isAutoCameraEnabled = false
        directorTask?.cancel()
        cameraTask?.cancel()
    }

    // MARK: - Live read-outs

    private func updateLiveReadouts(hapticsEnabled: Bool) {
        reachedAccelerationInG = max(reachedAccelerationInG, controller.currentAccelerationInG)
        guard let latest = controller.firedMarkers.last else { return }
        guard latest.objectID != lastCaptionedMarker else { return }
        lastCaptionedMarker = latest.objectID
        liveCaption = Self.liveCaption(for: latest)
        // Highlight what just went: the stage's own selection outline is the
        // only 3D affordance we have, and nothing else is using it mid-run.
        controller.selectedObjectID = latest.objectID
        if hapticsEnabled { TremorHaptic.medium.play() }
    }

    private func resetRunReadouts() {
        reachedAccelerationInG = 0
        liveCaption = ""
        lastCaptionedMarker = nil
    }

    /// SPEC §1.4 S-14: low power or a hot phone drops the stage's fidelity and
    /// says so. Nothing about the verdict changes.
    private func applyDeviceBudget() {
        let info = ProcessInfo.processInfo
        let constrained = info.isLowPowerModeEnabled
            || info.thermalState == .serious
            || info.thermalState == .critical
        guard constrained != isReducedFidelity else { return }
        isReducedFidelity = constrained
        var options = controller.sceneOptions
        options.castShadows = !constrained
        controller.sceneOptions = options
    }

    // MARK: - Derived copy

    /// "12 objects · Ground floor of 2 · Hardwood"
    var roomSubtitle: String {
        guard let room else { return "" }
        return Self.roomSubtitle(objectCount: room.objects.count, building: room.building)
    }

    /// The live meter's fill fraction, normalised against the record's own peak
    /// so the bar uses its whole travel whatever the intensity.
    var meterFraction: Double {
        guard peakAccelerationInG > 0 else { return 0 }
        return min(max(liveAccelerationInG / peakAccelerationInG, 0), 1)
    }

    var meterPeakFraction: Double {
        guard peakAccelerationInG > 0 else { return 0 }
        return min(max(reachedAccelerationInG / peakAccelerationInG, 0), 1)
    }
}

// MARK: - Pure helpers

extension StageModel {

    /// 250 ms per step (SPEC §1.4 S-14 *Countdown*).
    nonisolated static let countdownStepSeconds: Double = 0.25
    /// The pause between the motion stopping and the report rising.
    nonisolated static let settleSeconds: Double = 0.5
    /// Director cue times.
    nonisolated static let directorWideSeconds: Double = 2.0
    nonisolated static let directorCloseSeconds: Double = 2.5

    /// The slider runs MMI V…X: below V nothing in a house moves, and above X
    /// the building itself is the hazard, not the furniture.
    nonisolated static let intensityRange: ClosedRange<Double> = 5...10

    nonisolated static func intensity(fromSliderValue value: Double) -> MercalliIntensity {
        let clamped = Int(value.rounded())
        return MercalliIntensity(rawValue: min(max(clamped, 3), 10)) ?? .viii
    }

    /// The band the slider's gradient and thumb take at a given MMI.
    ///
    /// Aligned to `MercalliIntensity.shakingLabel`, not to an even split of the
    /// range: the slider sits directly under a pill that says "VIII · Severe",
    /// and a slider chip reading "High" next to it would be the app arguing with
    /// itself about the same number.
    nonisolated static func band(forSliderValue value: Double) -> TremorRiskBand {
        switch intensity(fromSliderValue: value) {
        case .iii, .iv, .v: return .low
        case .vi: return .moderate
        case .vii: return .high
        case .viii, .ix, .x: return .severe
        }
    }

    /// "0.34 g" — always with the unit, never bare.
    nonisolated static func pgaLabel(_ g: Double) -> String {
        if g >= 1 { return String(format: "%.2f g", g) }
        return String(format: "%.2f g", g)
    }

    /// "1.9×", or "about the same" when the building does not amplify.
    nonisolated static func amplificationLabel(_ factor: Double) -> String {
        String(format: "%.1f×", factor)
    }

    /// SPEC §1.4 S-13 item 6 — the single most persuasive line in the app, so
    /// it has to be true on the ground floor too.
    nonisolated static func amplificationSentence(floor: Int, factor: Double) -> String {
        guard factor > 1.05 else {
            return "You're on the ground floor, so your room feels the shaking almost exactly as it arrives."
        }
        return "Your floor shakes about \(amplificationLabel(factor)) as hard as the ground."
    }

    /// "12 objects · Ground floor of 2 · Hardwood"
    nonisolated static func roomSubtitle(objectCount: Int, building: BuildingContext) -> String {
        let objects = objectCount == 1 ? "1 object" : "\(objectCount) objects"
        let storey: String
        switch building.floor {
        case 0: storey = "Ground floor"
        case 1: storey = "1st floor"
        case 2: storey = "2nd floor"
        case 3: storey = "3rd floor"
        default: storey = "\(building.floor)th floor"
        }
        let of = building.totalStoreys > 1 ? "\(storey) of \(building.totalStoreys)" : storey
        return "\(objects) · \(of) · \(building.floorSurface.displayName)"
    }

    /// "3 hazards", "1 hazard", "Nothing falls".
    nonisolated static func hazardCountPhrase(_ count: Int) -> String {
        switch count {
        case 0: return "Nothing falls"
        case 1: return "1 hazard"
        default: return "\(count) hazards"
        }
    }

    /// "at intensity VIII — severe shaking"
    nonisolated static func intensityPhrase(_ intensity: MercalliIntensity) -> String {
        "at intensity \(intensity.roman) — \(intensity.shakingLabel.lowercased()) shaking"
    }

    /// The live caption, in the present progressive: what is happening *now*,
    /// not what happened. Never jargon — "going over", not "overturning".
    nonisolated static func liveCaption(for marker: FailureMarker) -> String {
        let name = spokenName(marker.displayName)
        switch marker.ending {
        case .topples: return "The \(name) is going over"
        case .fallsOff: return "The \(name) is coming off its shelf"
        case .detaches: return "The \(name) is coming off the wall"
        case .slides: return "The \(name) is sliding across the floor"
        case .rocks: return "The \(name) is rocking"
        case .stays: return "The \(name) is holding"
        }
    }

    /// "Bookcase toppled — 2.4 s" — the impact ticker line.
    nonisolated static func tickerLine(for marker: FailureMarker) -> String {
        String(format: "%@ %@ — %.1f s", marker.displayName, marker.ending.pastTense, marker.time)
    }

    /// A subtitle for a hazard row: what it does, what it lands on, and how hard.
    ///
    /// The "onto the …" clause and the impact energy are attached **only** to
    /// the behaviours that actually put something on the floor. "Stays put onto
    /// the bed" is the kind of sentence a template writes and a person never
    /// does.
    nonisolated static func hazardSubtitle(behaviour: RigidBlockSolver.Behaviour,
                               impactEnergy: Double,
                               endangers: [String]) -> String {
        let verb: String
        let lands: Bool
        switch behaviour {
        case .overturned: verb = "Topples"; lands = true
        case .fellOffSupport: verb = "Falls off its support"; lands = true
        case .slid: verb = "Slides across the floor"; lands = false
        case .rocked: verb = "Rocks, but stays up"; lands = false
        case .stable: verb = "Stays put"; lands = false
        case .restrained: verb = "Held by its fixing"; lands = false
        }

        guard lands else { return verb }

        var line = verb
        if let first = endangers.first {
            line += " onto the \(spokenName(first))"
        }
        if impactEnergy >= 1 {
            line += " · \(Int(impactEnergy.rounded())) J of impact"
        }
        return line
    }

    /// Lower-cases a display name for use mid-sentence, without flattening a
    /// name that is genuinely capitalised ("TV", "IKEA Billy").
    nonisolated static func spokenName(_ name: String) -> String {
        guard let first = name.first else { return name }
        let rest = name.dropFirst()
        if rest.contains(where: { $0.isUppercase }) { return name }
        return first.lowercased() + rest
    }

    /// Elevation for the idle and configurator shots, radians — 45°, not the
    /// framing default's 24°.
    ///
    /// A scanned room is a closed box: from a low angle the two *near* walls
    /// stand between the camera and everything the user came to look at, and
    /// half the frame is the back of a wall. Forty-five degrees looks over them
    /// into the room — the dollhouse view — while still being oblique enough
    /// that a bookcase reads as tall rather than as a rectangle on a plan.
    nonisolated static let viewerPitch: Float = 0.785

    /// The vertical drop applied to the look-at point so the room sits in the
    /// middle of the part of the display the sheet is **not** covering.
    ///
    /// The camera's look-at point lands at the centre of the display. The
    /// visible strip runs from the top to `(1 − fraction)·H`, so its centre is
    /// `fraction/2` of a screen height above the display's centre — and the
    /// subject has to move up by exactly that much. One screen height spans
    /// `2·d·tan(fov/2)` metres at the subject, which for the stage's 50° lens is
    /// `0.933·d`.
    nonisolated static func cameraDrop(forSheetFraction fraction: Double, distance: Double) -> Float {
        let clamped = min(max(fraction, 0), 1)
        let verticalExtent = 2 * max(distance, 0.5) * tan(50.0 * .pi / 360)
        return Float(clamped / 2 * verticalExtent * cameraDropDamping)
    }

    /// Full centring is the wrong answer past about half a screen: it lifts the
    /// room clean out of the top of the frame, because the strip the sheet
    /// leaves is smaller than the room's own angular size. Lyft's map does the
    /// same thing — it recentres part of the way and lets the content run on
    /// under the sheet, rather than pretending the sheet is not there.
    /// Measured on device rather than reasoned about: at 0.6 the room sat low
    /// in the frame with roughly a quarter of the visible strip empty above it.
    /// 0.85 puts the room in the middle of the strip while still letting the
    /// floor run on under the sheet, which is the effect we want.
    nonisolated static let cameraDropDamping: Double = 0.85

    /// How much further back to sit as the sheet grows, so the room still fits
    /// the strip that is left.
    /// A little air even at the peek detent, so the room's own walls never run
    /// out to the screen edge and under the floating controls.
    nonisolated static let cameraBaseMargin: Double = 1.08

    nonisolated static func cameraPullback(forSheetFraction fraction: Double) -> Double {
        cameraBaseMargin + min(max(fraction, 0), 1) * 0.55
    }

    /// A 2.5 s medium shot of one body: closer in, swung round a little, and
    /// centred on the object rather than on the room.
    ///
    /// Deliberately *not* a close-up. An object that is about to topple needs
    /// the floor it is going to land on in frame, or the shot reads as an
    /// abstract shape moving; and the pitch stays near the viewer's so the cut
    /// back out to the wide is a pan rather than a jump.
    nonisolated static func mediumShot(of body: BodySpec, from current: StageCameraState) -> StageCameraState {
        let height = max(body.sizeM.y, 0.4)
        let reach = max(simd_length(body.sizeM), 0.6)
        return StageCameraState(
            yaw: current.yaw + 0.30,
            pitch: viewerPitch * 0.72,
            distance: max(reach * 3.4, 2.6),
            target: SIMD3(body.placement.centre.x, height * 0.45, body.placement.centre.z),
            isUserControlled: false)
    }

    nonisolated static func interpolate(_ a: StageCameraState,
                            _ b: StageCameraState,
                            _ t: Double) -> StageCameraState {
        let f = Float(min(max(t, 0), 1))
        // Shortest way round for the azimuth, so a pan never takes the long way.
        var deltaYaw = b.yaw - a.yaw
        while deltaYaw > .pi { deltaYaw -= 2 * .pi }
        while deltaYaw < -.pi { deltaYaw += 2 * .pi }
        return StageCameraState(
            yaw: a.yaw + deltaYaw * f,
            pitch: a.pitch + (b.pitch - a.pitch) * f,
            distance: a.distance + (b.distance - a.distance) * f,
            target: a.target + (b.target - a.target) * f,
            isUserControlled: b.isUserControlled)
    }

    nonisolated static func easeOut(_ t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        return 1 - pow(1 - clamped, 3)
    }
}
