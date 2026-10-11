//
//  StageView.swift
//  Tremor — S-12 · S-13 · S-14 · S-15, which are one screen
//
//  SPEC §1.1 principle 5: the room viewer, the earthquake configurator, the
//  running simulation and the report share a **persistent 3D stage** and differ
//  only in what the sheet over it contains and how tall it is. So there is one
//  view, one `RealityView`, one camera and one `SimulationController` here, and
//  the four "screens" are `AppState.stagePhase`.
//
//  Layering, bottom to top:
//
//      z0   the stage: ink field, vignette, `SimulationView` (or the 2D plan
//           fallback when meshes could not be built)
//      z1   floating controls — back, overflow, recentre — which translate with
//           the sheet (Lyft §6.5)
//      z2   the S-14 overlay: countdown, caption, ticker, meter, transport bar
//      z3   the scrim, then the sheet itself
//

import SwiftUI

struct StageView: View {

    let roomID: UUID

    @Environment(\.tremor) private var tremor
    @Environment(Router.self) private var router
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model = StageModel()
    @State private var detent: StageDetent = .peek
    @State private var liveSheetHeight: CGFloat?
    /// The stage's own height in points, measured once the layout exists. The
    /// camera's framing is a function of how much of it the sheet covers, so
    /// this is real state rather than a guess.
    @State private var measuredHeight: CGFloat = 0
    @State private var isConfirmingDelete = false
    @State private var isRenaming = false
    @State private var draftName = ""

    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height
            let resting = height(for: detent, in: screenHeight)

            ZStack(alignment: .bottom) {
                stageLayer
                    .ignoresSafeArea()

                topControls
                recentreControl(liftedBy: liveSheetHeight ?? resting)

                if appState.stagePhase == .running {
                    StageRunningOverlay(
                        model: model,
                        onSkipToEnd: skipToResults,
                        onLeave: leaveRun)
                        .transition(.opacity)
                }

                scrim

                if detent != .hidden {
                    sheet(screenHeight: screenHeight, resting: resting)
                        .transition(.move(edge: .bottom))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TremorColor.ink.ignoresSafeArea())
            .onAppear { measuredHeight = screenHeight }
            .onChange(of: screenHeight) { _, height in measuredHeight = height }
            .onChange(of: detent) { _, new in
                liveSheetHeight = nil
                model.reframe(
                    forSheetFraction: new.fraction(in: screenHeight),
                    animated: !reduceMotion)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .animation(
            TremorMotion.resolved(TremorMotion.change, reduceMotion: reduceMotion),
            value: appState.stagePhase)
        .task(id: roomID) { await open() }
        .onChange(of: appState.stagePhase) { _, phase in
            detent = StageDetent.resting(
                for: phase,
                hasSelection: appState.selectedObjectID != nil)
            // The running state has no sheet and no controls of its own beyond
            // the transport bar, so arriving in it with nothing playing would be
            // a screen with no way out. Anything that puts us here starts a run.
            if phase == .running, model.runPhase == .idle { shake() }
        }
        .onChange(of: appState.selectedObjectID) { _, id in
            model.controller.selectedObjectID = id
            guard appState.stagePhase == .viewer else { return }
            detent = id == nil ? .peek : .medium
        }
        .onDisappear {
            // Pushing S-16 or S-17 also fires this, and tearing the stage down
            // for a screen the user is coming straight back from would rebuild
            // every mesh on return. Only release it when the route is gone.
            if router.path.contains(.stage(roomID: roomID)) {
                model.cancelRun()
            } else {
                model.teardown()
                appState.closeRoom()
            }
        }
        .alert("Delete this room?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) { delete() }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("The scan, the report and anything you added to your fix-it plan for this room go with it. This can't be undone.")
        }
        .alert("Rename this room", isPresented: $isRenaming) {
            TextField("Room name", text: $draftName)
            Button("Save") { rename() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Stage

    @ViewBuilder
    private var stageLayer: some View {
        ZStack {
            TremorColor.ink

            if let message = model.sceneState.failureMessage {
                StageFloorPlan(room: appState.room,
                               selection: appState.selectedObjectID,
                               assessment: appState.assessment,
                               onSelect: select)
                    .accessibilityHint(message)
            } else {
                SimulationView(
                    controller: model.controller,
                    selection: stageSelection,
                    camera: cameraBinding,
                    onReady: { reframeForCurrentSheet(animated: false) })
                    .opacity(model.sceneState.isReady ? 1 : 0)
                    .animation(
                        TremorMotion.resolved(TremorMotion.reveal, reduceMotion: reduceMotion),
                        value: model.sceneState)

                if model.sceneState.isBuilding {
                    StageBuildingIndicator()
                }
            }

            // The vignette (SPEC §2.7.12). The stage is the one surface that
            // ignores light mode, so it darkens toward its own ink rather than
            // toward black — which is what stops it reading as a grey hole.
            GeometryReader { proxy in
                RadialGradient(
                    colors: [.clear, TremorColor.scrim],
                    center: .center,
                    startRadius: proxy.size.width * 0.15,
                    endRadius: proxy.size.width * 1.15)
            }
            .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your room in 3D")
    }

    private var stageSelection: Binding<UUID?> {
        Binding(
            get: { appState.selectedObjectID },
            set: { select($0) })
    }

    private var cameraBinding: Binding<StageCameraState> {
        Binding(
            get: { model.camera },
            set: { newValue in
                if newValue.isUserControlled, !model.camera.isUserControlled {
                    model.userTookCamera()
                }
                model.camera = newValue
            })
    }

    // MARK: - Floating controls

    /// Back and overflow. Anchored to the top of the stage, never lifted — at
    /// the `large` detent the sheet leaves 44 pt of stage and the way out has to
    /// still be in it.
    @ViewBuilder
    private var topControls: some View {
        if appState.stagePhase != .running {
            VStack {
                HStack(alignment: .top) {
                    TremorIconButton(systemImage: "chevron.left",
                                    style: .material,
                                    size: .large,
                                    label: "Back",
                                    hint: "Returns to your rooms",
                                    action: { router.pop() })
                    Spacer(minLength: 0)
                    overflowMenu
                }
                .padding(.horizontal, TremorSpacing.md)
                .padding(.top, TremorSpacing.xs)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.opacity)
        }
    }

    /// Recentre. This one *does* translate with the sheet (Lyft §6.5) — and
    /// stands down entirely at `large`, where there is no room for it and
    /// nothing of the stage left to recentre.
    @ViewBuilder
    private func recentreControl(liftedBy sheetHeight: CGFloat) -> some View {
        if appState.stagePhase != .running, detent != .large, !model.sceneState.isBuilding {
            VStack {
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    TremorIconButton(systemImage: "scope",
                                    style: .material,
                                    size: .large,
                                    label: "Recentre the view",
                                    hint: "Frames the whole room again",
                                    action: { model.recentre(animated: !reduceMotion) })
                }
                .padding(.horizontal, TremorSpacing.md)
                .padding(.bottom, TremorSpacing.sm)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, sheetHeight)
            .transition(.opacity)
        }
    }

    private var overflowMenu: some View {
        Menu {
            Button {
                draftName = appState.room?.name ?? ""
                isRenaming = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                appState.beginScan(kind: appState.room?.kind ?? .bedroom,
                                   isDemo: !tremor.capabilities.supportsRoomScanning)
                router.startScan(deviceCanScan: tremor.capabilities.supportsRoomScanning)
            } label: {
                Label("Scan this room again", systemImage: "viewfinder")
            }
            Button {
                router.share(roomID: roomID)
            } label: {
                Label("Share or export", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Delete room", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: TremorControlMetrics.glyphLarge, weight: .semibold))
                .foregroundStyle(TremorColor.ink)
                .frame(width: TremorSize.buttonMedium, height: TremorSize.buttonMedium)
                .background(Circle().fill(.regularMaterial))
                .tremorShadow(.raised)
        }
        .accessibilityLabel("More")
        .accessibilityHint("Rename, rescan, share or delete this room")
    }

    // MARK: - Scrim

    @ViewBuilder
    private var scrim: some View {
        if detent.showsScrim {
            TremorColor.scrim
                .ignoresSafeArea()
                .transition(.opacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Sheet

    private func sheet(screenHeight: CGFloat, resting: CGFloat) -> some View {
        StageSheetShell(
            restingHeight: resting,
            maximumHeight: StageDetent.large.height(in: screenHeight),
            isDraggable: appState.stagePhase != .running,
            onDrag: { liveSheetHeight = $0 },
            onDragEnd: { landed in
                let settlement = StageDetent.settle(
                    dragHeight: landed,
                    phase: appState.stagePhase,
                    screenHeight: screenHeight,
                    peek: peekHeight)
                liveSheetHeight = nil
                if settlement.phase != appState.stagePhase {
                    appState.stagePhase = settlement.phase
                }
                detent = settlement.detent
            }
        ) {
            sheetContent
        }
    }

    @ViewBuilder
    private var sheetContent: some View {
        switch appState.stagePhase {
        case .viewer:
            StageViewerSheet(
                room: appState.room,
                assessment: appState.assessment,
                loadPhase: appState.loadPhase,
                sceneState: model.sceneState,
                subtitle: model.roomSubtitle,
                selectedObject: appState.selectedObject,
                selectedRisk: appState.selectedRisk,
                isExpanded: detent == .medium || detent == .large,
                isReducedFidelity: model.isReducedFidelity,
                onSimulate: { go(to: .configurator) },
                onSeeReport: showReport,
                onRunAgain: { go(to: .configurator) },
                onOpenDetails: { router.openObject($0) },
                onClearSelection: { select(nil) },
                onRetry: { appState.openRoom(id: roomID) },
                onRescan: {
                    appState.beginScan(kind: appState.room?.kind ?? .bedroom,
                                       isDemo: !tremor.capabilities.supportsRoomScanning)
                    router.startScan(deviceCanScan: tremor.capabilities.supportsRoomScanning)
                },
                onExplainMethod: { router.openMethod() })

        case .configurator:
            StageConfiguratorSheet(
                model: model,
                room: appState.room,
                isAssessing: appState.isAssessing,
                onShake: shake,
                onExplainMethod: { router.openMethod() },
                onBack: { go(to: .viewer) })

        case .running:
            EmptyView()

        case .results:
            StageResultsSheet(
                room: appState.room,
                assessment: appState.assessment,
                isAssessing: appState.isAssessing,
                ensembleSize: tremor.risk.ensembleSize,
                hasUncertainObjects: hasUncertainObjects,
                didPlaybackDiverge: model.didPlaybackDiverge,
                onSelect: { objectID in
                    select(objectID)
                    router.openObject(objectID)
                },
                onShare: { router.share(roomID: roomID) },
                onFixItPlan: { router.openFixItPlan() },
                onRunAgain: { go(to: .configurator) },
                onExplainMethod: { router.openMethod() })
        }
    }

    // MARK: - Geometry

    private var peekHeight: CGFloat {
        StageViewerSheet.peekHeight(
            hasAssessment: appState.assessment != nil,
            dynamicTypeSize: dynamicTypeSize)
    }

    private func height(for detent: StageDetent, in screenHeight: CGFloat) -> CGFloat {
        detent.height(in: screenHeight, peek: peekHeight)
    }

    private var hasUncertainObjects: Bool {
        guard let room = appState.room, !room.objects.isEmpty else { return false }
        let uncertain = room.objects.filter(\.provenance.isUncertain).count
        return Double(uncertain) / Double(room.objects.count) > 0.25
    }

    // MARK: - Actions

    private func open() async {
        appState.openRoom(id: roomID)
        // Wait for the document before touching the stage: the meshes come from
        // it, and building against a half-loaded room is how you get a room with
        // no walls.
        while appState.loadPhase.isLoading {
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
        guard let room = appState.room else { return }
        detent = StageDetent.resting(for: appState.stagePhase, hasSelection: false)

        // The scan flow hands the stage a room that is already assessed and
        // already on `.results` (`AppState.adopt`). Building the untinted idle
        // scene for it and then rebuilding would show the room twice.
        if appState.stagePhase == .results, let assessment = appState.assessment {
            await model.prepareResults(room: room, assessment: assessment)
        } else {
            await model.prepare(
                room: room,
                assessment: appState.assessment,
                defaultIntensity: tremor.settings.defaultIntensity)
        }

        // `SimulationView` frames the room itself on the first frame it renders,
        // and that frame happens after this `task` resumes — so the sheet-aware
        // framing has to be applied after it, not before, or it is overwritten.
        // `onReady` alone is not enough: it only fires if the anchor already has
        // a scene inside `RealityView`'s make closure, which is not guaranteed.
        try? await Task.sleep(nanoseconds: 350_000_000)
        reframeForCurrentSheet(animated: false)

        // At `peek` there is no room for a banner, so the fallback announces
        // itself once rather than leaving a flat plan unexplained.
        if model.sceneState.failureMessage != nil {
            appState.post("Showing the floor plan",
                          message: "The 3D view couldn't be built on this device. Everything in your report still works.",
                          style: .warning)
        }
    }

    private func reframeForCurrentSheet(animated: Bool) {
        guard measuredHeight > 0 else { return }
        model.reframe(
            forSheetFraction: detent.fraction(in: measuredHeight),
            animated: animated)
    }

    private func go(to phase: AppState.StagePhase) {
        appState.stagePhase = phase
    }

    private func select(_ id: UUID?) {
        appState.selectedObjectID = id
        model.controller.selectedObjectID = id
    }

    /// S-13 → S-14. The verdict is computed first, at the chosen intensity,
    /// because the scenario builder deliberately drops an assessment made at a
    /// different one rather than captioning a body with another earthquake's
    /// verdict.
    private func shake() {
        guard let room = appState.room else { return }
        let intensity = model.selectedIntensity
        let seed = model.resolvedSeed
        let needsAssessment = appState.assessment?.intensity != intensity
            || appState.assessment?.seed != seed
        if needsAssessment {
            appState.assess(intensity: intensity, seed: seed)
        }

        Task {
            await appState.waitForAssessment()
            guard let assessment = appState.assessment else { return }
            // `run` first: it marks the model as counting down synchronously, so
            // the phase change below cannot be mistaken for "arrived in the
            // running state with nothing running" and start a second run.
            model.run(
                room: room,
                assessment: assessment,
                reduceMotion: reduceMotion,
                hapticsEnabled: tremor.settings.hapticsEnabled,
                onFinish: { appState.stagePhase = .results })
            appState.stagePhase = .running
        }
    }

    /// "See the report" on a room that has been simulated before. Loads the
    /// risk-tinted stage without replaying it, so nothing is recomputed.
    private func showReport() {
        guard let room = appState.room, let assessment = appState.assessment else { return }
        appState.stagePhase = .results
        Task { await model.prepareResults(room: room, assessment: assessment) }
    }

    private func skipToResults() {
        model.cancelRun()
        appState.stagePhase = .results
    }

    private func leaveRun() {
        model.cancelRun()
        appState.stagePhase = .viewer
    }

    private func rename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var room = appState.room else { return }
        room.name = trimmed
        Task {
            do {
                _ = try await tremor.rooms.save(room)
                appState.reloadOpenRoom()
                appState.post("Renamed", message: "This room is now \(trimmed).", style: .success)
            } catch {
                appState.post("Couldn't rename this room",
                              message: AppState.message(for: error),
                              style: .error)
            }
        }
    }

    private func delete() {
        Task {
            do {
                try await tremor.rooms.delete(id: roomID)
                appState.closeRoom()
                router.popToRoot()
                appState.post("Room deleted", style: .info)
            } catch {
                appState.post("Couldn't delete this room",
                              message: AppState.message(for: error),
                              style: .error)
            }
        }
    }
}

// MARK: - Building indicator

/// What the stage shows while the meshes are being built: a wireframe pulse and
/// one honest line. Never a bare spinner on a dark field.
struct StageBuildingIndicator: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: TremorSpacing.md) {
            Image(systemName: "cube.transparent")
                .font(.system(size: TremorSpacing.section, weight: .light))
                .foregroundStyle(TremorColor.primarySoft.opacity(isPulsing ? 0.85 : 0.35))
            Text("Building your room…")
                .tremorType(.callout)
                .foregroundStyle(TremorColor.inkInverse.opacity(0.78))
        }
        .onAppear {
            guard !reduceMotion else {
                isPulsing = true
                return
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Building your room in 3D")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Previews

#Preview("S-12 stage — dangerous bedroom") {
    StagePreviewHost(room: RoomFixtures.dangerousBedroom, phase: .viewer)
}

#Preview("S-13 stage — configurator") {
    StagePreviewHost(room: RoomFixtures.dangerousBedroom, phase: .configurator)
}

#Preview("S-15 stage — results") {
    StagePreviewHost(room: RoomFixtures.dangerousBedroom, phase: .results, assesses: true)
}

/// Renders `StageView` against a fixture room, inside the real shell, so a
/// preview exercises the routing and the shared state rather than a mock.
@MainActor
struct StagePreviewHost: View {

    let room: ScannedRoom
    let phase: AppState.StagePhase
    var assesses: Bool = false

    @State private var env = TremorEnvironment.makePreview(seedsFixtures: false)
    @State private var router = Router()
    @State private var appState: AppState?

    var body: some View {
        Group {
            if let appState {
                StageView(roomID: room.id)
                    .environment(\.tremor, env)
                    .environment(router)
                    .environment(appState)
            } else {
                Color.clear
            }
        }
        .task {
            _ = try? await env.rooms.save(room)
            let state = AppState(env: env)
            state.openRoom(id: room.id)
            if assesses {
                try? await Task.sleep(nanoseconds: 200_000_000)
                state.assess(intensity: .viii, persists: false)
                await state.waitForAssessment()
            }
            state.stagePhase = phase
            router.replacePath(with: [.stage(roomID: room.id)])
            appState = state
        }
    }
}
