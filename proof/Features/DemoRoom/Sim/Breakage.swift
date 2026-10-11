import Combine
import Foundation
import RealityKit
import simd
#if canImport(UIKit)
import UIKit
#endif

// Things breaking, during the demo earthquake.
//
// RealityKit has no fracture — no runtime mesh splitting, no Voronoi, no convex
// decomposition. What it does have is a fast rigid-body solver, so breakage here is done
// by **substitution**: when a brittle prop takes an impulse above the threshold its
// authored material sets, the intact model is switched off and a spray of convex shards is
// spawned in its place *in the same frame*, inheriting the object's velocity and a share
// of the impact energy.
//
// The effect is convincing for the same reason a stunt car is: nobody watches the object
// that broke, they watch the pieces. So the pieces get the budget — real convex geometry
// sized from the prop's own bounds, radiating from the point that was struck, under a
// fracture-surface material, with a white flash and a puff of glitter over the instant of
// substitution so the switch itself is never seen.
//
// ## Two ways a break can fire, and why there are two
//
// The obvious trigger is `CollisionEvents`, and it is the one that carries a real contact
// point. It is not sufficient on its own:
//
//   • `Began` alone misses almost everything. A glass toppling on the counter never breaks
//     contact with it, so the solver reports one `Began` when physics turns on — inside the
//     settle grace — and nothing afterwards, however hard the glass then slams down. Hence
//     `Updated`, which fires every frame of a persisting contact.
//   • The impulse the event carries is in undocumented units and is zero for a good many
//     contacts, so it cannot be compared against a threshold in newton-seconds with a
//     straight face.
//
// So the second trigger is the object's **own change of velocity**, finite-differenced
// from its world transform frame to frame. A free body that loses 0.9 m/s in a sixtieth of
// a second has been hit by something: that is 54 m/s², and the strongest excitation this
// demo applies is 0.65 g. Nothing else in the scene can produce it. This path needs no
// event, no contact report and no `PhysicsMotionComponent` — it reads the transform, which
// is always true — and it is what guarantees the feature is not dead code.
//
// Both paths land in the same `shatter`, so the sound and the picture cannot desync: they
// are one call.
//
// ## Budget
//
// **`shardBudget` = 240 live shards, globally.** That is the number that matters on a
// phone, and it is chosen against the worst realistic case: MMI IX in this room breaks on
// the order of eight objects, and eight objects at the 40-shard ceiling would be 320. When
// a break would exceed the budget it is given *fewer, larger* pieces rather than being
// dropped — the shard size is `∝ 1/∛count`, so halving the count makes each piece 26%
// bigger and the object still visibly comes apart. Only if even the six-piece minimum will
// not fit are the oldest shards on the floor evicted to make room.
//
// Shards themselves never despawn. They are the evidence the analysis screen talks about,
// so they stay on the floor until the room is reset; after `shardFreeze` seconds each one
// is switched to a static body, which takes it out of the solver entirely and makes the
// steady-state cost of a floor full of glass close to nothing.
//
// Two rules keep it honest:
//   • Only materials whose authored `failure` is `.glass` or `.ceramic` can break. A sofa
//     cannot shatter no matter how hard it lands, because upholstery has no failure mode.
//   • The impulse is measured, not scripted. Nothing is on a timer and nothing is told in
//     advance which glass is going to go.
//
// Everything is deterministic: shard shapes, velocities and sound variants are all seeded
// from the prop id, so the demo is identical on every run.

@MainActor
final class BreakageSystem {

    struct Event {
        let propID: String
        let name: String
        let category: DemoProp.Category
        let material: PhysicalMaterial
        let impulse: Double
    }

    /// Called when a prop breaks, so the quake can record it for the results sheet.
    var onBreak: ((Event) -> Void)?

    private unowned let scene: ApartmentScene
    private let audio: DemoAudio?

    private var subscriptions: [any Cancellable] = []
    private var broken: Set<String> = []

    // MARK: Debris

    private enum DebrisKind {
        /// A physical fragment. Persists until the room is reset.
        case shard
        /// The puff at the fracture origin.
        case dust
        /// Fine bright specks thrown off the break, integrated ballistically.
        case glitter
        /// The white flash, and the brief light that goes with it.
        case flash
    }

    private struct Debris {
        let entity: Entity
        var age: Double = 0
        /// `.infinity` for shards, which are never removed on a clock.
        let lifetime: Double
        let kind: DebrisKind
        /// Glitter only — it has no rigid body, so it carries its own velocity.
        var velocity: SIMD3<Float> = .zero
        var isFrozen = false
    }
    private var debris: [Debris] = []
    private var liveShards = 0
    /// At most one flash light at a time. Point lights are the expensive kind and two
    /// breaks half a second apart do not need two.
    private var flashLightLive = false

    // MARK: Motion tracking

    /// One entry per brittle, movable prop. Finite-differenced from the world transform,
    /// which is the one thing about a rigid body that is always readable.
    private struct Tracked {
        var position: SIMD3<Float>
        var orientation: simd_quatf
        var linear: SIMD3<Float> = .zero
        var angular: SIMD3<Float> = .zero
        /// Two frames of history are needed before a change of velocity means anything.
        var samples = 0
    }
    private var tracked: [String: Tracked] = [:]

    /// `MaterialAssignment` does string work on the prop's id and name to recognise props
    /// nobody has explicitly listed. That is the right lookup and the wrong thing to run
    /// forty times a frame, so it is resolved once per prop and kept.
    private var materialCache: [String: PhysicalMaterial] = [:]

    private func resolvedMaterial(for prop: ApartmentScene.PropEntity) -> PhysicalMaterial {
        if let cached = materialCache[prop.id] { return cached }
        let resolved = MaterialAssignment.material(
            forPropID: prop.id, name: prop.name, category: prop.category
        )
        materialCache[prop.id] = resolved
        return resolved
    }

    /// Impact sounds are rate-limited. A quake produces dozens of contacts a second and
    /// playing a thud for each one is a wall of noise, not an earthquake.
    private var lastThud: Double = -1
    private var lastCreak: Double = -1
    private var elapsed: Double = 0

    /// The global cap. See the file header for how it was chosen.
    static let shardBudget = 240
    /// Below this an object stops reading as breaking and starts reading as splitting, so
    /// it is the floor the budget is never allowed to push through.
    private static let minimumShards = 6

    /// How long a shard stays a dynamic body before it is frozen where it lies. Long
    /// enough to land and settle — they are damped hard — and short enough that a floor
    /// covered in glass is not still being solved when the results sheet appears.
    private static let shardFreeze: Double = 4.5

    private static let dustLifetime: Double = 0.70
    private static let glitterLifetime: Double = 0.55
    private static let flashLifetime: Double = 0.11

    /// How long into the quake breakage is suppressed, and it must stay in step with
    /// `DemoQuake.settleGrace` — the two answer the same question about the same frames.
    ///
    /// It used to be 0.85 s, when the first thing the quake did was switch a hundred
    /// kinematic bodies to dynamic and let the solver resolve whatever residual overlap
    /// each one had; a glass exploding on frame one because it was authored 3 mm inside a
    /// countertop is an artefact, not a quake. The room now settles once at build time
    /// (`ApartmentScene.freezeSettledPose`), so everything is already resting on its real
    /// support when the shaking starts and there is far less to ignore. Nearly a second of
    /// deliberate blindness at the front of a 16 s record is expensive — the accelerogram's
    /// envelope is already rising there — so it comes down with it.
    private static let settleGrace: Double = 0.35

    /// Shards collide with the room but not with each other. Two hundred fragments
    /// resolving mutual contacts is most of the cost of this effect and none of its look:
    /// at 3 cm across, glass-on-glass contacts are below what anyone can see, and without
    /// this a big break visibly hitches the frame rate.
    private static let shardGroup = CollisionGroup(rawValue: 1 << 12)
    private static let shardFilter = CollisionFilter(
        group: shardGroup, mask: .all.subtracting(shardGroup)
    )

    init(scene: ApartmentScene, audio: DemoAudio?) {
        self.scene = scene
        self.audio = audio
    }

    // MARK: - Lifecycle

    /// Subscribing needs the entity to be in a live `Scene`, which does not happen until
    /// the RealityView has added it. The launch-argument path starts the quake before that,
    /// so this is retried from `update` until it takes.
    private func attachIfNeeded() {
        guard subscriptions.isEmpty, let rkScene = scene.root.scene else { return }
        subscriptions.append(rkScene.subscribe(to: CollisionEvents.Began.self) { [weak self] in
            let event = $0
            MainActor.assumeIsolated {
                self?.handle(
                    event.entityA, event.entityB,
                    at: event.position, direction: event.impulseDirection,
                    reported: event.impulse
                )
            }
        })
        // `Began` alone is not enough, and this is the single thing that made breakage
        // work. A glass toppling on the counter never breaks contact with it, so the
        // solver reports one `Began` when physics turns on — inside the settle grace —
        // and nothing afterwards, however hard the glass then slams down. `Updated` fires
        // for every frame of a persisting contact, which is where the slam actually is.
        subscriptions.append(rkScene.subscribe(to: CollisionEvents.Updated.self) { [weak self] in
            let event = $0
            MainActor.assumeIsolated {
                self?.handle(
                    event.entityA, event.entityB,
                    at: event.position, direction: event.impulseDirection,
                    reported: event.impulse
                )
            }
        })

        primeMotionComponents()
    }

    /// RealityKit only maintains a `PhysicsMotionComponent` on bodies that already have
    /// one; it does not add it for you when a body turns dynamic. Reading velocity off a
    /// prop that never had the component returns nil, which sent every impulse estimate
    /// down its fallback path and is the most likely reason a threshold that is perfectly
    /// reachable on paper never fired. Seeding an empty one at zero costs nothing — the
    /// props are at rest at this point — and gives the solver somewhere to write.
    private func primeMotionComponents() {
        for prop in scene.props.values where prop.isMovable {
            guard prop.entity.components[PhysicsMotionComponent.self] == nil else { continue }
            prop.entity.components.set(PhysicsMotionComponent())
        }
    }

    /// Debris is not in `scene.props`, so `ApartmentScene.applyHorizontalAcceleration`
    /// never reaches it. Without this the shards behave as though the quake stopped the
    /// moment they appeared: they drop, settle, and then sit dead still on a floor the
    /// rest of the room is visibly shaking around.
    func update(deltaTime: Double, groundAcceleration: SIMD3<Float>) {
        attachIfNeeded()
        elapsed += deltaTime

        trackMotion(deltaTime: deltaTime)
        playCreak(groundAcceleration)
        updateDebris(deltaTime: deltaTime, groundAcceleration: groundAcceleration)
    }

    /// Puts the room back: every shard removed, every broken prop visible again.
    func reset() {
        for piece in debris { piece.entity.removeFromParent() }
        debris.removeAll()
        liveShards = 0
        flashLightLive = false
        for id in broken { scene.props[id]?.entity.isEnabled = true }
        broken.removeAll()
        tracked.removeAll()
        elapsed = 0
        lastThud = -1
        lastCreak = -1
    }

    func detach() {
        for subscription in subscriptions { subscription.cancel() }
        subscriptions.removeAll()
    }

    // MARK: - Motion tracking and the deceleration trigger

    /// Differentiates every brittle prop's world transform, and fires a break on any
    /// object that loses more speed in one step than its material can survive.
    ///
    /// This is the trigger that does not depend on the collision system agreeing to report
    /// anything. The comparison is the same one the contact path makes — measured impulse
    /// against `fractureImpulse` — except that here the change in momentum is measured
    /// directly rather than modelled as `m·v·(1 + e)`, so the restitution term is already
    /// in the number and is not applied twice.
    private func trackMotion(deltaTime: Double) {
        guard deltaTime > 1e-4 else { return }
        let dt = Float(deltaTime)

        for (id, prop) in scene.props where prop.isMovable && !broken.contains(id) {
            let material = resolvedMaterial(for: prop)
            guard material.isBrittle else { continue }

            let position = prop.entity.position(relativeTo: nil)
            let orientation = prop.entity.orientation(relativeTo: nil)

            guard var previous = tracked[id] else {
                tracked[id] = Tracked(position: position, orientation: orientation)
                continue
            }

            let linear = (position - previous.position) / dt

            // Angular velocity from the quaternion step. The rim of a falling glass is
            // moving several times faster than its centre, and the rim is what hits the
            // stone, so this term is not optional.
            let delta = orientation * previous.orientation.inverse
            var angle = 2 * acos(min(max(delta.real, -1), 1))
            if angle > .pi { angle -= 2 * .pi }
            let imaginary = delta.imag
            let axisLength = simd_length(imaginary)
            let angular = axisLength > 1e-5
                ? imaginary / axisLength * (angle / dt)
                : SIMD3<Float>.zero

            // Captured before the sample is overwritten: the direction the object was
            // heading in *before* whatever stopped it is where the impact came from, and
            // it is gone the moment `previous` is updated.
            let priorVelocity = previous.linear
            let speedLoss = simd_length(priorVelocity - linear)

            previous.position = position
            previous.orientation = orientation
            previous.linear = linear
            previous.angular = angular
            previous.samples += 1
            tracked[id] = previous

            // Two samples of history before a difference of differences means anything,
            // and the same settle grace the rest of the demo uses: switching a hundred
            // bodies from kinematic to dynamic makes the solver resolve whatever residual
            // overlap each one has, and a glass exploding on the first frame because it
            // was authored 3 mm inside a countertop is an artefact, not a quake.
            guard previous.samples > 2, elapsed > Self.settleGrace else { continue }

            let impulse = prop.mass * Double(speedLoss)
            guard impulse > material.fractureImpulse(forMass: prop.mass) else { continue }

            shatter(
                prop, material: material, impulse: impulse,
                at: impactPoint(for: prop, travelling: priorVelocity)
            )
        }
    }

    /// Where to say the break started, when the trigger was a change of velocity rather
    /// than a reported contact. The object was moving; whatever stopped it was ahead of
    /// it, so the fracture origin is the point on its own collider furthest along the
    /// direction of travel.
    private func impactPoint(
        for prop: ApartmentScene.PropEntity, travelling direction: SIMD3<Float>
    ) -> SIMD3<Float> {
        // The prop's origin is its footprint centre on the floor, by the authoring
        // convention in `DemoProp`, so its collider centre is half a height above it.
        let centre = prop.entity.position(relativeTo: nil) + SIMD3(0, prop.halfExtents.y, 0)
        let heading = simd_length(direction) > 1e-4
            ? simd_normalize(direction)
            : SIMD3<Float>(0, -1, 0)
        return centre + heading * prop.halfExtents.min()
    }

    // MARK: - Collisions

    private func handle(
        _ entityA: Entity, _ entityB: Entity,
        at position: SIMD3<Float>, direction: SIMD3<Float>, reported: Float
    ) {
        guard elapsed > Self.settleGrace else { return }

        // Either side of the contact may be the interesting one — a glass hitting the
        // floor and the floor being hit by a glass are the same event.
        let a = scene.prop(containing: entityA)
        let b = scene.prop(containing: entityB)

        for candidate in [a, b] {
            guard let prop = candidate, prop.isMovable, !broken.contains(prop.id) else { continue }
            let material = resolvedMaterial(for: prop)
            let impulse = impulseEstimate(
                for: prop, material: material,
                at: position, direction: direction, reported: reported
            )

            if material.isBrittle, impulse > material.fractureImpulse(forMass: prop.mass) {
                shatter(prop, material: material, impulse: impulse, at: position)
            } else if impulse > 2.2, prop.mass > 3 {
                playThud(prop, impulse: impulse)
            }
        }
    }

    /// The impulse the prop actually took, in N·s.
    ///
    /// `CollisionEvents` carries an `impulse`, but its units are undocumented and it is
    /// zero for a good many contacts, so it cannot be compared against a threshold in
    /// newton-seconds with a straight face. The contact's own momentum change can be:
    /// J ≈ m·|v·n|·(1 + e), the textbook impulse for a body meeting a much heavier one,
    /// with the velocity read off the prop and the restitution off its authored material.
    ///
    /// The velocity that matters is the one **at the contact point**, v + ω × r, not the
    /// centre of mass's. A bottle toppling on a counter barely translates — almost all of
    /// its speed is rotational — so reading the linear velocity alone said a topple was a
    /// gentle event and nothing on the island ever broke.
    ///
    /// The velocity comes from this system's own tracking in preference to
    /// `PhysicsMotionComponent`, because the tracking is derived from the transform and is
    /// therefore always populated, whereas the component is only maintained if something
    /// put one there first.
    private func impulseEstimate(
        for prop: ApartmentScene.PropEntity, material: PhysicalMaterial,
        at position: SIMD3<Float>, direction: SIMD3<Float>, reported: Float
    ) -> Double {
        let linear: SIMD3<Float>
        let angular: SIMD3<Float>
        if let sample = tracked[prop.id], sample.samples > 1 {
            linear = sample.linear
            angular = sample.angular
        } else if let motion = prop.entity.components[PhysicsMotionComponent.self] {
            linear = motion.linearVelocity
            angular = motion.angularVelocity
        } else {
            return Double(abs(reported))
        }

        let normal = simd_length(direction) > 1e-4
            ? simd_normalize(direction)
            : SIMD3<Float>(0, 1, 0)

        // The prop's origin is its footprint centre on the floor — the pivot a toppling
        // object actually turns about, which is the right centre for this lever arm.
        let pivot = prop.entity.position(relativeTo: nil)
        let lever = position - pivot
        let contactVelocity = linear + simd_cross(angular, lever)

        let closing = abs(simd_dot(contactVelocity, normal))
        return prop.mass * Double(closing) * Double(1 + material.restitution)
    }

    // MARK: - Breaking

    private func shatter(
        _ prop: ApartmentScene.PropEntity,
        material: PhysicalMaterial,
        impulse: Double,
        at contact: SIMD3<Float>
    ) {
        guard let failure = material.failure, !broken.contains(prop.id) else { return }
        broken.insert(prop.id)

        let tint = fractureTint(of: prop.entity)
        let shardMaterial = DemoMaterials.shard(failure: failure, tint: tint)
        let inheritedVelocity = tracked[prop.id]?.linear
            ?? prop.entity.components[PhysicsMotionComponent.self]?.linearVelocity
            ?? .zero

        // Hide the intact object rather than deleting it, so `ApartmentScene.reset` and
        // the results sheet still have a prop to talk about. A disabled entity leaves the
        // simulation with its components intact, so this is one assignment to undo.
        prop.entity.isEnabled = false

        var rng = Seeded.Generator(prop.id)
        let extents = prop.halfExtents
        // The object's mean dimension, in metres. Everything about the break is scaled
        // from this, so a tumbler and a mirror are the same code with different numbers.
        let characteristic = max((extents.x + extents.y + extents.z) * 2 / 3, 0.02)

        let count = shardCount(for: material, characteristic: characteristic)

        // Everything below happens in the simulation root's space; the contact arrives in
        // world space and the scene may sit at any transform.
        let contactLocal = scene.simulationRoot.convert(position: contact, from: nil)
        let base = prop.entity.transform.translation
        let origin = simd_clamp(
            contactLocal,
            base + SIMD3(-extents.x, 0.005, -extents.z),
            base + SIMD3(extents.x, extents.y * 2, extents.z)
        )
        // The break opens away from the point that was struck. Taking the direction from
        // the impact to the body's centre and spraying along it is what makes a break read
        // as *caused* rather than as an object dissolving.
        let bodyCentre = base + SIMD3(0, extents.y, 0)
        let opening = simd_length(bodyCentre - origin) > 1e-4
            ? simd_normalize(bodyCentre - origin)
            : SIMD3<Float>(0, 1, 0)

        let energy = Float(min(max(impulse / material.fractureImpulse(forMass: prop.mass), 1), 3))
        let radius = characteristic * 0.5

        for index in 0..<count {
            // An evenly distributed direction per shard, jittered, then leaned along the
            // opening direction. Even coverage matters: random directions clump, and a
            // clumped break looks like two halves rather than a shatter.
            var direction = Self.fibonacciDirection(index: index, of: count)
            direction += SIMD3(rng.signed(), rng.signed(), rng.signed()) * 0.3
            direction += opening * 0.55
            direction = simd_length(direction) > 1e-4
                ? simd_normalize(direction)
                : SIMD3<Float>(0, 1, 0)

            guard let piece = shard(
                index: index, of: count, characteristic: characteristic,
                radiating: direction, material: material,
                surface: shardMaterial, rng: &rng
            ) else { continue }

            var position = origin + direction * radius * rng.range(0.15, 1.0)
            position.y = max(position.y, 0.006)   // never spawned under the floor
            piece.position = position

            let spray = rng.range(0.7, 1.9) * energy
            piece.components.set(PhysicsMotionComponent(
                linearVelocity: inheritedVelocity + direction * spray
                    + SIMD3(0, rng.range(0.15, 1.1), 0),
                angularVelocity: SIMD3(rng.signed(), rng.signed(), rng.signed()) * 9
            ))

            scene.simulationRoot.addChild(piece)
            debris.append(Debris(entity: piece, lifetime: .infinity, kind: .shard))
            liveShards += 1
        }

        addFlash(at: origin, radius: characteristic)
        addGlitter(at: origin, radius: characteristic, energy: energy, rng: &rng)
        addDust(at: origin, radius: characteristic, rng: &rng)

        // The same call that spawned the pieces plays the sound. Picture and audio come
        // from one event, so they cannot drift apart, and the cue is chosen from the
        // authored material rather than from a category — a wine glass, a bottle and a
        // plate are three different sounds.
        audio?.play(material.breakCue, seed: prop.id, gain: 0.9)

        onBreak?(Event(
            propID: prop.id, name: prop.name, category: prop.category,
            material: material, impulse: impulse
        ))
    }

    /// How many pieces, before and after the budget.
    ///
    /// The count goes as the *square* of the object's size against a target shard size,
    /// not as its volume: brittle thin-walled things fracture in-plane, so what scales is
    /// the area of the wall, and a pane of glass at the same thickness as a tumbler throws
    /// far more pieces than a cube-root law would give it. The material's own
    /// `shardCountRange` then clamps it — 15–40 for glass, 8–20 for ceramic.
    private func shardCount(for material: PhysicalMaterial, characteristic: Float) -> Int {
        let target: Float = material.failure == .glass ? 0.030 : 0.050
        let ratio = characteristic / target
        let range = material.shardCountRange
        var count = min(max(Int((ratio * ratio).rounded()), range.lowerBound), range.upperBound)

        let remaining = Self.shardBudget - liveShards
        guard count > remaining else { return count }

        // Over budget. Fewer and larger, never nothing — `shard` sizes each piece as
        // `1/∛count`, so a halved count is a 26% bigger fragment and the object still
        // visibly comes apart.
        count = max(remaining, Self.minimumShards)
        if count > remaining { evictOldestShards(count - remaining) }
        return count
    }

    /// Makes room at the budget by removing the shards that have been on the floor
    /// longest. The evidence the results sheet talks about is the most recent break, so
    /// oldest-first is also the right order for the story.
    private func evictOldestShards(_ wanted: Int) {
        var removed = 0
        var survivors: [Debris] = []
        survivors.reserveCapacity(debris.count)
        // `debris` is append-ordered, so the front of it is the oldest.
        for piece in debris {
            if piece.kind == .shard, removed < wanted {
                piece.entity.removeFromParent()
                removed += 1
                liveShards -= 1
                continue
            }
            survivors.append(piece)
        }
        debris = survivors
    }

    /// Evenly spaced directions on a sphere, by the Fibonacci spiral. Deterministic, and
    /// — unlike sampling three random components — genuinely even, which is what stops a
    /// break clumping into two lobes.
    private static func fibonacciDirection(index: Int, of count: Int) -> SIMD3<Float> {
        let k = Float(index) + 0.5
        let cosPhi = 1 - 2 * k / Float(max(count, 1))
        let sinPhi = (max(0, 1 - cosPhi * cosPhi)).squareRoot()
        let theta = Float.pi * (1 + Float(5).squareRoot()) * k
        return SIMD3(cos(theta) * sinPhi, cosPhi, sin(theta) * sinPhi)
    }

    /// One convex shard: a thin, sharp, elongated wedge, oriented so its flat face lies
    /// along the direction it is flying. Convex on purpose — a convex hull is the one shape
    /// the solver handles cheaply and never tunnels through the floor.
    private func shard(
        index: Int, of count: Int,
        characteristic: Float,
        radiating direction: SIMD3<Float>,
        material: PhysicalMaterial,
        surface: RealityKit.Material,
        rng: inout Seeded.Generator
    ) -> ModelEntity? {
        // Sized from the object's overall dimensions, so a shard from a wine glass is
        // small and one from a mirror is not. The cube root is the right divisor because
        // the pieces have to fill a volume: n pieces of a body means each is 1/∛n across,
        // not 1/√n. Taking the footprint alone put a wine glass's shards at 6 mm — real
        // slivers, and completely invisible from anywhere the demo camera stands.
        let coarseness: Float = material.failure == .glass ? 0.55 : 0.70
        let size = max(characteristic * coarseness / cbrtf(Float(count)), 0.012)

        // Three or four points on a jittered circle, stretched along one axis: a plausible
        // fragment outline, guaranteed simple so ear clipping cannot fail on it, and
        // *elongated*, because broken glass is splinters and slivers. Equilateral pieces
        // read as gravel.
        let elongation = rng.range(1.7, 3.4)
        let corners = 3 + Int(rng.next() % 2)
        var polygon: [SIMD2<Float>] = []
        polygon.reserveCapacity(corners)
        for c in 0..<corners {
            let theta = Float(c) / Float(corners) * 2 * .pi + rng.range(-0.35, 0.35)
            let r = size * rng.range(0.45, 1.0)
            // Stretched by `elongation` along x and narrowed by its square root along z,
            // rather than by the full factor both ways: dividing by the whole elongation
            // gives a 12:1 needle at the top of the range, which reads as a splinter of
            // wood. The square root holds it near 8:1, which is a shard.
            polygon.append(SIMD2(
                cos(theta) * r * elongation, sin(theta) * r / elongation.squareRoot()
            ))
        }

        // Thin. Glass fails at a few per cent of its span, and this is most of what makes
        // a fragment read as glass rather than as a pebble; ceramic is thicker in section
        // and looks wrong if it is not.
        let thickness = material.failure == .glass
            ? size * rng.range(0.030, 0.075)
            : size * rng.range(0.14, 0.28)

        // Tapered, so each piece is a wedge rather than a prism — a slab of glass with two
        // parallel faces reads as a tile, and the taper is what gives it a sharp edge.
        let mesh = ShardMesh.wedge(
            polygon: polygon, height: thickness, topScale: rng.range(0.20, 0.6)
        )
        guard !mesh.isEmpty, let resource = try? mesh.resource(named: "shard.\(index)") else {
            return nil
        }

        let entity = ModelEntity(mesh: resource, materials: [surface])
        entity.name = "shard"

        // The wedge is built flat in XZ with its thin axis along +Y. Rotating that thin
        // axis to something perpendicular to the flight direction turns the piece so it
        // flies edge-on, which is what a fragment peeling off a fracture surface does, and
        // it means the bright clearcoat edge is what catches the light.
        entity.orientation = Self.orientation(thinAxisPerpendicularTo: direction, rng: &rng)

        // A box collider around the fragment. The visual mesh is convex but irregular;
        // for pieces this small the difference between the hull and its box is below what
        // anyone can see, and the box is far cheaper. The collider is floored at 6 mm
        // thick even when the shard is thinner: a box shape a millimetre deep tunnels and
        // jitters, and the difference is invisible.
        let bounds = mesh.bounds
        let span = bounds.max - bounds.min
        let shape = ShapeResource.generateBox(
            size: SIMD3(max(span.x, 0.006), max(thickness, 0.006), max(span.z, 0.006))
        )
        entity.components.set(CollisionComponent(shapes: [shape], filter: Self.shardFilter))

        // Real mass from the authored density, and heavy damping. Undamped shards this
        // small never come to rest — the solver keeps finding micro-contacts and they
        // buzz across the floor for the rest of the quake.
        let volume = Double(span.x * span.z * thickness) * 0.4
        var body = PhysicsBodyComponent(
            shapes: [shape],
            mass: Float(max(volume * material.density, 0.004)),
            material: .generate(friction: material.friction, restitution: material.restitution * 0.5),
            mode: .dynamic
        )
        body.linearDamping = 1.4
        body.angularDamping = 2.2
        body.isContinuousCollisionDetectionEnabled = true
        entity.components.set(body)

        applyImageBasedLight(to: entity)
        return entity
    }

    /// Rotation putting the wedge's thin axis (+Y in its own space) at right angles to
    /// `direction`, with a random spin in the remaining degree of freedom.
    private static func orientation(
        thinAxisPerpendicularTo direction: SIMD3<Float>, rng: inout Seeded.Generator
    ) -> simd_quatf {
        var reference = SIMD3(rng.signed(), rng.signed(), rng.signed())
        if simd_length(reference) < 1e-3 { reference = SIMD3(0, 1, 0) }
        var thin = simd_cross(direction, reference)
        if simd_length(thin) < 1e-4 { thin = simd_cross(direction, SIMD3(0, 1, 0)) }
        if simd_length(thin) < 1e-4 { thin = SIMD3(1, 0, 0) }
        thin = simd_normalize(thin)

        let up = SIMD3<Float>(0, 1, 0)
        let align: simd_quatf
        let dot = simd_dot(up, thin)
        if dot < -0.9999 {
            // Antiparallel: `simd_quatf(from:to:)` is undefined there, so turn it over
            // about any perpendicular axis instead.
            align = simd_quatf(angle: .pi, axis: SIMD3(1, 0, 0))
        } else {
            align = simd_quatf(from: up, to: thin)
        }
        return align * simd_quatf(angle: rng.range(0, 2 * .pi), axis: up)
    }

    // MARK: - The instant of the break

    /// The white flash. Two things at once: an unlit sphere that blooms and vanishes in
    /// about a tenth of a second, and a brief point light so the flash lands on the
    /// surfaces around it rather than floating in front of them.
    ///
    /// It is not decoration. Substitution has one weakness — the single frame where an
    /// intact object becomes a cloud of pieces — and a bright frame over exactly that
    /// moment is the oldest fix in effects work, because the eye cannot resolve what
    /// happened underneath it.
    private func addFlash(at position: SIMD3<Float>, radius: Float) {
        let sphere = ModelEntity(
            mesh: .generateSphere(radius: max(radius, 0.03) * 0.9),
            materials: [DemoMaterials.impactFlash]
        )
        sphere.position = position
        sphere.scale = SIMD3(repeating: 0.35)
        scene.simulationRoot.addChild(sphere)
        debris.append(Debris(entity: sphere, lifetime: Self.flashLifetime, kind: .flash))

        guard !flashLightLive else { return }
        flashLightLive = true
        let light = Entity()
        light.components.set(PointLightComponent(
            color: UIColor(red: 1.0, green: 0.98, blue: 0.94, alpha: 1),
            intensity: 9000,
            attenuationRadius: 1.8
        ))
        light.position = position
        scene.simulationRoot.addChild(light)
        debris.append(Debris(entity: light, lifetime: Self.flashLifetime * 0.8, kind: .flash))
    }

    /// The fine stuff: sixteen sub-centimetre specks thrown out ballistically, unlit so
    /// they read at distance. Glass does not break into fragments alone — it breaks into
    /// fragments *and powder*, and the powder catching the light is a large part of why a
    /// real break looks violent.
    private func addGlitter(
        at position: SIMD3<Float>, radius: Float, energy: Float, rng: inout Seeded.Generator
    ) {
        for _ in 0..<16 {
            let speck = ModelEntity(
                mesh: .generateSphere(radius: rng.range(0.0018, 0.0042)),
                materials: [DemoMaterials.glitter]
            )
            speck.position = position + SIMD3(rng.signed(), rng.signed(), rng.signed()) * radius * 0.3
            scene.simulationRoot.addChild(speck)
            var direction = SIMD3(rng.signed(), rng.range(0.1, 1.0), rng.signed())
            if simd_length(direction) < 1e-4 { direction = SIMD3(0, 1, 0) }
            debris.append(Debris(
                entity: speck, lifetime: Self.glitterLifetime, kind: .glitter,
                velocity: simd_normalize(direction) * rng.range(0.9, 2.6) * energy
            ))
        }
    }

    /// A short puff where the break happened. Five small spheres that expand, rise and
    /// thin out — about as cheap as a particle can be while still doing the job of hiding
    /// the instant of substitution.
    ///
    /// Five rather than eight, and faint rather than translucent, because eight spheres at
    /// 0.20 alpha composite to roughly 0.83 wherever they overlap: not dust, but a cluster
    /// of solid grey balls.
    ///
    /// Deliberately not the prop's own material: a puff of clear glass is a puff of
    /// nothing. This is the dust the impact throws up, so it is dust-coloured.
    private func addDust(at position: SIMD3<Float>, radius: Float, rng: inout Seeded.Generator) {
        for _ in 0..<5 {
            let size = max(radius, 0.03) * rng.range(0.18, 0.36)
            let puff = ModelEntity(
                mesh: .generateSphere(radius: size),
                materials: [DemoMaterials.breakDust(opacity: DemoMaterials.breakDustOpacity)]
            )
            puff.position = position + SIMD3(rng.signed(), rng.unit(), rng.signed()) * radius * 0.6
            puff.scale = SIMD3(repeating: 0.4)
            scene.simulationRoot.addChild(puff)
            debris.append(Debris(entity: puff, lifetime: Self.dustLifetime, kind: .dust))
        }
    }

    // MARK: - Debris per frame

    private func updateDebris(deltaTime: Double, groundAcceleration: SIMD3<Float>) {
        guard !debris.isEmpty else { return }

        var survivors: [Debris] = []
        survivors.reserveCapacity(debris.count)

        for var piece in debris {
            piece.age += deltaTime
            if piece.age >= piece.lifetime {
                // Only the light half of a flash releases the one-light budget. Clearing
                // it when the flash *sphere* goes would let a second light in while the
                // first was still burning.
                if piece.entity.components.has(PointLightComponent.self) {
                    flashLightLive = false
                }
                piece.entity.removeFromParent()
                continue
            }

            switch piece.kind {
            case .shard:
                updateShard(&piece, deltaTime: deltaTime, groundAcceleration: groundAcceleration)
            case .dust:
                // Dust expands, rises and thins out. The fade is the important part: a puff
                // that only grew reached the end of its lifetime at maximum size and full
                // opacity and then disappeared between two frames, which is a pop, not a
                // puff. Fading is a material rebuild per frame, for at most a handful of
                // spheres at a time.
                let t = Float(piece.age / piece.lifetime)
                piece.entity.scale = SIMD3(repeating: 0.4 + t * 2.2)
                piece.entity.position.y += Float(deltaTime) * 0.22
                if var model = piece.entity.components[ModelComponent.self] {
                    // Squared, so the puff holds its shape for the first half of its life
                    // and then leaves quickly rather than lingering as a grey smear.
                    let remaining = (1 - t) * (1 - t)
                    model.materials = [
                        DemoMaterials.breakDust(
                            opacity: DemoMaterials.breakDustOpacity * remaining)
                    ]
                    piece.entity.components.set(model)
                }
            case .glitter:
                // No rigid body — sixteen specks per break, each with a collider, would
                // cost more than the shards do. Ballistic integration is enough for half a
                // second of flight.
                piece.velocity.y -= 9.81 * Float(deltaTime)
                piece.entity.position += piece.velocity * Float(deltaTime)
            case .flash:
                let t = Float(piece.age / piece.lifetime)
                piece.entity.scale = SIMD3(repeating: 0.35 + t * 1.5)
            }

            survivors.append(piece)
        }
        debris = survivors
    }

    private func updateShard(
        _ piece: inout Debris, deltaTime: Double, groundAcceleration: SIMD3<Float>
    ) {
        guard let model = piece.entity as? ModelEntity,
              var body = model.components[PhysicsBodyComponent.self] else { return }

        if piece.isFrozen { return }

        if piece.age > Self.shardFreeze {
            // Frozen where it lies. A static body is out of the solver entirely, so a
            // floor covered in glass costs nothing to keep — which is what lets the shards
            // stay for the whole quake and behind the results sheet instead of being
            // despawned on a clock.
            body.mode = .static
            model.components.set(body)
            piece.isFrozen = true
            return
        }

        guard body.mode == .dynamic else { return }
        // Debris is not in `scene.props`, so `ApartmentScene.applyHorizontalAcceleration`
        // never reaches it. Without this the shards behave as though the quake stopped the
        // moment they appeared.
        model.addForce(-body.massProperties.mass * groundAcceleration, relativeTo: nil)
    }

    // MARK: - Appearance

    /// The image-based light is an entity carrying `ImageBasedLightComponent`, hung off the
    /// scene root by `ApartmentScene.applyImageBasedLight`, and every prop is made a
    /// receiver of it at build time. Shards are created long afterwards, so they have to be
    /// enrolled too — without this a fragment is lit only by the direct lights and reads as
    /// a flat grey chip next to the object it came out of.
    private lazy var imageBasedLight: Entity? = scene.root.children.first {
        $0.components.has(ImageBasedLightComponent.self)
    }

    private func applyImageBasedLight(to entity: Entity) {
        guard let ibl = imageBasedLight else { return }
        entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl))
    }

    /// The colour of the object that broke, taken from the largest visible part — which for
    /// every breakable in this room is the body of the object rather than a label or a
    /// coaster. `DemoMaterials.shard` decides what to do with it.
    private func fractureTint(of entity: Entity) -> UIColor {
        var best: UIColor = .white
        var bestVolume: Float = -1
        for child in entity.children {
            guard let model = child.components[ModelComponent.self],
                  let material = model.materials.first else { continue }
            let extents = model.mesh.bounds.extents
            let volume = extents.x * extents.y * extents.z
            if volume > bestVolume {
                bestVolume = volume
                best = DemoMaterials.tint(of: material)
            }
        }
        return best
    }

    // MARK: - Impacts

    /// The building complaining. Triggered off the accelerogram rather than off any
    /// object, because that is what it is: the structure, not the contents. Sparse by
    /// design — one every few seconds at the peaks is atmosphere, any more is a haunted
    /// house — and deterministic, since the accelerogram it keys off is seeded.
    private func playCreak(_ groundAcceleration: SIMD3<Float>) {
        guard elapsed > Self.settleGrace else { return }
        let magnitude = Double(simd_length(groundAcceleration)) / 9.81
        guard magnitude > 0.30, elapsed - lastCreak > 2.4 else { return }
        lastCreak = elapsed
        audio?.play(.creak, seed: "creak.\(Int(elapsed))", gain: 0.35)
    }

    private func playThud(_ prop: ApartmentScene.PropEntity, impulse: Double) {
        guard elapsed - lastThud > 0.16 else { return }
        lastThud = elapsed
        audio?.play(.thud, seed: prop.id, gain: Float(min(impulse / 40, 1)) * 0.7 + 0.2)
    }
}

// MARK: - Shard geometry

/// A tapered convex wedge, built here rather than with `Mesh.extrude`.
///
/// `Mesh.extrude` gives its side walls outward normals but inward winding — harmless for
/// the rug and the coffee table, which are seen from above, and fatal for a shard, which
/// tumbles and is seen from every angle. With back-face culling on, half of every piece
/// would simply not be there. This builds the same form with winding and shading in
/// agreement, which is the same fix `DiningModule.Turned` makes for lofted surfaces.
private enum ShardMesh {

    /// `polygon` is the base outline in the XZ plane, counter-clockwise in numeric (x, z).
    static func wedge(polygon: [SIMD2<Float>], height: Float, topScale: Float) -> MeshAccumulator {
        guard polygon.count >= 3 else { return MeshAccumulator() }
        var mesh = MeshAccumulator()
        let n = polygon.count
        let top = polygon.map { $0 * topScale }

        for i in 0..<n {
            let b0 = polygon[i], b1 = polygon[(i + 1) % n]
            let t0 = top[i], t1 = top[(i + 1) % n]
            let edge = b1 - b0
            let length = simd_length(edge)
            guard length > 1e-6 else { continue }
            // Outward in the XZ plane; the taper's vertical component is small enough at
            // these sizes that leaving it out is invisible.
            let normal = SIMD3(edge.y / length, 0, -edge.x / length)
            mesh.addQuad(
                SIMD3(t0.x, height, t0.y), SIMD3(t1.x, height, t1.y),
                SIMD3(b1.x, 0, b1.y), SIMD3(b0.x, 0, b0.y),
                normal: normal
            )
        }

        // Ear clipping returns numerically counter-clockwise triples, which face −Y.
        let triangles = Triangulator.earClip(polygon)
        var base = [UInt32](repeating: 0, count: n)
        for (i, p) in polygon.enumerated() {
            base[i] = mesh.addVertex(SIMD3(p.x, 0, p.y), normal: SIMD3(0, -1, 0), uv: p)
        }
        for t in triangles { mesh.addTriangle(base[Int(t.0)], base[Int(t.1)], base[Int(t.2)]) }

        var cap = [UInt32](repeating: 0, count: n)
        for (i, p) in top.enumerated() {
            cap[i] = mesh.addVertex(SIMD3(p.x, height, p.y), normal: SIMD3(0, 1, 0), uv: p)
        }
        for t in triangles { mesh.addTriangle(cap[Int(t.0)], cap[Int(t.2)], cap[Int(t.1)]) }

        return mesh
    }
}
