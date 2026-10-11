//
//  StageResultsSheet.swift
//  Tremor — S-15 Results / report
//
//  The sheet at `large`, over the settled stage. The verdict first, then the
//  ranked list of what will hurt you, then everything that was fine, then how we
//  got there — in that order, because someone reading this is scared and the
//  answer to "how bad is it" cannot be below the fold.
//

import SwiftUI

struct StageResultsSheet: View {

    let room: ScannedRoom?
    let assessment: RoomAssessment?
    let isAssessing: Bool
    /// How many ground motions the verdict was averaged over. Read off the
    /// engine that actually produced it, never hard-coded — the footnote is a
    /// claim about this report, not about the default configuration.
    let ensembleSize: Int
    let hasUncertainObjects: Bool
    let didPlaybackDiverge: Bool

    let onSelect: (UUID) -> Void
    let onShare: () -> Void
    let onFixItPlan: () -> Void
    let onRunAgain: () -> Void
    let onExplainMethod: () -> Void

    @State private var showsSafeObjects = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // MARK: Derived

    private var hazards: [ObjectRisk] { assessment?.risksNeedingAction ?? [] }

    private var safeRisks: [ObjectRisk] {
        (assessment?.objectRisks ?? [])
            .filter { $0.band < .high }
            .sorted { $0.score > $1.score }
    }

    private var hasHazards: Bool { !hazards.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: TremorSpacing.lg) {
                    header
                    if isAssessing || assessment == nil {
                        skeleton
                    } else {
                        // Only the caveat that qualifies the *numbers* goes
                        // above the verdict. The playback note is about the
                        // animation, and putting it first would delay the
                        // answer the user opened this screen for.
                        uncertaintyBanner
                        verdictCard
                        playbackBanner
                        hazardList
                        safeSection
                        methodFooter
                    }
                }
                .padding(.horizontal, TremorSpacing.lg)
                .padding(.top, TremorSpacing.sm)
                .padding(.bottom, TremorSpacing.md)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.sm) {
            Text(room?.name ?? "Your room")
                .tremorType(.title1)
                .foregroundStyle(TremorColor.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: TremorSpacing.xs)
            Button(action: onShare) {
                Text("Share")
                    .tremorType(.subheadline)
                    .foregroundStyle(TremorColor.primary)
                    .padding(.horizontal, TremorSpacing.xs)
                    .padding(.vertical, TremorSpacing.xxs)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shares a card with the verdict and the top hazards")
        }
    }

    // MARK: - Loading

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.md) {
            StageSkeletonBlock(height: 160, radius: TremorRadius.card)
            ForEach(0..<3, id: \.self) { _ in
                StageSkeletonBlock(height: TremorSize.rowRich, radius: TremorRadius.card)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Working out what falls")
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Caveats

    @ViewBuilder
    private var uncertaintyBanner: some View {
        if hasUncertainObjects {
            TremorBanner("Some of this scan was low confidence",
                        message: "A few objects were measured rather than recognised, so their scores are less certain. Rescanning the room sharpens them.",
                        kind: .warning)
        }
    }

    @ViewBuilder
    private var playbackBanner: some View {
        if didPlaybackDiverge {
            // One line, deliberately. It is a footnote about the video, not a
            // caveat about the verdict, and it sits between the answer and the
            // list of hazards — the two things the user actually came for.
            TremorBanner("The animation was simplified. Every number here comes from the physics, so the report is unaffected.",
                        kind: .neutral)
        }
    }

    // MARK: - Verdict

    @ViewBuilder
    private var verdictCard: some View {
        if let assessment {
            TremorCard(padding: TremorSpacing.md,
                      fill: hasHazards ? assessment.overallBand.stageSurface : TremorColor.riskLowSurface,
                      shadow: nil) {
                VStack(alignment: .leading, spacing: TremorSpacing.md) {
                    // Dial and verdict side by side rather than stacked: this
                    // card is the top of a long report, and a full-width dial
                    // over a full-width headline pushes the hazard list — the
                    // thing the screen is for — clean off the first screenful.
                    verdictHeadline(assessment)

                    RiskDistributionBar(assessment)

                    Text("Based on \(ensembleSize) simulated ground motions at \(StageModel.pgaLabel(assessment.floorAccelerationInG)) on your floor.")
                        .tremorType(.caption)
                        .foregroundStyle(TremorColor.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func verdictHeadline(_ assessment: RoomAssessment) -> some View {
        let dial = RiskScoreDial(assessment,
                                 caption: nil,
                                 diameter: dialDiameter,
                                 animatesOnAppear: !reduceMotion)
        let words = VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
            Text(StageModel.hazardCountPhrase(hazards.count))
                .tremorType(.title1)
                .foregroundStyle(TremorColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(verdictSubtitle(assessment))
                .tremorType(.callout)
                .foregroundStyle(TremorColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        // At accessibility text sizes the two columns stop fitting, so they
        // stack instead of squeezing the headline into a two-word column.
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                dial.frame(maxWidth: .infinity, alignment: .center)
                words
            }
        } else {
            HStack(alignment: .center, spacing: TremorSpacing.md) {
                dial
                words
            }
        }
    }

    /// Big enough to be the screenshot someone sends their partner, small
    /// enough that the first hazard is on the same screenful.
    private var dialDiameter: CGFloat { 124 }

    private func verdictSubtitle(_ assessment: RoomAssessment) -> String {
        guard hasHazards else {
            return "At intensity \(assessment.intensity.roman), everything in this room stays put. That's unusual — nice work."
        }
        let phrase = StageModel.intensityPhrase(assessment.intensity)
        return phrase.prefix(1).uppercased() + phrase.dropFirst()
    }

    // MARK: - Hazards

    @ViewBuilder
    private var hazardList: some View {
        if hasHazards {
            VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                TremorSectionHeader("Worst first")
                ForEach(hazards) { risk in
                    hazardRow(risk)
                }
            }
        }
    }

    private func hazardRow(_ risk: ObjectRisk) -> some View {
        let object = room?.object(id: risk.objectID)
        return TremorCard.tappable(
            padding: TremorSpacing.sm,
            accessibilityLabel: "\(object?.type.displayName ?? "Object"). \(risk.band.displayName) risk, \(Int(risk.score.rounded())) out of 100. \(StageModel.hazardSubtitle(behaviour: risk.dominantBehaviour, impactEnergy: risk.impactEnergy, endangers: risk.endangers))",
            accessibilityHint: "Opens the full breakdown and how to fix it",
            action: { onSelect(risk.objectID) }
        ) {
            HStack(spacing: TremorSpacing.sm) {
                ObjectThumbnail(type: object?.type ?? .unknown, band: risk.band)

                VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                    Text(object?.type.displayName ?? "Unknown object")
                        .tremorType(.bodyEmphasis)
                        .foregroundStyle(TremorColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(StageModel.hazardSubtitle(
                        behaviour: risk.dominantBehaviour,
                        impactEnergy: risk.impactEnergy,
                        endangers: risk.endangers))
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    if object?.provenance.isUncertain == true {
                        Text("Estimated")
                            .tremorType(.caption)
                            .foregroundStyle(TremorColor.inkTertiary)
                            .padding(.horizontal, TremorSpacing.xs)
                            .padding(.vertical, TremorSpacing.hair)
                            .background(Capsule().fill(TremorColor.surfaceSunken))
                    }
                }

                Spacer(minLength: TremorSpacing.xs)

                VStack(alignment: .trailing, spacing: TremorSpacing.xxs) {
                    RiskBadge(risk.band)
                    Text("\(Int(risk.score.rounded()))")
                        .tremorType(.subheadline, numeric: true)
                        .foregroundStyle(TremorColor.inkSecondary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: TremorControlMetrics.glyphSmall, weight: .semibold))
                    .foregroundStyle(TremorColor.inkTertiary)
            }
        }
    }

    // MARK: - Everything else

    @ViewBuilder
    private var safeSection: some View {
        if !safeRisks.isEmpty {
            VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                Button {
                    withAnimation(TremorMotion.resolved(TremorMotion.change, reduceMotion: reduceMotion)) {
                        showsSafeObjects.toggle()
                    }
                } label: {
                    HStack(spacing: TremorSpacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(TremorColor.success)
                        Text(showsSafeObjects
                             ? "Hide the \(safeRisks.count) that are fine"
                             : "Show \(safeRisks.count) that are fine")
                            .tremorType(.subheadline)
                            .foregroundStyle(TremorColor.primary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .font(.system(size: TremorControlMetrics.glyphSmall, weight: .semibold))
                            .foregroundStyle(TremorColor.inkTertiary)
                            .rotationEffect(.degrees(showsSafeObjects ? 180 : 0))
                    }
                    .frame(minHeight: TremorSize.buttonMedium)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(showsSafeObjects ? "Collapses the list" : "Lists the objects that stay put")

                if showsSafeObjects {
                    ForEach(safeRisks) { risk in
                        safeRow(risk)
                    }
                }
            }
        }
    }

    private func safeRow(_ risk: ObjectRisk) -> some View {
        let object = room?.object(id: risk.objectID)
        return TremorListRow(
            title: object?.type.displayName ?? "Unknown object",
            subtitle: StageModel.hazardSubtitle(
                behaviour: risk.dominantBehaviour,
                impactEnergy: risk.impactEnergy,
                endangers: risk.endangers),
            leading: .iconWell(symbol: object?.type.symbolName ?? "cube",
                               tint: risk.band.stageMark,
                               fill: risk.band.stageSurface),
            accessory: .custom(AnyView(RiskBadge(risk.band))),
            accessibilityHint: "Opens the details for this object",
            action: { onSelect(risk.objectID) })
    }

    // MARK: - Method

    private var methodFooter: some View {
        Button(action: onExplainMethod) {
            Text("Scores follow FEMA E-74 with Housner rocking dynamics. Tap to see the maths, and what we're not sure about.")
                .tremorType(.footnote)
                .foregroundStyle(TremorColor.inkTertiary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, TremorSpacing.xs)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens how proof works")
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: TremorSpacing.xs) {
            if hasHazards {
                TremorButton("Make a fix-it plan",
                            leadingIcon: "wrench.and.screwdriver",
                            hint: "Adds every hazard to a checklist with the parts and the time",
                            action: onFixItPlan)
            } else {
                TremorButton("Try a bigger earthquake",
                            leadingIcon: "waveform.path.ecg",
                            hint: "Goes back to the earthquake settings",
                            action: onRunAgain)
            }
            TremorButton("Run it again",
                        variant: .tertiary,
                        size: .medium,
                        hint: "Goes back to the earthquake settings, keeping your room loaded",
                        action: onRunAgain)
        }
        .padding(.horizontal, TremorSpacing.lg)
        .padding(.top, TremorSpacing.sm)
        .padding(.bottom, TremorSpacing.ctaBottomInset)
        .background(TremorColor.surface)
    }
}

// MARK: - Previews

private func previewAssessment(_ room: ScannedRoom,
                               intensity: MercalliIntensity = .viii) -> RoomAssessment {
    RiskEngine(ensembleSize: 4).assess(room: room, intensity: intensity)
}

private func previewResults(room: ScannedRoom,
                            assessment: RoomAssessment?,
                            isAssessing: Bool = false,
                            uncertain: Bool = false,
                            diverged: Bool = false) -> StageResultsSheet {
    StageResultsSheet(
        room: room,
        assessment: assessment,
        isAssessing: isAssessing,
        ensembleSize: 4,
        hasUncertainObjects: uncertain,
        didPlaybackDiverge: diverged,
        onSelect: { _ in },
        onShare: {},
        onFixItPlan: {},
        onRunAgain: {},
        onExplainMethod: {})
}

#Preview("S-15 hazards") {
    let room = RoomFixtures.dangerousBedroom
    return previewResults(room: room, assessment: previewAssessment(room))
        .background(TremorColor.surface)
}

#Preview("S-15 nothing falls") {
    let room = RoomFixtures.safeLivingRoom
    return previewResults(room: room, assessment: previewAssessment(room, intensity: .v))
        .background(TremorColor.surface)
}

#Preview("S-15 loading") {
    previewResults(room: RoomFixtures.dangerousBedroom, assessment: nil, isAssessing: true)
        .background(TremorColor.surface)
}

#Preview("S-15 caveats") {
    let room = RoomFixtures.kitchen
    return previewResults(room: room,
                          assessment: previewAssessment(room),
                          uncertain: true,
                          diverged: true)
        .background(TremorColor.surface)
}

#Preview("S-15 accessibility text") {
    let room = RoomFixtures.dangerousBedroom
    return previewResults(room: room, assessment: previewAssessment(room))
        .background(TremorColor.surface)
        .environment(\.dynamicTypeSize, .accessibility3)
}
