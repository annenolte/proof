import Foundation
import Observation
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Profile

/// The local profile. Tremor keeps no server-side user record, so this *is* the
/// account: a display name, whatever contact address Apple relayed, and the
/// defaults a returning user should not have to retype.
public struct Profile: Codable, Hashable, Sendable {

    /// How the profile came to exist. `anonymous` is a first-class state, not a
    /// degraded one — the entire app works in it.
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case anonymous, apple
    }

    public var kind: Kind
    public var displayName: String?
    /// Apple's private relay address, or whatever the user typed. Optional
    /// because Sign in with Apple only hands over an email on the *first*
    /// authorisation, and only if the user allows it.
    public var email: String?
    public var createdAt: Date
    /// Defaults applied to a new scan, so someone on the third floor of a soft-
    /// soil apartment block sets it once rather than per room.
    public var homeBuilding: BuildingContext

    public init(
        kind: Kind = .anonymous,
        displayName: String? = nil,
        email: String? = nil,
        createdAt: Date = Date(),
        homeBuilding: BuildingContext = BuildingContext()
    ) {
        self.kind = kind
        self.displayName = displayName
        self.email = email
        self.createdAt = createdAt
        self.homeBuilding = homeBuilding
    }

    /// One or two letters for the avatar circle. Falls back to a neutral glyph
    /// rather than to a random letter, because a wrong initial reads as someone
    /// else's account.
    public var avatarInitials: String {
        let source = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? email?.split(separator: "@").first.map(String.init)
            ?? ""
        let words = source.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "-" })
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return "·" }
        if words.count == 1 {
            return String(words[0].prefix(1)).uppercased()
        }
        return (String(words[0].prefix(1)) + String(words[words.count - 1].prefix(1))).uppercased()
    }

    /// What the profile row says when there is no name.
    public var displayTitle: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let email, !email.isEmpty { return email }
        return kind == .apple ? "Apple ID" : "Local profile"
    }

    /// Decoded permissively so a profile written by an older build survives the
    /// addition of any field.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .anonymous
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        homeBuilding = try c.decodeIfPresent(BuildingContext.self, forKey: .homeBuilding) ?? BuildingContext()
    }
}

// MARK: - Credential

/// The parts of an Apple authorisation Tremor actually uses. Modelled separately
/// from `ASAuthorizationAppleIDCredential` so the sign-in logic can be driven in
/// a test without a window server.
public struct AppleCredential: Hashable, Sendable {
    public let userIdentifier: String
    public let fullName: String?
    public let email: String?

    public init(userIdentifier: String, fullName: String? = nil, email: String? = nil) {
        self.userIdentifier = userIdentifier
        self.fullName = fullName
        self.email = email
    }
}

public enum AccountError: LocalizedError, Equatable {
    /// The user dismissed the Apple sheet. Not an error worth showing.
    case cancelled
    /// The Sign in with Apple entitlement is missing — a free personal signing
    /// profile. The app must fall back to the local profile, not dead-end.
    case signInWithAppleUnavailable
    case authorizationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return nil
        case .signInWithAppleUnavailable:
            return "Sign in with Apple isn’t available in this build. You can keep using proof with a local profile — everything works the same."
        case let .authorizationFailed(reason):
            return "Sign in didn’t complete. \(reason)"
        }
    }
}

// MARK: - Store

/// Owns the profile and, when there is one, the Apple credential.
///
/// Two rules shape this type, and both are deliberate:
///
/// 1. **Signing in is optional.** `Profile.Kind.anonymous` is a real account
///    state. Nothing in the app is gated on `kind == .apple`, because Tremor
///    stores no server data — gating features on a sign-in that buys the user
///    nothing would be a dark pattern.
/// 2. **A missing entitlement must not dead-end.** Sign in with Apple needs a
///    paid developer account. When the entitlement is absent the authorisation
///    fails with an opaque error; we detect that, latch
///    `isSignInWithAppleAvailable = false`, and fall through to the local path.
@Observable
@MainActor
public final class AccountStore {

    // MARK: State

    /// `nil` until the user has made a choice (sign in, or continue without).
    /// The launch gate uses exactly this to decide whether to show S-03.
    public private(set) var profile: Profile?

    /// Apple's opaque user string for the signed-in account, mirrored from the
    /// keychain so the UI does not have to hit the keychain to render.
    public private(set) var appleUserIdentifier: String?

    /// False once an authorisation has failed in a way that means the
    /// entitlement is missing. Drives hiding the Apple button entirely rather
    /// than offering a button that cannot work.
    public private(set) var isSignInWithAppleAvailable: Bool = true

    /// Set when a launch-time revalidation found the credential revoked. The UI
    /// shows one non-blocking toast and clears it.
    public var credentialWasRevoked: Bool = false

    public var isSignedIn: Bool { profile?.kind == .apple }
    public var hasChosen: Bool { profile != nil }

    // MARK: Dependencies

    @ObservationIgnored private let secrets: any SecretStoring
    @ObservationIgnored private let profileURL: URL
    @ObservationIgnored private let encoder: JSONEncoder
    @ObservationIgnored private let decoder: JSONDecoder
    @ObservationIgnored private var revocationObserver: (any NSObjectProtocol)?

    public init(
        directory: URL = RoomStore.defaultRoot(),
        secrets: any SecretStoring = SecretStore.live
    ) {
        self.profileURL = directory.appendingPathComponent("Profile.json")
        self.secrets = secrets

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        self.encoder = encoder
        self.decoder = JSONDecoder()

        self.profile = Self.readProfile(at: profileURL, using: decoder)
        self.appleUserIdentifier = secrets.appleUserIdentifier

        observeRevocation()
    }

    /// Latches the Apple button off for the rest of the session. Called when an
    /// authorisation fails in the way a missing entitlement fails, and available
    /// to the composition root so a build that is known to be unsigned can hide
    /// the button before the user ever taps it.
    public func markSignInWithAppleUnavailable() {
        isSignInWithAppleAvailable = false
    }

    /// Detaches the revocation observer. Not done in `deinit`: the store lives
    /// for the whole process, and a `deinit` touching main-actor state is a
    /// concurrency hazard for a saving of nothing.
    public func stopObserving() {
        if let revocationObserver {
            NotificationCenter.default.removeObserver(revocationObserver)
            self.revocationObserver = nil
        }
    }

    // MARK: Sign in

    #if canImport(AuthenticationServices) && canImport(UIKit)
    /// Presents the system sheet and adopts the result.
    ///
    /// Throws `.signInWithAppleUnavailable` rather than a raw
    /// `ASAuthorizationError` when the entitlement is missing, so the caller's
    /// only correct response — offer the local profile instead — is obvious.
    @discardableResult
    public func signInWithApple() async throws -> Profile {
        guard isSignInWithAppleAvailable else {
            throw AccountError.signInWithAppleUnavailable
        }
        do {
            let credential = try await AppleSignInController.authorize()
            return adopt(credential)
        } catch let error as AccountError {
            if case .signInWithAppleUnavailable = error {
                isSignInWithAppleAvailable = false
            }
            throw error
        }
    }
    #endif

    /// Adopts an Apple credential. Separated from the UI so the whole
    /// state-transition can be tested.
    ///
    /// Apple hands over the name and email **only on the first authorisation**
    /// for an app. On every later sign-in they are nil, so an existing profile's
    /// values are kept rather than blanked.
    @discardableResult
    public func adopt(_ credential: AppleCredential) -> Profile {
        var updated = profile ?? Profile(kind: .apple)
        updated.kind = .apple
        if let name = credential.fullName, !name.isEmpty { updated.displayName = name }
        if let email = credential.email, !email.isEmpty { updated.email = email }

        appleUserIdentifier = credential.userIdentifier
        secrets.appleUserIdentifier = credential.userIdentifier

        profile = updated
        persist()
        return updated
    }

    /// The "Continue without an account" path. Creates a local profile, which is
    /// a complete and permanent state — nothing later nags the user to upgrade.
    @discardableResult
    public func continueWithoutAccount() -> Profile {
        if let existing = profile, existing.kind == .anonymous { return existing }
        let created = Profile(kind: .anonymous, createdAt: profile?.createdAt ?? Date())
        profile = created
        persist()
        return created
    }

    // MARK: Sign out / delete

    /// Drops the Apple credential and keeps everything else. Rooms are local and
    /// are not touched: they were never tied to the account.
    public func signOut() {
        secrets.appleUserIdentifier = nil
        appleUserIdentifier = nil
        guard var updated = profile else { return }
        updated.kind = .anonymous
        updated.email = nil
        profile = updated
        persist()
    }

    /// Erases the profile and every stored secret.
    ///
    /// - Parameter rooms: pass the library to erase the user's scans as well.
    ///   Left `nil` by default: a "delete account" that silently destroyed
    ///   unrelated local documents would be a nasty surprise, so the caller has
    ///   to ask for it after telling the user.
    public func deleteAccount(alsoErasing rooms: RoomStore? = nil) async {
        try? secrets.removeAll()
        appleUserIdentifier = nil
        profile = nil
        try? FileManager.default.removeItem(at: profileURL)

        if let rooms {
            for summary in (try? await rooms.list()) ?? [] {
                try? await rooms.delete(id: summary.id)
            }
        }
    }

    // MARK: Mutation

    public func update(_ mutate: (inout Profile) -> Void) {
        guard var current = profile else { return }
        mutate(&current)
        profile = current
        persist()
    }

    public func setDisplayName(_ name: String?) {
        update { $0.displayName = name?.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    public func setHomeBuilding(_ context: BuildingContext) {
        update { $0.homeBuilding = context }
    }

    // MARK: Revalidation

    /// Re-checks the Apple credential on launch and on every foreground.
    ///
    /// A user can revoke Tremor from Settings → Apple ID → Password & Security at
    /// any time; the app finds out only by asking. `.revoked` and `.notFound`
    /// both downgrade to a local profile and raise a one-shot flag for a
    /// non-blocking toast. The user is never signed out of the *app* — there is
    /// nothing to be signed out of.
    public func revalidate() async {
        guard let identifier = appleUserIdentifier, profile?.kind == .apple else { return }

        #if canImport(AuthenticationServices)
        let provider = ASAuthorizationAppleIDProvider()
        let state: ASAuthorizationAppleIDProvider.CredentialState
        do {
            state = try await provider.credentialState(forUserID: identifier)
        } catch {
            // Network or entitlement trouble. Do not punish the user for it —
            // the local profile keeps working and we retry next foreground.
            return
        }

        switch state {
        case .authorized:
            return
        case .revoked, .notFound:
            credentialWasRevoked = true
            signOut()
        case .transferred:
            // The app moved to a different developer account. Treat as still
            // valid; Apple migrates the identifier on the next authorisation.
            return
        @unknown default:
            return
        }
        #endif
    }

    private func observeRevocation() {
        #if canImport(AuthenticationServices)
        revocationObserver = NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.credentialWasRevoked = true
                self.signOut()
            }
        }
        #endif
    }

    // MARK: Persistence

    private func persist() {
        guard let profile else { return }
        guard let data = try? encoder.encode(profile) else { return }
        try? AtomicFile.write(data, to: profileURL)
    }

    private static func readProfile(at url: URL, using decoder: JSONDecoder) -> Profile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(Profile.self, from: data)
    }
}

// MARK: - Apple sign-in plumbing

#if canImport(AuthenticationServices) && canImport(UIKit)

/// Bridges `ASAuthorizationController`'s delegate callbacks to `async`.
///
/// Held alive for the duration of the request by `retained`: the system keeps
/// only a weak reference to the delegate, and a controller whose delegate has
/// been deallocated silently never calls back.
@MainActor
final class AppleSignInController: NSObject,
                                   ASAuthorizationControllerDelegate,
                                   ASAuthorizationControllerPresentationContextProviding {

    private var continuation: CheckedContinuation<AppleCredential, Error>?
    private static var retained: AppleSignInController?

    static func authorize() async throws -> AppleCredential {
        let controller = AppleSignInController()
        retained = controller
        defer { retained = nil }
        return try await controller.start()
    }

    private func start() async throws -> AppleCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<AppleCredential, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finish(.failure(AccountError.authorizationFailed("Unexpected credential type.")))
            return
        }

        var name: String?
        if let components = credential.fullName {
            let formatter = PersonNameComponentsFormatter()
            formatter.style = .default
            let formatted = formatter.string(from: components).trimmingCharacters(in: .whitespaces)
            name = formatted.isEmpty ? nil : formatted
        }

        finish(.success(AppleCredential(
            userIdentifier: credential.user,
            fullName: name,
            email: credential.email
        )))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        finish(.failure(Self.translate(error)))
    }

    /// Maps Apple's errors onto the two outcomes the UI cares about.
    ///
    /// A build signed with a free personal profile has no Sign in with Apple
    /// entitlement. The authorisation then fails immediately with
    /// `ASAuthorizationError.unknown` (1000) — the same code used for several
    /// unrelated failures, so this is a heuristic and is treated as such: it
    /// only ever *hides* the Apple button and routes the user to the local
    /// profile, which is a working path either way.
    static func translate(_ error: Error) -> AccountError {
        guard let authError = error as? ASAuthorizationError else {
            return .authorizationFailed(error.localizedDescription)
        }
        switch authError.code {
        case .canceled:
            return .cancelled
        case .unknown, .notInteractive:
            return .signInWithAppleUnavailable
        default:
            // Covers `.failed`, `.invalidResponse`, `.notHandled` and every case
            // Apple adds later. A plain `default` rather than `@unknown default`
            // because the SDK keeps growing this enum and a new case must not
            // become a build break in an unrelated release.
            return .authorizationFailed(authError.localizedDescription)
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let window = scenes
            .first(where: { $0.activationState == .foregroundActive })?
            .keyWindow
            ?? scenes.first?.windows.first
        return window ?? UIWindow()
    }
}

#endif
