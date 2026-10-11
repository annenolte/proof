//
//  FixItPlanStore.swift
//  Tremor — S-17 persistence
//
//  What the user has done, and what they have chosen to add. Two small sets per
//  room and nothing else.
//
//  The plan itself is *derived*: `Checklist.plan(for:room:)` builds it from the
//  assessment every time, so it always reflects the current state of the room
//  and can never drift out of date the way a stored copy would. The only things
//  worth persisting are the two facts the derivation cannot know — which fixes
//  the user has ticked off, and which extra objects they asked to include.
//
//  `AppState` deliberately does not hold this: it is the fix-it plan's own
//  cross-screen state, it outlives the open room, and it belongs to the screens
//  that read it.
//

import Foundation
import Observation
import SwiftUI

// MARK: - Store

@MainActor
@Observable
final class FixItPlanStore {

    /// One room's worth of user decisions.
    struct RoomState: Codable, Hashable, Sendable {
        /// `ChecklistItem.id` values the user has ticked.
        var completed: Set<String> = []
        /// Objects the user added by hand, below the band that earns an
        /// automatic place in the plan.
        var pinned: Set<UUID> = []

        var isEmpty: Bool { completed.isEmpty && pinned.isEmpty }
    }

    /// Namespaced like every other Tremor key.
    static let storageKey = "com.annenolte.proof.fixItPlan.v1"

    private(set) var rooms: [UUID: RoomState]

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([UUID: RoomState].self, from: data) {
            self.rooms = decoded
        } else {
            self.rooms = [:]
        }
    }

    /// The live store. One instance for the app, because two screens holding two
    /// copies of "have I done this yet" is a bug people notice immediately.
    static let shared = FixItPlanStore()

    /// A throwaway store on its own defaults suite, for previews and tests.
    /// Never touches the real container.
    static func ephemeral() -> FixItPlanStore {
        let suite = "com.annenolte.proof.fixItPlan.preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return FixItPlanStore(defaults: defaults)
    }

    // MARK: Reading

    func state(for roomID: UUID) -> RoomState { rooms[roomID] ?? RoomState() }

    func isComplete(_ itemID: String, in roomID: UUID) -> Bool {
        state(for: roomID).completed.contains(itemID)
    }

    func isPinned(_ objectID: UUID, in roomID: UUID) -> Bool {
        state(for: roomID).pinned.contains(objectID)
    }

    func completedCount(in roomID: UUID) -> Int { state(for: roomID).completed.count }

    // MARK: Writing

    func setComplete(_ isComplete: Bool, itemID: String, in roomID: UUID) {
        mutate(roomID) { state in
            if isComplete { state.completed.insert(itemID) } else { state.completed.remove(itemID) }
        }
    }

    func setPinned(_ isPinned: Bool, objectID: UUID, in roomID: UUID) {
        mutate(roomID) { state in
            if isPinned { state.pinned.insert(objectID) } else { state.pinned.remove(objectID) }
        }
    }

    /// Drops ticks for items that are no longer in the plan — an object the user
    /// deleted, or a fix that stopped being recommended after a correction.
    /// Without this, "3 of 6 done" can quietly become "5 of 4".
    func prune(roomID: UUID, keepingItemIDs valid: Set<String>) {
        guard let state = rooms[roomID] else { return }
        let kept = state.completed.intersection(valid)
        guard kept != state.completed else { return }
        mutate(roomID) { $0.completed = kept }
    }

    func forget(roomID: UUID) {
        rooms[roomID] = nil
        persist()
    }

    func resetAll() {
        rooms = [:]
        persist()
    }

    private func mutate(_ roomID: UUID, _ change: (inout RoomState) -> Void) {
        var state = rooms[roomID] ?? RoomState()
        change(&state)
        if state.isEmpty { rooms[roomID] = nil } else { rooms[roomID] = state }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(rooms) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

// MARK: - Environment

private struct FixItPlanStoreKey: EnvironmentKey {
    // `assumeIsolated` for the same reason `TremorEnvironmentKey` uses it: the
    // store is main-actor state and SwiftUI only reads the environment there.
    static var defaultValue: FixItPlanStore {
        MainActor.assumeIsolated { FixItPlanStore.shared }
    }
}

extension EnvironmentValues {
    /// The user's ticks and pins. Overridden in previews with
    /// `FixItPlanStore.ephemeral()` so a preview never writes to the real store.
    var fixItPlan: FixItPlanStore {
        get { self[FixItPlanStoreKey.self] }
        set { self[FixItPlanStoreKey.self] = newValue }
    }
}
