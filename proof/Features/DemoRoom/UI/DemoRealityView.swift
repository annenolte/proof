import Combine
import Metal
import RealityKit
import SwiftUI
import UIKit
import simd

// SwiftUI's `RealityView` has no post-process hook — `renderCallbacks` lives on `ARView`
// and nowhere else. So the demo room is hosted in an `ARView` in non-AR mode instead, and
// this wrapper reproduces the surface the explorer used to get from `RealityView`: the
// scene root, a camera driven by `DemoCameraPose`, the physics tick, and the three
// gestures with their original semantics intact.

struct DemoRealityView: UIViewRepresentable {
    let model: DemoRoomModel
    /// Passed explicitly rather than read inside `updateUIView`, because observation
    /// tracking only registers reads that happen in a `View` body.
    let sceneReady: Bool
    var settings: PostProcessSettings = .photoreal
    /// Runs on each physics step, alongside the model tick.
    var onSimulate: () -> Void = {}

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)

        // Nothing here is anchored to the world, so every AR-side feature is dead weight.
        // Motion blur, depth of field and HDR are left on: HDR in particular is what gives
        // the bright pass values above 1.0 to work with.
        view.renderOptions = [
            .disablePersonOcclusion,
            .disableAREnvironmentLighting,
            .disableFaceMesh,
            .disableCameraGrain
        ]
        // Clear, so the explorer's backdrop gradient still reads behind the cutaway room.
        view.environment.background = .color(.clear)
        // `RealityView` supplies a default studio environment; an `ARView` in non-AR mode
        // does not, and without this the room loses roughly a third of its ambient and the
        // ceiling and extractor hood go muddy. The room's own synthesised IBL is the right
        // thing to hand it — it is what the props are already lit by.
        view.environment.lighting.resource = EnvironmentFactory.makeEnvironment()
        view.environment.lighting.intensityExponent = 1.05
        view.backgroundColor = .clear
        view.isOpaque = false

        context.coordinator.attach(to: view, settings: settings)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.settings = settings
        if sceneReady { context.coordinator.attachScene() }
    }

    static func dismantleUIView(_ view: ARView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, onSimulate: onSimulate)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let model: DemoRoomModel
        private let onSimulate: () -> Void

        private weak var view: ARView?
        private let anchor = AnchorEntity(world: .zero)
        private let cameraEntity = PerspectiveCamera()
        private var pipeline: PostProcessPipeline?

        private var frameSubscription: (any Cancellable)?
        private var simulationSubscription: (any Cancellable)?
        private var sceneAttached = false
        private var postProcessAttached = false

        private var dragAnchor: DemoCameraPose?
        private var lastMagnification: CGFloat = 1

        var settings: PostProcessSettings = .photoreal {
            didSet { pipeline?.settings = settings }
        }

        init(model: DemoRoomModel, onSimulate: @escaping () -> Void) {
            self.model = model
            self.onSimulate = onSimulate
        }

        func attach(to view: ARView, settings: PostProcessSettings) {
            self.view = view
            self.settings = settings

            anchor.addChild(cameraEntity)
            view.scene.addAnchor(anchor)

            frameSubscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.attachScene()
                    self?.applyCamera()
                    self?.attachPostProcess()
                    if let self, let view = self.view {
                        self.model.clip.captureIfDue(from: view)
                        self.model.frameHandler?(view)
                    }
                }
            }

            addGestures(to: view)
            attachScene()
        }

        func detach() {
            frameSubscription = nil
            simulationSubscription = nil
            view?.renderCallbacks.postProcess = nil
        }

        /// The scene is built asynchronously, so this is retried until it exists. The tick
        /// is retried separately: subscribing needs the root to already be in a live scene.
        func attachScene() {
            guard let scene = model.scene else { return }
            if !sceneAttached {
                sceneAttached = true
                anchor.addChild(scene.root)
            }
            attachTick(to: scene)
        }

        /// Installed from the first rendered frame rather than from `makeUIView`: the
        /// setter reaches into the live renderer, which does not exist until the view has
        /// drawn once.
        private func attachPostProcess() {
            guard !postProcessAttached, let view else { return }
            postProcessAttached = true

            // `ARView.renderCallbacks` traps on the Simulator — assigning `postProcess`
            // there is an immediate SIGTRAP, not a soft failure we could catch. The demo
            // has to survive being run on a Simulator, so the grade is device-only and the
            // Simulator gets the ungraded image rather than a crash.
            #if targetEnvironment(simulator)
            return
            #else
            guard let device = MTLCreateSystemDefaultDevice(),
                  let pipeline = PostProcessPipeline(device: device) else { return }
            pipeline.settings = settings
            self.pipeline = pipeline
            view.renderCallbacks.postProcess = { context in
                pipeline.run(context)
            }
            #endif
        }

        // MARK: Per frame

        private func applyCamera() {
            DemoCameraRig.apply(model.pose, to: cameraEntity)
            guard let scene = model.scene else { return }
            let centre = SIMD3<Float>(Plan.width / 2, 0, Plan.length / 2)
            scene.applyCutaway(
                mode: model.pose.mode,
                cameraDirection: model.pose.position - centre
            )
        }

        /// The quake is stepped from the physics tick rather than from a display-rate event.
        /// Excitation forces have to be applied once per physics step; on a 120 Hz panel a
        /// display-rate hook would apply them twice as often and double the shaking.
        private func attachTick(to scene: ApartmentScene) {
            guard simulationSubscription == nil, let rkScene = scene.root.scene else { return }
            simulationSubscription = rkScene.subscribe(
                to: PhysicsSimulationEvents.WillSimulate.self,
                on: scene.simulationRoot
            ) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.model.tick(deltaTime: Double(event.deltaTime))
                    self.onSimulate()
                }
            }
        }

        // MARK: Gestures

        private func addGestures(to view: ARView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            for recogniser in [pan, pinch, tap] as [UIGestureRecognizer] {
                recogniser.delegate = self
                view.addGestureRecognizer(recogniser)
            }
        }

        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc private func handlePan(_ recogniser: UIPanGestureRecognizer) {
            switch recogniser.state {
            case .began, .changed:
                if dragAnchor == nil {
                    dragAnchor = model.pose
                    model.userTookCamera()
                }
                guard var pose = dragAnchor else { return }
                let translation = recogniser.translation(in: recogniser.view)
                pose.applyDrag(translation: SIMD2(
                    Float(translation.x), Float(translation.y)
                ))
                pose.shakeOffset = model.pose.shakeOffset
                model.pose = pose
            default:
                dragAnchor = nil
            }
        }

        @objc private func handlePinch(_ recogniser: UIPinchGestureRecognizer) {
            switch recogniser.state {
            case .began:
                lastMagnification = 1
            case .changed:
                let delta = recogniser.scale / max(lastMagnification, 0.001)
                lastMagnification = recogniser.scale
                model.userTookCamera()
                model.pose.applyMagnification(Float(delta))
            default:
                lastMagnification = 1
            }
        }

        @objc private func handleTap(_ recogniser: UITapGestureRecognizer) {
            guard let view, let scene = model.scene else { return }
            let point = recogniser.location(in: view)
            // A miss is not a deselection: the SwiftUI gesture this replaces was targeted to
            // entities and never fired on empty space.
            guard let hit = view.entity(at: point) else { return }
            guard let prop = scene.prop(containing: hit) else {
                model.selectedPropID = nil
                return
            }
            TremorHaptic.light.play()
            model.selectedPropID = prop.id == model.selectedPropID ? nil : prop.id
        }
    }
}
