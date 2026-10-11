//
//  TremorApp.swift
//  Tremor
//
//  The entry point, and nothing else. It builds the composition root once,
//  injects the three things every screen may read — services, navigation, shared
//  screen state — and hands off to `RootView`.
//
//  There is deliberately no logic here. Anything that looks like a decision
//  belongs in `CompositionRoot` (what to construct), `Router` (where to go) or
//  `RootView` (what to show while deciding).
//

import SwiftUI

@main
struct TremorApp: App {

    /// Built once, at launch. `@State` rather than `let` so the services survive
    /// every re-evaluation of the scene.
    @State private var tremor: TremorEnvironment
    @State private var router: Router
    @State private var appState: AppState

    init() {
        // One construction, one graph. Everything downstream reads these.
        let environment = CompositionRoot.live()
        _tremor = State(initialValue: environment)
        _router = State(initialValue: Router())
        _appState = State(initialValue: AppState(env: environment))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.tremor, tremor)
                .environment(router)
                .environment(appState)
                // v1 ships light only (SPEC §1.5). `UIUserInterfaceStyle` is
                // already pinned in the Info.plist; this makes the intent
                // visible in code as well, so a stray `.preferredColorScheme`
                // in a screen reads as the anomaly it would be.
                .preferredColorScheme(.light)
                #if DEBUG
                // Debug builds honour `-tremorScreen` and friends so any screen
                // can be reached in one command, for screenshot sweeps and
                // review passes. Compiled out entirely in release.
                .task {
                    let arguments = LaunchArguments()
                    guard arguments.isActive else { return }
                    await arguments.apply(router: router, appState: appState, env: tremor)
                }
                #endif
        }
    }
}
