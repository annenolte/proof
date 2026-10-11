//
//  ProcessingView.swift
//  Tremor — S-11, object understanding and physics precomputation
//
//  This is where Tremor earns trust. The user has just walked around their
//  bedroom holding a phone; now something happens that they cannot see, and the
//  only honest thing to do is show it happening.
//
//  So there is no spinner. There is a room that fills in — walls, then floor,
//  then each piece of furniture as it is actually identified, with its name — and
//  four steps that say plainly what is being done and what the answer was:
//  "9 objects, 4 walls and 1 door", "Tall bookshelf, dresser, bed…", "about
//  86 kg (66–106 kg)", "Peak shaking at your floor: 0.31 g".
//
//  Three rules the screen never breaks:
//
//   • **It never blocks on the network.** The catalogue prior alone gives every
//     object a defensible profile (SPEC §5.6.4), so the cloud pass is a bonus
//     that can fail silently. When it is off, unreachable or declined, step 2
//     says "Using on-device identification" and nothing else changes.
//   • **It is always cancellable.** Anything the user started, the user can stop.
//   • **It admits when it is slow.** Past twenty seconds it offers to finish with
//     Tremor's own estimates; past thirty-five it says why it is waiting.
//

import Foundation
import Observation
import SwiftUI

// MARK: - Model

/// Runs the whole of S-11 and publishes exactly what the screen renders.
@MainActor
@Observable
final class ProcessingModel {

    /// SPEC §1.4 S-11's four steps, in the order they are shown. They can
    /// complete out of order; each is marked independently.
    enum Step: Int, CaseIterable, Identifiable {
        case reading
        case identifying
        case weighing
        case shaking

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .reading: return "Reading the room"
            case .identifying: return "Identifying objects"
            case .weighing: return "Estimating weight and balance"
            case .shaking: return "Running the earthquake"
            }
        }
    }

    enum StepState: Equatable {
        case pending, active, done
    }

    private(set) var states: [StepState] = Array(repeating: .pending, count: Step.allCases.count)
    private(set) var details: [String] = Array(repeating: "", count: Step.allCases.count)

    /// The room as it is understood right now — object types update live as the
    /// pipeline refines them, so the drawing's labels are never stale.
    private(set) var room: ScannedRoom?
    private(set) var revealedObjectIDs: Set<UUID> = []
    private(set) var labelledObjectIDs: [UUID] = []

    /// Set when the cloud pass could not be used, with the reason in plain
    /// words. Never an error, never blocking (SPEC §1.4 S-11 "AI unavailable").
    private(set) var cloudNote: String?
    /// True when the run asked for cloud refinement at all.
    private(set) var isCloudRequested = false
    /// True while the one-time consent question is on screen.
    private(set) var isAwaitingConsent = false

    private(set) var elapsed: TimeInterval = 0
    private(set) var isFinished = false
    /// Set only by a hard failure: no objects at all, or the engine throwing.
    private(set) var failure: String?

    /// SPEC: after 20 s a tertiary "Skip AI details" appears.
    var showsSkip: Bool {
        isCloudRequested && !isFinished && failure == nil && elapsed >= Budget.offerSkip
            && states[Step.identifying.rawValue] == .active
    }

    /// And past the §1.3 budget we say why, rather than letting it sit there.
    var showsSlowNotice: Bool {
        !isFinished && failure == nil && elapsed >= Budget.explainSlowness
    }

    /// 0…1 across the four steps, for the ring.
    var progress: Double {
        let done = states.filter { $0 == .done }.count
        let active = states.contains(.active) ? 0.5 : 0
        return min((Double(done) + active) / Double(Step.allCases.count), 1)
    }

    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var pumpTask: Task<Void, Never>?
    @ObservationIgnored private var classifyTask: Task<[UUID: ClassificationResult], Never>?
    @ObservationIgnored private var consentContinuation: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var pendingReveals: [(id: UUID, result: ClassificationResult?)] = []
    @ObservationIgnored private var classificationFinished = false
    @ObservationIgnored private var skippedCloud = false
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var revealCadence: UInt64 = 90_000_000

    /// Where to go when everything is done. The view supplies it.
    var onFinished: ((UUID) -> Void)?

    // MARK: Entry

    func run(env: TremorEnvironment, appState: AppState, reduceMotion: Bool) {
        guard runTask == nil else { return }
        revealCadence = reduceMotion ? 0 : 90_000_000
        startedAt = Date()

        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self, !Task.isCancelled else { return }
                self.elapsed = Date().timeIntervalSince(self.startedAt)
            }
        }

        runTask = Task { @MainActor [weak self] in
            await self?.pipeline(env: env, appState: appState)
        }
    }

    /// The user backed out. Nothing is written, nothing is left running.
    func cancel() {
        resumeConsent(with: false)
        runTask?.cancel(); runTask = nil
        tickTask?.cancel(); tickTask = nil
        pumpTask?.cancel(); pumpTask = nil
        classifyTask?.cancel(); classifyTask = nil
    }

    /// "Skip AI details" — cancels the in-flight cloud work and finalises from
    /// the catalogue priors, which is the answer the report would have used
    /// anyway if the network had simply been off.
    func skipCloud() {
        guard !skippedCloud else { return }
        skippedCloud = true
        classifyTask?.cancel()
        cloudNote = "You skipped the extra detail, so proof used its own estimates."
    }

    func answerConsent(_ allow: Bool, env: TremorEnvironment) {
        guard isAwaitingConsent else { return }
        isAwaitingConsent = false
        UserDefaults.standard.set(true, forKey: Self.consentAskedKey)
        if allow { env.settings.cloudIdentificationEnabled = true }
        resumeConsent(with: allow)
    }

    // MARK: The pipeline

    private func pipeline(env: TremorEnvironment, appState: AppState) async {
        guard let draft = appState.draft, let result = draft.result else {
            failure = "This scan isn't open any more. Start a new one and we'll pick it up from there."
            return
        }

        // ── 1. Reading the room ───────────────────────────────────────────────
        set(.reading, .active)
        var working = result.room
        working.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ScanDraft.defaultName(for: draft.kind)
            : draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        working.kind = draft.kind
        working.building = draft.building
        room = working
        detail(.reading, ScanFlowCopy.inventory(result.quality))

        guard !working.objects.isEmpty else {
            failure = "We couldn't find anything in this room that could fall. Scanning again, sweeping slowly across each wall, usually finds it."
            set(.reading, .done)
            return
        }
        set(.reading, .done)
        guard !Task.isCancelled else { return }

        // ── 2. Identifying objects ────────────────────────────────────────────
        set(.identifying, .active)
        let allowCloud = await resolveCloudPermission(env: env)
        isCloudRequested = allowCloud
        if !allowCloud && cloudNote == nil {
            detail(.identifying, "Using on-device identification")
        }

        startRevealPump()
        let crops = result.crops
        let roomForClassification = working
        let classifier = env.classifier

        let task = Task<[UUID: ClassificationResult], Never> { [weak self] in
            await classifier.classify(
                room: roomForClassification,
                crops: crops,
                allowCloud: allowCloud
            ) { progress in
                Task { @MainActor in self?.absorb(progress) }
            }
        }
        classifyTask = task
        var profiles = await task.value

        // A cancelled cloud run still owes every object a profile. The
        // catalogue is the anchor, so re-running prior-only is instant and
        // produces exactly what a phone with no network would have produced.
        if Task.isCancelled { return }
        if profiles.count < working.objects.count {
            let fallback = ObjectClassifier()
            for object in working.objects where profiles[object.id] == nil {
                let request = ClassificationRequest(object: object, in: working, cropJPEG: nil)
                profiles[object.id] = await fallback.classify(request, allowCloud: false)
            }
        }

        for object in working.objects where !revealedObjectIDs.contains(object.id) {
            enqueueReveal(object.id, profiles[object.id])
        }
        classificationFinished = true
        await drainReveals()
        guard !Task.isCancelled else { return }

        working.objects = working.objects.map { object in
            profiles[object.id]?.applied(to: object) ?? object
        }
        room = working
        detail(.identifying, identifiedSummary(working))
        set(.identifying, .done)
        set(.weighing, .done)

        // ── 3. Saving, so the report has something to belong to ───────────────
        // A fresh identifier every time: a demo room replayed twice is two
        // rooms, not one room overwritten, and a bundled fixture in the library
        // is never clobbered by a scan of it.
        working.id = UUID()
        appState.updateDraft { $0.result?.room = working }

        let saved: ScannedRoom
        do {
            saved = try await appState.commitScan()
        } catch {
            failure = AppState.message(for: error)
            return
        }
        guard !Task.isCancelled else { return }

        // ── 4. Running the earthquake ─────────────────────────────────────────
        set(.shaking, .active)
        let intensity = env.settings.defaultIntensity
        detail(.shaking, "\(env.risk.ensembleSize) ground motions at \(intensity.roman), back to back")
        appState.adopt(room: saved)
        appState.assess(intensity: intensity)
        await appState.waitForAssessment()
        guard !Task.isCancelled else { return }

        if let assessment = appState.assessment {
            detail(.shaking, Self.shakingSummary(assessment, room: saved))
        } else {
            detail(.shaking, "Done — your report is ready.")
        }
        set(.shaking, .done)
        isFinished = true
        TremorHaptic.success.play()
        onFinished?(saved.id)
    }

    // MARK: Cloud permission

    /// The §5.6.4 ladder: opted in already, opted out already, never asked, or
    /// simply no usable connection. Only "never asked, and a connection exists"
    /// puts a question on screen, and it is asked exactly once.
    private func resolveCloudPermission(env: TremorEnvironment) async -> Bool {
        guard env.network.isOnline, !env.network.isConstrained else {
            cloudNote = env.network.isOnline
                ? "You're on a metered connection, so proof used its own estimates."
                : "You're offline, so proof used its own estimates."
            return false
        }
        if env.settings.cloudIdentificationEnabled { return true }
        if env.isPreview { return false }
        if UserDefaults.standard.bool(forKey: Self.consentAskedKey) {
            cloudNote = "Smarter details are off. You can turn them on in Settings."
            return false
        }

        isAwaitingConsent = true
        let allowed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            consentContinuation = continuation
        }
        if !allowed {
            cloudNote = "Everything stayed on your iPhone. You can change that in Settings."
        }
        return allowed
    }

    private func resumeConsent(with value: Bool) {
        guard let continuation = consentContinuation else { return }
        consentContinuation = nil
        isAwaitingConsent = false
        continuation.resume(returning: value)
    }

    // MARK: Progress

    private func absorb(_ progress: UnderstandingProgress) {
        switch progress {
        case .geometryComplete:
            break
        case .priorComplete(let objectID, _):
            enqueueReveal(objectID, nil)
        case .visionComplete(let objectID, let type):
            refine(objectID, to: type)
        case .cloudComplete(let objectID, _):
            _ = objectID
        case .cloudUnavailable(let reason):
            cloudNote = reason
            detail(.identifying, "Using on-device identification")
        case .finished:
            classificationFinished = true
        }
    }

    /// The pipeline resolves objects in parallel and can finish a whole room in
    /// milliseconds when the cloud is off. Revealing them at a floor cadence is
    /// not a fake progress bar — the work is genuinely done — it is the
    /// difference between watching a room fill in and watching it blink.
    private func enqueueReveal(_ id: UUID, _ result: ClassificationResult?) {
        guard !revealedObjectIDs.contains(id),
              !pendingReveals.contains(where: { $0.id == id }) else { return }
        pendingReveals.append((id, result))
    }

    private func startRevealPump() {
        guard pumpTask == nil else { return }
        pumpTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.pendingReveals.isEmpty {
                    if self.classificationFinished { return }
                    try? await Task.sleep(nanoseconds: 40_000_000)
                    continue
                }
                let next = self.pendingReveals.removeFirst()
                self.reveal(next.id, next.result)
                if self.revealCadence > 0 {
                    try? await Task.sleep(nanoseconds: self.revealCadence)
                }
            }
        }
    }

    /// Finishes the queue itself rather than waiting on the pump, so a pump that
    /// has already exited — it does, the moment the queue empties and the
    /// pipeline reports finished — can never strand the last few objects.
    private func drainReveals() async {
        pumpTask?.cancel()
        pumpTask = nil
        while !pendingReveals.isEmpty {
            if Task.isCancelled { return }
            let next = pendingReveals.removeFirst()
            reveal(next.id, next.result)
            if revealCadence > 0 {
                try? await Task.sleep(nanoseconds: revealCadence)
            }
        }
    }

    private func reveal(_ id: UUID, _ result: ClassificationResult?) {
        guard let object = room?.object(id: id) else { return }
        revealedObjectIDs.insert(id)
        labelledObjectIDs.append(id)
        if states[Step.weighing.rawValue] == .pending {
            set(.weighing, .active)
        }
        let mass = result?.mass
            ?? ObjectClassifier.priorMass(type: object.type,
                                          extents: object.extents,
                                          loading: object.loading)
        detail(.weighing, "\(object.type.displayName) — \(mass.displayString)")
        detail(.identifying, identifiedSummary(room))
    }

    private func refine(_ id: UUID, to type: ObjectType) {
        guard var current = room,
              let index = current.objects.firstIndex(where: { $0.id == id }) else { return }
        current.objects[index].type = type
        room = current
        detail(.identifying, identifiedSummary(current))
    }

    private func identifiedSummary(_ room: ScannedRoom?) -> String {
        guard let room else { return "" }
        let names = room.objects
            .filter { revealedObjectIDs.contains($0.id) }
            .map(\.type.displayName)
        guard let newest = names.last else {
            return "Looking at the first piece of furniture"
        }
        // The two most recent names and an honest count. More than two and the
        // line wraps, and a wrapping line that changes twice a second is noise.
        var shown = newest
        if names.count > 1 {
            shown += ", " + names[names.count - 2].lowercased()
        }
        return "\(shown) · \(names.count) of \(room.objects.count)"
    }

    static func shakingSummary(_ assessment: RoomAssessment, room: ScannedRoom) -> String {
        let peak = String(format: "%.2f", assessment.floorAccelerationInG)
        if let worst = assessment.risksNeedingAction.first,
           let object = room.object(id: worst.objectID) {
            return "Peak \(peak) g at your floor · \(object.type.displayName) is the worst of it"
        }
        return "Peak \(peak) g at your floor"
    }

    // MARK: Step plumbing

    private func set(_ step: Step, _ state: StepState) {
        states[step.rawValue] = state
    }

    private func detail(_ step: Step, _ text: String) {
        details[step.rawValue] = text
    }

    /// Remembered outside `AppSettings` because "asked and declined" is not the
    /// same as "never asked", and the settings value only records a yes.
    static let consentAskedKey = "com.annenolte.proof.scanflow.hasAskedCloudConsent"

    enum Budget {
        /// SPEC §1.4 S-11: the skip appears after twenty seconds.
        static let offerSkip: TimeInterval = 20
        /// SPEC §1.3 budgets ≤ 90 s of app time for the whole flow; past this we
        /// owe the user an explanation rather than more waiting.
        static let explainSlowness: TimeInterval = 35
    }
}

// MARK: - S-11

struct ProcessingView: View {

    @Environment(\.tremor) private var tremor
    @Environment(Router.self) private var router
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model = ProcessingModel()
    @State private var isConfirmingCancel = false

    var body: some View {
        ZStack {
            TremorColor.canvas.ignoresSafeArea()

            if let failure = model.failure {
                failureState(failure)
            } else {
                content
            }

            if model.isAwaitingConsent {
                CloudConsentDialog(
                    onAllow: { model.answerConsent(true, env: tremor) },
                    onDecline: { model.answerConsent(false, env: tremor) })
            }
        }
        .onAppear {
            model.onFinished = { roomID in
                appState.draft = nil
                router.openRoom(roomID)
            }
            model.run(env: tremor, appState: appState, reduceMotion: reduceMotion)
        }
        .onDisappear { if !model.isFinished { model.cancel() } }
        .confirmationDialog(
            "Stop building this report?",
            isPresented: $isConfirmingCancel,
            titleVisibility: .visible
        ) {
            Button("Stop and discard", role: .destructive) { abandon() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("The scan hasn't been saved yet, so you'd need to scan this room again.")
        }
    }

    // MARK: Running

    private var content: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: TremorSpacing.xl) {
                    figure

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(ProcessingModel.Step.allCases) { step in
                            ProcessingStepRow(
                                index: step.rawValue + 1,
                                title: step.title,
                                detail: model.details[step.rawValue],
                                state: model.states[step.rawValue],
                                isLast: step == ProcessingModel.Step.allCases.last)
                            .animation(
                                TremorMotion.resolved(TremorMotion.change,
                                                     reduceMotion: reduceMotion),
                                value: model.states[step.rawValue])
                        }
                    }

                    if let note = model.cloudNote {
                        Text(note)
                            .tremorType(.footnote)
                            .foregroundStyle(TremorColor.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Smarter details are off. \(note)")
                    }

                    if model.showsSlowNotice {
                        TremorBanner(
                            "This is taking longer than usual",
                            message: "Identification is waiting on the network. Everything proof needs for your report is already on this iPhone — you can finish without it.",
                            kind: .neutral,
                            actionTitle: model.showsSkip ? "Use proof's estimates" : nil,
                            action: model.showsSkip ? { model.skipCloud() } : nil)
                    }
                }
                .padding(.vertical, TremorSpacing.lg)
            }

            footer
        }
        .tremorScreen(inset: TremorSpacing.md)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: TremorSpacing.sm) {
            TremorIconButton(
                systemImage: "xmark",
                style: .ghost,
                size: .medium,
                label: "Stop building the report",
                action: { isConfirmingCancel = true })

            VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                Text("Building your report")
                    .tremorType(.title2)
                    .foregroundStyle(TremorColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("About twenty seconds. You can leave this running.")
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, TremorSpacing.xs)
        .padding(.bottom, TremorSpacing.md)
    }

    /// SPEC §1.4 S-11: "a 200 pt square isometric room render at the top that
    /// fills in progressively".
    private var figure: some View {
        IsometricRoomPlate {
            IsometricRoomFigure(
                room: model.room,
                revealedObjectIDs: model.revealedObjectIDs,
                labelledObjectIDs: model.labelledObjectIDs,
                padding: TremorSpacing.lg,
                showsFloor: model.states[ProcessingModel.Step.reading.rawValue] != .pending,
                accessibilityDescription: model.details[ProcessingModel.Step.reading.rawValue])
            .frame(height: Metric.figure)
            .frame(maxWidth: .infinity)
            // Only the drawing animates. Animating the whole screen makes the
            // live detail lines cross-dissolve into themselves, which renders
            // as two sentences printed on top of each other.
            .animation(TremorMotion.resolved(TremorMotion.reveal, reduceMotion: reduceMotion),
                       value: model.revealedObjectIDs)
        }
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private var footer: some View {
        if model.showsSkip {
            TremorButton("Skip the extra detail", variant: .tertiary, size: .medium,
                        hint: "Finishes now using proof's own estimates") {
                model.skipCloud()
            }
            .padding(.bottom, TremorSpacing.ctaBottomInset)
        }
    }

    // MARK: Failure

    private func failureState(_ message: String) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            TremorEmptyState(
                title: "We couldn't build a report from this scan",
                message: message,
                systemImage: "exclamationmark.triangle",
                actionTitle: "Scan again",
                actionHint: "Starts a new scan of this room",
                action: { restartScan() })
            Spacer(minLength: 0)
            TremorButton("Back to my rooms", variant: .tertiary, size: .medium) { abandon() }
                .padding(.horizontal, TremorSpacing.pageInset)
                .padding(.bottom, TremorSpacing.ctaBottomInset)
        }
    }

    // MARK: Actions

    private func abandon() {
        model.cancel()
        appState.cancelScan()
        router.cancelScan()
    }

    private func restartScan() {
        model.cancel()
        let kind = appState.draft?.kind ?? .bedroom
        let isDemo = appState.draft?.isDemo ?? false
        appState.beginScan(kind: kind, isDemo: isDemo)
        router.startScan(deviceCanScan: tremor.capabilities.supportsRoomScanning)
    }

    private enum Metric {
        static let figure: CGFloat = 200
    }
}

// MARK: - Step row

/// Zip §7.6's numbered stepper: a 32 pt circle, the label, and a detail line
/// that changes as the work happens. Completed steps get a check, so the state
/// is never carried by fill colour alone.
struct ProcessingStepRow: View {

    let index: Int
    let title: String
    let detail: String
    let state: ProcessingModel.StepState
    let isLast: Bool

    private var circleFill: Color {
        switch state {
        case .pending: return TremorColor.surfaceSunken
        case .active: return TremorColor.primary
        case .done: return TremorColor.primarySoft
        }
    }

    private var circleInk: Color {
        switch state {
        case .pending: return TremorColor.inkTertiary
        case .active: return TremorColor.onPrimary
        case .done: return TremorColor.primary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: TremorSpacing.md) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(circleFill)
                    if state == .done {
                        Image(systemName: "checkmark")
                            .font(.system(size: TremorControlMetrics.glyphSmall, weight: .bold))
                            .foregroundStyle(circleInk)
                    } else {
                        Text("\(index)")
                            .tremorType(.subheadline, numeric: true)
                            .foregroundStyle(circleInk)
                    }
                }
                .frame(width: Metric.circle, height: Metric.circle)

                if !isLast {
                    Rectangle()
                        .fill(TremorColor.divider)
                        .frame(width: TremorSize.hairline)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, TremorSpacing.xxs)
                }
            }
            .frame(width: Metric.circle)

            VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                Text(title)
                    .tremorType(.bodyEmphasis)
                    .foregroundStyle(state == .pending ? TremorColor.inkTertiary : TremorColor.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if !detail.isEmpty {
                    Text(detail)
                        .tremorType(.callout)
                        .foregroundStyle(TremorColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, isLast ? 0 : TremorSpacing.lg)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(index). \(title)")
        .accessibilityValue(spokenState)
    }

    private var spokenState: String {
        switch state {
        case .pending: return "Waiting"
        case .active: return detail.isEmpty ? "In progress" : "In progress. \(detail)"
        case .done: return detail.isEmpty ? "Done" : "Done. \(detail)"
        }
    }

    private enum Metric {
        static let circle: CGFloat = 32
    }
}

// MARK: - Cloud consent

/// SPEC §5.6.4: asked once, immediately before the first cloud call would
/// happen, with two equal-weight answers and no default.
///
/// Stacked full-width buttons rather than side-by-side (Lyft §7.4), and the
/// decline is a real answer that is remembered — not a dismissal.
struct CloudConsentDialog: View {

    let onAllow: () -> Void
    let onDecline: () -> Void

    var body: some View {
        ZStack {
            TremorColor.scrim.ignoresSafeArea()

            VStack(alignment: .leading, spacing: TremorSpacing.md) {
                Text("Want sharper identification?")
                    .tremorType(.title3)
                    .foregroundStyle(TremorColor.ink)
                    .accessibilityAddTraits(.isHeader)

                Text("proof can send a small photo of each object to an AI model, which names it more precisely and sharpens the weight estimate. Photos are never stored, nothing with a face in it is ever sent, and your report works fine without this.")
                    .tremorType(.callout)
                    .foregroundStyle(TremorColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: TremorSpacing.xs) {
                    // Equal weight on purpose (SPEC §5.6.4): this is a privacy
                    // decision, so neither answer is the one we push.
                    TremorButton("Use AI identification",
                                variant: .secondary, size: .medium, action: onAllow)
                    TremorButton("Keep it on my iPhone",
                                variant: .secondary, size: .medium, action: onDecline)
                }
            }
            .padding(TremorSpacing.xl)
            .frame(maxWidth: Metric.dialog)
            .background(TremorColor.surface,
                        in: RoundedRectangle(cornerRadius: TremorRadius.modal, style: .continuous))
            .tremorShadow(.modal)
            .padding(.horizontal, TremorSpacing.pageInset)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private enum Metric {
        static let dialog: CGFloat = 340
    }
}

// MARK: - Previews

#Preview("S-11 processing") {
    ScanFlowPreviewHost(stage: .processing)
}

#Preview("S-11 steps") {
    ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            ProcessingStepRow(index: 1, title: "Reading the room",
                              detail: "9 objects, 4 walls and 1 door",
                              state: .done, isLast: false)
            ProcessingStepRow(index: 2, title: "Identifying objects",
                              detail: "Tall bookshelf, dresser, bed… 3 of 9",
                              state: .active, isLast: false)
            ProcessingStepRow(index: 3, title: "Estimating weight and balance",
                              detail: "Tall bookshelf — about 86 kg (66–106 kg)",
                              state: .active, isLast: false)
            ProcessingStepRow(index: 4, title: "Running the earthquake",
                              detail: "", state: .pending, isLast: true)
        }
        .padding(TremorSpacing.md)
    }
    .background(TremorColor.canvas)
}

#Preview("S-11 consent") {
    ZStack {
        TremorColor.canvas.ignoresSafeArea()
        CloudConsentDialog(onAllow: {}, onDecline: {})
    }
}
