import Foundation

#if canImport(RoomPlan)
import RoomPlan
#endif

/// One piece of live coaching, ready to render.
public struct ScanCoaching: Codable, Hashable, Sendable {

    /// How loud the HUD should be about this. Nothing here scolds.
    public enum Tone: String, Codable, Hashable, Sendable {
        /// Everything is fine — reassurance only.
        case steady
        /// A small correction: move, slow down, turn.
        case nudge
        /// The scan will suffer until this is fixed.
        case attention
    }

    public var headline: String
    /// A second line, shown only when there is room for it.
    public var detail: String?
    public var symbolName: String
    public var tone: Tone

    public init(headline: String, detail: String? = nil, symbolName: String, tone: Tone) {
        self.headline = headline
        self.detail = detail
        self.symbolName = symbolName
        self.tone = tone
    }
}

/// Turns RoomPlan's six terse instructions into copy a person can act on, and
/// turns raw element counts into a coverage estimate.
///
/// RoomPlan's `Instruction` values carry no localised text of their own, so every
/// word the user reads during a scan originates here. The rules the copy follows:
/// say what to *do*, never what they did wrong; never use a word that only an
/// engineer knows ("world tracking", "texture", "mesh"); and never leave the
/// screen without an instruction, because silence during a scan reads as a
/// freeze.
public enum ScanCoach {

    /// RoomPlan's `Instruction`, mirrored so the coaching copy is testable
    /// without the SDK and so `@unknown default` is handled in exactly one place.
    public enum Cue: String, Codable, Hashable, Sendable, CaseIterable {
        case normal
        case moveCloseToWall
        case moveAwayFromWall
        case slowDown
        case turnOnLight
        case lowTexture
        /// Anything RoomPlan adds in a future release, plus the state before the
        /// first instruction arrives.
        case keepScanning
    }

    // MARK: - Copy

    public static func coaching(for cue: Cue) -> ScanCoaching {
        switch cue {
        case .normal:
            return ScanCoaching(
                headline: "Looking good — keep going",
                symbolName: "checkmark.circle.fill",
                tone: .steady)
        case .moveCloseToWall:
            return ScanCoaching(
                headline: "Move closer to the wall",
                detail: "About an arm's length works best.",
                symbolName: "arrow.forward",
                tone: .nudge)
        case .moveAwayFromWall:
            return ScanCoaching(
                headline: "Step back a little",
                detail: "You're too close to see the whole wall.",
                symbolName: "arrow.backward",
                tone: .nudge)
        case .slowDown:
            return ScanCoaching(
                headline: "Move a little slower",
                detail: "Sweeping slowly picks up more detail.",
                symbolName: "tortoise.fill",
                tone: .nudge)
        case .turnOnLight:
            return ScanCoaching(
                headline: "Turn on a light",
                detail: "It's a bit dark for the scanner to see.",
                symbolName: "lightbulb.fill",
                tone: .attention)
        case .lowTexture:
            return ScanCoaching(
                headline: "Point at the far wall",
                detail: "Blank surfaces are hard to lock on to — aim for a corner or a doorway.",
                symbolName: "scribble",
                tone: .attention)
        case .keepScanning:
            return ScanCoaching(
                headline: "Keep scanning",
                symbolName: "viewfinder",
                tone: .steady)
        }
    }

    /// What to show before the first instruction arrives, while ARKit warms up.
    public static var preparing: ScanCoaching {
        ScanCoaching(
            headline: "Point at a wall to begin",
            detail: "Then walk slowly around the edge of the room.",
            symbolName: "viewfinder",
            tone: .steady)
    }

    /// Shown once the room is complete enough to stop.
    public static var readyToFinish: ScanCoaching {
        ScanCoaching(
            headline: "That's the room — finish whenever you like",
            detail: "Anything else you point at gets added.",
            symbolName: "checkmark.circle.fill",
            tone: .steady)
    }

    // MARK: - Progress

    /// Coverage from the live element counts.
    ///
    /// Four tracks rather than one bar, because "62 %" tells a user nothing about
    /// where to point the phone next, and "Walls ▓▓▓░ Objects ▓░░░" does.
    ///
    /// - Parameters:
    ///   - walls: walls seen so far.
    ///   - completeWalls: of those, how many have all four edges scanned.
    ///   - floors: floor planes seen.
    ///   - openings: doors + windows + openings seen.
    ///   - objects: furniture detected.
    ///   - elapsed: seconds since the scan started.
    public static func progress(
        walls: Int,
        completeWalls: Int,
        floors: Int,
        openings: Int,
        objects: Int,
        elapsed: TimeInterval
    ) -> ScanProgress {
        // Four walls is a whole rectangular room; more is a bonus, not more
        // progress. Half the credit is for finding a wall, half for finishing it.
        let found = min(1.0, Double(walls) / 4.0)
        let finished = walls > 0 ? min(1.0, Double(completeWalls) / Double(max(walls, 4))) : 0
        let wallScore = found * 0.5 + finished * 0.5

        return ScanProgress(
            walls: wallScore,
            floor: floors > 0 ? 1 : 0,
            openings: min(1.0, Double(openings) / 2.0),
            objects: min(1.0, Double(objects) / 6.0),
            objectCount: objects,
            elapsed: elapsed,
            // The same rule the "Done scanning" button uses: three walls and a
            // floor is the least that can become a room.
            isReadyToFinish: walls >= 3 && floors >= 1
        )
    }

    /// Progress computed straight from a partially converted room.
    public static func progress(
        for room: ScannedRoom, completeWalls: Int? = nil, elapsed: TimeInterval
    ) -> ScanProgress {
        let walls = room.surfaces.filter { $0.kind == .wall }.count
        let floors = room.surfaces.filter { $0.kind == .floor }.count
        let openings = room.surfaces.filter {
            $0.kind == .door || $0.kind == .window || $0.kind == .opening
        }.count
        return progress(
            walls: walls,
            completeWalls: completeWalls ?? walls,
            floors: floors,
            openings: openings,
            objects: room.objects.count,
            elapsed: elapsed)
    }

    /// The live count line under the coverage bar. Plain English, never "n = 7".
    public static func objectSummary(count: Int) -> String {
        switch count {
        case 0: return "Looking for furniture"
        case 1: return "1 object found"
        default: return "\(count) objects found"
        }
    }

    /// A gentle, non-blocking nudge when a scan has run long enough that thermal
    /// throttling starts to hurt accuracy.
    public static func elapsedWarning(for elapsed: TimeInterval) -> String? {
        guard elapsed >= 270 else { return nil }
        return "Scans over five minutes lose accuracy — wrap up when you can."
    }

    /// Shown when `ProcessInfo.thermalState` reaches `.serious`.
    public static let thermalWarning =
        "Your iPhone is warm. Finish soon for the best accuracy."
}

// MARK: - The RoomPlan bridge

#if canImport(RoomPlan)
extension ScanCoach {

    /// Maps RoomPlan's instruction to our cue.
    ///
    /// `Instruction` is non-frozen — RoomPlan ships with library evolution
    /// enabled — so the `@unknown default` is required by the compiler under
    /// Swift 6 and is the reason `.keepScanning` exists.
    public static func cue(for instruction: RoomCaptureSession.Instruction) -> Cue {
        switch instruction {
        case .normal: return .normal
        case .moveCloseToWall: return .moveCloseToWall
        case .moveAwayFromWall: return .moveAwayFromWall
        case .slowDown: return .slowDown
        case .turnOnLight: return .turnOnLight
        case .lowTexture: return .lowTexture
        @unknown default: return .keepScanning
        }
    }

    /// Named distinctly from `coaching(for: Cue)` because `Instruction` and `Cue`
    /// share case names — `.normal`, `.slowDown` — and an overload pair would be
    /// ambiguous at every call site that leans on inference.
    public static func coaching(
        forInstruction instruction: RoomCaptureSession.Instruction
    ) -> ScanCoaching {
        coaching(for: cue(for: instruction))
    }

    /// Maps RoomPlan's capture and build errors onto ours, so the UI has exactly
    /// one error vocabulary.
    public static func scanError(from error: any Error) -> ScanError {
        if let capture = error as? RoomCaptureSession.CaptureError {
            switch capture {
            case .exceedSceneSizeLimit: return .sceneTooLarge
            case .worldTrackingFailure: return .trackingLost
            case .invalidARConfiguration: return .invalidConfiguration
            case .deviceTooHot: return .deviceTooHot
            case .deviceNotSupported: return .deviceNotSupported
            case .internalError: return .unknown("")
            @unknown default: return .unknown("")
            }
        }
        if let build = error as? RoomBuilder.BuildError {
            switch build {
            case .insufficientInput: return .nothingCaptured
            case .invalidInput: return .buildFailed("The scan data was unreadable.")
            case .exceedSceneSizeLimit: return .sceneTooLarge
            case .deviceNotSupported: return .deviceNotSupported
            case .internalError: return .buildFailed("")
            @unknown default: return .buildFailed("")
            }
        }
        if error is CancellationError { return .cancelled }
        return .unknown("")
    }
}
#endif
