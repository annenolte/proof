import Foundation
import RealityKit
import simd

// The three ways to look at the demo room.
//
// The stage screen in the main app has an orbit-only rig whose pitch is clamped short of
// vertical and whose position is always derived from a look-at target. That is the right
// design for inspecting a single piece of furniture, and the wrong one here: this demo
// has to fly around the room, stand inside it at eye height, and drop to a clean plan
// view. So the rig is expressed as a mode plus a pose, and each mode owns its own
// controls.

enum DemoCameraMode: String, CaseIterable, Identifiable, Sendable {
    /// Outside looking in — the establishing shot.
    case orbit
    /// Inside at eye height, look and move like a first-person walkthrough.
    case walk
    /// Straight down, ceiling hidden, for the floor plan read.
    case plan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .orbit: return "Orbit"
        case .walk: return "Walk"
        case .plan: return "Plan"
        }
    }

    var symbol: String {
        switch self {
        case .orbit: return "rotate.3d"
        case .walk: return "figure.walk"
        case .plan: return "square.split.bottomrightquarter"
        }
    }
}

/// The camera's full state. A value type, so it animates and diffs cleanly from SwiftUI.
struct DemoCameraPose: Equatable, Sendable {
    var mode: DemoCameraMode = .orbit

    // Orbit
    var target = Plan.Camera.orbitTarget
    var distance: Float = Plan.Camera.orbitDistance
    var orbitYaw: Float = Plan.Camera.orbitYaw
    var orbitPitch: Float = Plan.Camera.orbitPitch

    // Walk
    var eye = Plan.Camera.startPosition
    var walkYaw: Float = Plan.Camera.startYaw
    var walkPitch: Float = 0

    // Plan
    var planCentre = SIMD2<Float>(Plan.width / 2, Plan.length / 2)
    var planHeight: Float = Plan.Camera.planHeight
    var planYaw: Float = 0

    /// Ground displacement during the quake. Subtracted from the eye so that the whole
    /// room appears to shake rather than only the loose objects.
    var shakeOffset = SIMD3<Float>.zero

    // MARK: Derived pose

    var position: SIMD3<Float> {
        let base: SIMD3<Float>
        switch mode {
        case .orbit:
            let cp = cos(orbitPitch)
            base = target + SIMD3(
                sin(orbitYaw) * cp * distance,
                sin(orbitPitch) * distance,
                cos(orbitYaw) * cp * distance
            )
        case .walk:
            base = eye
        case .plan:
            base = SIMD3(planCentre.x, planHeight, planCentre.y)
        }
        return base - shakeOffset
    }

    var lookAt: SIMD3<Float> {
        switch mode {
        case .orbit:
            return target - shakeOffset
        case .walk:
            let forward = SIMD3(
                sin(walkYaw) * cos(walkPitch),
                sin(walkPitch),
                cos(walkYaw) * cos(walkPitch)
            )
            return eye + forward - shakeOffset
        case .plan:
            // Looking straight down degenerates a plain look-at, so the target is nudged
            // a hair off the vertical axis and the up vector is supplied explicitly below.
            return SIMD3(planCentre.x, 0, planCentre.y) - shakeOffset
        }
    }

    var fieldOfView: Float {
        switch mode {
        case .orbit: return 46
        case .walk: return 68      // wider, so interiors do not feel claustrophobic
        case .plan: return 42
        }
    }

    /// Plan view needs an explicit up vector because the view direction is parallel to
    /// world up, which makes the default basis undefined.
    var upVector: SIMD3<Float> {
        switch mode {
        case .plan: return SIMD3(sin(planYaw), 0, -cos(planYaw))
        default: return SIMD3(0, 1, 0)
        }
    }

    // MARK: Mutation

    mutating func applyDrag(translation: SIMD2<Float>) {
        switch mode {
        case .orbit:
            orbitYaw -= translation.x / 220
            orbitPitch = clampPitch(orbitPitch + translation.y / 260)
        case .walk:
            // Inverted relative to orbit: dragging turns the head, not the world.
            walkYaw -= translation.x / 260
            walkPitch = clampPitch(walkPitch - translation.y / 300, limit: 1.20)
        case .plan:
            let scale = planHeight / 900
            planCentre.x -= translation.x * scale
            planCentre.y -= translation.y * scale
            clampPlan()
        }
    }

    mutating func applyMagnification(_ factor: Float) {
        switch mode {
        case .orbit:
            distance = min(max(distance / factor, 1.4), 26)
        case .walk:
            // Pinch nudges the walker forward and back, which is more useful than zoom.
            moveWalker(forward: (factor - 1) * 2.2, strafe: 0)
        case .plan:
            planHeight = min(max(planHeight / factor, 4.5), 22)
        }
    }

    /// Moves the first-person camera in its own facing frame, then keeps it inside the
    /// apartment. Without the clamp the demo's most likely embarrassment is walking
    /// through a wall in front of an investor.
    mutating func moveWalker(forward: Float, strafe: Float) {
        let sy = sin(walkYaw), cy = cos(walkYaw)
        eye.x += sy * forward + cy * strafe
        eye.z += cy * forward - sy * strafe
        clampWalker()
    }

    mutating func clampWalker() {
        let inset: Float = 0.42
        eye.x = min(max(eye.x, inset), Plan.width - inset)
        eye.z = min(max(eye.z, inset), Plan.length - inset)
        eye.y = Plan.Camera.eyeHeight
    }

    private mutating func clampPlan() {
        planCentre.x = min(max(planCentre.x, 0), Plan.width)
        planCentre.y = min(max(planCentre.y, 0), Plan.length)
    }

    private func clampPitch(_ value: Float, limit: Float = 1.44) -> Float {
        min(max(value, -limit), limit)
    }

    // MARK: Presets

    static func preset(for mode: DemoCameraMode, from current: DemoCameraPose) -> DemoCameraPose {
        var pose = current
        pose.mode = mode
        switch mode {
        case .orbit:
            pose.target = Plan.Camera.orbitTarget
            pose.distance = Plan.Camera.orbitDistance
            pose.orbitYaw = Plan.Camera.orbitYaw
            pose.orbitPitch = Plan.Camera.orbitPitch
        case .walk:
            pose.eye = Plan.Camera.startPosition
            pose.walkYaw = Plan.Camera.startYaw
            pose.walkPitch = 0
        case .plan:
            pose.planCentre = SIMD2(Plan.width / 2, Plan.length / 2)
            pose.planHeight = Plan.Camera.planHeight
            pose.planYaw = 0
        }
        return pose
    }

    /// Frame-rate independent blend, used when switching modes and for the guided tour.
    static func blend(_ a: DemoCameraPose, _ b: DemoCameraPose, _ t: Float) -> DemoCameraPose {
        var out = b
        out.target = mix(a.target, b.target, t)
        out.distance = mix(a.distance, b.distance, t)
        out.orbitYaw = mix(a.orbitYaw, b.orbitYaw, t)
        out.orbitPitch = mix(a.orbitPitch, b.orbitPitch, t)
        out.eye = mix(a.eye, b.eye, t)
        out.walkYaw = mix(a.walkYaw, b.walkYaw, t)
        out.walkPitch = mix(a.walkPitch, b.walkPitch, t)
        out.planCentre = mix(a.planCentre, b.planCentre, t)
        out.planHeight = mix(a.planHeight, b.planHeight, t)
        return out
    }

    private static func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
    private static func mix(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ t: Float) -> SIMD2<Float> { a + (b - a) * t }
    private static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * t }
}

// MARK: - Applying the pose

@MainActor
enum DemoCameraRig {
    static func apply(_ pose: DemoCameraPose, to camera: PerspectiveCamera) {
        camera.camera.fieldOfViewInDegrees = pose.fieldOfView
        camera.camera.near = 0.04
        camera.camera.far = 220

        let eye = pose.position
        let focus = pose.lookAt

        if pose.mode == .plan {
            // Build the basis by hand: `look(at:from:)` cannot resolve a straight-down view.
            let forward = simd_normalize(focus - eye)
            let up = pose.upVector
            let right = simd_normalize(simd_cross(up, -forward))
            let trueUp = simd_cross(-forward, right)
            let rotation = simd_float3x3(right, trueUp, -forward)
            camera.transform = Transform(
                scale: SIMD3(repeating: 1),
                rotation: simd_quatf(rotation),
                translation: eye
            )
        } else {
            camera.look(at: focus, from: eye, relativeTo: nil)
        }
    }

    /// The establishing orbit the room performs on its own once generation finishes.
    static func idleOrbit(_ pose: inout DemoCameraPose, deltaTime: Float) {
        guard pose.mode == .orbit else { return }
        pose.orbitYaw += deltaTime * 0.085
    }
}
