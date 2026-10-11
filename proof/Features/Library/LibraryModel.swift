//
//  LibraryModel.swift
//  Tremor — Features / Library (S-06)
//
//  Everything S-06 knows that is not a view.
//
//  The split is deliberate: every decision the library makes — how rooms sort,
//  which ones a band filter keeps, what the home summary says, what a duplicate
//  is called, what a row's subtitle reads — is a **static pure function** here,
//  and the `@Observable` class is a thin shell that holds the loaded list and
//  awaits the store. That is what makes the screen testable without a window
//  server, and it is why `LibraryScreenTests` can assert the copy itself.
//
//  Undo deserves a note. Deleting a room removes a directory package; there is
//  no trash. So a delete first exports the package to a single flat file in the
//  temporary directory and keeps the URL — `RoomStore.export(id:)` already
//  produces exactly that, and `importPackage(from:)` restores it with its
//  original identifier when the identifier is free. Undo is therefore real: the
//  same room comes back, with its assessments, its thumbnail and its crops. When
//  the export cannot be taken (a damaged package), we say so instead of offering
//  an undo that would not work.
//

import Foundation
import Observation
import SwiftUI

// MARK: - Sorting

/// How the room list is ordered. Three orders, because a library of five rooms
/// does not need more and a library of fifty is served by all three.
enum LibrarySort: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// Most recently scanned or edited first. The default.
    case recent
    /// Worst finding first, then by score inside a band. What a person who has
    /// just read a scary report actually wants.
    case risk
    /// A to Z, for someone who knows the room's name.
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return "Recent"
        case .risk: return "Riskiest"
        case .name: return "Name"
        }
    }

    var symbolName: String {
        switch self {
        case .recent: return "clock"
        case .risk: return "exclamationmark.triangle"
        case .name: return "textformat.abc"
        }
    }

    /// Spoken when the sort changes, so the change is not silent to VoiceOver.
    var announcement: String {
        switch self {
        case .recent: return "Sorted by most recent"
        case .risk: return "Sorted by highest risk"
        case .name: return "Sorted by name"
        }
    }
}

// MARK: - Home safety summary

/// The whole-home verdict shown above the room list.
///
/// It is a summary of *rooms*, not of objects: one room contributes one entry to
/// the distribution, whatever is inside it. That keeps the bar honest — a room
/// with forty safe chairs must not dilute a room with one lethal bookcase.
struct HomeSafetySummary: Equatable, Sendable {

    /// Rooms in the library, including ones never simulated.
    var roomCount: Int
    /// Rooms that have at least one saved assessment.
    var simulatedCount: Int
    /// Room counts per band, for the distribution bar.
    var counts: [RiskBand: Int]
    /// The worst band across every simulated room.
    var worstBand: RiskBand
    /// When the most recent assessment was made.
    var lastSimulated: Date?

    var unsimulatedCount: Int { max(0, roomCount - simulatedCount) }

    /// The headline. Warm, specific, second person, and never a scolding.
    var headline: String {
        switch worstBand {
        case .severe: return "Something here could seriously hurt someone"
        case .high: return "A few things here are likely to fall"
        case .moderate: return "Mostly steady, with a few things worth securing"
        case .low: return "Everything you've scanned should stay put"
        }
    }

    /// The supporting line. Always carries the counts, never bare adjectives.
    var message: String {
        let roomWord = simulatedCount == 1 ? "room" : "rooms"
        let atRisk = (counts[.high] ?? 0) + (counts[.severe] ?? 0)

        switch worstBand {
        case .severe, .high:
            let riskWord = atRisk == 1 ? "room needs" : "rooms need"
            return "Across \(simulatedCount) simulated \(roomWord), \(atRisk) \(riskWord) attention before the next earthquake."
        case .moderate:
            return "Across \(simulatedCount) simulated \(roomWord), nothing looks life-threatening — but a few cheap fixes would help."
        case .low:
            return "Across \(simulatedCount) simulated \(roomWord), nothing we can see would come down. A Low is not a guarantee, though."
        }
    }

    /// What the distribution bar says out loud. The shared component counts
    /// *objects*; here each segment is a whole room, so the label is replaced
    /// rather than left to say the wrong noun.
    var spokenDistribution: String {
        let parts = RiskBand.allCases.reversed().compactMap { band -> String? in
            guard let count = counts[band], count > 0 else { return nil }
            return "\(count) \(band.displayName.lowercased())"
        }
        guard !parts.isEmpty else { return "No rooms shaken yet" }
        let roomWord = simulatedCount == 1 ? "room" : "rooms"
        return "\(simulatedCount) \(roomWord): " + parts.joined(separator: ", ")
    }

    /// Builds the summary, or `nil` when nothing has been simulated yet — in
    /// which case the screen shows an invitation rather than an empty gauge.
    static func make(from rooms: [RoomSummary]) -> HomeSafetySummary? {
        let live = rooms.filter { !$0.isDamaged }
        let assessed = live.compactMap { $0.latestAssessment }
        guard !assessed.isEmpty else { return nil }

        var counts: [RiskBand: Int] = [:]
        for assessment in assessed {
            counts[assessment.band, default: 0] += 1
        }

        return HomeSafetySummary(
            roomCount: live.count,
            simulatedCount: assessed.count,
            counts: counts,
            worstBand: assessed.map(\.band).max() ?? .low,
            lastSimulated: assessed.map(\.createdAt).max())
    }
}

// MARK: - Formatting

/// The strings S-06 and S-18 put on screen. Static so the tests can read them
/// without rendering anything.
enum LibraryFormatting {

    /// "4 Aug" — short, no year unless the year is not this one.
    static func shortDate(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "dMMM" : "dMMMyyyy")
        return formatter.string(from: date)
    }

    /// "12 objects" / "1 object" / "Empty room".
    static func objectCount(_ count: Int) -> String {
        switch count {
        case 0: return "No objects yet"
        case 1: return "1 object"
        default: return "\(count) objects"
        }
    }

    /// The library row's second line.
    ///
    /// Three shapes, in priority order: damaged beats everything, then a room
    /// that has been simulated, then one that has not. A room that has never
    /// been shaken says when it was *scanned* rather than repeating what the
    /// trailing pill already says — the row has two slots, and spending both on
    /// the same fact wastes one and wraps the line.
    static func rowSubtitle(for room: RoomSummary, now: Date = Date()) -> String {
        if room.isDamaged {
            return "This room's file is damaged"
        }
        let objects = objectCount(room.objectCount)
        if let assessment = room.latestAssessment {
            return "\(objects) · shaken \(shortDate(assessment.createdAt, now: now))"
        }
        return "\(objects) · scanned \(shortDate(room.createdAt, now: now))"
    }

    /// The accessibility value for a room row: never colour alone, always the
    /// band's name and, where there is one, the score out of a hundred.
    static func rowAccessibilityValue(for room: RoomSummary, now: Date = Date()) -> String {
        if room.isDamaged { return "Damaged. This room's file can't be read." }
        var parts = [objectCount(room.objectCount)]
        if let assessment = room.latestAssessment {
            parts.append("\(assessment.band.displayName) risk, \(Int(assessment.score.rounded())) out of 100")
            parts.append("shaken at intensity \(assessment.intensity.roman) on \(shortDate(assessment.createdAt, now: now))")
        } else {
            parts.append("Not simulated yet")
        }
        return parts.joined(separator: ". ")
    }

    /// "Bedroom copy", then "Bedroom copy 2", and so on. Never collides with a
    /// name already in the library.
    static func duplicateName(of name: String, existing: [String]) -> String {
        let taken = Set(existing)
        let base = "\(name) copy"
        guard taken.contains(base) else { return base }
        var index = 2
        while taken.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }

    /// Bytes as a short human string, for the storage row in Settings.
    static func fileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: max(0, bytes))
    }
}

// MARK: - Undo

/// A delete that can still be taken back.
struct PendingRoomDeletion: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    /// The flattened package. `nil` when the room was too damaged to export, in
    /// which case the banner says the delete is permanent rather than lying.
    let archive: URL?

    var canUndo: Bool { archive != nil }

    var message: String {
        canUndo
            ? "You can put it back for a few seconds."
            : "That room's file was damaged, so it couldn't be kept."
    }
}

// MARK: - The model

/// S-06's state: the loaded list, the sort, the band filter, edit mode, and the
/// one pending undo.
@MainActor
@Observable
final class LibraryModel {

    /// What the list is doing. `failed` carries copy a person can act on.
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)

        var isLoading: Bool { self == .loading }
    }

    // MARK: State

    private(set) var phase: Phase = .loading
    private(set) var rooms: [RoomSummary] = []

    var sort: LibrarySort = .recent
    /// `nil` means every band. Only ever set to a band that is actually present.
    var bandFilter: RiskBand?
    var isEditing = false

    /// The delete the user can still take back. Cleared by a timer, by an undo,
    /// or by any other action.
    private(set) var pendingDeletion: PendingRoomDeletion?

    /// True while a rename, duplicate, delete or undo is in flight, so the row
    /// actions can disable rather than double-fire.
    private(set) var isMutating = false

    @ObservationIgnored private var env: TremorEnvironment?
    @ObservationIgnored private var undoTimer: Task<Void, Never>?

    /// Seconds the undo banner stays up. Long enough to read and reach, short
    /// enough that it is gone before it becomes furniture.
    static let undoWindowSeconds: Double = 8

    init() {}

    deinit { undoTimer?.cancel() }

    /// Hands the model its services. Called from the view's `.task`, because a
    /// `@State` model cannot read the environment at initialisation.
    func attach(_ env: TremorEnvironment) {
        self.env = env
    }

    // MARK: Derived

    /// The rooms actually rendered, after the filter and the sort.
    var visibleRooms: [RoomSummary] {
        Self.arrange(rooms, sort: sort, band: bandFilter)
    }

    /// The whole-home verdict, or `nil` when nothing has been simulated.
    var summary: HomeSafetySummary? { HomeSafetySummary.make(from: rooms) }

    /// Bands that at least one room is currently in, in severity order. Drives
    /// the filter chips — we never offer a filter that would return nothing.
    var availableBands: [RiskBand] {
        let present = Set(rooms.compactMap { $0.latestAssessment?.band })
        return RiskBand.allCases.filter(present.contains).reversed()
    }

    /// True when the library holds nothing at all.
    var isEmpty: Bool { rooms.isEmpty }

    /// True when a filter is hiding everything — a different, recoverable kind
    /// of empty, and one that must offer the way out.
    var isFilteredEmpty: Bool { !rooms.isEmpty && visibleRooms.isEmpty }

    /// Count of rooms whose package could not be read.
    var damagedCount: Int { rooms.filter(\.isDamaged).count }

    // MARK: Pure arrangement

    /// Filter then sort. Static and pure, so the tests can pin the ordering.
    static func arrange(_ rooms: [RoomSummary],
                        sort: LibrarySort,
                        band: RiskBand?) -> [RoomSummary] {
        sorted(filtered(rooms, band: band), by: sort)
    }

    /// Keeps rooms whose latest assessment is in `band`. A `nil` band keeps
    /// everything; a room that has never been simulated is never kept by a band
    /// filter, because it has no band to match.
    static func filtered(_ rooms: [RoomSummary], band: RiskBand?) -> [RoomSummary] {
        guard let band else { return rooms }
        return rooms.filter { $0.latestAssessment?.band == band }
    }

    static func sorted(_ rooms: [RoomSummary], by sort: LibrarySort) -> [RoomSummary] {
        switch sort {
        case .recent:
            return rooms.sorted { left, right in
                if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }
        case .name:
            return rooms.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .risk:
            return rooms.sorted { left, right in
                let l = left.latestAssessment
                let r = right.latestAssessment
                switch (l, r) {
                case (nil, nil):
                    return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
                // A room nobody has simulated sorts last: we are not claiming it
                // is safe, we simply do not know, and guesses do not go top.
                case (nil, _): return false
                case (_, nil): return true
                case (let l?, let r?):
                    if l.band != r.band { return l.band > r.band }
                    if l.score != r.score { return l.score > r.score }
                    return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
                }
            }
        }
    }

    // MARK: Loading

    /// Reads the library index. Never throws at the caller: a failure becomes a
    /// `failed` phase carrying a sentence with a way forward.
    func load(showsSpinner: Bool = true) async {
        guard let env else { return }
        if showsSpinner, rooms.isEmpty { phase = .loading }
        do {
            let listed = try await env.rooms.list()
            rooms = listed
            // A filter that no longer matches anything would strand the user on
            // an empty list they did not ask for, so it is dropped silently.
            if let band = bandFilter, !availableBands.contains(band) { bandFilter = nil }
            phase = .loaded
        } catch {
            phase = .failed(AppState.message(for: error))
        }
    }

    /// Reload without the skeleton, after a mutation the user just made.
    func refresh() async { await load(showsSpinner: false) }

    // MARK: Mutations

    /// Renames a room. Trims, and refuses to write an empty name — falling back
    /// to the room kind rather than leaving a blank row.
    @discardableResult
    func rename(_ room: RoomSummary, to newName: String) async -> Bool {
        guard let env, !isMutating else { return false }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let final = trimmed.isEmpty ? room.kind.displayName : trimmed
        guard final != room.name else { return true }

        isMutating = true
        defer { isMutating = false }
        do {
            var loaded = try await env.rooms.load(id: room.id)
            loaded.name = final
            _ = try await env.rooms.save(loaded)
            await refresh()
            return true
        } catch {
            phase = .failed(AppState.message(for: error))
            return false
        }
    }

    /// Copies a room, its thumbnail and its crops under a new identifier.
    /// Assessments are deliberately not copied: a copy has not been shaken.
    @discardableResult
    func duplicate(_ room: RoomSummary) async -> String? {
        guard let env, !isMutating else { return nil }
        isMutating = true
        defer { isMutating = false }

        do {
            var loaded = try await env.rooms.load(id: room.id)
            let name = LibraryFormatting.duplicateName(of: loaded.name, existing: rooms.map(\.name))
            loaded.id = UUID()
            loaded.name = name
            loaded.createdAt = Date()
            loaded.updatedAt = Date()
            let saved = try await env.rooms.save(loaded)

            if let thumbnail = await env.rooms.loadThumbnail(for: room.id) {
                try? await env.rooms.saveThumbnail(thumbnail, for: saved.id)
            }
            for object in loaded.objects {
                if let crop = await env.rooms.loadCrop(objectID: object.id, roomID: room.id) {
                    try? await env.rooms.saveCrop(crop, objectID: object.id, roomID: saved.id)
                }
            }
            await refresh()
            return name
        } catch {
            phase = .failed(AppState.message(for: error))
            return nil
        }
    }

    /// Deletes a room, keeping a flattened copy so the delete can be undone.
    @discardableResult
    func delete(_ room: RoomSummary) async -> PendingRoomDeletion? {
        guard let env, !isMutating else { return nil }
        isMutating = true
        defer { isMutating = false }

        // Taken before the delete, and allowed to fail: a damaged package cannot
        // be exported, and refusing to delete it would trap the user with a row
        // they cannot get rid of.
        let archive = try? await env.rooms.export(id: room.id)

        do {
            try await env.rooms.delete(id: room.id)
        } catch {
            phase = .failed(AppState.message(for: error))
            return nil
        }

        await refresh()
        let pending = PendingRoomDeletion(id: room.id, name: room.name, archive: archive)
        armUndo(pending)
        return pending
    }

    /// Restores the last deleted room. Returns false when the window has closed
    /// or the archive could not be read back.
    @discardableResult
    func undoDelete() async -> Bool {
        guard let env, let pending = pendingDeletion, let archive = pending.archive else { return false }
        undoTimer?.cancel()
        pendingDeletion = nil
        isMutating = true
        defer { isMutating = false }

        do {
            _ = try await env.rooms.importPackage(from: archive)
            await refresh()
            return true
        } catch {
            phase = .failed(AppState.message(for: error))
            return false
        }
    }

    /// Drops the undo without restoring. Called by the banner's close button and
    /// by the expiry timer.
    func dismissUndo() {
        undoTimer?.cancel()
        undoTimer = nil
        pendingDeletion = nil
    }

    /// Removes every unreadable package. Offered explicitly from the damaged
    /// banner, never run behind the user's back.
    @discardableResult
    func purgeDamaged() async -> Int {
        guard let env else { return 0 }
        let removed = (try? await env.rooms.purgeDamaged()) ?? 0
        await refresh()
        return removed
    }

    /// Re-installs the bundled demo rooms. The way back from "I deleted
    /// everything, including the samples".
    func restoreDemoRooms() async {
        guard let env else { return }
        try? await env.rooms.resetSamples()
        await refresh()
    }

    private func armUndo(_ pending: PendingRoomDeletion) {
        undoTimer?.cancel()
        pendingDeletion = pending
        guard pending.canUndo else {
            // Nothing to undo — the banner is informational, and still expires.
            undoTimer = expiry(after: Self.undoWindowSeconds)
            return
        }
        undoTimer = expiry(after: Self.undoWindowSeconds)
    }

    private func expiry(after seconds: Double) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.pendingDeletion = nil
        }
    }
}
