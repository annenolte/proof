//
//  RootView.swift
//  Tremor — App shell / the root composition
//
//  Three responsibilities, in order of when they happen:
//
//   1. **The cold-start gate (S-01).** Decide, before the first frame the user
//      perceives, whether they are going to onboarding, sign-in, permission
//      priming or the app. The decision itself is `LaunchPhase.gate`, which is a
//      pure function and is unit-tested; this file only runs the work the gate
//      needs (library index, credential revalidation, camera status) and shows
//      the wordmark while it happens.
//
//   2. **The three-tab shell.** `Rooms`, `Add Room` and `Settings`, one
//      navigation stack each, a tab bar drawn from design-system tokens, and the
//      immersive screens (camera, processing, 3D stage) taking the whole display
//      when they need it — including when the immersive screen *is* a tab root,
//      which is the case for the whole Add Room flow.
//
//   3. **The global overlays.** One toast host at the very top of the tree, so a
//      toast raised by a screen that is being dismissed still gets seen, and one
//      quiet offline notice above the tab bar.
//

import Foundation
import SwiftUI

// MARK: - Root

struct RootView: View {

    @Environment(\.tremor) private var tremor
    @Environment(Router.self) private var router
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var appState = appState

        ZStack {
            switch router.phase {
            case .launching:
                LaunchScreen(isMigrating: false)
                    .transition(.opacity)
            case .migrating:
                LaunchScreen(isMigrating: true)
                    .transition(.opacity)
            case .onboarding:
                OnboardingCarouselView()
                    .transition(.opacity)
            case .signIn:
                SignInView()
                    .transition(.opacity)
            case .permissionPrimer:
                PermissionPrimerView(isFirstRun: true)
                    .transition(.opacity)
            case .ready:
                TabShell()
                    .transition(.opacity)
            }
        }
        .animation(
            TremorMotion.resolved(TremorMotion.reveal, reduceMotion: reduceMotion),
            value: router.phase)
        .tremorToast($appState.toast)
        .task { await coldStart() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !router.phase.isResolving else { return }
            Task { await foreground() }
        }
    }

    // MARK: Cold start (S-01)

    /// The work S-01 covers: load the library index, revalidate the Apple
    /// credential, read the camera status. Then the gate decides where to go.
    ///
    /// Two deliberate details:
    ///
    /// * If the index has not answered within 400 ms we switch to the migration
    ///   state, which is honest rather than pretending a slow disk is instant.
    ///   SPEC caps this at 3 s; past that we go to the library anyway and let
    ///   individual rooms migrate lazily.
    /// * We hold the wordmark for a beat on a fast launch so it reads as a brand
    ///   moment rather than a flash — unless Reduce Motion is on, in which case
    ///   there is nothing to see and waiting would just be a delay.
    private func coldStart() async {
        guard router.phase == .launching else { return }
        let started = Date()

        let work = Task { @MainActor in
            // `list()` is what rebuilds the index and surfaces damaged packages;
            // it never throws for one bad room.
            _ = try? await tremor.rooms.seedSamplesIfNeeded()
            _ = try? await tremor.rooms.list()
            tremor.permissions.refresh()
            await tremor.account.revalidate()
        }

        let slow = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, router.phase == .launching else { return }
            router.setLaunchPhase(.migrating)
        }

        // Never hold the launch screen longer than SPEC's 3 s ceiling.
        let deadline = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            work.cancel()
        }

        await work.value
        slow.cancel()
        deadline.cancel()

        if !reduceMotion {
            let elapsed = Date().timeIntervalSince(started)
            if elapsed < Self.minimumLaunchSeconds {
                let remaining = Self.minimumLaunchSeconds - elapsed
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
        }

        router.advanceLaunch(with: tremor)
        announceRevocationIfNeeded()

        #if DEBUG
        // Applied again once the gate has run, so `-proofScreen` never loses the race
        // with it. Every override is idempotent.
        let arguments = LaunchArguments()
        if arguments.isActive {
            await arguments.apply(router: router, appState: appState, env: tremor)
        }
        #endif
    }

    /// Every foreground: the camera can have been changed in Settings, and the
    /// Apple credential can have been revoked while we were away (SPEC §3.5).
    private func foreground() async {
        tremor.permissions.refresh()
        await tremor.account.revalidate()
        announceRevocationIfNeeded()
    }

    /// Revocation is a toast, never a modal: nothing the user was doing depends
    /// on the account, because Tremor stores nothing on a server.
    private func announceRevocationIfNeeded() {
        guard tremor.account.credentialWasRevoked else { return }
        tremor.account.credentialWasRevoked = false
        appState.post(
            "You signed out of Apple",
            message: "Your rooms are still here — they live on this iPhone.",
            style: .info)
    }

    /// Long enough for the seismic trace to land, short enough that nobody waits
    /// on it. SPEC S-01 budgets 400 ms for the launch state.
    private static let minimumLaunchSeconds: TimeInterval = 0.7
}

#Preview("Root — ready") {
    RootPreviewHost(env: .makePreview(), phase: .ready)
}

#Preview("Root — first run") {
    RootPreviewHost(
        env: .makePreview(onboarded: false, signedIn: false),
        phase: .onboarding)
}

#Preview("Root — offline") {
    RootPreviewHost(env: .makePreview(online: false), phase: .ready)
}

// MARK: - Launch screen (S-01)

/// The cold-start screen: a full-bleed ink field, the wordmark, and a 2 pt
/// seismic trace that draws itself across the baseline once.
///
/// It carries no controls on purpose. If the work behind it is slow the copy
/// changes to say so; it never turns into an error, because SPEC S-01 says a
/// damaged index is recovered silently rather than confessed at launch.
struct LaunchScreen: View {

    var isMigrating: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var traceProgress: CGFloat = 0

    var body: some View {
        ZStack {
            TremorColor.ink.ignoresSafeArea()

            VStack(spacing: TremorSpacing.xl) {
                ZStack(alignment: .bottom) {
                    Text("proof")
                        .tremorType(.displayL)
                        .foregroundStyle(TremorColor.primarySoft)

                    SeismicTrace()
                        .trim(from: 0, to: traceProgress)
                        .stroke(
                            TremorColor.accent,
                            style: StrokeStyle(lineWidth: TremorSize.strokeEmphasis,
                                               lineCap: .round, lineJoin: .round))
                        .frame(height: TremorSpacing.xl)
                        .padding(.horizontal, -TremorSpacing.lg)
                        .offset(y: TremorSpacing.sm)
                        .accessibilityHidden(true)
                }

                if isMigrating {
                    VStack(spacing: TremorSpacing.sm) {
                        Text("Updating your rooms…")
                            .tremorType(.callout)
                            .foregroundStyle(TremorColor.inkInverse.opacity(0.78))
                        TremorProgressBar(value: nil, tint: TremorColor.accent)
                            .frame(maxWidth: Self.progressWidth)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, TremorSpacing.pageInset)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("proof")
        .accessibilityValue(isMigrating ? "Updating your rooms" : "Starting up")
        .accessibilityAddTraits(.updatesFrequently)
        .task {
            guard !reduceMotion else {
                traceProgress = 1
                return
            }
            withAnimation(.timingCurve(0, 0, 0.15, 1, duration: Self.traceSeconds)) {
                traceProgress = 1
            }
        }
    }

    /// SPEC S-01: the trace draws left to right over 700 ms, once, no repeat.
    private static let traceSeconds: Double = 0.7
    private static let progressWidth: CGFloat = 180
}

/// A single burst of ground motion: quiet, a sharp arrival, then a decay. The
/// same shape as the accelerograms the app actually integrates, which is why it
/// is drawn rather than being a generic sine.
private struct SeismicTrace: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 220
        let midY = rect.midY
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            // Gaussian envelope centred just past the wordmark's midpoint.
            let envelope = exp(-pow((t - 0.46) / 0.19, 2))
            let carrier = sin(t * 52) * 0.7 + sin(t * 23 + 1.1) * 0.3
            let y = midY - CGFloat(carrier * envelope) * rect.height / 2
            let point = CGPoint(x: rect.minX + rect.width * CGFloat(t), y: y)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

#Preview("S-01 launch") {
    LaunchScreen(isMigrating: false)
}

#Preview("S-01 migrating") {
    LaunchScreen(isMigrating: true)
}

// MARK: - Tab shell

/// The three-tab root. Every stack stays alive so switching tabs preserves
/// scroll position and navigation depth, which is what every iOS user expects
/// and what a `switch` over the selected tab would quietly throw away.
///
/// Keeping Add Room alive matters more than the other two: its 3D room takes
/// seconds to build, and a user who glances at Rooms mid-flow must come back to
/// the room they were already standing in, not to a rebuild.
struct TabShell: View {

    @Environment(\.tremor) private var tremor
    @Environment(Router.self) private var router
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var router = router

        // A real column, not a `safeAreaInset` on the stack of tabs.
        //
        // `safeAreaInset` reduces a view's *safe-area metadata*; it does not shrink its
        // frame. Scroll views honour that and reinset their content, so lists looked
        // right — but anything that simply lays out, which is every docked CTA in the app,
        // filled the full frame and was drawn underneath the tab bar. It cost the report
        // screen its "Back to the room" button once (worked around by standing the tab bar
        // down) and the Add Room CTA a second time. A `VStack` ends where the tab bar
        // begins, so nothing has to know the tab bar's height to stay clear of it.
        VStack(spacing: 0) {
            ZStack {
                stack(for: .rooms, path: $router.roomsPath)
                    .opacity(router.tab == .rooms ? 1 : 0)
                    .allowsHitTesting(router.tab == .rooms)
                    .accessibilityHidden(router.tab != .rooms)

                stack(for: .addRoom, path: $router.addRoomPath)
                    .opacity(router.tab == .addRoom ? 1 : 0)
                    .allowsHitTesting(router.tab == .addRoom)
                    .accessibilityHidden(router.tab != .addRoom)

                stack(for: .settings, path: $router.settingsPath)
                    .opacity(router.tab == .settings ? 1 : 0)
                    .allowsHitTesting(router.tab == .settings)
                    .accessibilityHidden(router.tab != .settings)
            }

            VStack(spacing: TremorSpacing.xs) {
                OfflineNotice()
                if !router.hidesTabBar {
                    TremorTabBar(selection: router.tab) { router.select($0) }
                }
            }
        }
        .background(TremorColor.canvas.ignoresSafeArea())
        .sheet(item: $router.sheet) { route in
            SheetScreen(route: route)
        }
        .fullScreenCover(item: $router.cover) { route in
            CoverScreen(route: route)
        }
    }

    @ViewBuilder
    private func stack(for tab: TremorTab, path: Binding<[Route]>) -> some View {
        NavigationStack(path: path) {
            TabRootScreen(tab: tab)
                .navigationDestination(for: Route.self) { route in
                    RouteScreen(route: route)
                }
        }
    }
}

#Preview("Tab shell") {
    RootPreviewHost(env: .makePreview(), phase: .ready)
}

// MARK: - Tab bar

/// The tab bar, built from design-system tokens rather than `TabView`'s chrome
/// so it sits on the same warm canvas as everything else.
///
/// Applied through `safeAreaInset`, never as an overlay, so scroll views inside
/// each tab get the correct bottom inset and no list ever ends underneath it.
struct TremorTabBar: View {

    var tabs: [TremorTab] = TremorTab.allCases
    var selection: TremorTab
    var onSelect: (TremorTab) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// At accessibility sizes the label is dropped and the glyph grows. Nothing
    /// clips, and VoiceOver still hears the full name because it comes from the
    /// accessibility label, not from the visible text.
    private var showsLabels: Bool { !dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                item(tab, position: index + 1)
            }
        }
        .padding(.top, TremorSpacing.xs)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                TremorColor.surface
                Rectangle()
                    .fill(TremorColor.divider)
                    .frame(height: TremorSize.hairline)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Main")
    }

    private func item(_ tab: TremorTab, position: Int) -> some View {
        let isSelected = tab == selection
        var traits = AccessibilityTraits.isButton
        if isSelected { traits.formUnion(.isSelected) }
        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: TremorSpacing.hair) {
                Image(systemName: tab.symbolName(selected: isSelected))
                    .font(.system(
                        size: showsLabels
                            ? TremorControlMetrics.glyphMedium
                            : TremorControlMetrics.glyphLarge,
                        weight: .medium))
                if showsLabels {
                    Text(tab.title)
                        .tremorType(.caption)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isSelected ? TremorColor.primary : TremorColor.inkTertiary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: TremorSize.minimumTapTarget)
            .padding(.vertical, TremorSpacing.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.title)
        .accessibilityValue("Tab \(position) of \(tabs.count)")
        .accessibilityAddTraits(traits)
        .accessibilityHint(isSelected ? "Double tap to go back to the top" : "")
    }
}

#Preview("Tab bar") {
    VStack(spacing: TremorSpacing.xxl) {
        TremorTabBar(selection: .rooms) { _ in }
        TremorTabBar(selection: .addRoom) { _ in }
        TremorTabBar(selection: .settings) { _ in }
        TremorTabBar(selection: .rooms) { _ in }
            .environment(\.dynamicTypeSize, .accessibility3)
    }
    .padding(.vertical, TremorSpacing.xxl)
    .background(TremorColor.canvas)
}

// MARK: - Offline notice

/// SPEC §1.5: offline is "a single note where relevant. No modal ever." So this
/// is a quiet strip that says what still works, dismissible, and it never
/// disables anything.
struct OfflineNotice: View {

    @Environment(\.tremor) private var tremor
    @State private var isDismissed = false

    private var isVisible: Bool {
        tremor.network.hasResolved && !tremor.network.isOnline && !isDismissed
    }

    var body: some View {
        Group {
            if isVisible {
                TremorBanner(
                    "You're offline",
                    message: "Your rooms, their flags and your checklist all work offline.",
                    kind: .neutral,
                    onDismiss: { isDismissed = true })
                .padding(.horizontal, TremorSpacing.md)
                .transition(.opacity)
            }
        }
        .animation(TremorMotion.reveal, value: isVisible)
        .onChange(of: tremor.network.isOnline) { _, online in
            // Re-arm for the next outage; a dismissal is for this episode only.
            if online { isDismissed = false }
        }
    }
}

#Preview("Offline notice") {
    OfflineNotice()
        .environment(\.tremor, .makePreview(online: false))
        .padding(.vertical, TremorSpacing.xxl)
        .background(TremorColor.canvas)
}

// MARK: - Preview host

/// Wires a router, an app state and an environment together the way `TremorApp`
/// does, so a `#Preview` anywhere in the app can render a real screen with real
/// navigation against fixtures.
///
/// ```swift
/// #Preview { RootPreviewHost(env: .makePreview(), phase: .ready) }
/// ```
@MainActor
struct RootPreviewHost: View {

    private let env: TremorEnvironment
    @State private var router: Router
    @State private var appState: AppState

    init(
        env: TremorEnvironment,
        phase: LaunchPhase = .ready,
        tab: TremorTab = .rooms,
        path: [Route] = []
    ) {
        self.env = env
        // Configured here rather than in a `.task`, so the preview never races
        // `RootView`'s own cold-start task.
        let router = Router()
        router.phase = phase
        router.tab = tab
        router.replacePath(with: path)
        _router = State(initialValue: router)
        _appState = State(initialValue: AppState(env: env))
    }

    var body: some View {
        RootView()
            .environment(\.tremor, env)
            .environment(router)
            .environment(appState)
    }
}
