import AVFoundation
import Foundation

// Sound for the demo earthquake.
//
// Every sample is synthesised at runtime. Nothing is downloaded and no audio file ships
// with the app — partly because we have no licensed assets, and mostly because the one
// sound that has to be right is the rumble, and the rumble has to track the actual
// accelerogram. A looped recording cannot swell and fade with `DemoQuake`'s output; a
// generated one can, by driving the gain of a periodic low band directly from the
// instantaneous ground acceleration.
//
// Construction:
//   • Rumble — a bed of partials between 20 and 80 Hz whose frequencies are all exact
//     multiples of 1/loopLength, so the buffer loops with no seam at all. Gain follows
//     the quake.
//   • One-shots — short decaying buffers built per event kind, four pitch variants each,
//     selected by a hash of the prop id so the same glass always breaks the same way and
//     two glasses never sound identical.
//
// The session category is `.ambient`, so the silent switch silences the demo, which is
// what anyone flicking it in a meeting expects. `isMuted` is the in-app toggle.

@MainActor
final class DemoAudio {

    /// One cue per *material*, not one per event class.
    ///
    /// A wine glass, a wine bottle and a dropped plate are three genuinely different
    /// sounds, and playing one "break" sample for all three is the fastest way to make a
    /// demo feel canned. Each is built from the same three ingredients in different
    /// proportions — a wideband crack, a set of resonant modes, and a scatter of landings
    /// — because that is what the three objects physically differ in: wall thickness sets
    /// the modal frequencies, and how many pieces it goes into sets the scatter.
    ///
    /// `PhysicalMaterial.breakCue` decides which one an object gets, so the sound and the
    /// shard count are chosen from the same authored fact.
    enum Cue: CaseIterable {
        /// Thin stemware: highest modes, longest ringing tail, densest scatter.
        case stemwareShatter
        /// Container glass — a bottle, the hurricane vessel. Thicker walls, so lower modes
        /// and a blunter crack; fewer, heavier pieces landing.
        case glassShatter
        /// Glazed stoneware. One flat clack and a few low partials. It does not ring.
        case ceramicBreak
        /// Vitrified porcelain. Between the two: a ceramic clack with a real note in it,
        /// which is exactly what a dropped teacup does.
        case porcelainBreak
        /// A heavy object landing without breaking.
        case thud
        /// The structure working.
        case creak
    }

    /// In-app mute. The silent switch is handled separately by the session category.
    var isMuted: Bool = false {
        didSet { engine.mainMixerNode.outputVolume = isMuted ? 0 : 1 }
    }

    private let engine = AVAudioEngine()
    private let rumblePlayer = AVAudioPlayerNode()
    /// One-shots round-robin across a small pool so overlapping breaks do not cut
    /// each other off.
    private let oneShotPlayers = (0..<8).map { _ in AVAudioPlayerNode() }
    private var nextPlayer = 0

    private var format: AVAudioFormat?
    private var rumbleBuffer: AVAudioPCMBuffer?
    private var cueBuffers: [Cue: [AVAudioPCMBuffer]] = [:]
    private var isPrepared = false
    private var isRunning = false

    /// Smoothed rumble gain. The raw accelerogram is noisy at frame rate and stepping the
    /// gain from it directly produces audible zipper artefacts.
    private var rumbleGain: Float = 0

    private static let loopLength: Double = 4.0

    // MARK: - Lifecycle

    /// Builds the buffers and starts the engine. Idempotent, and safe to fail — if audio
    /// is unavailable for any reason the demo simply runs silent.
    func start() {
        prepare()
        guard isPrepared, !isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            try engine.start()
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    func stop() {
        guard isRunning else { return }
        stopRumble()
        engine.stop()
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func prepare() {
        guard !isPrepared else { return }

        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        // A stopped engine can report 0 Hz; 48 kHz is the simulator and device default.
        let rate = sampleRate > 0 ? sampleRate : 48_000
        guard let mono = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false
        ) else { return }
        format = mono

        engine.attach(rumblePlayer)
        engine.connect(rumblePlayer, to: engine.mainMixerNode, format: mono)
        for player in oneShotPlayers {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: mono)
        }

        rumbleBuffer = Synth.rumble(format: mono, seconds: Self.loopLength)
        for cue in Cue.allCases {
            cueBuffers[cue] = (0..<4).compactMap { Synth.cue(cue, variant: $0, format: mono) }
        }
        engine.mainMixerNode.outputVolume = isMuted ? 0 : 1
        isPrepared = true
    }

    // MARK: - Rumble

    func startRumble() {
        start()
        guard isRunning, let buffer = rumbleBuffer, !rumblePlayer.isPlaying else { return }
        rumbleGain = 0
        rumblePlayer.volume = 0
        rumblePlayer.scheduleBuffer(buffer, at: nil, options: [.loops])
        rumblePlayer.play()
    }

    func stopRumble() {
        guard rumblePlayer.isPlaying else { return }
        rumblePlayer.stop()
        rumbleGain = 0
    }

    /// Drives the rumble from the accelerogram. `g` is the instantaneous horizontal
    /// resultant in g, straight off `DemoQuake.currentAccelerationG`.
    func setGroundAcceleration(_ g: Double, deltaTime: Double) {
        guard isRunning, rumblePlayer.isPlaying else { return }
        // A square root rather than a linear map: perceived loudness against ground
        // acceleration is compressive, and a linear map leaves the low-intensity
        // intensities inaudible while MMI IX clips.
        let target = Float(min(max(g, 0), 1.2).squareRoot() * 0.92)
        // ~90 ms time constant, so the bed breathes with the envelope rather than
        // chattering at frame rate.
        let k = Float(min(deltaTime / 0.09, 1))
        rumbleGain += (target - rumbleGain) * k
        rumblePlayer.volume = rumbleGain
    }

    // MARK: - One-shots

    /// Plays a cue, varied deterministically by `seed` so the demo is identical every run
    /// but no two objects sound the same.
    func play(_ cue: Cue, seed: String, gain: Float = 1) {
        start()
        guard isRunning, !isMuted, let variants = cueBuffers[cue], !variants.isEmpty else { return }
        let hash = Seeded.hash(seed)
        let buffer = variants[Int(hash % UInt64(variants.count))]

        let player = oneShotPlayers[nextPlayer]
        nextPlayer = (nextPlayer + 1) % oneShotPlayers.count
        // A last touch of level variation on top of the pitch variants, ±12%.
        let jitter = 0.88 + Float((hash >> 8) % 24) / 100
        player.volume = min(max(gain * jitter, 0), 1)
        player.scheduleBuffer(buffer, at: nil, options: [.interrupts])
        if !player.isPlaying { player.play() }
    }
}

// MARK: - Deterministic seeding

/// A fixed hash. `String.hashValue` is salted per process, so using it here would make the
/// demo sound different on every launch — the one thing the brief rules out.
enum Seeded {
    static func hash(_ string: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325          // FNV-1a 64
        for byte in string.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x1000_0000_01b3
        }
        return h
    }

    /// SplitMix64. Small, fast, and reproducible, which is the whole requirement.
    struct Generator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        init(_ string: String) { state = Seeded.hash(string) }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        /// Uniform in [0, 1).
        mutating func unit() -> Float {
            Float(next() >> 40) / Float(1 << 24)
        }

        /// Uniform in [low, high).
        mutating func range(_ low: Float, _ high: Float) -> Float {
            low + (high - low) * unit()
        }

        /// Uniform in [-1, 1).
        mutating func signed() -> Float { unit() * 2 - 1 }
    }
}

// MARK: - Synthesis

private enum Synth {

    /// The quake bed: a seamless low-band loop.
    ///
    /// Filtered white noise would be the obvious construction, but a noise loop has a
    /// discontinuity at the splice that reads as a click once a second. Building the band
    /// additively from partials at exact multiples of 1/seconds makes the buffer perfectly
    /// periodic, so it loops forever with no seam and no crossfade.
    static func rumble(format: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(rate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames

        for i in 0..<Int(frames) { out[i] = 0 }

        var rng = Seeded.Generator(seed: 0xDEED_10CE)   // the quake's own seed
        let fundamental = 1.0 / seconds
        let low = Int((20.0 / fundamental).rounded())
        let high = Int((80.0 / fundamental).rounded())
        // Enough partials to fill the band without the cost of one per bin.
        let spacing = max((high - low) / 64, 1)

        for k in Swift.stride(from: low, through: high, by: spacing) {
            let frequency = Double(k) * fundamental
            // Pink-ish tilt: a flat band at these frequencies sounds like a hum, a 1/f
            // tilt sounds like a building.
            let amplitude = Double(rng.range(0.6, 1.0)) * (28.0 / frequency)
            let phase = Double(rng.unit()) * 2 * .pi
            let step = 2 * .pi * frequency / rate
            for i in 0..<Int(frames) {
                out[i] += Float(amplitude * sin(step * Double(i) + phase))
            }
        }

        // A slow, also-periodic swell so a held rumble does not sit perfectly still.
        for i in 0..<Int(frames) {
            let t = Double(i) / rate
            let wobble = 1 + 0.18 * sin(2 * .pi * t / seconds) + 0.10 * sin(6 * .pi * t / seconds)
            out[i] *= Float(wobble)
        }

        normalise(out, count: Int(frames), to: 0.85)
        return buffer
    }

    static func cue(_ cue: DemoAudio.Cue, variant: Int, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        var rng = Seeded.Generator(seed: UInt64(variant) &+ Seeded.hash(label(cue)))
        // Each variant is detuned as a whole, which is what makes repeats read as
        // different objects rather than as the same sample twice.
        let detune = 1 + Double(rng.range(-0.14, 0.14))

        switch cue {
        case .stemwareShatter:
            return fracture(.stemware, format: format, detune: detune, rng: &rng)
        case .glassShatter:
            return fracture(.container, format: format, detune: detune, rng: &rng)
        case .ceramicBreak:
            return fracture(.stoneware, format: format, detune: detune, rng: &rng)
        case .porcelainBreak:
            return fracture(.porcelain, format: format, detune: detune, rng: &rng)
        case .thud:
            return thud(format: format, detune: detune, rng: &rng)
        case .creak:
            return creak(format: format, detune: detune, rng: &rng)
        }
    }

    private static func label(_ cue: DemoAudio.Cue) -> String {
        switch cue {
        case .stemwareShatter: return "stemware"
        case .glassShatter: return "glass"
        case .ceramicBreak: return "ceramic"
        case .porcelainBreak: return "porcelain"
        case .thud: return "thud"
        case .creak: return "creak"
        }
    }

    // MARK: Cues

    /// The shape of one brittle failure, as four numbers a material can differ in.
    ///
    /// Every break is the same three events in sequence — the crack as the body fails, the
    /// ringing of the pieces that are still big enough to have modes, and the scatter as
    /// they land. What separates a wine glass from a dinner plate is not the ingredients,
    /// it is the proportions: thin walls ring high and long, thick ones barely ring at all,
    /// and something that goes into thirty pieces keeps arriving for half a second while
    /// something that goes into eight is over almost at once.
    private struct Fracture {
        /// Total length of the cue, seconds.
        let seconds: Double
        /// Time constant of the opening noise burst. Short and bright is a crack; longer
        /// and darker is a crunch.
        let crackDecay: Double
        /// How much of the burst survives the one-pole filter. High keeps it hissy and
        /// glassy; low makes it a thud with grit in it.
        let brightness: Float
        /// Range of the ringing modes, Hz. This is wall thickness, heard.
        let modes: ClosedRange<Double>
        /// How many modes ring, and how long they hold.
        let modeCount: Int
        let modeDecay: ClosedRange<Double>
        /// How many individual pieces are heard landing, and over what window.
        let scatterCount: Int
        let scatterWindow: Double

        /// Thin blown stemware: the highest modes in the room and a long, dense shower.
        static let stemware = Fracture(
            seconds: 0.62, crackDecay: 0.028, brightness: 0.90,
            modes: 3200...9200, modeCount: 9, modeDecay: 0.08...0.30,
            scatterCount: 22, scatterWindow: 0.42
        )
        /// Container glass. Thicker walls put the modes an octave down and the pieces are
        /// heavier, so fewer of them land and they land sooner.
        static let container = Fracture(
            seconds: 0.48, crackDecay: 0.040, brightness: 0.78,
            modes: 1500...5200, modeCount: 6, modeDecay: 0.05...0.20,
            scatterCount: 13, scatterWindow: 0.30
        )
        /// Vitrified porcelain: a ceramic clack that still has a note in it.
        static let porcelain = Fracture(
            seconds: 0.34, crackDecay: 0.026, brightness: 0.62,
            modes: 1100...3400, modeCount: 5, modeDecay: 0.04...0.14,
            scatterCount: 9, scatterWindow: 0.20
        )
        /// Glazed stoneware. Almost no ring at all — a plate is a damped plate.
        static let stoneware = Fracture(
            seconds: 0.28, crackDecay: 0.022, brightness: 0.34,
            modes: 520...1900, modeCount: 4, modeDecay: 0.025...0.08,
            scatterCount: 6, scatterWindow: 0.15
        )
    }

    private static func fracture(
        _ shape: Fracture, format: AVAudioFormat, detune: Double, rng: inout Seeded.Generator
    ) -> AVAudioPCMBuffer? {
        make(format: format, seconds: shape.seconds) { out, count, rate in
            // The crack. A one-pole filter on white noise, with the pole position doing
            // duty as the material's brightness: near 1 leaves the hiss, near 0 leaves a
            // dull knock.
            var filtered: Float = 0
            for i in 0..<count {
                let t = Double(i) / rate
                let noise = rng.signed()
                filtered = filtered * (1 - shape.brightness) + noise * shape.brightness
                out[i] = filtered * Float(exp(-t / shape.crackDecay))
            }

            // The modes of the fragments that are still big enough to have any.
            for _ in 0..<shape.modeCount {
                let frequency = Double(rng.range(
                    Float(shape.modes.lowerBound), Float(shape.modes.upperBound)
                )) * detune
                let onset = Double(rng.range(0, Float(shape.scatterWindow * 0.4)))
                let decay = Double(rng.range(
                    Float(shape.modeDecay.lowerBound), Float(shape.modeDecay.upperBound)
                ))
                let level = Double(rng.range(0.10, 0.30))
                let step = 2 * .pi * frequency / rate
                let first = Int(onset * rate)
                guard first < count else { continue }
                for i in first..<count {
                    let t = Double(i - first) / rate
                    out[i] += Float(level * exp(-t / decay) * sin(step * Double(i - first)))
                }
            }

            // The scatter: each piece arriving as its own tiny filtered tick. This is the
            // part that carries the shard count, and it is why stemware sounds like more
            // glass than a bottle does even though both are glass.
            for _ in 0..<shape.scatterCount {
                let onset = Double(rng.range(0.02, Float(shape.scatterWindow)))
                let first = Int(onset * rate)
                guard first < count else { continue }
                let decay = Double(rng.range(0.004, 0.018))
                let level = Double(rng.range(0.05, 0.20))
                let frequency = Double(rng.range(
                    Float(shape.modes.lowerBound) * 1.2, Float(shape.modes.upperBound)
                )) * detune
                let step = 2 * .pi * frequency / rate
                for i in first..<count {
                    let t = Double(i - first) / rate
                    guard t < decay * 8 else { break }
                    out[i] += Float(level * exp(-t / decay) * sin(step * Double(i - first)))
                }
            }
        }
    }

    /// A heavy object landing: a damped low sine under a very short noise transient.
    private static func thud(
        format: AVAudioFormat, detune: Double, rng: inout Seeded.Generator
    ) -> AVAudioPCMBuffer? {
        let body = Double(rng.range(52, 88)) * detune
        return make(format: format, seconds: 0.34) { out, count, rate in
            let step = 2 * .pi * body / rate
            var lowpass: Float = 0
            for i in 0..<count {
                let t = Double(i) / rate
                // The body drops a little in pitch as it decays, which is what a real
                // impact does and what stops it sounding like a kick drum.
                let sweep = 1 - 0.22 * min(t / 0.18, 1)
                lowpass += (rng.signed() - lowpass) * 0.22
                out[i] = Float(0.75 * exp(-t / 0.11) * sin(step * sweep * Double(i)))
                       + lowpass * Float(0.5 * exp(-t / 0.014))
            }
        }
    }

    /// The structure working. Sparse and quiet by design — one of these per quake is
    /// atmosphere, three is a haunted house.
    private static func creak(
        format: AVAudioFormat, detune: Double, rng: inout Seeded.Generator
    ) -> AVAudioPCMBuffer? {
        let centre = Double(rng.range(300, 820)) * detune
        return make(format: format, seconds: 0.85) { out, count, rate in
            var bandpass: Float = 0, integrator: Float = 0
            // A two-pole state-variable filter, swept slowly: the pitch drift is the
            // creak. Stick-slip, approximated.
            for i in 0..<count {
                let t = Double(i) / rate
                let f = centre * (1 + 0.35 * sin(2 * .pi * 0.9 * t))
                let q: Float = 0.06
                let g = Float(2 * sin(.pi * f / rate))
                let input = rng.signed() * 0.5
                let highpass = input - integrator - q * bandpass
                bandpass += g * highpass
                integrator += g * bandpass
                // Irregular grip-and-slip envelope, not a smooth swell.
                let grip = Float(max(0, sin(2 * .pi * 3.3 * t)) * exp(-t / 0.42))
                out[i] = bandpass * grip * 0.5
            }
        }
    }

    // MARK: Plumbing

    private static func make(
        format: AVAudioFormat, seconds: Double,
        fill: (UnsafeMutablePointer<Float>, Int, Double) -> Void
    ) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(rate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        let count = Int(frames)
        for i in 0..<count { out[i] = 0 }
        fill(out, count, rate)

        // A 3 ms fade at each end. Every cue already decays to near zero, but a buffer
        // that starts on a non-zero sample clicks.
        let fade = min(Int(rate * 0.003), count / 2)
        for i in 0..<fade {
            let k = Float(i) / Float(fade)
            out[i] *= k
            out[count - 1 - i] *= k
        }
        normalise(out, count: count, to: 0.9)
        return buffer
    }

    private static func normalise(_ out: UnsafeMutablePointer<Float>, count: Int, to peak: Float) {
        var maximum: Float = 0
        for i in 0..<count { maximum = max(maximum, abs(out[i])) }
        guard maximum > 1e-6 else { return }
        let scale = peak / maximum
        for i in 0..<count { out[i] *= scale }
    }
}
