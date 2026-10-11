//
//  GuidedCaptureView.swift
//  proof — Add Room / the guided panorama capture
//
//  The user has just named a room and is now standing in it holding a phone.
//  Everything on this screen is built for that posture, and it borrows the
//  posture's rules wholesale from S-09 (`ScanFlow/ScanView.swift`): nothing to
//  read, one instruction at a time, a progress indication that answers "where do
//  I point next" rather than "how long is left", and a single confident way to
//  stop. The coaching pill, the overlay chip and the coaching vocabulary are
//  literally the same types S-09 uses — `ScanCoachingPill`, `ScanOverlayChip`,
//  `ScanCoaching`, `ScanFlowCopy.elapsed` — because two capture screens that
//  spoke differently would read as two different apps.
//
//  THREE THINGS CAN BE BEHIND THE CHROME
//  --------------------------------------
//  The live back camera; the prepared walkthrough; or, when there is no camera
//  at all, a calm backdrop. The third is not a degraded state — it is how this
//  screen is developed and screenshotted, since the Simulator has no camera.
//  Every control, the coverage ring, the timer and the coaching all keep
//  working over it, so the screen is fully usable with nothing but a gradient
//  behind it.
//
//  "LOAD DEMO ROOM"
//  ----------------
//  One quiet text button at the bottom. Tapping it hands the viewfinder to the
//  bundled walkthrough, played once, muted, cropped to fill — and then gets out
//  of the way permanently. Everything above it carries on exactly as it was:
//  the indicator pulses, the timer counts, the ring fills and the coach
//  advances, all now driven by the clip's playhead inside `CaptureCoachModel`.
//  The button's own label before the tap is the only thing on this screen that
//  says where the footage came from, and it is gone the moment it is used.
//
//  To point that button at a different clip, edit the one line called out in
//  the header of `CaptureCoachModel.swift`.
//

import AVFoundation
import SwiftUI

// MARK: - S-A2

/// The guided capture screen: name a room, then sweep it.
///
/// ```swift
/// GuidedCaptureView(roomName: "Living room",
///                   onFinish: { usedWalkthrough in flow.captured(demo: usedWalkthrough) },
///                   onCancel: { flow.backToName() })
/// ```
///
/// - `onFinish` reports whether the capture the user is carrying forward came
///   from the prepared walkthrough, so the next step can choose what to build.
/// - `onCancel` abandons the room. Nothing has been written at this point.
struct GuidedCaptureView: View {

    let roomName: String
    var onFinish: (_ injectedDemoVideo: Bool) -> Void
    var onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var coach = CaptureCoachModel()
    @State private var camera = CameraFeed()
    /// Drives the record indicator's blink and the enabled Next button's pulse.
    /// One flag for both: they are the only two repeating animations here and
    /// they should never drift apart.
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            viewfinder
                .ignoresSafeArea()

            CaptureReticle(pan: coach.pan, isActive: coach.isCapturing)
                .allowsHitTesting(false)

            chrome
        }
        .background(TremorColor.ink)
        .animation(TremorMotion.resolved(TremorMotion.reveal, reduceMotion: reduceMotion),
                   value: coach.mode)
        .onAppear {
            camera.start()
            coach.startLiveCapture()
            isPulsing = true
        }
        .onDisappear {
            coach.stop()
            camera.stop()
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Layer 0 — what fills the frame

    @ViewBuilder
    private var viewfinder: some View {
        ZStack {
            placeholderBackdrop

            // `isRunning` first: it is the observed property, and reading it is
            // what subscribes this view to the session appearing. `session`
            // itself is deliberately not observed.
            if camera.isRunning, !coach.isWalkthrough, let session = camera.session {
                CameraPreviewLayer(session: session)
            }

            if let player = coach.player, coach.isWalkthrough {
                VideoPlaybackLayer(player: player)
                    // The clip plays once and stops on its last frame, because a viewfinder
                    // that rewinds itself is the single loudest tell that the footage is
                    // canned. A pixel-frozen image is the other one — no camera, live or
                    // stopped, ever produces a perfectly static frame — so once the clip has
                    // run out the last frame keeps drifting, slowly, the way a held phone
                    // does. Neither failure mode, and no loop.
                    .scaleEffect(coach.didPlayThrough && !reduceMotion ? Metric.driftScale : 1)
                    .animation(
                        coach.didPlayThrough && !reduceMotion
                            ? .easeInOut(duration: Metric.driftSeconds)
                                .repeatForever(autoreverses: true)
                            : nil,
                        value: coach.didPlayThrough)
                    .transition(.opacity)
            }
        }
    }

    /// What the Simulator, a refused camera and every `#Preview` see. Deliberately
    /// wordless: a viewfinder with an apology in it is not a viewfinder, and the
    /// coaching chrome on top is the same either way. The vocabulary is S-09's
    /// replay backdrop — ink, with the interactive purple bloomed through it.
    private var placeholderBackdrop: some View {
        ZStack {
            TremorColor.ink
            RadialGradient(
                colors: [TremorColor.primary.opacity(Metric.backdropBloom), .clear],
                center: .center,
                startRadius: 0,
                endRadius: Metric.backdropBloomRadius)
            LinearGradient(
                colors: [.clear, TremorColor.ink.opacity(Metric.backdropVignette)],
                startPoint: .center,
                endPoint: .bottom)
        }
        .accessibilityHidden(true)
    }

    // MARK: Layer 1 — the chrome

    private var chrome: some View {
        VStack(spacing: 0) {
            topBar

            ScanCoachingPill(coaching: coach.coaching)
                .padding(.horizontal, TremorSpacing.md)
                .padding(.top, TremorSpacing.sm)
                .id(coach.coaching.headline)
                .transition(.opacity)
                .animation(
                    TremorMotion.resolved(TremorMotion.reveal, reduceMotion: reduceMotion),
                    value: coach.coaching.headline)

            Spacer(minLength: 0)

            if camera.isActionableProblem, !coach.isWalkthrough {
                TremorBanner(
                    "Camera access is off",
                    message: "proof needs the camera to film your room. You can turn it on in Settings, or use a walkthrough video below.",
                    kind: .warning)
                    .padding(.horizontal, TremorSpacing.md)
                    .padding(.bottom, TremorSpacing.sm)
            }

            bottomDock
        }
        .padding(.bottom, TremorSpacing.ctaBottomInset)
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: TremorSpacing.sm) {
            TremorIconButton(
                systemImage: "xmark",
                style: .material,
                size: .large,
                label: "Stop and go back",
                hint: "Leaves this room without saving anything",
                action: {
                    coach.stop()
                    camera.stop()
                    onCancel()
                })

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: TremorSpacing.xxs) {
                Text("Filming \(roomName)")
                    .tremorType(.subheadline)
                    .foregroundStyle(TremorColor.inkInverse)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, TremorSpacing.sm)
                    .padding(.vertical, TremorSpacing.xxs)
                    .background(TremorColor.ink.opacity(Metric.chipGround), in: Capsule())
                    .accessibilityAddTraits(.isHeader)

                if coach.isRecording {
                    recordingChip
                }
            }
        }
        .padding(.horizontal, TremorSpacing.md)
        .padding(.top, TremorSpacing.xs)
    }

    /// The blinking dot and the running clock, in S-09's overlay-chip clothes.
    /// Built here rather than with `ScanOverlayChip` only because the dot has to
    /// pulse; every colour, radius and type style is the same.
    ///
    /// Once the source has run out this becomes a *stopped* indicator rather than
    /// a red dot next to a frozen clock. A red REC dot beside a timer that has
    /// stopped counting is a contradiction no real camera can produce, and it was
    /// the thing that broke the illusion if a presenter lingered — so the chip
    /// says what is actually true: the recording is finished and this is how long
    /// it ran.
    private var recordingChip: some View {
        HStack(spacing: TremorSpacing.xxs) {
            if coach.didPlayThrough {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: Metric.recordDot + 2, weight: .semibold))
                    .foregroundStyle(TremorColor.accent)
            } else {
                Circle()
                    .fill(TremorColor.danger)
                    .frame(width: Metric.recordDot, height: Metric.recordDot)
                    .opacity(coach.isCapturing && isPulsing && !reduceMotion
                             ? Metric.blinkLow : 1)
                    .animation(
                        reduceMotion || !coach.isCapturing
                            ? nil
                            : TremorMotion.colorShift.repeatForever(autoreverses: true),
                        value: isPulsing)
            }

            Text(coach.didPlayThrough
                 ? "Recorded \(ScanFlowCopy.elapsed(coach.elapsed))"
                 : ScanFlowCopy.elapsed(coach.elapsed))
                .tremorType(.caption, numeric: true)
        }
        .foregroundStyle(TremorColor.inkInverse)
        .padding(.horizontal, TremorSpacing.sm)
        .padding(.vertical, TremorSpacing.xxs)
        .background(TremorColor.ink.opacity(Metric.chipGround), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(coach.didPlayThrough ? "Recording finished" : "Recording")
        .accessibilityValue(ScanFlowCopy.elapsed(coach.elapsed))
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var bottomDock: some View {
        VStack(spacing: TremorSpacing.md) {
            CaptureRecordControl(
                coverage: coach.coverage,
                isCapturing: coach.isCapturing,
                isFinished: coach.didPlayThrough,
                description: coach.coverageDescription,
                action: { coach.toggleCapture() })

            TremorButton("Next",
                        variant: .accent,
                        trailingIcon: "arrow.right",
                        hint: "Rebuilds the room from the walkthrough") {
                coach.stop()
                camera.stop()
                onFinish(coach.isWalkthrough)
            }
            .disabled(!coach.canFinish)
            .scaleEffect(shouldPulseNext && isPulsing ? Metric.pulseScale : 1)
            .animation(
                shouldPulseNext
                    ? TremorMotion.change.repeatForever(autoreverses: true)
                    : nil,
                value: isPulsing)

            if let requirement = nextRequirement {
                Text(requirement)
                    .tremorType(.caption)
                    .foregroundStyle(TremorColor.inkInverse.opacity(Metric.captionInk))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The demo path, said plainly: the presenter is not standing in a kitchen.
            if !coach.isWalkthrough {
                TremorButton("Use a walkthrough video",
                            variant: .secondary,
                            size: .medium,
                            leadingIcon: "film",
                            hint: "Uses a walkthrough video instead of the live camera") {
                    if coach.loadWalkthrough() { camera.stop() }
                }
            } else {
                Label("Walkthrough video", systemImage: "film")
                    .tremorType(.caption)
                    .foregroundStyle(TremorColor.inkInverse.opacity(Metric.captionInk))
            }
        }
        .padding(.horizontal, TremorSpacing.md)
        .padding(.top, TremorSpacing.md)
        .background {
            LinearGradient(
                colors: [TremorColor.ink.opacity(0), TremorColor.ink.opacity(Metric.dockScrim)],
                startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        }
    }

    /// The Next button breathes once the walkthrough has played out, because at
    /// that moment nothing else on screen has changed and the user needs to know
    /// the wait is over. Never while the user is still sweeping — a pulsing CTA
    /// during a capture reads as "hurry up".
    private var shouldPulseNext: Bool {
        coach.didPlayThrough && !reduceMotion
    }

    /// What Next is still waiting for. Nil the moment it stops being true, so
    /// the caption disappears rather than lingering as a contradiction.
    private var nextRequirement: String? {
        guard !coach.canFinish else { return nil }
        return "Keep sweeping — the ring fills as you cover the room."
    }

    // MARK: Metrics

    /// Anatomy the design-system tokens do not carry, each with its reasoning.
    /// Same discipline as `TremorControlMetrics`: no bare number in a view body.
    private enum Metric {
        /// The overlay chip ground, taken verbatim from `ScanOverlayChip`.
        static let chipGround: Double = 0.62
        /// The bottom scrim under the dock, taken verbatim from S-09.
        static let dockScrim: Double = 0.72
        /// S-09's caption opacity over a camera feed.
        static let captionInk: Double = 0.78

        /// The backdrop bloom, matched to S-09's replay backdrop.
        static let backdropBloom: Double = 0.20
        static let backdropBloomRadius: CGFloat = 420
        static let backdropVignette: Double = 0.35

        /// 10pt — the record dot. Large enough to catch the eye at the top of a
        /// phone held at arm's length, small enough not to become a control.
        static let recordDot: CGFloat = 10
        /// The blink floor. Not zero: a dot that vanishes reads as a glitch,
        /// one that dims reads as a pulse.
        static let blinkLow: Double = 0.25
        /// 1.02. Lyft's press scale is 0.97 in the other direction; a breath
        /// outwards wants to be gentler still than a press inwards.
        static let pulseScale: CGFloat = 1.02

        /// The held-phone drift on the clip's last frame. 4% over 9 s is under
        /// half a pixel per frame at 60 Hz — below the threshold at which anyone
        /// reads it as a Ken Burns effect, above the one at which the image
        /// reads as a still.
        static let driftScale: CGFloat = 1.04
        static let driftSeconds: Double = 9
    }
}

// MARK: - The reticle

/// The horizon guide and the arrow, over whatever is behind them.
///
/// It is a guide, not a frame: hairline corner brackets that say "this is the
/// part that counts", a horizon rule to level against, and a chevron drifting in
/// the direction the coach just asked for. Nothing here is filled, because
/// anything opaque over a viewfinder competes with the room.
private struct CaptureReticle: View {

    let pan: CaptureCoachScript.PanDirection
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var drift = false

    var body: some View {
        ZStack {
            ReticleBrackets()
                .stroke(TremorColor.inkInverse.opacity(Metric.line),
                        style: StrokeStyle(lineWidth: TremorSize.strokeEmphasis, lineCap: .round))
                .frame(width: Metric.width, height: Metric.height)

            // The horizon. A capture that is level produces a room that is
            // square, and this is the only cue a person can act on for that.
            Rectangle()
                .fill(TremorColor.inkInverse.opacity(Metric.horizon))
                .frame(width: Metric.width - TremorSpacing.xxl, height: TremorSize.hairline)

            if let symbol = pan.symbolName, isActive {
                Image(systemName: symbol)
                    .font(.system(size: TremorControlMetrics.glyphLarge, weight: .semibold))
                    .foregroundStyle(TremorColor.inkInverse)
                    .shadow(color: TremorColor.ink.opacity(Metric.glyphShadow),
                            radius: TremorSpacing.xxs)
                    .offset(x: offset.width, y: offset.height)
                    .padding(Metric.arrowInset)
                    .frame(width: Metric.width, height: Metric.height,
                           alignment: alignment)
                    .transition(.opacity)
            }
        }
        .animation(TremorMotion.resolved(TremorMotion.reveal, reduceMotion: reduceMotion),
                   value: pan)
        .onAppear { drift = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pan.spoken ?? "Viewfinder")
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// Where in the reticle the chevron sits — always on the edge it is pointing
    /// at, so the arrow and its position say the same thing.
    private var alignment: Alignment {
        switch pan {
        case .right: return .trailing
        case .up: return .top
        case .down: return .bottom
        case .none: return .center
        }
    }

    /// The nudge outwards. Reduce Motion keeps the arrow, drops the travel.
    private var offset: CGSize {
        guard drift, !reduceMotion else { return .zero }
        switch pan {
        case .right: return CGSize(width: Metric.drift, height: 0)
        case .up: return CGSize(width: 0, height: -Metric.drift)
        case .down: return CGSize(width: 0, height: Metric.drift)
        case .none: return .zero
        }
    }

    private enum Metric {
        /// 260 × 176 — roughly a 3:2 window, large enough to frame a wall and a
        /// floor line together at arm's length without walling in the feed.
        static let width: CGFloat = 260
        static let height: CGFloat = 176
        static let line: Double = 0.55
        static let horizon: Double = 0.22
        static let glyphShadow: Double = 0.45
        static let drift: CGFloat = 6
        static let arrowInset: CGFloat = TremorSpacing.xs
    }
}

/// Four corner brackets. A closed rectangle would read as a crop frame — the
/// user is being pointed at a region, not asked to fit the room inside a box.
private struct ReticleBrackets: Shape {

    /// 28pt of each corner, on the 260 × 176 reticle: enough to read as a
    /// bracket, short enough never to close into a rectangle.
    private let arm: CGFloat = 28

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corners: [(CGPoint, CGVector, CGVector)] = [
            (CGPoint(x: rect.minX, y: rect.minY), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: 1)),
            (CGPoint(x: rect.maxX, y: rect.minY), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: 1)),
            (CGPoint(x: rect.minX, y: rect.maxY), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: -1)),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1))
        ]
        for (origin, horizontal, vertical) in corners {
            path.move(to: CGPoint(x: origin.x + horizontal.dx * arm, y: origin.y))
            path.addLine(to: origin)
            path.addLine(to: CGPoint(x: origin.x, y: origin.y + vertical.dy * arm))
        }
        return path
    }
}

// MARK: - The record control

/// The record button, wearing the panorama's progress as an arc around it.
///
/// A ring rather than a bar because a sweep is angular: the fill maps onto the
/// turn the user is making. It starts at the top and runs clockwise, which is
/// the direction the coaching asks them to turn. Putting the coverage on the
/// record button itself means the one thing the user is looking at is also the
/// one thing telling them how far round they are.
private struct CaptureRecordControl: View {

    let coverage: Double
    let isCapturing: Bool
    /// The source has run out; the button has nothing left to pause.
    let isFinished: Bool
    let description: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Double { min(max(coverage, 0), 1) }
    private var isComplete: Bool { clamped >= 0.999 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(TremorColor.inkInverse.opacity(Metric.track),
                        style: StrokeStyle(lineWidth: Metric.ring, lineCap: .round))

            Circle()
                .trim(from: 0, to: clamped)
                .stroke(isComplete ? TremorColor.accent : TremorColor.inkInverse,
                        style: StrokeStyle(lineWidth: Metric.ring, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(TremorMotion.resolved(TremorMotion.colorShift,
                                                reduceMotion: reduceMotion),
                           value: clamped)

            Button(action: action) {
                Circle()
                    .fill(TremorColor.surface)
                    .frame(width: Metric.disc, height: Metric.disc)
                    .overlay {
                        // Square while recording, round while stopped — the
                        // record/stop pair every camera in the world uses, so
                        // shape carries the state and colour never has to.
                        RoundedRectangle(cornerRadius: isCapturing
                                         ? TremorRadius.xs
                                         : TremorRadius.chip,
                                         style: .continuous)
                            .fill(TremorColor.danger)
                            .frame(width: isCapturing ? Metric.stop : Metric.dot,
                                   height: isCapturing ? Metric.stop : Metric.dot)
                            .animation(TremorMotion.resolved(TremorMotion.change,
                                                            reduceMotion: reduceMotion),
                                       value: isCapturing)
                    }
                    .tremorShadow(.raised)
            }
            .buttonStyle(.plain)
            .disabled(isFinished)
            .accessibilityLabel(isCapturing ? "Pause recording" : "Resume recording")
            .accessibilityValue(description)
            .accessibilityHint("Pauses or resumes without losing what you have covered")
            .accessibilityAddTraits(.updatesFrequently)
        }
        .frame(width: Metric.diameter, height: Metric.diameter)
    }

    private enum Metric {
        /// 88pt outer, 64pt disc — the record control every phone camera has,
        /// at the tap-target size Lyft §6.1 and the HIG both floor at 44.
        static let diameter: CGFloat = 88
        static let disc: CGFloat = 64
        /// 4pt ring — Lyft ships a 4pt progress bar; the arc is that bar bent
        /// into a circle, so it takes the same weight.
        static let ring: CGFloat = 4
        static let track: Double = 0.28
        /// 26pt dot when idle, 24pt rounded square while recording — the
        /// universal record/stop pair.
        static let dot: CGFloat = 26
        static let stop: CGFloat = 24
    }
}

// MARK: - Previews

#Preview("Guided capture") {
    GuidedCaptureView(roomName: "Living room", onFinish: { _ in }, onCancel: {})
}

#Preview("Reticle — pan right") {
    ZStack {
        TremorColor.ink.ignoresSafeArea()
        CaptureReticle(pan: .right, isActive: true)
    }
}

#Preview("Record control") {
    HStack(spacing: TremorSpacing.xl) {
        CaptureRecordControl(coverage: 0, isCapturing: false, isFinished: false,
                             description: "0 percent", action: {})
        CaptureRecordControl(coverage: 0.42, isCapturing: true, isFinished: false,
                             description: "42 percent", action: {})
        CaptureRecordControl(coverage: 1, isCapturing: false, isFinished: true,
                             description: "100 percent", action: {})
    }
    .padding(TremorSpacing.lg)
    .background(TremorColor.ink)
}
