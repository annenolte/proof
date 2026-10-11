//
//  AddRoomFlowModel.swift
//  proof — Add Room
//
//  The spine of the consumer path, kept from Tremor:
//
//      name it  →  say what you're preparing for  →  film it  →  build it  →  see the sky  →  check it
//
//  One object owns the whole sequence, for the two reasons Tremor gave:
//
//  1. **The room starts building before anyone asks for it.** Assembling the kitchen —
//     meshes, PBR textures, the synthesised IBL — takes seconds, so the build is kicked off
//     the moment the camera opens and is normally finished before the user stops filming.
//
//  2. **The 3D room is expensive and must exist exactly once.** `DemoRoomModel` owns the
//     scene, the camera and the renderer; this model holds one and the sky that goes over it.
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AddRoomFlowModel {

    /// Where the user is. Ordered as they are reached.
    enum Step: Equatable {
        /// Naming the room.
        case naming
        /// The concern and the age stage; the translator's noun phrases.
        case concern
        /// The guided capture, live or replaced by the example kitchen walkthrough.
        case capturing
        /// The reconstruction: Gaussian splatting and SAM 3, as the pipeline runs them.
        case processing
        /// Standing in the finished room under its sky.
        case exploring
        /// The checklist.
        case analysis

        /// True for the steps that own the whole display, so the shell's tab bar stands down.
        var isImmersive: Bool {
            switch self {
            case .capturing, .processing, .exploring, .analysis: return true
            case .naming, .concern: return false
            }
        }

        /// Stable machine name, for the launch arguments and for tests.
        var name: String {
            switch self {
            case .naming: return "naming"
            case .concern: return "concern"
            case .capturing: return "capturing"
            case .processing: return "processing"
            case .exploring: return "exploring"
            case .analysis: return "analysis"
            }
        }
    }

    private(set) var step: Step = .naming

    /// What the user typed. An empty name falls back to `defaultRoomName`.
    var roomName: String = ""

    /// The photoreal kitchen and its scene lifecycle, reused wholesale from Tremor.
    let demo = DemoRoomModel()

    /// The constellation over it.
    let sky = ConstellationModel()

    /// True when the user replaced the live camera with the bundled walkthrough. Recorded
    /// rather than hidden: it is the reason the finished room is the example kitchen rather
    /// than whatever the phone was pointed at.
    var usedDemoInjection = false

    init() {}

    // MARK: - Names

    static let defaultRoomName = "Kitchen"

    /// The one-tap suggestions on the naming screen.
    static let suggestedNames = ["Kitchen", "Living room", "Nursery", "Playroom"]

    var trimmedName: String {
        roomName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var displayName: String {
        trimmedName.isEmpty ? Self.defaultRoomName : trimmedName
    }

    var canBeginCapture: Bool { !trimmedName.isEmpty }

    /// The stage, read and written through the sky so the explorer and this flow agree.
    var stage: AgeStage {
        get { sky.stage }
        set { sky.setStage(newValue) }
    }

    // MARK: - Flow

    /// naming → concern.
    func chooseConcern() {
        guard step == .naming else { return }
        step = .concern
    }

    func backToNaming() {
        guard step == .concern else { return }
        step = .naming
    }

    /// concern → capturing. Also starts the room building underneath the camera.
    func beginCapture() {
        guard step == .concern else { return }
        step = .capturing
        Task { await demo.prepareScene() }
    }

    /// capturing → processing.
    func finishCapture(injected: Bool) {
        guard step == .capturing else { return }
        usedDemoInjection = injected
        demo.confirmScan()
        step = .processing
    }

    /// processing → exploring.
    func finishProcessing() {
        guard step == .processing else { return }
        demo.finishGenerating()
        step = .exploring
    }

    /// → the checklist.
    func showAnalysis() {
        guard step == .exploring else { return }
        step = .analysis
    }

    /// checklist → the room, which was never torn down.
    func backToRoom() {
        guard step == .analysis else { return }
        step = .exploring
    }

    /// Opens the finished kitchen directly — from the Rooms tab, once it has been built.
    func reopenRoom() {
        guard demo.isSceneReady else { return }
        if step == .analysis { step = .exploring }
    }

    /// Back to the beginning, with the room released. The caregiver's edits are kept —
    /// they belong to the kitchen, not to this pass through the flow.
    func startOver() {
        demo.frameHandler = nil
        demo.teardown()
        usedDemoInjection = false
        roomName = ""
        step = .naming
    }

    // MARK: - Launch arguments

    /// `-proofAddRoomStep <step>` drops straight into any step of the flow. Debug only.
    @discardableResult
    func applyLaunchOverride(_ arguments: LaunchArguments = LaunchArguments()) async -> Bool {
        #if DEBUG
        guard let target = arguments.addRoomStep else { return false }
        if roomName.isEmpty { roomName = Self.defaultRoomName }

        switch target {
        case "naming":
            step = .naming
        case "concern":
            step = .concern
        case "capturing":
            step = .concern
            beginCapture()
        case "processing":
            step = .concern
            beginCapture()
            finishCapture(injected: true)
        case "exploring", "analysis":
            step = .concern
            beginCapture()
            finishCapture(injected: true)
            await demo.prepareScene()
            finishProcessing()
            if target == "analysis" { showAnalysis() }
        default:
            return false
        }
        return true
        #else
        return false
        #endif
    }
}
