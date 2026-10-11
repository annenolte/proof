//
//  ObjectDetailModel.swift
//  Tremor — S-16 object detail and mitigation
//
//  Everything S-16 renders, assembled once and kept until the object changes.
//
//  Two things here are load-bearing:
//
//  1. **The "after this fix" number is real.** It comes from re-running the
//     analytic engine on a copy of the room with the mitigation applied, at the
//     same intensity and the same seed. It is never an estimate, a percentage
//     off, or a look-up. If a fix changes nothing the model can represent, the
//     card says so instead of inventing an improvement.
//
//  2. **A correction re-scores immediately.** Changing what an object is, how
//     full it is, or whether it is already anchored writes through to the room,
//     saves it, and kicks a fresh assessment — so the user watches the number
//     move in response to something they said. That feedback loop is the whole
//     reason this screen exists.
//

import Foundation
import Observation
import SwiftUI

// MARK: - Corrections

/// The three things a user can tell us about an object that we might have got
/// wrong, plus the mass override that follows from the first two.
enum ObjectCorrection: Equatable {
    case type(ObjectType)
    case loading(LoadingState)
    case anchored(Bool)

    /// What the toast says after the change lands.
    var confirmation: String {
        switch self {
        case .type(let type): return "Now treated as a \(type.displayName.lowercased())"
        case .loading(let loading): return "Now treated as \(loading.displayName.lowercased())"
        case .anchored(let on): return on ? "Marked as already anchored" : "No longer marked as anchored"
        }
    }
}

// MARK: - Model

@MainActor
@Observable
final class ObjectDetailModel {

    /// What the screen can be showing.
    enum Phase: Equatable {
        /// Assembling: the room is loading, or the fix projections are running.
        case loading
        /// Everything is here.
        case ready
        /// The room is open but has never been shaken, so there is no verdict to
        /// show. Offers the way to get one.
        case notAssessed
        /// The object is not in the open room any more — a stale sheet.
        case missing
        /// Something failed in a way the user can retry.
        case failed(String)
    }

    // MARK: Inputs

    private(set) var objectID: UUID

    // MARK: Outputs

    private(set) var phase: Phase = .loading
    private(set) var room: ScannedRoom?
    private(set) var assessment: RoomAssessment?
    private(set) var object: ScannedObject?
    private(set) var risk: ObjectRisk?

    /// Ordered advice from the library, capped at the three the user will act on.
    private(set) var advice: [Mitigation] = []
    /// ASCE 7-22 sizing, present only where we are telling someone to bolt
    /// something to structure.
    private(set) var anchorage: AnchorageRequirement?
    /// Mitigation id → this object's score once that fix is done. Absent for a
    /// fix the rigid-block model cannot represent.
    private(set) var projectedScores: [String: Double] = [:]
    /// True while the projections are still being computed, so the cards can
    /// show a placeholder rather than a wrong number.
    private(set) var isProjecting = false
    /// True while a correction is being written and re-scored.
    private(set) var isApplyingCorrection = false
    /// The captured crop for the hero, when the scan kept one.
    private(set) var cropImage: Image?

    // MARK: Dependencies

    @ObservationIgnored private var env: TremorEnvironment?
    @ObservationIgnored private var appState: AppState?
    @ObservationIgnored private var projectionTask: Task<Void, Never>?

    init(objectID: UUID) {
        self.objectID = objectID
    }

    /// Called when the sheet goes away. Projections are the only long-running
    /// work here and there is no reason to finish one nobody will read.
    func cancel() {
        projectionTask?.cancel()
        projectionTask = nil
        isProjecting = false
    }

    // MARK: - Loading

    /// Reads the object out of the shared stage state and assembles everything
    /// around it. Safe to call repeatedly — it is what `.task(id:)` drives.
    func load(env: TremorEnvironment, appState: AppState) async {
        self.env = env
        self.appState = appState

        switch appState.loadPhase {
        case .idle, .loading:
            phase = .loading
            return
        case .failed(let message):
            phase = .failed(message)
            return
        case .loaded:
            break
        }

        guard let room = appState.room, let object = room.object(id: objectID) else {
            phase = .missing
            return
        }

        self.room = room
        self.object = object

        guard let assessment = appState.assessment else {
            self.assessment = nil
            self.risk = nil
            self.advice = Array(MitigationLibrary.advice(for: object, in: room)
                .prefix(Checklist.maximumFixesPerObject))
            self.anchorage = nil
            phase = .notAssessed
            await loadCrop(env: env, roomID: room.id)
            return
        }

        self.assessment = assessment
        self.risk = assessment.risk(for: objectID)

        let advice = Array(MitigationLibrary.advice(for: object, risk: risk, in: room)
            .prefix(Checklist.maximumFixesPerObject))
        self.advice = advice
        self.anchorage = Self.anchorage(for: object, in: room, advice: advice, assessment: assessment)

        phase = .ready
        await loadCrop(env: env, roomID: room.id)
        startProjections(room: room, object: object, advice: advice,
                         assessment: assessment, engine: env.risk)
    }

    private func loadCrop(env: TremorEnvironment, roomID: UUID) async {
        guard cropImage == nil else { return }
        let objectID = self.objectID
        let data = await env.rooms.loadCrop(objectID: objectID, roomID: roomID)
        guard let data, let uiImage = UIImage(data: data) else { return }
        cropImage = Image(uiImage: uiImage)
    }

    // MARK: - "After this fix"

    /// Re-runs the whole assessment on a mitigated copy of the room, once per
    /// fix, off the main actor.
    ///
    /// Same intensity, same seed, same engine configuration as the assessment on
    /// screen — anything else and the two numbers are not comparable, which is
    /// exactly the mistake a "20% safer" heuristic makes.
    private func startProjections(room: ScannedRoom, object: ScannedObject,
                                  advice: [Mitigation], assessment: RoomAssessment,
                                  engine: RiskEngine) {
        projectionTask?.cancel()
        let modelled = advice.filter(\.effect.isModelled)
        guard !modelled.isEmpty else {
            projectedScores = [:]
            isProjecting = false
            return
        }

        isProjecting = true
        projectionTask = Task { [weak self] in
            var results: [String: Double] = [:]
            for mitigation in modelled {
                if Task.isCancelled { return }
                let score = await Task.detached(priority: .userInitiated) { () -> Double? in
                    var mitigated = room
                    guard let index = mitigated.objects.firstIndex(where: { $0.id == object.id })
                    else { return nil }
                    mitigated.objects[index] = Checklist.apply(
                        mitigation.effect, to: object, in: room)
                    let after = engine.assess(
                        room: mitigated, intensity: assessment.intensity, seed: assessment.seed)
                    return after.risk(for: object.id)?.score
                }.value
                if let score { results[mitigation.id] = score }
            }
            guard !Task.isCancelled else { return }
            self?.projectedScores = results
            self?.isProjecting = false
        }
    }

    /// The score this object would carry once `mitigation` is done, capped so a
    /// fix can never be shown as making things worse — the ensemble is
    /// stochastic and a one-point rise is noise, not advice.
    func projectedScore(for mitigation: Mitigation) -> Double? {
        guard let current = risk?.score, let projected = projectedScores[mitigation.id] else {
            return nil
        }
        return min(projected, current)
    }

    func projectedBand(for mitigation: Mitigation) -> RiskBand? {
        projectedScore(for: mitigation).map(RiskBand.init(score:))
    }

    /// The single best outcome available for this object, used by the header.
    var bestProjectedScore: Double? {
        let scores = advice.compactMap { projectedScore(for: $0) }
        return scores.min()
    }

    // MARK: - Corrections

    /// Writes a correction through to the room, saves it, and re-scores.
    ///
    /// The mass follows the type and the loading unless the user has set it by
    /// hand — a dresser reclassified as a wardrobe that kept the dresser's mass
    /// would be a worse answer than the one we started with.
    @discardableResult
    func apply(_ correction: ObjectCorrection) async -> String? {
        guard let env, let appState, var room, let object else { return nil }
        guard let index = room.objects.firstIndex(where: { $0.id == objectID }) else {
            phase = .missing
            return nil
        }

        isApplyingCorrection = true
        defer { isApplyingCorrection = false }

        var updated = object
        switch correction {
        case .type(let type):
            guard type != object.type else { return nil }
            updated.type = type
            updated.provenance = IdentificationProvenance(
                source: .user, confidence: 1.0, scannerCategory: object.provenance.scannerCategory)
            if !updated.massIsUserSet {
                updated.mass = MassEstimator.mass(
                    type: type, extents: updated.extents, loading: updated.loading)
            }
            updated.centreOfMassHeight = Double(updated.extents.height) * type.centreOfMassFraction
            if object.mounting == object.type.defaultMounting {
                updated.mounting = type.defaultMounting
            }

        case .loading(let loading):
            guard loading != object.loading else { return nil }
            updated.loading = loading
            if !updated.massIsUserSet {
                updated.mass = MassEstimator.mass(
                    type: updated.type, extents: updated.extents, loading: loading)
            }

        case .anchored(let isAnchored):
            guard isAnchored != object.isAnchored else { return nil }
            updated.isAnchored = isAnchored
            if isAnchored {
                updated.mounting = .anchored
            } else if object.mounting == .anchored {
                updated.mounting = updated.type.defaultMounting
            }
        }

        room.objects[index] = updated
        room.updatedAt = Date()

        do {
            let saved = try await env.rooms.save(room)
            appState.adopt(room: saved, assessment: appState.assessment)
            appState.selectedObjectID = objectID
            self.room = saved
            self.object = saved.object(id: objectID)

            // Re-score at the intensity already on screen, so the number the
            // user is watching is the number that moves.
            if let intensity = appState.assessment?.intensity {
                appState.assess(intensity: intensity)
                await appState.waitForAssessment()
            }
            await load(env: env, appState: appState)
            return correction.confirmation
        } catch {
            phase = .failed(AppState.message(for: error))
            return nil
        }
    }

    // MARK: - Derived copy

    /// "This bookcase topples onto the bed." — one sentence, no jargon.
    var verdictSentence: String {
        guard let object, let risk else {
            return "Shake the room to find out what happens to this."
        }
        let headline = ReportBuilder.headline(risk: risk, object: object)
        return "\(headline)."
    }

    /// The honest note when the app is guessing at what this is.
    var provenanceNote: String? {
        guard let object else { return nil }
        let provenance = object.provenance
        switch provenance.source {
        case .user:
            return nil
        case .scanner where provenance.isUncertain,
             .onDeviceVision where provenance.isUncertain,
             .cloudVision where provenance.isUncertain:
            return "Your scanner reported this as “\(provenance.scannerCategory)”, and we are not "
                + "confident it is a \(object.type.displayName.lowercased()). "
                + "If that is wrong, set it below — the score updates straight away."
        case .scanner:
            return "Your scanner reported this as “\(provenance.scannerCategory)”. "
                + "We filled in the rest from a catalogue of typical furniture."
        case .onDeviceVision, .cloudVision:
            return nil
        }
    }

    /// The provenance chip beside the weight: what refined this number.
    var massProvenanceChip: String {
        guard let object else { return "Estimated" }
        if object.massIsUserSet { return "You set this" }
        switch object.provenance.source {
        case .user: return "You set this"
        case .cloudVision, .onDeviceVision: return "AI-refined"
        case .scanner: return "Estimated"
        }
    }

    var massChipIsCaution: Bool {
        guard let object else { return true }
        return !object.massIsUserSet && object.provenance.source == .scanner
    }

    /// Behaviour counts across the ensemble, worst first, as sentences.
    var outcomeLines: [(label: String, share: Double)] {
        guard let risk else { return [] }
        let order: [RigidBlockSolver.Behaviour] = [
            .overturned, .fellOffSupport, .slid, .rocked, .restrained, .stable,
        ]
        return order.compactMap { behaviour in
            guard let share = risk.behaviourDistribution[behaviour.rawValue], share > 0.001
            else { return nil }
            return (Self.outcomeLabel(behaviour), share)
        }
    }

    static func outcomeLabel(_ behaviour: RigidBlockSolver.Behaviour) -> String {
        switch behaviour {
        case .overturned: return "Falls over"
        case .fellOffSupport: return "Comes off what it sits on"
        case .slid: return "Slides across the floor"
        case .rocked: return "Rocks but stays up"
        case .restrained: return "Held by its fixings"
        case .stable: return "Doesn't move"
        }
    }

    /// True when there is genuinely nothing to do: a sink, a fireplace, the
    /// stairs. The fix block is replaced with a plain statement rather than a
    /// made-up recommendation.
    var isBuiltIn: Bool {
        guard let object else { return false }
        switch object.type {
        case .sink, .toilet, .bathtub, .fireplace, .stairs:
            return true
        default:
            return false
        }
    }

    /// The likely alternatives, for the one-tap corrections. Always includes the
    /// current type so the row reads as a selection rather than a command.
    var typeCandidates: [ObjectType] {
        guard let object else { return [] }
        var seen = Set<ObjectType>()
        var out: [ObjectType] = []
        for candidate in [object.type]
            + ObjectType.candidates(forRoomPlanCategory: object.provenance.scannerCategory) {
            if seen.insert(candidate).inserted { out.append(candidate) }
        }
        return out
    }

    // MARK: - Anchorage

    private static func anchorage(
        for object: ScannedObject, in room: ScannedRoom,
        advice: [Mitigation], assessment: RoomAssessment
    ) -> AnchorageRequirement? {
        guard advice.contains(where: { $0.effect.setsAnchored }) else { return nil }
        // S_DS ≈ 2.5 × PGA, the standard short-period plateau. Same relationship
        // the PDF uses, so the app and the report size the same hardware.
        let sds = min(max(2.5 * assessment.groundAccelerationInG, 0.1), 2.0)
        return AnchorageCalculator.requirement(for: object, in: room, sds: sds)
    }
}
