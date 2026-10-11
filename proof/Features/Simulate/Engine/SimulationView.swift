import SwiftUI
import RealityKit
import simd

/// Where the camera is looking from. Orbit is expressed in spherical
/// coordinates about a target so a caller can animate it, snapshot it, or drive
/// it from an automatic director without knowing anything about RealityKit.
public struct StageCameraState: Equatable, Sendable {
    /// Azimuth about world Y, radians.
    public var yaw: Float
    /// Elevation above the horizon, radians. Clamped to ±80°.
    public var pitch: Float
    /// Distance from the target, metres.
    public var distance: Float
    /// The point the camera looks at.
    public var target: SIMD3<Float>
    /// Set once the user has dragged; lets a director hand control over.
    public var isUserControlled: Bool

    public init(
        yaw: Float = 0.85,
        pitch: Float = 0.42,
        distance: Float = 8,
        target: SIMD3<Float> = SIMD3(0, 1.1, 0),
        isUserControlled: Bool = false
    ) {
        self.yaw = yaw
        self.pitch = Self.clampPitch(pitch)
        self.distance = max(distance, 0.4)
        self.target = target
        self.isUserControlled = isUserControlled
    }

    static func clampPitch(_ value: Float) -> Float {
        min(max(value, -1.396), 1.396) // ±80°
    }

    /// The camera position implied by the current orbit.
    public var position: SIMD3<Float> {
        SIMD3(
            target.x + distance * cos(pitch) * sin(yaw),
            target.y + distance * sin(pitch),
            target.z + distance * cos(pitch) * cos(yaw))
    }

    /// Frames a whole room: centred on it, far enough back that its longest
    /// diagonal fits the vertical field of view with a margin.
    /// - Parameter visibleFraction: how much of the view's height is actually
    ///   visible, rather than covered by the sheet. The stage is a
    ///   Lyft-style map-under-sheet, so on the idle screen the bottom ~42 % of
    ///   the render surface is behind an opaque sheet. Framing the room to the
    ///   *whole* surface therefore centres it under the sheet and wastes the top
    ///   third — which is exactly what it did until this parameter existed.
    public static func framing(
        bounds: BoundingBox,
        fieldOfViewDegrees: Float = 50,
        margin: Float = 1.25,
        visibleFraction: Float = 1.0
    ) -> StageCameraState {
        let extents = bounds.max - bounds.min
        let centre = (bounds.max + bounds.min) / 2
        let radius = max(simd_length(extents) / 2, 0.5)
        let halfFov = fieldOfViewDegrees * .pi / 360
        let visible = min(max(visibleFraction, 0.25), 1.0)

        // Pull back so the room's diagonal fits the visible band rather than the
        // full height.
        let distance = max(radius / max(tan(halfFov), 0.05) * margin / visible, 1.2)

        // Then slide the look-at point down the world by the same offset that
        // moves the room up the screen into the middle of that band. The world
        // height spanned by the full viewport at this distance is
        // 2·d·tan(halfFov); the band's centre sits `0.5 − visible/2` of the
        // viewport above the middle.
        let viewportHeight = 2 * distance * tan(halfFov)
        let lift = (0.5 - visible / 2) * viewportHeight

        return StageCameraState(
            yaw: 0.85,
            pitch: 0.42,
            distance: distance,
            target: SIMD3(centre.x,
                          max(centre.y, extents.y * 0.35) - lift,
                          centre.z),
            isUserControlled: false)
    }
}

/// A bare, unstyled `RealityView` wrapper around the simulation stage.
///
/// Deliberately has no chrome: no transport bar, no captions, no design-system
/// types. It renders the scene, gives the user orbit / pan / zoom, frames the
/// room automatically, and reports taps. Everything else belongs to whoever
/// owns the surrounding UI.
public struct SimulationView: View {

    /// The fraction of this view's height that is not covered by the sheet in
    /// front of it. The stage owner sets this from its current detent so the
    /// room is framed into the space the user can actually see.
    public var visibleFraction: Float = 1.0

    private let controller: SimulationController
    @Binding private var selection: UUID?
    @Binding private var camera: StageCameraState

    /// Fires when the scene is live, so a caller can start playback.
    private let onReady: (() -> Void)?

    @State private var cameraEntity = PerspectiveCamera()
    @State private var didFrame = false
    @State private var orbitStart: StageCameraState?
    @State private var panStart: StageCameraState?
    @State private var zoomStart: Float?
    @State private var isMultiTouch = false

    public init(
        controller: SimulationController,
        selection: Binding<UUID?>,
        camera: Binding<StageCameraState>,
        onReady: (() -> Void)? = nil
    ) {
        self.controller = controller
        self._selection = selection
        self._camera = camera
        self.onReady = onReady
    }

    public var body: some View {
        RealityView { content in
            cameraEntity.camera.fieldOfViewInDegrees = 50
            cameraEntity.camera.near = 0.05
            cameraEntity.camera.far = 400
            content.add(cameraEntity)

            if let stage = controller.stage {
                content.add(stage.anchor)
                if !didFrame {
                    camera = StageCameraState.framing(bounds: stage.roomBounds, visibleFraction: visibleFraction)
                    didFrame = true
                }
                applyCamera()
                // Environment lighting if the bundle ships one; the directional
                // rig alone is already a complete look, so this never blocks.
                await SceneBuilder.applyImageBasedLight(to: stage)
                if let scene = stage.anchor.scene {
                    controller.attach(to: scene)
                    onReady?()
                }
            }
        } update: { content in
            // Swap the stage if the controller reloaded a different room.
            if let stage = controller.stage, stage.anchor.scene == nil {
                content.entities
                    .compactMap { $0 as? AnchorEntity }
                    .filter { $0 !== stage.anchor }
                    .forEach { content.remove($0) }
                content.add(stage.anchor)
                camera = StageCameraState.framing(bounds: stage.roomBounds, visibleFraction: visibleFraction)
                if let scene = stage.anchor.scene {
                    controller.attach(to: scene)
                }
            }
            applyCamera()
        }
        .gesture(dragGesture)
        .simultaneousGesture(magnifyGesture)
        .gesture(tapGesture)
        .onDisappear { controller.detach() }
    }

    // MARK: - Camera

    private func applyCamera() {
        cameraEntity.look(at: camera.target, from: camera.position, relativeTo: nil)
    }

    /// One finger orbits; two fingers (i.e. while a pinch is live) pans.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if isMultiTouch {
                    let start = panStart ?? camera
                    if panStart == nil { panStart = start }
                    // Pan in the camera's own screen plane, scaled by distance
                    // so the drag feels the same at any zoom.
                    let scale = start.distance * 0.0022
                    let right = SIMD3<Float>(cos(start.yaw), 0, -sin(start.yaw))
                    let upish = SIMD3<Float>(
                        -sin(start.yaw) * sin(start.pitch),
                        cos(start.pitch),
                        -cos(start.yaw) * sin(start.pitch))
                    var next = start
                    next.target = start.target
                        - right * Float(value.translation.width) * scale
                        + upish * Float(value.translation.height) * scale
                    next.isUserControlled = true
                    camera = next
                } else {
                    let start = orbitStart ?? camera
                    if orbitStart == nil { orbitStart = start }
                    var next = start
                    next.yaw = start.yaw - Float(value.translation.width) / 220
                    next.pitch = StageCameraState.clampPitch(
                        start.pitch + Float(value.translation.height) / 260)
                    next.isUserControlled = true
                    camera = next
                }
            }
            .onEnded { _ in
                orbitStart = nil
                panStart = nil
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0)
            .onChanged { value in
                isMultiTouch = true
                let start = zoomStart ?? camera.distance
                if zoomStart == nil { zoomStart = start }
                var next = camera
                next.distance = min(max(start / Float(value.magnification), 0.4), 200)
                next.isUserControlled = true
                camera = next
            }
            .onEnded { _ in
                zoomStart = nil
                isMultiTouch = false
                panStart = nil
            }
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                let hit = controller.objectID(for: value.entity)
                selection = (hit == selection) ? nil : hit
                controller.selectedObjectID = selection
            }
    }
}
