import SwiftUI

// The structured room analysis — the payoff of the add-room flow.
//
// A user has just watched their room shake. This screen is the part that turns watching
// into knowing: what is dangerous, what has to be moved, how long each fix takes, and one
// number for the room as a whole.
//
// Three rules shaped it, and they are worth stating because each one is easy to break:
//
// 1. **Every number traces to something real.** The intensity, the peak ground
//    acceleration, the counts, the displacements, the masses — all of them are read out
//    of the finished simulation by `RoomAnalysisModel`. There is no placeholder copy on
//    this screen and no example finding. If the quake produced nothing, the screen says
//    so; it does not fill the space.
//
// 2. **It shows what held up.** A report that lists only hazards is fear-mongering, and a
//    user told that everything is dangerous learns to ignore all of it. The "What held up"
//    section is what makes this read as an assessment rather than an alarm.
//
// 3. **It reuses the findings language.** `RiskBadge`, `RiskScoreDial`, `StatTile`,
//    `TremorCard`, `FindingsSectionLabel`, `FindingsTag`, `FindingsWorking` — the same
//    components the shipping findings screens (S-16, S-17, S-21) use, so a user who has
//    seen one recognises the other. Nothing new is invented here.
//
// The score itself is deliberately inverted relative to `RiskBand`: on this screen higher
// is safer, because "how safe is my room" is the question a user actually asks. The
// mapping back into band colour lives in `RoomSafetyBand.riskEquivalent`.

// The screen and its row are both `@MainActor`: they read `DemoQuake` and `ApartmentScene`,
// which are main-actor-isolated because they own RealityKit entities. A SwiftUI `body` is
// already main-actor, but the helper properties and methods around it are not unless they
// are said to be.
@MainActor
struct RoomAnalysisView: View {

    let roomName: String
    let quake: DemoQuake
    let scene: ApartmentScene?
    var onBackToRoom: () -> Void

    /// Display units. Defaults to metric, which is what the demo apartment is measured in;
    /// declared after `onBackToRoom` so the memberwise initialiser other screens already
    /// call keeps its signature.
    var units: UnitSystem = .metric

    /// The value ranking shows its best three; the rest wait behind one tap so the report
    /// does not grow a second full list of everything.
    @State private var showsAllFixes = false
    private static let fixesShown = 3

    /// Rebuilt from the observable quake rather than captured in `init`, so the screen is
    /// correct whether it is presented mid-run or after. Building it walks the prop table
    /// once — a few hundred arithmetic operations — which is far cheaper than the layout
    /// pass it feeds.
    private var model: RoomAnalysisModel {
        RoomAnalysisModel(roomName: roomName, quake: quake, scene: scene)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TremorSpacing.xxl) {
                header(model)

                if model.didRun {
                    score(model)
                    counts(model)
                    retrofitSection(model)
                    urgentSection(model)
                    secondarySection(model)
                    survivorsSection(model)
                    provenance(model)
                } else {
                    notRunYet
                }
            }
            .padding(.top, TremorSpacing.lg)
            .padding(.bottom, TremorSpacing.section)
        }
        .tremorScreen()
        .safeAreaInset(edge: .bottom) { actions(model) }
    }

    // MARK: - Header

    private func header(_ model: RoomAnalysisModel) -> some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            Text("Room analysis")
                .tremorType(.overline)
                .foregroundStyle(TremorColor.inkTertiary)
                .accessibilityAddTraits(.isHeader)

            Text(roomName)
                .tremorType(.displayM)
                .foregroundStyle(TremorColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            if model.didRun {
                // Intensity, its plain-English descriptor and the acceleration actually
                // reached. Three facts, one line, all measured.
                HStack(spacing: TremorSpacing.xs) {
                    FindingsTag("Intensity \(model.intensity.roman)",
                                systemImage: "waveform.path.ecg")
                    FindingsTag(model.intensity.shakingLabel)
                    FindingsTag("\(gForce(model.peakAccelerationG)) peak")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "Simulated at Mercalli intensity \(model.intensity.rawValue), "
                    + "\(model.intensity.shakingLabel) shaking, "
                    + "peak ground acceleration \(gForce(model.peakAccelerationG))")

                // Framed, because unframed it reads as a claim that this run played back
                // the Loma Prieta record — which would contradict the synthesised
                // Clough–Penzien provenance printed at the bottom of this same screen.
                // `IntensityScale.reference` is an analogy for how big the shaking was,
                // and it has to say so.
                //
                // A run of one of the site's own earthquakes is not an analogy, so it names
                // the event and says where the shaking came from instead.
                VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                    if quake.shock > 0 {
                        Text(quake.title)
                        Text(quake.provenance)
                            .foregroundStyle(TremorColor.inkTertiary.opacity(0.85))
                    } else if let event = quake.event {
                        Text(event.title)
                        Text(quake.provenance)
                            .foregroundStyle(TremorColor.inkTertiary.opacity(0.85))
                    } else {
                        Text(model.intensity.reference)
                        Text("For scale only — this run used a synthesised record of that size, "
                             + "not a recording of that event.")
                            .foregroundStyle(TremorColor.inkTertiary.opacity(0.85))
                    }
                }
                .tremorType(.footnote)
                .foregroundStyle(TremorColor.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Score

    private func score(_ model: RoomAnalysisModel) -> some View {
        TremorCard {
            VStack(spacing: TremorSpacing.md) {
                RiskScoreDial(score: Double(model.safetyScore),
                              band: model.band.riskEquivalent,
                              caption: "out of 100 · higher is safer")
                    .accessibilityLabel("Room safety score")
                    .accessibilityValue(
                        "\(model.safetyScore) out of 100. \(model.band.title). \(model.headline)")

                HStack(spacing: TremorSpacing.xs) {
                    Image(systemName: model.band.symbolName)
                        .font(TremorFont.font(.subheadline))
                    Text(model.band.title)
                        .tremorType(.title3)
                }
                .foregroundStyle(model.band.riskEquivalent.bandMark)
                .padding(.horizontal, TremorSpacing.sm)
                .padding(.vertical, TremorSpacing.xxs)
                .background(model.band.riskEquivalent.bandSurface,
                            in: Capsule(style: .continuous))
                .accessibilityHidden(true)

                Text(model.headline)
                    .tremorType(.callout)
                    .foregroundStyle(TremorColor.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Counts

    private func counts(_ model: RoomAnalysisModel) -> some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            FindingsSectionLabel(
                "What happened",
                subtitle: "\(model.findings.count) of \(model.movableCount) loose objects moved "
                    + "during \(seconds(model.durationSeconds)) of shaking.")

            HStack(alignment: .top, spacing: TremorSpacing.sm) {
                countTile("Toppled", model.toppledCount, band: .severe)
                countTile("Slid", model.slidCount, band: .moderate)
                countTile("Broke", model.brokeCount, band: .high)
            }
        }
    }

    private func countTile(_ label: String, _ value: Int, band: RiskBand) -> some View {
        TremorCard(padding: TremorSpacing.sm,
                  fill: value == 0 ? TremorColor.surface : band.bandSurface,
                  shadow: nil) {
            StatTile(label: label,
                     value: "\(value)",
                     band: value == 0 ? .low : band,
                     alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Best value

    @ViewBuilder
    private func retrofitSection(_ model: RoomAnalysisModel) -> some View {
        let options = model.retrofit
        if !options.isEmpty {
            let shown = showsAllFixes ? options : Array(options.prefix(Self.fixesShown))
            VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                FindingsSectionLabel(
                    "Best value fixes",
                    subtitle: "Ranked by safety points gained per dollar.")

                TremorCard(padding: TremorSpacing.md) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, option in
                            if index > 0 { TremorRowDivider() }
                            RetrofitRow(rank: index + 1, option: option)
                        }

                        if options.count > Self.fixesShown {
                            TremorRowDivider()
                            Button(showsAllFixes
                                   ? "Show fewer"
                                   : "Show all \(options.count) fixes") {
                                withAnimation(TremorMotion.change) { showsAllFixes.toggle() }
                            }
                            .tremorType(.captionEmphasis)
                            .foregroundStyle(TremorColor.primary)
                            .padding(.top, TremorSpacing.sm)
                        }
                    }
                }

                // Rule 4: the ranking leans on an assumption, so the assumption is printed.
                Text("All \(options.count) fixes: \(FindingsFormat.money(RetrofitOption.totalCost(options)))"
                     + " · score \(model.safetyScore) → 100 if every fix holds. Points assume a "
                     + "fixed object does not move in this earthquake; prices are typical US retail.")
                    .tremorType(.caption)
                    .foregroundStyle(TremorColor.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Findings sections

    @ViewBuilder
    private func urgentSection(_ model: RoomAnalysisModel) -> some View {
        if model.urgent.isEmpty {
            VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                FindingsSectionLabel("Move these first")
                TremorBanner("Nothing reached the high band",
                            message: "No object in this room ended up somewhere that would "
                                + "hurt someone or block your way out.",
                            kind: .success)
            }
        } else {
            VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                FindingsSectionLabel(
                    "Move these first",
                    subtitle: "\(model.urgent.count) "
                        + (model.urgent.count == 1 ? "object" : "objects")
                        + " · about \(FindingsFormat.duration(model.urgent.reduce(0) { $0 + $1.effortMinutes })) of work")
                // The worst finding opens itself. A report whose every fix is behind a tap
                // reads as a list of complaints; showing one in full sets the expectation
                // that there is an answer behind each of the others.
                ForEach(Array(model.urgent.enumerated()), id: \.element.id) { index, finding in
                    RoomFindingRow(finding: finding, units: units,
                                   isExpandedByDefault: index == 0)
                }
            }
        }
    }

    @ViewBuilder
    private func secondarySection(_ model: RoomAnalysisModel) -> some View {
        if !model.secondary.isEmpty {
            VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                FindingsSectionLabel(
                    "Also worth doing",
                    subtitle: "These moved, but not into anyone's way. Cheap fixes, no urgency.")
                ForEach(model.secondary) { finding in
                    RoomFindingRow(finding: finding, units: units, isExpandedByDefault: false)
                }
            }
        }
    }

    @ViewBuilder
    private func survivorsSection(_ model: RoomAnalysisModel) -> some View {
        if !model.survivors.isEmpty {
            let stayed = model.movableCount - model.findings.count
            VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                FindingsSectionLabel(
                    "What held up",
                    subtitle: "\(stayed) of \(model.movableCount) loose objects finished exactly "
                        + "where they started. These are the ones that could have hurt and did not.")
                TremorCard(padding: 0, shadow: nil, isSelected: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(model.survivors.enumerated()), id: \.element.id) { index, survivor in
                            if index > 0 { TremorRowDivider() }
                            TremorListRow(title: survivor.name,
                                         subtitle: survivor.note,
                                         // The low-risk pair rather than a fresh green:
                                         // the band ramp already means "this is fine",
                                         // and it clears contrast on its own surface.
                                         leading: .iconWell(symbol: "checkmark",
                                                            tint: RiskBand.low.bandMark,
                                                            fill: RiskBand.low.bandSurface),
                                         accessory: .value(FindingsFormat.mass(survivor.massKg,
                                                                               units: units)))
                        }
                    }
                }
                if stayed > model.survivors.count {
                    Text("…and \(stayed - model.survivors.count) more.")
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkTertiary)
                }
            }
        }
    }

    // MARK: - Provenance

    /// Where the numbers came from. The app's whole claim is that it is not guessing, so
    /// the screen that makes the claim carries the citation.
    private func provenance(_ model: RoomAnalysisModel) -> some View {
        FindingsWorking(
            formula: "Room score = 100 × ½ ^ (hazard load ÷ 2.5)",
            inputs: "Hazard load sums each object's squared risk, weighted 1.6× when it "
                + "came to rest within a metre of somewhere you sit or stand. "
                + "Displacements measured off the finished simulation; masses and materials "
                + "are the room's authored values.",
            citation: groundMotionCitation(model) + " Fixes and hardware from FEMA E-74.")
    }

    private func groundMotionCitation(_ model: RoomAnalysisModel) -> String {
        if quake.isRecorded {
            return "Ground motion is a recorded accelerogram from CESMD, scaled to the USGS "
                + "ShakeMap peak for this site."
        }
        if let event = quake.event {
            return "Ground motion after Clough–Penzien with a Jennings–Housner–Tsai envelope, "
                + "scaled to the USGS ShakeMap peak for \(event.title) at this site."
        }
        return "Ground motion after Clough–Penzien with a Jennings–Housner–Tsai "
            + "envelope, scaled to the MMI \(model.intensity.roman) band of the Worden "
            + "et al. (2012) relation."

    }

    // MARK: - Empty state

    private var notRunYet: some View {
        TremorCard(padding: 0, shadow: nil) {
            // Deliberately no action on the card. "Back to the room" is docked at the
            // foot of this screen in every state, and giving the empty state its own
            // copy put two identical primary buttons on screen at once, one of them
            // the only button on an otherwise blank page.
            TremorEmptyState(
                title: "The earthquake has not run yet",
                message: "There is nothing to analyse until the room has been shaken. "
                    + "Go back, pick an intensity, and run it — then this page fills in.",
                systemImage: "waveform.path.ecg")
        }
    }

    // MARK: - Actions

    private func actions(_ model: RoomAnalysisModel) -> some View {
        VStack(spacing: TremorSpacing.xs) {
            TremorButton("Back to the room",
                        hint: "Returns to the 3D room, where you can run the simulation again",
                        action: onBackToRoom)

            if model.didRun {
                // The product's PDF export builds from a `ScannedRoom` and a
                // `RoomAssessment`; the demo apartment is a hand-authored scene and has
                // neither, so rather than fabricate them this shares the same findings as
                // text. See `RoomAnalysisModel.shareText`.
                ShareLink(item: model.shareText,
                          subject: Text("\(roomName) — earthquake analysis"),
                          message: Text("What moved, and what to do about it.")) {
                    Text("Share this report")
                        .tremorType(.subheadline)
                        .foregroundStyle(TremorColor.primary)
                        .frame(maxWidth: .infinity, minHeight: TremorSize.buttonSmall)
                }
                .accessibilityHint("Shares the findings as text")
            }
        }
        .padding(.horizontal, TremorSpacing.pageInset)
        .padding(.top, TremorSpacing.sm)
        .padding(.bottom, TremorSpacing.ctaBottomInset)
        .background(TremorColor.canvas)
    }

    // MARK: - Formatting

    /// Peak ground acceleration, in multiples of g.
    ///
    /// One notation, everywhere. This quantity previously appeared as `0.47g` on the
    /// intensity picker, `0.37 g` on the results sheet and `37%g` here — three renderings
    /// of one number on three consecutive screens, which reads as three different numbers.
    /// `%g` is what USGS ShakeMap prints and it is a perfectly good unit; it is just not
    /// worth having two.
    private func gForce(_ g: Double) -> String {
        String(format: "%.2f g", g)
    }

    private func seconds(_ value: Double) -> String {
        "\(Int(value.rounded())) s"
    }
}

// MARK: - One finding

/// A finding as a tappable row that expands into the fix.
///
/// It is its own view so that expanding one row re-evaluates that row and nothing else —
/// the parent screen rebuilds its model from the scene, and there is no reason to pay for
/// that when a disclosure opens.
@MainActor
private struct RoomFindingRow: View {

    let finding: RoomFinding
    let units: UnitSystem
    let isExpandedByDefault: Bool

    @State private var isExpanded: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TremorCard(padding: TremorSpacing.md) {
            VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                Button {
                    withAnimation(TremorMotion.resolved(TremorMotion.change,
                                                       reduceMotion: reduceMotion)) {
                        isExpanded.toggle()
                    }
                } label: {
                    summary
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(finding.name)
                .accessibilityValue(spokenSummary)
                .accessibilityHint(isExpanded ? "Hides the fix" : "Shows how to fix it")
                .accessibilityAddTraits(.isButton)

                if isExpanded { fix }
            }
        }
        .onAppear { isExpanded = isExpandedByDefault }
    }

    // MARK: Collapsed

    private var summary: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.sm) {
                Text(finding.name)
                    .tremorType(.title3)
                    .foregroundStyle(TremorColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                RiskBadge(finding.band)
            }

            HStack(alignment: .top, spacing: TremorSpacing.xs) {
                Image(systemName: kindSymbol)
                    .font(TremorFont.font(.footnote))
                    .foregroundStyle(finding.band.bandMark)
                    .padding(.top, TremorSpacing.hair)
                Text(finding.outcome)
                    .tremorType(.bodyEmphasis)
                    .foregroundStyle(TremorColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(finding.why)
                .tremorType(.callout)
                .foregroundStyle(TremorColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: TremorSpacing.xs) {
                FindingsTag(finding.action, systemImage: finding.mitigation.symbolName)
                FindingsTag(FindingsFormat.duration(finding.effortMinutes),
                            systemImage: "clock")
            }

            HStack(spacing: TremorSpacing.md) {
                Text("Risk \(finding.score)/100")
                Text(FindingsFormat.mass(finding.massKg, units: units))
                Text("moved \(RoomAnalysisModel.distance(finding.displacementMetres))")
                Text("at \(String(format: "%.1f", finding.timeSeconds)) s")
                Spacer(minLength: 0)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            }
            .tremorType(.caption)
            .foregroundStyle(TremorColor.inkTertiary)
        }
    }

    // MARK: Expanded

    private var fix: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            TremorRowDivider()

            Text(finding.mitigation.title)
                .tremorType(.headline)
                .foregroundStyle(TremorColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(finding.mitigation.summary)
                .tremorType(.callout)
                .foregroundStyle(TremorColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                ForEach(Array(finding.mitigation.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: TremorSpacing.xs) {
                        Text("\(index + 1)")
                            .tremorType(.captionEmphasis, numeric: true)
                            .foregroundStyle(TremorColor.primary)
                            .frame(width: TremorSpacing.md, alignment: .trailing)
                        Text(step)
                            .tremorType(.footnote)
                            .foregroundStyle(TremorColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: TremorSpacing.xs) {
                FindingsTag(finding.mitigation.difficulty.displayName,
                            systemImage: finding.mitigation.difficulty.symbolName)
                FindingsTag(FindingsFormat.money(finding.mitigation.estimatedCostUSD))
                FindingsTag(finding.mitigation.femaReference)
            }

            if let warning = finding.mitigation.warning {
                TremorBanner(warning, kind: .warning)
            }
        }
        .transition(.opacity)
        .accessibilityElement(children: .contain)
    }

    // MARK: Detail

    private var kindSymbol: String {
        switch finding.kind {
        case .toppled: return "arrow.down.right.circle.fill"
        case .slid: return "arrow.left.and.right.circle.fill"
        case .broke: return "burst.fill"
        }
    }

    private var spokenSummary: String {
        "\(finding.band.displayName), \(finding.score) out of 100. \(finding.outcome) "
            + "\(finding.why) Fix: \(finding.action), \(FindingsFormat.duration(finding.effortMinutes))."
    }
}


// MARK: - Retrofit row

/// "1 · Museum putty under the base · Wine glass, Vase and 2 more · $6–15 · +9"
private struct RetrofitRow: View {
    let rank: Int
    let option: RetrofitOption

    var body: some View {
        HStack(alignment: .top, spacing: TremorSpacing.sm) {
            Text("\(rank)")
                .tremorType(.captionEmphasis, numeric: true)
                .foregroundStyle(TremorColor.inkInverse)
                .frame(width: 22, height: 22)
                .background(Circle().fill(rank == 1 ? TremorColor.primary : TremorColor.inkTertiary))

            VStack(alignment: .leading, spacing: 2) {
                Text(option.mitigation.title)
                    .tremorType(.bodyEmphasis)
                    .foregroundStyle(TremorColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(option.objectSummary)
                    .tremorType(.caption)
                    .foregroundStyle(TremorColor.inkTertiary)
                    .lineLimit(1)
                HStack(spacing: TremorSpacing.xs) {
                    FindingsTag(FindingsFormat.money(option.costUSD))
                    FindingsTag(FindingsFormat.duration(option.mitigation.minutes),
                                systemImage: "clock")
                }
                .padding(.top, 2)
            }

            Spacer(minLength: TremorSpacing.xs)

            VStack(alignment: .trailing, spacing: 0) {
                Text("+\(option.pointsGained)")
                    .tremorType(.title3, numeric: true)
                    .foregroundStyle(TremorColor.ink)
                Text("points")
                    .tremorType(.caption)
                    .foregroundStyle(TremorColor.inkTertiary)
            }
        }
        .padding(.vertical, TremorSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rank). \(option.mitigation.title), for \(option.objectSummary). "
            + "\(FindingsFormat.money(option.costUSD)), adds \(option.pointsGained) safety points.")
    }
}
