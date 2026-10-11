import CoreGraphics
import CoreImage
import Foundation
import simd

#if canImport(RoomPlan)
import RoomPlan
#endif
#if canImport(ARKit)
import ARKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - The protocol

/// Anything that can produce a room scan.
///
/// The whole app talks to this and never to RoomPlan, which is what makes the
/// entire flow — coaching HUD, coverage bar, quality gate, conversion, physics —
/// developable and testable in the Simulator, where `RoomCaptureSession` reports
/// `isSupported == false` and `RoomBuilder` throws.
///
/// `@MainActor` is a requirement, not a style choice: the live implementation
/// wraps `RoomCaptureView` and `RoomCaptureSession`, both main-actor-bound and
/// neither `Sendable`. A non-isolated protocol here produces a conformance
/// diagnostic (`docs/research/api-roomplan.md` §7.4).
@MainActor
public protocol RoomScanning: AnyObject {

    /// Whether this scanner can actually run here and now.
    var isAvailable: Bool { get }

    /// True between `start()` and the terminal event.
    var isScanning: Bool { get }

    /// Begins a scan and returns its event stream.
    ///
    /// The stream always terminates with exactly one `.finished` or `.failed`
    /// event and then completes. Calling `start()` again after that begins a new
    /// scan with a new stream.
    func start() -> AsyncStream<ScanEvent>

    /// The user tapped "Done scanning": finish and deliver a result.
    func stop()

    /// The user backed out: abandon the scan and deliver `.failed(.cancelled)`.
    func cancel()
}

// MARK: - Choosing one

/// Returns the right scanner for this device, without the caller having to know
/// what "the right one" means.
///
/// `RoomCaptureSession.isSupported` is the single correct gate — it covers LiDAR,
/// OS version and the Simulator in one call, and a hand-rolled device allow-list
/// would rot. The `targetEnvironment` check is belt-and-braces so the Simulator
/// path is picked at compile time even if the runtime check ever changes.
@MainActor
public func makeRoomScanner(
    replaying room: ScannedRoom = RoomFixtures.dangerousBedroom,
    duration: TimeInterval = 20
) -> any RoomScanning {
    #if targetEnvironment(simulator)
    return ReplayScanner(room: room, duration: duration)
    #elseif canImport(RoomPlan) && canImport(UIKit)
    if RoomCaptureSession.isSupported {
        return RoomPlanScanner()
    }
    return ReplayScanner(room: room, duration: duration)
    #else
    return ReplayScanner(room: room, duration: duration)
    #endif
}

// MARK: - Replay

/// Replays a fixture room as if it were being scanned.
///
/// This is not a stub. It emits the same event stream in the same order at the
/// same sort of pace as the live scanner — walls first, then the floor, then
/// doors and windows, then furniture one piece at a time, with coaching
/// interleaved — so the coverage bar, the coaching pill, the live 3D preview and
/// the quality gate are all exercised for real in the Simulator and in previews.
///
/// It is also the demo path: someone who opens Tremor on a phone without LiDAR
/// still gets to watch a room assemble itself and then shake.
@MainActor
public final class ReplayScanner: RoomScanning {

    public let room: ScannedRoom
    /// Wall-clock seconds the replay takes end to end.
    public let duration: TimeInterval
    /// Whether to emit placeholder crops, so the vision pipeline's plumbing runs.
    public let emitsCrops: Bool

    public private(set) var isScanning = false
    public var isAvailable: Bool { true }

    private var task: Task<Void, Never>?
    private var continuation: AsyncStream<ScanEvent>.Continuation?
    private var finishEarly = false

    public init(
        room: ScannedRoom = RoomFixtures.dangerousBedroom,
        duration: TimeInterval = 20,
        emitsCrops: Bool = true
    ) {
        self.room = room
        self.duration = duration
        self.emitsCrops = emitsCrops
    }

    public func start() -> AsyncStream<ScanEvent> {
        cancel()
        let (stream, continuation) = AsyncStream<ScanEvent>.makeStream(
            bufferingPolicy: .unbounded)
        self.continuation = continuation
        self.finishEarly = false
        self.isScanning = true

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.run(continuation)
        }
        return stream
    }

    public func stop() {
        // "Done scanning" on a replay hands back the whole fixture — the point of
        // the demo path is to reach a complete room.
        finishEarly = true
    }

    public func cancel() {
        task?.cancel()
        task = nil
        if isScanning {
            continuation?.yield(.failed(.cancelled))
            continuation?.finish()
        }
        continuation = nil
        isScanning = false
    }

    // MARK: Timeline

    /// One beat of the replay: the geometry it reveals and the coaching that
    /// goes with it.
    private struct Beat {
        var surfaces: [RoomSurface] = []
        var object: ScannedObject?
        var cue: ScanCoach.Cue?
    }

    private func beats() -> [Beat] {
        var beats: [Beat] = []

        let walls = room.surfaces.filter { $0.kind == .wall }
        let floors = room.surfaces.filter { $0.kind == .floor || $0.kind == .ceiling }
        let openings = room.surfaces.filter {
            $0.kind == .door || $0.kind == .window || $0.kind == .opening
        }

        // A real scan finds walls first, because that is what the user is told
        // to point at.
        for (index, wall) in walls.enumerated() {
            var beat = Beat(surfaces: [wall])
            switch index {
            case 0: beat.cue = .normal
            case 1: beat.cue = .slowDown
            case 2: beat.cue = .moveCloseToWall
            default: beat.cue = .normal
            }
            beats.append(beat)
        }
        if !floors.isEmpty {
            beats.append(Beat(surfaces: floors, cue: .normal))
        }
        for opening in openings {
            beats.append(Beat(surfaces: [opening]))
        }
        // Then furniture, largest first — which is also the order RoomPlan tends
        // to resolve it in.
        let objects = room.objects.sorted { $0.extents.volume > $1.extents.volume }
        for (index, object) in objects.enumerated() {
            var beat = Beat(object: object)
            if index == 1 { beat.cue = .lowTexture }
            if index == 3 { beat.cue = .moveAwayFromWall }
            if index == objects.count - 1 { beat.cue = .normal }
            beats.append(beat)
        }
        return beats
    }

    private func run(_ continuation: AsyncStream<ScanEvent>.Continuation) async {
        continuation.onTermination = { _ in }
        continuation.yield(.started)
        continuation.yield(.coaching(ScanCoach.preparing))

        let beats = self.beats()
        let step = beats.isEmpty ? 0 : duration / Double(beats.count)
        let started = Date()

        var partial = ScannedRoom(
            id: room.id,
            name: room.name,
            kind: room.kind,
            building: room.building,
            surfaces: [],
            objects: [],
            createdAt: room.createdAt,
            updatedAt: room.updatedAt)
        var lastCue: ScanCoach.Cue?
        let crop = emitsCrops ? ReplayScanner.placeholderJPEG : Data()

        for beat in beats {
            if Task.isCancelled { return }
            if finishEarly { break }
            if step > 0 {
                try? await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
            }
            if Task.isCancelled { return }

            partial.surfaces.append(contentsOf: beat.surfaces)
            if let object = beat.object {
                partial.objects.append(object)
            }

            if let cue = beat.cue, cue != lastCue {
                lastCue = cue
                continuation.yield(.coaching(ScanCoach.coaching(for: cue)))
            }
            continuation.yield(.geometry(partial))
            let progress = ScanCoach.progress(
                for: partial, elapsed: Date().timeIntervalSince(started))
            continuation.yield(.progress(progress))

            if let object = beat.object, emitsCrops, !crop.isEmpty {
                continuation.yield(.capturedFrame(objectID: object.id, jpeg: crop))
            }
        }

        guard !Task.isCancelled else { return }

        var crops: [UUID: Data] = [:]
        if emitsCrops, !crop.isEmpty {
            for object in room.objects { crops[object.id] = crop }
        }

        continuation.yield(.coaching(ScanCoach.readyToFinish))
        continuation.yield(.finished(ScanResult(
            room: room,
            quality: ReplayScanner.quality(of: room),
            crops: crops,
            sourceIdentifiers: Dictionary(
                uniqueKeysWithValues: room.objects.map { ($0.id, $0.id) }),
            elapsed: Date().timeIntervalSince(started))))
        continuation.finish()
        isScanning = false
    }

    /// A fixture is by construction a clean scan, so the gate passes — but the
    /// numbers are computed, not asserted, so a deliberately broken fixture
    /// exercises the failure path too.
    static func quality(of room: ScannedRoom) -> ScanQualityReport {
        let walls = room.surfaces.filter { $0.kind == .wall }.count
        let floors = room.surfaces.filter { $0.kind == .floor }.count
        let openings = room.surfaces.filter {
            $0.kind == .door || $0.kind == .window || $0.kind == .opening
        }.count
        let area = room.floorArea

        var issues: [ScanQualityReport.Issue] = []
        if walls < 3 || floors < 1 || area < 4 || area > 120 { issues.append(.roomShape) }
        if room.objects.isEmpty { issues.append(.noObjects) }

        return ScanQualityReport(
            wallCount: walls,
            floorCount: floors,
            openingCount: openings,
            objectCount: room.objects.count,
            droppedObjectCount: 0,
            completeWallFraction: 1,
            highConfidenceFraction: 1,
            lowConfidenceFraction: 0,
            floorArea: area,
            issues: issues)
    }

    /// A small neutral JPEG standing in for a camera crop, so downstream code
    /// receives real bytes rather than a special case it will only meet in
    /// production.
    static let placeholderJPEG: Data = {
        let image = CIImage(color: CIColor(red: 0.86, green: 0.86, blue: 0.89))
            .cropped(to: CGRect(x: 0, y: 0, width: 96, height: 96))
        let context = CIContext(options: [.useSoftwareRenderer: true])
        return context.jpegRepresentation(
            of: image, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [:]) ?? Data()
    }()
}

// MARK: - Live

#if canImport(RoomPlan) && canImport(ARKit) && canImport(UIKit)

/// The real thing: RoomPlan on a LiDAR device.
///
/// It owns a `RoomCaptureView` because that is the only way to get Apple's
/// animated wall/object visualiser, its ARCoachingOverlay and its VoiceOver
/// guidance — none of which are worth rebuilding — and backs it with **our own**
/// `ARSession` so `ScanFramePump` can poll `currentFrame` without fighting
/// RoomPlan for the session's single delegate slot.
@MainActor
public final class RoomPlanScanner: NSObject, RoomScanning {

    public private(set) var isScanning = false
    public var isAvailable: Bool { RoomCaptureSession.isSupported }

    public override init() { super.init() }

    /// `RoomCaptureViewDelegate` inherits `NSCoding`. The scanner is never
    /// archived, so unarchiving one always fails.
    public init?(coder: NSCoder) { nil }

    /// The ARSession every transform in the scan is expressed in.
    public let arSession = ARSession()

    /// Hand this to a `UIViewRepresentable`. Created lazily so instantiating the
    /// scanner on an unsupported device costs nothing.
    public private(set) lazy var captureView: RoomCaptureView = {
        let view = RoomCaptureView(frame: .zero, arSession: arSession)
        view.delegate = self
        // Apple's own sample takes the session delegate as well; the visualiser
        // does not go through the public delegate, so the overlay is unaffected.
        view.captureSession.delegate = self
        return view
    }()

    /// The last raw room RoomPlan produced, for USDZ export — which is
    /// LiDAR-only and therefore cannot live anywhere else.
    public private(set) var capturedRoom: CapturedRoom?
    /// The opaque raw scan, persisted so a future SDK can re-run `RoomBuilder`.
    public private(set) var capturedRoomData: CapturedRoomData?

    /// Room metadata chosen on the building-context screen before the scan.
    public var roomName: String = "Room"
    public var roomKind: RoomKind = .other
    public var building: BuildingContext = BuildingContext()

    private var continuation: AsyncStream<ScanEvent>.Continuation?
    private var pump: ScanFramePump?
    private let crops = ScanCropIndex()
    private var liveObjects: [LiveObject] = []
    private var lastCue: ScanCoach.Cue?
    private var startedAt = Date()
    private var didFinish = false
    /// One crop-encode batch in flight at a time. Frames that arrive while a
    /// batch is encoding are dropped rather than queued — see `handle(_:)`.
    private var isEncoding = false

    private struct LiveObject {
        var identifier: UUID
        var centre: SIMD3<Float>
        var extents: SIMD3<Float>
        var yaw: Float
    }

    // MARK: Lifecycle

    public func start() -> AsyncStream<ScanEvent> {
        let (stream, continuation) = AsyncStream<ScanEvent>.makeStream(
            bufferingPolicy: .unbounded)
        self.continuation = continuation

        guard RoomCaptureSession.isSupported else {
            continuation.yield(.failed(.deviceNotSupported))
            continuation.finish()
            return stream
        }

        didFinish = false
        isScanning = true
        startedAt = Date()
        lastCue = nil
        liveObjects = []
        crops.removeAll()

        var configuration = RoomCaptureSession.Configuration()
        configuration.isCoachingEnabled = true
        captureView.captureSession.run(configuration: configuration)

        let pump = ScanFramePump(session: arSession, framesPerSecond: 1.0) { [weak self] snapshot in
            self?.handle(snapshot)
        }
        pump.start()
        self.pump = pump

        continuation.yield(.started)
        continuation.yield(.coaching(ScanCoach.preparing))
        return stream
    }

    public func stop() {
        guard isScanning else { return }
        pump?.stop()
        pump = nil
        // `pauseARSession: false` keeps the world origin alive, so a follow-up
        // room could join the same coordinate frame. We do not ship multi-room,
        // but destroying the option costs nothing to avoid.
        captureView.captureSession.stop(pauseARSession: false)
        // The result arrives via the RoomCaptureView delegate once RoomBuilder
        // has run; `isScanning` stays true until then.
    }

    public func cancel() {
        pump?.stop()
        pump = nil
        if isScanning {
            captureView.captureSession.stop(pauseARSession: true)
        }
        finish(with: .failed(.cancelled))
    }

    private func finish(with event: ScanEvent) {
        guard !didFinish else { return }
        didFinish = true
        isScanning = false
        continuation?.yield(event)
        continuation?.finish()
        continuation = nil
    }

    // MARK: Frames

    /// What the main actor decides about one object in one frame. Cheap: a
    /// projection and a score, both pure arithmetic.
    private struct PendingCrop: Sendable {
        var objectID: UUID
        var centre: SIMD3<Float>
        var extents: SIMD3<Float>
        var rect: CGRect
        var score: Double
    }

    private func handle(_ snapshot: ScanFramePump.Snapshot) {
        guard !liveObjects.isEmpty else { return }

        // Encoding is the expensive half and it must not happen here.
        //
        // A JPEG encode is a Core Image render of a ~0.2 MP region out of a
        // 4 MP YUV buffer — single-digit milliseconds each. With a dozen
        // objects in view that is a dozen of them per second on the main
        // thread, competing with `RoomCaptureView`'s 60 fps visualiser and with
        // ARKit's own main-thread work, during the one activity where a dropped
        // frame costs tracking quality. Deciding *which* frames are worth
        // encoding is arithmetic and stays here; the encode goes to a utility
        // task and comes back.
        var pending: [PendingCrop] = []
        for object in liveObjects {
            guard let box = CropGeometry.project(
                centre: object.centre,
                extents: object.extents,
                yaw: object.yaw,
                cameraTransform: snapshot.cameraTransform,
                intrinsics: snapshot.intrinsics,
                imageSize: snapshot.imageSize)
            else { continue }

            let candidate = FrameCandidate(
                objectID: object.identifier,
                box: box,
                imageSize: snapshot.imageSize,
                trackingQuality: snapshot.trackingQuality,
                sharpness: snapshot.sharpness)
            let score = CropScoring.score(candidate)
            guard score > 0 else { continue }
            // Only pay for the encode when this frame would actually win.
            if let existing = crops.crop(for: object.identifier), existing.score >= score {
                continue
            }

            pending.append(PendingCrop(
                objectID: object.identifier,
                centre: object.centre,
                extents: object.extents,
                rect: CropGeometry.inflate(box.rect, by: 0.12, clampedTo: snapshot.imageSize),
                score: score))
        }
        guard !pending.isEmpty else { return }

        // Drop the frame rather than queue it. The index keeps the best frame
        // per object, so a skipped frame costs nothing but a slightly worse
        // crop; a backlog costs memory (each held snapshot is a 4 MP buffer)
        // and would keep encoding long after the user pressed Done.
        guard !isEncoding else { return }
        isEncoding = true

        let buffer = snapshot.pixelBuffer
        Task.detached(priority: .utility) { [weak self] in
            var encoded: [(PendingCrop, Data)] = []
            for item in pending {
                if let jpeg = CropEncoder.jpeg(from: buffer, cropping: item.rect) {
                    encoded.append((item, jpeg))
                }
            }
            await self?.finishEncoding(encoded)
        }
    }

    private func finishEncoding(_ encoded: [(PendingCrop, Data)]) {
        isEncoding = false
        guard isScanning else { return }
        for (item, jpeg) in encoded {
            let crop = ScanCrop(
                sourceIdentifier: item.objectID,
                centre: item.centre,
                extents: item.extents,
                jpeg: jpeg,
                score: item.score)
            // `offer` re-checks the score, so a crop that lost a race while it
            // was being encoded is discarded here rather than overwriting a
            // better one.
            if crops.offer(crop) {
                continuation?.yield(.capturedFrame(objectID: item.objectID, jpeg: jpeg))
            }
        }
    }

    // MARK: Live geometry

    fileprivate func handleLiveUpdate(_ room: CapturedRoom) {
        liveObjects = room.objects.map {
            LiveObject(
                identifier: $0.identifier,
                centre: RawScanGeometry.centre(of: $0.transform),
                extents: $0.dimensions,
                yaw: RawScanGeometry.yaw(of: $0.transform))
        }

        let raw = CapturedRoomConverter.raw(from: room)
        let converted = CapturedRoomConverter.convert(
            raw, name: roomName, kind: roomKind, building: building)
        continuation?.yield(.geometry(converted.room))
        continuation?.yield(.progress(ScanCoach.progress(
            walls: raw.walls.count,
            completeWalls: raw.walls.filter { $0.completedEdgeCount >= 4 }.count,
            floors: raw.floors.count,
            openings: raw.doors.count + raw.windows.count + raw.openings.count,
            objects: converted.room.objects.count,
            elapsed: Date().timeIntervalSince(startedAt))))
    }

    fileprivate func handleInstruction(_ instruction: RoomCaptureSession.Instruction) {
        let cue = ScanCoach.cue(for: instruction)
        guard cue != lastCue else { return }
        lastCue = cue
        continuation?.yield(.coaching(ScanCoach.coaching(for: cue)))
    }

    fileprivate func handleFinalRoom(_ room: CapturedRoom) {
        capturedRoom = room
        let raw = CapturedRoomConverter.raw(from: room)
        let converted = CapturedRoomConverter.convert(
            raw, name: roomName, kind: roomKind, building: building)

        guard converted.quality.isUsable else {
            finish(with: .failed(.nothingCaptured))
            return
        }

        // Crops were captured in RoomPlan's world frame; the converted room has
        // been rebased onto its own floor. Move the crops into the same frame
        // before matching, or every crop lands on the wrong object.
        let origin = CapturedRoomConverter.origin(of: raw, options: .default)
        let rebased = crops.crops.map { crop -> ScanCrop in
            var c = crop
            c.centre = origin.apply(crop.centre)
            return c
        }
        let matched = ScanCropIndex.rekey(
            crops: rebased,
            to: converted.room,
            objectIDsBySource: converted.objectIDsBySource)

        finish(with: .finished(ScanResult(
            room: converted.room,
            quality: converted.quality,
            crops: matched,
            sourceIdentifiers: converted.sourceIdentifiers,
            elapsed: Date().timeIntervalSince(startedAt))))
    }

    fileprivate func handleFailure(_ error: any Error) {
        finish(with: .failed(ScanCoach.scanError(from: error)))
    }

    fileprivate func storeRawData(_ data: CapturedRoomData) {
        capturedRoomData = data
    }
}

// MARK: Delegates

extension RoomPlanScanner: RoomCaptureSessionDelegate {

    public nonisolated func captureSession(
        _ session: RoomCaptureSession, didUpdate room: CapturedRoom
    ) {
        Task { @MainActor in self.handleLiveUpdate(room) }
    }

    public nonisolated func captureSession(
        _ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction
    ) {
        Task { @MainActor in self.handleInstruction(instruction) }
    }

    public nonisolated func captureSession(
        _ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: (any Error)?
    ) {
        Task { @MainActor in
            self.storeRawData(data)
            if let error { self.handleFailure(error) }
        }
    }
}

extension RoomPlanScanner: RoomCaptureViewDelegate {

    /// `RoomCaptureViewDelegate` inherits `NSCoding` for historical reasons.
    /// The scanner is never archived, so this is the minimum legal conformance.
    public nonisolated func encode(with coder: NSCoder) {}


    /// Returning true lets RoomPlan run `RoomBuilder(options: [.beautifyObjects])`
    /// itself and present the finished room — which is also what drives the
    /// view's closing animation.
    public nonisolated func captureView(
        shouldPresent roomDataForProcessing: CapturedRoomData, error: (any Error)?
    ) -> Bool {
        true
    }

    public nonisolated func captureView(
        didPresent processedResult: CapturedRoom, error: (any Error)?
    ) {
        Task { @MainActor in
            if let error {
                self.handleFailure(error)
            } else {
                self.handleFinalRoom(processedResult)
            }
        }
    }
}

#endif
