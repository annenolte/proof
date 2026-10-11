import Foundation
import RealityKit
import SwiftUI
import simd

// State for the demo room screen: the scene, the camera, the quake, and which phase of
// the scripted flow we are in.

@MainActor
@Observable
final class DemoRoomModel {

    enum Phase: Equatable {
        /// The opening card with the single call to action.
        case intro
        /// Reviewing the captured walkthrough.
        case reviewing
        /// The (scripted) reconstruction.
        case generating
        /// Free exploration.
        case exploring
        /// Shaking.
        case shaking
        /// Post-quake summary.
        case results
    }

    private(set) var phase: Phase = .intro
    private(set) var scene: ApartmentScene?
    private(set) var isSceneReady = false
    private(set) var buildSeconds: Double = 0

    var pose = DemoCameraPose()
    let quake = DemoQuake()
    let audio = DemoAudio()
    /// Records every shake, so the results sheet can offer the clip.
    let clip = DemoClipRecorder()

    /// Created with the quake and torn down with it, so no collision subscription is live
    /// while the user is only exploring.
    private(set) var breakage: BreakageSystem?

    /// Selected object, surfaced as a label in the explorer.
    var selectedPropID: String?

    /// Called once per rendered frame with the live view — how the star overlay learns
    /// where each object lands on screen.
    @ObservationIgnored var frameHandler: ((ARView) -> Void)?

    /// Called on every physics step with its duration — how proof's pull test drives forces.
    @ObservationIgnored var physicsHandler: ((Double) -> Void)?

    /// Auto-rotate the establishing shot until the user takes the camera.
    var isIdleOrbiting = true

    // MARK: - Flow

    func begin() { phase = .intro }

    /// `-tremorDemoPhase explore` skips the scripted opening and lands straight in the
    /// room. Rehearsing the demo, and iterating on how the room looks, both want this;
    /// tapping through the video every time is a tax on both.
    func applyLaunchOverride() async -> Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-proofDemoPhase"),
              index + 1 < arguments.count else { return false }
        let target = arguments[index + 1]

        // The two scripted screens need no scene, so they can be reached instantly.
        switch target {
        case "review":
            phase = .reviewing
            Task { await prepareScene() }
            return true
        case "generating":
            phase = .generating
            // The reconstruction screen waits for the room rather than building
            // it, so nothing would ever start the build on this path.
            Task { await prepareScene() }
            return true
        default:
            break
        }

        guard target == "explore" || target == "shake" else { return false }

        await prepareScene()
        phase = .exploring

        var mode = DemoCameraMode.orbit
        if let modeIndex = arguments.firstIndex(of: "-proofDemoMode"),
           modeIndex + 1 < arguments.count,
           let parsed = DemoCameraMode(rawValue: arguments[modeIndex + 1]) {
            mode = parsed
        }
        pose = DemoCameraPose.preset(for: mode, from: pose)
        isIdleOrbiting = false   // hold the framing still for screenshots

        // `-tremorDemoEvent nc216859` — one of the site's real earthquakes, by USGS id, so a
        // recorded run can be rehearsed without tapping through the site sheet.
        if target == "shake",
           let index = arguments.firstIndex(of: "-proofDemoEvent"),
           index + 1 < arguments.count,
           let event = (site.scenarios + site.history).first(where: { $0.id == arguments[index + 1] }) {
            startQuake(event: event)
            // `-tremorDemoAftershock` follows the mainshock with its first aftershock, the
            // way the results sheet's button would.
            if arguments.contains("-proofDemoAftershock") {
                Task {
                    while quake.state != .finished {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    try? await Task.sleep(for: .seconds(2))
                    startAftershock()
                }
            }
            return true
        }

        if target == "shake" {
            // `-tremorDemoIntensity ix` — rehearsing breakage needs the top of the picker,
            // and tapping through to it every time is the same tax the phase argument
            // exists to remove.
            var intensity = MercalliIntensity.viii
            if let index = arguments.firstIndex(of: "-proofDemoIntensity"),
               index + 1 < arguments.count {
                let roman = arguments[index + 1].lowercased()
                intensity = MercalliIntensity.allCases.first { $0.roman.lowercased() == roman }
                    ?? .viii
            }
            startQuake(intensity: intensity)
        }
        return true
        #else
        return false
        #endif
    }

    func reviewScan() { phase = .reviewing }

    func confirmScan() {
        phase = .generating
    }

    func finishGenerating() {
        guard phase == .generating else { return }
        phase = .exploring
        pose = DemoCameraPose.preset(for: .orbit, from: pose)
        isIdleOrbiting = true
    }

    /// Where the apartment is. Baked, not looked up — see `DemoSite`.
    let site = DemoSite.livermore

    func startQuake(intensity: MercalliIntensity) {
        guard let scene else { return }
        quake.start(intensity: intensity, scene: scene)
        beginShaking(scene: scene)
    }

    /// Runs one of the site's real scenario or historical earthquakes.
    func startQuake(event: DemoSite.Event) {
        guard let scene else { return }
        quake.start(
            event: event, site: site, scene: scene,
            recording: DemoRecordingLibrary.recording(for: event))
        beginShaking(scene: scene)
    }

    /// Shakes the room again as the last quake left it — nothing is put back, and the
    /// shards from the mainshock stay on the floor.
    func startAftershock() {
        guard let scene, quake.nextAftershock != nil else { return }
        quake.startAftershock(scene: scene)
        beginShaking(scene: scene, keepingBreakage: true)
    }

    private func beginShaking(scene: ApartmentScene, keepingBreakage: Bool = false) {
        // The shake reads best from inside the room rather than from orbit, but forcing a
        // mode change would take the camera away from wherever the user parked it. So the
        // mode is left alone and only the idle rotation is stopped.
        isIdleOrbiting = false

        if !keepingBreakage || breakage == nil {
            let system = BreakageSystem(scene: scene, audio: audio)
            system.onBreak = { [weak self] event in
                self?.quake.recordBreak(
                    propID: event.propID, name: event.name, category: event.category
                )
            }
            breakage = system
        }
        audio.startRumble()
        clip.start()

        phase = .shaking
    }

    func stopQuake() {
        guard let scene else { return }
        quake.stop(scene: scene)
        endShakeEffects()
        pose.shakeOffset = .zero
        phase = .exploring
    }

    /// Silences the rumble and puts every shard back in the object it came from. Called on
    /// every exit from the quake — cancelled, finished, or reset.
    private func endShakeEffects() {
        audio.stopRumble()
        clip.discard()
        breakage?.reset()
        breakage?.detach()
        breakage = nil
    }

    func showResults() { phase = .results }

    func resetRoom() {
        guard let scene else { return }
        quake.stop(scene: scene)
        endShakeEffects()
        pose = DemoCameraPose.preset(for: pose.mode, from: pose)
        pose.shakeOffset = .zero
        phase = .exploring
    }

    /// Drops the room and returns to the opening state.
    ///
    /// Used when a flow that hosts this model starts over: the quake is stopped,
    /// the shards and the rumble go, the in-flight build is cancelled and the
    /// scene reference is released so RealityKit can free the entities and their
    /// textures — several hundred megabytes of them. Calling `prepareScene()`
    /// afterwards builds a fresh room rather than handing back the old one.
    func teardown() {
        if let scene { quake.stop(scene: scene) }
        endShakeEffects()
        buildTask?.cancel()
        buildTask = nil
        scene = nil
        isSceneReady = false
        buildSeconds = 0
        selectedPropID = nil
        pose = DemoCameraPose()
        isIdleOrbiting = true
        phase = .intro
    }

    // MARK: - Scene

    private var buildTask: Task<Void, Never>?

    /// Builds the apartment. Texture synthesis is the expensive part and happens off the
    /// main actor; only the GPU resource creation has to come back to it.
    ///
    /// Idempotent and re-entrant: the flow kicks this off as soon as the screen appears,
    /// so it runs underneath the walkthrough video, and the generating screen simply
    /// awaits the same task rather than starting a second one.
    func prepareScene() async {
        if let buildTask {
            await buildTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self, self.scene == nil else { return }
            let started = Date()
            let materials = await DemoMaterials.make()
            let built = ApartmentScene(materials: materials)
            built.build()
            self.scene = built
            self.buildSeconds = Date().timeIntervalSince(started)
            self.isSceneReady = true
        }
        buildTask = task
        await task.value
    }

    // MARK: - Per-frame

    func tick(deltaTime: Double) {
        guard let scene else { return }
        physicsHandler?(deltaTime)

        if phase == .shaking {
            quake.step(deltaTime: deltaTime, scene: scene)
            pose.shakeOffset = quake.groundOffset
            breakage?.update(deltaTime: deltaTime, groundAcceleration: quake.currentHorizontal)
            audio.setGroundAcceleration(quake.currentAccelerationG, deltaTime: deltaTime)
            if quake.state == .finished {
                // The rumble goes, but the debris stays: it is the evidence the results
                // sheet is about. Ticking `breakage` stops here too, which freezes the
                // shards' despawn clocks so they are still on the floor behind the sheet.
                audio.stopRumble()
                clip.finishAfterSettling()
                phase = .results
            }
        } else if isIdleOrbiting && phase == .exploring {
            DemoCameraRig.idleOrbit(&pose, deltaTime: Float(deltaTime))
        }
    }

    // MARK: - Camera

    /// Deliberately not gated on `phase`: switching to walk mid-quake and standing in the
    /// room while it shakes is the best thing this demo does. `preset` leaves
    /// `shakeOffset` alone (it is not one of the fields `blend`/`preset` touch), and walk
    /// mode subtracts it from both the eye and the look-at, so the room keeps shaking
    /// around the walker.
    func setMode(_ mode: DemoCameraMode) {
        guard mode != pose.mode else { return }
        pose = DemoCameraPose.preset(for: mode, from: pose)
        // Only the automatic establishing rotation is phase-gated — nobody wants the
        // camera drifting on its own during the quake.
        isIdleOrbiting = (mode == .orbit) && phase == .exploring
        // The ceiling and wall cutaway follow the camera every frame in
        // `ApartmentScene.applyCutaway`, so there is nothing to toggle here.
    }

    func userTookCamera() {
        isIdleOrbiting = false
    }

    var modeHint: String {
        switch pose.mode {
        case .orbit: return "Drag to orbit · pinch to zoom"
        case .walk: return "Drag to look · use the pad to move"
        case .plan: return "Drag to pan · pinch to zoom"
        }
    }
}
