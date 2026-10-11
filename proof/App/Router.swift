//
//  Router.swift
//  Tremor — App shell / navigation
//
//  The navigation graph of SPEC §1.3, expressed as values rather than as views
//  reaching for each other.
//
//  The rule: **a screen never constructs another screen.** It states an
//  intent — `router.openRoom(id)`, `router.startScan()` — and the shell decides
//  what that means. That is what keeps the scan flow's path surgery (S-11 must
//  not be reachable by swiping back from S-12) in one file instead of five, and
//  what makes the whole graph testable without rendering anything.
//

import Foundation
import Observation
import SwiftUI

// MARK: - Tabs

/// SPEC §1.2 opened with "There are **two tabs only**: `Rooms` (S-06) and
/// `Settings` (S-19)". There are now three: adding a room is the app's whole
/// purpose, and burying it behind a card on the library meant the first thing a
/// new user wants to do was the one thing that was not on the tab bar.
///
/// Everything else is still pushed or presented.
enum TremorTab: String, CaseIterable, Hashable, Identifiable, Sendable {
    case rooms
    /// The consumer capture path: name → guided camera → reconstruction → the
    /// finished 3D room → earthquake → analysis.
    case addRoom
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rooms: return "Rooms"
        case .addRoom: return "Add Room"
        case .settings: return "Settings"
        }
    }

    /// Filled when selected, outline when not — the standard iOS reading, and a
    /// second channel besides colour for which tab is active.
    ///
    /// `plus.viewfinder` is the exception: SF Symbols ships no filled
    /// counterpart for it, and every alternative that has one (`viewfinder.circle`)
    /// is a heavier, rounder shape that sits badly beside the other two glyphs.
    /// The selected state is still carried by colour **and** by the
    /// `.isSelected` accessibility trait the tab bar applies, so nothing is lost
    /// for VoiceOver or for greyscale — only the glyph itself is invariant.
    func symbolName(selected: Bool) -> String {
        switch self {
        case .rooms: return selected ? "square.stack.3d.up.fill" : "square.stack.3d.up"
        case .addRoom: return "plus.viewfinder"
        case .settings: return selected ? "gearshape.fill" : "gearshape"
        }
    }
}

// MARK: - Pushed destinations

/// Everything that can be **pushed** onto a tab's navigation stack.
///
/// Cases carry identifiers, never payloads. The in-progress scan and the open
/// room live in `AppState`, so a route stays small, `Hashable`, and cheap to
/// keep in a path array.
enum Route: Hashable, Sendable {

    /// S-07 — building context, three steps.
    case scanSetup
    /// S-08 — device unsupported, pick a demo room.
    case demoRooms
    /// S-09 — live capture.
    case capture
    /// S-10 — scan review / quality gate.
    case scanReview
    /// S-11 — object understanding and physics precomputation.
    case processing
    /// S-12/S-13/S-14/S-15 — one screen, four sheet states (SPEC §1.1 principle
    /// 5). Which of the four is showing is `AppState.stagePhase`, not a route,
    /// because they share a persistent 3D stage and must never push.
    case stage(roomID: UUID)
    /// S-22 — the pre-built demo apartment: scripted capture, reconstruction and
    /// earthquake, on hand-authored photoreal geometry. Self-contained, and does not
    /// touch the scanning pipeline or the frozen physics core.
    case demoRoom
    /// S-17 — the fix-it plan checklist.
    case fixItPlan
    /// S-20 — method and sources.
    case method
    /// The bibliography rendered from `Sources.json`.
    case sources
    /// The privacy explainer.
    case privacy
    /// Font and data licences.
    case licences

    /// Stable machine name. Used by the tests and by local telemetry; never
    /// shown to a user.
    var name: String {
        switch self {
        case .scanSetup: return "scan-setup"
        case .demoRooms: return "demo-rooms"
        case .capture: return "capture"
        case .scanReview: return "scan-review"
        case .processing: return "processing"
        case .stage: return "stage"
        case .demoRoom: return "demo-room"
        case .fixItPlan: return "fix-it-plan"
        case .method: return "method"
        case .sources: return "sources"
        case .privacy: return "privacy"
        case .licences: return "licences"
        }
    }

    /// The SPEC §1.2 screen this route lands on.
    var specScreen: String {
        switch self {
        case .scanSetup: return "S-07"
        case .demoRooms: return "S-08"
        case .capture: return "S-09"
        case .scanReview: return "S-10"
        case .processing: return "S-11"
        case .stage: return "S-12"
        case .demoRoom: return "S-22"
        case .fixItPlan: return "S-17"
        case .method: return "S-20"
        case .sources, .privacy, .licences: return "S-19"
        }
    }

    /// The navigation-bar title. Empty for screens that draw their own chrome
    /// over a camera or a 3D stage.
    var title: String {
        switch self {
        case .scanSetup: return "New scan"
        case .demoRooms: return "Demo rooms"
        case .capture: return ""
        case .scanReview: return "Scan review"
        case .processing: return ""
        case .stage: return ""
        case .demoRoom: return ""
        case .fixItPlan: return "Fix-it plan"
        case .method: return "How proof works"
        case .sources: return "Sources"
        case .privacy: return "Privacy"
        case .licences: return "Licences"
        }
    }

    /// True for screens that own the whole display: the camera (S-09), the
    /// processing cover (S-11) and the 3D stage (S-12…S-15). The tab bar and the
    /// navigation bar both step aside for these.
    var isImmersive: Bool {
        switch self {
        case .capture, .processing, .stage, .demoRoom: return true
        case .scanSetup, .demoRooms, .scanReview, .fixItPlan,
             .method, .sources, .privacy, .licences: return false
        }
    }

    /// Every destination, one per case.
    ///
    /// Adding a case to `Route` breaks the switches above at compile time and
    /// fails `ShellTests.testRouteDestinationsAreExhaustive` until it is added
    /// here — which is the point.
    static var allDestinations: [Route] {
        [.scanSetup, .demoRooms, .capture, .scanReview, .processing,
         .stage(roomID: UUID()), .demoRoom, .fixItPlan, .method, .sources, .privacy, .licences]
    }
}

// MARK: - Sheets

/// Everything **presented** as a sheet over whatever is on screen.
enum SheetRoute: Hashable, Identifiable, Sendable {
    /// S-04 — account and profile.
    case profile
    /// S-16 — object detail and mitigation, over the spotlit stage.
    case objectDetail(objectID: UUID)
    /// S-21 — the rendered share card and the export options.
    case share(roomID: UUID)

    var id: String {
        switch self {
        case .profile: return "profile"
        case .objectDetail(let objectID): return "object-\(objectID.uuidString)"
        case .share(let roomID): return "share-\(roomID.uuidString)"
        }
    }

    var name: String {
        switch self {
        case .profile: return "profile"
        case .objectDetail: return "object-detail"
        case .share: return "share"
        }
    }

    var specScreen: String {
        switch self {
        case .profile: return "S-04"
        case .objectDetail: return "S-16"
        case .share: return "S-21"
        }
    }

    var title: String {
        switch self {
        case .profile: return "Your account"
        case .objectDetail: return "Object detail"
        case .share: return "Share"
        }
    }

    static var allSheets: [SheetRoute] {
        [.profile, .objectDetail(objectID: UUID()), .share(roomID: UUID())]
    }
}

// MARK: - Full-screen covers

/// The one thing presented as a full-screen cover *after* launch.
///
/// S-05 is a launch phase on a cold start, but it is also raised mid-flow when
/// someone taps "Scan a room" having previously declined the camera. It is a
/// cover rather than a push because it is a decision, not a place: you either
/// grant, or you back out to where you were.
enum CoverRoute: Hashable, Identifiable, Sendable {
    /// S-05 — camera and LiDAR priming.
    case permissionPrimer

    var id: String { name }

    var name: String {
        switch self {
        case .permissionPrimer: return "permission-primer"
        }
    }

    var specScreen: String {
        switch self {
        case .permissionPrimer: return "S-05"
        }
    }

    static var allCovers: [CoverRoute] { [.permissionPrimer] }
}

// MARK: - Launch gate

/// S-01. Where a cold start lands, decided before the first frame the user
/// perceives.
enum LaunchPhase: Hashable, Sendable {
    /// The wordmark and the seismic trace, while the library index loads.
    case launching
    /// A schema migration is taking longer than a beat. Rare.
    case migrating
    /// S-02.
    case onboarding
    /// S-03.
    case signIn
    /// S-05.
    case permissionPrimer
    /// The two-tab shell.
    case ready

    /// True for the states that are still resolving, where no user-facing
    /// decision has been made yet.
    var isResolving: Bool { self == .launching || self == .migrating }

    /// The gate itself, as a pure function of the four things that decide it.
    ///
    /// Order matters and is the order of SPEC §1.3:
    ///
    /// 1. **Onboarding** first, because it is what earns the permission ask.
    /// 2. **Sign in** next. "Signed in" here means *has chosen* — continuing
    ///    without an account is a complete, permanent answer (SPEC §3.5), and a
    ///    user who chose it is never asked again.
    /// 3. **Priming** only if it can still do something: the device can scan,
    ///    the system prompt has never been raised, and we have not already
    ///    primed. A user who declined gets on with the app; a phone with no
    ///    LiDAR is never asked for a camera it will not use.
    /// 4. Otherwise the app.
    static func gate(
        hasCompletedOnboarding: Bool,
        hasChosenAccount: Bool,
        camera: CameraAuthorization,
        hasPrimedCamera: Bool,
        deviceCanScan: Bool
    ) -> LaunchPhase {
        guard hasCompletedOnboarding else { return .onboarding }
        guard hasChosenAccount else { return .signIn }
        if deviceCanScan, camera.canRequest, !hasPrimedCamera { return .permissionPrimer }
        return .ready
    }

    /// The gate, read off the live services.
    @MainActor
    static func gate(for env: TremorEnvironment) -> LaunchPhase {
        gate(
            hasCompletedOnboarding: env.settings.hasCompletedOnboarding,
            hasChosenAccount: env.account.hasChosen,
            camera: env.permissions.camera,
            hasPrimedCamera: env.permissions.hasPrimedCamera,
            deviceCanScan: env.capabilities.supportsRoomScanning)
    }
}

// MARK: - Router

/// All navigation state for the app: which tab, what is pushed on each tab, what
/// is presented over the top, and which launch phase we are in.
///
/// One instance, injected into the SwiftUI environment by `TremorApp`.
@MainActor
@Observable
final class Router {

    // MARK: State

    /// Where a cold start has landed. Owned here because the first-run screens
    /// are navigation, not content.
    var phase: LaunchPhase = .launching

    var tab: TremorTab = .rooms

    /// One stack per tab, so switching tabs preserves where you were — the
    /// behaviour every iOS user already expects.
    var roomsPath: [Route] = []
    var addRoomPath: [Route] = []
    var settingsPath: [Route] = []

    /// Tab **roots** that have gone full-screen.
    ///
    /// `Route.isImmersive` covers the pushed screens, but the Add Room flow is a
    /// state machine living at its tab's root: the camera, the reconstruction
    /// and the 3D room are all the same route. Rather than overlay something on
    /// top of the tab bar and pretend, the flow tells the router when it owns the
    /// display and the tab bar stands down for real — same mechanism, same
    /// `safeAreaInset`, so scroll insets stay honest either way.
    private(set) var immersiveTabRoots: Set<TremorTab> = []

    var sheet: SheetRoute?
    var cover: CoverRoute?

    init() {}

    // MARK: Derived

    /// The active tab's stack.
    var path: [Route] {
        get { path(for: tab) }
        set { setPath(newValue, for: tab) }
    }

    /// The route currently on top of the active tab, or `nil` at a tab root.
    var top: Route? { path.last }

    /// Whether the tab bar should stand down. True over the camera, the
    /// processing screen and the 3D stage — pushed or at a tab root.
    var hidesTabBar: Bool {
        if let top { return top.isImmersive }
        return immersiveTabRoots.contains(tab)
    }

    func path(for tab: TremorTab) -> [Route] {
        switch tab {
        case .rooms: return roomsPath
        case .addRoom: return addRoomPath
        case .settings: return settingsPath
        }
    }

    private func setPath(_ routes: [Route], for tab: TremorTab) {
        switch tab {
        case .rooms: roomsPath = routes
        case .addRoom: addRoomPath = routes
        case .settings: settingsPath = routes
        }
    }

    /// Declared by a tab root that has taken over the whole display, and
    /// withdrawn the moment it hasn't. Idempotent, so a screen can call it from
    /// `onChange` on every step without churning the set.
    func setTabRootImmersive(_ isImmersive: Bool, for tab: TremorTab) {
        if isImmersive {
            immersiveTabRoots.insert(tab)
        } else {
            immersiveTabRoots.remove(tab)
        }
    }

    // MARK: Primitive moves

    func select(_ tab: TremorTab) {
        guard self.tab != tab else {
            // Re-tapping the active tab pops it to its root, as every iOS app
            // has done since 2008.
            popToRoot()
            return
        }
        self.tab = tab
    }

    func push(_ route: Route, on tab: TremorTab? = nil) {
        let target = tab ?? self.tab
        if let tab, tab != self.tab { self.tab = tab }
        setPath(path(for: target) + [route], for: target)
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func popToRoot() {
        guard !path.isEmpty else { return }
        path.removeAll()
    }

    /// Replaces the active tab's stack wholesale.
    ///
    /// This is how the scan flow ends: S-11 finishes and the stack becomes
    /// `[.stage(roomID:)]`, so swiping back from the room viewer goes to the
    /// library and never to a processing screen with nothing left to process.
    func replacePath(with routes: [Route]) {
        path = routes
    }

    func present(_ sheet: SheetRoute) { self.sheet = sheet }
    func dismissSheet() { sheet = nil }

    func present(_ cover: CoverRoute) { self.cover = cover }
    func dismissCover() { cover = nil }

    // MARK: Intents — the vocabulary screens actually use

    /// S-06 hero card. Goes to the demo picker instead when the device cannot
    /// scan, because "Scan a room" must never lead to a dead end (SPEC §1.4
    /// S-08).
    func startScan(deviceCanScan: Bool) {
        select(.rooms)
        replacePath(with: [deviceCanScan ? .scanSetup : .demoRooms])
    }

    /// The Add Room tab, from its root. Anything the tab had pushed is cleared,
    /// because "add a room" is a beginning and must never land mid-flow.
    func openAddRoom() {
        select(.addRoom)
        addRoomPath.removeAll()
    }

    /// S-07 → S-09. The building context is already in `AppState.draft`.
    func beginCapture() { push(.capture) }

    /// S-08. Also reachable from S-07's fourth step and from S-09's error
    /// takeovers.
    func useDemoRoom() { push(.demoRooms) }

    /// S-09 → S-10.
    func reviewScan() { push(.scanReview) }

    /// S-10 → S-11, or S-08 → S-11. Replaces the capture screens so backing out
    /// of processing cannot return to a camera that has been torn down.
    func processScan() { replacePath(with: [.processing]) }

    /// S-11 → S-12, and S-06 → S-12. Ends any scan flow: the stack becomes just
    /// the stage, whose back button goes to the library.
    func openRoom(_ roomID: UUID) {
        select(.rooms)
        replacePath(with: [.stage(roomID: roomID)])
    }

    /// S-15 → S-16.
    func openObject(_ objectID: UUID) { present(.objectDetail(objectID: objectID)) }

    /// S-15/S-16 → S-17.
    func openFixItPlan() { push(.fixItPlan) }

    /// S-15 → S-21.
    func share(roomID: UUID) { present(.share(roomID: roomID)) }

    /// S-19 → S-04.
    func openProfile() { present(.profile) }

    /// Any "?" affordance → S-20.
    func openMethod() { push(.method) }

    /// Abandons a scan and returns to the library. The caller clears the draft.
    func cancelScan() {
        select(.rooms)
        replacePath(with: [])
    }

    // MARK: Launch

    /// Re-reads the gate and moves to whatever it says.
    ///
    /// Every first-run screen calls this when it is done: onboarding after it
    /// sets `hasCompletedOnboarding`, sign-in after it adopts or declines a
    /// credential, priming after the user answers either way. None of them needs
    /// to know what comes next.
    func advanceLaunch(with env: TremorEnvironment) {
        phase = LaunchPhase.gate(for: env)
    }

    /// Used by the cold-start task while the library index loads.
    func setLaunchPhase(_ phase: LaunchPhase) { self.phase = phase }
}
