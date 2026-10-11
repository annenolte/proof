import AVFoundation
import Photos
import RealityKit
import UIKit

// Records each earthquake as a short video, so the results sheet can offer "Save clip".
//
// The room records itself whenever it shakes; nobody has to remember to press record before
// the thing worth recording happens. Frames come from `ARView.snapshot`, which works on a
// device and on the Simulator alike. The post-process hook would give cleaner access to the
// GPU frame, but it traps on the Simulator, and the demo has to run on both.
//
// Cost is kept off the frame that matters: snapshots are taken at 24 fps rather than at
// display rate, scaled to 720 px wide, converted and encoded on a background queue, and a
// snapshot is skipped outright while the previous one is still being converted. A dropped
// frame in the clip is invisible; a dropped frame in the live room is not.
//
// The clip is the 3D room only — the HUD is SwiftUI on top of the view and is not in the
// snapshot. It is silent: the rumble is synthesised live and is not captured.

@MainActor
@Observable
final class DemoClipRecorder {

    enum State: Equatable {
        case idle
        case recording
        /// The writer is closing the file.
        case finishing
        case ready(URL)
        case failed
    }

    private(set) var state: State = .idle

    static let framesPerSecond = 24.0
    static let maximumWidth = 720
    /// How long recording continues after the shaking stops, so things still falling are
    /// in the clip.
    static let settleTail: Double = 1.5

    private let queue = DispatchQueue(label: "tremor.clip-recorder")
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var outputURL: URL?

    private var startTime: CFTimeInterval = 0
    private var lastCapture: CFTimeInterval = -.infinity
    /// Snapshots requested but not yet written. A few may overlap: on the Simulator one
    /// snapshot takes several frame times, and waiting for each in turn held the clip to
    /// under 8 fps.
    private var framesInFlight = 0
    private static let maximumInFlight = 3
    /// Frames must reach the writer in time order; one that arrives late is dropped.
    private var lastAppended = CMTime.negativeInfinity
    private var framesWritten = 0
    private var finishTask: Task<Void, Never>?

    // MARK: - Control

    func start() {
        discard()
        state = .recording
        startTime = CACurrentMediaTime()
        lastCapture = -.infinity
        lastAppended = .negativeInfinity
        framesWritten = 0
    }

    /// Called once per rendered frame. Takes a snapshot when one is due and none is pending.
    func captureIfDue(from view: ARView) {
        guard state == .recording, framesInFlight < Self.maximumInFlight else { return }
        let now = CACurrentMediaTime()
        guard now - lastCapture >= 1 / Self.framesPerSecond else { return }
        lastCapture = now
        framesInFlight += 1
        let time = CMTime(seconds: now - startTime, preferredTimescale: 600)

        view.snapshot(saveToHDR: false) { [weak self] image in
            // The callback's queue is not documented; everything below touches main-actor
            // state, so it goes to the main queue explicitly.
            DispatchQueue.main.async { self?.received(image, at: time) }
        }
    }

    private func received(_ image: UIImage?, at time: CMTime) {
        framesInFlight = max(framesInFlight - 1, 0)
        guard state == .recording, let cgImage = image?.cgImage, time > lastAppended else { return }
        prepareWriterIfNeeded(for: cgImage)
        guard let input, let adaptor else { return }
        lastAppended = time
        queue.async {
            let written = Self.append(cgImage, at: time, input: input, adaptor: adaptor)
            DispatchQueue.main.async {
                if written { self.framesWritten += 1 }
            }
        }
    }

    /// Stops after `settleTail`, then closes the file.
    func finishAfterSettling() {
        guard state == .recording else { return }
        finishTask?.cancel()
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.settleTail))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    /// Throws away the current clip, recorded or in progress. Called when the room is reset,
    /// so the sheet never offers a clip of a run that is no longer on screen.
    func discard() {
        finishTask?.cancel()
        finishTask = nil
        if writer?.status == .writing { writer?.cancelWriting() }
        if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
        if case .ready(let url) = state { try? FileManager.default.removeItem(at: url) }
        writer = nil
        input = nil
        adaptor = nil
        outputURL = nil
        framesInFlight = 0
        state = .idle
    }

    private func finish() {
        guard state == .recording else { return }
        guard let writer, let input, framesWritten > 0 else {
            discard()
            state = .failed
            return
        }
        state = .finishing
        let url = outputURL
        queue.async {
            input.markAsFinished()
            writer.finishWriting { [weak self] in
                let ok = writer.status == .completed
                DispatchQueue.main.async {
                    guard let self, self.writer === writer else { return }
                    self.state = ok ? url.map(State.ready) ?? .failed : .failed
                    // The file now belongs to `state`; `discard` removes it from there.
                    self.outputURL = nil
                }
            }
        }
    }

    // MARK: - Writer

    private func prepareWriterIfNeeded(for image: CGImage) {
        guard writer == nil, state == .recording else { return }

        let scale = min(1, Double(Self.maximumWidth) / Double(image.width))
        // H.264 wants even dimensions.
        let width = Int(Double(image.width) * scale) & ~1
        let height = Int(Double(image.height) * scale) & ~1

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tremor-quake-\(UUID().uuidString).mp4")
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            state = .failed
            return
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000],
        ])
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ])
        guard writer.canAdd(input) else {
            state = .failed
            return
        }
        writer.add(input)
        guard writer.startWriting() else {
            state = .failed
            return
        }
        writer.startSession(atSourceTime: .zero)

        self.writer = writer
        self.input = input
        self.adaptor = adaptor
        self.outputURL = url
    }

    /// The backdrop the explorer draws behind the cut-away room. The view itself is clear,
    /// so without this the clip's background would be black where the screen is grey.
    private nonisolated static let backdrop: [CGColor] = [
        CGColor(srgbRed: 0.20, green: 0.20, blue: 0.24, alpha: 1),
        CGColor(srgbRed: 0.44, green: 0.44, blue: 0.48, alpha: 1),
        CGColor(srgbRed: 0.30, green: 0.29, blue: 0.33, alpha: 1),
    ]

    private nonisolated static func append(
        _ image: CGImage, at time: CMTime,
        input: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor
    ) -> Bool {
        guard input.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool else { return false }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return false }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return false }

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        if let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: backdrop as CFArray, locations: [0, 0.5, 1]) {
            // Core Graphics is y-up, so the gradient runs from the top edge down.
            context.drawLinearGradient(
                gradient, start: CGPoint(x: 0, y: rect.maxY), end: .zero, options: [])
        }
        context.interpolationQuality = .medium
        context.draw(image, in: rect)

        return adaptor.append(buffer, withPresentationTime: time)
    }
}

// MARK: - Saving

enum DemoClipSaver {

    enum Failure: Error { case notAllowed, failed }

    /// Adds the clip to the photo library. Asks for add-only access, which is what
    /// `NSPhotoLibraryAddUsageDescription` in Info.plist already explains.
    static func save(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.notAllowed }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
            }
        } catch {
            throw Failure.failed
        }
    }
}
