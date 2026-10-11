import Foundation
import RealityKit
import simd

// The unit of construction for the demo room.
//
// A `DemoProp` is one thing in the apartment: the sofa, the range, a wall, a wine bottle.
// It owns its geometry as a list of parts (each part being a mesh plus a material, so a
// chair can be walnut and leather at once) and it knows whether the earthquake is allowed
// to move it.
//
// The authoring convention that makes everything else work:
//
//   *Parts are built in the prop's own local space, with the origin at the centre of its
//   footprint, on the floor (y = 0).*
//
// That means `transform` is just "where in the apartment does this stand, and which way
// does it face" — and, more importantly, that a prop rotates about its own base when it
// topples, which is exactly the pivot a real object tips over.

struct DemoPart {
    var mesh: MeshAccumulator
    var material: PhysicallyBasedMaterial
    /// Parts that should not receive taps or cast shadows — glass panes, glow cards.
    var castsShadow: Bool = true

    init(_ mesh: MeshAccumulator, _ material: PhysicallyBasedMaterial, castsShadow: Bool = true) {
        self.mesh = mesh
        self.material = material
        self.castsShadow = castsShadow
    }
}

struct DemoProp {
    /// Stable identifier, used by the tour script and the object inspector.
    var id: String
    /// Shown in the UI when the object is selected or when it fails during the quake.
    var name: String
    var parts: [DemoPart]
    var transform: simd_float4x4

    var behaviour: Behaviour
    /// Category drives the risk copy and the shake response.
    var category: Category

    /// An explicit, compound collider in the prop's own local space.
    ///
    /// Left empty, `ApartmentScene` falls back to a single box taken from `localBounds`,
    /// which is right for a fridge and catastrophically wrong for anything with usable
    /// surfaces. A bookshelf's bounding box is a *solid* 0.98 × 2.32 × 0.34 block: nothing
    /// can stand on a shelf inside it, because the inside is full. Anything authored there
    /// either starts interpenetrating and is ejected on the first frame, or has to be
    /// welded into the shelf's own mesh — which is why, before this existed, none of the
    /// books on the shelf could ever fall off it.
    ///
    /// So shelved and open-frame furniture declares its own boxes: one per plank, one per
    /// upright. The plank tops then *are* real surfaces, and a mug authored at the plank's
    /// top face genuinely rests on it.
    var colliderBoxes: [ColliderBox] = []

    /// One box of a compound collider, in the prop's local frame.
    ///
    /// Deliberately axis-aligned and deliberately boxes: the failure mode this product
    /// cares about is toppling, and toppling is governed by the footprint and the centre of
    /// mass, not by surface detail. A rounded coffee table topples like the box that
    /// contains it.
    struct ColliderBox {
        /// Centre of the box in the prop's local space.
        var centre: SIMD3<Float>
        /// Full extents, not half — the same units `ShapeResource.generateBox` takes.
        var size: SIMD3<Float>

        init(centre: SIMD3<Float>, size: SIMD3<Float>) {
            self.centre = centre
            self.size = size
        }

        /// From the two opposite corners the modules already author geometry with.
        static func between(_ lo: SIMD3<Float>, _ hi: SIMD3<Float>) -> ColliderBox {
            ColliderBox(centre: (lo + hi) / 2, size: simd_abs(hi - lo))
        }

        static func span(
            x: ClosedRange<Float>, y: ClosedRange<Float>, z: ClosedRange<Float>
        ) -> ColliderBox {
            between(
                SIMD3(x.lowerBound, y.lowerBound, z.lowerBound),
                SIMD3(x.upperBound, y.upperBound, z.upperBound)
            )
        }

        /// A horizontal surface whose **top face sits exactly at `top`**.
        ///
        /// This is the one that matters. Author an object at `top` and it rests there with
        /// no gap to fall through and no overlap to be ejected from, which is the whole
        /// reason the boxes are declared rather than inferred.
        static func surface(
            x: ClosedRange<Float>, z: ClosedRange<Float>,
            top: Float, thickness: Float = 0.03
        ) -> ColliderBox {
            span(x: x, y: (top - thickness)...top, z: z)
        }

        /// A vertical member — a leg, a stile, a post — of constant section.
        static func post(
            at position: SIMD2<Float>, section: SIMD2<Float>,
            from bottom: Float, to top: Float
        ) -> ColliderBox {
            span(
                x: (position.x - section.x / 2)...(position.x + section.x / 2),
                y: bottom...top,
                z: (position.y - section.y / 2)...(position.y + section.y / 2)
            )
        }
    }

    enum Behaviour {
        /// Structure — floor, walls, ceiling, built-in cabinetry. Never moves.
        case fixed
        /// Free-standing furniture and objects. Mass in kg.
        case movable(mass: Double)
        /// Attached to a wall — art, upper cabinets. Moves with the building, can fall.
        case mounted(mass: Double)
    }

    enum Category: String {
        case structure, cabinetry, appliance, seating, table, storage
        case lighting, art, softFurnishing, tableware, decor, glazing
    }

    init(
        id: String,
        name: String,
        parts: [DemoPart],
        transform: simd_float4x4 = matrix_identity_float4x4,
        behaviour: Behaviour = .fixed,
        category: Category = .decor,
        colliderBoxes: [ColliderBox] = []
    ) {
        self.id = id
        self.name = name
        self.parts = parts
        self.transform = transform
        self.behaviour = behaviour
        self.category = category
        self.colliderBoxes = colliderBoxes
    }

    /// Convenience for the common single-material case.
    init(
        id: String,
        name: String,
        mesh: MeshAccumulator,
        material: PhysicallyBasedMaterial,
        transform: simd_float4x4 = matrix_identity_float4x4,
        behaviour: Behaviour = .fixed,
        category: Category = .decor,
        colliderBoxes: [ColliderBox] = []
    ) {
        self.init(
            id: id, name: name, parts: [DemoPart(mesh, material)],
            transform: transform, behaviour: behaviour, category: category,
            colliderBoxes: colliderBoxes
        )
    }

    var isMovable: Bool {
        if case .movable = behaviour { return true }
        return false
    }

    var mass: Double {
        switch behaviour {
        case .fixed: return .infinity
        case .movable(let m), .mounted(let m): return m
        }
    }

    /// Local-space bounds across every part. Used for the collider and for framing.
    var localBounds: (min: SIMD3<Float>, max: SIMD3<Float>) {
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var found = false
        for part in parts where !part.mesh.isEmpty {
            let b = part.mesh.bounds
            lo = simd_min(lo, b.min)
            hi = simd_max(hi, b.max)
            found = true
        }
        return found ? (lo, hi) : (.zero, .zero)
    }
}

// MARK: - Authoring helpers

extension DemoProp {
    /// Places a prop by its footprint centre on the floor, with an optional yaw.
    static func at(_ x: Float, _ z: Float, y: Float = 0, yaw: Float = 0) -> simd_float4x4 {
        Xf.place(x, y, z, yaw: yaw)
    }
}

/// A builder's shared signature. Each module in `Scene/` returns its props from one of
/// these, and `ApartmentScene` concatenates them.
@MainActor
protocol DemoModule {
    static func build(_ m: DemoMaterials) -> [DemoProp]
}
