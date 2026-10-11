//
//  ScanFlowPreviews.swift
//  Tremor — Scan flow (S-09 … S-11) / preview and test harness
//
//  The three scan screens all read the same in-progress `ScanDraft`, so
//  previewing one means seeding a draft in a particular state. This host does
//  that in one line, against `TremorEnvironment.makePreview()` — a throwaway
//  library in a temporary directory that can never touch the user's rooms.
//
//  It is also what the unit tests use to build a draft, which is why the state
//  builders are static and pure rather than living inside a `#Preview`.
//

import Foundation
import SwiftUI

// MARK: - Draft states

/// The scan-flow states worth previewing and worth testing.
enum ScanFlowFixture {

    /// A clean capture: every quality check passes.
    static func cleanResult(room: ScannedRoom = RoomFixtures.dangerousBedroom) -> ScanResult {
        ScanResult(
            room: room,
            quality: ScanQualityReport(
                wallCount: room.surfaces.filter { $0.kind == .wall }.count,
                floorCount: max(room.surfaces.filter { $0.kind == .floor }.count, 1),
                openingCount: room.surfaces.filter {
                    $0.kind == .door || $0.kind == .window || $0.kind == .opening
                }.count,
                objectCount: room.objects.count,
                droppedObjectCount: 0,
                completeWallFraction: 1,
                highConfidenceFraction: 0.94,
                lowConfidenceFraction: 0,
                floorArea: room.floorArea,
                issues: []),
            crops: [:],
            sourceIdentifiers: Dictionary(uniqueKeysWithValues: room.objects.map { ($0.id, $0.id) }),
            elapsed: 142)
    }

    /// A capture the gate should stop: unfinished walls and shaky confidence.
    static func degradedResult(room: ScannedRoom = RoomFixtures.dangerousBedroom) -> ScanResult {
        var result = cleanResult(room: room)
        result.quality = ScanQualityReport(
            wallCount: 3,
            floorCount: 1,
            openingCount: 1,
            objectCount: room.objects.count,
            droppedObjectCount: 2,
            completeWallFraction: 0.55,
            highConfidenceFraction: 0.48,
            lowConfidenceFraction: 0.34,
            floorArea: room.floorArea,
            issues: [.wallCompleteness, .confidence])
        return result
    }

    /// A capture that found the room but no furniture at all.
    static func emptyResult() -> ScanResult {
        var room = RoomFixtures.dangerousBedroom
        room.objects = []
        var result = cleanResult(room: room)
        result.quality = ScanQualityReport(
            wallCount: 4,
            floorCount: 1,
            openingCount: 2,
            objectCount: 0,
            droppedObjectCount: 0,
            completeWallFraction: 1,
            highConfidenceFraction: 0.9,
            lowConfidenceFraction: 0,
            floorArea: room.floorArea,
            issues: [.noObjects])
        return result
    }

    /// A draft ready for S-10 or S-11.
    static func draft(result: ScanResult?, isDemo: Bool = false) -> ScanDraft {
        var draft = ScanDraft(name: "Bedroom", kind: .bedroom, isDemo: isDemo)
        draft.result = result
        draft.preview = result?.room
        if let result {
            draft.progress = ScanCoach.progress(for: result.room, elapsed: result.elapsed)
        }
        return draft
    }
}

// MARK: - Host

/// Renders one scan-flow screen with a router, an app state and a seeded draft.
@MainActor
struct ScanFlowPreviewHost: View {

    enum ReviewQuality {
        case clean, degraded, empty, missing
    }

    enum Stage {
        case capture
        case review(quality: ReviewQuality)
        case processing
    }

    private let env: TremorEnvironment
    private let stage: Stage
    @State private var router = Router()
    @State private var appState: AppState

    /// `env` defaults to a fresh fixture-backed environment. It is resolved
    /// inside the initialiser rather than as a default argument because default
    /// arguments are evaluated at the call site, which is not main-actor
    /// isolated in a `#Preview`.
    init(stage: Stage, env: TremorEnvironment? = nil) {
        let resolved = env ?? .makePreview()
        self.stage = stage
        self.env = resolved
        _appState = State(initialValue: AppState(env: resolved))
    }

    var body: some View {
        Group {
            switch stage {
            case .capture: ScanView()
            case .review: ScanReviewView()
            case .processing: ProcessingView()
            }
        }
        .environment(\.tremor, env)
        .environment(router)
        .environment(appState)
        .onAppear(perform: seed)
    }

    private func seed() {
        switch stage {
        case .capture:
            appState.beginScan(kind: .bedroom)
        case .review(let quality):
            switch quality {
            case .clean: appState.draft = ScanFlowFixture.draft(result: ScanFlowFixture.cleanResult())
            case .degraded: appState.draft = ScanFlowFixture.draft(result: ScanFlowFixture.degradedResult())
            case .empty: appState.draft = ScanFlowFixture.draft(result: ScanFlowFixture.emptyResult())
            case .missing: appState.draft = ScanFlowFixture.draft(result: nil)
            }
        case .processing:
            appState.draft = ScanFlowFixture.draft(result: ScanFlowFixture.cleanResult())
        }
    }
}
