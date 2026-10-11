//
//  PermissionPrimerView.swift
//  Tremor — Features / Onboarding — S-05
//
//  SPEC §1.4 S-05: "Never trigger the system camera prompt cold."
//
//  iOS gives an app exactly one chance to ask for the camera. A user who taps
//  "Don't Allow" on a prompt they did not expect cannot be asked again — the
//  only route back is three levels deep in Settings. So this screen exists to
//  spend a sentence explaining *why* before the one prompt is spent, and to
//  handle, properly, the three ways that can end: granted, denied, and
//  restricted by Screen Time or an MDM profile.
//
//  It is raised in two situations, and `isFirstRun` is the only difference:
//  as a launch phase on a cold start, and as a full-screen cover when someone
//  taps "Scan a room" having previously declined.
//

import SwiftUI

// MARK: - What the screen says

/// The copy and the affordances for one authorisation state, as a value.
///
/// Pulled out of the view so the whole ladder — four states × two entry points —
/// is asserted in `OnboardingScreenTests` without a camera, a window server, or
/// a rendered frame.
struct PermissionPrimerModel: Equatable {

    enum IconTone: Equatable { case brand, warning, blocked, granted }

    var title: String
    var message: String
    var symbolName: String
    var tone: IconTone
    /// `nil` hides the primary pill entirely — the restricted case, where there
    /// is nothing the user can do and offering a button would be a lie.
    var primaryTitle: String?
    var primaryHint: String?
    var secondaryTitle: String
    var secondaryHint: String
    /// Whether to print the three-step route through iOS Settings.
    var showsSettingsSteps: Bool

    static func make(camera: CameraAuthorization, isFirstRun: Bool) -> PermissionPrimerModel {
        switch camera {
        case .undetermined:
            return PermissionPrimerModel(
                title: "proof needs the camera.",
                message: "The camera films a slow walkthrough of your room so proof can rebuild it in 3D and find the objects in it. In this build nothing you film leaves your iPhone.",
                symbolName: "camera.viewfinder",
                tone: .brand,
                primaryTitle: "Allow camera access",
                primaryHint: "Shows the iOS permission prompt",
                secondaryTitle: "Not now",
                secondaryHint: isFirstRun
                    ? "Goes to your rooms. You can turn the camera on later."
                    : "Goes back without filming",
                showsSettingsSteps: false)

        case .denied:
            return PermissionPrimerModel(
                title: "Camera access is off.",
                message: "proof can't film your room without it. Turning it back on takes about ten seconds, and until you do, you can use a walkthrough video instead.",
                symbolName: "exclamationmark.triangle.fill",
                tone: .warning,
                primaryTitle: "Open Settings",
                primaryHint: "Opens proof's page in the iOS Settings app",
                secondaryTitle: "Use a walkthrough video",
                secondaryHint: "Uses a walkthrough video instead of the camera",
                showsSettingsSteps: true)

        case .restricted:
            return PermissionPrimerModel(
                title: "The camera is blocked on this iPhone.",
                message: "Screen Time or a device management profile is switched on and it controls the camera, so this isn't something proof or Settings can change. Whoever manages this iPhone can. In the meantime, you can use a walkthrough video instead.",
                symbolName: "lock.fill",
                tone: .blocked,
                primaryTitle: nil,
                primaryHint: nil,
                secondaryTitle: "Use a walkthrough video",
                secondaryHint: "Uses a walkthrough video instead of the camera",
                showsSettingsSteps: false)

        case .granted:
            return PermissionPrimerModel(
                title: "The camera is on.",
                message: "That's everything proof needs. Filming a room takes about ten seconds: walk a slow lap and keep the camera moving.",
                symbolName: "checkmark.circle.fill",
                tone: .granted,
                primaryTitle: isFirstRun ? "Continue" : "Scan a room",
                primaryHint: isFirstRun ? "Goes to your rooms" : "Starts filming a room",
                secondaryTitle: isFirstRun ? "" : "Not now",
                secondaryHint: "Goes back without filming",
                showsSettingsSteps: false)
        }
    }

    /// The three steps of the route through Settings, written the way the
    /// current iOS labels read.
    static let settingsSteps = [
        "Open the Settings app",
        "Scroll down and tap proof",
        "Turn Camera on",
    ]
}

// MARK: - S-05

struct PermissionPrimerView: View {

    /// True when this is the cold-start gate rather than a mid-flow cover. It
    /// changes only where the screen hands control back to.
    let isFirstRun: Bool

    @Environment(\.tremor) private var tremor
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var camera: CameraAuthorization { tremor.permissions.camera }
    private var model: PermissionPrimerModel {
        PermissionPrimerModel.make(camera: camera, isFirstRun: isFirstRun)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isFirstRun {
                TremorNavBar(
                    title: "",
                    leading: TremorNavBarItem(
                        systemImage: "xmark",
                        label: "Close",
                        hint: "Goes back without filming",
                        action: dismissWithoutGranting))
            }

            // Centred when the card fits, scrollable when the copy grows at an
            // accessibility text size. A `Spacer` inside a `ScrollView` does not
            // expand, so this is the only arrangement that does both.
            GeometryReader { geometry in
                ScrollView {
                    card
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, TremorSpacing.pageInset)
                        .padding(.vertical, TremorSpacing.xl)
                        .frame(minHeight: geometry.size.height, alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            actions
        }
        .tremorScreen(inset: 0)
        .animation(TremorMotion.resolved(TremorMotion.reveal, reduceMotion: reduceMotion),
                   value: camera)
        .onChange(of: scenePhase) { _, phase in
            // The user can flip the switch in Settings while we are backgrounded.
            // Re-reading on every foreground is what turns the "Open Settings"
            // state into the "camera is on" state without a relaunch.
            guard phase == .active else { return }
            tremor.permissions.refresh()
        }
    }

    // MARK: The card

    private var card: some View {
        TremorCard(padding: TremorSpacing.xl, shadow: .card) {
            VStack(spacing: TremorSpacing.md) {
                iconWell

                Text(model.title)
                    .tremorType(.title2)
                    .foregroundStyle(TremorColor.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text(model.message)
                    .tremorType(.callout)
                    .foregroundStyle(TremorColor.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if model.showsSettingsSteps {
                    settingsSteps
                        .padding(.top, TremorSpacing.xs)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var iconWell: some View {
        Image(systemName: model.symbolName)
            .font(.system(size: TremorType.displayM.spec.size, weight: .medium))
            .foregroundStyle(tint(for: model.tone))
            .frame(width: OnboardingMetric.iconWell, height: OnboardingMetric.iconWell)
            .background(fill(for: model.tone), in: Circle())
            .accessibilityHidden(true)
    }

    private func tint(for tone: PermissionPrimerModel.IconTone) -> Color {
        switch tone {
        case .brand: return TremorColor.primary
        case .warning: return TremorColor.warning
        case .blocked: return TremorColor.inkSecondary
        case .granted: return TremorColor.success
        }
    }

    private func fill(for tone: PermissionPrimerModel.IconTone) -> Color {
        switch tone {
        case .brand: return TremorColor.primarySoft
        case .warning: return TremorColor.warning.opacity(0.12)
        case .blocked: return TremorColor.surfaceSunken
        case .granted: return TremorColor.success.opacity(0.12)
        }
    }

    /// The route through Settings, spelled out. A "go to Settings" button with
    /// no instructions strands anyone who has not done it before — iOS drops you
    /// at Tremor's page most of the time, and at the root of Settings the rest.
    private var settingsSteps: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            ForEach(Array(PermissionPrimerModel.settingsSteps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.sm) {
                    Text("\(index + 1)")
                        .tremorType(.captionEmphasis, numeric: true)
                        .foregroundStyle(TremorColor.primary)
                        .frame(width: TremorSpacing.lg, height: TremorSpacing.lg)
                        .background(TremorColor.primarySoft, in: Circle())
                        .accessibilityHidden(true)
                    Text(step)
                        .tremorType(.callout)
                        .foregroundStyle(TremorColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(TremorSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TremorColor.surfaceSunken,
                    in: RoundedRectangle(cornerRadius: TremorRadius.thumbnail, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("How to turn the camera on: "
                            + PermissionPrimerModel.settingsSteps.joined(separator: ", then "))
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: TremorSpacing.xs) {
            if let primaryTitle = model.primaryTitle {
                TremorButton(primaryTitle,
                            isLoading: tremor.permissions.isRequesting,
                            hint: model.primaryHint) {
                    performPrimary()
                }
            }

            if !model.secondaryTitle.isEmpty {
                TremorButton(model.secondaryTitle,
                            variant: .tertiary,
                            size: .medium,
                            hint: model.secondaryHint) {
                    performSecondary()
                }
            }
        }
        .padding(.horizontal, TremorSpacing.pageInset)
        .padding(.top, TremorSpacing.sm)
        .padding(.bottom, TremorSpacing.ctaBottomInset)
        .background(TremorColor.canvas.ignoresSafeArea(edges: .bottom))
    }

    private func performPrimary() {
        switch camera {
        case .undetermined:
            Task {
                await tremor.permissions.requestCameraAccess()
                // On a cold start, whichever way it lands is an answer, and the
                // gate takes it from here. Following a decline with a "go to
                // Settings" screen would be nagging.
                if isFirstRun {
                    finish()
                } else if tremor.permissions.camera == .granted {
                    startScanning()
                }
            }
        case .denied:
            tremor.permissions.openSystemSettings()
        case .granted:
            if isFirstRun { finish() } else { startScanning() }
        case .restricted:
            break
        }
    }

    private func performSecondary() {
        tremor.permissions.markPrimed()
        switch camera {
        case .denied, .restricted:
            useDemoRoom()
        case .undetermined, .granted:
            dismissWithoutGranting()
        }
    }

    // MARK: Exits

    private func finish() {
        tremor.permissions.markPrimed()
        router.advanceLaunch(with: tremor)
    }

    private func dismissWithoutGranting() {
        tremor.permissions.markPrimed()
        if isFirstRun {
            router.advanceLaunch(with: tremor)
        } else {
            router.dismissCover()
        }
    }

    private func startScanning() {
        if isFirstRun {
            router.advanceLaunch(with: tremor)
        } else {
            router.dismissCover()
            router.startScan(deviceCanScan: true)
        }
    }

    /// SPEC S-08: never a dead end. A camera we cannot have is a reason to show
    /// the demo rooms, not a reason to stop.
    private func useDemoRoom() {
        if isFirstRun {
            router.advanceLaunch(with: tremor)
            router.startScan(deviceCanScan: false)
        } else {
            router.dismissCover()
            router.startScan(deviceCanScan: false)
        }
    }
}

// MARK: - Previews

#Preview("S-05 undetermined — first run") {
    PermissionPrimerView(isFirstRun: true)
        .environment(\.tremor, .makePreview(camera: .undetermined, seedsFixtures: false))
        .environment(Router())
}

#Preview("S-05 denied") {
    PermissionPrimerView(isFirstRun: false)
        .environment(\.tremor, .makePreview(camera: .denied, seedsFixtures: false))
        .environment(Router())
}

#Preview("S-05 restricted") {
    PermissionPrimerView(isFirstRun: false)
        .environment(\.tremor, .makePreview(camera: .restricted, seedsFixtures: false))
        .environment(Router())
}

#Preview("S-05 granted") {
    PermissionPrimerView(isFirstRun: false)
        .environment(\.tremor, .makePreview(camera: .granted, seedsFixtures: false))
        .environment(Router())
}

#Preview("S-05 large text") {
    PermissionPrimerView(isFirstRun: true)
        .environment(\.tremor, .makePreview(camera: .undetermined, seedsFixtures: false))
        .environment(Router())
        .environment(\.dynamicTypeSize, .accessibility2)
}
