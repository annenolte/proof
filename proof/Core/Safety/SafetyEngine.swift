//
//  SafetyEngine.swift
//  proof — Core / Safety
//
//  The analysis of CLAUDE.md §7. Pure, deterministic, and unit tested (`EngineTests`).
//
//  It answers one question with geometry: *from the floor, by stepping up from surface to
//  surface, what can a child of this stage get within reach of?* No language model is
//  involved at any point (§3 rule 3). The LLM may later write prose *about* a chain; it
//  never decides that one exists.
//
//  What it cannot know, and the UI says so: whether furniture is anchored, whether a
//  cabinet is latched, whether a drawer pulls out into a step, or anything about objects
//  the scan did not find. Bounds are approximate; surfaces are where the model says they
//  are; the parameters are placeholders until they are sourced.
//

import Foundation
import simd

enum SafetyEngine {

    /// A place a child can be: the floor, or one surface of one object.
    struct Node: Hashable {
        /// `nil` is the floor.
        var objectID: String?
        var height: Float

        static let floor = Node(objectID: nil, height: 0)
        var isFloor: Bool { objectID == nil }
    }

    static func analyze(
        _ objects: [SceneObject],
        parameters p: SafetyParameters,
        userLinks: [Relation] = []
    ) -> SafetyAnalysis {
        let byID = Dictionary(objects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let climbables = objects.filter { $0.role.isClimbable }
        let hazards = objects.filter { $0.role.isHazard }

        // ── 1. Climb graph ───────────────────────────────────────────────
        var nodes: [Node] = [.floor]
        for object in climbables {
            for height in standableSurfaces(of: object) {
                nodes.append(Node(objectID: object.id, height: height))
            }
        }

        var edges: [Node: [(Node, Relation)]] = [:]
        var climbRelations: [Relation] = []
        for a in nodes {
            for b in nodes where b.objectID != nil && b != a {
                guard let relation = climbStep(from: a, to: b, objects: byID, parameters: p) else { continue }
                edges[a, default: []].append((b, relation))
                climbRelations.append(relation)
            }
        }

        // ── 2. Breadth-first from the floor: fewest steps to every surface ──
        var depth: [Node: Int] = [.floor: 0]
        var parent: [Node: (Node, Relation)] = [:]
        var queue: [Node] = [.floor]
        var head = 0
        while head < queue.count {
            let current = queue[head]; head += 1
            // Deterministic order: lower surfaces first, then by id.
            let next = (edges[current] ?? []).sorted { nodeOrder($0.0, $1.0) }
            for (node, relation) in next where depth[node] == nil {
                depth[node] = (depth[current] ?? 0) + 1
                parent[node] = (current, relation)
                queue.append(node)
            }
        }

        // ── 3. Reach, and the chains it makes ────────────────────────────
        var chains: [Chain] = []
        var reachRelations: [Relation] = []
        var reachability: [String: Reachability] = [:]

        let reachedNodes = queue.filter { !$0.isFloor }
        for hazard in hazards.sorted(by: { $0.id < $1.id }) {
            if reaches(from: .floor, hazard: hazard, objects: byID, parameters: p) != nil {
                reachability[hazard.id] = .fromFloor
                continue
            }
            // The cheapest surface to stand on: fewest steps, then lowest.
            let candidates = reachedNodes.compactMap { node -> (Node, Relation)? in
                guard node.objectID != hazard.id,
                      let relation = reaches(from: node, hazard: hazard, objects: byID, parameters: p)
                else { return nil }
                return (node, relation)
            }
            guard let best = candidates.min(by: { a, b in
                let da = depth[a.0] ?? .max, db = depth[b.0] ?? .max
                return da != db ? da < db : nodeOrder(a.0, b.0)
            }) else {
                reachability[hazard.id] = .notReached
                continue
            }

            var path: [(Node, Relation)] = []
            var cursor = best.0
            while let step = parent[cursor] {
                path.insert((cursor, step.1), at: 0)
                cursor = step.0
            }
            var nodeIDs: [String] = []
            for (node, _) in path where nodeIDs.last != node.objectID {
                nodeIDs.append(node.objectID!)
            }
            nodeIDs.append(hazard.id)

            let relations = path.map(\.1) + [best.1]
            let chain = Chain(
                id: "chain:" + nodeIDs.joined(separator: ">"),
                nodeIDs: nodeIDs,
                relations: relations,
                why: why(path: path, reach: best.1, hazard: hazard, objects: byID))
            chains.append(chain)
            reachRelations.append(best.1)
            reachability[hazard.id] = .viaChain(chainID: chain.id)
        }

        // A climbable object is "reached" if any of its surfaces is.
        func climbReachability(_ object: SceneObject) -> Reachability {
            let reached = reachedNodes.filter { $0.objectID == object.id }
            guard let first = reached.min(by: { (depth[$0] ?? .max) < (depth[$1] ?? .max) })
            else { return .notReached }
            if depth[first] == 1 { return .fromFloor }
            return .viaChain(chainID: "climb:\(object.id)")
        }

        // ── 4. Flags ─────────────────────────────────────────────────────
        var flags: [Flag] = []
        for object in objects.sorted(by: { $0.id < $1.id }) {
            for kind in object.hazards {
                if let flag = makeFlag(kind, object: object, parameters: p,
                                       reach: reachability[object.id] ?? climbReachability(object),
                                       climbReach: climbReachability(object)) {
                    flags.append(flag)
                }
            }
        }

        // ── 5. Clusters ──────────────────────────────────────────────────
        var clusterRelations: [Relation] = []
        let sortedHazards = hazards.sorted { $0.id < $1.id }
        for (i, a) in sortedHazards.enumerated() {
            for b in sortedHazards[(i + 1)...] {
                let distance = simd_distance(a.centroid, b.centroid)
                guard distance <= p.clusterDistance.value else { continue }
                clusterRelations.append(Relation(
                    id: Relation.makeID(.cluster, a.id, b.id), kind: .cluster,
                    fromID: a.id, toID: b.id, rise: nil, gap: distance,
                    surfaceHeight: nil, origin: .engine))
            }
        }

        let validLinks = userLinks.filter { link in
            byID[link.toID] != nil && (link.fromID.map { byID[$0] != nil } ?? true)
        }

        return SafetyAnalysis(
            parameters: p,
            objects: objects,
            relations: climbRelations + reachRelations + clusterRelations + validLinks,
            chains: chains.sorted { a, b in
                a.stepCount != b.stepCount ? a.stepCount < b.stepCount : a.id < b.id
            },
            flags: flags)
    }

    /// Lower surfaces first, then by id — so every tie breaks the same way on every run.
    private static func nodeOrder(_ a: Node, _ b: Node) -> Bool {
        if a.height != b.height { return a.height < b.height }
        return (a.objectID ?? "") < (b.objectID ?? "")
    }

    // MARK: - Geometry rules

    /// Surfaces a child can stand on, lowest first.
    static func standableSurfaces(of object: SceneObject) -> [Float] {
        let surfaces = object.surfaces.isEmpty ? [object.topHeight] : object.surfaces
        return surfaces.filter { $0 > 0.05 }.sorted()
    }

    /// An edge A → B exists if B is higher by no more than `stepMax` and the footprints are
    /// no further apart than `gapMax`. Only upward steps: the question is how high a child
    /// can get, and coming down is never what stops them.
    static func climbStep(
        from a: Node, to b: Node, objects: [String: SceneObject], parameters p: SafetyParameters
    ) -> Relation? {
        guard let bID = b.objectID, let bObject = objects[bID] else { return nil }
        let rise = b.height - a.height
        guard rise > 0.02, rise <= p.stepMax.value else { return nil }

        let gap: Float
        if let aID = a.objectID, let aObject = objects[aID] {
            gap = aID == bID ? 0 : aObject.aabb.footprintGap(to: bObject.aabb)
        } else {
            gap = 0     // from the floor, a child walks right up to it
        }
        guard gap <= p.gapMax.value else { return nil }

        return Relation(
            id: Relation.makeID(.climbStep, a.objectID, bID, b.height), kind: .climbStep,
            fromID: a.objectID, toID: bID, rise: rise, gap: gap,
            surfaceHeight: b.height, origin: .engine)
    }

    /// A hazard is within reach from a surface if its lowest point is no more than
    /// `reachHeight` above the surface, some of it is above the surface, and it is within
    /// `horizontalReach` of the surface's footprint.
    static func reaches(
        from node: Node, hazard: SceneObject, objects: [String: SceneObject], parameters p: SafetyParameters
    ) -> Relation? {
        let rise = hazard.lowestPoint - node.height
        guard rise <= p.reachHeight.value, hazard.topHeight >= node.height else { return nil }

        var gap: Float = 0
        if let id = node.objectID, let standing = objects[id] {
            gap = standing.aabb.footprintGap(to: hazard.aabb)
            guard gap <= p.horizontalReach.value else { return nil }
        }
        return Relation(
            id: Relation.makeID(.reach, node.objectID, hazard.id, node.height), kind: .reach,
            fromID: node.objectID, toID: hazard.id, rise: max(0, rise), gap: gap,
            surfaceHeight: node.height, origin: .engine)
    }

    // MARK: - Flags

    private static func makeFlag(
        _ kind: HazardKind, object: SceneObject, parameters p: SafetyParameters,
        reach: Reachability, climbReach: Reachability
    ) -> Flag? {
        let id = "flag:\(object.id):\(kind.rawValue)"
        switch kind {
        case .tipOver:
            // Heuristic on the object's own proportions. Whether it is anchored cannot be
            // seen in a scan, so the flag asks the caregiver to check rather than asserting.
            let height = object.aabb.size.y
            let minor = max(object.aabb.footprintMinor, 0.01)
            let ratio = height / minor
            guard height >= p.tipMinHeight.value, ratio >= p.tipRatio.value else { return nil }
            return Flag(
                id: id, objectID: object.id, kind: kind, label: object.label,
                detail: String(format: "%.2f m tall on a %.2f m base (%.1f×). Check whether it is anchored — a scan cannot tell.", height, minor, ratio),
                detectedBy: .engineGeometry, reachability: reach,
                fixTypes: kind.fixTypes, isHeuristic: true)

        case .corners:
            let top = object.topHeight
            guard top >= p.cornerLow.value, top <= p.cornerHigh.value else { return nil }
            return Flag(
                id: id, objectID: object.id, kind: kind, label: object.label,
                detail: String(format: "Edges at %.2f m — around head height for this stage.", top),
                detectedBy: .engineGeometry, reachability: .fromFloor,
                fixTypes: kind.fixTypes, isHeuristic: true)

        case .falls where object.role.isClimbable:
            let highest = standableSurfaces(of: object).last ?? object.topHeight
            return Flag(
                id: id, objectID: object.id, kind: kind, label: object.label,
                detail: String(format: "Climbable to %.2f m.", highest),
                detectedBy: .engineGeometry, reachability: climbReach,
                fixTypes: kind.fixTypes, isHeuristic: false)

        default:
            let detail: String
            switch reach {
            case .fromFloor:
                detail = String(format: "Lowest part at %.2f m — within reach from the floor.", object.lowestPoint)
            case .viaChain:
                detail = String(format: "Lowest part at %.2f m — out of reach from the floor, reachable by climbing.", object.lowestPoint)
            case .notReached:
                detail = String(format: "Lowest part at %.2f m — not reachable at this stage by the engine's geometry.", object.lowestPoint)
            }
            return Flag(
                id: id, objectID: object.id, kind: kind, label: object.label,
                detail: detail, detectedBy: .concept, reachability: reach,
                fixTypes: kind.fixTypes, isHeuristic: false)
        }
    }

    // MARK: - Explanations

    /// "Floor → Counter stool, footrail (+0.20 m) → …". Built only from measured values.
    private static func why(
        path: [(Node, Relation)], reach: Relation, hazard: SceneObject, objects: [String: SceneObject]
    ) -> String {
        var parts = ["Floor"]
        for (node, relation) in path {
            let name = objects[node.objectID ?? ""]?.label ?? "surface"
            var text = String(format: "%@ at %.2f m (step %.2f m", name, node.height, relation.rise ?? 0)
            if let gap = relation.gap, gap > 0.005 { text += String(format: ", gap %.2f m", gap) }
            parts.append(text + ")")
        }
        var last = String(format: "%@ (%.2f m above", hazard.label, reach.rise ?? 0)
        if let gap = reach.gap, gap > 0.005 { last += String(format: ", %.2f m across", gap) }
        parts.append(last + ")")
        return parts.joined(separator: " → ")
    }
}
