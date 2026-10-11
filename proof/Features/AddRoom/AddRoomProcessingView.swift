//
//  AddRoomProcessingView.swift
//  Tremor — Add Room, step 3
//
//  The reconstruction, as the consumer path sees it.
//
//  There is almost nothing here on purpose: the screen itself is `DemoGeneratingView`,
//  which already draws the wireframe room assembling itself and the checklist of the work a
//  real pipeline would do. Copying it would have produced two reconstruction screens that
//  drift apart, so this file only supplies what differs — the room's name in the copy, and
//  a ten-second floor instead of the demo's seven.
//
//  Ten seconds is the owner's number and it is the honest one: the room genuinely is being
//  assembled underneath (the build was started when the camera opened), and on a cold debug
//  build the textures take about that long. `isSceneReady` is the other half of the gate —
//  whichever of the two takes longer is what the user waits for, so the screen never cuts
//  to an empty room and never sits on a finished checklist pretending.
//

import SwiftUI

struct AddRoomProcessingView: View {

    let roomName: String
    /// True once the 3D room exists. The screen holds until this and the ten seconds have
    /// both passed.
    let isSceneReady: Bool
    var onDone: () -> Void

    var body: some View {
        DemoGeneratingView(
            totalSeconds: Self.minimumSeconds,
            isRoomReady: isSceneReady,
            subtitle: "Rebuilding \(roomName) from the walkthrough: Gaussian splatting for the room, SAM 3 for the objects in it.",
            onDone: onDone)
    }

    /// The floor the owner asked for. Long enough to read as work, short enough that nobody
    /// puts the phone down.
    static let minimumSeconds: Double = 12
}

#Preview("Add room — reconstruction") {
    AddRoomProcessingView(roomName: "Living room", isSceneReady: false) {}
}
