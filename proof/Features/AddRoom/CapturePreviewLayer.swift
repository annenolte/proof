//
//  CapturePreviewLayer.swift
//  Tremor — Add Room / the two things that can fill the viewfinder
//
//  The guided capture screen shows exactly one of two moving images behind its
//  chrome: the live back camera, or a video file playing back. Both are
//  CoreAnimation layers that SwiftUI cannot host natively, so both live here as
//  `UIViewRepresentable`s over a `UIView` whose `layerClass` *is* the layer.
//  Hosting the layer as the view's own backing layer — rather than adding a
//  sublayer and resizing it in `layoutSubviews` — is what makes the feed track
//  rotation and safe-area changes without a frame-behind stutter.
//
//  WHY THE SESSION IS A SEPARATE OBSERVABLE OBJECT
//  ------------------------------------------------
//  `AVCaptureSession.startRunning()` blocks for tens of milliseconds while it
//  negotiates with the hardware, and adding an input does the same. Doing either
//  on the main thread drops frames in the presenting animation, so `CameraFeed`
//  does all of it on one private serial queue and publishes only a small
//  `State` back to the main actor. The view observes `state`; it never touches
//  the session except to hand it to the preview layer.
//
//  THE SIMULATOR HAS NO CAMERA, AND THAT IS A SUPPORTED STATE
//  ----------------------------------------------------------
//  `AVCaptureDevice.default(...)` returns nil in the Simulator, and a user can
//  refuse or be restricted from the camera on a real device. None of those are
//  errors here: `CameraFeed` reports `.unavailable(_)`, the screen draws its
//  calm backdrop instead, and every piece of coaching chrome keeps working. The
//  screen is fully usable and screenshot-able with no camera at all, which is
//  how it gets verified on a machine that has none.
//
//  Nothing in this file knows what a room is, what coaching is, or what a demo
//  is. It renders pixels.
//

// AVFoundation predates strict concurrency checking and `AVCaptureSession` /
// `AVCaptureDevice` are not marked `Sendable`, so handing either to the session
// queue below raises a warning the framework gives us no way to satisfy.
//
// The pattern here is the one Apple documents, and it is safe for the reason the
// annotation is meant for: **every mutating call on the session happens on
// `sessionQueue` and nowhere else** — `beginConfiguration`, `addInput`,
// `commitConfiguration`, `startRunning`, `stopRunning`. The main actor only ever
// holds the reference, publishes a derived `State`, and hands the session to
// `AVCaptureVideoPreviewLayer`, which is documented to accept it from any thread.
// Break that discipline and this annotation starts hiding a real race, so keep
// session mutation on the queue.
@preconcurrency import AVFoundation
import Observation
import SwiftUI
import UIKit

// MARK: - The live camera

/// Owns the `AVCaptureSession` for the guided capture screen and reduces it to
/// a state a SwiftUI view can switch on.
///
/// ```swift
/// @State private var camera = CameraFeed()
/// ...
/// .onAppear { camera.start() }
/// .onDisappear { camera.stop() }
/// ```
@MainActor
@Observable
final class CameraFeed {

    /// Why there is no picture. Each case is a thing the screen can say
    /// something true about, which is why they are distinguished at all.
    enum Unavailable: Equatable {
        /// No back camera exists — the Simulator, and nothing else in practice.
        case noDevice
        /// The user said no, or has not said yes.
        case notAuthorised
        /// Screen Time or an MDM profile forbids the camera.
        case restricted
        /// The device exists and we are allowed, and it still would not start.
        case configurationFailed
    }

    enum State: Equatable {
        case idle
        /// Authorisation or hardware negotiation is in flight.
        case starting
        case running
        case unavailable(Unavailable)
    }

    private(set) var state: State = .idle

    /// Handed to `CameraPreviewLayer` once `state == .running`. Deliberately not
    /// observed: the session is a reference the view passes through, and
    /// observing it would republish on every internal change for no reason.
    @ObservationIgnored private(set) var session: AVCaptureSession?

    /// Every `AVCaptureSession` mutation happens here. Apple's own guidance:
    /// one serial queue, never the main one.
    @ObservationIgnored private let sessionQueue =
        DispatchQueue(label: "com.annenolte.proof.capture-session")

    var isRunning: Bool { state == .running }

    /// Whether the reason there is no picture is worth telling the user about.
    /// A missing camera is not — there is nothing they can do and nothing they
    /// did wrong — but a permission they can grant is.
    var isActionableProblem: Bool {
        state == .unavailable(.notAuthorised) || state == .unavailable(.restricted)
    }

    // MARK: Lifecycle

    /// Asks for permission if it has not been asked for, then starts the feed.
    /// Safe to call repeatedly; only the first call in a given state does work.
    func start() {
        guard state == .idle else { return }

        #if targetEnvironment(simulator)
        // Short-circuited rather than discovered, so the Simulator never shows
        // a permission prompt for a camera it does not have.
        state = .unavailable(.noDevice)
        #else
        state = .starting
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if granted {
                        self.configureAndRun()
                    } else {
                        self.state = .unavailable(.notAuthorised)
                    }
                }
            }
        case .denied:
            state = .unavailable(.notAuthorised)
        case .restricted:
            state = .unavailable(.restricted)
        @unknown default:
            state = .unavailable(.notAuthorised)
        }
        #endif
    }

    /// Stops the feed and releases the session. Called on disappear, and when
    /// the walkthrough video takes the viewfinder over — a session left running
    /// behind an opaque layer costs battery and holds the camera indicator on.
    func stop() {
        let running = session
        session = nil
        state = .idle
        guard let running else { return }
        sessionQueue.async {
            if running.isRunning { running.stopRunning() }
        }
    }

    // MARK: Configuration

    private func configureAndRun() {
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .back)
        else {
            state = .unavailable(.noDevice)
            return
        }

        let session = AVCaptureSession()
        self.session = session

        sessionQueue.async { [weak self] in
            session.beginConfiguration()
            session.sessionPreset = .high

            var configured = false
            if let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
                configured = true
            }
            session.commitConfiguration()

            if configured { session.startRunning() }

            Task { @MainActor [weak self] in
                guard let self else { return }
                if configured {
                    self.state = .running
                } else {
                    self.session = nil
                    self.state = .unavailable(.configurationFailed)
                }
            }
        }
    }
}

// MARK: - The live camera, as a view

/// The back camera, full bleed, cropped to fill rather than letterboxed —
/// a viewfinder with bars down the side does not read as a viewfinder.
struct CameraPreviewLayer: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .clear
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }

    /// A view *whose own layer* is the preview layer, so it resizes with the
    /// view for free and never lags a frame behind a rotation.
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        // Guaranteed by `layerClass` above.
        // swiftlint:disable:next force_cast
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Playback, as a view

/// An `AVPlayer` drawn edge to edge with the same `.resizeAspectFill` gravity
/// the camera uses.
///
/// The gravity is the whole point: a portrait clip shown in a portrait
/// viewfinder at `.resizeAspect` would sit inside black bars, and bars are the
/// single strongest signal that what you are looking at is a file rather than a
/// camera. `AVPlayerLayer` is used instead of SwiftUI's `VideoPlayer` for the
/// same reason — `VideoPlayer` brings transport controls, and a viewfinder has
/// no scrubber.
struct VideoPlaybackLayer: UIViewRepresentable {

    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.backgroundColor = .clear
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        // Guaranteed by `layerClass` above.
        // swiftlint:disable:next force_cast
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
