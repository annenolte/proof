//
//  CraftState.swift
//  proof — Core / Safety
//
//  What the caregiver has authored (CLAUDE.md §9 Stage 7). The engine proposes; this
//  records what a person decided: which stars stay, which were added, which links they
//  drew, which constellations they named, and which flags are done.
//
//  Persisted as JSON in UserDefaults, so edits survive a relaunch. Small on purpose — one
//  room, one caregiver, a few hundred bytes.
//

import Foundation
import simd

/// A named group of stars with a fix plan. The caregiver's constellation.
struct Constellation: Codable, Hashable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable { case open, done }
    enum Origin: String, Codable, Sendable {
        /// Kept from a chain the engine found.
        case engine
        /// Grouped by hand.
        case user
    }

    var id: String
    var name: String
    var starIDs: [String]
    var relationIDs: [String]
    var fixPlan: String
    var status: Status
    var origin: Origin
}

/// A star the caregiver added for something the scan did not flag.
struct AddedStar: Codable, Hashable, Sendable {
    var objectID: String
    var label: String
    var hazard: HazardKind
    var aabb: AABB
}

struct CraftState: Codable, Equatable, Sendable {
    var stage: AgeStage = .walking
    var removedStarIDs: Set<String> = []
    var confirmedStarIDs: Set<String> = []
    var addedStars: [AddedStar] = []
    var userLinks: [Relation] = []
    var constellations: [Constellation] = []
    var doneFlagIDs: Set<String> = []

    /// The scene as the caregiver has shaped it: catalogue objects they kept, plus their own.
    func effectiveObjects(from package: ScenePackage) -> [SceneObject] {
        var objects = package.objects.filter { !removedStarIDs.contains($0.id) }
        for added in addedStars where !removedStarIDs.contains(added.objectID) {
            if let index = objects.firstIndex(where: { $0.id == added.objectID }) {
                if !objects[index].hazards.contains(added.hazard) {
                    objects[index].hazards.append(added.hazard)
                }
                if objects[index].role == .climbable { objects[index].role = .both }
                if objects[index].role == .neutral { objects[index].role = .hazard }
            } else {
                objects.append(SceneObject(
                    id: added.objectID, label: added.label, concept: "added by you",
                    role: .hazard, hazards: [added.hazard], aabb: added.aabb,
                    surfaces: [], source: .userAdded, confidence: nil))
            }
        }
        return objects
    }

    // MARK: Persistence

    private static let key = "proof.craft.kitchen.v1"

    static func load(_ defaults: UserDefaults = .standard) -> CraftState {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(CraftState.self, from: data) else { return CraftState() }
        return state
    }

    func save(_ defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    static func reset(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
