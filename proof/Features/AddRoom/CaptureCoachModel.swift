//
//  CaptureCoachModel.swift
//  Tremor — Add Room / where to point the phone, and for how long
//
//  ─────────────────────────────────────────────────────────────────────────
//  TO POINT THE WALKTHROUGH AT A DIFFERENT CLIP, EDIT ONE LINE
//  ─────────────────────────────────────────────────────────────────────────
//  Search this file for `static let current` — it is the single declaration
//  under `DemoCaptureSource` and it is the only line that decides which video
//  the viewfinder plays. Today:
//
//      static let current: DemoCaptureSource = .bundled
//
//  Point it at anything reachable over the network with:
//
//      static let current: DemoCaptureSource = .remote(URL(string: "https://…/clip.mp4")!)
//
//  `AVPlayer` treats a file URL and an HTTP URL identically, so nothing else in
//  the app changes — not this model, not the layer, not the chrome. A remote
//  clip simply starts a beat later while the first range is fetched.
//  ─────────────────────────────────────────────────────────────────────────
//
//  WHAT THIS TYPE IS FOR
//  ---------------------
//  A guided panorama has to answer one question continuously — *where do I
//  point next* — and it has to answer it identically whether the pixels are
//  coming from the camera or from a file. So coverage, elapsed time and the
//  coaching line all come from here, and the view never computes any of them.
//
//  COVERAGE IS SWEPT ANGLE, NOT ELAPSED TIME
//  ------------------------------------------
//  On a device with a gyroscope the ring fills from the *accumulated absolute
//  yaw* reported by `CMMotionManager`, so standing still fills nothing and
//  turning back on yourself still counts as work done. That is the honest
//  measure of a panorama, and it is the same discipline `ScanCoach.progress`
//  applies to a LiDAR scan: no timer anywhere in the number the user is
//  watching.
//
//  Where there is no device motion — the Simulator, and every `#Preview` — the
//  ring falls back to elapsed time against a fixed sweep duration, because a
//  frozen progress ring makes the whole screen look broken. And when the
//  walkthrough video is playing, coverage *is* video progress: the clip is one
//  complete lap of the room, so its playhead is a truthful coverage figure.
//
//  The coaching copy is the scan flow's, in the scan flow's tone: say what to
//  do, one instruction at a time, never scold, never use a word only an
//  engineer knows. `ScanCoaching` is reused verbatim so the pill that renders
//  it is the same pill S-09 uses.
//

import AVFoundation
import CoreMotion
import Foundation
import Observation
import SwiftUI

// MARK: - Where the walkthrough comes from

/// The clip the viewfinder plays when someone asks for the prepared room.
///
/// Two cases, one behaviour: both resolve to a URL and `AVPlayer` handles them
/// the same way. See the header for the one line to change.
enum DemoCaptureSource: Equatable, Sendable {

    /// `DemoRoomScan.mp4`, shipped in `Tremor/Resources` and already in the
    /// build. The ten-second handheld lap of the apartment.
    case bundled

    /// Any URL `AVPlayer` can open — an HTTPS file, an HLS playlist, a file on
    /// disk. Identical downstream.
    case remote(URL)

    // ── ONE LINE TO EDIT ────────────────────────────────────────────────
    /// The clip in use. Change this and nothing else.
    static let current: DemoCaptureSource = .bundled
    // ────────────────────────────────────────────────────────────────────

    /// Nil only when the bundled asset is missing from the target, in which
    /// case the screen quietly stays on the live feed rather than blanking.
    var url: URL? {
        switch self {
        case .bundled:
            return Bundle.main.url(forResource: "DemoRoomScan", withExtension: "mp4")
        case .remote(let url):
            return url
        }
    }
}

// MARK: - The script

/// The rotating instructions, and which way the arrow points while each one is
/// on screen.
///
/// A beat is chosen by coverage rather than by a timer so that the words always
/// match what the user has actually done. Someone who sweeps fast reaches
/// "pan up to the shelves" sooner; someone who stops hears nothing new, which
/// is correct — repeating an instruction they have not carried out yet is how a
/// coach becomes noise.
enum CaptureCoachScript {

    /// Which way the on-screen arrow points. `none` means the instruction is
    /// about standing still, so no arrow is drawn at all.
    enum PanDirection: String, Equatable, Sendable {
        case none
        case right
        case up
        case down

        var symbolName: String? {
            switch self {
            case .none: return nil
            case .right: return "chevron.right"
            case .up: return "chevron.up"
            case .down: return "chevron.down"
            }
        }

        /// Spoken to VoiceOver, which cannot see a chevron.
        var spoken: String? {
            switch self {
            case .none: return nil
            case .right: return "Pan to your right"
            case .up: return "Pan upwards"
            case .down: return "Tilt downwards"
            }
        }
    }

    struct Beat: Equatable, Sendable {
        /// The beat is on screen while coverage is below this.
        let until: Double
        let coaching: ScanCoaching
        let pan: PanDirection
    }

    /// Before the capture starts. Reused verbatim from S-09 so the two capture
    /// screens open with the same sentence.
    static let standby = ScanCoach.preparing

    static let beats: [Beat] = [
        Beat(until: 0.12,
             coaching: ScanCoaching(
                headline: "Stand in a corner",
                detail: "From a corner you can see the whole room without walking.",
                symbolName: "figure.stand",
                tone: .nudge),
             pan: .none),
        Beat(until: 0.45,
             coaching: ScanCoaching(
                headline: "Sweep slowly to your right",
                detail: "Turn on the spot. One slow lap is all it takes.",
                symbolName: "arrow.clockwise",
                tone: .nudge),
             pan: .right),
        Beat(until: 0.68,
             coaching: ScanCoaching(
                headline: "Keep the floor in frame",
                detail: "Where the wall meets the floor is what the room is measured from.",
                symbolName: "square.split.bottomrightquarter",
                tone: .steady),
             pan: .down),
        Beat(until: 0.90,
             coaching: ScanCoaching(
                headline: "Now pan up to the shelves",
                detail: "Anything above head height matters most in an earthquake.",
                symbolName: "books.vertical",
                tone: .nudge),
             pan: .up),
        Beat(until: .infinity,
             coaching: ScanCoach.readyToFinish,
             pan: .none)
    ]

    static func beat(at coverage: Double) -> Beat {
        beats.first { coverage < $0.until } ?? beats[beats.count - 1]
    }
}

// MARK: - The model

/// Drives the guided capture screen: what is on the viewfinder, how far round
/// the sweep has got, how long it has been running and what to say next.
///
/// One object covers both sources on purpose. Once `loadWalkthrough()` has been
/// called the screen behaves exactly as it did a moment earlier — the timer
/// still runs, the ring still fills, the coach still advances — because every
/// one of those readings is derived here from whichever source is live, and the
/// view cannot tell the difference.
@MainActor
@Observable
final class CaptureCoachModel {

    /// What is filling the viewfinder.
    enum Mode: Equatable {
        /// Nothing is being recorded yet.
        case standby
        /// The live camera, with the user sweeping.
        case live
        /// The prepared walkthrough is playing.
        case walkthrough
    }

    // MARK: Published state

    private(set) var mode: Mode = .standby
    /// Seconds on the record indicator. Against the wall clock while live;
    /// against the clip's own playhead during the walkthrough.
    private(set) var elapsed: TimeInterval = 0
    /// 0…1 around the ring.
    private(set) var coverage: Double = 0
    private(set) var coaching: ScanCoaching = CaptureCoachScript.standby
    private(set) var pan: CaptureCoachScript.PanDirection = .none
    /// True once the walkthrough has played through. It plays exactly once —
    /// a loop is what makes a clip read as canned rather than as a recording
    /// being made right now.
    private(set) var didPlayThrough = false
    /// Handed to `VideoPlaybackLayer`. Nil in every other mode.
    private(set) var player: AVPlayer?
    /// The record button's state. Paused keeps everything already covered —
    /// there is no way on this screen to throw away a sweep by accident.
    private(set) var isPaused = false

    var isRecording: Bool { mode != .standby }
    var isWalkthrough: Bool { mode == .walkthrough }
    /// Whether the recording indicator should be pulsing right now.
    var isCapturing: Bool { isRecording && !didPlayThrough && !isPaused }
    /// The Next button's gate.
    var canFinish: Bool { coverage >= Metric.adequateCoverage || didPlayThrough }

    /// What VoiceOver reads for the ring.
    var coverageDescription: String {
        "\(Int((coverage * 100).rounded())) percent of the room covered"
    }

    // MARK: Private state

    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    /// Accumulated absolute yaw, radians. The panorama's real progress measure.
    @ObservationIgnored private var sweptRadians: Double = 0
    @ObservationIgnored private var lastYaw: Double?
    /// False until the gyroscope has actually delivered a sample, which is what
    /// selects the time-based fallback rather than merely asking the hardware
    /// whether it exists.
    @ObservationIgnored private var hasMotionSamples = false

    // MARK: Lifecycle

    /// Begins a live capture. Coverage starts accruing from device motion, or
    /// from the clock where there is none.
    func startLiveCapture() {
        guard mode == .standby else { return }
        resetProgress()
        mode = .live
        startMotionUpdates()
        startTicking()
    }

    /// Swaps the live feed for the prepared walkthrough and keeps recording.
    ///
    /// Everything the user can see carries on behaving as it did: the indicator
    /// keeps pulsing, the timer keeps counting, the ring keeps filling and the
    /// coaching keeps advancing — all now driven by the clip's playhead.
    ///
    /// - Returns: false when the clip could not be opened, so the caller can
    ///   stay on the live feed instead of showing a black rectangle.
    @discardableResult
    func loadWalkthrough() -> Bool {
        guard let url = DemoCaptureSource.current.url else { return false }

        stopMotionUpdates()
        resetProgress()

        let player = AVPlayer(url: url)
        player.isMuted = true
        // A viewfinder never rewinds itself, so neither does this. The other half of
        // that decision lives in `GuidedCaptureView`: the chrome switches to a
        // *stopped* recording indicator when the clip runs out, and the last frame
        // keeps drifting, so stopping is not the same as freezing.
        player.actionAtItemEnd = .pause
        self.player = player

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.notePlayedThrough() }
        }

        mode = .walkthrough
        startTicking()
        player.play()
        return true
    }

    /// The record button. Starts a capture that has not begun, and otherwise
    /// pauses or resumes the one that has — including the walkthrough, which
    /// pauses on its own frame exactly as a paused recording would.
    func toggleCapture() {
        switch mode {
        case .standby:
            startLiveCapture()
        case .live:
            isPaused.toggle()
        case .walkthrough:
            guard !didPlayThrough else { return }
            isPaused.toggle()
            if isPaused { player?.pause() } else { player?.play() }
        }
        TremorHaptic.selection.play()
    }

    /// Ends everything: the tick, the gyroscope, the clip and the observer.
    /// Called on disappear and before the screen hands control on.
    func stop() {
        tickTask?.cancel()
        tickTask = nil
        stopMotionUpdates()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player?.pause()
        player = nil
        mode = .standby
    }

    // MARK: The tick

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Metric.tickNanoseconds)
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        guard !isPaused else { return }
        switch mode {
        case .standby:
            return
        case .live:
            // Accumulated rather than read off the wall clock, so a pause is a
            // pause: the timer stops where it stopped and resumes from there.
            elapsed += Metric.tickInterval
            coverage = liveCoverage()
        case .walkthrough:
            guard let player else { return }
            let played = player.currentTime().seconds
            elapsed = played.isFinite ? max(played, 0) : 0
            let duration = player.currentItem?.duration.seconds ?? .nan
            if duration.isFinite, duration > 0 {
                coverage = min(max(elapsed / duration, 0), 1)
            }
            if didPlayThrough { coverage = 1 }
        }
        applyScript()
    }

    /// Swept angle where the gyroscope is talking to us, elapsed time where it
    /// is not.
    private func liveCoverage() -> Double {
        if motion.isDeviceMotionAvailable, let yaw = motion.deviceMotion?.attitude.yaw {
            hasMotionSamples = true
            if let last = lastYaw {
                // Yaw wraps at ±π; the shortest signed step is the real one.
                var delta = yaw - last
                while delta > .pi { delta -= 2 * .pi }
                while delta < -.pi { delta += 2 * .pi }
                // Below this the phone is being held, not turned. Counting the
                // noise would fill the ring while standing still.
                if abs(delta) > Metric.yawNoiseFloor { sweptRadians += abs(delta) }
            }
            lastYaw = yaw
        }
        guard hasMotionSamples else {
            return min(max(elapsed / Metric.fallbackSweepSeconds, 0), 1)
        }
        return min(max(sweptRadians / Metric.sweepTargetRadians, 0), 1)
    }

    private func applyScript() {
        let beat = CaptureCoachScript.beat(at: coverage)
        if beat.coaching != coaching { coaching = beat.coaching }
        if beat.pan != pan { pan = beat.pan }
    }

    private func notePlayedThrough() {
        guard mode == .walkthrough, !didPlayThrough else { return }
        didPlayThrough = true
        coverage = 1
        applyScript()
        TremorHaptic.success.play()
    }

    private func resetProgress() {
        elapsed = 0
        coverage = 0
        sweptRadians = 0
        lastYaw = nil
        hasMotionSamples = false
        didPlayThrough = false
        isPaused = false
        coaching = CaptureCoachScript.standby
        pan = .none
    }

    // MARK: Motion

    private func startMotionUpdates() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = Metric.tickInterval
        // Yaw is measured about gravity, which is the axis a person turns
        // around when they sweep a room.
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical)
    }

    private func stopMotionUpdates() {
        guard motion.isDeviceMotionActive else { return }
        motion.stopDeviceMotionUpdates()
    }

    // MARK: Constants

    /// The handful of numbers that describe a sweep. Each carries its reasoning
    /// because none of them can be derived from a design token.
    private enum Metric {
        /// 20 Hz. Fast enough that the ring reads as continuous motion, slow
        /// enough to be free next to a camera preview.
        static let tickInterval: TimeInterval = 1.0 / 20.0
        static let tickNanoseconds: UInt64 = 50_000_000

        /// 315°. A full turn minus the overlap you get back by starting in a
        /// corner — the room is covered before the user is back where they
        /// began, and demanding a true 360° makes the last few degrees feel
        /// like a chore.
        static let sweepTargetRadians: Double = 5.5

        /// 0.23°/tick. Below this the phone is being held rather than turned.
        static let yawNoiseFloor: Double = 0.004

        /// 18 s, the Simulator's stand-in for a sweep. Chosen so that the
        /// screen reaches "adequate" in about the time a real slow lap takes,
        /// and so a screenshot taken at any point looks like a capture in
        /// progress rather than one stuck at zero.
        static let fallbackSweepSeconds: TimeInterval = 18

        /// The ring does not need to close for the room to be usable — the last
        /// tenth is overlap. Matching S-09's philosophy that "done" is a
        /// judgement about sufficiency, not about completeness.
        static let adequateCoverage: Double = 0.90
    }
}
