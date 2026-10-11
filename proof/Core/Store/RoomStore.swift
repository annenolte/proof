import Foundation

// MARK: - Errors

/// Everything the store can fail with. Deliberately small and `Equatable` so
/// call sites (and tests) can switch on a case rather than string-match.
public enum RoomStoreError: LocalizedError, Equatable {
    /// No package on disk for this identifier.
    case roomNotFound(UUID)
    /// The package exists but its `room.json` could not be decoded.
    case packageUnreadable(UUID, String)
    /// The file was written by a newer build of the app than this one.
    case schemaTooNew(found: Int, supported: Int)
    /// A migration step is missing for a version we claim to support.
    case migrationMissing(from: Int)
    /// The URL handed to `importPackage(from:)` is not a Tremor room.
    case notATremorRoom(String)
    /// A write could not be completed. The previous contents are intact.
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .roomNotFound:
            return "That room is no longer in your library."
        case .packageUnreadable:
            return "This room’s data is damaged and can’t be opened."
        case let .schemaTooNew(found, supported):
            return "This room was saved by a newer version of proof (format \(found), this version reads \(supported)). Update proof to open it."
        case .migrationMissing:
            return "This room’s data is in an older format proof can no longer read."
        case .notATremorRoom:
            return "That file isn’t a proof room."
        case let .writeFailed(reason):
            return "proof couldn’t save your room. \(reason)"
        }
    }
}

// MARK: - On-disk envelope

/// What actually lands in `room.json`.
///
/// `ScannedRoom` itself carries no version field — it is the domain model and
/// belongs to the physics core, which must not know that a disk exists. The
/// envelope adds the two things persistence needs and the model must not have:
/// a schema version to migrate against, and the `isSample` flag that marks the
/// seeded demo rooms so the library can badge them and re-seeding can tell them
/// from the user's own scans.
struct RoomEnvelope: Codable, Sendable {
    var version: Int
    var isSample: Bool
    var room: ScannedRoom

    init(version: Int = RoomStore.currentSchemaVersion, isSample: Bool = false, room: ScannedRoom) {
        self.version = version
        self.isSample = isSample
        self.room = room
    }

    /// Both envelope fields default, so a `room.json` that predates either of
    /// them — or one hand-edited by a developer — still decodes rather than
    /// presenting as a damaged room.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        isSample = try c.decodeIfPresent(Bool.self, forKey: .isSample) ?? false
        room = try c.decode(ScannedRoom.self, forKey: .room)
    }
}

/// Just enough of the envelope to read the version off a blob whose body may be
/// in a format this build cannot decode yet. Migration runs on the raw bytes,
/// before any attempt at the real decode.
private struct VersionProbe: Decodable {
    var version: Int?
}

// MARK: - Library listing

/// One row of the library screen, cheap enough to build for every room on every
/// appearance without opening the heavy parts of a package.
public struct RoomSummary: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: RoomKind
    public var objectCount: Int
    public var createdAt: Date
    public var updatedAt: Date
    /// Seeded demo content rather than something the user scanned.
    public var isSample: Bool
    public var hasThumbnail: Bool
    /// True when the package is present but unreadable. Such a room is still
    /// listed — the user is told it is damaged and offered delete or re-scan —
    /// because silently dropping rooms from a library is worse than showing a
    /// broken one.
    public var isDamaged: Bool
    /// Headline of the most recent saved assessment, if any.
    public var latestAssessment: AssessmentSummary?

    public init(
        id: UUID, name: String, kind: RoomKind = .other, objectCount: Int = 0,
        createdAt: Date = Date(), updatedAt: Date = Date(), isSample: Bool = false,
        hasThumbnail: Bool = false, isDamaged: Bool = false,
        latestAssessment: AssessmentSummary? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.objectCount = objectCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isSample = isSample
        self.hasThumbnail = hasThumbnail
        self.isDamaged = isDamaged
        self.latestAssessment = latestAssessment
    }
}

/// The three numbers a library row shows from a past run, without decoding the
/// whole per-object breakdown.
public struct AssessmentSummary: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var intensity: MercalliIntensity
    public var band: RiskBand
    public var score: Double
    public var createdAt: Date

    public init(id: UUID, intensity: MercalliIntensity, band: RiskBand, score: Double, createdAt: Date) {
        self.id = id
        self.intensity = intensity
        self.band = band
        self.score = score
        self.createdAt = createdAt
    }

    public init(_ assessment: RoomAssessment) {
        self.init(
            id: assessment.id,
            intensity: assessment.intensity,
            band: assessment.overallBand,
            score: assessment.overallScore,
            createdAt: assessment.createdAt
        )
    }
}

// MARK: - Export archive

/// The single-file form of a room, for share sheets, AirDrop and backup.
///
/// On disk a room is a *directory* package. A directory is not a thing
/// `UIActivityViewController` can reliably hand to another app without
/// registering an exported package UTI and going through `NSFileCoordinator`,
/// so export flattens the package into one self-contained JSON document with
/// the binaries base64-encoded. `importPackage(from:)` accepts either form.
struct RoomArchive: Codable, Sendable {
    static let magic = "ai.skarmy.tremor.room"

    var format: String = RoomArchive.magic
    var version: Int
    var room: ScannedRoom
    var assessments: [RoomAssessment]
    var thumbnail: Data?
    var usdz: Data?
    /// Object identifier (uuidString) → JPEG bytes.
    var crops: [String: Data]
}

// MARK: - Store

/// Persists rooms as self-contained `.tremorroom` packages under Application
/// Support. See SPEC §3.3 for why this is Codable-to-disk and not SwiftData:
/// the payload is one document plus several multi-megabyte blobs, versioning has
/// to be ours because Apple has changed `CapturedRoomData`'s encoding between OS
/// releases, and we need "this one attachment stopped decoding but the room is
/// still fine" recovery that a relational migration plan cannot express.
///
/// Package layout:
/// ```
/// <root>/
/// ├── .seeded                        marker: samples were installed once
/// └── Rooms/<roomID>.tremorroom/
///     ├── room.json                  RoomEnvelope { version, isSample, room }
///     ├── room.usdz                  optional exported geometry
///     ├── thumbnail.heic             optional
///     ├── crops/<objectID>.jpg       optional, one per identified object
///     └── assessments/<runID>.json   RoomAssessment
/// ```
public actor RoomStore {

    // MARK: Schema

    /// Bump this and add a migration whenever `room.json`'s shape changes in a
    /// way `Codable` cannot absorb on its own. Adding an *optional* property, or
    /// one decoded with `decodeIfPresent`, needs no bump.
    public static let currentSchemaVersion = 1

    /// Version *N* → version *N+1*, operating on the raw `room.json` bytes.
    /// Pure functions, applied on read and re-persisted lazily by the next save.
    public typealias Migration = @Sendable (Data) throws -> Data

    /// Registered migrations, keyed by the version they upgrade *from*.
    /// Empty at v1 — the hook exists so the first schema change is a one-line
    /// addition rather than a redesign.
    static let migrations: [Int: Migration] = [:]

    public static let packageExtension = "tremorroom"

    // MARK: Layout

    public let root: URL
    private let fm = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var roomsDirectory: URL { root.appendingPathComponent("Rooms", isDirectory: true) }
    private var seedMarker: URL { root.appendingPathComponent(".seeded", isDirectory: false) }

    private func packageURL(_ id: UUID) -> URL {
        roomsDirectory.appendingPathComponent("\(id.uuidString).\(Self.packageExtension)", isDirectory: true)
    }
    private func roomFile(_ id: UUID) -> URL { packageURL(id).appendingPathComponent("room.json") }
    private func usdzFile(_ id: UUID) -> URL { packageURL(id).appendingPathComponent("room.usdz") }
    private func thumbnailFile(_ id: UUID) -> URL { packageURL(id).appendingPathComponent("thumbnail.heic") }
    private func cropsDirectory(_ id: UUID) -> URL {
        packageURL(id).appendingPathComponent("crops", isDirectory: true)
    }
    private func cropFile(object: UUID, room: UUID) -> URL {
        cropsDirectory(room).appendingPathComponent("\(object.uuidString).jpg")
    }
    private func assessmentsDirectory(_ id: UUID) -> URL {
        packageURL(id).appendingPathComponent("assessments", isDirectory: true)
    }

    // MARK: Caching

    /// A room.json's identity on disk. If neither the size nor the modification
    /// date has moved, the cached summary is still true.
    private struct Stamp: Equatable {
        var size: Int
        var modified: Date
    }
    private var summaryCache: [UUID: (stamp: Stamp, summary: RoomSummary)] = [:]

    // MARK: Test seam

    /// Called with the destination URL immediately *after* the temporary file is
    /// written and immediately *before* it replaces the live file. Throwing from
    /// here is exactly a crash at the worst possible moment, and is how the
    /// atomicity test proves the previous room survives it. Never set in
    /// production code.
    var writeFault: (@Sendable (URL) throws -> Void)?

    func setWriteFault(_ fault: (@Sendable (URL) throws -> Void)?) {
        writeFault = fault
    }

    // MARK: Init

    /// - Parameter root: the directory the library lives in. Tests pass a fresh
    ///   temporary directory; the app uses `RoomStore.defaultRoot()`.
    public init(root: URL = RoomStore.defaultRoot()) {
        self.root = root

        // Dates use Foundation's default strategy — a `Double` of
        // `timeIntervalSinceReferenceDate` — deliberately, and not ISO 8601.
        // ISO 8601 truncates to whole seconds, so a saved room would not compare
        // equal to the one held in memory; `ScannedRoom` is `Equatable` and the
        // app diffs it, so a lossy date field would produce phantom edits.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    /// `~/Library/Application Support/Tremor`, created lazily on first write.
    ///
    /// Application Support rather than Documents: the library is app-managed
    /// data, not user-visible documents, and Documents is backed by iTunes/Files
    /// exposure we do not want for a directory of opaque packages.
    public nonisolated static func defaultRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("proof", isDirectory: true)
    }

    public static let shared = RoomStore()

    // MARK: - Listing

    /// Every room in the library, newest first, samples last within their date
    /// order. Never throws for a damaged package: that room is listed with
    /// `isDamaged == true` and the rest of the library is unaffected.
    @discardableResult
    public func list() throws -> [RoomSummary] {
        try seedSamplesIfNeeded()

        guard fm.fileExists(atPath: roomsDirectory.path) else { return [] }

        let entries = (try? fm.contentsOfDirectory(
            at: roomsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var summaries: [RoomSummary] = []
        for entry in entries where entry.pathExtension == Self.packageExtension {
            let name = entry.deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: name) else { continue }
            summaries.append(summary(for: id))
        }
        summaries.sort { $0.updatedAt > $1.updatedAt }
        return summaries
    }

    private func summary(for id: UUID) -> RoomSummary {
        let file = roomFile(id)
        let stamp = self.stamp(of: file)

        if let cached = summaryCache[id], let stamp, cached.stamp == stamp {
            return cached.summary
        }

        guard let data = try? Data(contentsOf: file) else {
            return damagedSummary(id)
        }
        guard let envelope = try? decodeEnvelope(data, id: id) else {
            return damagedSummary(id)
        }

        let latest = latestAssessmentSummary(for: id)
        let summary = RoomSummary(
            id: envelope.room.id,
            name: envelope.room.name,
            kind: envelope.room.kind,
            objectCount: envelope.room.objects.count,
            createdAt: envelope.room.createdAt,
            updatedAt: envelope.room.updatedAt,
            isSample: envelope.isSample,
            hasThumbnail: fm.fileExists(atPath: thumbnailFile(id).path),
            isDamaged: false,
            latestAssessment: latest
        )
        if let stamp { summaryCache[id] = (stamp, summary) }
        return summary
    }

    private func damagedSummary(_ id: UUID) -> RoomSummary {
        // Fall back to the folder's own dates so a damaged room still sorts
        // sensibly instead of jumping to the top of the library forever.
        let attrs = try? fm.attributesOfItem(atPath: packageURL(id).path)
        let modified = (attrs?[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
        let created = (attrs?[.creationDate] as? Date) ?? modified
        return RoomSummary(
            id: id, name: "Damaged room", kind: .other, objectCount: 0,
            createdAt: created, updatedAt: modified,
            isSample: false,
            hasThumbnail: fm.fileExists(atPath: thumbnailFile(id).path),
            isDamaged: true, latestAssessment: nil
        )
    }

    private func stamp(of url: URL) -> Stamp? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize, let modified = values.contentModificationDate
        else { return nil }
        return Stamp(size: size, modified: modified)
    }

    // MARK: - Rooms

    public func load(id: UUID) throws -> ScannedRoom {
        try envelope(id: id).room
    }

    /// Whether this room is one of the seeded demos.
    public func isSample(id: UUID) throws -> Bool {
        try envelope(id: id).isSample
    }

    private func envelope(id: UUID) throws -> RoomEnvelope {
        let file = roomFile(id)
        guard fm.fileExists(atPath: file.path) else { throw RoomStoreError.roomNotFound(id) }
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            throw RoomStoreError.packageUnreadable(id, error.localizedDescription)
        }
        return try decodeEnvelope(data, id: id)
    }

    /// Version-probe → migrate → decode. Migration happens on the bytes, so a
    /// v1 blob is never handed to a v3 `Codable` initialiser.
    private func decodeEnvelope(_ data: Data, id: UUID) throws -> RoomEnvelope {
        let probe = (try? decoder.decode(VersionProbe.self, from: data))?.version ?? 1
        guard probe <= Self.currentSchemaVersion else {
            throw RoomStoreError.schemaTooNew(found: probe, supported: Self.currentSchemaVersion)
        }

        var migrated = data
        var version = probe
        while version < Self.currentSchemaVersion {
            guard let step = Self.migrations[version] else {
                throw RoomStoreError.migrationMissing(from: version)
            }
            do {
                migrated = try step(migrated)
            } catch {
                throw RoomStoreError.packageUnreadable(id, "migration \(version)→\(version + 1) failed: \(error)")
            }
            version += 1
        }

        do {
            var envelope = try decoder.decode(RoomEnvelope.self, from: migrated)
            envelope.version = Self.currentSchemaVersion
            return envelope
        } catch {
            throw RoomStoreError.packageUnreadable(id, String(describing: error))
        }
    }

    /// Writes the room. Atomic: the previous `room.json` is only replaced once
    /// the new one is completely on disk, so a crash mid-save leaves the old
    /// room loadable rather than a truncated one.
    ///
    /// - Parameter touch: stamps `updatedAt` with `now`. Pass `false` to persist
    ///   a room exactly as given (round-trip tests, imports, sample seeding).
    /// - Returns: what was actually written, which is what the caller should
    ///   keep in memory.
    @discardableResult
    public func save(_ room: ScannedRoom, touch: Bool = true, isSample: Bool? = nil) throws -> ScannedRoom {
        var room = room
        if touch { room.updatedAt = Date() }

        // Preserve the sample flag across saves unless explicitly overridden, so
        // editing a demo room does not silently turn it into a user room (and
        // vice versa).
        let sample = isSample ?? ((try? envelope(id: room.id).isSample) ?? false)

        try ensureDirectory(packageURL(room.id))
        let envelope = RoomEnvelope(version: Self.currentSchemaVersion, isSample: sample, room: room)
        let data = try encoder.encode(envelope)
        try atomicWrite(data, to: roomFile(room.id))
        summaryCache[room.id] = nil
        return room
    }

    public func delete(id: UUID) throws {
        summaryCache[id] = nil
        let package = packageURL(id)
        guard fm.fileExists(atPath: package.path) else { return }
        do {
            try fm.removeItem(at: package)
        } catch {
            throw RoomStoreError.writeFailed(error.localizedDescription)
        }
    }

    public func exists(id: UUID) -> Bool {
        fm.fileExists(atPath: roomFile(id).path)
    }

    // MARK: - Assets

    public func saveThumbnail(_ data: Data, for roomID: UUID) throws {
        try requirePackage(roomID)
        try atomicWrite(data, to: thumbnailFile(roomID))
        summaryCache[roomID] = nil
    }

    public func loadThumbnail(for roomID: UUID) -> Data? {
        try? Data(contentsOf: thumbnailFile(roomID))
    }

    public func thumbnailURL(for roomID: UUID) -> URL? {
        let url = thumbnailFile(roomID)
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    public func saveCrop(_ data: Data, objectID: UUID, roomID: UUID) throws {
        try requirePackage(roomID)
        try ensureDirectory(cropsDirectory(roomID))
        try atomicWrite(data, to: cropFile(object: objectID, room: roomID))
    }

    public func loadCrop(objectID: UUID, roomID: UUID) -> Data? {
        try? Data(contentsOf: cropFile(object: objectID, room: roomID))
    }

    public func cropURL(objectID: UUID, roomID: UUID) -> URL? {
        let url = cropFile(object: objectID, room: roomID)
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    /// The exported geometry, written next to the room so the package stays
    /// self-contained and movable.
    public func saveUSDZ(_ data: Data, for roomID: UUID) throws {
        try requirePackage(roomID)
        try atomicWrite(data, to: usdzFile(roomID))
    }

    /// Copies a USDZ that RoomPlan wrote to a temporary location into the package.
    public func importUSDZ(from source: URL, for roomID: UUID) throws {
        let data = try Data(contentsOf: source)
        try saveUSDZ(data, for: roomID)
    }

    public func usdzURL(for roomID: UUID) -> URL? {
        let url = usdzFile(roomID)
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Assessments

    public func saveAssessment(_ assessment: RoomAssessment) throws {
        try requirePackage(assessment.roomID)
        try ensureDirectory(assessmentsDirectory(assessment.roomID))
        let url = assessmentsDirectory(assessment.roomID)
            .appendingPathComponent("\(assessment.id.uuidString).json")
        try atomicWrite(try encoder.encode(assessment), to: url)
        summaryCache[assessment.roomID] = nil
    }

    /// Saved runs for a room, newest first. A single unreadable run is skipped,
    /// never fatal.
    public func assessments(for roomID: UUID) -> [RoomAssessment] {
        let directory = assessmentsDirectory(roomID)
        guard let files = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [RoomAssessment] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let assessment = try? decoder.decode(RoomAssessment.self, from: data)
            else { continue }
            results.append(assessment)
        }
        return results.sorted { $0.createdAt > $1.createdAt }
    }

    public func latestAssessment(for roomID: UUID) -> RoomAssessment? {
        assessments(for: roomID).first
    }

    public func deleteAssessment(id: UUID, roomID: UUID) throws {
        let url = assessmentsDirectory(roomID).appendingPathComponent("\(id.uuidString).json")
        guard fm.fileExists(atPath: url.path) else { return }
        try fm.removeItem(at: url)
        summaryCache[roomID] = nil
    }

    private func latestAssessmentSummary(for roomID: UUID) -> AssessmentSummary? {
        assessments(for: roomID).first.map(AssessmentSummary.init)
    }

    // MARK: - Export / import

    /// Flattens a package into one shareable `.tremorroom` file in the temporary
    /// directory and returns its URL. The caller hands it to a share sheet; the
    /// system copies it out before the temporary directory is reaped.
    public func export(id: UUID) throws -> URL {
        let envelope = try self.envelope(id: id)

        var crops: [String: Data] = [:]
        if let files = try? fm.contentsOfDirectory(
            at: cropsDirectory(id), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) {
            for file in files where file.pathExtension == "jpg" {
                guard let data = try? Data(contentsOf: file) else { continue }
                crops[file.deletingPathExtension().lastPathComponent] = data
            }
        }

        let archive = RoomArchive(
            version: Self.currentSchemaVersion,
            room: envelope.room,
            assessments: assessments(for: id),
            thumbnail: loadThumbnail(for: id),
            usdz: usdzURL(for: id).flatMap { try? Data(contentsOf: $0) },
            crops: crops
        )

        let exports = fm.temporaryDirectory.appendingPathComponent("TremorExports", isDirectory: true)
        try ensureDirectory(exports)
        let url = exports.appendingPathComponent("\(Self.safeFilename(envelope.room.name)).\(Self.packageExtension)")
        try? fm.removeItem(at: url)
        try encoder.encode(archive).write(to: url, options: .atomic)
        return url
    }

    /// Accepts either an exported single-file archive or a `.tremorroom`
    /// directory copied by hand, and installs it as a new room in the library.
    ///
    /// The identifier is preserved when it is free and re-minted when it would
    /// collide, so importing a room you already have never overwrites your copy.
    /// Imported rooms are never samples.
    @discardableResult
    public func importPackage(from url: URL) throws -> ScannedRoom {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw RoomStoreError.notATremorRoom(url.lastPathComponent)
        }

        if isDirectory.boolValue {
            return try importDirectory(url)
        } else {
            return try importArchive(url)
        }
    }

    private func importArchive(_ url: URL) throws -> ScannedRoom {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { throw RoomStoreError.notATremorRoom(url.lastPathComponent) }

        guard let archive = try? decoder.decode(RoomArchive.self, from: data),
              archive.format == RoomArchive.magic
        else {
            // Maybe it is a bare room.json rather than a full archive.
            if let envelope = try? decoder.decode(RoomEnvelope.self, from: data) {
                return try install(room: envelope.room, assessments: [], thumbnail: nil, usdz: nil, crops: [:])
            }
            throw RoomStoreError.notATremorRoom(url.lastPathComponent)
        }
        guard archive.version <= Self.currentSchemaVersion else {
            throw RoomStoreError.schemaTooNew(found: archive.version, supported: Self.currentSchemaVersion)
        }

        return try install(
            room: archive.room,
            assessments: archive.assessments,
            thumbnail: archive.thumbnail,
            usdz: archive.usdz,
            crops: archive.crops
        )
    }

    private func importDirectory(_ url: URL) throws -> ScannedRoom {
        let roomFile = url.appendingPathComponent("room.json")
        guard let data = try? Data(contentsOf: roomFile) else {
            throw RoomStoreError.notATremorRoom(url.lastPathComponent)
        }
        let probeID = UUID()
        let envelope = try decodeEnvelope(data, id: probeID)

        var assessments: [RoomAssessment] = []
        if let files = try? fm.contentsOfDirectory(
            at: url.appendingPathComponent("assessments", isDirectory: true),
            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) {
            for file in files where file.pathExtension == "json" {
                if let d = try? Data(contentsOf: file),
                   let a = try? decoder.decode(RoomAssessment.self, from: d) {
                    assessments.append(a)
                }
            }
        }

        var crops: [String: Data] = [:]
        if let files = try? fm.contentsOfDirectory(
            at: url.appendingPathComponent("crops", isDirectory: true),
            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) {
            for file in files where file.pathExtension == "jpg" {
                if let d = try? Data(contentsOf: file) {
                    crops[file.deletingPathExtension().lastPathComponent] = d
                }
            }
        }

        return try install(
            room: envelope.room,
            assessments: assessments,
            thumbnail: try? Data(contentsOf: url.appendingPathComponent("thumbnail.heic")),
            usdz: try? Data(contentsOf: url.appendingPathComponent("room.usdz")),
            crops: crops
        )
    }

    private func install(
        room: ScannedRoom,
        assessments: [RoomAssessment],
        thumbnail: Data?,
        usdz: Data?,
        crops: [String: Data]
    ) throws -> ScannedRoom {
        var room = room
        let collided = exists(id: room.id)
        if collided {
            room.id = UUID()
            room.name = Self.disambiguated(room.name)
        }

        let saved = try save(room, touch: false, isSample: false)
        if let thumbnail { try saveThumbnail(thumbnail, for: saved.id) }
        if let usdz { try saveUSDZ(usdz, for: saved.id) }
        for (key, data) in crops {
            guard let objectID = UUID(uuidString: key) else { continue }
            try saveCrop(data, objectID: objectID, roomID: saved.id)
        }
        for assessment in assessments {
            var assessment = assessment
            if collided {
                assessment.id = UUID()
                assessment.roomID = saved.id
            }
            try saveAssessment(assessment)
        }
        return saved
    }

    // MARK: - Sample seeding

    /// Installs `RoomFixtures.all` the first time the library is opened, so a
    /// new user has something to explore before they have scanned anything.
    ///
    /// Guarded by a marker file rather than by "is the library empty", because a
    /// user who deletes the demos must not get them back on next launch.
    @discardableResult
    public func seedSamplesIfNeeded() throws -> Bool {
        guard !fm.fileExists(atPath: seedMarker.path) else { return false }
        try ensureDirectory(roomsDirectory)

        for room in RoomFixtures.all {
            // Never clobber a real room that happens to share a fixture id.
            guard !exists(id: room.id) else { continue }
            try save(room, touch: false, isSample: true)
        }
        try Data().write(to: seedMarker, options: .atomic)
        return true
    }

    /// Removes every seeded sample and re-installs a fresh set. Used by
    /// "Restore demo rooms" in Settings.
    public func resetSamples() throws {
        for summary in (try? list()) ?? [] where summary.isSample {
            try delete(id: summary.id)
        }
        try? fm.removeItem(at: seedMarker)
        try seedSamplesIfNeeded()
    }

    // MARK: - Maintenance

    /// Total bytes the library occupies, for the storage row in Settings.
    public func diskUsage() -> Int64 {
        guard let enumerator = fm.enumerator(
            at: roomsDirectory, includingPropertiesForKeys: [.fileSizeKey], options: []
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
        return total
    }

    /// Deletes packages whose `room.json` cannot be decoded. Offered to the user
    /// explicitly; never run automatically, because a damaged package may still
    /// be recoverable by a future build.
    @discardableResult
    public func purgeDamaged() throws -> Int {
        let damaged = ((try? list()) ?? []).filter(\.isDamaged)
        for summary in damaged { try delete(id: summary.id) }
        return damaged.count
    }

    // MARK: - Filesystem primitives

    private func requirePackage(_ id: UUID) throws {
        guard fm.fileExists(atPath: roomFile(id).path) else {
            throw RoomStoreError.roomNotFound(id)
        }
    }

    private func ensureDirectory(_ url: URL) throws {
        try AtomicFile.ensureDirectory(url)
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        try AtomicFile.write(data, to: url, beforeSwap: writeFault)
    }
}

// MARK: - Atomic file primitive

/// Write-to-temp-then-swap, shared by the room store and the profile store.
///
/// `Data.write(options: .atomic)` alone does the same thing for a file that does
/// not exist yet, but the explicit two-step lets a test seam interpose between
/// "new bytes are durable" and "new bytes are visible" — precisely the window a
/// crash has to hit to corrupt a saved room. It also guarantees a failed write
/// leaves no partial file behind.
enum AtomicFile {

    static func ensureDirectory(_ url: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else { return }
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw RoomStoreError.writeFailed(error.localizedDescription)
        }
    }

    static func write(
        _ data: Data,
        to url: URL,
        beforeSwap: ((URL) throws -> Void)? = nil
    ) throws {
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        try ensureDirectory(directory)

        let temp = directory.appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).tmp"
        )
        do {
            try data.write(to: temp, options: .atomic)
        } catch {
            throw RoomStoreError.writeFailed(error.localizedDescription)
        }

        if let beforeSwap {
            do {
                try beforeSwap(url)
            } catch {
                try? fm.removeItem(at: temp)
                throw error
            }
        }

        do {
            if fm.fileExists(atPath: url.path) {
                _ = try fm.replaceItemAt(url, withItemAt: temp)
            } else {
                try fm.moveItem(at: temp, to: url)
            }
        } catch {
            try? fm.removeItem(at: temp)
            throw RoomStoreError.writeFailed(error.localizedDescription)
        }
    }
}

extension RoomStore {

    // MARK: - Naming

    static func safeFilename(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let stripped = String(name.unicodeScalars.filter { allowed.contains($0) })
        // Collapse the runs of spaces left behind by the removed characters, so
        // "Anne’s bedroom / #2" exports as "Annes bedroom 2" rather than with a
        // gap where the punctuation used to be.
        let cleaned = stripped.split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        return cleaned.isEmpty ? "Room" : String(cleaned.prefix(60))
    }

    static func disambiguated(_ name: String) -> String {
        name.hasSuffix(" (imported)") ? name : "\(name) (imported)"
    }
}
