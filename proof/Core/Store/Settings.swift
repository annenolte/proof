import Foundation
import Observation

/// Metric or imperial. The app is **metric internally, everywhere** — every
/// length is a metre and every mass a kilogram in the model, the physics and the
/// stored file. This preference only ever changes the string a user reads.
public enum UnitSystem: String, Codable, CaseIterable, Sendable, Identifiable {
    case metric, imperial

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .metric: return "Metric"
        case .imperial: return "Imperial"
        }
    }

    /// The unit suffix a length is shown with.
    public var lengthSuffix: String { self == .metric ? "m" : "ft" }
    public var massSuffix: String { self == .metric ? "kg" : "lb" }
}

/// Display-side conversion. Kept next to the preference so there is exactly one
/// place in the app that knows the conversion factors, and no call site is ever
/// tempted to store a converted number back into the model.
public enum UnitFormatter {
    public static func length(_ metres: Double, in system: UnitSystem, decimals: Int = 2) -> String {
        switch system {
        case .metric:
            return "\(rounded(metres, decimals)) m"
        case .imperial:
            let feet = metres * 3.280_839_895
            return "\(rounded(feet, decimals)) ft"
        }
    }

    public static func mass(_ kilograms: Double, in system: UnitSystem, decimals: Int = 0) -> String {
        switch system {
        case .metric:
            return "\(rounded(kilograms, decimals)) kg"
        case .imperial:
            let pounds = kilograms * 2.204_622_622
            return "\(rounded(pounds, decimals)) lb"
        }
    }

    /// Height above the floor, where imperial readers expect feet *and* inches.
    public static func height(_ metres: Double, in system: UnitSystem) -> String {
        switch system {
        case .metric:
            return "\(rounded(metres, 2)) m"
        case .imperial:
            let totalInches = metres * 39.370_078_74
            let feet = Int(totalInches / 12)
            let inches = Int((totalInches - Double(feet) * 12).rounded())
            return inches == 12 ? "\(feet + 1)′ 0″" : "\(feet)′ \(inches)″"
        }
    }

    private static func rounded(_ value: Double, _ decimals: Int) -> String {
        let factor = pow(10.0, Double(decimals))
        let r = (value * factor).rounded() / factor
        return decimals == 0 ? String(Int(r)) : String(format: "%.\(decimals)f", r)
    }
}

// MARK: - Values

/// The whole preference set as one `Codable` value.
///
/// Storing a struct rather than a scatter of `UserDefaults` keys means the
/// defaults, the persistence and the reset path are each written once, and a new
/// preference is a single line here rather than four lines in three places.
public struct SettingsValues: Codable, Hashable, Sendable {
    public var defaultIntensity: MercalliIntensity
    public var defaultSoil: SoilClass
    public var units: UnitSystem
    /// Sending object crops to a cloud vision-language model for identification.
    /// **Off by default and opt-in**, because it leaves the device.
    public var cloudIdentificationEnabled: Bool
    /// When the user turned cloud identification on, kept so the consent is
    /// auditable rather than implicit.
    public var cloudConsentRecordedAt: Date?
    public var hapticsEnabled: Bool
    /// User override for reduced motion, on top of the system accessibility
    /// setting. The app reduces motion if *either* is on; this can only ever add
    /// to the system preference, never override it downwards.
    public var reduceMotion: Bool
    public var hasCompletedOnboarding: Bool
    /// Default building context for a new scan, so a user in a first-floor
    /// apartment on soft soil does not re-enter it for every room.
    public var defaultBuilding: BuildingContext

    public init(
        defaultIntensity: MercalliIntensity = .vii,
        defaultSoil: SoilClass = .firm,
        units: UnitSystem = .metric,
        cloudIdentificationEnabled: Bool = false,
        cloudConsentRecordedAt: Date? = nil,
        hapticsEnabled: Bool = true,
        reduceMotion: Bool = false,
        hasCompletedOnboarding: Bool = false,
        defaultBuilding: BuildingContext = BuildingContext()
    ) {
        self.defaultIntensity = defaultIntensity
        self.defaultSoil = defaultSoil
        self.units = units
        self.cloudIdentificationEnabled = cloudIdentificationEnabled
        self.cloudConsentRecordedAt = cloudConsentRecordedAt
        self.hapticsEnabled = hapticsEnabled
        self.reduceMotion = reduceMotion
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.defaultBuilding = defaultBuilding
    }

    /// Decoded field by field with `decodeIfPresent` so adding a preference in a
    /// later build reads old stored blobs without a migration.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SettingsValues()
        defaultIntensity = try c.decodeIfPresent(MercalliIntensity.self, forKey: .defaultIntensity) ?? d.defaultIntensity
        defaultSoil = try c.decodeIfPresent(SoilClass.self, forKey: .defaultSoil) ?? d.defaultSoil
        units = try c.decodeIfPresent(UnitSystem.self, forKey: .units) ?? d.units
        cloudIdentificationEnabled = try c.decodeIfPresent(Bool.self, forKey: .cloudIdentificationEnabled) ?? d.cloudIdentificationEnabled
        cloudConsentRecordedAt = try c.decodeIfPresent(Date.self, forKey: .cloudConsentRecordedAt)
        hapticsEnabled = try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? d.hapticsEnabled
        reduceMotion = try c.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? d.reduceMotion
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? d.hasCompletedOnboarding
        defaultBuilding = try c.decodeIfPresent(BuildingContext.self, forKey: .defaultBuilding) ?? d.defaultBuilding
    }
}

// MARK: - Store

/// Observable, `UserDefaults`-backed app preferences.
///
/// Every mutation writes through immediately. Preferences are a few hundred
/// bytes and change at human speed, so there is no batching to be gained and a
/// crash must never lose a toggle the user just flipped.
@Observable
public final class AppSettings {

    /// The single `UserDefaults` key. One blob, not eleven keys — see
    /// `SettingsValues`.
    public static let storageKey = "com.annenolte.proof.settings"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()

    /// Tracked storage. Private, but observation is by key path at runtime and
    /// does not care about access level, so views observing the computed
    /// accessors below are correctly invalidated.
    private var values: SettingsValues

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(SettingsValues.self, from: data) {
            self.values = decoded
        } else {
            self.values = SettingsValues()
        }
    }

    public static let shared = AppSettings()

    // MARK: Preferences

    public var defaultIntensity: MercalliIntensity {
        get { values.defaultIntensity }
        set { values.defaultIntensity = newValue; persist() }
    }

    public var defaultSoil: SoilClass {
        get { values.defaultSoil }
        set { values.defaultSoil = newValue; persist() }
    }

    public var units: UnitSystem {
        get { values.units }
        set { values.units = newValue; persist() }
    }

    /// Opt-in cloud object identification. Setting it to `true` stamps the
    /// consent date; setting it to `false` clears it, so re-enabling records a
    /// fresh consent rather than resurrecting an old one.
    public var cloudIdentificationEnabled: Bool {
        get { values.cloudIdentificationEnabled }
        set {
            guard newValue != values.cloudIdentificationEnabled else { return }
            values.cloudIdentificationEnabled = newValue
            values.cloudConsentRecordedAt = newValue ? Date() : nil
            persist()
        }
    }

    public var cloudConsentRecordedAt: Date? { values.cloudConsentRecordedAt }

    public var hapticsEnabled: Bool {
        get { values.hapticsEnabled }
        set { values.hapticsEnabled = newValue; persist() }
    }

    public var reduceMotion: Bool {
        get { values.reduceMotion }
        set { values.reduceMotion = newValue; persist() }
    }

    public var hasCompletedOnboarding: Bool {
        get { values.hasCompletedOnboarding }
        set { values.hasCompletedOnboarding = newValue; persist() }
    }

    public var defaultBuilding: BuildingContext {
        get { values.defaultBuilding }
        set { values.defaultBuilding = newValue; persist() }
    }

    // MARK: Bulk access

    /// The whole preference set, for export, diagnostics and tests.
    public var snapshot: SettingsValues {
        get { values }
        set { values = newValue; persist() }
    }

    /// Restores factory defaults, including clearing the onboarding flag.
    public func reset() {
        values = SettingsValues()
        persist()
    }

    // MARK: Formatting helpers

    public func formatLength(_ metres: Double, decimals: Int = 2) -> String {
        UnitFormatter.length(metres, in: units, decimals: decimals)
    }

    public func formatMass(_ kilograms: Double) -> String {
        UnitFormatter.mass(kilograms, in: units)
    }

    public func formatHeight(_ metres: Double) -> String {
        UnitFormatter.height(metres, in: units)
    }

    // MARK: Persistence

    private func persist() {
        guard let data = try? encoder.encode(values) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
