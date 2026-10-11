//
//  CompositionRoot.swift
//  Tremor — App shell / dependency injection
//
//  SPEC §3.6. One `TremorEnvironment` value, built once, injected through the
//  SwiftUI environment. No singletons reached for from a view, no DI container,
//  no `@EnvironmentObject` graph.
//
//  The rule that makes this work: **a screen never constructs a service.** It
//  reads `@Environment(\.tremor)` and uses what it finds. That is what lets every
//  `#Preview` in the app run against `TremorEnvironment.preview`, which is backed
//  by fixtures in a throwaway temporary directory and never touches the user's
//  real container.
//

import AVFoundation
import Foundation
import Network
import Observation
import SwiftUI

#if canImport(RoomPlan)
import RoomPlan
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Device capabilities

/// What this particular iPhone can do, resolved once at launch.
///
/// `RoomCaptureSession.isSupported` is the single correct gate for scanning — it
/// covers LiDAR, OS version and the Simulator in one call, and a hand-rolled
/// device allow-list would rot within a year. Everything else in the app is
/// available on every supported device.
struct DeviceCapabilities: Hashable, Sendable {

    /// Can this device run a live RoomPlan capture? False on non-Pro iPhones and
    /// in the Simulator, where the demo rooms (S-08) take over.
    var supportsRoomScanning: Bool

    /// True in the Simulator. Kept separate from `supportsRoomScanning` so copy
    /// can distinguish "your phone can't" from "you're on a Mac".
    var isSimulator: Bool

    /// The real answer for the device the app is running on.
    static var current: DeviceCapabilities {
        #if targetEnvironment(simulator)
        return DeviceCapabilities(supportsRoomScanning: false, isSimulator: true)
        #elseif canImport(RoomPlan)
        return DeviceCapabilities(
            supportsRoomScanning: RoomCaptureSession.isSupported, isSimulator: false)
        #else
        return DeviceCapabilities(supportsRoomScanning: false, isSimulator: false)
        #endif
    }

    /// A LiDAR-equipped iPhone. The shape previews and tests assume.
    static let scanCapable = DeviceCapabilities(supportsRoomScanning: true, isSimulator: false)

    /// A device that has to use the demo rooms.
    static let scanIncapable = DeviceCapabilities(supportsRoomScanning: false, isSimulator: false)
}

// MARK: - Camera permission

/// The camera authorisation states the app actually branches on.
///
/// `AVAuthorizationStatus` is mirrored rather than used directly so the launch
/// gate can be driven in a test without a camera, and so `@unknown default`
/// lands in exactly one place.
enum CameraAuthorization: String, Hashable, Sendable, CaseIterable {
    /// The system prompt has never been shown. This is the only state in which
    /// priming (S-05) is worth showing.
    case undetermined
    case granted
    /// The user said no. Recoverable only in iOS Settings.
    case denied
    /// Screen Time or an MDM profile forbids the camera. Not recoverable by the
    /// user, so the copy must not offer a Settings button.
    case restricted

    var allowsCapture: Bool { self == .granted }

    /// True when the system prompt can still be raised. Once it can't, S-05
    /// switches to its "Open Settings" / "Use a demo room" copy.
    var canRequest: Bool { self == .undetermined }
}

/// Owns camera permission state and the one-time record of whether we have
/// already primed for it.
///
/// Priming is remembered because a user who tapped "Not now" must not be shown
/// the same full-screen ask on every cold start — that is nagging, and the app
/// works fine without the camera (demo rooms, saved rooms, reports).
///
/// The system calls are injected so the launch gate is testable: pass a `probe`
/// and a `requester` and the whole permission ladder runs with no camera and no
/// window server.
@MainActor
@Observable
final class PermissionsStore {

    /// One `UserDefaults` key, namespaced like every other Tremor key.
    static let primedKey = "com.annenolte.proof.hasPrimedCamera"

    private(set) var camera: CameraAuthorization
    /// True once the user has seen S-05 and made a choice, either way.
    private(set) var hasPrimedCamera: Bool
    /// True while the system sheet is up, so the CTA can show its spinner.
    private(set) var isRequesting = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let probe: @MainActor () -> CameraAuthorization
    @ObservationIgnored private let requester: @MainActor () async -> CameraAuthorization

    init(
        defaults: UserDefaults = .standard,
        probe: @escaping @MainActor () -> CameraAuthorization = PermissionsStore.systemCameraStatus,
        requester: @escaping @MainActor () async -> CameraAuthorization
            = PermissionsStore.requestSystemCamera
    ) {
        self.defaults = defaults
        self.probe = probe
        self.requester = requester
        self.camera = probe()
        self.hasPrimedCamera = defaults.bool(forKey: Self.primedKey)
    }

    /// Re-reads the system status. Called on every foreground, because the user
    /// can change it in Settings while the app is backgrounded.
    func refresh() {
        camera = probe()
        if camera != .undetermined { markPrimed() }
    }

    /// Raises the system prompt. Returns the resulting status so the caller can
    /// route on it without re-reading.
    @discardableResult
    func requestCameraAccess() async -> CameraAuthorization {
        markPrimed()
        guard camera.canRequest else { return camera }
        isRequesting = true
        let result = await requester()
        isRequesting = false
        camera = result
        return result
    }

    /// Records that the user has seen the ask. Called by S-05's "Not now" too —
    /// declining is a decision, and we honour it.
    func markPrimed() {
        guard !hasPrimedCamera else { return }
        hasPrimedCamera = true
        defaults.set(true, forKey: Self.primedKey)
    }

    /// Opens Tremor's page in iOS Settings, for the `.denied` case.
    func openSystemSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }

    // MARK: System bridges

    static func systemCameraStatus() -> CameraAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: return .undetermined
        case .authorized: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    static func requestSystemCamera() async -> CameraAuthorization {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .granted : .denied
    }

    /// A store that reports whatever you tell it to, for previews and tests.
    static func stub(
        _ status: CameraAuthorization,
        primed: Bool = true,
        grants: CameraAuthorization? = nil
    ) -> PermissionsStore {
        let suite = "com.annenolte.proof.stub.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let store = PermissionsStore(
            defaults: defaults,
            probe: { status },
            requester: { grants ?? status })
        if primed { store.markPrimed() }
        return store
    }
}

// MARK: - Network reachability

/// Whether the device has a usable path to the internet.
///
/// Tremor never blocks on the network — SPEC §1.1 principle 3 — so this drives
/// exactly two things: the quiet global banner in `RootView`, and the copy on
/// the settings row that explains why "smarter object details" is asleep. It is
/// never used to disable a button.
@MainActor
@Observable
final class NetworkMonitor {

    private(set) var isOnline: Bool
    /// Low Data Mode or a personal hotspot. Cloud refinement is skipped here too,
    /// because a 12-image burst on a metered link is not a kindness.
    private(set) var isConstrained: Bool
    /// True until the first path update arrives, so the banner cannot flash
    /// "offline" during the half-second before the monitor has an answer.
    private(set) var hasResolved: Bool

    @ObservationIgnored private let monitor: NWPathMonitor?
    @ObservationIgnored private let queue = DispatchQueue(label: "com.annenolte.proof.network")

    /// - Parameter monitoring: pass `false` for previews and tests, which get a
    ///   fixed answer rather than the host machine's real connectivity.
    init(monitoring: Bool = true, isOnline: Bool = true, isConstrained: Bool = false) {
        self.isOnline = isOnline
        self.isConstrained = isConstrained
        self.hasResolved = !monitoring
        self.monitor = monitoring ? NWPathMonitor() : nil
        start()
    }

    private func start() {
        guard let monitor else { return }
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            let constrained = path.isConstrained || path.isExpensive
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isOnline = online
                self.isConstrained = constrained
                self.hasResolved = true
            }
        }
        monitor.start(queue: queue)
    }

    func stop() { monitor?.cancel() }

    /// Reports a connection and never watches the real one.
    static var connected: NetworkMonitor { NetworkMonitor(monitoring: false, isOnline: true) }
    /// Reports no connection, for previewing the offline banner.
    static var offline: NetworkMonitor { NetworkMonitor(monitoring: false, isOnline: false) }
}

// MARK: - The environment

/// The service bundle every screen reads from.
///
/// Deliberately a `struct` of concrete, already-shipped types rather than a
/// protocol soup: `RoomStore` is an actor, `AppSettings` and `AccountStore` are
/// `@Observable` classes designed to be observed by a view, and inventing
/// protocol wrappers around them would cost the observation that makes the UI
/// update. The two things that genuinely need substituting in a test — the
/// scanner and the permission probe — are injected as closures.
///
/// Not `Sendable`, and it must not become so: it holds `@MainActor` references
/// on purpose. It lives on the main actor, where SwiftUI reads it.
struct TremorEnvironment {

    /// The room library. An `actor`; every call is `await`ed.
    var rooms: RoomStore
    /// Preferences (SPEC §1.4 S-19). `@Observable`, so a view that reads it
    /// updates when it changes.
    var settings: AppSettings
    /// Profile and Sign in with Apple (SPEC §3.5).
    var account: AccountStore
    /// Camera authorisation and the one-time priming record.
    var permissions: PermissionsStore
    /// Connectivity, for the quiet offline banner only.
    var network: NetworkMonitor
    /// The §5 object-understanding pipeline.
    var classifier: any ObjectClassifying
    /// The §4/§6 analytic verdict engine.
    var risk: RiskEngine
    /// What this device can do.
    var capabilities: DeviceCapabilities
    /// True when this environment is the fixture-backed preview one. Screens use
    /// it to skip work that only makes sense against real hardware.
    var isPreview: Bool

    /// Vends a scanner. A factory rather than a stored instance because
    /// `RoomScanning` is `@MainActor` and a scanner owns an `ARSession` — one
    /// per capture, never shared, always torn down.
    ///
    /// The room passed in is the fixture a `ReplayScanner` replays when the
    /// device has no LiDAR; the live scanner ignores it.
    var scannerFactory: @MainActor (ScannedRoom) -> any RoomScanning

    /// Convenience over `scannerFactory` so call sites read as English.
    @MainActor
    func makeScanner(demo room: ScannedRoom = RoomFixtures.dangerousBedroom) -> any RoomScanning {
        scannerFactory(room)
    }

    init(
        rooms: RoomStore,
        settings: AppSettings,
        account: AccountStore,
        permissions: PermissionsStore,
        network: NetworkMonitor,
        classifier: any ObjectClassifying,
        risk: RiskEngine,
        capabilities: DeviceCapabilities,
        isPreview: Bool = false,
        scannerFactory: @escaping @MainActor (ScannedRoom) -> any RoomScanning
    ) {
        self.rooms = rooms
        self.settings = settings
        self.account = account
        self.permissions = permissions
        self.network = network
        self.classifier = classifier
        self.risk = risk
        self.capabilities = capabilities
        self.isPreview = isPreview
        self.scannerFactory = scannerFactory
    }
}

// MARK: Preview environment

extension TremorEnvironment {

    /// The environment every `#Preview` in the app runs against.
    ///
    /// Built once per process, backed by `RoomFixtures`, rooted in a throwaway
    /// directory under `NSTemporaryDirectory()` and a throwaway `UserDefaults`
    /// suite. It can neither read nor write the user's real library, settings,
    /// profile or keychain — which is the whole point, because previews run in
    /// the same simulator as the app.
    @MainActor
    static let preview: TremorEnvironment = makePreview()

    /// A fresh preview environment. Use this rather than `.preview` when a
    /// preview or a test needs its own isolated library.
    @MainActor
    static func makePreview(
        capabilities: DeviceCapabilities = .scanCapable,
        camera: CameraAuthorization = .granted,
        online: Bool = true,
        onboarded: Bool = true,
        signedIn: Bool = true,
        seedsFixtures: Bool = true
    ) -> TremorEnvironment {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TremorPreview-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let suite = "com.annenolte.proof.preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)

        let rooms = RoomStore(root: root)
        let settings = AppSettings(defaults: defaults)
        settings.hasCompletedOnboarding = onboarded

        let account = AccountStore(directory: root, secrets: InMemorySecretStore())
        if signedIn { account.continueWithoutAccount() }

        let permissions = PermissionsStore.stub(camera, primed: camera != .undetermined)

        if seedsFixtures {
            Task { try? await rooms.seedSamplesIfNeeded() }
        }

        return TremorEnvironment(
            rooms: rooms,
            settings: settings,
            account: account,
            permissions: permissions,
            network: online ? .connected : .offline,
            // No vision request, no network client: previews must be instant and
            // deterministic, and the prior alone gives every object a defensible
            // profile (SPEC §5.6.4).
            classifier: ObjectClassifier(),
            // A short ensemble. Twenty realisations is right for a verdict the
            // user reads; six is right for a canvas that redraws as you type.
            risk: RiskEngine(ensembleSize: 6),
            capabilities: capabilities,
            isPreview: true,
            scannerFactory: { room in ReplayScanner(room: room, duration: 6) })
    }
}

// MARK: Environment key

private struct TremorEnvironmentKey: EnvironmentKey {
    // `assumeIsolated` rather than a nonisolated default: the value holds
    // main-actor services, and SwiftUI only ever reads the environment on the
    // main actor. Cached in `TremorEnvironment.preview`, so this builds one
    // fixture library per process, not one per read.
    static var defaultValue: TremorEnvironment {
        MainActor.assumeIsolated { TremorEnvironment.preview }
    }
}

extension EnvironmentValues {
    /// Every Tremor service, in one place.
    ///
    /// ```swift
    /// @Environment(\.tremor) private var tremor
    /// ...
    /// let room = try await tremor.rooms.load(id: roomID)
    /// ```
    ///
    /// Defaults to `TremorEnvironment.preview`, so a view rendered without an
    /// explicit injection — every `#Preview` — still works, against fixtures.
    var tremor: TremorEnvironment {
        get { self[TremorEnvironmentKey.self] }
        set { self[TremorEnvironmentKey.self] = newValue }
    }
}

// MARK: - Composition root

/// Builds the one live environment, once, at launch.
///
/// Nothing else in the app is allowed to call a service's initialiser. If a new
/// service appears, it is constructed here and reaches its screens through
/// `TremorEnvironment`.
@MainActor
enum CompositionRoot {

    /// The real thing: the user's library on disk, their preferences, their
    /// profile, their keychain, the live network monitor, and — on a device that
    /// has LiDAR — a real RoomPlan scanner.
    static func live() -> TremorEnvironment {
        let capabilities = DeviceCapabilities.current

        return TremorEnvironment(
            rooms: RoomStore.shared,
            settings: AppSettings.shared,
            account: AccountStore(),
            permissions: PermissionsStore(),
            network: NetworkMonitor(),
            // The full §5 chain. `OnDeviceVision` runs locally and always; the
            // cloud pass is additionally gated on the user's opt-in at the call
            // site, so constructing it here commits to nothing leaving the phone.
            classifier: ObjectClassifier(vision: OnDeviceVision(), llm: OpenAIClassifier()),
            risk: RiskEngine(),
            capabilities: capabilities,
            isPreview: false,
            // `makeRoomScanner` picks RoomPlan on a capable device and the replay
            // scanner everywhere else, including the Simulator.
            scannerFactory: { room in makeRoomScanner(replaying: room) })
    }
}
