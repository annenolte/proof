//
//  SafetyModel.swift
//  proof — Core / Safety
//
//  The data model of CLAUDE.md §6, as values.
//
//  Everything here is plain, Codable and free of RealityKit, so the analysis engine can be
//  unit tested on synthetic scenes and run on the bundled kitchen package without building
//  a single mesh. The 3D room is one *source* of these values (`ScenePackageBuilder`); the
//  bundled `kitchen.scene.json` is another. The engine does not know which it was given.
//
//  Coordinates: metres, y up, the floor at y = 0. The same frame the kitchen is authored in.
//

import Foundation
import simd

// MARK: - Geometry

/// An axis-aligned box in metres.
struct AABB: Codable, Hashable, Sendable {
    var min: SIMD3<Float>
    var max: SIMD3<Float>

    var centre: SIMD3<Float> { (min + max) / 2 }
    var size: SIMD3<Float> { max - min }

    /// Horizontal (x/z) distance between two footprints. Zero when they overlap.
    func footprintGap(to other: AABB) -> Float {
        let dx = Swift.max(0, Swift.max(other.min.x - max.x, min.x - other.max.x))
        let dz = Swift.max(0, Swift.max(other.min.z - max.z, min.z - other.max.z))
        return (dx * dx + dz * dz).squareRoot()
    }

    /// The narrower of the two horizontal dimensions.
    var footprintMinor: Float { Swift.min(size.x, size.z) }
}

// MARK: - Vocabulary

/// What an object is to a small child. From the concept catalog, never from the LLM.
enum ObjectRole: String, Codable, CaseIterable, Sendable {
    /// Something to keep a child away from.
    case hazard
    /// A surface a child could stand or kneel on.
    case climbable
    case both
    /// Present in the scan, not a flag.
    case neutral

    var isHazard: Bool { self == .hazard || self == .both }
    var isClimbable: Bool { self == .climbable || self == .both }
}

/// Hazard categories of CLAUDE.md §7a. Wording lives here once so the list, the sky, the
/// export and the fix plans cannot disagree about what a category is called.
enum HazardKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case heat
    case sharp
    case chemicals
    case choking
    case cords
    case tipOver
    case falls
    case water
    case breakable
    case corners

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heat: return "Heat and burns"
        case .sharp: return "Sharp items"
        case .chemicals: return "Cabinets and chemicals"
        case .choking: return "Small objects"
        case .cords: return "Cords and outlets"
        case .tipOver: return "Tip-over"
        case .falls: return "Falls"
        case .water: return "Water"
        case .breakable: return "Glass and breakables"
        case .corners: return "Corners and edges"
        }
    }

    var symbol: String {
        switch self {
        case .heat: return "flame.fill"
        case .sharp: return "scissors"
        case .chemicals: return "flask.fill"
        case .choking: return "circle.grid.cross.fill"
        case .cords: return "powerplug.fill"
        case .tipOver: return "arrow.down.forward.square.fill"
        case .falls: return "figure.fall"
        case .water: return "drop.fill"
        case .breakable: return "wineglass.fill"
        case .corners: return "square.dashed"
        }
    }

    /// Generic fix types only. No brands, no product links (CLAUDE.md §7a.2).
    var fixTypes: [String] {
        switch self {
        case .heat: return ["Stove knob covers", "Stove guard", "Cook on the back burners, handles turned in"]
        case .sharp: return ["Move sharp items above reach", "Latch the drawer they live in"]
        case .chemicals: return ["Cabinet latch", "Move cleaning products up high"]
        case .choking: return ["Move small items above reach"]
        case .cords: return ["Route cords out of reach", "Outlet covers"]
        case .tipOver: return ["Anchor furniture to the wall"]
        case .falls: return ["Move climbable furniture away", "Push chairs in under the table"]
        case .water: return ["Keep basins empty", "Supervise near water"]
        case .breakable: return ["Move breakables above reach or to the middle of the surface"]
        case .corners: return ["Corner guards"]
        }
    }
}

// MARK: - Scene package

/// One object found in the scan. A star in the sky.
struct SceneObject: Codable, Hashable, Identifiable, Sendable {
    enum Source: String, Codable, Sendable {
        /// Found by the pipeline (SAM 3 concept → lifted to 3D).
        case auto
        /// Added by the caregiver in the Craft step.
        case userAdded
    }

    var id: String
    var label: String
    /// The SAM 3 noun phrase that found it.
    var concept: String
    var role: ObjectRole
    var hazards: [HazardKind]
    /// World bounds in metres.
    var aabb: AABB
    /// Heights of the horizontal surfaces a child could stand on, from the model's authored
    /// dimensions. Empty for anything not climbable. A chair's bounding box tops out at its
    /// backrest; its *seat* is the step that matters.
    var surfaces: [Float]
    var source: Source
    /// Detection confidence when the pipeline reports one. `nil` for authored scenes.
    var confidence: Double?

    var topHeight: Float { aabb.max.y }
    var lowestPoint: Float { aabb.min.y }
    var centroid: SIMD3<Float> { aabb.centre }
    /// Where the star is drawn: just above the middle of the object's top.
    var starPosition: SIMD3<Float> { SIMD3(aabb.centre.x, aabb.max.y + 0.04, aabb.centre.z) }
}

/// The prepared scene: what CLAUDE.md §4 calls `scene.json`.
struct ScenePackage: Codable, Sendable {
    var name: String
    /// Plain statement of where this package came from, shown in the UI.
    var provenance: String
    var objects: [SceneObject]

    func object(_ id: String) -> SceneObject? { objects.first { $0.id == id } }
}

// MARK: - Analysis output

/// A measured relationship between two objects (or the floor and an object).
struct Relation: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// A child on `from` could reach `to`.
        case reach
        /// A child could step from `from` up onto `to`.
        case climbStep
        /// Two hazards close together.
        case cluster
        /// A user-drawn link with no measurement behind it.
        case userLink
    }
    enum Origin: String, Codable, Sendable { case engine, userDrawn }

    var id: String
    var kind: Kind
    /// `nil` means the floor.
    var fromID: String?
    var toID: String
    /// Rise in metres from the standing surface (climb) or to the hazard's lowest point (reach).
    var rise: Float?
    /// Horizontal gap in metres between the two footprints.
    var gap: Float?
    /// Surface height the step lands on, or the height stood on for a reach.
    var surfaceHeight: Float?
    var origin: Origin

    static func makeID(_ kind: Kind, _ from: String?, _ to: String, _ surface: Float? = nil) -> String {
        let s = surface.map { String(format: "@%.2f", $0) } ?? ""
        return "\(kind.rawValue):\(from ?? "floor")->\(to)\(s)"
    }
}

/// A path from the floor, up through climbable surfaces, to a hazard.
struct Chain: Codable, Hashable, Identifiable, Sendable {
    var id: String
    /// Object ids in order, floor excluded. The last one is the hazard.
    var nodeIDs: [String]
    var relations: [Relation]
    /// Built from the measured values, never written by a model.
    var why: String

    var hazardID: String { nodeIDs.last ?? "" }
    var stepCount: Int { nodeIDs.count - 1 }
}

/// How a hazard can be reached at the current age stage.
enum Reachability: Codable, Hashable, Sendable {
    case fromFloor
    case viaChain(chainID: String)
    case notReached

    var summary: String {
        switch self {
        case .fromFloor: return "Within reach from the floor"
        case .viaChain: return "Reachable by climbing"
        case .notReached: return "Not reachable at this stage, by this geometry"
        }
    }
}

/// One thing to check.
struct Flag: Codable, Hashable, Identifiable, Sendable {
    enum DetectedBy: String, Codable, Sendable {
        /// Category from the object's concept; position from the scan.
        case concept
        /// Computed from bounds (corners, tip-over).
        case engineGeometry
        case userAdded
    }

    var id: String
    var objectID: String
    var kind: HazardKind
    var label: String
    var detail: String
    var detectedBy: DetectedBy
    var reachability: Reachability
    var fixTypes: [String]
    /// True for flags the engine can only guess at — tip-over, corners. Labelled in the UI.
    var isHeuristic: Bool
}

/// Everything the engine produces for one scene at one age stage.
struct SafetyAnalysis: Sendable {
    var parameters: SafetyParameters
    var objects: [SceneObject]
    var relations: [Relation]
    var chains: [Chain]
    var flags: [Flag]

    func object(_ id: String) -> SceneObject? { objects.first { $0.id == id } }
    func chain(_ id: String) -> Chain? { chains.first { $0.id == id } }
    func flags(for objectID: String) -> [Flag] { flags.filter { $0.objectID == objectID } }
    func chains(through objectID: String) -> [Chain] { chains.filter { $0.nodeIDs.contains(objectID) } }

    static let empty = SafetyAnalysis(
        parameters: .forStage(.walking), objects: [], relations: [], chains: [], flags: [])
}
