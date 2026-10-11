//
//  ConstellationModel.swift
//  proof — Features / Constellation
//
//  The sky over the room, and everything the caregiver does to it.
//
//  Owns: the scene package (measured from the live kitchen), the caregiver's `CraftState`,
//  the engine's latest `SafetyAnalysis`, what is selected, which layers are on, which
//  chain is lit, and where every star currently lands on screen.
//
//  The engine is re-run on every edit. It is cheap — a few dozen objects — and running it
//  again is simpler and more honest than patching a previous answer.
//

import Foundation
import Observation
import RealityKit
import SwiftUI
import simd

@MainActor
@Observable
final class ConstellationModel {

    // MARK: State

    private(set) var package: ScenePackage?
    private(set) var analysis: SafetyAnalysis = .empty
    private(set) var craft: CraftState {
        didSet { craft.save(); recompute() }
    }

    /// Star (object) id, or a prop the caregiver tapped that is not a star yet.
    var selectedID: String?
    var litChainID: String?
    /// Restarted every time a chain is lit, so the draw-on animation plays from the floor.
    private(set) var litChainStartedAt = Date()

    /// Draw-a-link mode: the first star tapped is held here, the second completes the link.
    var linkStartID: String?
    var isLinking = false

    /// Where each star is on screen this frame. Written by the renderer's frame hook.
    private(set) var projected: [String: CGPoint] = [:]
    /// Where the floor sits under each star, for the first step of a chain.
    private(set) var projectedFloor: [String: CGPoint] = [:]

    init() {
        self.craft = CraftState.load()
        if let bundled = KitchenScene.bundled() {
            self.package = bundled
            recompute()
        }
    }

    // MARK: Scene

    /// Replaces the bundled package with one measured from the live room.
    func attach(scene: ApartmentScene) {
        package = ScenePackageBuilder.package(from: scene)
        recompute()
    }

    private func recompute() {
        guard let package else { return }
        let objects = craft.effectiveObjects(from: package)
        analysis = SafetyEngine.analyze(
            objects, parameters: .forStage(craft.stage), userLinks: craft.userLinks)
        if let lit = litChainID, analysis.chain(lit) == nil { litChainID = nil }
    }

    // MARK: Derived

    var stage: AgeStage { craft.stage }
    var stars: [SceneObject] { analysis.objects.filter { $0.role != .neutral } }
    var constellations: [Constellation] { craft.constellations }
    var suggestions: [Constellation] {
        let kept = Set(craft.constellations.map(\.id))
        return FixPlanWriter.suggestions(for: analysis).filter { !kept.contains($0.id) }
    }
    var removedObjects: [SceneObject] {
        (package?.objects ?? []).filter { craft.removedStarIDs.contains($0.id) }
    }

    func isDone(_ flag: Flag) -> Bool { craft.doneFlagIDs.contains(flag.id) }
    func isConfirmed(_ id: String) -> Bool { craft.confirmedStarIDs.contains(id) }
    var doneCount: Int { analysis.flags.filter(isDone).count }

    var progressText: String { "\(doneCount) of \(analysis.flags.count) flags marked done" }

    var litChain: Chain? { litChainID.flatMap(analysis.chain) }

    /// Object ids the lit chain passes through, for emphasis in the sky.
    var litIDs: Set<String> { Set(litChain?.nodeIDs ?? []) }

    // MARK: Two ways to look at the room

    enum Mode: Equatable {
        /// The whole sky: every flag a star, every measured link a line, every fix plan a
        /// named constellation. The opening view — the theme, on screen.
        case constellation
        /// The calm view: only the climbing paths glow; one path at a time.
        case paths
    }

    private(set) var mode: Mode = .constellation
    /// When the current view appeared, so the stars can fade in one by one.
    private(set) var modeChangedAt = Date()

    func setMode(_ mode: Mode) {
        guard mode != self.mode else { return }
        self.mode = mode
        modeChangedAt = Date()
        selectedID = nil
        if mode == .constellation { litChainID = nil }
    }

    /// Restarts the fade-in, for when the room first comes into view.
    func replayArrival() { modeChangedAt = Date() }

    /// Lines in the whole sky, for the constellation card's count.
    var linkCount: Int {
        analysis.relations.filter { $0.fromID != nil && $0.fromID != $0.toID }.count
    }

    // MARK: What the sky shows

    /// How loudly a point is drawn. The room opens calm: only the climbing paths glow.
    enum Tone: Equatable {
        /// A hazard only reachable by climbing — the insight. Bright lime.
        case pathHazard
        /// Something a child steps on along a climbing path. Lavender.
        case pathStep
        /// Any other flag a child can reach. A small, quiet dot.
        case flag
        /// Out of reach at this stage, or not a hazard. Not drawn.
        case hidden
    }

    /// Every object a climbing path passes through.
    var pathIDs: Set<String> { Set(analysis.chains.flatMap(\.nodeIDs)) }

    func tone(of object: SceneObject) -> Tone {
        let onPath = pathIDs.contains(object.id)
        if onPath, analysis.chains.contains(where: { $0.hazardID == object.id }) { return .pathHazard }
        if onPath { return .pathStep }
        let flags = analysis.flags(for: object.id)
        if flags.contains(where: { $0.reachability != .notReached }) || object.source == .userAdded {
            return .flag
        }
        return .hidden
    }

    /// The points worth drawing, plus whatever is selected.
    var visibleStars: [SceneObject] {
        if mode == .constellation { return stars }
        return stars.filter { tone(of: $0) != .hidden || $0.id == selectedID }
    }

    /// One plain phrase for how a child gets to this object.
    func reachPhrase(_ object: SceneObject) -> String {
        if analysis.chains.contains(where: { $0.hazardID == object.id }) { return "Reachable by climbing" }
        if pathIDs.contains(object.id) { return "A step a child can climb" }
        let flags = analysis.flags(for: object.id)
        if flags.contains(where: { $0.reachability == .fromFloor }) { return "Within reach from the floor" }
        if object.role.isClimbable, flags.isEmpty { return "Something a child can climb" }
        return "Out of reach for \(Self.who(stage).lowercased())"
    }

    func isObjectDone(_ id: String) -> Bool {
        let flags = analysis.flags(for: id)
        return !flags.isEmpty && flags.allSatisfy(isDone)
    }

    func toggleObjectDone(_ id: String) {
        let flags = analysis.flags(for: id)
        let done = isObjectDone(id)
        for flag in flags {
            if done { craft.doneFlagIDs.remove(flag.id) } else { craft.doneFlagIDs.insert(flag.id) }
        }
    }

    // MARK: Plain language

    static func who(_ stage: AgeStage) -> String {
        switch stage {
        case .crawling: return "A crawling baby"
        case .walking: return "A toddler"
        case .climbing: return "A climbing toddler"
        }
    }

    /// "Counter stool 1" → "counter stool". Numbers help a list, not a sentence.
    static func plain(_ label: String) -> String { PlainNames.plain(label) }

    /// Which surface of a multi-surface object a step lands on, in words.
    private func surfaceName(_ object: SceneObject, height: Float?) -> String {
        let surfaces = SafetyEngine.standableSurfaces(of: object)
        let name = Self.plain(object.label)
        guard surfaces.count > 1, let height,
              let index = surfaces.firstIndex(where: { abs($0 - height) < 0.01 }) else { return "the \(name)" }
        switch object.concept {
        case "bar stool": return index == 0 ? "the \(name)'s footrail" : "the \(name)'s seat"
        case "shelf": return index == 0 ? "the bottom shelf" : "a shelf \(String(format: "%.1f", height)) m up"
        default: return "the \(name)"
        }
    }

    /// What the hazard is resting on, if anything — "on the breakfast bar".
    private func support(of hazard: SceneObject) -> SceneObject? {
        analysis.objects
            .filter { $0.id != hazard.id && abs($0.topHeight - hazard.lowestPoint) < 0.04
                && $0.aabb.footprintGap(to: hazard.aabb) < 0.01 && $0.aabb.size.x * $0.aabb.size.z > 0.2 }
            .max { $0.aabb.size.x * $0.aabb.size.z < $1.aabb.size.x * $1.aabb.size.z }
    }

    /// "A toddler could step onto the counter stool's footrail and reach the wine glass on
    /// the breakfast bar." Built only from the chain's own steps.
    func sentence(for chain: Chain) -> String {
        guard let hazard = analysis.object(chain.hazardID) else { return "" }
        var steps: [String] = []
        for relation in chain.relations where relation.kind == .climbStep {
            guard let object = analysis.object(relation.toID) else { continue }
            let name = surfaceName(object, height: relation.surfaceHeight)
            if steps.last != name { steps.append(name) }
        }
        let route = steps.count <= 1
            ? (steps.first ?? "something")
            : steps.dropLast().joined(separator: ", ") + " and then " + (steps.last ?? "")
        var target = "the " + Self.plain(hazard.label)
        if let support = support(of: hazard) { target += " on the " + Self.plain(support.label) }
        return "\(Self.who(stage)) could step onto \(route) and reach \(target)."
    }

    /// The numbers behind the sentence, for anyone who wants to check them.
    func measurements(for chain: Chain) -> String {
        chain.relations.map { relation in
            if relation.kind == .climbStep {
                return String(format: "step up %.2f m", relation.rise ?? 0)
            }
            var text = String(format: "reach %.2f m up", relation.rise ?? 0)
            if let gap = relation.gap, gap > 0.005 { text += String(format: ", %.2f m across", gap) }
            return text
        }.joined(separator: " · ")
    }

    /// Plays the first path once, the first time the room opens, so the point of the app
    /// is on screen before anyone has to find it.
    @ObservationIgnored private(set) var hasIntroduced = false

    func introduceIfNeeded() {
        guard !hasIntroduced else { return }
        hasIntroduced = true
        guard litChainID == nil, selectedID == nil, let first = preferredFirstChain else { return }
        light(first.id)
    }

    /// The glass on the breakfast bar is the clearest example; any path is a real one.
    private var preferredFirstChain: Chain? { paths.first }

    /// The engine's paths in the order the app shows them: the clearest example first.
    var paths: [Chain] {
        let chains = analysis.chains
        guard let i = chains.firstIndex(where: { $0.hazardID.contains("wineGlass") }) else { return chains }
        return [chains[i]] + chains.enumerated().filter { $0.offset != i }.map(\.element)
    }

    // MARK: Craft actions

    func setStage(_ stage: AgeStage) {
        guard stage != craft.stage else { return }
        litChainID = nil
        craft.stage = stage
    }

    func confirm(_ id: String) {
        craft.confirmedStarIDs.insert(id)
        craft.removedStarIDs.remove(id)
    }

    func remove(_ id: String) {
        craft.removedStarIDs.insert(id)
        craft.confirmedStarIDs.remove(id)
        craft.userLinks.removeAll { $0.fromID == id || $0.toID == id }
        if selectedID == id { selectedID = nil }
    }

    func restore(_ id: String) {
        craft.removedStarIDs.remove(id)
    }

    /// Adds a star for something the scan missed or the catalog calls neutral.
    func addStar(objectID: String, label: String, hazard: HazardKind, aabb: AABB) {
        craft.removedStarIDs.remove(objectID)
        craft.addedStars.removeAll { $0.objectID == objectID && $0.hazard == hazard }
        craft.addedStars.append(AddedStar(objectID: objectID, label: label, hazard: hazard, aabb: aabb))
        craft.confirmedStarIDs.insert(objectID)
    }

    /// Bounds for any prop in the live room — how a non-star becomes a star.
    func bounds(forProp id: String, in scene: ApartmentScene?) -> (label: String, aabb: AABB)? {
        if let object = package?.object(id) { return (object.label, object.aabb) }
        guard let scene, let prop = scene.props[id] else { return nil }
        return (prop.name, ScenePackageBuilder.aabb(of: prop.entity))
    }

    func beginLink(from id: String) {
        isLinking = true
        linkStartID = id
    }

    func cancelLink() {
        isLinking = false
        linkStartID = nil
    }

    /// Second tap of a link. Same star twice cancels.
    func completeLink(to id: String) {
        defer { cancelLink() }
        guard let from = linkStartID, from != id else { return }
        let link = Relation(
            id: Relation.makeID(.userLink, from, id), kind: .userLink,
            fromID: from, toID: id, rise: nil, gap: nil, surfaceHeight: nil, origin: .userDrawn)
        guard !craft.userLinks.contains(where: { $0.id == link.id }) else { return }
        craft.userLinks.append(link)
    }

    func removeLink(_ id: String) {
        craft.userLinks.removeAll { $0.id == id }
    }

    func toggleDone(_ flag: Flag) {
        if craft.doneFlagIDs.contains(flag.id) {
            craft.doneFlagIDs.remove(flag.id)
        } else {
            craft.doneFlagIDs.insert(flag.id)
        }
    }

    func keep(_ suggestion: Constellation) {
        guard !craft.constellations.contains(where: { $0.id == suggestion.id }) else { return }
        craft.constellations.append(suggestion)
    }

    /// Groups stars by hand into a new, named constellation.
    func createConstellation(name: String, starIDs: [String]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "My fix plan" : trimmed
        let ids = starIDs.filter { analysis.object($0) != nil }
        let links = craft.userLinks.filter { link in
            ids.contains(link.toID) && link.fromID.map(ids.contains) == true
        }
        craft.constellations.append(Constellation(
            id: "user:\(UUID().uuidString)",
            name: title,
            starIDs: ids,
            relationIDs: links.map(\.id),
            fixPlan: FixPlanWriter.plan(name: title, starIDs: ids, analysis: analysis),
            status: .open,
            origin: .user))
    }

    func rename(_ id: String, to name: String) {
        guard let i = craft.constellations.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        craft.constellations[i].name = trimmed
    }

    func addStar(_ starID: String, toConstellation id: String) {
        guard let i = craft.constellations.firstIndex(where: { $0.id == id }),
              !craft.constellations[i].starIDs.contains(starID) else { return }
        craft.constellations[i].starIDs.append(starID)
        craft.constellations[i].fixPlan = FixPlanWriter.plan(
            name: craft.constellations[i].name, starIDs: craft.constellations[i].starIDs,
            analysis: analysis)
    }

    func toggleStatus(_ id: String) {
        guard let i = craft.constellations.firstIndex(where: { $0.id == id }) else { return }
        craft.constellations[i].status = craft.constellations[i].status == .done ? .open : .done
    }

    func deleteConstellation(_ id: String) {
        craft.constellations.removeAll { $0.id == id }
    }

    /// Back to what the engine found. For rehearsing the demo.
    func resetCraft() {
        let stage = craft.stage
        craft = CraftState()
        craft.stage = stage
        selectedID = nil
        litChainID = nil
        cancelLink()
    }

    // MARK: Chains

    func light(_ chainID: String?) {
        litChainID = chainID
        litChainStartedAt = Date()
    }

    /// Steps through the chains, one per tap, ending on none.
    func lightNextChain() {
        let chains = paths
        guard !chains.isEmpty else { litChainID = nil; return }
        if let current = litChainID, let i = chains.firstIndex(where: { $0.id == current }) {
            light(i + 1 < chains.count ? chains[i + 1].id : nil)
        } else {
            light(chains[0].id)
        }
    }

    // MARK: Projection

    /// Called once per rendered frame with the live view. Writes only when something moved
    /// by more than half a point, so a still camera does not invalidate the overlay.
    func project(in view: ARView) {
        var points: [String: CGPoint] = [:]
        var floor: [String: CGPoint] = [:]
        for object in analysis.objects {
            let p = object.starPosition
            if let s = view.project(p) { points[object.id] = s }
            if let f = view.project(SIMD3(p.x, 0, p.z)) { floor[object.id] = f }
        }
        if !Self.close(points, projected) { projected = points }
        if !Self.close(floor, projectedFloor) { projectedFloor = floor }
    }

    private static func close(_ a: [String: CGPoint], _ b: [String: CGPoint]) -> Bool {
        guard a.count == b.count else { return false }
        for (key, p) in a {
            guard let q = b[key], abs(p.x - q.x) < 0.5, abs(p.y - q.y) < 0.5 else { return false }
        }
        return true
    }
}

// MARK: - Measuring the live room

@MainActor
enum ScenePackageBuilder {

    /// World bounds of a prop as it is actually resting.
    static func aabb(of entity: Entity) -> AABB {
        let bounds = entity.visualBounds(relativeTo: nil)
        return AABB(min: bounds.min, max: bounds.max)
    }

    /// Every catalogued object in the room, measured.
    static func package(from scene: ApartmentScene) -> ScenePackage {
        let objects: [SceneObject] = scene.props.values.compactMap { prop in
            guard let entry = ConceptCatalog.entry(for: prop.id) else { return nil }
            return SceneObject(
                id: prop.id, label: prop.name, concept: entry.concept, role: entry.role,
                hazards: entry.hazards, aabb: aabb(of: prop.entity),
                surfaces: entry.surfaces ?? [], source: .auto, confidence: nil)
        }
        return ScenePackage(
            name: "Kitchen", provenance: KitchenScene.provenance,
            objects: KitchenScene.disambiguated(objects))
    }

    /// `-proofExportScene`: writes the measured package to Documents, so it can be copied into
    /// `proof/Resources/kitchen.scene.json`. Debug only.
    static func exportIfRequested(_ scene: ApartmentScene) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-proofExportScene") else { return }
        let package = package(from: scene)
        guard let data = try? KitchenScene.encode(package),
              let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return }
        let url = dir.appendingPathComponent("\(KitchenScene.resourceName).json")
        try? data.write(to: url)
        print("[proof] exported \(package.objects.count) objects to \(url.path)")
        #endif
    }
}
