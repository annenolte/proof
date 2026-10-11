import Foundation
import RealityKit
import simd
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Components

/// Marks an entity as the physics body for one scanned object, so a tap or a
/// scene walk can recover the object identity without a side table.
public struct StageBodyComponent: Component {
    public var objectID: UUID
    public init(objectID: UUID) { self.objectID = objectID }
}

/// Marks the static architecture — floor, wall segments, opening panels.
public struct StageArchitectureComponent: Component {
    public enum Kind: String, Sendable {
        case floor, wall, window, door, opening, ceiling, grid
    }
    public var kind: Kind
    public init(kind: Kind) { self.kind = kind }
}

// MARK: - Scene builder

/// Turns a `ScannedRoom` into a RealityKit scene: a floor, walls with real
/// cut-outs for windows and doors, and one physics body per object, sized from
/// its `Extents` and placed from its `Placement`.
///
/// The builder is pure with respect to physics: every mass, friction
/// coefficient, inertia and centre-of-mass offset comes from the `BodySpec`s in
/// the `SimulationScenario`, which in turn come from `MassEstimator` and
/// `FrictionDatabase`. Nothing is invented here.
@MainActor
public enum SceneBuilder {

    // MARK: Options

    public struct Options: Sendable {
        public var palette: StagePalette
        /// Tint objects by their risk band when an assessment is available.
        public var tintByRisk: Bool
        public var showGrid: Bool
        public var castShadows: Bool
        /// Wall thickness for the static boxes, metres. Scanned walls are
        /// reported ~1 cm thick, which is below the engine's contact margin
        /// comfort zone, so the stage gives them a believable 8 cm.
        public var wallThicknessM: Float
        public var solverPositionIterations: Int
        public var solverVelocityIterations: Int
        /// Smallest dimension any collider is allowed to have. Below ~2 cm
        /// RealityKit's contact margin dominates (research §3.3).
        public var minimumColliderDimensionM: Float

        public init(
            palette: StagePalette = .stage,
            tintByRisk: Bool = true,
            showGrid: Bool = true,
            castShadows: Bool = true,
            wallThicknessM: Float = 0.08,
            solverPositionIterations: Int = 16,
            solverVelocityIterations: Int = 8,
            minimumColliderDimensionM: Float = 0.02
        ) {
            self.palette = palette
            self.tintByRisk = tintByRisk
            self.showGrid = showGrid
            self.castShadows = castShadows
            self.wallThicknessM = wallThicknessM
            self.solverPositionIterations = solverPositionIterations
            self.solverVelocityIterations = solverVelocityIterations
            self.minimumColliderDimensionM = minimumColliderDimensionM
        }

        public static let `default` = Options()
    }

    // MARK: Result

    /// The built scene. Everything the simulator and the view need, and nothing
    /// they have to go looking for.
    @MainActor
    public final class Stage {
        /// The anchor to hand to `RealityView`'s content.
        public let anchor: AnchorEntity
        /// The entity carrying `PhysicsSimulationComponent`. All bodies and all
        /// architecture are descendants of this.
        public let simulationRoot: Entity
        /// Non-simulated decoration: the ground grid.
        public let decorationRoot: Entity
        public let lightingRoot: Entity
        /// One entity per scanned object, keyed by object id.
        public private(set) var bodies: [UUID: ModelEntity]
        /// Static architecture, in build order.
        public private(set) var architecture: [ModelEntity]
        /// The transform each body started at, for measuring displacement and
        /// for `restart()`.
        public private(set) var initialTransforms: [UUID: Transform]
        /// Axis-aligned bounds of the room, used to frame the camera.
        public let roomBounds: BoundingBox
        public let palette: StagePalette

        private var selectionHalos: [UUID: Entity] = [:]

        init(
            anchor: AnchorEntity,
            simulationRoot: Entity,
            decorationRoot: Entity,
            lightingRoot: Entity,
            bodies: [UUID: ModelEntity],
            architecture: [ModelEntity],
            initialTransforms: [UUID: Transform],
            selectionHalos: [UUID: Entity],
            roomBounds: BoundingBox,
            palette: StagePalette
        ) {
            self.anchor = anchor
            self.simulationRoot = simulationRoot
            self.decorationRoot = decorationRoot
            self.lightingRoot = lightingRoot
            self.bodies = bodies
            self.architecture = architecture
            self.initialTransforms = initialTransforms
            self.selectionHalos = selectionHalos
            self.roomBounds = roomBounds
            self.palette = palette
        }

        /// The object id an arbitrary tapped entity belongs to, walking up the
        /// hierarchy so hits on child meshes still resolve.
        public func objectID(for entity: Entity?) -> UUID? {
            var node: Entity? = entity
            while let current = node {
                if let marker = current.components[StageBodyComponent.self] {
                    return marker.objectID
                }
                node = current.parent
            }
            return nil
        }

        /// Shows the `fearless` selection halo on one object, hiding all others.
        public func setSelection(_ id: UUID?) {
            for (key, halo) in selectionHalos {
                halo.isEnabled = (key == id)
            }
        }

        /// Puts every body back where it started and clears its velocity.
        public func resetTransforms() {
            for (id, entity) in bodies {
                guard let start = initialTransforms[id] else { continue }
                entity.transform = start
                if entity.components.has(PhysicsMotionComponent.self) {
                    entity.components.set(PhysicsMotionComponent())
                }
                entity.resetPhysicsTransform(recursive: false)
            }
        }
    }

    // MARK: Build

    public static func build(
        room: ScannedRoom,
        scenario: SimulationScenario?,
        options: Options = .default
    ) -> Stage {
        registerComponentsIfNeeded()

        let palette = options.palette
        let anchor = AnchorEntity(world: .zero)

        let simulationRoot = Entity()
        simulationRoot.name = "simulationRoot"
        var simulation = PhysicsSimulationComponent()
        simulation.gravity = SIMD3(0, Float(-Physics.g), 0)
        simulation.solverIterations = .init(
            positionIterations: options.solverPositionIterations,
            velocityIterations: options.solverVelocityIterations)
        simulationRoot.components.set(simulation)
        anchor.addChild(simulationRoot)

        let decorationRoot = Entity()
        decorationRoot.name = "decoration"
        anchor.addChild(decorationRoot)

        let lightingRoot = Entity()
        lightingRoot.name = "lighting"
        anchor.addChild(lightingRoot)

        let bounds = roomBounds(for: room)
        var architecture: [ModelEntity] = []

        // ---- Floor -------------------------------------------------------
        // Neutral, *not* the floor finish's own coefficient: RealityKit
        // multiplies the two contacting materials, so a supporting surface must
        // present 1.0 for the moving body's analytic μ to survive the combine.
        // Each object carries the real footing × floor-finish pair.
        let floorMaterial = PhysicsMaterialResource.generate(
            staticFriction: 1.0, dynamicFriction: 1.0, restitution: 0.0)

        let floorSpan = SIMD3<Float>(
            max(bounds.max.x - bounds.min.x, 1) + 0.6,
            0.16,
            max(bounds.max.z - bounds.min.z, 1) + 0.6)
        let floor = makeStaticBox(
            size: floorSpan,
            position: SIMD3(
                (bounds.min.x + bounds.max.x) / 2,
                -floorSpan.y / 2,
                (bounds.min.z + bounds.max.z) / 2),
            orientation: simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)),
            colour: palette.floor,
            roughness: 0.92,
            physicsMaterial: floorMaterial,
            kind: .floor,
            options: options)
        floor.name = "floor"
        simulationRoot.addChild(floor)
        architecture.append(floor)

        // ---- Walls, with the openings actually cut out --------------------
        let wallPhysics = PhysicsMaterialResource.generate(
            staticFriction: 1.0, dynamicFriction: 1.0, restitution: 0.0)
        let openings = room.surfaces.filter {
            $0.kind == .window || $0.kind == .door || $0.kind == .opening
        }

        for wall in room.walls {
            let frame = Frame(placement: wall.placement)
            let wallWidth = wall.extents.width
            let wallHeight = wall.extents.height
            var rects = [Rect(u0: -wallWidth / 2, u1: wallWidth / 2, v0: 0, v1: wallHeight)]

            for opening in openings {
                guard let local = localRect(of: opening, on: wall, frame: frame) else { continue }
                rects = rects.flatMap { subtract($0, local) }
            }

            for rect in rects where rect.width > 0.03 && rect.height > 0.03 {
                let centreLocal = SIMD3<Float>(rect.midU, rect.midV - wallHeight / 2, 0)
                let segment = makeStaticBox(
                    size: SIMD3(rect.width, rect.height, options.wallThicknessM),
                    position: wall.placement.centre + frame.rotation.act(centreLocal),
                    orientation: frame.rotation,
                    colour: palette.wall,
                    roughness: 0.88,
                    physicsMaterial: wallPhysics,
                    kind: .wall,
                    options: options)
                segment.name = "wall"
                simulationRoot.addChild(segment)
                architecture.append(segment)
            }
        }

        // ---- Opening panels: glass, door leaves, open thresholds ----------
        for opening in openings {
            let frame = Frame(placement: opening.placement)
            let colour: StageColor
            let kind: StageArchitectureComponent.Kind
            switch opening.kind {
            case .window: colour = palette.window; kind = .window
            case .door: colour = palette.door; kind = .door
            default: colour = palette.wallTrim; kind = .opening
            }
            // An open door, or an opening with no leaf, is drawn as a recessed
            // reveal rather than a solid panel — visually distinct either way.
            let thickness: Float = (opening.kind == .door && opening.isOpen) ? 0.012 : 0.03
            let panel = makeDecorativeBox(
                size: SIMD3(opening.extents.width, opening.extents.height, thickness),
                position: opening.placement.centre,
                orientation: frame.rotation,
                colour: colour,
                roughness: opening.kind == .window ? 0.12 : 0.80,
                metallic: 0,
                kind: kind)
            panel.name = opening.kind.rawValue
            simulationRoot.addChild(panel)
            architecture.append(panel)

            // A slim reveal frame so the cut-out reads even against a dark wall.
            let reveal = makeDecorativeBox(
                size: SIMD3(
                    opening.extents.width + 0.09,
                    opening.extents.height + 0.09,
                    options.wallThicknessM * 0.6),
                position: opening.placement.centre,
                orientation: frame.rotation,
                colour: palette.wallTrim,
                roughness: 0.85,
                metallic: 0,
                kind: kind)
            reveal.name = "\(opening.kind.rawValue).reveal"
            simulationRoot.addChild(reveal)
            architecture.append(reveal)
        }

        // ---- Objects -----------------------------------------------------
        var bodies: [UUID: ModelEntity] = [:]
        var initialTransforms: [UUID: Transform] = [:]
        var halos: [UUID: Entity] = [:]

        let specs = scenario?.bodies ?? fallbackSpecs(for: room)
        for spec in specs {
            let (entity, halo) = makeBody(spec: spec, options: options)
            simulationRoot.addChild(entity)
            bodies[spec.id] = entity
            initialTransforms[spec.id] = entity.transform
            halos[spec.id] = halo
        }

        // ---- Ground grid --------------------------------------------------
        if options.showGrid {
            decorationRoot.addChild(makeGrid(bounds: bounds, palette: palette))
        }

        // ---- Lighting ------------------------------------------------------
        addLighting(to: lightingRoot, bounds: bounds, castShadows: options.castShadows)

        return Stage(
            anchor: anchor,
            simulationRoot: simulationRoot,
            decorationRoot: decorationRoot,
            lightingRoot: lightingRoot,
            bodies: bodies,
            architecture: architecture,
            initialTransforms: initialTransforms,
            selectionHalos: halos,
            roomBounds: bounds,
            palette: palette)
    }

    /// Adds an image-based light if one ships in the bundle. Optional by
    /// design: the directional rig alone is a complete, shippable look, and a
    /// missing asset must never take the stage down.
    public static func applyImageBasedLight(to stage: Stage, named name: String = "studio") async {
        guard let resource = try? await EnvironmentResource(named: name) else { return }
        let iblEntity = Entity()
        iblEntity.name = "ibl"
        var component = ImageBasedLightComponent(source: .single(resource), intensityExponent: 0.9)
        component.inheritsRotation = false
        iblEntity.components.set(component)
        stage.lightingRoot.addChild(iblEntity)

        let receiver = ImageBasedLightReceiverComponent(imageBasedLight: iblEntity)
        for entity in stage.bodies.values { entity.components.set(receiver) }
        for entity in stage.architecture { entity.components.set(receiver) }
    }

    // MARK: - Bodies

    private static func makeBody(
        spec: BodySpec, options: Options
    ) -> (ModelEntity, Entity) {
        let visualSize = spec.sizeM
        let colliderSize = SIMD3<Float>(
            max(visualSize.x, options.minimumColliderDimensionM),
            max(visualSize.y, options.minimumColliderDimensionM),
            max(visualSize.z, options.minimumColliderDimensionM))

        let radius = min(min(visualSize.x, min(visualSize.y, visualSize.z)) * 0.06, 0.012)
        let mesh = MeshResource.generateBox(size: visualSize, cornerRadius: max(radius, 0))
        let material = StageMaterials.object(
            type: spec.type,
            band: options.tintByRisk ? spec.riskBand : nil,
            palette: options.palette)

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = spec.displayName

        // --- collision + physics, all numbers from the BodySpec ---
        let shape = ShapeResource.generateBox(size: colliderSize)
        entity.components.set(CollisionComponent(shapes: [shape]))

        var massProperties = PhysicsMassProperties(
            mass: Float(spec.massKg),
            inertia: spec.inertiaKgM2,
            centerOfMass: (
                position: spec.centreOfMassOffset,
                orientation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)))
        // Guard against a degenerate inertia on hairline-thin objects.
        massProperties.inertia = simd_max(massProperties.inertia, SIMD3(repeating: 1e-5))

        // `stageStaticFriction`, not `staticFriction`: RealityKit multiplies the
        // two materials at a contact, and supporting surfaces are neutral, so
        // this is the value that makes the *solved* contact equal the analytic
        // pair. See `BodySpec.stageStaticFriction`.
        let contact = PhysicsMaterialResource.generate(
            staticFriction: Float(spec.stageStaticFriction),
            dynamicFriction: Float(spec.stageKineticFriction),
            restitution: Float(max(0, min(spec.restitution, 0.4))))

        var body = PhysicsBodyComponent(
            massProperties: massProperties,
            material: contact,
            mode: spec.startsDynamic ? .dynamic : .kinematic)
        body.isAffectedByGravity = true
        // Non-zero damping bleeds energy and makes sliding distances come out
        // systematically short (research §3.8).
        body.linearDamping = 0
        body.angularDamping = 0
        // CCD only for small fast debris; a 1 m/s wardrobe moves 1.7 cm a step.
        body.isContinuousCollisionDetectionEnabled =
            min(visualSize.x, min(visualSize.y, visualSize.z)) < 0.15

        entity.components.set(body)
        entity.components.set(PhysicsMotionComponent())
        entity.components.set(StageBodyComponent(objectID: spec.id))
        entity.components.set(InputTargetComponent())
        if options.castShadows {
            entity.components.set(GroundingShadowComponent(castsShadow: true))
        }

        entity.position = spec.placement.centre
        entity.orientation = Frame(placement: spec.placement).rotation

        // --- selection halo ---
        let halo = makeSelectionHalo(size: visualSize, palette: options.palette)
        halo.isEnabled = false
        entity.addChild(halo)

        return (entity, halo)
    }

    private static func makeSelectionHalo(
        size: SIMD3<Float>, palette: StagePalette
    ) -> Entity {
        let inflated = size + SIMD3<Float>(repeating: 0.035)
        #if canImport(UIKit)
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: palette.selection.uiColor)
        material.emissiveColor = .init(color: palette.selection.uiColor)
        material.emissiveIntensity = 0.8
        material.roughness = 1.0
        material.metallic = 0.0
        // Render only the inside faces so the halo reads as an outline rather
        // than a fog over the object.
        material.faceCulling = .front
        material.blending = .transparent(opacity: .init(floatLiteral: 0.55))
        let entity = ModelEntity(
            mesh: .generateBox(size: inflated, cornerRadius: 0.012),
            materials: [material])
        #else
        let entity = ModelEntity(mesh: .generateBox(size: inflated))
        #endif
        entity.name = "selection"
        return entity
    }

    /// Specs for a room with no scenario — the idle S-12 room viewer. Physics
    /// values still come from `MassEstimator`, so a scene built without an
    /// assessment is identical apart from the tint.
    public static func fallbackSpecs(for room: ScannedRoom) -> [BodySpec] {
        SimulationScenario.build(
            room: room, assessment: nil,
            motion: GroundMotion.quiet(duration: 0.05)
        ).bodies
    }

    // MARK: - Architecture primitives

    private static func makeStaticBox(
        size: SIMD3<Float>,
        position: SIMD3<Float>,
        orientation: simd_quatf,
        colour: StageColor,
        roughness: Float,
        physicsMaterial: PhysicsMaterialResource,
        kind: StageArchitectureComponent.Kind,
        options: Options
    ) -> ModelEntity {
        let clamped = SIMD3<Float>(
            max(size.x, options.minimumColliderDimensionM),
            max(size.y, options.minimumColliderDimensionM),
            max(size.z, options.minimumColliderDimensionM))
        let entity = ModelEntity(
            mesh: .generateBox(size: clamped),
            materials: [StageMaterials.matte(colour, roughness: roughness)])
        entity.components.set(
            CollisionComponent(shapes: [.generateBox(size: clamped)]))
        entity.components.set(PhysicsBodyComponent(
            massProperties: .default, material: physicsMaterial, mode: .static))
        entity.components.set(StageArchitectureComponent(kind: kind))
        entity.position = position
        entity.orientation = orientation
        return entity
    }

    private static func makeDecorativeBox(
        size: SIMD3<Float>,
        position: SIMD3<Float>,
        orientation: simd_quatf,
        colour: StageColor,
        roughness: Float,
        metallic: Float,
        kind: StageArchitectureComponent.Kind
    ) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateBox(size: size),
            materials: [StageMaterials.matte(colour, roughness: roughness, metallic: metallic)])
        entity.components.set(StageArchitectureComponent(kind: kind))
        entity.position = position
        entity.orientation = orientation
        return entity
    }

    private static func makeGrid(bounds: BoundingBox, palette: StagePalette) -> Entity {
        let root = Entity()
        root.name = "grid"
        root.components.set(StageArchitectureComponent(kind: .grid))

        let spacing: Float = 0.5
        let width = max(bounds.max.x - bounds.min.x, 1) + 0.6
        let depth = max(bounds.max.z - bounds.min.z, 1) + 0.6
        let centre = SIMD3<Float>(
            (bounds.min.x + bounds.max.x) / 2, 0.004, (bounds.min.z + bounds.max.z) / 2)

        let material = StageMaterials.matte(palette.grid, roughness: 1.0)
        let lineThickness: Float = 0.006

        let columns = min(Int((width / spacing).rounded()) + 1, 32)
        let rows = min(Int((depth / spacing).rounded()) + 1, 32)

        for index in 0..<columns {
            let x = centre.x - width / 2 + Float(index) * (width / Float(max(columns - 1, 1)))
            let line = ModelEntity(
                mesh: .generateBox(size: SIMD3(lineThickness, 0.002, depth)),
                materials: [material])
            line.position = SIMD3(x, centre.y, centre.z)
            root.addChild(line)
        }
        for index in 0..<rows {
            let z = centre.z - depth / 2 + Float(index) * (depth / Float(max(rows - 1, 1)))
            let line = ModelEntity(
                mesh: .generateBox(size: SIMD3(width, 0.002, lineThickness)),
                materials: [material])
            line.position = SIMD3(centre.x, centre.y, z)
            root.addChild(line)
        }
        return root
    }

    private static func addLighting(to root: Entity, bounds: BoundingBox, castShadows: Bool) {
        let centre = SIMD3<Float>(
            (bounds.min.x + bounds.max.x) / 2, 0, (bounds.min.z + bounds.max.z) / 2)
        let span = max(
            max(bounds.max.x - bounds.min.x, bounds.max.z - bounds.min.z), 3)

        // Key light: warm, high, from the front-left, with real shadows.
        let key = Entity()
        key.name = "keyLight"
        #if canImport(UIKit)
        let keyLight = DirectionalLightComponent(
            color: UIColor(red: 1.0, green: 0.96, blue: 0.90, alpha: 1),
            intensity: 5_200)
        #else
        let keyLight = DirectionalLightComponent(intensity: 5_200)
        #endif
        key.components.set(keyLight)
        if castShadows {
            key.components.set(DirectionalLightComponent.Shadow())
        }
        key.look(
            at: centre,
            from: centre + SIMD3(-span * 0.7, span * 1.25, span * 0.85),
            relativeTo: nil)
        root.addChild(key)

        // Cool fill from the opposite side, so shadowed faces are readable.
        let fill = Entity()
        fill.name = "fillLight"
        #if canImport(UIKit)
        let fillLight = DirectionalLightComponent(
            color: UIColor(red: 0.82, green: 0.86, blue: 1.0, alpha: 1),
            intensity: 1_500)
        #else
        let fillLight = DirectionalLightComponent(intensity: 1_500)
        #endif
        fill.components.set(fillLight)
        fill.look(
            at: centre,
            from: centre + SIMD3(span * 0.9, span * 0.5, -span * 0.7),
            relativeTo: nil)
        root.addChild(fill)

        // A dim up-light keeps undersides from going pure black.
        let bounce = Entity()
        bounce.name = "bounceLight"
        #if canImport(UIKit)
        let bounceLight = DirectionalLightComponent(
            color: UIColor(red: 0.92, green: 0.90, blue: 0.95, alpha: 1),
            intensity: 620)
        #else
        let bounceLight = DirectionalLightComponent(intensity: 620)
        #endif
        bounce.components.set(bounceLight)
        bounce.look(
            at: centre + SIMD3(0, 1.2, 0),
            from: centre + SIMD3(0.2, -span * 0.4, 0.2),
            relativeTo: nil)
        root.addChild(bounce)
    }

    // MARK: - Geometry helpers

    /// The room's axis-aligned bounds, from the wall endpoints and the ceiling.
    public static func roomBounds(for room: ScannedRoom) -> BoundingBox {
        var minPoint = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxPoint = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var sawAnything = false

        func include(_ point: SIMD3<Float>) {
            minPoint = simd_min(minPoint, point)
            maxPoint = simd_max(maxPoint, point)
            sawAnything = true
        }

        for wall in room.walls {
            let frame = Frame(placement: wall.placement)
            let axis = frame.rotation.act(SIMD3<Float>(1, 0, 0))
            let half = axis * (wall.extents.width / 2)
            let base = SIMD3(wall.placement.centre.x, 0, wall.placement.centre.z)
            include(base - half)
            include(base + half)
            include(SIMD3(
                wall.placement.centre.x,
                wall.placement.centre.y + wall.extents.height / 2,
                wall.placement.centre.z))
        }
        for object in room.objects {
            let c = object.placement.centre
            let e = object.extents.simd
            let reach = max(e.x, max(e.y, e.z)) / 2
            include(c - SIMD3(repeating: reach))
            include(c + SIMD3(repeating: reach))
        }
        if !sawAnything {
            return BoundingBox(min: SIMD3(-2, 0, -2), max: SIMD3(2, 2.4, 2))
        }
        minPoint.y = min(minPoint.y, 0)
        maxPoint.y = max(maxPoint.y, Float(room.ceilingHeight))
        return BoundingBox(min: minPoint, max: maxPoint)
    }

    /// A placement's rotation, taken from `Placement.transform` itself so the
    /// stage can never disagree with the model about which way an object faces.
    struct Frame {
        let rotation: simd_quatf

        /// Built from `Placement.stageBasis`, which is the convention the app
        /// actually stores — **not** from `Placement.transform`, which is its
        /// mirror image. See the note on `Placement` in `SimulationScenario`.
        init(placement: Placement) {
            self.rotation = placement.stageRotation
        }

        /// World → local for a point.
        func localPoint(_ world: SIMD3<Float>, origin: SIMD3<Float>) -> SIMD3<Float> {
            rotation.inverse.act(world - origin)
        }
    }

    /// A rectangle on a wall's surface: `u` runs along the wall's width from its
    /// centre, `v` runs up from the wall's base.
    struct Rect {
        var u0: Float
        var u1: Float
        var v0: Float
        var v1: Float

        var width: Float { u1 - u0 }
        var height: Float { v1 - v0 }
        var midU: Float { (u0 + u1) / 2 }
        var midV: Float { (v0 + v1) / 2 }
    }

    /// Where an opening sits on a wall, or nil if it belongs to a different one.
    static func localRect(
        of opening: RoomSurface, on wall: RoomSurface, frame: Frame
    ) -> Rect? {
        let local = frame.localPoint(opening.placement.centre, origin: wall.placement.centre)
        // Must lie in the wall's plane…
        guard abs(local.z) < 0.35 else { return nil }
        // …and within its run, allowing a little overhang.
        guard abs(local.x) <= wall.extents.width / 2 + 0.15 else { return nil }

        let wallBase = wall.placement.centre.y - wall.extents.height / 2
        let openingBase = opening.placement.centre.y - opening.extents.height / 2
        let v0 = openingBase - wallBase
        return Rect(
            u0: local.x - opening.extents.width / 2,
            u1: local.x + opening.extents.width / 2,
            v0: v0,
            v1: v0 + opening.extents.height)
    }

    /// `rect` minus `hole`, as up to four rectangles. The cut-out that makes a
    /// wall read as a wall with a window in it rather than a wall with a poster
    /// stuck on it.
    static func subtract(_ rect: Rect, _ hole: Rect) -> [Rect] {
        let overlapsU = hole.u0 < rect.u1 && hole.u1 > rect.u0
        let overlapsV = hole.v0 < rect.v1 && hole.v1 > rect.v0
        guard overlapsU && overlapsV else { return [rect] }

        var pieces: [Rect] = []
        if hole.u0 > rect.u0 {
            pieces.append(Rect(u0: rect.u0, u1: min(hole.u0, rect.u1), v0: rect.v0, v1: rect.v1))
        }
        if hole.u1 < rect.u1 {
            pieces.append(Rect(u0: max(hole.u1, rect.u0), u1: rect.u1, v0: rect.v0, v1: rect.v1))
        }
        let bandU0 = max(rect.u0, hole.u0)
        let bandU1 = min(rect.u1, hole.u1)
        if bandU1 > bandU0 {
            if hole.v0 > rect.v0 {
                pieces.append(Rect(u0: bandU0, u1: bandU1, v0: rect.v0, v1: min(hole.v0, rect.v1)))
            }
            if hole.v1 < rect.v1 {
                pieces.append(Rect(u0: bandU0, u1: bandU1, v0: max(hole.v1, rect.v0), v1: rect.v1))
            }
        }
        return pieces.filter { $0.width > 0.01 && $0.height > 0.01 }
    }

    // MARK: - Component registration

    private static var didRegisterComponents = false

    static func registerComponentsIfNeeded() {
        guard !didRegisterComponents else { return }
        didRegisterComponents = true
        StageBodyComponent.registerComponent()
        StageArchitectureComponent.registerComponent()
    }
}
