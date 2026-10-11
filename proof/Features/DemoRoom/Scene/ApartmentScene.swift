import Foundation
import RealityKit
import simd
#if canImport(UIKit)
import UIKit
#endif

// Assembles the demo apartment into a live RealityKit scene.
//
// Every module contributes `DemoProp`s; this turns them into entities, gives the movable
// ones rigid bodies, and lights the room.
//
// ## How the earthquake is staged
//
// The physics runs in the *ground* frame: the floor and walls never move, and each loose
// object is excited by the d'Alembert force −m·a(t). That is the standard base-excitation
// formulation, and it is the same one `EarthquakeSimulator` uses for the real product, so
// the demo does not contradict the app's own physics.
//
// The room still has to *look* like it is shaking, though — objects sliding around a
// static room reads as a poltergeist, not an earthquake. That is fixed at the camera:
// the camera is displaced by −d(t), so on screen the entire room translates by +d(t)
// while loose objects additionally slide and topple relative to it. One subtraction buys
// the whole effect, and it stays physically honest.

@MainActor
final class ApartmentScene {

    /// Everything in the apartment. The camera is deliberately *not* a child of this.
    let root = Entity()
    /// Physics owner. Gravity lives here so the vertical component can be modulated.
    let simulationRoot = Entity()
    let lightingRoot = Entity()

    private(set) var props: [String: PropEntity] = [:]
    private(set) var order: [String] = []

    /// Set once at build time so the top-down mode can drop the ceiling out of the way.
    private(set) var ceilingEntity: Entity?

    let materials: DemoMaterials

    struct PropEntity {
        let id: String
        let name: String
        let category: DemoProp.Category
        /// A `ModelEntity` with no mesh of its own — the parts hang off it as children.
        /// It has to be a `ModelEntity` rather than a plain `Entity` because only that
        /// conforms to `HasPhysicsBody`, and therefore only that accepts `addForce`.
        let entity: ModelEntity
        /// Where the object stands when the room is at rest. Set at build time and then
        /// *replaced by the settled pose* once the solver has dropped everything onto its
        /// real support, so "reset" means "back to where it was actually resting", not
        /// "back to the height the author typed".
        var restTransform: Transform
        let mass: Double
        let isMovable: Bool
        /// Half-extents of the collider, cached for the force calculation.
        let halfExtents: SIMD3<Float>
        /// The collider's own bounds, in the prop's local frame.
        ///
        /// `halfExtents` alone is not enough to say where a prop's top face is: a countertop
        /// declares its collider at 0.92…0.955 m and a wall cabinet at 1.40…2.20 m, so
        /// "origin plus twice the half-extent" puts both of them somewhere near the floor.
        /// Anything reasoning about what is standing on what needs the real span.
        let localLow: SIMD3<Float>
        let localHigh: SIMD3<Float>
        /// Whether this prop's body was given continuous collision detection when it was
        /// built. Remembered so the flag can be taken off while the body is kinematic and
        /// put back when it goes dynamic again — see `setPhysicsActive(_:)`.
        let usesContinuousCollision: Bool
    }

    // MARK: - Build

    init(materials: DemoMaterials) {
        self.materials = materials
        root.addChild(simulationRoot)
        root.addChild(lightingRoot)

        var physics = PhysicsSimulationComponent()
        physics.gravity = SIMD3(0, -9.81, 0)
        physics.solverIterations = .init(positionIterations: 12, velocityIterations: 6)
        simulationRoot.components.set(physics)
    }

    /// Builds the whole apartment. Returns the number of props realised.
    @discardableResult
    func build() -> Int {
        let all = ShellModule.build(materials)
            + KitchenModule.build(materials)
            + DiningModule.build(materials)
            + LivingModule.build(materials)

        for prop in all { realise(prop) }
        installLighting()
        applyImageBasedLight()
        beginSettling()
        return props.count
    }

    private func realise(_ prop: DemoProp) {
        let container = ModelEntity()
        container.name = prop.id
        container.transform = Transform(matrix: prop.transform)

        var built = 0
        for (index, part) in prop.parts.enumerated() where !part.mesh.isEmpty {
            guard let mesh = try? part.mesh.resource(named: "\(prop.id).\(index)") else { continue }
            let model = ModelEntity(mesh: mesh, materials: [part.material])
            model.name = "\(prop.id).part\(index)"
            if part.castsShadow {
                model.components.set(GroundingShadowComponent(castsShadow: true))
            }
            container.addChild(model)
            built += 1
        }
        guard built > 0 else { return }

        let collider = makeCollider(for: prop)
        container.components.set(CollisionComponent(shapes: collider.shapes))
        var usesContinuousCollision = false

        let behaviour = effectiveBehaviour(for: prop)
        switch behaviour {
        case .fixed, .mounted:
            // Wall-mounted pieces are pinned for the demo. Their colliders necessarily
            // intersect the wall they hang on, and a box-on-box contact resolves that by
            // firing the picture into the room on the first frame. Making art fall
            // convincingly needs a constraint, not a rigid body, and that is a bigger
            // change than this demo needs.
            container.components.set(PhysicsBodyComponent(
                shapes: collider.shapes, mass: 1, material: .default, mode: .static
            ))
        case .movable(let mass):
            let material = PhysicsMaterialResource.generate(
                friction: friction(for: prop.category),
                restitution: restitution(for: prop.category)
            )
            // Dynamic from the moment the room exists, not from the moment the quake
            // starts. A kinematic body ignores gravity and ignores contacts, so under the
            // old arrangement nothing was ever *resting* on anything — every object simply
            // hung at the height it was authored at, and the first frame of the earthquake
            // was also the first frame of gravity. `beginSettling` lets the solver drop
            // everything onto its real support and then freezes the result.
            var body = PhysicsBodyComponent(
                shapes: collider.shapes, mass: Float(mass),
                material: material, mode: .dynamic
            )
            // Small objects moving at quake speeds tunnel through a 24 mm shelf plank in a
            // single 60 Hz step, which is exactly the population this change is about.
            body.isContinuousCollisionDetectionEnabled = collider.smallestExtent < 0.16
            usesContinuousCollision = body.isContinuousCollisionDetectionEnabled
            container.components.set(body)
            // Only loose objects are tappable; walls should never swallow a tap.
            container.components.set(InputTargetComponent())
        }

        simulationRoot.addChild(container)

        let isMovable: Bool
        let mass: Double
        if case .movable(let m) = behaviour {
            isMovable = true
            mass = m
        } else {
            isMovable = false
            mass = .infinity
        }

        let entry = PropEntity(
            id: prop.id, name: prop.name, category: prop.category,
            entity: container, restTransform: container.transform,
            mass: mass, isMovable: isMovable, halfExtents: collider.halfExtents,
            localLow: collider.low, localHigh: collider.high,
            usesContinuousCollision: usesContinuousCollision
        )
        props[prop.id] = entry
        order.append(prop.id)

        if prop.id == "shell.ceiling" { ceilingEntity = container }
    }

    private struct Collider {
        let shapes: [ShapeResource]
        let halfExtents: SIMD3<Float>
        /// The union of the collider's boxes, in local space.
        let low: SIMD3<Float>
        let high: SIMD3<Float>
        /// The thinnest dimension of the thinnest box, which is what decides whether this
        /// prop can tunnel through a contact in one step.
        let smallestExtent: Float
    }

    /// Props are authored to touch — a range sits in a cabinet run, a dishwasher fills a
    /// gap — so a box taken from raw geometry overlaps its neighbours, and the solver
    /// resolves that overlap by firing the appliances across the room on the first frame.
    /// Inferred colliders are therefore shrunk by `inset`.
    private static let inset: Float = 0.014

    private func makeCollider(for prop: DemoProp) -> Collider {
        // Declared boxes are used **verbatim**, with no inset.
        //
        // The inset exists to pull an inferred box back out of its neighbours. A declared
        // box has no such problem: the author knew where the plank's top face was and put
        // it there. Shrinking it would drop every object resting on that plank by 14 mm on
        // the first frame — the visible "everything sinks into the furniture" artefact
        // this whole change is about — and open a 14 mm gap at the sides that small props
        // slide into and stick in.
        if !prop.colliderBoxes.isEmpty {
            var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
            var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
            var smallest = Float.greatestFiniteMagnitude
            var shapes: [ShapeResource] = []
            shapes.reserveCapacity(prop.colliderBoxes.count)
            for box in prop.colliderBoxes {
                let size = simd_max(box.size, SIMD3(repeating: 0.006))
                shapes.append(
                    ShapeResource.generateBox(size: size).offsetBy(translation: box.centre)
                )
                lo = simd_min(lo, box.centre - size / 2)
                hi = simd_max(hi, box.centre + size / 2)
                smallest = min(smallest, size.min())
            }
            return Collider(
                shapes: shapes, halfExtents: (hi - lo) / 2,
                low: lo, high: hi, smallestExtent: smallest
            )
        }

        // One box per prop, offset to the geometry's centre. A box is the right shape here
        // for the same reason it is right in the safety product: the failure mode of
        // interest is toppling, and toppling is governed by the footprint and the centre of
        // mass, not by surface detail.
        // The inset is applied sideways and at the top, but **never at the bottom**.
        //
        // A prop's underside is the face it stands on. Insetting it lifted every object's
        // collider 14 mm above its own base, so the object came to rest with its geometry
        // 14 mm inside whatever it was standing on. On a fridge nobody notices; on a 60 mm
        // brass dish it is a quarter of the object buried in the shelf. Sideways and
        // overhead the inset still does its job, which is to stop props authored to touch
        // from starting inside each other.
        let bounds = colliderBounds(for: prop)
        let lo = bounds.min + SIMD3(Self.inset, 0, Self.inset)
        let hi = bounds.max - SIMD3(repeating: Self.inset)
        let size = simd_max(hi - lo, SIMD3(repeating: 0.02))
        let centre = lo + size / 2
        return Collider(
            shapes: [ShapeResource.generateBox(size: size).offsetBy(translation: centre)],
            halfExtents: size / 2,
            low: centre - size / 2, high: centre + size / 2,
            smallestExtent: size.min()
        )
    }

    /// Most colliders come straight from the geometry, but a few props have a silhouette
    /// whose bounding box would be wrong to rest things on — a sofa's box would reach the
    /// top of its back, leaving its cushions floating in mid-air.
    private func colliderBounds(for prop: DemoProp) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        var bounds = prop.localBounds
        switch prop.id {
        case "living.sofa":
            bounds.max.y = 0.44          // seat height, so cushions land on the seat
        case "living.armchair":
            bounds.max.y = 0.42
        default:
            break
        }
        return bounds
    }

    /// Appliances that are built into the cabinet run. A dishwasher and an under-counter
    /// microwave are captive between a carcass and a countertop — they cannot slide out,
    /// and modelling them as loose bodies only produces artefacts.
    private static let builtIn: Set<String> = [
        "kitchen.dishwasher", "kitchen.microwave", "kitchen.hood", "kitchen.range"
    ]

    private func effectiveBehaviour(for prop: DemoProp) -> DemoProp.Behaviour {
        Self.builtIn.contains(prop.id) ? .fixed : prop.behaviour
    }

    private func friction(for category: DemoProp.Category) -> Float {
        switch category {
        case .seating, .softFurnishing: return 0.62
        case .table, .storage, .appliance: return 0.48
        case .tableware: return 0.32     // crockery on quartz slides readily
        case .decor, .lighting: return 0.40
        default: return 0.45
        }
    }

    /// Deliberately low, and lower still for anything soft.
    ///
    /// The measured coefficient of restitution of glass on stone is around 0.4, but that is
    /// a number for a single free drop. Fed to a 60 Hz solver that re-resolves a persisting
    /// contact every step, it becomes a mug that never stops hopping on the counter. The
    /// demo's job is to show what falls, not to run a bounce experiment, so restitution is
    /// held at the point where objects settle within a few frames of landing.
    private func restitution(for category: DemoProp.Category) -> Float {
        switch category {
        case .softFurnishing, .seating: return 0.02
        case .tableware, .glazing: return 0.14
        case .decor, .lighting: return 0.10
        default: return 0.06
        }
    }

    // MARK: - Lighting

    private func installLighting() {
        // Sun through the corner glazing. This is the only shadow-caster: multiple shadow
        // maps are expensive on a phone, and a single strong directional source is what an
        // interior at this hour actually looks like.
        let sun = Entity()
        var sunLight = DirectionalLightComponent(
            color: UIColor(red: 1.0, green: 0.955, blue: 0.90, alpha: 1),
            intensity: Plan.Light.sunIntensity
        )
        sunLight.isRealWorldProxy = false
        sun.components.set(sunLight)
        sun.components.set(DirectionalLightComponent.Shadow(
            maximumDistance: 14, depthBias: 1.6
        ))
        let dir = simd_normalize(Plan.Light.sunDirection)
        sun.look(at: Plan.centre, from: Plan.centre - dir * 12, relativeTo: nil)
        lightingRoot.addChild(sun)

        // Cool sky fill from the opposite side, no shadow. Keeps the shadow interiors from
        // going black, which is the single most common tell of a rendered interior.
        let fill = Entity()
        fill.components.set(DirectionalLightComponent(
            color: UIColor(red: 0.84, green: 0.89, blue: 1.0, alpha: 1),
            intensity: Plan.Light.skyIntensity
        ))
        fill.look(
            at: Plan.centre,
            from: Plan.centre + SIMD3(-0.7, 0.85, 0.5) * 10,
            relativeTo: nil
        )
        lightingRoot.addChild(fill)

        // Warm bounce off the oak floor. Kept deliberately weak and only lightly tinted:
        // this light points up, so it lands almost entirely on the ceiling, and at full
        // saturation it turns the grey concrete soffit into something that reads as pine.
        let bounce = Entity()
        bounce.components.set(DirectionalLightComponent(
            color: UIColor(red: 1.0, green: 0.95, blue: 0.88, alpha: 1),
            intensity: 150
        ))
        bounce.look(
            at: SIMD3(Plan.width / 2, 1.6, Plan.length / 2),
            from: SIMD3(Plan.width / 2, -1.2, Plan.length / 2 + 1),
            relativeTo: nil
        )
        lightingRoot.addChild(bounce)

        // Practicals. These are what make the room feel inhabited rather than lit.
        addPointLight(at: Plan.Light.floorLamp, colour: (1.0, 0.86, 0.66), intensity: 2600, radius: 4.2)
        addPointLight(at: Plan.Light.consoleLamp, colour: (1.0, 0.87, 0.68), intensity: 1900, radius: 3.4)
        addPointLight(at: Plan.Light.kitchenUnderCabinet, colour: (1.0, 0.93, 0.82), intensity: 1500, radius: 3.0)

        // The five track heads. These are spot lights, not point lights: a track head is a
        // directional fitting aimed at the counter, and modelling it as an omnidirectional
        // bulb floods the concrete soffit with warm light and turns the ceiling tan.
        let track = Plan.Kitchen.trackZ
        for i in 0..<Plan.Kitchen.trackHeadCount {
            let t = Float(i) / Float(max(Plan.Kitchen.trackHeadCount - 1, 1))
            let z = track.lowerBound + (track.upperBound - track.lowerBound) * t
            let origin = SIMD3<Float>(Plan.Kitchen.trackX, Plan.ceilingHeight - 0.16, z)

            let head = Entity()
            head.components.set(SpotLightComponent(
                color: UIColor(red: 1.0, green: 0.91, blue: 0.78, alpha: 1),
                intensity: 4200,
                innerAngleInDegrees: 24,
                outerAngleInDegrees: 52,
                attenuationRadius: 5.0
            ))
            // Heads on the kitchen half aim at the counter run; the rest wash the floor.
            let aim = z < 1.9
                ? SIMD3<Float>(Plan.Kitchen.sinkCentre, 0.95, 0.35)
                : SIMD3<Float>(Plan.Kitchen.trackX, 0, z + 0.3)
            head.look(at: aim, from: origin, relativeTo: nil)
            lightingRoot.addChild(head)
        }
    }

    private func addPointLight(
        at position: SIMD3<Float>, colour: (Float, Float, Float),
        intensity: Float, radius: Float
    ) {
        let light = Entity()
        light.components.set(PointLightComponent(
            color: UIColor(
                red: CGFloat(colour.0), green: CGFloat(colour.1),
                blue: CGFloat(colour.2), alpha: 1
            ),
            intensity: intensity,
            attenuationRadius: radius
        ))
        light.position = position
        lightingRoot.addChild(light)
    }

    private func applyImageBasedLight() {
        guard let environment = EnvironmentFactory.makeEnvironment() else { return }
        let ibl = Entity()
        ibl.components.set(ImageBasedLightComponent(source: .single(environment), intensityExponent: 1.05))
        root.addChild(ibl)
        for prop in props.values {
            prop.entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl))
        }
    }

    // MARK: - Settling

    /// True once the loose objects have been dropped onto their supports and frozen there.
    private(set) var isSettled = false
    private var settleTask: Task<Void, Never>?

    /// How long the solver is given to bring the room to rest. Objects start within a few
    /// millimetres of their support, so this is generous; the cost of it being too short is
    /// a prop frozen mid-drop, which is worse than a little idle time nobody sees.
    private static let settleSeconds: Double = 1.6

    /// 0.5 mm. See `freezeSettledPose` — this is the gap that stops a resting object's
    /// base and its support from being the same plane.
    private static let restLift: Float = 0.0005

    /// Drop everything onto its real support, then take that as the room's rest pose.
    ///
    /// This is the answer to "why doesn't anything fall off the shelves". Loose props used
    /// to be kinematic until the earthquake began: a kinematic body has no gravity and no
    /// contacts, so a vase authored 2 cm above a shelf simply hung there, and a vase
    /// authored 2 cm *inside* one was fine until the instant physics turned on, at which
    /// point the solver pushed it out at speed. Neither is resting on anything.
    ///
    /// Settling first means the room the user explores is a room where every object is
    /// demonstrably supported by the surface under it, and the first frame of the quake is
    /// an earthquake rather than the first frame of gravity.
    private func beginSettling() {
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            // RealityKit does not step a simulation that is not in a presented scene, and
            // this room is built when the demo screen appears but not *shown* until the
            // user has tapped through the video — which may be a minute later, or never.
            // So the wait is on the scene going live rather than on a clock. The reference
            // is weak: if the room is discarded before it is ever presented, this returns.
            while true {
                guard let self, !Task.isCancelled else { return }
                if self.root.scene != nil { break }
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
            guard let self, !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: UInt64(Self.settleSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.freezeSettledPose()
        }
    }

    /// Takes wherever the solver left each object as its rest pose, and puts it back to
    /// sleep so nothing creeps while the user orbits the room.
    ///
    /// Anything that escaped the room during the settle is put back where the author had
    /// it. That is a bug guard, not a physics decision: an object 3 m below the floor is a
    /// collider mistake, and freezing it there would hide the mistake instead of showing it.
    func freezeSettledPose() {
        for id in order {
            guard let prop = props[id], prop.isMovable else { continue }
            let settled = prop.entity.transform
            let escaped = settled.translation.y < -0.4
                || simd_distance(settled.translation, prop.restTransform.translation) > 1.2
            if escaped {
                #if DEBUG
                // Say so. Restoring an escapee silently is what let a 120 kg fridge
                // interpenetrating the wall cabinets go unnoticed — it was put back every
                // time, so the room looked right, while on the way past it knocked over
                // the ladder shelving and left twelve objects hanging in the air. An
                // escape is always a collider bug in this room; it should be loud.
                print("""
                    [ApartmentScene] \(id) escaped during the settle — \
                    \(simd_distance(settled.translation, prop.restTransform.translation))\
                    m from \(prop.restTransform.translation) to \(settled.translation). \
                    Its collider almost certainly starts inside another prop's.
                    """)
                #endif
            }
            if escaped {
                prop.entity.transform = prop.restTransform
                prop.entity.resetPhysicsTransform(recursive: false)
            } else {
                // Lifted by half a millimetre before the pose is frozen.
                //
                // The solver brings an object to rest with its base plane *exactly*
                // coincident with the plane it is resting on, and two coincident planes are
                // the textbook cause of z-fighting: at the foot of a vase and inside a bowl
                // the depth test flickers between the two surfaces and paints a bright
                // radial starburst, which is visible in the very first frame the user sees.
                // Half a millimetre is under a tenth of a pixel at any framing this room is
                // ever shown at, and it is two orders of magnitude more than the depth
                // buffer's resolution at these distances.
                var lifted = settled
                lifted.translation.y += Self.restLift
                prop.entity.transform = lifted
                prop.entity.resetPhysicsTransform(recursive: false)
                props[id]?.restTransform = lifted
            }
        }
        setPhysicsActive(false)
        isSettled = true
    }

    // MARK: - Simulation control

    /// Loose objects are dynamic while the room settles and while it shakes, and kinematic
    /// in between, so nothing drifts or jitters while the user is exploring.
    func setPhysicsActive(_ active: Bool) {
        if active {
            // Starting the quake mid-settle is legitimate — the launch arguments jump
            // straight to `shake` — and the quake is a strictly better source of motion
            // than the settle, so it simply takes over.
            settleTask?.cancel()
            settleTask = nil
            isSettled = true
        }
        for prop in props.values where prop.isMovable {
            guard var body = prop.entity.components[PhysicsBodyComponent.self] else { continue }
            body.mode = active ? .dynamic : .kinematic
            // PhysX does not support continuous collision detection on a kinematic body
            // and says so, once per prop, every time the room is put to sleep — eighty
            // lines of `CCD will be ignored` per launch, which buried the one console
            // message this file actually wants seen (the settle-escape warning above).
            // The flag is taken off on the way out and put back on the way in, so the
            // small props still get CCD in the only state where it does anything.
            body.isContinuousCollisionDetectionEnabled = active && prop.usesContinuousCollision
            prop.entity.components.set(body)
            if active {
                // Put the motion component back on the way in.
                //
                // Turning a body dynamic does not give it one — RealityKit expects the
                // caller to supply it — and stripping it below on the way out used to
                // leave every prop permanently without one after the first stop. That
                // was not cosmetic: `BreakageSystem` reads linear velocity from this
                // component to estimate impact energy, so with it missing every impact
                // estimate fell through to a dead path and *nothing in the room could
                // ever break*. Seed an empty one and let the solver fill it in.
                if prop.entity.components[PhysicsMotionComponent.self] == nil {
                    prop.entity.components.set(PhysicsMotionComponent())
                }
            } else {
                // Removed on the way out so a kinematic prop does not keep reporting the
                // velocity it had at the instant the quake stopped.
                prop.entity.components.remove(PhysicsMotionComponent.self)
            }
        }
    }

    /// Restores every object to where the designer put it.
    func reset() {
        for prop in props.values {
            prop.entity.transform = prop.restTransform
            if prop.isMovable {
                prop.entity.components.remove(PhysicsMotionComponent.self)
                if var body = prop.entity.components[PhysicsBodyComponent.self] {
                    body.mode = .kinematic
                    body.isContinuousCollisionDetectionEnabled = false
                    prop.entity.components.set(body)
                }
                prop.entity.resetPhysicsTransform(recursive: false)
            }
        }
    }

    /// Vertical ground acceleration is folded into gravity rather than applied as a force,
    /// which keeps resting contacts stable.
    func setVerticalAcceleration(_ ay: Float) {
        guard var physics = simulationRoot.components[PhysicsSimulationComponent.self] else { return }
        physics.gravity = SIMD3(0, -(9.81 + ay), 0)
        simulationRoot.components.set(physics)
    }

    /// Applies one step of horizontal base excitation.
    func applyHorizontalAcceleration(_ a: SIMD3<Float>) {
        for prop in props.values where prop.isMovable {
            prop.entity.addForce(-Float(prop.mass) * a, relativeTo: nil)
        }
    }

    // MARK: - Queries

    /// Walks up from a hit entity to the prop that owns it.
    func prop(containing entity: Entity) -> PropEntity? {
        var node: Entity? = entity
        while let current = node {
            if let match = props[current.name] { return match }
            node = current.parent
        }
        return nil
    }

    var movableCount: Int { props.values.filter(\.isMovable).count }

    func setCeilingHidden(_ hidden: Bool) {
        ceilingEntity?.isEnabled = !hidden
    }

    /// Which way each part of the envelope faces, so the cutaway knows what is in the way.
    ///
    /// Windows, the entry door and the exterior backdrops have to travel with the wall
    /// they belong to. A hidden wall that leaves its glazing behind puts a black frame and
    /// a glowing city panel floating in mid-air in front of the room.
    private static let envelopeNormals: [String: SIMD3<Float>] = [
        "shell.wall.north": SIMD3(0, 0, -1),
        "shell.wall.south": SIMD3(0, 0, 1),
        "shell.wall.west.kitchen": SIMD3(-1, 0, 0),
        "shell.wall.west.living": SIMD3(-1, 0, 0),
        "shell.wall.east.entry": SIMD3(1, 0, 0),
        "shell.wall.east.living": SIMD3(1, 0, 0),
        "shell.window.eastA": SIMD3(1, 0, 0),
        "shell.window.eastB": SIMD3(1, 0, 0),
        "shell.window.south": SIMD3(0, 0, 1),
        "shell.door.entry": SIMD3(1, 0, 0),
        "shell.backdrop.east": SIMD3(1, 0, 0),
        "shell.backdrop.south": SIMD3(0, 0, 1),
        // Anything hung on a wall belongs to it too, or the picture is left hanging in
        // space once the wall behind it is culled.
        "living.art.pier": SIMD3(1, 0, 0),
        "living.art.abstract": SIMD3(-1, 0, 0)
    ]

    /// A closed room cannot be orbited from outside — the camera ends up above the ceiling
    /// looking at a lid. So the two exterior modes get a dollhouse cutaway: the ceiling
    /// goes, and whichever walls stand between the camera and the room go with it. Walking
    /// through the room is the one mode that wants the shell intact, because being enclosed
    /// is the whole point of standing inside it.
    func applyCutaway(mode: DemoCameraMode, cameraDirection: SIMD3<Float>) {
        let isDollhouse = mode != .walk
        ceilingEntity?.isEnabled = !isDollhouse

        let direction = simd_length(cameraDirection) > 1e-4
            ? simd_normalize(SIMD3(cameraDirection.x, 0, cameraDirection.z))
            : SIMD3<Float>(0, 0, 1)

        for (id, normal) in Self.envelopeNormals {
            guard let prop = props[id] else { continue }
            // Plan view looks straight down, so no wall is ever in front of the camera.
            let blocks = isDollhouse && mode == .orbit && simd_dot(normal, direction) > 0.34
            prop.entity.isEnabled = !blocks
        }
    }
}
