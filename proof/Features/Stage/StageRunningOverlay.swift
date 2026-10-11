//
//  StageRunningOverlay.swift
//  Tremor — S-14 Simulation running
//
//  The show. The sheet retracts to nothing and the stage fills the screen; all
//  that is left is a transport bar, a live acceleration meter down the trailing
//  edge, a caption naming what is happening, and the impact ticker.
//
//  Two honesty rules from SPEC §4.7.6, both enforced here rather than assumed:
//
//    • Every number on this screen comes off the accelerogram or off Track A's
//      timeline. Nothing is read out of the physics engine.
//    • The captions use Track A's verbs, so what the user hears matches what
//      the report will later say.
//

import SwiftUI

// MARK: - Countdown

/// 3-2-1 in the display face, one step every 250 ms (SPEC §1.4 S-14).
struct StageCountdown: View {

    let value: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("\(value)")
            .tremorType(.displayXL, numeric: true)
            .foregroundStyle(TremorColor.primarySoft)
            .padding(TremorSpacing.xl)
            .background {
                Circle()
                    .fill(TremorColor.ink.opacity(0.55))
                    .overlay {
                        Circle().strokeBorder(
                            TremorColor.primarySoft.opacity(0.35),
                            lineWidth: TremorSize.strokeEmphasis)
                    }
            }
            .scaleEffect(reduceMotion ? 1 : 1.0)
            .transition(reduceMotion ? .opacity : .scale(scale: 1.35).combined(with: .opacity))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Starting in \(value)")
            .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Live acceleration meter

/// The 4 pt bar down the trailing edge: how hard the floor is being shaken right
/// now, with a tick at the hardest it has reached. Reads the record, never the
/// engine.
struct StageAccelerationMeter: View {

    let fraction: Double
    let peakFraction: Double
    let label: String
    let band: RiskBand

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let trackHeight: CGFloat = 200

    var body: some View {
        VStack(alignment: .trailing, spacing: TremorSpacing.xs) {
            Text(label)
                .tremorType(.captionEmphasis, numeric: true)
                .foregroundStyle(TremorColor.inkInverse)
                .padding(.horizontal, TremorSpacing.xs)
                .padding(.vertical, TremorSpacing.hair)
                .background(Capsule(style: .continuous).fill(TremorColor.ink.opacity(0.6)))

            ZStack(alignment: .bottom) {
                Capsule(style: .continuous)
                    .fill(TremorColor.inkInverse.opacity(0.18))
                    .frame(width: TremorSpacing.xxs, height: Self.trackHeight)

                Capsule(style: .continuous)
                    .fill(band.stageMark)
                    .frame(width: TremorSpacing.xxs,
                           height: Self.trackHeight * CGFloat(min(max(fraction, 0), 1)))
                    .animation(
                        TremorMotion.resolved(TremorMotion.colorShift, reduceMotion: reduceMotion),
                        value: fraction)

                // The peak tick, so the highest value reached stays readable
                // after the shaking has passed it.
                Capsule(style: .continuous)
                    .fill(TremorColor.inkInverse)
                    .frame(width: TremorSpacing.sm, height: TremorSize.hairline)
                    .offset(y: -Self.trackHeight * CGFloat(min(max(peakFraction, 0), 1)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shaking right now")
        .accessibilityValue(label)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Impact ticker

/// At most three lines, newest first, naming what has just hit the floor.
struct StageImpactTicker: View {

    let markers: [FailureMarker]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            ForEach(Array(markers.enumerated()), id: \.element.id) { index, marker in
                HStack(spacing: TremorSpacing.xs) {
                    Image(systemName: (marker.band ?? .moderate).symbolName)
                        .font(.system(size: TremorControlMetrics.glyphSmall, weight: .semibold))
                        .foregroundStyle((marker.band ?? .moderate).stageSurface)
                    Text(StageModel.tickerLine(for: marker))
                        .tremorType(.callout, numeric: true)
                        .foregroundStyle(TremorColor.inkInverse)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, TremorSpacing.sm)
                .padding(.vertical, TremorSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: TremorRadius.thumbnail, style: .continuous)
                        .fill(TremorColor.ink.opacity(0.82)))
                .opacity(index == 0 ? 1 : 0.62)
                .transition(reduceMotion
                            ? .opacity
                            : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(
            TremorMotion.resolved(TremorMotion.reveal, reduceMotion: reduceMotion),
            value: markers.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What has fallen")
    }
}

// MARK: - Transport bar

/// The floating 96 pt bar: scrub, play/pause, speed, replay (SPEC §1.4 S-14).
struct StageTransportBar: View {

    let currentTime: Double
    let duration: Double
    let markers: [TimelineScrubber.Marker]
    let isPlaying: Bool
    let isFinished: Bool
    let rate: PlaybackRate

    let onScrub: (Double) -> Void
    let onPlayPause: () -> Void
    let onRate: (PlaybackRate) -> Void
    let onReplay: () -> Void
    let onSkipToEnd: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: TremorSpacing.xs) {
            TimelineScrubber(
                currentTime: currentTime,
                duration: duration,
                markers: markers,
                isPlaying: isPlaying,
                onScrub: onScrub,
                onScrubEnd: onScrub,
                onPlayPause: onPlayPause)

            controls
        }
        .padding(.horizontal, TremorSpacing.md)
        .padding(.vertical, TremorSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: TremorRadius.sheet, style: .continuous)
                .fill(TremorColor.surface))
        .tremorShadow(.lifted)
    }

    @ViewBuilder
    private var controls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                speedChips
                HStack(spacing: TremorSpacing.xs) {
                    Spacer(minLength: 0)
                    trailingAction
                }
            }
        } else {
            HStack(spacing: TremorSpacing.xs) {
                speedChips
                Spacer(minLength: TremorSpacing.xs)
                trailingAction
            }
        }
    }

    private var speedChips: some View {
        HStack(spacing: TremorSpacing.xs) {
            ForEach(PlaybackRate.allCases) { option in
                TremorChip(option.displayName,
                          isSelected: rate == option,
                          showsSelectionCheck: false) {
                    onRate(option)
                }
                .accessibilityLabel("Play at \(option.displayName) speed")
            }
        }
    }

    @ViewBuilder
    private var trailingAction: some View {
        if isFinished {
            TremorButton("Replay",
                        variant: .secondary,
                        size: .small,
                        leadingIcon: "arrow.counterclockwise",
                        fillsWidth: false,
                        action: onReplay)
        } else {
            TremorButton("Skip",
                        variant: .tertiary,
                        size: .small,
                        trailingIcon: "forward.end.fill",
                        fillsWidth: false,
                        hint: "Jumps to the report without watching the rest",
                        action: onSkipToEnd)
        }
    }
}

// MARK: - The whole overlay

/// Everything S-14 draws over the stage.
struct StageRunningOverlay: View {

    @Bindable var model: StageModel

    let onSkipToEnd: () -> Void
    let onLeave: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var controller: SimulationController { model.controller }

    private var band: RiskBand {
        RiskBand(score: min(model.liveAccelerationInG / max(model.peakAccelerationInG, 0.001), 1) * 100)
    }

    var body: some View {
        ZStack {
            if case .countdown(let value) = model.runPhase {
                StageCountdown(value: value)
                    .id(value)
            }

            VStack(spacing: 0) {
                topRow
                Spacer(minLength: 0)
                caption
                ticker
                transport
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(
            TremorMotion.resolved(TremorMotion.reveal, reduceMotion: reduceMotion),
            value: model.runPhase)
    }

    // MARK: Pieces

    private var topRow: some View {
        HStack(alignment: .top, spacing: TremorSpacing.sm) {
            TremorIconButton(systemImage: "xmark",
                            style: .material,
                            size: .large,
                            label: "Stop the earthquake",
                            hint: "Goes back to your room",
                            action: onLeave)

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: TremorSpacing.xs) {
                Text(clockLabel)
                    .tremorType(.subheadline, numeric: true)
                    .foregroundStyle(TremorColor.inkInverse)
                    .padding(.horizontal, TremorSpacing.sm)
                    .padding(.vertical, TremorSpacing.xxs)
                    .background(Capsule(style: .continuous).fill(TremorColor.ink.opacity(0.6)))
                    .accessibilityLabel("Elapsed")
                    .accessibilityValue(clockLabel)

                StageAccelerationMeter(
                    fraction: model.meterFraction,
                    peakFraction: model.meterPeakFraction,
                    label: StageModel.pgaLabel(model.liveAccelerationInG),
                    band: band)

                if !model.isAutoCameraEnabled {
                    TremorButton("Auto camera",
                                variant: .secondary,
                                size: .small,
                                leadingIcon: "video",
                                fillsWidth: false) {
                        model.recentre(animated: !reduceMotion)
                    }
                }
            }
        }
        .padding(.horizontal, TremorSpacing.md)
        .padding(.top, TremorSpacing.xs)
    }

    private var clockLabel: String {
        "\(controller.elapsedLabel) / \(controller.durationLabel)"
    }

    @ViewBuilder
    private var caption: some View {
        if !model.liveCaption.isEmpty {
            Text(model.liveCaption)
                .tremorType(.title3)
                .foregroundStyle(TremorColor.inkInverse)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, TremorSpacing.md)
                .padding(.vertical, TremorSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: TremorRadius.thumbnail, style: .continuous)
                        .fill(TremorColor.ink.opacity(0.72)))
                .padding(.horizontal, TremorSpacing.md)
                .padding(.bottom, TremorSpacing.xs)
                .transition(.opacity)
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityLabel(model.liveCaption)
        }
    }

    private var ticker: some View {
        HStack {
            StageImpactTicker(markers: model.recentFailures)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TremorSpacing.md)
        .padding(.bottom, TremorSpacing.xs)
    }

    private var transport: some View {
        StageTransportBar(
            currentTime: controller.time,
            duration: controller.duration,
            markers: controller.markers.map {
                TimelineScrubber.Marker(
                    id: $0.objectID,
                    time: $0.time,
                    band: $0.band ?? .moderate,
                    label: $0.displayName)
            },
            isPlaying: controller.isPlaying,
            isFinished: controller.isFinished,
            rate: controller.rate,
            onScrub: { model.seek(to: $0) },
            onPlayPause: { model.togglePlayback() },
            onRate: { model.setRate($0) },
            onReplay: { model.replay(reduceMotion: reduceMotion, hapticsEnabled: true) },
            onSkipToEnd: onSkipToEnd)
        .padding(.horizontal, TremorSpacing.md)
        .padding(.bottom, TremorSpacing.md)
    }
}

// MARK: - Previews

#Preview("S-14 transport bar") {
    struct Harness: View {
        @State private var time: Double = 6.4
        var body: some View {
            ZStack {
                TremorColor.ink.ignoresSafeArea()
                StageTransportBar(
                    currentTime: time,
                    duration: 26,
                    markers: [
                        .init(time: 4.1, band: .severe, label: "Tall bookcase"),
                        .init(time: 9.6, band: .high, label: "Television"),
                        .init(time: 14.2, band: .moderate, label: "Floor lamp")
                    ],
                    isPlaying: true,
                    isFinished: false,
                    rate: .half,
                    onScrub: { time = $0 },
                    onPlayPause: {},
                    onRate: { _ in },
                    onReplay: {},
                    onSkipToEnd: {})
                    .padding(TremorSpacing.md)
            }
        }
    }
    return Harness()
}

#Preview("S-14 transport — finished") {
    ZStack {
        TremorColor.ink.ignoresSafeArea()
        StageTransportBar(
            currentTime: 26, duration: 26,
            markers: [.init(time: 4.1, band: .severe, label: "Tall bookcase")],
            isPlaying: false, isFinished: true, rate: .normal,
            onScrub: { _ in }, onPlayPause: {}, onRate: { _ in },
            onReplay: {}, onSkipToEnd: {})
            .padding(TremorSpacing.md)
    }
}

#Preview("S-14 ticker and meter") {
    ZStack {
        TremorColor.ink.ignoresSafeArea()
        HStack(alignment: .bottom) {
            StageImpactTicker(markers: [
                FailureMarker(objectID: UUID(), displayName: "Tall bookcase",
                              time: 4.1, ending: .topples, band: .severe),
                FailureMarker(objectID: UUID(), displayName: "Television",
                              time: 9.6, ending: .fallsOff, band: .high)
            ])
            Spacer()
            StageAccelerationMeter(fraction: 0.72, peakFraction: 0.88,
                                   label: "0.31 g", band: .high)
        }
        .padding(TremorSpacing.md)
    }
}

#Preview("S-14 countdown") {
    ZStack {
        TremorColor.ink.ignoresSafeArea()
        StageCountdown(value: 3)
    }
}
