//
//  StageConfiguratorSheet.swift
//  Tremor — S-13 Earthquake configurator
//
//  The app's signature screen. The user has to understand what they are about
//  to see *before* they see it, so every control has a plain-English consequence
//  attached to it and every number carries its unit:
//
//    • the intensity, as a scale you can point at and a slider you can drag,
//    • what that shaking does to a room, in words,
//    • the peak acceleration in g, at the ground and at *your* floor,
//    • why your floor is different from the ground, drawn,
//    • and, folded away, the record and the seed — because overturning is
//      genuinely non-monotonic and pretending otherwise would be dishonest.
//

import SwiftUI

struct StageConfiguratorSheet: View {

    @Bindable var model: StageModel

    let room: ScannedRoom?
    let isAssessing: Bool
    let onShake: () -> Void
    let onExplainMethod: () -> Void
    let onBack: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var intensity: MercalliIntensity { model.selectedIntensity }
    private var building: BuildingContext { room?.building ?? BuildingContext() }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: TremorSpacing.md) {
                    header
                    modeSelector
                    Group {
                        switch model.mode {
                        case .intensity: intensitySection
                        case .magnitude: magnitudeSection
                        }
                    }
                    consequenceCard
                    floorStrip
                    groundCard
                    advanced
                }
                .padding(.horizontal, TremorSpacing.lg)
                .padding(.top, TremorSpacing.sm)
                .padding(.bottom, TremorSpacing.md)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
        .animation(
            TremorMotion.resolved(TremorMotion.change, reduceMotion: reduceMotion),
            value: model.mode)
    }

    // MARK: - Header

    /// Deliberately one line. At the `medium` detent the sheet is 58 % of the
    /// screen and the slider has to be above the fold — a supporting sentence
    /// under the title is exactly what pushes it below.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.sm) {
            Text("How big?")
                .tremorType(.title2)
                .foregroundStyle(TremorColor.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: TremorSpacing.xs)
            TremorIconButton(systemImage: "questionmark.circle",
                            style: .ghost,
                            size: .medium,
                            label: "How we work this out",
                            hint: "Opens the method and the sources",
                            action: onExplainMethod)
        }
    }

    private var modeSelector: some View {
        TremorSegmentedControl(
            selection: $model.mode,
            label: "How to choose the earthquake") { $0.title }
    }

    // MARK: - Intensity mode

    private var intensitySection: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.md) {
            readout

            TremorSlider(
                value: $model.intensityValue,
                in: StageModel.intensityRange,
                step: 1,
                label: "Shaking intensity",
                minimumLabel: "Felt indoors",
                maximumLabel: "Buildings damaged",
                valueLabel: { value in StageModel.intensity(fromSliderValue: value).roman },
                band: { StageModel.band(forSliderValue: $0) })

            // The whole Mercalli ladder, so the number on the slider has a scale
            // around it. Tappable, because pointing at "VIII" is faster than
            // dragging to it.
            IntensityScaleView(intensity: intensity, showsReadout: false) { level in
                model.intensityValue = Double(level.rawValue)
            }
        }
    }

    /// The number the whole screen turns on: what the *floor of this room*
    /// actually reaches. The ground value sits underneath it, because the
    /// difference between the two is the point of the floor strip below.
    private var readout: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.xs) {
                Text(StageModel.pgaLabel(model.floorPGAInG))
                    .tremorType(.displayM, numeric: true)
                    .foregroundStyle(TremorColor.ink)
                    .contentTransition(.numericText())
                    .animation(
                        TremorMotion.resolved(TremorMotion.change, reduceMotion: reduceMotion),
                        value: model.floorPGAInG)
                Text("at your floor")
                    .tremorType(.callout)
                    .foregroundStyle(TremorColor.inkTertiary)
                Spacer(minLength: TremorSpacing.xs)
                intensityPill
            }

            Text("\(StageModel.pgaLabel(model.groundPGAInG)) at the ground · \(intensity.reference)")
                .tremorType(.footnote)
                .foregroundStyle(TremorColor.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shaking at your floor")
        .accessibilityValue(
            "\(StageModel.pgaLabel(model.floorPGAInG)). "
            + "Intensity \(intensity.roman), \(intensity.shakingLabel). "
            + "\(StageModel.pgaLabel(model.groundPGAInG)) at the ground.")
    }

    private var intensityPill: some View {
        HStack(spacing: TremorSpacing.xxs) {
            Text(intensity.roman)
                .tremorType(.subheadline)
            Text(intensity.shakingLabel)
                .tremorType(.captionEmphasis)
                .lineLimit(1)
        }
        .foregroundStyle(TremorColor.primary)
        .padding(.horizontal, TremorSpacing.sm)
        .padding(.vertical, TremorSpacing.xxs)
        .background(Capsule(style: .continuous).fill(TremorColor.primarySoft))
        .accessibilityHidden(true)
    }

    // MARK: - Magnitude mode

    private var magnitudeSection: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.md) {
            readout

            TremorSlider(
                value: $model.magnitude,
                in: 5.0...8.5,
                step: 0.1,
                label: "Magnitude",
                minimumLabel: "M5.0 — a local jolt",
                maximumLabel: "M8.5 — a subduction quake",
                valueLabel: { String(format: "M%.1f", $0) },
                band: { StageConfiguratorSheet.magnitudeBand($0) })

            TremorSlider(
                value: $model.distanceKm,
                in: 2...100,
                step: 1,
                label: "How far away",
                minimumLabel: "2 km — under your feet",
                maximumLabel: "100 km — a distant fault",
                valueLabel: { "\(Int($0.rounded())) km" },
                band: { StageConfiguratorSheet.distanceBand($0) })

            Text("A magnitude \(String(format: "%.1f", model.magnitude)) quake \(Int(model.distanceKm.rounded())) km away puts about \(StageModel.pgaLabel(model.groundPGAInG)) on \(building.soil.displayName.lowercased()) — that's intensity \(intensity.roman).")
                .tremorType(.callout)
                .foregroundStyle(TremorColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func magnitudeBand(_ magnitude: Double) -> TremorRiskBand {
        switch magnitude {
        case ..<5.8: return .low
        case ..<6.6: return .moderate
        case ..<7.4: return .high
        default: return .severe
        }
    }

    /// Closer is worse, so the ramp runs backwards.
    static func distanceBand(_ km: Double) -> TremorRiskBand {
        switch km {
        case ..<8: return .severe
        case ..<20: return .high
        case ..<45: return .moderate
        default: return .low
        }
    }

    // MARK: - What it feels like

    private var consequenceCard: some View {
        TremorCard(fill: TremorColor.primarySoft, shadow: nil) {
            VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                Text("What that feels like")
                    .tremorType(.overline)
                    .foregroundStyle(TremorColor.primary)
                Text(intensity.contentsDescription)
                    .tremorType(.body)
                    .foregroundStyle(TremorColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Damage to buildings: \(intensity.damageLabel.lowercased()).")
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Floor amplification

    private var floorStrip: some View {
        TremorCard {
            VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                HStack(alignment: .center, spacing: TremorSpacing.md) {
                    StageBuildingDiagram(floor: building.floor,
                                         totalStoreys: building.totalStoreys)
                    VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                        Text(StageModel.amplificationSentence(
                            floor: building.floor,
                            factor: building.floorAmplification))
                            .tremorType(.bodyEmphasis)
                            .foregroundStyle(TremorColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("A building sways most at the top, so the same earthquake is harder on an upper floor than on the ground.")
                            .tremorType(.footnote)
                            .foregroundStyle(TremorColor.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Ground and floor context

    private var groundCard: some View {
        TremorCard {
            VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                contextRow(title: building.soil.displayName,
                           detail: building.soil.detail,
                           symbol: "square.3.layers.3d.down.right")
                TremorRowDivider(leadingInset: 0)
                contextRow(title: building.floorSurface.displayName,
                           detail: floorSurfaceExplanation,
                           symbol: "square.grid.3x3")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func contextRow(title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: TremorSpacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: TremorControlMetrics.glyphMedium, weight: .medium))
                .foregroundStyle(TremorColor.primary)
                .frame(width: TremorControlMetrics.glyphLarge)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                Text(title)
                    .tremorType(.bodyEmphasis)
                    .foregroundStyle(TremorColor.ink)
                Text(detail)
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var floorSurfaceExplanation: String {
        switch building.floorSurface {
        case .carpet, .rug:
            return "Furniture grips carpet, so it tips before it slides — and tipping is the dangerous one."
        case .tile, .stoneCounter, .glassShelf:
            return "Hard, slick surfaces let furniture slide, which often saves it from going over."
        case .hardwood, .laminate, .woodShelf:
            return "A middling grip: some things slide, the tall ones still go over."
        case .concrete:
            return "Rough and grippy, so tall furniture tips rather than slides."
        }
    }

    // MARK: - Advanced

    private var advanced: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            Button {
                withAnimation(TremorMotion.resolved(TremorMotion.change, reduceMotion: reduceMotion)) {
                    model.isAdvancedExpanded.toggle()
                }
            } label: {
                HStack(spacing: TremorSpacing.xs) {
                    Text("Ground motion")
                        .tremorType(.subheadline)
                        .foregroundStyle(TremorColor.ink)
                    Spacer(minLength: TremorSpacing.xs)
                    Text(model.record.title)
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkTertiary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: TremorControlMetrics.glyphSmall, weight: .semibold))
                        .foregroundStyle(TremorColor.inkTertiary)
                        .rotationEffect(.degrees(model.isAdvancedExpanded ? 180 : 0))
                }
                .frame(minHeight: TremorSize.minimumTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ground motion")
            .accessibilityValue(model.record.title)
            .accessibilityHint(model.isAdvancedExpanded ? "Collapses the options" : "Shows the record and seed options")

            if model.isAdvancedExpanded {
                advancedBody
            }
        }
    }

    private var advancedBody: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TremorSpacing.xs) {
                    ForEach(StageGroundMotion.allCases) { record in
                        TremorChip(record.title,
                                  isSelected: model.record == record,
                                  showsSelectionCheck: false) {
                            model.record = record
                        }
                    }
                }
                .padding(.horizontal, TremorSize.hairline)
            }

            Text(model.record.detail)
                .tremorType(.footnote)
                .foregroundStyle(TremorColor.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: TremorSpacing.sm) {
                VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                    Text("Random seed")
                        .tremorType(.subheadline)
                        .foregroundStyle(TremorColor.ink)
                    Text("Same intensity, different shake. A bigger jolt can leave standing what a smaller one topples.")
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: TremorSpacing.xs)
                TremorIconButton(systemImage: "shuffle",
                                style: .surface,
                                size: .medium,
                                label: "Shuffle the shake",
                                hint: "Rolls a new ground motion at the same intensity") {
                    model.shuffleSeed()
                }
            }
        }
        .transition(.opacity)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: TremorSpacing.xs) {
            TremorButton("Shake it",
                        leadingIcon: "waveform.path.ecg",
                        isLoading: isAssessing,
                        hint: "Runs the earthquake on your room",
                        action: onShake)
            TremorButton("Back to the room",
                        variant: .tertiary,
                        size: .small,
                        action: onBack)
        }
        .padding(.horizontal, TremorSpacing.lg)
        .padding(.top, TremorSpacing.sm)
        .padding(.bottom, TremorSpacing.ctaBottomInset)
        .background(TremorColor.surface)
    }
}

// MARK: - Building diagram

/// SPEC §1.4 S-13 item 6. A 56 pt-tall elevation of the building with the
/// user's storey highlighted — the drawing that makes floor amplification
/// obvious without a word of physics.
struct StageBuildingDiagram: View {

    let floor: Int
    let totalStoreys: Int

    private var storeys: [Int] { Array(0..<max(totalStoreys, 1)).reversed() }

    var body: some View {
        VStack(spacing: TremorSize.hairline) {
            ForEach(storeys, id: \.self) { storey in
                RoundedRectangle(cornerRadius: TremorRadius.xs, style: .continuous)
                    .fill(storey == floor ? TremorColor.primary : TremorColor.surfaceSunken)
                    .frame(height: storeyHeight)
                    .overlay(alignment: .leading) {
                        if storey == floor {
                            Image(systemName: "figure.stand")
                                .font(.system(size: TremorControlMetrics.glyphSmall, weight: .semibold))
                                .foregroundStyle(TremorColor.onPrimary)
                                .padding(.leading, TremorSpacing.xxs)
                        }
                    }
            }
            Rectangle()
                .fill(TremorColor.strokeStrong)
                .frame(height: TremorSize.strokeEmphasis)
        }
        .frame(width: 44, height: TremorSize.row)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your building")
        .accessibilityValue(
            totalStoreys > 1
                ? "You are on floor \(floor) of \(totalStoreys)"
                : "A single-storey building")
    }

    private var storeyHeight: CGFloat {
        let count = CGFloat(max(totalStoreys, 1))
        return max((TremorSize.row - TremorSize.strokeEmphasis) / count - TremorSize.hairline, TremorSpacing.xxs)
    }
}

// MARK: - Previews

#Preview("S-13 configurator") {
    struct Harness: View {
        @State private var model = StageModel()
        var body: some View {
            ZStack(alignment: .bottom) {
                TremorColor.ink.ignoresSafeArea()
                StageConfiguratorSheet(
                    model: model,
                    room: RoomFixtures.dangerousBedroom,
                    isAssessing: false,
                    onShake: {},
                    onExplainMethod: {},
                    onBack: {})
                    .frame(height: 560)
                    .background(TremorColor.surface)
                    .clipShape(UnevenRoundedRectangle(
                        topLeadingRadius: TremorRadius.sheet,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: TremorRadius.sheet,
                        style: .continuous))
            }
        }
    }
    return Harness()
}

#Preview("S-13 magnitude mode") {
    struct Harness: View {
        @State private var model: StageModel = {
            let model = StageModel()
            model.mode = .magnitude
            model.isAdvancedExpanded = true
            return model
        }()
        var body: some View {
            ZStack(alignment: .bottom) {
                TremorColor.ink.ignoresSafeArea()
                StageConfiguratorSheet(
                    model: model,
                    room: RoomFixtures.safeLivingRoom,
                    isAssessing: false,
                    onShake: {},
                    onExplainMethod: {},
                    onBack: {})
                    .frame(height: 620)
                    .background(TremorColor.surface)
            }
        }
    }
    return Harness()
}

#Preview("S-13 computing") {
    struct Harness: View {
        @State private var model = StageModel()
        var body: some View {
            StageConfiguratorSheet(
                model: model,
                room: RoomFixtures.nursery,
                isAssessing: true,
                onShake: {},
                onExplainMethod: {},
                onBack: {})
                .frame(height: 560)
                .background(TremorColor.surface)
        }
    }
    return Harness()
}

#Preview("S-13 accessibility text") {
    struct Harness: View {
        @State private var model = StageModel()
        var body: some View {
            StageConfiguratorSheet(
                model: model,
                room: RoomFixtures.dangerousBedroom,
                isAssessing: false,
                onShake: {},
                onExplainMethod: {},
                onBack: {})
                .frame(height: 700)
                .background(TremorColor.surface)
                .environment(\.dynamicTypeSize, .accessibility3)
        }
    }
    return Harness()
}
