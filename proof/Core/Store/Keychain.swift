import Foundation
import Security

/// The keys Tremor stores. Centralised so nothing is written under an ad-hoc
/// string that a later delete pass then misses.
public enum SecretKey {
    /// The user's own OpenAI API key, used when cloud object identification is
    /// enabled. Never `UserDefaults`, never a plist, never the app bundle.
    public static let openAIAPIKey = "openai.api-key"
    /// Apple's stable, opaque `user` string from Sign in with Apple.
    public static let appleUserIdentifier = "apple.user-identifier"

    public static let all = [openAIAPIKey, appleUserIdentifier]
}

/// Anything that can hold a secret. A protocol rather than a concrete type for
/// one specific reason: the simulator's keychain is not reliably available to an
/// unsigned test bundle (it answers `errSecMissingEntitlement`), and a store
/// that cannot be faked cannot be tested.
///
/// It refines `OpenAIKeyProviding` (declared by `Core/Understanding`, which must
/// stay buildable with no secret store at all) so that `any SecretStoring` — the
/// static type of `SecretStore.live` — can be handed straight to
/// `OpenAIClassifier`. Conforming the two concrete types separately was not
/// enough: an existential of the base protocol does not carry the refinement,
/// so the shipped app had no way to give the classifier a real key.
public protocol SecretStoring: Sendable, OpenAIKeyProviding {
    func data(for key: String) throws -> Data?
    func set(_ data: Data, for key: String) throws
    func delete(_ key: String) throws
    func removeAll() throws
}

public extension SecretStoring {
    func string(for key: String) throws -> String? {
        guard let data = try data(for: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Setting `nil` or an empty/whitespace-only string deletes the item, so
    /// "clear my API key" is the same call as "set my API key".
    func setString(_ value: String?, for key: String) throws {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            try delete(key)
            return
        }
        try set(Data(value.utf8), for: key)
    }

    func has(_ key: String) -> Bool {
        ((try? data(for: key)) ?? nil) != nil
    }
}

// MARK: - Keychain

public enum KeychainError: LocalizedError, Equatable {
    case status(OSStatus)
    /// The process has no keychain entitlement — a free personal signing profile
    /// or an unhosted test bundle. Callers fall back rather than dying.
    case unavailable

    public var errorDescription: String? {
        switch self {
        case let .status(code):
            return "Keychain error \(code)."
        case .unavailable:
            return "The keychain isn’t available to this build of proof."
        }
    }
}

/// A minimal `kSecClassGenericPassword` wrapper.
///
/// Items are `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: available to
/// background work after the first unlock following a boot, and never copied to
/// a new device by an encrypted backup. An API key is a device-local credential;
/// carrying it to a restored device is a liability, not a feature.
public struct Keychain: SecretStoring {

    public let service: String
    public let accessGroup: String?

    public init(service: String = "com.annenolte.proof", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public static let shared = Keychain()

    private func baseQuery(_ key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    public func data(for key: String) throws -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        case errSecMissingEntitlement, errSecNotAvailable, errSecInteractionNotAllowed:
            throw KeychainError.unavailable
        default:
            throw KeychainError.status(status)
        }
    }

    public func set(_ data: Data, for key: String) throws {
        let query = baseQuery(key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return }
        if update == errSecMissingEntitlement || update == errSecNotAvailable {
            throw KeychainError.unavailable
        }
        guard update == errSecItemNotFound else { throw KeychainError.status(update) }

        var insert = query
        insert.merge(attributes) { _, new in new }
        let add = SecItemAdd(insert as CFDictionary, nil)
        switch add {
        case errSecSuccess, errSecDuplicateItem:
            return
        case errSecMissingEntitlement, errSecNotAvailable:
            throw KeychainError.unavailable
        default:
            throw KeychainError.status(add)
        }
    }

    public func delete(_ key: String) throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        case errSecMissingEntitlement, errSecNotAvailable:
            throw KeychainError.unavailable
        default:
            throw KeychainError.status(status)
        }
    }

    public func removeAll() throws {
        for key in SecretKey.all { try delete(key) }
    }

    /// Whether the keychain answers at all in this process. Used once at launch
    /// so the app can degrade to in-memory secrets instead of throwing on every
    /// read, which matters on a free personal signing profile.
    public func isAvailable() -> Bool {
        do {
            _ = try data(for: "com.annenolte.proof.probe")
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Fallback

/// Process-lifetime secret storage. Used when the keychain is unavailable (free
/// signing profile, unhosted test bundle) and by tests directly. Secrets kept
/// here do not survive relaunch, which is the correct failure mode: the user is
/// asked for the key again rather than the app pretending it saved something.
public final class InMemorySecretStore: SecretStoring, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    public init() {}

    public func data(for key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    public func set(_ data: Data, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = data
    }

    public func delete(_ key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = nil
    }

    public func removeAll() throws {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll()
    }
}

// MARK: - Convenience

public extension SecretStoring {
    /// The OpenAI key, or `nil` if the user has not supplied one.
    var openAIAPIKey: String? {
        get { (try? string(for: SecretKey.openAIAPIKey)) ?? nil }
        nonmutating set { try? setString(newValue, for: SecretKey.openAIAPIKey) }
    }

    var appleUserIdentifier: String? {
        get { (try? string(for: SecretKey.appleUserIdentifier)) ?? nil }
        nonmutating set { try? setString(newValue, for: SecretKey.appleUserIdentifier) }
    }
}

/// Picks the real keychain when the process can use it and falls back to
/// in-memory storage when it cannot, so no call site has to know the difference.
public enum SecretStore {
    public static let live: any SecretStoring = {
        let keychain = Keychain.shared
        return keychain.isAvailable() ? keychain : InMemorySecretStore()
    }()
}

// MARK: - The cloud classifier's key

/// Any secret store is a key provider for `OpenAIClassifier`.
///
/// `Core/Understanding` deliberately declares `OpenAIKeyProviding` rather than
/// depending on the keychain, so that stage stays testable with no secret store
/// at all. This is the one adapter that joins the two — without it the shipped
/// app has no way to hand a real key to the classifier, and the cloud layer
/// silently never engages. There is no second protocol and no second storage
/// path: `SecretKey.openAIAPIKey` remains the only place the key lives, and
/// `SecretStoring` refines `OpenAIKeyProviding` so the existential works too.
extension SecretStoring {
    /// Reading a secret is a keychain round trip, not free; the classifier
    /// calls this once per request on a background actor.
    public func openAIKey() throws -> String? {
        let raw = try string(for: SecretKey.openAIAPIKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty ?? true) ? nil : raw
    }
}
