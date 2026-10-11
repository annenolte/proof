//
//  FixItPlanModel.swift
//  Tremor — S-17 fix-it plan
//
//  Turns the room's findings into an ordered plan, prices it, groups it by the
//  trip the user would actually make, and — the number that sells the straps —
//  keeps three scores live: what the room is now, what it is with the boxes
//  already ticked, and what it will be when the whole plan is done.
//
//  The "with what you've ticked" number is the reason this model exists rather
//  than a computed property on the view. It is a full re-assessment of a
//  mitigated copy of the room, so it is exactly as trustworthy as the score it
//  is compared against, and it has to run off the main actor.
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class FixItPlanModel {

    enum Phase: Equatable {
        case loading
        /// The room is open but has never been shaken.
        case notAssessed
        /// A plan with at least one fix in it.
        case ready
        /// The room came back clean: nothing to fix.
        case nothingToFix
        /// No room is open. A stale push.
        case noRoom
        case failed(String)
    }

    // MARK: Outputs

    private(set) var phase: Phase = .loading
    private(set) var plan: FixItPlan?
    private(set) var room: ScannedRoom?
    private(set) var assessment: RoomAssessment?

    /// The room's score with only the ticked fixes applied. `nil` until the
    /// first pass finishes, and equal to the current score when nothing is
    /// ticked.
    private(set) var scoreSoFar: Double?
    private(set) var isScoringProgress = false

    /// Set once, the moment the last box is ticked. The view clears it when the
    /// celebration finishes so it cannot fire twice.
    var celebrating = false

    // MARK: Dependencies

    @ObservationIgnored private var env: TremorEnvironment?
    @ObservationIgnored private var store: FixItPlanStore?
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var lastCompletedSignature: Set<String> = []

    init() {}

    func cancel() {
        progressTask?.cancel()
        progressTask = nil
        isScoringProgress = false
    }

    // MARK: - Building

    func load(env: TremorEnvironment, appState: AppState, store: FixItPlanStore) async {
        self.env = env
        self.store = store

        switch appState.loadPhase {
        case .idle where appState.room == nil:
            phase = .noRoom
            return
        case .loading, .idle:
            phase = .loading
            return
        case .failed(let message):
            phase = .failed(message)
            return
        case .loaded:
            break
        }

        guard let room = appState.room else {
            phase = .noRoom
            return
        }
        self.room = room

        guard let assessment = appState.assessment else {
            self.assessment = nil
            self.plan = nil
            phase = .notAssessed
            return
        }
        self.assessment = assessment

        let pinned = store.state(for: room.id).pinned
        let built = Self.build(room: room, assessment: assessment,
                               engine: env.risk, pinned: pinned)
        self.plan = built

        // A tick for a fix that no longer exists must not survive — it would
        // make "3 of 2 done" possible.
        store.prune(roomID: room.id, keepingItemIDs: Set(built.items.map(\.id)))

        phase = built.isEmpty ? .nothingToFix : .ready
        refreshProgressScore(store: store)
    }

    /// The plan, plus any objects the user pinned by hand from S-16.
    ///
    /// `Checklist.plan` owns the ordering, the projection and the trip merge;
    /// pinned objects are folded in through the same pieces (`MitigationLibrary`
    /// for the advice, `Checklist.shoppingTrips` for the merge) rather than
    /// through a second implementation of any of it.
    static func build(room: ScannedRoom, assessment: RoomAssessment,
                      engine: RiskEngine, pinned: Set<UUID>) -> FixItPlan {
        var plan = Checklist.plan(for: assessment, room: room, engine: engine)

        let alreadyIn = Set(plan.items.map(\.objectID))
        let extras = pinned.subtracting(alreadyIn)
        guard !extras.isEmpty else { return plan }

        var items = plan.items
        for objectID in extras.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let object = room.object(id: objectID) else { continue }
            let risk = assessment.risk(for: objectID)
            let advice = Array(MitigationLibrary.advice(for: object, risk: risk, in: room)
                .prefix(Checklist.maximumFixesPerObject))
            guard let primary = advice.first else { continue }

            let current = risk?.score ?? 0
            let projected = projectedScore(
                applying: primary, to: object, in: room,
                assessment: assessment, engine: engine) ?? current

            for mitigation in advice {
                let isPrimary = mitigation.id == primary.id
                items.append(ChecklistItem(
                    id: "\(objectID.uuidString).\(mitigation.id)",
                    objectID: objectID,
                    objectName: object.type.displayName,
                    objectSymbolName: object.type.symbolName,
                    mitigation: mitigation,
                    currentScore: current,
                    projectedScore: isPrimary ? min(projected, current) : current,
                    isPrimary: isPrimary,
                    isScored: isPrimary))
            }
        }

        let cost = items.reduce(0.0...0.0) { total, item in
            (total.lowerBound + item.mitigation.estimatedCostUSD.lowerBound)
                ... (total.upperBound + item.mitigation.estimatedCostUSD.upperBound)
        }

        plan = FixItPlan(
            id: plan.id,
            roomID: plan.roomID,
            roomName: plan.roomName,
            intensity: plan.intensity,
            items: items,
            trips: Checklist.shoppingTrips(for: items),
            estimatedCostUSD: cost,
            totalMinutes: items.reduce(0) { $0 + $1.mitigation.minutes },
            currentScore: plan.currentScore,
            projectedScore: min(
                score(room: room, assessment: assessment, engine: engine,
                      applying: items.filter(\.isPrimary)) ?? plan.projectedScore,
                plan.currentScore))
        return plan
    }

    // MARK: - Progress score

    /// Re-scores the room with only the ticked fixes applied.
    ///
    /// Debounced by comparing the completed set: ticking three boxes quickly
    /// runs the ensemble once, not three times.
    func refreshProgressScore(store: FixItPlanStore) {
        guard let plan, let room, let assessment, let env else { return }
        let completed = store.state(for: room.id).completed
        guard completed != lastCompletedSignature || scoreSoFar == nil else { return }
        lastCompletedSignature = completed

        let done = plan.items.filter { completed.contains($0.id) }
        guard !done.isEmpty else {
            progressTask?.cancel()
            isScoringProgress = false
            scoreSoFar = plan.currentScore
            return
        }

        progressTask?.cancel()
        isScoringProgress = true
        let engine = env.risk
        progressTask = Task { [weak self] in
            let value = await Task.detached(priority: .userInitiated) {
                Self.score(room: room, assessment: assessment, engine: engine, applying: done)
            }.value
            guard !Task.isCancelled else { return }
            self?.scoreSoFar = min(value ?? plan.currentScore, plan.currentScore)
            self?.isScoringProgress = false
        }
    }

    /// The room's overall score with a set of fixes applied. The one place this
    /// arithmetic happens.
    nonisolated static func score(room: ScannedRoom, assessment: RoomAssessment,
                                  engine: RiskEngine, applying items: [ChecklistItem]) -> Double? {
        guard !items.isEmpty else { return assessment.overallScore }
        var mitigated = room
        var changed = false
        for item in items {
            guard let index = mitigated.objects.firstIndex(where: { $0.id == item.objectID })
            else { continue }
            let before = mitigated.objects[index]
            let after = Checklist.apply(item.mitigation.effect, to: before, in: mitigated)
            if after != before {
                mitigated.objects[index] = after
                changed = true
            }
        }
        guard changed else { return assessment.overallScore }
        return engine.assess(room: mitigated, intensity: assessment.intensity,
                             seed: assessment.seed).overallScore
    }

    nonisolated private static func projectedScore(
        applying mitigation: Mitigation, to object: ScannedObject,
        in room: ScannedRoom, assessment: RoomAssessment, engine: RiskEngine
    ) -> Double? {
        guard mitigation.effect.isModelled,
              let index = room.objects.firstIndex(where: { $0.id == object.id })
        else { return nil }
        var mitigated = room
        mitigated.objects[index] = Checklist.apply(mitigation.effect, to: object, in: room)
        return engine.assess(room: mitigated, intensity: assessment.intensity,
                             seed: assessment.seed).risk(for: object.id)?.score
    }

    // MARK: - Derived

    func completedItemIDs(store: FixItPlanStore) -> Set<String> {
        guard let room else { return [] }
        return store.state(for: room.id).completed
    }

    func completedCount(store: FixItPlanStore) -> Int {
        guard let plan else { return 0 }
        let completed = completedItemIDs(store: store)
        return plan.items.filter { completed.contains($0.id) }.count
    }

    /// 0…1 for the progress ring.
    func progress(store: FixItPlanStore) -> Double {
        guard let plan, !plan.items.isEmpty else { return 0 }
        return Double(completedCount(store: store)) / Double(plan.items.count)
    }

    func isFinished(store: FixItPlanStore) -> Bool {
        guard let plan, !plan.items.isEmpty else { return false }
        return completedCount(store: store) == plan.items.count
    }

    /// Ticks a box, re-scores, and reports whether that completed the plan.
    @discardableResult
    func toggle(_ item: ChecklistItem, store: FixItPlanStore) -> Bool {
        guard let room else { return false }
        let wasComplete = store.isComplete(item.id, in: room.id)
        store.setComplete(!wasComplete, itemID: item.id, in: room.id)
        refreshProgressScore(store: store)
        let finished = !wasComplete && isFinished(store: store)
        if finished { celebrating = true }
        return finished
    }

    /// The trips that still have unfinished work in them, first.
    func trips(store: FixItPlanStore) -> [ShoppingTrip] {
        guard let plan else { return [] }
        let completed = completedItemIDs(store: store)
        return plan.trips.sorted { a, b in
            let aDone = a.itemIDs.allSatisfy { completed.contains($0) }
            let bDone = b.itemIDs.allSatisfy { completed.contains($0) }
            if aDone != bDone { return !aDone }
            return a.venue.order < b.venue.order
        }
    }

    func items(in trip: ShoppingTrip) -> [ChecklistItem] {
        guard let plan else { return [] }
        let ids = Set(trip.itemIDs)
        return plan.items.filter { ids.contains($0.id) }
    }
}
