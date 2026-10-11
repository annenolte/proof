import Foundation

/// Turns a scanned bounding box into a mass, and a scanned object into the
/// rigid block the solver integrates.
///
/// The estimate is deliberately anchored: it starts from an effective density
/// prior for the object type, multiplies by the measured bounding-box volume,
/// applies a loading multiplier, and then **clamps to the type's plausible mass
/// envelope**. That clamp is what makes the pipeline safe to put a language
/// model in front of — a hallucinated "800 kg bookshelf" is impossible, because
/// the model only ever chooses a *type*, and the type caps the mass.
public enum MassEstimator {

    /// Estimated mass in kg for an object type occupying a given bounding box.
    public static func mass(
        type: ObjectType,
        extents: Extents,
        loading: LoadingState = .partial
    ) -> Double {
        let raw = type.densityPrior * extents.volume
        // The catalogue's density priors describe a typically-loaded example, so
        // `.partial` reproduces the published mass exactly and the other states
        // scale around it. Objects with no contents ignore loading entirely.
        let loadFactor = type.respondsToLoading ? loading.multiplier : 1.0
        let range = type.massRange
        return min(max(raw * loadFactor, range.lowerBound), range.upperBound)
    }

    /// The centre-of-mass height for an object, accounting for anything stacked
    /// on top of it.
    ///
    /// A 16 kg television on a 95 kg dresser moves the combined centre of mass
    /// up by about 8 cm, which takes the slenderness ratio from 1.64 to 1.95 —
    /// enough to matter. Modelling the stack as one block is the conservative
    /// and honest treatment, and the app tells the user *why* the pairing is
    /// worse than either piece alone.
    public static func combinedCentreOfMassHeight(
        base: ScannedObject,
        stacked: [ScannedObject]
    ) -> Double {
        var momentSum = base.mass * base.centreOfMassHeight
        var massSum = base.mass
        for item in stacked {
            // The stacked item's centre of mass, measured from the base
            // object's own bottom.
            let height = Double(base.extents.height) + item.centreOfMassHeight
            momentSum += item.mass * height
            massSum += item.mass
        }
        return massSum > 0 ? momentSum / massSum : base.centreOfMassHeight
    }

    /// Builds the rigid block for the solver.
    ///
    /// - Parameters:
    ///   - object: the scanned object.
    ///   - room: the room it stands in, for the floor surface and geometry.
    ///   - friction: the friction pair to use. Pass a sampled pair when running
    ///     the ensemble; pass nil for the nominal design value.
    ///   - stacked: anything sitting on top of this object.
    public static func block(
        for object: ScannedObject,
        in room: ScannedRoom,
        friction: FrictionPair? = nil,
        stacked: [ScannedObject] = []
    ) -> RigidBlockSolver.Block {
        // An object on a shelf rubs against that shelf, not against the floor.
        let surface: FloorSurface = object.supportHeight > 0.05
            ? .woodShelf
            : room.building.floorSurface
        let pair = friction ?? FrictionDatabase.coefficient(
            footing: object.type.footing, on: surface)

        let totalMass = object.mass + stacked.reduce(0) { $0 + $1.mass }
        let comHeight = stacked.isEmpty
            ? object.centreOfMassHeight
            : combinedCentreOfMassHeight(base: object, stacked: stacked)

        return RigidBlockSolver.Block(
            halfWidth: object.extents.governingHalfWidth,
            comHeight: comHeight,
            mass: totalMass,
            staticFriction: pair.staticCoefficient,
            kineticFriction: pair.kineticCoefficient,
            isRestrained: !object.canMove,
            supportHeight: object.supportHeight,
            distanceToSupportEdge: distanceToSupportEdge(for: object, in: room)
        )
    }

    /// How far the object can slide before it runs out of support.
    ///
    /// On the floor this is effectively unbounded — a sliding wardrobe hits a
    /// wall, it does not fall off the world. On a shelf or a counter it is the
    /// real distance to the edge, and it is usually only a few centimetres,
    /// which is why shelf contents are the first thing to go in any quake.
    public static func distanceToSupportEdge(
        for object: ScannedObject,
        in room: ScannedRoom
    ) -> Double {
        guard object.supportHeight > 0.05 else {
            return .greatestFiniteMagnitude
        }
        if let supportID = object.supportedBy, let support = room.object(id: supportID) {
            // Distance from this object's edge to the support's edge, along the
            // support's shallower axis — the direction it will fall off first.
            let supportHalf = Double(min(support.extents.width, support.extents.depth)) / 2
            let objectHalf = Double(min(object.extents.width, object.extents.depth)) / 2
            return max(supportHalf - objectHalf, 0.01)
        }
        // On a shelf whose parent we did not resolve: assume a typical 0.3 m
        // deep shelf with the object roughly centred.
        let objectHalf = Double(min(object.extents.width, object.extents.depth)) / 2
        return max(0.15 - objectHalf, 0.02)
    }

    /// Objects sitting on top of a given object, resolved from the scan graph
    /// and from simple geometric containment when the scanner did not link them.
    public static func objectsStacked(on host: ScannedObject, in room: ScannedRoom) -> [ScannedObject] {
        room.objects.filter { candidate in
            guard candidate.id != host.id else { return false }
            if candidate.supportedBy == host.id { return true }
            guard candidate.supportedBy == nil else { return false }
            // Sitting at roughly the host's top height, and horizontally inside
            // the host's footprint.
            let hostTop = Double(host.placement.centre.y) + Double(host.extents.height) / 2
            let candidateBottom = Double(candidate.placement.centre.y) - Double(candidate.extents.height) / 2
            guard abs(candidateBottom - hostTop) < 0.12 else { return false }
            let dx = abs(candidate.placement.centre.x - host.placement.centre.x)
            let dz = abs(candidate.placement.centre.z - host.placement.centre.z)
            return dx < host.extents.width / 2 && dz < host.extents.depth / 2
        }
    }
}
