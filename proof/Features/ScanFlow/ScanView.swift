//
//  ScanView.swift
//  Tremor — S-09, live capture
//
//  The one screen in Tremor where the user is doing physical work — walking
//  around a room holding a phone at arm's length — so everything here is built
//  for that posture: nothing to read, one instruction at a time, a progress
//  indication that answers "where do I point next" rather than "how long left",
//  and a single confident way to stop.
//
//  The coverage bar is driven by `ScanCoach.progress`, which counts real walls,
//  real floors, real openings and real furniture. There is no timer anywhere in
//  it. A scan that finds nothing shows nothing, which is the honest thing to
//  show and also the thing that makes the user move.
//
//  On a LiDAR iPhone layer 0 is Apple's `RoomCaptureView` — the animated wall
//  visualiser and its VoiceOver guidance are not worth rebuilding. Everywhere
//  else (the Simulator, a non-Pro iPhone, every `#Preview`) `ReplayScanner`
//  drives the same event stream and layer 0 becomes the isometric drawing,
//  assembling itself wall by wall. Both paths run identical UI code.
//

import AVFoundation
import Foundation
import Observation
import SwiftUI

#if canImport(RoomPlan)
import RoomPlan
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Session model

/// Owns the scanner and everything about a capture that is not in the draft:
/// which phase it is in, how long it has run, whether the phone is hot, and
/// whether the app was sent to the background halfway through.
///
/// The geometry, the coaching and the coverage live in `AppState.draft` —
/// exactly one copy, folded there by `AppState.apply(_:)` — so this type never
/// duplicates them and the view stays a pure function of the draft.
@MainActor
@Observable
final class ScanSessionModel {

    enum Phase: Equatable {
        /// Nothing has been started yet.
        case idle
        /// The session is up but no geometry has arrived. SPEC: the HUD is
        /// hidden and the screen says "Point at a wall to begin."
        case preparing
        /// Geometry is flowing.
        case scanning
        /// The app was backgrounded mid-capture and we owe the user a decision.
        case interrupted
        /// "Done scanning" was pressed; RoomPlan is building the room.
        case finishing
        /// A result was delivered.
        case finished
        case failed(ScanError)

        var isLive: Bool { self == .preparing || self == .scanning || self == .interrupted }
        var isTerminal: Bool {
            if case .failed = self { return true }
            return self == .finished
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var elapsed: TimeInterval = 0
    /// `ProcessInfo.thermalState >= .serious`. A warm phone loses tracking
    /// accuracy long before it throws `deviceTooHot`, so it is worth saying.
    private(set) var isThermallyStressed = false
    private(set) var isTorchOn = false
    let hasTorch = ScanTorch.isAvailable

    /// Kept so the view can present `RoomCaptureView` when this is the live
    /// scanner, and so cancellation reaches the real session.
    private(set) var scanner: (any RoomScanning)?

    /// Raised when the capture produces a room. The view pushes S-10.
    var onFinished: (() -> Void)?

    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var buildTimeout: Task<Void, Never>?
    @ObservationIgnored private var thermalObserver: NSObjectProtocol?
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var wasBackgrounded = false

    deinit {
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
        }
    }

    // MARK: Lifecycle

    /// Begins a capture, replacing any previous one.
    func start(env: TremorEnvironment, appState: AppState) {
        teardown(cancelScanner: true)

        guard let draft = appState.draft else {
            // Reaching S-09 with no draft means the flow was entered sideways.
            // Fail loudly rather than scanning into nothing.
            phase = .failed(.nothingCaptured)
            return
        }

        appState.updateDraft {
            $0.result = nil
            $0.error = nil
            $0.preview = nil
            $0.progress = ScanProgress()
            $0.coaching = nil
            $0.liveCrops = [:]
            $0.acceptedDegradedQuality = false
        }

        let scanner = env.makeScanner(demo: Self.fixture(for: draft.kind))
        self.scanner = scanner
        startedAt = Date()
        elapsed = 0
        wasBackgrounded = false
        phase = .preparing
        observeThermalState()

        let stream = scanner.start()
        streamTask = Task { @MainActor [weak self] in
            for await event in stream {
                self?.handle(event, appState: appState)
            }
        }
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self, !Task.isCancelled else { return }
                self.elapsed = Date().timeIntervalSince(self.startedAt)
            }
        }
    }

    /// "Done scanning". RoomPlan then runs `RoomBuilder`, which takes a beat, so
    /// the screen goes to `.finishing` rather than pretending it is instant.
    func finish() {
        guard phase.isLive else { return }
        phase = .finishing
        scanner?.stop()
        buildTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard let self, !Task.isCancelled, self.phase == .finishing else { return }
            self.phase = .failed(.buildFailed("Putting the room together took too long."))
        }
    }

    /// The user backed out. The scan is abandoned and nothing is written.
    func cancel() {
        teardown(cancelScanner: true)
        phase = .idle
    }

    /// Called when the app leaves the foreground during a capture. ARKit stops
    /// tracking the moment we lose the screen, so pretending otherwise would
    /// silently produce a bad room.
    func noteBackgrounded() {
        guard phase == .preparing || phase == .scanning else { return }
        wasBackgrounded = true
    }

    /// Called on the way back to the foreground.
    func noteForegrounded() {
        guard wasBackgrounded, phase == .preparing || phase == .scanning else { return }
        wasBackgrounded = false
        phase = .interrupted
    }

    /// "Keep scanning" from the interruption card.
    func resume() {
        guard phase == .interrupted else { return }
        phase = .scanning
    }

    func setTorch(_ on: Bool) {
        guard hasTorch else { return }
        isTorchOn = ScanTorch.set(on) ? on : isTorchOn
    }

    // MARK: Events

    private func handle(_ event: ScanEvent, appState: AppState) {
        appState.apply(event)

        switch event {
        case .started:
            if phase == .idle { phase = .preparing }
        case .geometry, .progress:
            if phase == .preparing { phase = .scanning }
        case .coaching, .capturedFrame:
            break
        case .finished:
            buildTimeout?.cancel()
            phase = .finished
            teardown(cancelScanner: false)
            TremorHaptic.success.play()
            onFinished?()
        case .failed(let error):
            buildTimeout?.cancel()
            teardown(cancelScanner: false)
            // We ask for cancellation ourselves when the user backs out; that
            // is not a failure to report back to them.
            if error == .cancelled {
                phase = .idle
            } else {
                phase = .failed(error)
                TremorHaptic.error.play()
            }
        }
    }

    private func teardown(cancelScanner: Bool) {
        streamTask?.cancel()
        streamTask = nil
        tickTask?.cancel()
        tickTask = nil
        buildTimeout?.cancel()
        buildTimeout = nil
        if isTorchOn {
            ScanTorch.set(false)
            isTorchOn = false
        }
        if cancelScanner {
            scanner?.cancel()
            scanner = nil
        }
    }

    private func observeThermalState() {
        isThermallyStressed = ProcessInfo.processInfo.thermalState.rawValue
            >= ProcessInfo.ThermalState.serious.rawValue
        guard thermalObserver == nil else { return }
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let state = ProcessInfo.processInfo.thermalState
            Task { @MainActor in
                self?.isThermallyStressed =
                    state.rawValue >= ProcessInfo.ThermalState.serious.rawValue
            }
        }
    }

    // MARK: Fixtures

    /// Which bundled room the replay scanner walks through, matched to what the
    /// user said they were scanning so the demo path is not always a bedroom.
    static func fixture(for kind: RoomKind) -> ScannedRoom {
        switch kind {
        case .bedroom: return RoomFixtures.dangerousBedroom
        case .livingRoom, .diningRoom, .office, .hallway, .other:
            return RoomFixtures.safeLivingRoom
        case .kitchen, .bathroom: return RoomFixtures.kitchen
        case .nursery: return RoomFixtures.nursery
        case .garage, .basement: return RoomFixtures.garage
        }
    }
}

// MARK: - Torch

/// The torch, for the one instruction that a phone can act on itself.
///
/// RoomPlan says `.turnOnLight` when the room is too dark to track; offering
/// the torch at exactly that moment is the difference between an instruction
/// and a dead end. Nothing else turns it on.
enum ScanTorch {

    static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return device?.hasTorch ?? false
        #endif
    }

    /// Returns whether the change took effect, so the UI never shows a torch as
    /// on when the hardware refused.
    @discardableResult
    static func set(_ on: Bool) -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        guard let device, device.hasTorch else { return false }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.torchMode = on ? .on : .off
            return true
        } catch {
            return false
        }
        #endif
    }

    private static var device: AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }
}

// MARK: - The camera layer

#if canImport(RoomPlan) && canImport(UIKit) && !targetEnvironment(simulator)

/// Apple's capture view, full bleed. SPEC §1.4 S-09 layer 0.
struct RoomCaptureViewport: UIViewRepresentable {
    let scanner: RoomPlanScanner

    func makeUIView(context: Context) -> RoomCaptureView { scanner.captureView }
    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}

#endif

// MARK: - S-09

struct ScanView: View {

    @Environment(\.tremor) private var tremor
    @Environment(Router.self) private var router
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model = ScanSessionModel()
    @State private var isPreviewExpanded = false
    @State private var isConfirmingExit = false

    private var draft: ScanDraft? { appState.draft }
    private var progress: ScanProgress { draft?.progress ?? ScanProgress() }
    private var coaching: ScanCoaching {
        draft?.coaching ?? ScanCoach.preparing
    }

    /// Something that stops a capture happening at all, checked before the
    /// session is ever started so we never open a camera we cannot use.
    private var blocker: ScanBlocker? {
        if draft == nil { return .noDraft }
        if tremor.capabilities.supportsRoomScanning, !tremor.permissions.camera.allowsCapture {
            return .camera(tremor.permissions.camera)
        }
        return nil
    }

    var body: some View {
        ZStack {
            backdrop
                .ignoresSafeArea()

            if let blocker {
                ScanBlockerTakeover(blocker: blocker,
                                    onOpenSettings: { tremor.permissions.openSystemSettings() },
                                    onUseDemoRoom: { router.useDemoRoom() },
                                    onBack: { exitScan() })
            } else if case .failed(let error) = model.phase {
                ScanErrorTakeover(
                    error: error,
                    onRetry: { model.start(env: tremor, appState: appState) },
                    onUseDemoRoom: { router.useDemoRoom() },
                    onBack: { exitScan() })
            } else if model.phase == .finishing {
                ScanFinishingOverlay()
            } else {
                hud
            }

            if model.phase == .interrupted {
                ScanInterruptionOverlay(
                    canFinish: progress.isReadyToFinish,
                    onResume: { model.resume() },
                    onFinish: { model.finish() },
                    onRestart: { model.start(env: tremor, appState: appState) },
                    onDiscard: { exitScan() })
            }
        }
        .background(TremorColor.ink)
        .statusBarHidden(false)
        .animation(TremorMotion.resolved(TremorMotion.reveal, reduceMotion: reduceMotion),
                   value: model.phase)
        .onAppear {
            model.onFinished = { router.reviewScan() }
            // Fires on first entry and again when S-10 pops back for a rescan,
            // which is exactly when a fresh capture is wanted.
            let needsFreshCapture = model.phase == .idle
                || (model.phase.isTerminal && draft?.result == nil)
            if blocker == nil, needsFreshCapture {
                model.start(env: tremor, appState: appState)
            }
        }
        .onDisappear {
            // Leaving with a finished result means we are on our way to S-10;
            // leaving any other way abandons the capture and its ARSession.
            if !model.phase.isTerminal { model.cancel() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.noteForegrounded()
            case .background, .inactive: model.noteBackgrounded()
            @unknown default: break
            }
        }
        .confirmationDialog(
            "Stop scanning this room?",
            isPresented: $isConfirmingExit,
            titleVisibility: .visible
        ) {
            Button("Discard this scan", role: .destructive) { exitScan() }
            Button("Keep scanning", role: .cancel) {}
        } message: {
            Text("Nothing has been saved yet, so you would start this room again from the beginning.")
        }
    }

    // MARK: Layer 0

    @ViewBuilder
    private var backdrop: some View {
        #if canImport(RoomPlan) && canImport(UIKit) && !targetEnvironment(simulator)
        if let live = model.scanner as? RoomPlanScanner {
            RoomCaptureViewport(scanner: live)
        } else {
            replayBackdrop
        }
        #else
        replayBackdrop
        #endif
    }

    /// What the Simulator, a non-Pro iPhone and every preview see: the room
    /// assembling itself on the stage as the replay delivers it.
    private var replayBackdrop: some View {
        ZStack {
            TremorColor.ink
            RadialGradient(
                colors: [TremorColor.primary.opacity(0.20), .clear],
                center: .center, startRadius: 0, endRadius: 420)
            IsometricRoomFigure(
                room: draft?.preview,
                padding: TremorSpacing.lg,
                showsFloor: (draft?.preview?.surfaces.isEmpty == false))
            .padding(.top, TremorSpacing.hero)
            .padding(.bottom, TremorSpacing.xxxl)
        }
    }

    // MARK: The HUD

    private var hud: some View {
        VStack(spacing: 0) {
            topBar

            if model.phase == .preparing {
                Spacer(minLength: 0)
                preparingNotice
                Spacer(minLength: 0)
            } else {
                ScanCoachingPill(coaching: coaching)
                    .padding(.horizontal, TremorSpacing.md)
                    .padding(.top, TremorSpacing.sm)
                    .id(coaching.headline)
                    .transition(.opacity)
                    .animation(
                        TremorMotion.resolved(TremorMotion.reveal, reduceMotion: reduceMotion),
                        value: coaching.headline)

                Spacer(minLength: 0)

                notices

                bottomDock
            }
        }
        .padding(.bottom, TremorSpacing.ctaBottomInset)
        .sheet(isPresented: $isPreviewExpanded) {
            ScanCapturedSoFarSheet(room: draft?.preview, progress: progress)
        }
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: TremorSpacing.sm) {
            TremorIconButton(
                systemImage: "xmark",
                style: .surface,
                size: .large,
                label: "Stop scanning",
                hint: "Discards this scan and goes back",
                action: {
                    if progress.overall > 0.02 {
                        isConfirmingExit = true
                    } else {
                        exitScan()
                    }
                })

            Spacer(minLength: 0)

            if model.phase != .preparing {
                ScanOverlayChip(
                    systemImage: "timer",
                    text: ScanFlowCopy.elapsed(model.elapsed),
                    accessibilityLabelText: "Scanning for \(ScanFlowCopy.elapsed(model.elapsed))")
                    .padding(.top, TremorSpacing.xxs)
            }

            if showsCapturedPreviewCard {
                capturedPreviewCard
            }
        }
        .padding(.horizontal, TremorSpacing.md)
        .padding(.top, TremorSpacing.xs)
    }

    /// On a real capture the camera fills the screen, so the only way to see
    /// what has actually been recorded is this miniature. On the replay path the
    /// whole backdrop already is the miniature, so showing a second one would be
    /// noise.
    private var showsCapturedPreviewCard: Bool {
        guard model.phase != .preparing else { return false }
        #if canImport(RoomPlan) && canImport(UIKit) && !targetEnvironment(simulator)
        return model.scanner is RoomPlanScanner
        #else
        return false
        #endif
    }

    private var capturedPreviewCard: some View {
        Button {
            isPreviewExpanded = true
        } label: {
            IsometricRoomPlate(cornerRadius: TremorRadius.thumbnail) {
                IsometricRoomFigure(room: draft?.preview, padding: TremorSpacing.xs)
                    .frame(width: Metric.previewCard, height: Metric.previewCard)
            }
            .tremorShadow(.raised)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What you have captured so far")
        .accessibilityValue(IsometricRoomFigure.describe(draft?.preview))
        .accessibilityHint("Opens a bigger view of the room so far")
    }

    private var preparingNotice: some View {
        VStack(spacing: TremorSpacing.sm) {
            Image(systemName: "viewfinder")
                .font(.system(size: TremorType.displayM.spec.size, weight: .light))
                .foregroundStyle(TremorColor.inkInverse.opacity(0.9))
            Text("Point at a wall to begin")
                .tremorType(.title3)
                .foregroundStyle(TremorColor.inkInverse)
            Text("Then walk slowly around the edge of the room.")
                .tremorType(.callout)
                .foregroundStyle(TremorColor.inkInverse.opacity(0.78))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, TremorSpacing.pageInset)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var notices: some View {
        VStack(spacing: TremorSpacing.xs) {
            if model.isThermallyStressed {
                TremorBanner("Your iPhone is warm",
                            message: ScanCoach.thermalWarning,
                            kind: .warning)
            }
            if let overlong = ScanCoach.elapsedWarning(for: model.elapsed) {
                TremorBanner("This is a long scan", message: overlong, kind: .neutral)
            }
        }
        .padding(.horizontal, TremorSpacing.md)
        .padding(.bottom, TremorSpacing.sm)
    }

    private var bottomDock: some View {
        VStack(spacing: TremorSpacing.sm) {
            HStack(alignment: .bottom, spacing: TremorSpacing.sm) {
                Text(ScanCoach.objectSummary(count: progress.objectCount))
                    .tremorType(.subheadline)
                    .foregroundStyle(TremorColor.inkInverse)
                    .accessibilityAddTraits(.updatesFrequently)

                Spacer(minLength: 0)

                if model.hasTorch, coaching.symbolName == "lightbulb.fill" || model.isTorchOn {
                    TremorIconButton(
                        systemImage: model.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                        style: .surface,
                        size: .medium,
                        label: model.isTorchOn ? "Turn the torch off" : "Turn the torch on",
                        isSelected: model.isTorchOn,
                        action: { model.setTorch(!model.isTorchOn) })
                }
            }

            ScanCoverageBar(progress: progress)

            TremorButton("Done scanning",
                        variant: .accent,
                        hint: "Finishes the scan and shows you what was found") {
                model.finish()
            }
            .disabled(!progress.isReadyToFinish)

            if let requirement = ScanFlowCopy.doneRequirement(progress) {
                Text(requirement)
                    .tremorType(.caption)
                    .foregroundStyle(TremorColor.inkInverse.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, TremorSpacing.md)
        .padding(.top, TremorSpacing.md)
        .background {
            LinearGradient(
                colors: [TremorColor.ink.opacity(0), TremorColor.ink.opacity(0.72)],
                startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        }
    }

    // MARK: Actions

    private func exitScan() {
        model.cancel()
        appState.cancelScan()
        router.cancelScan()
    }

    private enum Metric {
        static let previewCard: CGFloat = 84
    }
}

// MARK: - Blockers

/// The reasons a capture cannot start. Each one has a way forward; none of them
/// is a dead end.
enum ScanBlocker: Equatable {
    case camera(CameraAuthorization)
    case noDraft
}

private struct ScanBlockerTakeover: View {

    let blocker: ScanBlocker
    let onOpenSettings: () -> Void
    let onUseDemoRoom: () -> Void
    let onBack: () -> Void

    var body: some View {
        ScanTakeover(
            symbol: symbol,
            title: title,
            message: message,
            primary: primary,
            secondary: ("Back to my rooms", onBack))
    }

    private var symbol: String {
        switch blocker {
        case .camera: return "camera.metering.none"
        case .noDraft: return "questionmark.folder"
        }
    }

    private var title: String {
        switch blocker {
        case .camera(.denied): return "Camera access is off"
        case .camera(.restricted): return "The camera is restricted"
        case .camera: return "proof needs the camera"
        case .noDraft: return "This scan is no longer open"
        }
    }

    private var message: String {
        switch blocker {
        case .camera(.denied):
            return "Scanning needs the camera to measure your room. Turn it on in Settings, or explore a demo room — everything after the scan is identical."
        case .camera(.restricted):
            return "Screen Time or a device profile is blocking the camera on this iPhone. You can still explore a demo room — everything after the scan is identical."
        case .camera:
            return "The camera and LiDAR scanner measure the shape of your room. Frames are processed on your iPhone and nothing is uploaded."
        case .noDraft:
            return "Start a new scan from your rooms and we'll pick up from the questions about your building."
        }
    }

    private var primary: (String, () -> Void) {
        switch blocker {
        case .camera(.denied): return ("Open Settings", onOpenSettings)
        case .camera(.restricted): return ("Try a demo room", onUseDemoRoom)
        case .camera: return ("Try a demo room", onUseDemoRoom)
        case .noDraft: return ("Back to my rooms", onBack)
        }
    }
}

// MARK: - Error takeover

/// SPEC §1.4 S-09: every `CaptureError` becomes a full-screen takeover with a
/// specific message and a way on. `ScanError` already carries both, which is
/// why this view has no `switch` in it.
private struct ScanErrorTakeover: View {

    let error: ScanError
    let onRetry: () -> Void
    let onUseDemoRoom: () -> Void
    let onBack: () -> Void

    var body: some View {
        ScanTakeover(
            symbol: symbol,
            title: error.title,
            message: error.message,
            primary: error.suggestsDemoRoom
                ? ("Try a demo room", onUseDemoRoom)
                : ("Try again", onRetry),
            secondary: error.suggestsDemoRoom
                ? ("Back to my rooms", onBack)
                : ("Use a demo room instead", onUseDemoRoom))
    }

    private var symbol: String {
        switch error {
        case .deviceTooHot: return "thermometer.high"
        case .trackingLost: return "scope"
        case .sceneTooLarge: return "arrow.down.right.and.arrow.up.left"
        case .deviceNotSupported: return "iphone.slash"
        case .nothingCaptured: return "viewfinder"
        default: return "exclamationmark.triangle"
        }
    }
}

/// The shared full-screen takeover: dark ground, one illustration, one message,
/// two ways forward.
private struct ScanTakeover: View {

    let symbol: String
    let title: String
    let message: String
    let primary: (title: String, action: () -> Void)
    let secondary: (title: String, action: () -> Void)?

    var body: some View {
        ZStack {
            TremorColor.ink.opacity(0.94).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                Image(systemName: symbol)
                    .font(.system(size: TremorType.displayM.spec.size, weight: .light))
                    .foregroundStyle(TremorColor.primarySoft)
                    .frame(width: TremorSpacing.hero + TremorSpacing.xxl,
                           height: TremorSpacing.hero + TremorSpacing.xxl)
                    .background(TremorColor.primary.opacity(0.24), in: Circle())
                    .accessibilityHidden(true)

                Text(title)
                    .tremorType(.title2)
                    .foregroundStyle(TremorColor.inkInverse)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, TremorSpacing.xl)
                    .accessibilityAddTraits(.isHeader)

                Text(message)
                    .tremorType(.callout)
                    .foregroundStyle(TremorColor.inkInverse.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, TremorSpacing.xs)

                Spacer(minLength: 0)

                VStack(spacing: TremorSpacing.xs) {
                    TremorButton(primary.title, variant: .accent, action: primary.action)
                    if let secondary {
                        TremorButton(secondary.title, variant: .tertiary, action: secondary.action)
                            .foregroundStyle(TremorColor.primarySoft)
                    }
                }
            }
            .padding(.horizontal, TremorSpacing.pageInset)
            .padding(.vertical, TremorSpacing.section)
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Finishing

/// The gap between "Done scanning" and a finished room. RoomPlan runs
/// `RoomBuilder` here, which is real work on a real room, so it gets an honest
/// screen rather than a frozen HUD.
private struct ScanFinishingOverlay: View {
    var body: some View {
        ZStack {
            TremorColor.ink.opacity(0.88).ignoresSafeArea()
            VStack(spacing: TremorSpacing.md) {
                TremorProgressRing(caption: nil, tint: TremorColor.primarySoft)
                Text("Putting your room together")
                    .tremorType(.title3)
                    .foregroundStyle(TremorColor.inkInverse)
                Text("Squaring the walls and tidying the furniture. A few seconds.")
                    .tremorType(.callout)
                    .foregroundStyle(TremorColor.inkInverse.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, TremorSpacing.pageInset)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Interruption

/// The app came back from the background mid-scan. ARKit stopped tracking while
/// we were away, so continuing silently would quietly produce a worse room.
private struct ScanInterruptionOverlay: View {

    let canFinish: Bool
    let onResume: () -> Void
    let onFinish: () -> Void
    let onRestart: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        ZStack {
            TremorColor.scrim.ignoresSafeArea()

            VStack(alignment: .leading, spacing: TremorSpacing.md) {
                Text("Scanning paused")
                    .tremorType(.title3)
                    .foregroundStyle(TremorColor.ink)
                    .accessibilityAddTraits(.isHeader)

                Text(canFinish
                     ? "The camera stopped while you were in another app. You can carry on from where you're standing, or finish with what you already have."
                     : "The camera stopped while you were in another app. Point at a wall again to carry on, or start this room over.")
                    .tremorType(.callout)
                    .foregroundStyle(TremorColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: TremorSpacing.xs) {
                    TremorButton("Keep scanning", size: .medium, action: onResume)
                    if canFinish {
                        TremorButton("Finish with what I have",
                                    variant: .secondary, size: .medium, action: onFinish)
                    }
                    TremorButton("Start this room over",
                                variant: .tertiary, size: .medium, action: onRestart)
                    TremorButton("Discard", variant: .tertiary, size: .medium, action: onDiscard)
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

// MARK: - Captured so far

/// The bigger look at what has been recorded, raised from the miniature. It is
/// deliberately a sheet rather than a mode: the capture keeps running behind it.
private struct ScanCapturedSoFarSheet: View {

    let room: ScannedRoom?
    let progress: ScanProgress

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            TremorNavBar(
                title: "Captured so far",
                trailing: TremorNavBarItem(systemImage: "xmark", label: "Close") { dismiss() })

            ScrollView {
                VStack(alignment: .leading, spacing: TremorSpacing.md) {
                    IsometricRoomPlate {
                        IsometricRoomFigure(room: room)
                            .frame(height: Metric.figure)
                    }

                    if let room, !room.surfaces.isEmpty || !room.objects.isEmpty {
                        Text(ScanFlowCopy.inventory(room))
                            .tremorType(.bodyEmphasis)
                            .foregroundStyle(TremorColor.ink)
                        Text("Keep going until every wall is filled in. Anything you point at afterwards is added.")
                            .tremorType(.callout)
                            .foregroundStyle(TremorColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        TremorEmptyState(
                            title: "Nothing captured yet",
                            message: "Point the camera at a wall and walk slowly along it. The room appears here as it's measured.",
                            systemImage: "viewfinder")
                    }

                    ScanCoverageBar(progress: progress)
                        .padding(TremorSpacing.md)
                        .background(TremorColor.ink,
                                    in: RoundedRectangle(cornerRadius: TremorRadius.card,
                                                         style: .continuous))
                }
                .padding(.vertical, TremorSpacing.md)
            }
        }
        .tremorScreen(inset: TremorSpacing.md)
    }

    private enum Metric {
        static let figure: CGFloat = 240
    }
}

// MARK: - Previews

#Preview("S-09 scanning") {
    ScanFlowPreviewHost(stage: .capture)
}

#Preview("S-09 no camera") {
    ScanFlowPreviewHost(
        stage: .capture,
        env: .makePreview(capabilities: .scanCapable, camera: .denied))
}

#Preview("S-09 takeover — tracking lost") {
    ScanTakeoverPreview(error: .trackingLost)
}

#Preview("S-09 takeover — too large") {
    ScanTakeoverPreview(error: .sceneTooLarge)
}

#Preview("S-09 interrupted") {
    ZStack {
        TremorColor.ink.ignoresSafeArea()
        ScanInterruptionOverlay(canFinish: true, onResume: {}, onFinish: {},
                                onRestart: {}, onDiscard: {})
    }
}

#Preview("S-09 finishing") {
    ZStack {
        TremorColor.ink.ignoresSafeArea()
        ScanFinishingOverlay()
    }
}

private struct ScanTakeoverPreview: View {
    let error: ScanError
    var body: some View {
        ZStack {
            TremorColor.ink.ignoresSafeArea()
            ScanErrorTakeover(error: error, onRetry: {}, onUseDemoRoom: {}, onBack: {})
        }
    }
}
