//
//  AddRoomView.swift
//  proof — Add Room, the tab root
//
//  The whole consumer path lives at one tab root and switches on
//  `AddRoomFlowModel.Step`. It does not push.
//
//  That is a deliberate departure from the scan flow (S-07…S-12), which pushes and then
//  performs path surgery so nobody can swipe back into a torn-down camera. Here there is
//  nothing to swipe back to: every step replaces the last, the 3D room has to survive from
//  the moment it is built until the user leaves, and a `NavigationStack` that kept the
//  camera and the reconstruction alive underneath the room would hold a camera session and
//  a few hundred megabytes of textures for no reason. One root, one live step.
//
//  The tab bar stands down for the steps that own the display. It is told to, through
//  `Router.setTabRootImmersive(_:for:)` — the same mechanism `Route.isImmersive` uses for
//  pushed screens, so the tab bar is genuinely absent and every scroll view inside gets the
//  right bottom inset, rather than something being drawn on top of it.
//
//  Two of the four screens below belong to other files by design:
//  `GuidedCaptureView` (the guided panorama and the "Load Demo Room" injection) and
//  `RoomAnalysisView` (the structured report). This file only sequences them.
//

import SwiftUI

struct AddRoomView: View {

    @Environment(AppState.self) private var appState
    @State private var confirmsLeaving = false

    private var flow: AddRoomFlowModel { appState.addRoomFlow }

    @Environment(Router.self) private var router
    @Environment(\.tremor) private var tremor

    var body: some View {
        ZStack {
            switch flow.step {
            case .naming:
                // The shell keeps all three tab roots mounted, so this screen exists from
                // launch whether or not anyone is looking at it. It is told which, because
                // its text field must not take first responder — and raise the keyboard
                // over the Rooms dashboard — until this tab is the selected one.
                AddRoomNameView(
                    name: Bindable(flow).roomName,
                    isActive: router.tab == .addRoom
                ) {
                    flow.chooseConcern()
                }
                .transition(.opacity)

            case .concern:
                AddRoomConcernView(
                    roomName: flow.displayName,
                    stage: Bindable(flow).stage,
                    onBack: { flow.backToNaming() },
                    onContinue: { flow.beginCapture() })
                .transition(.opacity)

            case .capturing:
                GuidedCaptureView(
                    roomName: flow.displayName,
                    onFinish: { injectedDemoVideo in
                        flow.finishCapture(injected: injectedDemoVideo)
                    },
                    onCancel: { flow.startOver() })
                .transition(.opacity)

            case .processing:
                AddRoomProcessingView(
                    roomName: flow.displayName,
                    isSceneReady: flow.demo.isSceneReady,
                    onDone: { flow.finishProcessing() })
                .transition(.opacity)

            // The checklist is layered over the room rather than replacing it, so the 3D
            // view is never dismantled and rebuilt on the way back.
            case .exploring, .analysis:
                ConstellationExplorerView(
                    model: flow.demo,
                    sky: flow.sky,
                    roomTitle: flow.displayName,
                    onExit: { confirmsLeaving = true },
                    onOpenChecklist: { flow.showAnalysis() })
                .accessibilityHidden(flow.step == .analysis)
                .transition(.opacity)
            }

            if flow.step == .analysis {
                ChecklistView(
                    roomName: flow.displayName,
                    sky: flow.sky,
                    onBackToRoom: { flow.backToRoom() },
                    onShowInRoom: { flow.backToRoom() })
                .transition(.move(edge: .bottom))
            }
        }
        .animation(TremorMotion.sheet, value: flow.step)
        .toolbar(.hidden, for: .navigationBar)
        // `initial: true` so a step reached by a launch argument, or a tab the user comes
        // back to mid-flow, gets the right chrome without waiting for a change.
        .onChange(of: flow.step, initial: true) { _, step in
            router.setTabRootImmersive(step.isImmersive, for: .addRoom)
        }
        .confirmationDialog(
            "Leave this room?",
            isPresented: $confirmsLeaving,
            titleVisibility: .visible
        ) {
            Button("Start a new scan", role: .destructive) { flow.startOver() }
            Button("Stay here", role: .cancel) {}
        } message: {
            Text("Your flags, links and fix plans for this kitchen are kept. Starting over films the room again.")
        }
        .task { await flow.applyLaunchOverride() }
    }
}

#Preview("Add room") {
    RootPreviewHost(env: .makePreview(), tab: .addRoom)
}
