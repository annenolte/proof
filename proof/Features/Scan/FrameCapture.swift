import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import simd

#if canImport(ARKit)
import ARKit
#endif
#if canImport(QuartzCore)
import QuartzCore
#endif

// MARK: - Projecting a scanned box into the camera image

/// Where an object's bounding box lands in the camera image.
public struct ProjectedBox: Hashable, Sendable {
    /// Union of the eight projected corners, in image pixels, origin top-left.
    public var rect: CGRect
    /// Every corner is in front of the camera. When false the projection is
    /// meaningless and the candidate must be discarded.
    public var isFullyInFront: Bool
    /// The whole box lies inside the image.
    public var isFullyOnScreen: Bool

    public init(rect: CGRect, isFullyInFront: Bool, isFullyOnScreen: Bool) {
        self.rect = rect
        self.isFullyInFront = isFullyInFront
        self.isFullyOnScreen = isFullyOnScreen
    }
}

/// Pinhole projection and crop framing, kept free of ARKit so it can be tested.
///
/// ARKit's camera looks down its own **−Z**, with +X right and +Y up; the image
/// has its origin at the top-left with y increasing downward. Getting that flip
/// wrong mirrors every crop vertically, which is invisible in a thumbnail and
/// fatal to a vision model.
public enum CropGeometry {

    /// Projects a gravity-aligned cuboid into the camera image.
    ///
    /// - Parameters:
    ///   - centre: box centroid in world metres.
    ///   - extents: full extents in metres.
    ///   - yaw: rotation about world +Y, the `Placement` convention.
    ///   - cameraTransform: camera→world, i.e. `ARFrame.camera.transform`.
    ///   - intrinsics: `ARFrame.camera.intrinsics`, for the image size given.
    ///   - imageSize: the size the intrinsics are expressed in, pixels.
    public static func project(
        centre: SIMD3<Float>,
        extents: SIMD3<Float>,
        yaw: Float,
        cameraTransform: simd_float4x4,
        intrinsics: simd_float3x3,
        imageSize: CGSize
    ) -> ProjectedBox? {
        let view = cameraTransform.inverse
        let c = cos(yaw), s = sin(yaw)
        let half = extents / 2

        let fx = intrinsics.columns.0.x
        let fy = intrinsics.columns.1.y
        let cx = intrinsics.columns.2.x
        let cy = intrinsics.columns.2.y
        guard fx > 0, fy > 0 else { return nil }

        var minX = Float.greatestFiniteMagnitude, maxX = -Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude, maxY = -Float.greatestFiniteMagnitude
        var allInFront = true

        for sx in [-1, 1] as [Float] {
            for sy in [-1, 1] as [Float] {
                for sz in [-1, 1] as [Float] {
                    let local = SIMD3(sx * half.x, sy * half.y, sz * half.z)
                    // Yaw about +Y, matching `Placement.transform`'s basis
                    // (local +X → (cos, 0, sin) in our recovered convention).
                    let rotated = SIMD3(
                        local.x * c + local.z * s,
                        local.y,
                        local.x * s - local.z * c
                    )
                    let world = centre + rotated
                    let p4 = view * SIMD4<Float>(world.x, world.y, world.z, 1)
                    let depth = -p4.z                       // metres in front
                    guard depth > 0.01 else { allInFront = false; continue }
                    let u = fx * (p4.x / depth) + cx
                    let v = fy * (-p4.y / depth) + cy       // image y grows down
                    minX = min(minX, u); maxX = max(maxX, u)
                    minY = min(minY, v); maxY = max(maxY, v)
                }
            }
        }

        guard minX <= maxX, minY <= maxY, minX.isFinite, maxY.isFinite else { return nil }

        let rect = CGRect(
            x: CGFloat(minX), y: CGFloat(minY),
            width: CGFloat(maxX - minX), height: CGFloat(maxY - minY))
        let onScreen = rect.minX >= 0 && rect.minY >= 0
            && rect.maxX <= imageSize.width && rect.maxY <= imageSize.height

        return ProjectedBox(
            rect: rect, isFullyInFront: allInFront, isFullyOnScreen: allInFront && onScreen)
    }

    /// Grows a rect by a fraction on every side and clips it to the image.
    /// A 12 % margin keeps the object's silhouette off the crop's edge, which is
    /// what the vision model needs to see its shape.
    public static func inflate(
        _ rect: CGRect, by fraction: CGFloat, clampedTo size: CGSize
    ) -> CGRect {
        let dx = rect.width * fraction
        let dy = rect.height * fraction
        var r = rect.insetBy(dx: -dx, dy: -dy)
        r = r.intersection(CGRect(origin: .zero, size: size))
        return r.isNull ? .zero : r
    }
}

/// One frame's worth of evidence about how well an object is framed. Deliberately
/// free of image data so scoring can be tested and reasoned about on its own.
public struct FrameCandidate: Hashable, Sendable {
    public var objectID: UUID
    public var box: ProjectedBox
    public var imageSize: CGSize
    /// 0…1. Derived on device from tracking state and exposure.
    public var trackingQuality: Double
    /// 0…1. A long exposure means a motion-blurred frame.
    public var sharpness: Double

    public init(
        objectID: UUID,
        box: ProjectedBox,
        imageSize: CGSize,
        trackingQuality: Double = 1,
        sharpness: Double = 1
    ) {
        self.objectID = objectID
        self.box = box
        self.imageSize = imageSize
        self.trackingQuality = trackingQuality
        self.sharpness = sharpness
    }
}

/// Scores how good a portrait of an object a frame is.
///
/// Bigger is better, centred is better, sharp and well-tracked is better, and a
/// box running off the edge of the image is heavily penalised — but not
/// disqualified, because a sofa two metres away may never fit inside the frame
/// and half a sofa is still better than nothing.
public enum CropScoring {

    /// Weight applied to a box that is clipped by the image edge.
    public static let clippedPenalty = 0.2

    public static func score(_ candidate: FrameCandidate) -> Double {
        guard candidate.box.isFullyInFront,
              candidate.imageSize.width > 0, candidate.imageSize.height > 0
        else { return 0 }

        let imageArea = Double(candidate.imageSize.width * candidate.imageSize.height)
        let clipped = candidate.box.rect.intersection(
            CGRect(origin: .zero, size: candidate.imageSize))
        guard !clipped.isNull, clipped.width > 1, clipped.height > 1 else { return 0 }

        let areaFraction = min(1.0, Double(clipped.width * clipped.height) / imageArea)

        // Distance of the box centre from the image centre, normalised by the
        // half-diagonal so it is 1 at a corner.
        let centre = CGPoint(x: clipped.midX, y: clipped.midY)
        let imageCentre = CGPoint(
            x: candidate.imageSize.width / 2, y: candidate.imageSize.height / 2)
        let dx = Double(centre.x - imageCentre.x)
        let dy = Double(centre.y - imageCentre.y)
        let halfDiagonal = sqrt(
            Double(imageCentre.x * imageCentre.x + imageCentre.y * imageCentre.y))
        let centrality = halfDiagonal > 0
            ? min(1.0, sqrt(dx * dx + dy * dy) / halfDiagonal)
            : 0

        let framing = candidate.box.isFullyOnScreen ? 1.0 : clippedPenalty

        return areaFraction
            * (1 - 0.6 * centrality)
            * max(0, min(1, candidate.trackingQuality))
            * max(0, min(1, candidate.sharpness))
            * framing
    }
}

// MARK: - Encoding

/// Turns a camera pixel buffer and a crop rect into JPEG bytes.
///
/// Re-encoding from the pixel buffer rather than forwarding a camera JPEG is a
/// privacy requirement, not an optimisation: it strips every EXIF field,
/// including the GPS tag that would otherwise leave the device attached to a
/// photograph of someone's bedroom.
public enum CropEncoder {

    /// ≈0.8 MP is what the vision model is fed; anything larger costs tokens and
    /// changes no answer (`docs/research/api-vision-llm.md` §"detail: low").
    public static let targetPixelCount: Double = 800_000
    public static let jpegQuality: Double = 0.8

    private static let context: CIContext = CIContext(options: [.useSoftwareRenderer: false])

    /// - Parameters:
    ///   - rect: crop rect in image pixels, origin **top-left**.
    public static func jpeg(
        from pixelBuffer: CVPixelBuffer,
        cropping rect: CGRect,
        quality: Double = jpegQuality,
        targetPixels: Double = targetPixelCount
    ) -> Data? {
        let full = CIImage(cvPixelBuffer: pixelBuffer)
        let bounds = full.extent
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        // Core Image's origin is bottom-left; ours is top-left.
        let flipped = CGRect(
            x: rect.minX,
            y: bounds.height - rect.maxY,
            width: rect.width,
            height: rect.height)
        let crop = flipped.intersection(bounds)
        guard !crop.isNull, crop.width >= 2, crop.height >= 2 else { return nil }

        var image = full.cropped(to: crop)
        // Re-origin so the crop starts at (0,0); otherwise the JPEG carries the
        // original frame's extent and encodes mostly empty pixels.
        image = image.transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))

        let pixels = Double(crop.width * crop.height)
        if pixels > targetPixels {
            let scale = CGFloat(sqrt(targetPixels / pixels))
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        let qualityKey = CIImageRepresentationOption(
            rawValue: kCGImageDestinationLossyCompressionQuality as String)
        return context.jpegRepresentation(
            of: image,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: [qualityKey: quality])
    }
}

// MARK: - Keeping the best crop per object

/// Holds the single best camera crop for every object seen during a scan.
///
/// **Memory.** No `ARFrame` and no `CVPixelBuffer` is ever retained: a candidate
/// is cropped and JPEG-encoded the moment it arrives, and only the bytes are
/// kept. A typical crop is 25–60 KB, so a 20-object room costs about a megabyte.
/// Both the crop count and the total byte budget are capped, and the
/// lowest-scoring crop is evicted first — so a pathological scan that finds two
/// hundred "objects" cannot grow without bound.
@MainActor
public final class ScanCropIndex {

    private struct Entry {
        var crop: ScanCrop
        var bytes: Int
    }

    public let maximumCrops: Int
    public let maximumBytes: Int

    private var entries: [UUID: Entry] = [:]

    public init(maximumCrops: Int = 64, maximumBytes: Int = 8 * 1024 * 1024) {
        self.maximumCrops = maximumCrops
        self.maximumBytes = maximumBytes
    }

    public var count: Int { entries.count }
    public var totalBytes: Int { entries.values.reduce(0) { $0 + $1.bytes } }
    public var crops: [ScanCrop] { entries.values.map(\.crop) }

    public func crop(for sourceIdentifier: UUID) -> ScanCrop? {
        entries[sourceIdentifier]?.crop
    }

    /// Offers a crop. Returns true when it displaced whatever was there before,
    /// which is the signal to emit a `.capturedFrame` event.
    @discardableResult
    public func offer(_ crop: ScanCrop) -> Bool {
        if let existing = entries[crop.sourceIdentifier], existing.crop.score >= crop.score {
            return false
        }
        entries[crop.sourceIdentifier] = Entry(crop: crop, bytes: crop.jpeg.count)
        evictIfNeeded()
        return entries[crop.sourceIdentifier] != nil
    }

    private func evictIfNeeded() {
        while entries.count > maximumCrops || totalBytes > maximumBytes {
            guard let worst = entries.min(by: { $0.value.crop.score < $1.value.crop.score })
            else { return }
            entries.removeValue(forKey: worst.key)
        }
    }

    public func removeAll() { entries.removeAll() }

    /// Re-keys the crops onto the final room's objects.
    ///
    /// This is necessary, not defensive: `RoomBuilder` **regenerates every
    /// identifier** when it produces the final `CapturedRoom`, so the UUIDs the
    /// crops were captured against no longer exist. Identity is re-established
    /// geometrically — an object that has not moved between the last live update
    /// and the final build is the same object.
    public func rekey(
        to room: ScannedRoom, objectIDsBySource: [UUID: UUID] = [:]
    ) -> [UUID: Data] {
        ScanCropIndex.rekey(crops: crops, to: room, objectIDsBySource: objectIDsBySource)
    }

    /// Maximum distance, in metres, between a crop's captured centroid and a
    /// final object's centroid for them to be considered the same thing.
    public static let matchRadius: Float = 0.6

    public static func rekey(
        crops: [ScanCrop], to room: ScannedRoom, objectIDsBySource: [UUID: UUID] = [:]
    ) -> [UUID: Data] {
        var result: [UUID: Data] = [:]
        var unmatched: [ScanCrop] = []

        for crop in crops {
            if let id = objectIDsBySource[crop.sourceIdentifier],
               room.object(id: id) != nil {
                result[id] = crop.jpeg
            } else {
                unmatched.append(crop)
            }
        }

        guard !unmatched.isEmpty else { return result }

        // Best-scoring crops claim their object first, so a good portrait is
        // never displaced by a marginal one.
        for crop in unmatched.sorted(by: { $0.score > $1.score }) {
            var best: (id: UUID, cost: Float)?
            for object in room.objects where result[object.id] == nil {
                let d = simd_distance(object.placement.centre, crop.centre)
                guard d <= matchRadius else { continue }
                // Prefer a similar-sized box: two objects can share a centroid
                // (a television on a dresser) and size is what tells them apart.
                let ratio = sizeMismatch(object.extents.simd, crop.extents)
                guard ratio <= 0.6 else { continue }
                let cost = d + ratio
                if best == nil || cost < best!.cost { best = (object.id, cost) }
            }
            if let best { result[best.id] = crop.jpeg }
        }
        return result
    }

    /// 0 for identical boxes, growing with relative size difference.
    static func sizeMismatch(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        var total: Float = 0
        for i in 0..<3 {
            let x = max(a[i], 1e-3), y = max(b[i], 1e-3)
            total += abs(x - y) / max(x, y)
        }
        return total / 3
    }
}

// MARK: - Pulling frames out of a live scan

#if canImport(ARKit) && canImport(QuartzCore)

/// Polls camera frames from a running scan for the vision pipeline.
///
/// It deliberately does **not** become the `ARSession` delegate: RoomPlan owns
/// that single slot, and taking it starves RoomPlan of frames and collapses scan
/// quality. Polling `currentFrame` from a display link has no such contention and
/// rate-limits naturally, which matters because the vision pass wants about one
/// frame a second, not sixty.
///
/// Every emitted buffer is a deep copy. ARKit recycles `capturedImage`, and
/// holding one past the callback produces "the delegate of ARSession is
/// retaining N ARFrames", which stalls the camera and overheats the device.
@MainActor
public final class ScanFramePump: NSObject {

    /// A frame, detached from ARKit. `@unchecked Sendable` because
    /// `CVPixelBuffer` is a CoreFoundation type: this one is a private deep copy
    /// nothing else can reach, and it is never mutated after construction.
    public struct Snapshot: @unchecked Sendable {
        public var pixelBuffer: CVPixelBuffer
        /// Camera→world, in the same frame as every `CapturedRoom` transform.
        public var cameraTransform: simd_float4x4
        public var intrinsics: simd_float3x3
        public var imageSize: CGSize
        public var timestamp: TimeInterval
        /// 0…1, from `ARCamera.trackingState`.
        public var trackingQuality: Double
        /// 0…1, from exposure duration — a proxy for motion blur.
        public var sharpness: Double
    }

    private weak var session: ARSession?
    private var link: CADisplayLink?
    private var lastEmitted: TimeInterval = 0
    private let interval: TimeInterval
    private let onSnapshot: (Snapshot) -> Void

    public init(
        session: ARSession,
        framesPerSecond: Double = 1.0,
        onSnapshot: @escaping (Snapshot) -> Void
    ) {
        self.session = session
        self.interval = 1.0 / max(framesPerSecond, 0.1)
        self.onSnapshot = onSnapshot
        super.init()
    }

    public func start() {
        stop()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 15)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    public func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick() {
        guard let frame = session?.currentFrame else { return }
        guard frame.timestamp - lastEmitted >= interval else { return }
        let quality = ScanFramePump.trackingQuality(frame.camera.trackingState)
        guard quality > 0 else { return }
        lastEmitted = frame.timestamp

        guard let copy = ScanFramePump.deepCopy(frame.capturedImage) else { return }
        let width = CVPixelBufferGetWidth(copy)
        let height = CVPixelBufferGetHeight(copy)

        // Anything longer than 1/30 s is visibly smeared when the phone is
        // moving, which is exactly when a scan is happening.
        let exposure = frame.camera.exposureDuration
        let sharpness = exposure <= 1.0 / 30 ? 1.0 : max(0.3, (1.0 / 30) / exposure)

        onSnapshot(Snapshot(
            pixelBuffer: copy,
            cameraTransform: frame.camera.transform,
            intrinsics: frame.camera.intrinsics,
            imageSize: CGSize(width: width, height: height),
            timestamp: frame.timestamp,
            trackingQuality: quality,
            sharpness: sharpness))
        // `frame` dies here and ARKit reclaims it immediately.
    }

    static func trackingQuality(_ state: ARCamera.TrackingState) -> Double {
        switch state {
        case .normal: return 1.0
        case .limited: return 0.4
        case .notAvailable: return 0.0
        @unknown default: return 0.4
        }
    }

    /// ARKit recycles `capturedImage`; a retained buffer stalls the pipeline.
    static func deepCopy(_ src: CVPixelBuffer) -> CVPixelBuffer? {
        var dst: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            CVPixelBufferGetWidth(src),
            CVPixelBufferGetHeight(src),
            CVPixelBufferGetPixelFormatType(src),
            attrs as CFDictionary,
            &dst)
        guard status == kCVReturnSuccess, let dst else { return nil }

        CVPixelBufferLockBaseAddress(src, .readOnly)
        CVPixelBufferLockBaseAddress(dst, [])
        defer {
            CVPixelBufferUnlockBaseAddress(dst, [])
            CVPixelBufferUnlockBaseAddress(src, .readOnly)
        }

        let planeCount = CVPixelBufferGetPlaneCount(src)
        if planeCount == 0 {
            // ARKit gives biplanar 420f, but a packed format (BGRA) has no
            // planes at all and `…OfPlane` returns NULL for it.
            guard let s = CVPixelBufferGetBaseAddress(src),
                  let d = CVPixelBufferGetBaseAddress(dst) else { return nil }
            let sBytes = CVPixelBufferGetBytesPerRow(src)
            let dBytes = CVPixelBufferGetBytesPerRow(dst)
            let width = min(sBytes, dBytes)
            for row in 0..<CVPixelBufferGetHeight(src) {
                memcpy(d.advanced(by: row * dBytes), s.advanced(by: row * sBytes), width)
            }
            return dst
        }
        for p in 0..<planeCount {
            guard let s = CVPixelBufferGetBaseAddressOfPlane(src, p),
                  let d = CVPixelBufferGetBaseAddressOfPlane(dst, p) else { return nil }
            let sBytes = CVPixelBufferGetBytesPerRowOfPlane(src, p)
            let dBytes = CVPixelBufferGetBytesPerRowOfPlane(dst, p)
            let height = CVPixelBufferGetHeightOfPlane(src, p)
            let width = min(sBytes, dBytes)
            for row in 0..<height {
                memcpy(d.advanced(by: row * dBytes), s.advanced(by: row * sBytes), width)
            }
        }
        return dst
    }
}

#endif
