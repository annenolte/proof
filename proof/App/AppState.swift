//
//  AppState.swift
//  Tremor — App shell / shared screen state
//
//  SPEC §1.1 principle 5 and §1.2: the room viewer, the earthquake configurator,
//  the running simulation and the report are **one screen with four sheet
//  states**, sitting on one persistent 3D stage. They therefore cannot each own
//  their own copy of the room, the assessment or the selection — the stage would
//  rebuild, the numbers would drift, and the sheet would flicker on every
//  transition.
//
//  So they share this. `AppState` holds exactly three things plus the two pieces
//  of chrome that must outlive any single screen:
//
//    • the currently open room and its latest assessment (S-12…S-16),
//    • the in-progress scan (S-07…S-11),
//    • which of the four sheet states the stage is showing, and what is selected,
//    • the global toast queue, because a toast raised by a screen that is being
//      dismissed still has to be seen.
//
//  Everything else — library rows, configurator inputs, checklist ticks — belongs
//  to the screen that owns it.
//

import Foundation
import Observation
import SwiftUI

// MARK: - Scan draft

/// A scan in progress, from the first question on S-07 to the moment the room is
/// written to the library.
///
/// Deliberately one value rather than a scatter of optionals across four
/// screens: cancelling a scan is then `draft = nil`, and there is no way to end
/// up on S-10 holding a result from a previous session.
struct ScanDraft {

    /// What the room will be called. Editable on S-10; defaults from the kind.
    var name: String
    var kind: RoomKind
    /// The four answers from S-07 that change the physics.
    var building: BuildingContext
    /// True when this came from a bundled fixture (S-08) rather than a capture.
    /// Everything downstream is genuine either way; this only changes copy.
    var isDemo: Bool
    var startedAt: Date

    /// Live geometry from the scanner, for the S-09 preview. Partial by nature.
    var preview: ScannedRoom?
    /// Coverage for the S-09 bar.
    var progress: ScanProgress
    /// The current coaching line, mapped from RoomPlan's instruction.
    var coaching: ScanCoaching?
    /// JPEG crops keyed by the scanner's own object identifier, re-keyed by the
    /// converter when the scan finishes.
    var liveCrops: [UUID: Data]

    /// Set once capture finishes. Present on S-10 and S-11.
    var result: ScanResult?
    /// Set when capture fails. S-09 renders a takeover for it.
    var error: ScanError?
    /// The user chose "Continue anyway" past a failed quality check, which puts
    /// a permanent caveat on the report (SPEC §1.4 S-10, S-15).
    var acceptedDegradedQuality: Bool

    init(
        name: String,
        kind: RoomKind = .bedroom,
        building: BuildingContext = BuildingContext(),
        isDemo: Bool = false,
        startedAt: Date = Date(),
        preview: ScannedRoom? = nil,
        progress: ScanProgress = ScanProgress(),
        coaching: ScanCoaching? = nil,
        liveCrops: [UUID: Data] = [:],
        result: ScanResult? = nil,
        error: ScanError? = nil,
        acceptedDegradedQuality: Bool = false
    ) {
        self.name = name
        self.kind = kind
        self.building = building
        self.isDemo = isDemo
        self.startedAt = startedAt
        self.preview = preview
        self.progress = progress
        self.coaching = coaching
        self.liveCrops = liveCrops
        self.result = result
        self.error = error
        self.acceptedDegradedQuality = acceptedDegradedQuality
    }

    var quality: ScanQualityReport? { result?.quality }

    /// True when the scan is finished and good enough to build a report from,
    /// either because it passed or because the user knowingly continued.
    var isReadyToProcess: Bool {
        guard let quality else { return false }
        return quality.passes || (quality.isUsable && acceptedDegradedQuality)
    }

    /// What the saved room will be called if the user does not rename it.
    static func defaultName(for kind: RoomKind) -> String { kind.displayName }
}

// MARK: - App state

/// The shared state behind the one-screen stage and the scan flow.
@MainActor
@Observable
final class AppState {

    /// Which of the four sheet states the stage is showing. Not a route: these
    /// never push, and the stage underneath them is never rebuilt.
    enum StagePhase: String, CaseIterable, Hashable, Sendable {
        /// S-12 — idle, `peek` detent.
        case viewer
        /// S-13 — configurator, `medium` detent.
        case configurator
        /// S-14 — running, sheet retracted to the transport bar.
        case running
        /// S-15 — results, `large` detent.
        case results
    }

    /// How the open room is doing. Four states, all of which S-12 renders.
    enum LoadPhase: Hashable, Sendable {
        case idle
        case loading
        case loaded
        /// Carries copy a person can act on, never a raw error description.
        case failed(String)

        var isLoading: Bool { self == .loading }

        var failureMessage: String? {
            if case .failed(let message) = self { return message }
            return nil
        }
    }

    // MARK: Open room

    private(set) var room: ScannedRoom?
    private(set) var assessment: RoomAssessment?
    private(set) var loadPhase: LoadPhase = .idle
    /// True while a fresh assessment is being computed. S-13's "Shake it" shows
    /// its spinner from this; S-15 skeletonises on it.
    private(set) var isAssessing = false

    var stagePhase: StagePhase = .viewer
    /// The object tapped on the stage or in the hazard list. Drives the outline
    /// on the stage, the sheet's summary card and S-16.
    var selectedObjectID: UUID?

    // MARK: Scan

    var draft: ScanDraft?

    // MARK: Chrome

    /// The global toast. Hosted once, at the root, so a toast survives the
    /// dismissal of whatever raised it.
    var toast: TremorToastMessage?

    // MARK: Dependencies

    @ObservationIgnored private let env: TremorEnvironment
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var assessTask: Task<Void, Never>?

    /// proof's whole room flow and the kitchen's sky. Owned here rather than by the Add Room
    /// screen so the Rooms tab can show the kitchen's progress and open it again.
    let addRoomFlow = AddRoomFlowModel()

    init(env: TremorEnvironment) {
        self.env = env
    }

    // MARK: - Opening a room

    /// Loads a room and its most recent assessment.
    ///
    /// Idempotent: asking for the room that is already open is a no-op, so a
    /// re-render of S-12 does not re-read the package from disk. Any in-flight
    /// load for a different room is cancelled first.
    func openRoom(id: UUID) {
        if room?.id == id, loadPhase == .loaded { return }
        loadTask?.cancel()
        assessTask?.cancel()
        isAssessing = false
        selectedObjectID = nil
        stagePhase = .viewer
        loadPhase = .loading

        loadTask = Task { [env] in
            do {
                let loaded = try await env.rooms.load(id: id)
                let latest = await env.rooms.latestAssessment(for: id)
                guard !Task.isCancelled else { return }
                self.room = loaded
                self.assessment = latest
                // Always land on S-12. A room that has been simulated before
                // shows "See the report" there rather than jumping past the
                // stage the user tapped to see.
                self.stagePhase = .viewer
                self.loadPhase = .loaded
            } catch {
                guard !Task.isCancelled else { return }
                self.room = nil
                self.assessment = nil
                self.loadPhase = .failed(Self.message(for: error))
            }
        }
    }

    /// Adopts a room the caller already has in hand — the one the scan flow just
    /// saved — without a round trip through the store.
    func adopt(room: ScannedRoom, assessment: RoomAssessment? = nil) {
        loadTask?.cancel()
        self.room = room
        self.assessment = assessment
        self.loadPhase = .loaded
        self.selectedObjectID = nil
        self.stagePhase = assessment == nil ? .viewer : .results
    }

    /// Releases the open room. Called when the stage is popped, so the stage's
    /// meshes and the assessment do not sit in memory behind the library.
    func closeRoom() {
        loadTask?.cancel()
        assessTask?.cancel()
        room = nil
        assessment = nil
        loadPhase = .idle
        isAssessing = false
        selectedObjectID = nil
        stagePhase = .viewer
    }

    /// Re-reads the open room after an edit elsewhere (a rename, a deleted
    /// object, a mitigation marked done).
    func reloadOpenRoom() {
        guard let id = room?.id else { return }
        loadPhase = .loading
        loadTask?.cancel()
        loadTask = Task { [env] in
            let loaded = try? await env.rooms.load(id: id)
            guard !Task.isCancelled else { return }
            if let loaded {
                self.room = loaded
                self.loadPhase = .loaded
            } else {
                self.loadPhase = .failed(Self.message(for: RoomStoreError.roomNotFound(id)))
            }
        }
    }

    /// The currently selected object, if it is still in the room.
    var selectedObject: ScannedObject? {
        guard let selectedObjectID else { return nil }
        return room?.object(id: selectedObjectID)
    }

    /// The risk for the selected object at the current intensity.
    var selectedRisk: ObjectRisk? {
        guard let selectedObjectID else { return nil }
        return assessment?.risk(for: selectedObjectID)
    }

    // MARK: - Assessing

    /// Runs the analytic verdict engine for the open room and keeps the result.
    ///
    /// The ensemble is twenty rigid-block solutions over synthetic accelerograms
    /// and takes long enough to be felt, so it runs off the main actor and the
    /// caller gets `isAssessing` to render against. Cancelling and re-running —
    /// which is what dragging the intensity selector does — is safe: only the
    /// last one assigns.
    func assess(intensity: MercalliIntensity, seed: UInt64 = 0x1ED6E, persists: Bool = true) {
        guard let room else { return }
        assessTask?.cancel()
        isAssessing = true

        assessTask = Task { [env] in
            let engine = env.risk
            let computed = await Task.detached(priority: .userInitiated) {
                engine.assess(room: room, intensity: intensity, seed: seed)
            }.value
            guard !Task.isCancelled else { return }
            self.assessment = computed
            self.isAssessing = false
            if persists {
                try? await env.rooms.saveAssessment(computed)
            }
        }
    }

    /// Awaits any assessment currently in flight. For screens that must not
    /// advance until the numbers exist — S-11's fourth step.
    func waitForAssessment() async {
        await assessTask?.value
    }

    // MARK: - The scan flow

    /// S-07 step 1. Seeds the draft from the user's saved defaults so someone on
    /// the third floor of a soft-soil block answers once, not once per room.
    func beginScan(kind: RoomKind = .bedroom, isDemo: Bool = false) {
        let building = env.account.profile?.homeBuilding ?? env.settings.defaultBuilding
        draft = ScanDraft(
            name: ScanDraft.defaultName(for: kind),
            kind: kind,
            building: building,
            isDemo: isDemo)
    }

    /// Mutates the draft in place. A no-op when there is no scan in progress, so
    /// a late scanner event arriving after a cancel cannot resurrect one.
    func updateDraft(_ mutate: (inout ScanDraft) -> Void) {
        guard var current = draft else { return }
        mutate(&current)
        draft = current
    }

    /// Folds one scanner event into the draft. The whole of S-09's state, in one
    /// place, so the view is a pure function of the draft.
    func apply(_ event: ScanEvent) {
        switch event {
        case .started:
            updateDraft { $0.error = nil }
        case .coaching(let coaching):
            updateDraft { $0.coaching = coaching }
        case .geometry(let room):
            updateDraft { $0.preview = room }
        case .capturedFrame(let objectID, let jpeg):
            updateDraft { $0.liveCrops[objectID] = jpeg }
        case .progress(let progress):
            updateDraft { $0.progress = progress }
        case .finished(let result):
            updateDraft {
                $0.result = result
                $0.preview = result.room
                $0.error = nil
            }
        case .failed(let error):
            updateDraft { $0.error = error }
        }
    }

    /// Abandons the scan. The draft is the only thing holding the capture's
    /// memory, so dropping it is the whole cleanup.
    func cancelScan() {
        draft = nil
    }

    /// Writes the scanned room, its crops and its building context to the
    /// library and returns the saved room.
    ///
    /// Throws only for a genuine write failure; a caller that gets a throw shows
    /// the error with a "Try again" and keeps the draft, so nothing is lost.
    @discardableResult
    func commitScan() async throws -> ScannedRoom {
        guard let draft, let result = draft.result else {
            throw RoomStoreError.writeFailed("There is no finished scan to save.")
        }

        var room = result.room
        room.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ScanDraft.defaultName(for: draft.kind)
            : draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        room.kind = draft.kind
        room.building = draft.building

        let saved = try await env.rooms.save(room)
        for (objectID, jpeg) in result.crops {
            try? await env.rooms.saveCrop(jpeg, objectID: objectID, roomID: saved.id)
        }
        return saved
    }

    // MARK: - Toasts

    /// Raises a toast at the root. Replacing a visible toast re-arms its timer,
    /// which is the behaviour a burst of events wants.
    func post(_ message: TremorToastMessage) {
        toast = message
    }

    func post(_ title: String, message: String? = nil, style: TremorToastStyle = .success) {
        toast = TremorToastMessage(title, message: message, style: style)
    }

    // MARK: - Errors

    /// Turns anything thrown into a sentence a person can act on. `RoomStore`
    /// already writes its own; everything else gets the honest generic rather
    /// than a Foundation string with a domain and a code in it.
    static func message(for error: Error) -> String {
        if let described = (error as? LocalizedError)?.errorDescription, !described.isEmpty {
            return described
        }
        return "Something went wrong opening this room. Try again in a moment."
    }
}
