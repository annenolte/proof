//
//  PullTest.swift
//  proof — Features / Constellation
//
//  "What if a child pulls on it?" — the optional, illustrative physics of CLAUDE.md §8 and
//  Stage 10.
//
//  The rules it keeps:
//
//  * **Illustrative, not a prediction.** It is a real-time rigid-body solver acting on the
//    model's own colliders with assumed masses and an assumed pull. It looks convincing
//    whether or not it is right, so every screen it appears on says so, and lists the
//    assumptions it ran with.
//  * **It never changes a flag.** Tip-over flags come from the geometry engine. Nothing
//    here feeds back into `SafetyAnalysis`, the checklist or the export.
//  * **The anchored rerun is the point.** The same pull, with the object held fixed, is
//    what turns a spectacle into a reason to buy a wall strap.
//

import Foundation
import Observation
import RealityKit
import simd

@MainActor
@Observable
final class PullTest {

    enum Phase: Equatable {
        case idle
        case running
        case finished(Outcome)
    }

    struct Outcome: Equatable {
        var tipped: Bool
        /// Peak lean of the pulled object from upright, in degrees.
        var peakLean: Double
        var fellNames: [String]
        var brokeNames: [String]
    }

    /// The assumptions a run used, shown beside it.
    struct Assumptions: Equatable {
        var objectName: String
        var massKg: Double
        var pullNewtons: Float
        var pullHeight: Float
        var pullSeconds: Double
        var handSpeed: Float
        var handTravel: Float
        var anchored: Bool
    }

    // Placeholders, labelled as such wherever they appear (CLAUDE.md §3 rule 2).
    //
    // The pull is a *hand*, not a fixed force. A fixed force is independent of what it
    // pushes, so the same 120 N that barely moves a 26 kg shelf throws a 6 kg chair across
    // the room at ~12 m/s. A child's arm cannot do that: it moves at arm speed, over an
    // arm's length, and stops. So the force is capped at `pullNewtons`, but only ever
    // applied while the point being held is slower than `handSpeed` and has travelled less
    // than `handTravel`. Light objects get tugged; tall ones still go over, because once
    // they pass their balance point gravity takes over.
    static let pullNewtons: Float = 120
    static let pullSeconds: Double = 1.0
    static let handSpeed: Float = 0.6
    static let handTravel: Float = 0.40
    static let runSeconds: Double = 4.5
    /// Lean past which an object counts as tipped over.
    static let tippedDegrees: Double = 35
    /// Drop past which a small object counts as having fallen.
    static let fallDrop: Float = 0.25

    private(set) var phase: Phase = .idle
    private(set) var assumptions: Assumptions?
    private(set) var targetID: String?

    var isActive: Bool { phase != .idle }

    @ObservationIgnored private var elapsed: Double = 0
    @ObservationIgnored private var peakLean: Double = 0
    @ObservationIgnored private var direction = SIMD3<Float>(1, 0, 0)
    /// The held point, in the object's own frame, so it travels with the object as it tips.
    @ObservationIgnored private var heldLocal = SIMD3<Float>.zero
    @ObservationIgnored private var heldStart = SIMD3<Float>.zero
    @ObservationIgnored private var heldPrevious = SIMD3<Float>.zero
    @ObservationIgnored private var handReleased = false
    @ObservationIgnored private var restHeights: [String: Float] = [:]
    @ObservationIgnored private var broke: [String] = []
    @ObservationIgnored private var breakage: BreakageSystem?
    @ObservationIgnored private weak var scene: ApartmentScene?

    // MARK: Which objects

    /// Free-standing objects tall enough for a pull to mean something. Built-ins, wall
    /// art and tableware are not offered.
    static func canPull(_ id: String, in scene: ApartmentScene?) -> Bool {
        guard let prop = scene?.props[id], prop.isMovable else { return false }
        let height = prop.localHigh.y - prop.localLow.y
        return height >= 0.5 && prop.mass >= 3
    }

    // MARK: Running

    /// Puts the room back as it was, then pulls the object toward the middle of the room
    /// at a child's reach height for a moment and lets the solver run.
    func start(objectID: String, reachHeight: Float, scene: ApartmentScene, audio: DemoAudio, anchored: Bool) {
        guard let prop = scene.props[objectID], prop.isMovable else { return }
        cleanUp()
        self.scene = scene
        scene.reset()

        // Toward the open floor: from the object to the middle of the apartment.
        let position = prop.restTransform.translation
        let centre = SIMD3<Float>(Plan.width / 2, 0, Plan.length / 2)
        var away = SIMD3<Float>(centre.x - position.x, 0, centre.z - position.z)
        if simd_length(away) < 0.01 { away = SIMD3(1, 0, 0) }
        direction = simd_normalize(away)

        let top = prop.localHigh.y
        let height = min(reachHeight, top * 0.9)

        restHeights = [:]
        for other in scene.props.values where other.isMovable {
            restHeights[other.id] = other.restTransform.translation.y
        }

        audio.start()
        let system = BreakageSystem(scene: scene, audio: audio)
        system.onBreak = { [weak self] event in self?.broke.append(event.name) }
        breakage = system

        scene.setPhysicsActive(true)
        if anchored, var body = prop.entity.components[PhysicsBodyComponent.self] {
            body.mode = .kinematic
            prop.entity.components.set(body)
        }

        let base = prop.entity.position(relativeTo: nil)
        let held = SIMD3<Float>(base.x, height, base.z)
        heldLocal = prop.entity.convert(position: held, from: nil)
        heldStart = held
        heldPrevious = held
        handReleased = false

        assumptions = Assumptions(
            objectName: prop.name, massKg: prop.mass, pullNewtons: Self.pullNewtons,
            pullHeight: height, pullSeconds: Self.pullSeconds,
            handSpeed: Self.handSpeed, handTravel: Self.handTravel, anchored: anchored)
        targetID = objectID
        elapsed = 0
        peakLean = 0
        broke = []
        phase = .running
    }

    /// One physics step. Called from the renderer's simulation tick.
    func step(deltaTime: Double) {
        guard phase == .running, let scene, let id = targetID, let prop = scene.props[id],
              let assumptions else { return }
        elapsed += deltaTime

        if !assumptions.anchored, !handReleased, deltaTime > 0 {
            let held = prop.entity.convert(position: heldLocal, to: nil)
            let speed = simd_dot(held - heldPrevious, direction) / Float(deltaTime)
            let travelled = simd_dot(held - heldStart, direction)
            heldPrevious = held

            if elapsed > Self.pullSeconds || travelled >= assumptions.handTravel {
                handReleased = true          // the arm is fully drawn back; let go
            } else if speed < assumptions.handSpeed {
                // Just enough to bring the held point up to hand speed this step, never
                // more than the cap. Using the whole mass overstates the force needed to
                // rotate a tall object, which errs toward a gentler pull.
                let needed = Float(prop.mass) * (assumptions.handSpeed - speed) / Float(deltaTime)
                let force = min(needed, assumptions.pullNewtons)
                prop.entity.addForce(direction * force, at: held, relativeTo: nil)
            }
        }
        breakage?.update(deltaTime: deltaTime, groundAcceleration: .zero)

        let up = prop.entity.orientation(relativeTo: nil).act(SIMD3<Float>(0, 1, 0))
        let lean = Double(acos(max(-1, min(1, up.y)))) * 180 / .pi
        peakLean = max(peakLean, lean)

        if elapsed >= Self.runSeconds { finish(scene: scene, target: id) }
    }

    private func finish(scene: ApartmentScene, target: String) {
        var fell: [String] = []
        for prop in scene.props.values where prop.isMovable && prop.id != target {
            guard let rest = restHeights[prop.id] else { continue }
            if rest - prop.entity.position(relativeTo: nil).y > Self.fallDrop, prop.entity.isEnabled {
                fell.append(prop.name)
            }
        }
        #if DEBUG
        if let prop = scene.props[target] {
            let moved = prop.entity.position(relativeTo: nil) - prop.restTransform.translation
            print(String(format: "[proof] pull %@: moved %.2f m, peak lean %.0f°, fell %d, broke %d",
                         target, simd_length(SIMD2(moved.x, moved.z)), peakLean, fell.count, broke.count))
        }
        #endif
        // Freeze where everything landed, so the result can be looked at from any angle.
        scene.setPhysicsActive(false)
        phase = .finished(Outcome(
            tipped: peakLean >= Self.tippedDegrees,
            peakLean: peakLean,
            fellNames: fell.sorted(),
            brokeNames: broke))
    }

    /// Puts every object, shard and broken piece back.
    func reset() {
        if let scene {
            scene.reset()
            scene.setPhysicsActive(false)
        }
        cleanUp()
        phase = .idle
        assumptions = nil
        targetID = nil
    }

    private func cleanUp() {
        breakage?.reset()
        breakage?.detach()
        breakage = nil
    }
}
