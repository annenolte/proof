import Foundation
import RealityKit
import simd

// Drives the earthquake in the demo room.
//
// The excitation is not invented for the demo: it comes from the same
// `AccelerogramSynthesizer` the shipping product uses — a Clough–Penzien filtered process
// under a Jennings–Housner–Tsai envelope, scaled so the peak horizontal resultant matches
// the requested intensity's representative PGA. So when an investor asks what the shaking
// is based on, the answer is a real answer.
//
// Forces are applied in the ground frame (see `ApartmentScene`), and the ground's own
// displacement is tracked separately so the camera can be offset by it.

@MainActor
@Observable
final class DemoQuake {

    enum State: Equatable {
        case idle
        case running
        case finished
    }

    private(set) var state: State = .idle
    private(set) var elapsed: Double = 0

    /// Ground displacement, in metres. The camera subtracts this so the room shakes.
    private(set) var groundOffset = SIMD3<Float>.zero
    /// Instantaneous horizontal acceleration, in g — drives the on-screen meter.
    private(set) var currentAccelerationG: Double = 0
    /// The largest horizontal resultant the record has reached so far, in g.
    ///
    /// Taken from the record's own samples rather than from the per-frame reading. The
    /// accelerogram is sampled at 200 Hz and the screen refreshes at 60, so a running max
    /// over the frames simply misses four samples in five — it came back about 79% of the
    /// record's real peak, every time, which is why the picker advertised 0.47 g and the
    /// results sheet reported 0.37 g for the same run. Both numbers were honest; one of
    /// them was answering a different question.
    private(set) var peakAccelerationG: Double = 0
    /// This step's horizontal ground acceleration, m/s². Debris spawned mid-quake is not
    /// in `scene.props`, so it has to be excited from here or it sits inertly on a floor
    /// the rest of the room is shaking around.
    private(set) var currentHorizontal = SIMD3<Float>.zero

    /// Objects that have moved far enough or tilted far enough to count as a failure.
    private(set) var displaced: [Displacement] = []

    struct Displacement: Identifiable, Equatable {
        var id: String { propID }
        let propID: String
        let name: String
        let category: DemoProp.Category
        /// Seconds after onset.
        let time: Double
        let kind: Kind
        /// 0 for the mainshock, n for the n-th aftershock it happened in.
        var shock: Int = 0

        enum Kind: String, Equatable {
            case toppled = "toppled"
            case slid = "slid"
            case broke = "broke"
        }
    }

    /// How long the solver is given to settle before displacement counts as damage.
    ///
    /// This used to be 0.85 s because the whole room went from kinematic to dynamic at
    /// t = 0 and needed most of a second to stop resolving residual contacts. The room now
    /// settles when it is built (`ApartmentScene.freezeSettledPose`), so everything is
    /// already resting on something and the grace only has to cover the switch back to
    /// dynamic. Shortening it matters: at MMI IX the first things off the shelf are gone
    /// well inside a second, and they were being credited to the settle rather than to the
    /// earthquake.
    private static let settleGrace: Double = 0.35

    /// Tilt past which an object counts as toppled — 22°.
    private static let toppleTilt: Double = 0.384
    /// Horizontal travel past which an object counts as having slid.
    private static let slideDistance: Float = 0.12
    /// A drop past which an object has plainly left the surface it was standing on. A
    /// shelf's boards are 470 mm apart and a counter is 920 mm up, so 180 mm cannot be
    /// settling — it is the object no longer being on the thing it was on.
    private static let fallDrop: Float = 0.18

    var intensity: MercalliIntensity = .viii
    /// The site event this run reproduces, when it is one. `nil` for a plain intensity run.
    private(set) var event: DemoSite.Event?
    /// Where this run's shaking came from, in a sentence: the station and scale for a real
    /// recording, or a plain statement that it was generated. Shown under the results.
    private(set) var provenance: String = ""
    /// True when the room is being shaken by an actual seismometer record.
    private(set) var isRecorded = false
    private(set) var motion: GroundMotion?

    /// 0 while the mainshock is the latest run; n after the n-th aftershock.
    private(set) var shock = 0

    /// What the aftershocks are sized from: the mainshock's peak at the site, its magnitude
    /// when it is a known event, and the soil it was run on. Cleared when the room is reset.
    private var mainshock: (pgaInG: Double, magnitude: Double?, soil: SoilClass)?

    /// "Intensity VIII", "M6.9 Greenville fault · Intensity VIII" for a site event, or
    /// "Aftershock 1 · M5.7 · Intensity VII" after the mainshock.
    var title: String {
        let level = "Intensity \(intensity.roman)"
        if shock > 0 {
            let magnitude = mainshock?.magnitude.map {
                String(format: " · M%.1f", $0 - Self.aftershockMagnitudeDrop(number: shock))
            } ?? ""
            return "Aftershock \(shock)\(magnitude) · \(level)"
        }
        guard let event else { return level }
        return "\(event.title) · \(level)"
    }

    // MARK: - Aftershocks
    //
    // Båth's law (Båth 1965): the largest aftershock is typically 1.2 magnitude units below
    // its mainshock. With a Gutenberg–Richter b-value of 1, the n-th largest is a further
    // log₁₀(n) below that. The magnitude drop becomes a drop in shaking through the app's
    // own ground-motion model (`IntensityScale.pgaInG`, Boore–Joyner–Fumal 1997), at the
    // same fault distance — so no new physics is introduced here, only a smaller earthquake
    // on the same fault, hitting a room that has already been shaken once.

    static let bathDrop = 1.2

    /// How many magnitude units the n-th aftershock sits below its mainshock.
    static func aftershockMagnitudeDrop(number n: Int) -> Double {
        bathDrop + log10(Double(max(n, 1)))
    }

    /// The n-th aftershock's peak ground acceleration as a fraction of the mainshock's. The
    /// model is log-linear in magnitude, so the ratio is the same at any distance and soil;
    /// the reference values below only pick a point on it.
    static func aftershockPGAFactor(number n: Int) -> Double {
        let reference = 6.5
        let drop = aftershockMagnitudeDrop(number: n)
        return IntensityScale.pgaInG(magnitude: reference - drop, distanceKm: 10, soil: .firm)
            / IntensityScale.pgaInG(magnitude: reference, distanceKm: 10, soil: .firm)
    }

    /// The aftershock the results sheet can offer next, or `nil` while shaking or when
    /// there has been no mainshock since the room was last reset.
    var nextAftershock: (number: Int, magnitude: Double?, pgaInG: Double)? {
        guard state == .finished, let mainshock else { return nil }
        let n = shock + 1
        return (n,
                mainshock.magnitude.map { $0 - Self.aftershockMagnitudeDrop(number: n) },
                mainshock.pgaInG * Self.aftershockPGAFactor(number: n))
    }

    /// Shakes the room again without putting anything back. What already moved is the
    /// starting point, which is the whole point: a bookcase that walked toward the edge in
    /// the mainshock is closer to going over in this one.
    func startAftershock(scene: ApartmentScene) {
        guard let next = nextAftershock, let mainshock else { return }
        shock = next.number
        let motion = Self.synthesize(
            targetPGAInG: next.pgaInG, soil: mainshock.soil,
            name: "Aftershock \(next.number)",
            // A smaller earthquake is a shorter one, and it is a different rupture, so it
            // gets its own seed rather than replaying the mainshock's waveform smaller.
            duration: 11, strongMotionDuration: 4,
            seed: 0xDEED_10CE &+ UInt64(next.number))
        provenance = "Generated shaking — a typical aftershock size (Båth's law), "
            + "hitting the room as the earlier shaking left it"
        isRecorded = false
        run(intensity: IntensityScale.bin(forPGAInG: next.pgaInG), motion: motion,
            scene: scene, continuing: true)
    }

    /// Records where each object started so displacement is measured, not guessed.
    private var startTransforms: [String: Transform] = [:]
    private var reported: Set<String> = []

    /// Leaky integrators. A pure double integration of a noisy accelerogram drifts badly
    /// within a couple of seconds; the decay terms high-pass the result, which is both
    /// numerically stable and closer to what a real seismograph's baseline correction
    /// produces.
    private var groundVelocity = SIMD3<Float>.zero

    /// The first record sample not yet folded into `peakAccelerationG`.
    private var nextPeakSample = 0

    var duration: Double { motion?.duration ?? 0 }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(elapsed / duration, 1)
    }

    // MARK: - Control

    func start(intensity: MercalliIntensity, scene: ApartmentScene) {
        event = nil
        shock = 0
        mainshock = (intensity.representativePGAInG, nil, .firm)
        let synthesized = Self.synthesize(
            targetPGAInG: intensity.representativePGAInG, soil: .firm,
            name: "Demo \(intensity.roman)")
        provenance = "Generated shaking at this intensity's typical peak"
        isRecorded = false
        run(intensity: intensity, motion: synthesized, scene: scene)
    }

    /// Shakes the room with a real USGS scenario or historical event at its ShakeMap PGA
    /// for the site.
    ///
    /// A past earthquake with a baked seismometer record plays that record, scaled to the
    /// site's peak — the station's soil is already in it. Anything else (a scenario, 1906,
    /// an event whose only record is too far away) is synthesized on the site's own soil,
    /// with the same seed every intensity run uses, and says so.
    func start(
        event: DemoSite.Event, site: DemoSite, scene: ApartmentScene,
        recording: DemoRecording? = nil
    ) {
        self.event = event
        shock = 0
        mainshock = (event.pgaInG, event.magnitude, site.soil)
        let motion: GroundMotion
        if let recording {
            motion = recording.groundMotion(scaledToPGAInG: event.pgaInG, name: event.title)
            provenance = recording.provenance(scale: recording.scale(toPGAInG: event.pgaInG))
            isRecorded = true
        } else {
            motion = Self.synthesize(targetPGAInG: event.pgaInG, soil: site.soil, name: event.title)
            provenance = event.kind == .scenario
                ? "Generated shaking — this earthquake has not happened"
                : "Generated shaking — no usable recording from near here"
            isRecorded = false
        }
        run(intensity: event.intensity, motion: motion, scene: scene)
    }

    private static func synthesize(
        targetPGAInG: Double, soil: SoilClass, name: String,
        duration: Double = 16, strongMotionDuration: Double = 7, seed: UInt64 = 0xDEED_10CE
    ) -> GroundMotion {
        let synthesizer = AccelerogramSynthesizer()
        // A demo has to hold attention, so the record is shorter than the 30 s default
        // while keeping the full strong-motion plateau.
        let parameters = AccelerogramSynthesizer.Parameters(
            targetPGAInG: targetPGAInG,
            soil: soil,
            duration: duration,
            strongMotionDuration: strongMotionDuration,
            dt: 0.005,
            seed: seed
        )
        return synthesizer.generate(parameters, name: name)
    }

    /// `continuing` keeps what earlier shocks displaced, so an aftershock's results add to
    /// the mainshock's instead of replacing them.
    private func run(
        intensity: MercalliIntensity, motion: GroundMotion, scene: ApartmentScene,
        continuing: Bool = false
    ) {
        self.intensity = intensity
        self.motion = motion

        elapsed = 0
        groundOffset = .zero
        groundVelocity = .zero
        currentAccelerationG = 0
        peakAccelerationG = 0
        nextPeakSample = 0
        if !continuing {
            displaced.removeAll()
            reported.removeAll()
        }

        startTransforms = scene.props.reduce(into: [:]) { result, entry in
            if entry.value.isMovable { result[entry.key] = entry.value.entity.transform }
        }

        scene.setPhysicsActive(true)
        state = .running
    }

    func stop(scene: ApartmentScene) {
        state = .idle
        elapsed = 0
        groundOffset = .zero
        groundVelocity = .zero
        currentAccelerationG = 0
        scene.setPhysicsActive(false)
        scene.reset()
        displaced.removeAll()
        reported.removeAll()
        // The room is back as it was built, so there is no mainshock left to follow.
        shock = 0
        mainshock = nil
    }

    // MARK: - Per-frame

    func step(deltaTime: Double, scene: ApartmentScene) {
        guard state == .running, let motion else { return }

        let dt = min(deltaTime, 1.0 / 30.0)   // a long frame must not launch the furniture
        elapsed += dt

        if elapsed >= motion.duration {
            finish(scene: scene)
            return
        }

        let a = motion.acceleration(at: elapsed)
        let horizontal = SIMD3<Float>(Float(a.x), 0, Float(a.z))
        currentHorizontal = horizontal

        currentAccelerationG = (a.x * a.x + a.z * a.z).squareRoot() / 9.81
        // Every record sample the playhead has passed since the last frame, so the peak is
        // the record's peak rather than the fastest of the frames that happened to land on
        // one. `nextPeakSample` never rewinds, so no sample is counted twice.
        let lastSample = min(Int(elapsed / motion.dt), motion.sampleCount - 1)
        if lastSample >= nextPeakSample {
            for index in nextPeakSample...lastSample {
                peakAccelerationG = max(
                    peakAccelerationG, motion.horizontalMagnitude(at: index) / 9.81)
            }
            nextPeakSample = lastSample + 1
        }

        scene.setVerticalAcceleration(Float(a.y))
        scene.applyHorizontalAcceleration(horizontal)

        // Ground displacement for the camera, high-passed to keep it centred.
        groundVelocity += horizontal * Float(dt)
        groundVelocity *= 0.986
        groundOffset += groundVelocity * Float(dt)
        groundOffset *= 0.975

        detectFailures(scene: scene)
    }

    private func finish(scene: ApartmentScene) {
        state = .finished
        currentAccelerationG = 0
        currentHorizontal = .zero
        groundVelocity = .zero
        // Let the room settle rather than freezing objects mid-fall.
        groundOffset = .zero
    }

    /// An object counts as failed when it has rotated more than 22° off vertical, fallen off
    /// whatever it was standing on, or travelled more than 12 cm from where it was placed.
    /// The tilt and travel thresholds are the same ones the product's display contract
    /// uses, so the demo tells the same story the report would.
    ///
    /// The fall test is the one that is not in the product, and it is here because most of
    /// this room's loose objects are on shelves, counters and an island rather than on the
    /// floor. A mug swept off the counter can land upright and within 12 cm of where it
    /// started, which under the two original tests is *no event at all* — the single
    /// biggest thing an earthquake does to a kitchen, reported as nothing. An object that
    /// has dropped 18 cm is off its support, and being off its support is a failure
    /// regardless of what attitude it happens to have landed in.
    private func detectFailures(scene: ApartmentScene) {
        // Ignore the first moments. Switching the loose objects back to dynamic lets the
        // solver resolve whatever residual contact each one has, and a prop that settles
        // two millimetres is not an earthquake casualty. Reporting "slid at 0.0 s" for the
        // built-in appliances was exactly this artefact.
        guard elapsed > Self.settleGrace else { return }

        for (id, prop) in scene.props where prop.isMovable {
            guard let start = startTransforms[id] else { continue }
            // Something reported in an earlier shock is only looked at again if it merely
            // slid then: going over in the aftershock is new information, sliding again is
            // not.
            let earlier = displaced.firstIndex { $0.propID == id }
            if reported.contains(id) {
                guard let earlier, displaced[earlier].kind == .slid, displaced[earlier].shock < shock
                else { continue }
            }
            let now = prop.entity.transform

            let up = now.rotation.act(SIMD3<Float>(0, 1, 0))
            let tilt = acos(min(max(up.y, -1), 1))

            let delta = now.translation - start.translation
            let travel = simd_length(SIMD2(delta.x, delta.z))

            let kind: Displacement.Kind?
            if Double(tilt) > Self.toppleTilt || -delta.y > Self.fallDrop {
                kind = .toppled
            } else if travel > Self.slideDistance {
                kind = .slid
            } else {
                kind = nil
            }

            guard let kind else { continue }
            let entry = Displacement(
                propID: id, name: prop.name, category: prop.category,
                time: elapsed, kind: kind, shock: shock
            )
            if reported.contains(id) {
                guard kind == .toppled, let earlier else { continue }
                displaced[earlier] = entry
            } else {
                reported.insert(id)
                displaced.append(entry)
            }
        }
    }

    /// Recorded by `BreakageSystem` when a prop's fracture threshold is exceeded. A break
    /// supersedes anything else that object might have been about to be reported for —
    /// "the wine glass slid" is not the interesting fact once it is in pieces.
    func recordBreak(propID: String, name: String, category: DemoProp.Category) {
        guard state == .running else { return }
        let entry = Displacement(
            propID: propID, name: name, category: category,
            time: elapsed, kind: .broke, shock: shock
        )
        // Objects usually slide before they fall, so most breakages have already been
        // reported once as `slid`. Replace that entry rather than skipping the break —
        // "the wine glass slid" is the wrong last word on an object that is now in pieces.
        if let existing = displaced.firstIndex(where: { $0.propID == propID }) {
            displaced[existing] = entry
        } else {
            displaced.append(entry)
        }
        reported.insert(propID)
    }

    // MARK: - Reporting

    var toppledCount: Int { displaced.filter { $0.kind == .toppled }.count }
    var slidCount: Int { displaced.filter { $0.kind == .slid }.count }
    var brokeCount: Int { displaced.filter { $0.kind == .broke }.count }

    /// The headline the results card shows. Breakage leads when there is any, because it
    /// is the outcome that is not recoverable by standing something back up.
    var summary: String {
        guard state == .finished else { return "" }
        if shock > 0 {
            // After an aftershock the headline is what *it* did; the room's running total
            // is the list underneath, which keeps every shock's entries.
            let added = displaced.filter { $0.shock == shock }
            if added.isEmpty { return "The aftershock moved nothing more." }
            return "The aftershock added: " + Self.describe(
                broke: added.filter { $0.kind == .broke }.count,
                toppled: added.filter { $0.kind == .toppled }.count,
                slid: added.filter { $0.kind == .slid }.count)
        }
        if displaced.isEmpty { return "Nothing moved." }
        return Self.describe(broke: brokeCount, toppled: toppledCount, slid: slidCount)
    }

    /// "3 objects broke, 5 toppled, 17 shifted." — or "2 objects shifted. Nothing toppled."
    static func describe(broke: Int, toppled: Int, slid: Int) -> String {
        func count(_ n: Int) -> String { "\(n) object\(n == 1 ? "" : "s")" }
        var clauses: [String] = []
        if broke > 0 { clauses.append("\(count(broke)) broke") }
        if toppled > 0 {
            clauses.append(clauses.isEmpty ? "\(count(toppled)) toppled" : "\(toppled) toppled")
        }
        if slid > 0 {
            clauses.append(clauses.isEmpty ? "\(count(slid)) shifted" : "\(slid) shifted")
        }

        // The reassuring half of the sentence is worth keeping when there is one: a quake
        // that only moved things is a different result from one that destroyed them.
        if clauses.count == 1, broke == 0, toppled == 0 {
            return "\(clauses[0]). Nothing toppled."
        }
        return clauses.joined(separator: ", ") + "."
    }
}
