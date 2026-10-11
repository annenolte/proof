import Foundation
import SwiftUI

/// Deep-links the app to a specific screen at launch, driven by process
/// arguments.
///
/// This exists so the whole product can be inspected without a human tapping
/// through it: a screenshot sweep, a review pass, or a UI test can put the app
/// on any screen in one command. It is also the only practical way to
/// screenshot the deeper screens on a Simulator, where there is no LiDAR and so
/// no way to reach them through the scan flow.
///
/// It is a **debug-build-only** facility — `#if DEBUG` guards the whole
/// application of it, so a release build ignores these arguments entirely and
/// no user can route themselves into a half-configured state.
///
/// Usage:
///
///     xcrun simctl launch booted ai.skarmy.Tremor \
///         -tremorScreen stage -tremorRoom bedroom -tremorStagePhase results
///
/// Supported arguments:
///
/// | Argument | Values |
/// |---|---|
/// | `-tremorScreen` | `onboarding` `signIn` `permissions` `library` `settings` `method` `demoRooms` `scanSetup` `stage` `objectDetail` `fixItPlan` `share` `profile` `addRoom` `demo` |
/// | `-tremorAddRoomStep` | `naming` `capturing` `processing` `exploring` `analysis` |
/// | `-tremorRoom` | `bedroom` `living` `kitchen` `nursery` `garage` |
/// | `-tremorStagePhase` | `viewer` `configurator` `running` `results` |
/// | `-tremorIntensity` | `3`…`10` |
/// | `-tremorResetState` | `1` to wipe onboarding/account flags first |
public struct LaunchArguments {

    public enum Screen: String {
        case onboarding, signIn, permissions
        case library, settings, method, demoRooms, scanSetup
        case stage, objectDetail, fixItPlan, share, profile
        /// The pre-built investor demo apartment.
        case demo
        /// The consumer capture path, at its tab root.
        case addRoom
    }

    public var screen: Screen?
    /// Which step of the Add Room flow to land on. Read by `AddRoomFlowModel`
    /// rather than applied here, because the flow is a state machine at a tab
    /// root and only the model knows how to reach a step legally — the router
    /// can get you to the tab and no further.
    public var addRoomStep: String?
    public var room: String?
    public var stagePhase: String?
    public var intensity: MercalliIntensity?
    public var resetsState: Bool

    public init(_ arguments: [String] = ProcessInfo.processInfo.arguments) {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            let next = arguments[i + 1]
            return next.hasPrefix("-") ? nil : next
        }
        let step = value("-proofAddRoomStep")
        self.addRoomStep = step
        // Naming a step is enough: nobody who asks for the reconstruction screen
        // also wants to have to say which tab it is on.
        self.screen = value("-proofScreen").flatMap(Screen.init(rawValue:))
            ?? (step == nil ? nil : .addRoom)
        self.room = value("-proofRoom")
        self.stagePhase = value("-proofStagePhase")
        self.intensity = value("-proofIntensity").flatMap(Int.init).flatMap(MercalliIntensity.init(rawValue:))
        self.resetsState = value("-proofResetState") == "1"
    }

    public var isActive: Bool { screen != nil || resetsState }

    /// The fixture the `-tremorRoom` argument names.
    public var fixtureRoom: ScannedRoom? {
        switch room {
        case "bedroom": return RoomFixtures.dangerousBedroom
        case "living": return RoomFixtures.safeLivingRoom
        case "kitchen": return RoomFixtures.kitchen
        case "nursery": return RoomFixtures.nursery
        case "garage": return RoomFixtures.garage
        case .some(let other):
            return RoomFixtures.all.first {
                $0.name.lowercased().hasPrefix(other.lowercased())
            }
        case nil: return nil
        }
    }
}

#if DEBUG
extension LaunchArguments {

    /// Applies the requested route once the environment is ready.
    @MainActor
    func apply(router: Router, appState: AppState, env: TremorEnvironment) async {
        if resetsState {
            env.settings.hasCompletedOnboarding = false
            env.account.signOut()
        }

        guard let screen else { return }

        switch screen {
        case .onboarding:
            router.setLaunchPhase(.onboarding)
            return
        case .signIn:
            router.setLaunchPhase(.signIn)
            return
        case .permissions:
            router.setLaunchPhase(.permissionPrimer)
            return
        default:
            // The cold-start gate is a pure function of the persisted flags, and
            // it re-runs after this. Setting only the phase loses that race, so
            // satisfy the gate's own inputs before setting it.
            env.settings.hasCompletedOnboarding = true
            if !env.account.hasChosen { _ = env.account.continueWithoutAccount() }
            router.setLaunchPhase(.ready)
        }

        switch screen {
        case .library:
            router.select(.rooms)
            router.popToRoot()
        case .settings:
            router.select(.settings)
        case .method:
            router.select(.settings)
            router.openMethod()
        case .demoRooms:
            router.select(.rooms)
            router.useDemoRoom()
        case .scanSetup:
            router.select(.rooms)
            router.push(.scanSetup)
        case .demo:
            router.select(.rooms)
            router.push(.demoRoom)
        case .addRoom:
            // The step, if one was named, is applied by `AddRoomFlowModel` when
            // the tab's root appears.
            router.openAddRoom()
        case .profile:
            router.select(.rooms)
            router.openProfile()
        case .stage, .objectDetail, .fixItPlan, .share:
            await openRoomAndRun(router: router, appState: appState, env: env, screen: screen)
        case .onboarding, .signIn, .permissions:
            break
        }
    }

    @MainActor
    private func openRoomAndRun(
        router: Router, appState: AppState, env: TremorEnvironment, screen: Screen
    ) async {
        // Prefer a room already in the library so the stage reads from the same
        // store the rest of the app does; fall back to adopting the fixture.
        let fixture = fixtureRoom ?? RoomFixtures.dangerousBedroom
        appState.adopt(room: fixture)
        router.select(.rooms)
        router.openRoom(fixture.id)

        let level = intensity ?? .viii
        appState.assess(intensity: level, persists: false)
        await appState.waitForAssessment()

        switch stagePhase {
        case "configurator": appState.stagePhase = .configurator
        case "running": appState.stagePhase = .running
        case "results": appState.stagePhase = .results
        case "viewer", nil: appState.stagePhase = .viewer
        default: appState.stagePhase = .viewer
        }

        switch screen {
        case .objectDetail:
            // The worst object in the room — the one a reviewer wants to see.
            if let worst = appState.assessment?.objectRisks.max(by: { $0.score < $1.score }) {
                appState.stagePhase = .results
                router.openObject(worst.objectID)
            }
        case .fixItPlan:
            appState.stagePhase = .results
            router.openFixItPlan()
        case .share:
            appState.stagePhase = .results
            router.share(roomID: fixture.id)
        default:
            break
        }
    }
}
#endif
