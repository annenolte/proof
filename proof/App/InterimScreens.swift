//
//  InterimScreens.swift
//  Tremor — App shell / the destination table
//
//  ─────────────────────────────────────────────────────────────────────────────
//  THIS FILE IS THE INTEGRATION POINT, AND MOST OF IT IS TEMPORARY.
//
//  `RouteScreen`, `SheetScreen`, `CoverScreen` and `TabRootScreen` are the four
//  switches that turn a route value into a view. They are permanent. Everything
//  named `Interim*` below is a working stand-in for a screen another team is
//  building right now, and each one is a **one-line swap**:
//
//      case .method:  InterimRouteScreen(route: route)   →   MethodView()
//
//  The stand-ins are deliberately real rather than blank: they navigate, they
//  handle their states, and the first-run ones actually set the flags the launch
//  gate reads — so the shell can be run, tested and demoed end to end today, and
//  so no route is ever a dead end.
//
//  Shell contract for screen teams
//  ───────────────────────────────
//  • The system navigation bar is hidden for every pushed route. Draw your own
//    `TremorNavBar`, and put `router.pop()` behind its leading item. Swipe-back
//    still works.
//  • The tab bar is supplied by the shell and stands down automatically for the
//    immersive routes (`Route.isImmersive`).
//  • Read services from `@Environment(\.tremor)`, navigation from
//    `@Environment(Router.self)`, shared room/scan state from
//    `@Environment(AppState.self)`.
//  ─────────────────────────────────────────────────────────────────────────────
//

import Foundation
import SwiftUI

// MARK: - Tab roots

/// The root of each tab.
struct TabRootScreen: View {
    let tab: TremorTab

    var body: some View {
        Group {
            switch tab {
            case .rooms:    ProofRoomsView()             // S-06, proof
            case .addRoom:  AddRoomView()               // name → capture → build → room
            case .settings: SettingsView()              // S-19
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Pushed destinations

/// Turns a pushed `Route` into its screen.
struct RouteScreen: View {
    let route: Route

    var body: some View {
        Group {
            switch route {
            case .scanSetup:   BuildingContextView()              // S-07
            case .demoRooms:   DemoRoomsView()                    // S-08
            case .capture:     ScanView()                         // S-09
            case .scanReview:  ScanReviewView()                   // S-10
            case .processing:  ProcessingView()                   // S-11
            case .stage(let roomID): StageView(roomID: roomID)     // S-12…S-15
            case .demoRoom:    DemoFlowView()                     // S-22
            case .fixItPlan:   FixItPlanView()                    // S-17
            case .method:      ProofMethodView()                   // How proof works
            case .sources:     SourcesView()                      // S-20 bibliography
            case .privacy:     PrivacyView()                      // S-19 → Privacy
            case .licences:    LicencesView()                     // S-19 → Licences
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Sheets

/// Turns a presented `SheetRoute` into its screen.
struct SheetScreen: View {
    let route: SheetRoute

    var body: some View {
        switch route {
        case .profile:      ProfileSheetView()                    // S-04
        case .objectDetail(let objectID):
            ObjectDetailSheet(objectID: objectID)                 // S-16
        case .share(let roomID):
            ShareSheet(roomID: roomID)                            // S-21
        }
    }
}

// MARK: - Full-screen covers

/// Turns a presented `CoverRoute` into its screen.
struct CoverScreen: View {
    let route: CoverRoute

    var body: some View {
        switch route {
        case .permissionPrimer:
            PermissionPrimerView(isFirstRun: false)               // S-05
        }
    }
}

// MARK: - Shared chrome

/// The standard pushed-screen top bar: a back chevron and the route's title.
///
/// Every stand-in uses it, and it is the shape a real screen should keep.
private struct BackBar: View {
    let title: String
    @Environment(Router.self) private var router

    var body: some View {
        TremorNavBar(
            title: title,
            leading: TremorNavBarItem(
                systemImage: "chevron.left",
                label: "Back",
                action: { router.pop() }))
    }
}

// MARK: - Interim: library (S-06)

/// A working room library: the scan action, the saved rooms, and every state a
/// list can be in. The real S-06 replaces it with the hero card, the isometric
/// thumbnails and swipe-to-delete.
struct InterimLibraryScreen: View {

    private enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    @Environment(\.tremor) private var tremor
    @Environment(Router.self) private var router
    @Environment(AppState.self) private var appState

    @State private var phase: Phase = .loading
    @State private var rooms: [RoomSummary] = []

    var body: some View {
        VStack(spacing: 0) {
            TremorNavBar(title: "Rooms")

            ScrollView {
                VStack(alignment: .leading, spacing: TremorSpacing.md) {
                    scanAction

                    switch phase {
                    case .loading:
                        TremorSectionHeader("Your rooms")
                        TremorProgressBar(value: nil, label: "Opening your library")
                            .padding(.vertical, TremorSpacing.md)

                    case .failed(let message):
                        TremorEmptyState(
                            title: "Couldn't open your library",
                            message: message,
                            systemImage: "exclamationmark.triangle",
                            actionTitle: "Try again",
                            action: { Task { await load() } })

                    case .loaded where rooms.isEmpty:
                        TremorEmptyState(
                            title: "No rooms yet",
                            message: "Scan the room you sleep in first. That's where most earthquake injuries happen.",
                            systemImage: "bed.double")

                    case .loaded:
                        TremorSectionHeader("Your rooms")
                        ForEach(rooms) { room in
                            TremorListRow(
                                title: room.name,
                                subtitle: subtitle(for: room),
                                leading: .iconWell(room.kind.symbolName),
                                accessory: accessory(for: room),
                                accessibilityHint: "Opens this room in 3D",
                                action: { open(room) })
                            TremorRowDivider()
                        }
                    }
                }
                .padding(.vertical, TremorSpacing.md)
            }
        }
        .tremorScreen(inset: TremorSpacing.md)
        .task { await load() }
    }

    private var scanAction: some View {
        TremorListRow(
            title: tremor.capabilities.supportsRoomScanning ? "Scan a room" : "Try a demo room",
            subtitle: tremor.capabilities.supportsRoomScanning
                ? "About 3 minutes"
                : "This iPhone has no LiDAR scanner, so start with a room we prepared",
            leading: .iconWell("viewfinder"),
            accessory: .chevron,
            action: {
                appState.beginScan(isDemo: !tremor.capabilities.supportsRoomScanning)
                router.startScan(deviceCanScan: tremor.capabilities.supportsRoomScanning)
            })
        .background(TremorColor.surface, in: RoundedRectangle(
            cornerRadius: TremorRadius.card, style: .continuous))
        .tremorShadow(.card)
    }

    private func subtitle(for room: RoomSummary) -> String {
        if room.isDamaged { return "This room's data is damaged" }
        let objects = room.objectCount == 1 ? "1 object" : "\(room.objectCount) objects"
        return "\(objects) · \(Self.dateFormatter.string(from: room.updatedAt))"
    }

    private func accessory(for room: RoomSummary) -> TremorRowAccessory {
        guard let assessment = room.latestAssessment else { return .chevron }
        return .custom(AnyView(RiskBadge(assessment.band)))
    }

    private func open(_ room: RoomSummary) {
        appState.openRoom(id: room.id)
        router.openRoom(room.id)
    }

    private func load() async {
        phase = .loading
        do {
            rooms = try await tremor.rooms.list()
            phase = .loaded
        } catch {
            phase = .failed(AppState.message(for: error))
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()
}

#Preview("Interim library") {
    RootPreviewHost(env: .makePreview(), phase: .ready)
}

// MARK: - Interim: settings (S-19)

/// The settings root, wired to the routes it owns so the Settings tab is
/// navigable today.
struct InterimSettingsScreen: View {

    @Environment(\.tremor) private var tremor
    @Environment(Router.self) private var router

    var body: some View {
        VStack(spacing: 0) {
            TremorNavBar(title: "Settings")

            ScrollView {
                VStack(alignment: .leading, spacing: TremorSpacing.md) {
                    TremorSectionHeader("Account")
                    TremorListRow(
                        title: tremor.account.profile?.displayTitle ?? "Set up your profile",
                        subtitle: tremor.account.isSignedIn
                            ? "Signed in with Apple"
                            : "Local profile — everything works the same",
                        leading: .iconWell("person.crop.circle"),
                        accessory: .chevron,
                        action: { router.openProfile() })

                    TremorSectionHeader("About")
                    TremorListRow(title: "How proof works", leading: .iconWell("function"),
                                 accessory: .chevron, action: { router.push(.method) })
                    TremorRowDivider()
                    TremorListRow(title: "Sources and citations", leading: .iconWell("book"),
                                 accessory: .chevron, action: { router.push(.sources) })
                    TremorRowDivider()
                    TremorListRow(title: "Privacy", leading: .iconWell("hand.raised"),
                                 accessory: .chevron, action: { router.push(.privacy) })
                    TremorRowDivider()
                    TremorListRow(title: "Licences", leading: .iconWell("doc.text"),
                                 accessory: .chevron, action: { router.push(.licences) })

                    Text(Self.versionLine)
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, TremorSpacing.xl)
                }
                .padding(.vertical, TremorSpacing.md)
            }
        }
        .tremorScreen(inset: TremorSpacing.md)
    }

    private static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "proof \(version) (\(build))"
    }
}

#Preview("Interim settings") {
    RootPreviewHost(env: .makePreview(), phase: .ready, tab: .settings)
}

// MARK: - Interim: pushed routes

/// The stand-in for a pushed screen that has not landed yet. Never a dead end:
/// it names the screen, says plainly that it is on its way, and offers the way
/// back.
struct InterimRouteScreen: View {

    let route: Route

    @Environment(Router.self) private var router

    var body: some View {
        VStack(spacing: 0) {
            BackBar(title: route.title.isEmpty ? "proof" : route.title)
            Spacer(minLength: 0)
            TremorEmptyState(
                title: Self.headline(for: route),
                message: "This part of proof is still being built. Everything around it — your rooms, the earthquake and the report — is already here.",
                systemImage: Self.symbol(for: route),
                actionTitle: "Go back",
                actionHint: "Returns to the previous screen",
                action: { router.pop() })
            Spacer(minLength: 0)
        }
        .tremorScreen(inset: 0)
    }

    private static func headline(for route: Route) -> String {
        switch route {
        case .scanSetup:  return "A few questions first"
        case .demoRooms:  return "Demo rooms"
        case .capture:    return "Scanning"
        case .scanReview: return "Scan review"
        case .processing: return "Building your report"
        case .stage:      return "Your room in 3D"
        case .demoRoom:   return "Demo apartment"
        case .fixItPlan:  return "Your fix-it plan"
        case .method:     return "How proof works"
        case .sources:    return "Sources and citations"
        case .privacy:    return "Privacy"
        case .licences:   return "Licences"
        }
    }

    private static func symbol(for route: Route) -> String {
        switch route {
        case .scanSetup:  return "list.bullet.clipboard"
        case .demoRooms:  return "square.stack.3d.up"
        case .capture:    return "camera.viewfinder"
        case .scanReview: return "checklist"
        case .processing: return "gearshape.2"
        case .stage:      return "cube.transparent"
        case .demoRoom:   return "house.and.flag"
        case .fixItPlan:  return "wrench.and.screwdriver"
        case .method:     return "function"
        case .sources:    return "book"
        case .privacy:    return "hand.raised"
        case .licences:   return "doc.text"
        }
    }
}

#Preview("Interim route") {
    RootPreviewHost(env: .makePreview(), phase: .ready, path: [.method])
}

// MARK: - Interim: sheets

/// The stand-in for a presented sheet.
struct InterimSheetScreen: View {

    let route: SheetRoute

    @Environment(Router.self) private var router

    var body: some View {
        VStack(spacing: 0) {
            TremorNavBar(
                title: route.title,
                trailing: TremorNavBarItem(
                    systemImage: "xmark",
                    label: "Close",
                    action: { router.dismissSheet() }))
            Spacer(minLength: 0)
            TremorEmptyState(
                title: route.title,
                message: "This sheet is still being built. Close it to carry on — nothing here is needed to use the rest of proof.",
                systemImage: "rectangle.portrait.on.rectangle.portrait",
                actionTitle: "Close",
                action: { router.dismissSheet() })
            Spacer(minLength: 0)
        }
        .tremorScreen(inset: 0)
    }
}

#Preview("Interim sheet") {
    InterimSheetScreen(route: .profile)
        .environment(Router())
}

// MARK: - Interim: onboarding (S-02)

/// The stand-in for the three-page carousel. It does the one thing the launch
/// gate depends on: records that onboarding is done, then re-asks the gate.
struct InterimOnboardingScreen: View {

    @Environment(\.tremor) private var tremor
    @Environment(Router.self) private var router

    var body: some View {
        ZStack {
            TremorColor.ink.ignoresSafeArea()

            VStack(alignment: .leading, spacing: TremorSpacing.md) {
                Spacer(minLength: 0)

                Text("Your room.\nYour earthquake.")
                    .tremorType(.displayL)
                    .foregroundStyle(TremorColor.primarySoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("proof scans your actual room, shakes it with a real ground motion, and tells you exactly what would fall — and how to fix it.")
                    .tremorType(.body)
                    .foregroundStyle(TremorColor.inkInverse.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                TremorButton("Get started", variant: .accent) {
                    tremor.settings.hasCompletedOnboarding = true
                    router.advanceLaunch(with: tremor)
                }
            }
            .padding(.horizontal, TremorSpacing.pageInset)
            .padding(.vertical, TremorSpacing.section)
        }
    }
}

#Preview("Interim onboarding") {
    InterimOnboardingScreen()
        .environment(\.tremor, .makePreview(onboarded: false, signedIn: false))
        .environment(Router())
}

// MARK: - Interim: sign in (S-03)

/// The stand-in for Sign in with Apple. It offers the path that always works —
/// a local profile — and never blocks the user behind an account, because
/// nothing in Tremor lives on a server.
struct InterimSignInScreen: View {

    @Environment(\.tremor) private var tremor
    @Environment(Router.self) private var router
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            TremorColor.ink.ignoresSafeArea()

            VStack(alignment: .leading, spacing: TremorSpacing.md) {
                Spacer(minLength: 0)

                Text("Save your rooms.")
                    .tremorType(.displayM)
                    .foregroundStyle(TremorColor.primarySoft)
                    .accessibilityAddTraits(.isHeader)

                Text("An account keeps your scans, reports and fix-it plans across devices. We never see your room — it stays on your iPhone.")
                    .tremorType(.body)
                    .foregroundStyle(TremorColor.inkInverse.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                if let errorMessage {
                    Text(errorMessage)
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.riskSevereSurface)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if tremor.account.isSignInWithAppleAvailable {
                    TremorButton("Continue with Apple", variant: .accent, isLoading: isWorking) {
                        Task { await signIn() }
                    }
                }

                TremorButton("Continue without an account", variant: .tertiary) {
                    tremor.account.continueWithoutAccount()
                    router.advanceLaunch(with: tremor)
                }
                .foregroundStyle(TremorColor.primarySoft)
            }
            .padding(.horizontal, TremorSpacing.pageInset)
            .padding(.vertical, TremorSpacing.section)
        }
    }

    private func signIn() async {
        isWorking = true
        errorMessage = nil
        do {
            _ = try await tremor.account.signInWithApple()
            router.advanceLaunch(with: tremor)
        } catch let error as AccountError {
            // A cancellation is a decision, not a failure. Say nothing.
            if case .cancelled = error {} else { errorMessage = error.errorDescription }
        } catch {
            errorMessage = "Couldn't sign in. Try again."
        }
        isWorking = false
    }
}

#Preview("Interim sign in") {
    InterimSignInScreen()
        .environment(\.tremor, .makePreview(signedIn: false))
        .environment(Router())
}

// MARK: - Interim: permission priming (S-05)

/// The stand-in for S-05. It handles all three authorisation states the spec
/// calls for, because a primer that only knows `undetermined` strands anyone who
/// has ever said no.
struct InterimPermissionScreen: View {

    /// True when this is the cold-start gate rather than a mid-flow cover, which
    /// changes only what "Not now" does.
    let isFirstRun: Bool

    @Environment(\.tremor) private var tremor
    @Environment(Router.self) private var router

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            TremorEmptyState(
                title: title,
                message: message,
                systemImage: "camera.viewfinder")

            Spacer(minLength: 0)

            VStack(spacing: TremorSpacing.sm) {
                switch tremor.permissions.camera {
                case .undetermined:
                    TremorButton("Allow camera access",
                                isLoading: tremor.permissions.isRequesting) {
                        Task {
                            await tremor.permissions.requestCameraAccess()
                            finish()
                        }
                    }
                case .denied:
                    TremorButton("Open Settings") { tremor.permissions.openSystemSettings() }
                case .granted, .restricted:
                    EmptyView()
                }

                TremorButton(secondaryTitle, variant: .tertiary) {
                    tremor.permissions.markPrimed()
                    if isFirstRun {
                        finish()
                    } else {
                        router.dismissCover()
                        router.startScan(deviceCanScan: false)
                    }
                }
            }
            .padding(.horizontal, TremorSpacing.pageInset)
            .padding(.bottom, TremorSpacing.ctaBottomInset)
        }
        .tremorScreen(inset: 0)
    }

    private var title: String {
        switch tremor.permissions.camera {
        case .undetermined, .granted: return "proof needs the camera"
        case .denied: return "Camera access is off"
        case .restricted: return "The camera is restricted"
        }
    }

    private var message: String {
        switch tremor.permissions.camera {
        case .undetermined, .granted:
            return "The camera and LiDAR scanner measure the shape of your room and the size of everything in it. Frames are processed on your iPhone. Nothing is recorded or uploaded."
        case .denied:
            return "Turn the camera on in Settings to scan your own room. Until then you can explore a demo room — everything after the scan is identical."
        case .restricted:
            return "Screen Time or a device profile is blocking the camera on this iPhone. You can still explore a demo room — everything after the scan is identical."
        }
    }

    private var secondaryTitle: String {
        switch tremor.permissions.camera {
        case .undetermined, .granted: return "Not now"
        case .denied, .restricted: return "Use a demo room"
        }
    }

    private func finish() {
        if isFirstRun {
            router.advanceLaunch(with: tremor)
        } else {
            router.dismissCover()
        }
    }
}

#Preview("S-05 undetermined") {
    InterimPermissionScreen(isFirstRun: true)
        .environment(\.tremor, .makePreview(camera: .undetermined))
        .environment(Router())
}

#Preview("S-05 denied") {
    InterimPermissionScreen(isFirstRun: false)
        .environment(\.tremor, .makePreview(camera: .denied))
        .environment(Router())
}

#Preview("S-05 restricted") {
    InterimPermissionScreen(isFirstRun: false)
        .environment(\.tremor, .makePreview(camera: .restricted))
        .environment(Router())
}
