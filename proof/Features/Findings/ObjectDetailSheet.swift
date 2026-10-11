//
//  ObjectDetailSheet.swift
//  Tremor — S-16 object detail and mitigation
//
//  The screen where the app earns its trust. For one object: what we think it
//  is and how sure we are, what it weighs and how tall it stands, the exact
//  acceleration at which it starts to move against what this quake delivered,
//  the seven weighted factors behind its score, what it would land on, and what
//  to do about it — with real hardware and a real "after" number.
//
//  Presented as a sheet at the `large` detent over the spotlit stage.
//

import SwiftUI

// MARK: - Sheet

struct ObjectDetailSheet: View {

    let objectID: UUID

    @Environment(\.tremor) private var tremor
    @Environment(Router.self) private var router
    @Environment(AppState.self) private var appState
    @Environment(\.fixItPlan) private var planStore

    @State private var model: ObjectDetailModel
    @State private var showsTypePicker = false

    init(objectID: UUID) {
        self.objectID = objectID
        _model = State(initialValue: ObjectDetailModel(objectID: objectID))
    }

    var body: some View {
        TremorSheet(presentation: .modal, gutter: TremorSpacing.lg) {
            content
        } footer: {
            footer
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(TremorRadius.sheet)
        .presentationBackground(TremorColor.surface)
        .task(id: taskKey) {
            await model.load(env: tremor, appState: appState)
        }
        .onDisappear { model.cancel() }
        .sheet(isPresented: $showsTypePicker) {
            ObjectTypePickerSheet(current: model.object?.type ?? .unknown) { type in
                showsTypePicker = false
                Task { await correct(.type(type)) }
            }
        }
    }

    /// Re-runs `load` whenever anything it reads changes: the room, the verdict,
    /// or which object we are looking at.
    private var taskKey: String {
        "\(objectID.uuidString)/\(appState.room?.updatedAt.timeIntervalSince1970 ?? 0)"
            + "/\(appState.assessment?.id.uuidString ?? "none")"
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ObjectDetailSkeleton()

        case .missing:
            TremorEmptyState(
                title: "That object is gone",
                message: "It is not in this room any more — it may have been removed after a rescan.",
                systemImage: "questionmark.square.dashed",
                actionTitle: "Back to the report",
                action: { router.dismissSheet() })

        case .failed(let message):
            TremorEmptyState(
                title: "We couldn't open this",
                message: message,
                systemImage: "exclamationmark.triangle",
                actionTitle: "Try again",
                action: { Task { await model.load(env: tremor, appState: appState) } })

        case .notAssessed:
            notAssessed

        case .ready:
            loaded
        }
    }

    @ViewBuilder
    private var notAssessed: some View {
        if let object = model.object {
            VStack(alignment: .leading, spacing: TremorSpacing.lg) {
                ObjectHero(object: object, band: nil, behaviour: nil, crop: model.cropImage)
                Text(object.type.displayName)
                    .tremorType(.title1)
                    .foregroundStyle(TremorColor.ink)
                    .accessibilityAddTraits(.isHeader)
                TremorBanner(
                    "This room hasn't been shaken yet",
                    message: "Run an earthquake and we'll tell you exactly what happens to this and how to stop it.",
                    kind: .highlight,
                    actionTitle: "Choose an earthquake",
                    action: {
                        appState.stagePhase = .configurator
                        router.dismissSheet()
                    })
                measurements(object)
                corrections(object)
            }
        }
    }

    @ViewBuilder
    private var loaded: some View {
        if let object = model.object, let risk = model.risk, let assessment = model.assessment {
            VStack(alignment: .leading, spacing: TremorSpacing.xxl) {
                VStack(alignment: .leading, spacing: TremorSpacing.lg) {
                    ObjectHero(object: object, band: risk.band,
                               behaviour: risk.dominantBehaviour, crop: model.cropImage)
                    verdict(object: object, risk: risk)
                    if let note = model.provenanceNote {
                        TremorBanner("We're partly guessing at this one", message: note, kind: .neutral)
                    }
                    if risk.hasRegulatoryOverride, let reason = risk.overrideReason {
                        TremorBanner("A safety code applies here", message: reason, kind: .warning)
                    }
                }

                why(object: object, risk: risk, assessment: assessment)
                whatHappens(risk: risk)
                if !risk.endangers.isEmpty { endangers(risk: risk) }
                breakdown(risk: risk)
                corrections(object)
                fixes(object: object, risk: risk)
                methodFooter
            }
        }
    }

    // MARK: Verdict

    private func verdict(object: ScannedObject, risk: ObjectRisk) -> some View {
        TremorCard(padding: TremorSpacing.lg, fill: risk.band.bandSurface, shadow: nil) {
            VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                RiskBadge(risk.band, size: .large, showsAction: true)
                Text(object.type.displayName)
                    .tremorType(.title1)
                    .foregroundStyle(TremorColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.xs) {
                    Text(FindingsFormat.score(risk.score))
                        .tremorType(.displayM, numeric: true)
                        .foregroundStyle(risk.band.bandMark)
                    Text("out of 100")
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkSecondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(risk.band.spokenScore(risk.score))
                Text(model.verdictSentence)
                    .tremorType(.body)
                    .foregroundStyle(TremorColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Why

    private func why(object: ScannedObject, risk: ObjectRisk,
                     assessment: RoomAssessment) -> some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            FindingsSectionLabel("Why", subtitle: "Tap any line to see how it was worked out.")

            TremorCard(padding: TremorSpacing.md) {
                VStack(spacing: 0) {
                    FindingsStatRow(
                        label: "Weight",
                        value: "about \(FindingsFormat.mass(object.mass, units: tremor.settings.units))",
                        caption: object.type.respondsToLoading
                            ? "\(object.loading.displayName.lowercased()), including what's on the shelves"
                            : nil,
                        valueCaption: FindingsFormat.massSpread(
                            object.mass, range: object.type.massRange,
                            units: tremor.settings.units),
                        chip: model.massProvenanceChip,
                        chipIsCaution: model.massChipIsCaution
                    ) {
                        FindingsWorking(
                            formula: "mass = density × volume × how full it is",
                            inputs: "\(FindingsFormat.dimensions(object.extents, units: tremor.settings.units)) "
                                + "at \(Int(object.type.densityPrior)) kg/m³"
                                + (object.type.respondsToLoading
                                   ? ", \(object.loading.displayName.lowercased()) (×\(String(format: "%.2f", object.loading.multiplier)))"
                                   : ""),
                            citation: "Density priors from manufacturer specification sheets and FEMA E-74 Chapter 6. The range is the honest ±30% we work to.")
                    }

                    TremorRowDivider()

                    FindingsStatRow(
                        label: "How top-heavy it is",
                        value: String(format: "%.1f", object.slenderness),
                        caption: Self.slendernessCaption(object.slenderness)
                    ) {
                        FindingsWorking(
                            formula: "slenderness = height of the centre of mass ÷ half its depth",
                            inputs: String(format: "centre of mass %.2f m up, half-depth %.2f m",
                                           object.centreOfMassHeight,
                                           object.extents.governingHalfWidth),
                            citation: "Above about 3 a piece is at real risk of tipping; above 6 it tips in a moderate quake.")
                    }

                    TremorRowDivider()

                    FindingsStatRow(
                        label: "Starts to move at",
                        value: FindingsFormat.g(risk.movementThresholdInG),
                        caption: "Your floor reached \(FindingsFormat.g(risk.testedAccelerationInG))"
                    ) {
                        FindingsWorking(
                            formula: "a_rock = g · b / h_cm  (or a_slide = g · μ, whichever is smaller)",
                            inputs: String(format: "b/h = %.2f. The ground shook at %@ and your floor turned that into %@.",
                                           1 / max(object.slenderness, 0.001),
                                           FindingsFormat.g(assessment.groundAccelerationInG),
                                           FindingsFormat.g(assessment.floorAccelerationInG)),
                            citation: "Housner (1963), rocking of a rigid block; Newmark (1965) for sliding.")
                    }

                    TremorRowDivider()

                    FindingsStatRow(
                        label: "Chance it fails",
                        value: FindingsFormat.chanceInWords(risk.likelihood),
                        caption: "Across 20 simulated ground motions"
                    ) {
                        FindingsWorking(
                            formula: "one earthquake is not an answer — twenty are",
                            inputs: "Friction is only known to ±25% and overturning is not monotonic in shaking strength, so we sample rather than run once.",
                            citation: "Makris & Roussos (2000) on non-monotonic overturning.")
                    }

                    if risk.impactEnergy >= 1 {
                        TremorRowDivider()
                        FindingsStatRow(
                            label: "Energy when it lands",
                            value: FindingsFormat.energy(risk.impactEnergy),
                            caption: Self.energyComparison(risk.impactEnergy))
                    }
                }
            }
        }
    }

    // MARK: What happens

    private func whatHappens(risk: ObjectRisk) -> some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            FindingsSectionLabel(
                "What happens",
                subtitle: "Out of 20 simulated quakes at this strength, here is how it ended up.")

            TremorCard(padding: TremorSpacing.md) {
                VStack(alignment: .leading, spacing: TremorSpacing.md) {
                    ForEach(Array(model.outcomeLines.enumerated()), id: \.offset) { pair in
                        OutcomeBar(label: pair.element.label,
                                   share: pair.element.share,
                                   band: risk.band,
                                   isWorst: pair.offset == 0)
                    }

                    if risk.slidingDisplacement >= 0.02 {
                        Text("It also walks about \(ReportFormat.distance(risk.slidingDisplacement)) across the floor.")
                            .tremorType(.footnote)
                            .foregroundStyle(TremorColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if risk.closenessToToppling > 0.5, risk.dominantBehaviour != .overturned {
                        Text("In the runs where it stayed up it still came within \(Int((risk.closenessToToppling * 100).rounded()))% of going over.")
                            .tremorType(.footnote)
                            .foregroundStyle(TremorColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func endangers(risk: ObjectRisk) -> some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            FindingsSectionLabel("What's in the way")
            TremorCard(padding: TremorSpacing.md, fill: TremorColor.primarySoft, shadow: nil) {
                VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                    Text("If it goes over, it reaches:")
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkSecondary)
                    ForEach(risk.endangers, id: \.self) { name in
                        HStack(spacing: TremorSpacing.xs) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(TremorFont.caption)
                                .foregroundStyle(TremorColor.primary)
                                .accessibilityHidden(true)
                            Text(name)
                                .tremorType(.bodyEmphasis)
                                .foregroundStyle(TremorColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func breakdown(risk: ObjectRisk) -> some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            FindingsSectionLabel(
                "What makes it dangerous",
                subtitle: "Seven weighted factors decide how bad it is if this does move. Here are this object's.")
            TremorCard(padding: TremorSpacing.md) {
                FactorBreakdownChart(risk.consequence, band: risk.band)
            }
        }
    }

    // MARK: Measurements (used before an assessment exists)

    private func measurements(_ object: ScannedObject) -> some View {
        TremorCard(padding: TremorSpacing.md) {
            VStack(spacing: 0) {
                FindingsStatRow(
                    label: "Size",
                    value: FindingsFormat.dimensions(object.extents, units: tremor.settings.units))
                TremorRowDivider()
                FindingsStatRow(
                    label: "Weight",
                    value: FindingsFormat.mass(object.mass, units: tremor.settings.units),
                    chip: model.massProvenanceChip,
                    chipIsCaution: model.massChipIsCaution)
                TremorRowDivider()
                FindingsStatRow(
                    label: "How it's held",
                    value: object.mounting.displayName)
            }
        }
    }

    // MARK: Corrections — the feedback loop

    private func corrections(_ object: ScannedObject) -> some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            FindingsSectionLabel(
                "Set us straight",
                subtitle: "Change anything here and the score updates straight away.")

            TremorCard(padding: TremorSpacing.md) {
                VStack(alignment: .leading, spacing: TremorSpacing.lg) {
                    VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                        Text("What is it?")
                            .tremorType(.subheadline)
                            .foregroundStyle(TremorColor.inkSecondary)
                        FindingsWrap(spacing: TremorSpacing.xs) {
                            ForEach(model.typeCandidates) { candidate in
                                TremorChip(candidate.displayName,
                                          isSelected: candidate == object.type) {
                                    Task { await correct(.type(candidate)) }
                                }
                            }
                            TremorChip("Something else…", systemImage: "ellipsis") {
                                showsTypePicker = true
                            }
                        }
                    }

                    if object.type.respondsToLoading {
                        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                            Text("How full is it?")
                                .tremorType(.subheadline)
                                .foregroundStyle(TremorColor.inkSecondary)
                            Text("A packed bookcase weighs three times what an empty one does, which is usually the difference between two risk bands.")
                                .tremorType(.caption)
                                .foregroundStyle(TremorColor.inkTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                            FindingsWrap(spacing: TremorSpacing.xs) {
                                ForEach(LoadingState.allCases, id: \.self) { state in
                                    TremorChip(state.displayName,
                                              isSelected: state == object.loading) {
                                        Task { await correct(.loading(state)) }
                                    }
                                }
                            }
                        }
                    }

                    TremorToggle(
                        "It's already anchored",
                        subtitle: "Bolted, strapped or screwed to the wall or the floor.",
                        systemImage: "wrench.and.screwdriver",
                        isOn: Binding(
                            get: { object.isAnchored },
                            set: { value in Task { await correct(.anchored(value)) } }))

                    if model.isApplyingCorrection {
                        HStack(spacing: TremorSpacing.sm) {
                            ProgressView().controlSize(.small).tint(TremorColor.primary)
                            Text("Shaking the room again…")
                                .tremorType(.footnote)
                                .foregroundStyle(TremorColor.inkTertiary)
                        }
                        .accessibilityAddTraits(.updatesFrequently)
                    }
                }
            }
        }
    }

    // MARK: Fixes

    @ViewBuilder
    private func fixes(object: ScannedObject, risk: ObjectRisk) -> some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            FindingsSectionLabel("Fix it")

            if model.isBuiltIn {
                TremorBanner(
                    "Built in — nothing to do",
                    message: "This is part of the building rather than something standing in the room, so there is nothing to anchor. It is in the report for completeness.",
                    kind: .neutral)
            } else if object.isAnchored {
                TremorBanner(
                    "You've told us this is anchored",
                    message: "We're scoring it as held in place. If that changes, switch it back above.",
                    kind: .success)
            } else if model.advice.isEmpty {
                TremorBanner(
                    "Nothing to do here",
                    message: "This one stays put at this strength of shaking, and there is no fix worth your afternoon.",
                    kind: .success)
            } else {
                VStack(spacing: TremorSpacing.md) {
                    ForEach(Array(model.advice.enumerated()), id: \.element.id) { pair in
                        MitigationCard(
                            mitigation: pair.element,
                            index: pair.offset + 1,
                            currentScore: risk.score,
                            projectedScore: model.projectedScore(for: pair.element),
                            isProjecting: model.isProjecting,
                            anchorage: model.anchorage)
                    }
                }
            }
        }
    }

    private var methodFooter: some View {
        Button {
            router.dismissSheet()
            router.openMethod()
        } label: {
            Text("Scores follow FEMA E-74 with Housner rocking dynamics. See the maths.")
                .tremorType(.footnote)
                .foregroundStyle(TremorColor.inkTertiary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("How proof works")
        .accessibilityHint("Opens the method and sources")
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        switch model.phase {
        case .ready:
            if let object = model.object, !model.isBuiltIn, !model.advice.isEmpty {
                planAction(object)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func planAction(_ object: ScannedObject) -> some View {
        let inPlan = isInPlan(object)
        VStack(spacing: TremorSpacing.xs) {
            if inPlan {
                TremorButton("Open your fix-it plan", variant: .secondary,
                            leadingIcon: "checkmark.circle.fill") {
                    openPlan()
                }
                Text("This is already in your plan.")
                    .tremorType(.caption)
                    .foregroundStyle(TremorColor.inkTertiary)
            } else {
                TremorButton("Add to my fix-it plan", leadingIcon: "plus") {
                    addToPlan(object)
                }
            }
        }
    }

    // MARK: Actions

    private func correct(_ correction: ObjectCorrection) async {
        guard let confirmation = await model.apply(correction) else { return }
        appState.post(confirmation, message: "The score has been worked out again.")
        if tremor.settings.hapticsEnabled { TremorHaptic.success.play() }
    }

    private func isInPlan(_ object: ScannedObject) -> Bool {
        guard let room = model.room, let risk = model.risk else { return false }
        return risk.band >= .moderate || risk.hasRegulatoryOverride
            || planStore.isPinned(object.id, in: room.id)
    }

    private func addToPlan(_ object: ScannedObject) {
        guard let room = model.room else { return }
        planStore.setPinned(true, objectID: object.id, in: room.id)
        if tremor.settings.hapticsEnabled { TremorHaptic.success.play() }
        appState.post("Added to your fix-it plan",
                      message: "\(object.type.displayName) and its fixes are in the list.")
        openPlan()
    }

    private func openPlan() {
        router.dismissSheet()
        router.openFixItPlan()
    }

    // MARK: Copy helpers

    static func slendernessCaption(_ ratio: Double) -> String {
        switch ratio {
        case ..<1.5: return "Low and stable"
        case ..<3: return "A bit top-heavy"
        case ..<6: return "Tall and narrow"
        default: return "Very tall and narrow"
        }
    }

    static func energyComparison(_ joules: Double) -> String {
        switch joules {
        case ..<50: return "About a dropped book"
        case ..<300: return "About a bicycle hitting a wall at walking pace"
        case ..<1500: return "More than enough to break a bone"
        default: return "Comparable to a small car at walking pace"
        }
    }
}

// MARK: - Hero

/// The object as it stands now, beside what the quake does to it.
///
/// Deliberately schematic rather than a fake photo-real render: the captured
/// crop is shown when the scan kept one, and the "after" tile is an honest
/// diagram of the outcome the solver actually produced, labelled in words.
struct ObjectHero: View {

    let object: ScannedObject
    let band: RiskBand?
    let behaviour: RigidBlockSolver.Behaviour?
    let crop: Image?

    var body: some View {
        HStack(spacing: TremorSpacing.sm) {
            tile(title: "Now", fill: TremorColor.surfaceSunken) {
                if let crop {
                    crop
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipped()
                } else {
                    Image(systemName: object.type.symbolName)
                        .font(TremorFont.displayXL)
                        .foregroundStyle(TremorColor.primary)
                }
            }

            tile(title: afterTitle, fill: (band ?? .low).bandSurface) {
                Image(systemName: object.type.symbolName)
                    .font(TremorFont.displayXL)
                    .foregroundStyle((band ?? .low).bandMark)
                    .rotationEffect(.degrees(rotation))
                    .offset(y: rotation == 0 ? 0 : TremorSpacing.xs)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(object.type.displayName). Now, and after the quake: \(afterTitle.lowercased()).")
    }

    private var afterTitle: String {
        guard let behaviour else { return "After the quake" }
        return ObjectDetailModel.outcomeLabel(behaviour)
    }

    /// Reduce Motion never removes this — it is a static diagram of an outcome,
    /// not an animation.
    private var rotation: Double {
        switch behaviour {
        case .overturned, .fellOffSupport: return 74
        case .rocked: return 12
        case .slid: return 0
        case .restrained, .stable, .none: return 0
        }
    }

    /// The spec asks for a 200pt hero. Two rich-row heights plus a gutter lands
    /// there and stays a token rather than a magic number.
    static let tileHeight: CGFloat = TremorSize.rowRich * 2 + TremorSpacing.xl

    private func tile<Content: View>(title: String, fill: Color,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: TremorSpacing.xs) {
            ZStack {
                content()
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.tileHeight)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: TremorRadius.card, style: .continuous))

            Text(title)
                .tremorType(.overline)
                .foregroundStyle(TremorColor.inkTertiary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Outcome bar

/// One row of the ensemble's outcome distribution: a label, a proportional bar,
/// and the share as a percentage. Meaning never rests on the bar alone.
struct OutcomeBar: View {

    let label: String
    let share: Double
    let band: RiskBand
    let isWorst: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.sm) {
                Text(label)
                    .tremorType(isWorst ? .bodyEmphasis : .callout)
                    .foregroundStyle(isWorst ? TremorColor.ink : TremorColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(Int((share * 100).rounded()))%")
                    .tremorType(.subheadline, numeric: true)
                    .foregroundStyle(isWorst ? band.bandMark : TremorColor.inkTertiary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(TremorColor.surfaceSunken)
                    Capsule(style: .continuous)
                        .fill(isWorst ? band.bandMark : TremorColor.stroke)
                        .frame(width: max(geometry.size.width * min(max(share, 0), 1),
                                          TremorSpacing.xxs))
                }
            }
            .frame(height: TremorSpacing.xs)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((share * 100).rounded())) percent of runs")
    }
}

// MARK: - Type picker

/// The full taxonomy, searchable, for the correction that the shortlist does not
/// cover. Never a dead end: an empty search says so and offers a way back.
struct ObjectTypePickerSheet: View {

    let current: ObjectType
    let onPick: (ObjectType) -> Void

    @State private var query = ""

    private var matches: [ObjectType] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = ObjectType.allCases.sorted { $0.displayName < $1.displayName }
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.displayName.lowercased().contains(trimmed) }
    }

    var body: some View {
        TremorSheet(title: "What is it?",
                   subtitle: "Pick the closest match. It changes the weight, the shape of the block and the advice.",
                   scrolls: false,
                   presentation: .modal) {
            VStack(alignment: .leading, spacing: TremorSpacing.md) {
                TremorTextField("Search", text: $query, placeholder: "Bookshelf, water heater…",
                               leadingIcon: "magnifyingglass",
                               submitLabel: .search,
                               autocapitalization: .never)

                if matches.isEmpty {
                    TremorEmptyState(
                        title: "Nothing matches “\(query)”",
                        message: "Try a plainer word — “cabinet”, “shelf”, “heater”.",
                        systemImage: "magnifyingglass",
                        actionTitle: "Clear the search",
                        action: { query = "" })
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(matches) { type in
                                TremorListRow(
                                    title: type.displayName,
                                    leading: .iconWell(type.symbolName),
                                    accessory: type == current ? .value("Current") : .chevron,
                                    isSelected: type == current,
                                    action: { onPick(type) })
                                TremorRowDivider()
                            }
                        }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(TremorRadius.sheet)
        .presentationBackground(TremorColor.surface)
    }
}

// MARK: - Skeleton

/// The loading state. Same geometry as the real thing, so nothing jumps when the
/// numbers land.
struct ObjectDetailSkeleton: View {

    var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.lg) {
            HStack(spacing: TremorSpacing.sm) {
                block.frame(height: ObjectHero.tileHeight)
                block.frame(height: ObjectHero.tileHeight)
            }
            block.frame(height: TremorSize.rowRich * 2)
            block.frame(height: TremorSize.rowRich * 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading this object's verdict")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var block: some View {
        RoundedRectangle(cornerRadius: TremorRadius.card, style: .continuous)
            .fill(TremorColor.surfaceSunken)
    }
}

// MARK: - Previews

#Preview("S-16 — severe hazard") {
    ObjectDetailPreviewHost(objectIndex: 1)
}

#Preview("S-16 — safe object") {
    ObjectDetailPreviewHost(objectIndex: 0)
}

#Preview("S-16 — not assessed") {
    ObjectDetailPreviewHost(objectIndex: 1, assess: false)
}

/// Hosts the sheet against a real fixture room and a real assessment, because
/// half of what this screen renders is arithmetic and a stubbed one would hide
/// every mistake worth catching.
struct ObjectDetailPreviewHost: View {

    let objectIndex: Int
    var assess: Bool = true

    @State private var env = TremorEnvironment.makePreview()
    @State private var router = Router()
    @State private var appState: AppState?
    @State private var store = FixItPlanStore.ephemeral()

    private func previewObject(in state: AppState) -> ScannedObject? {
        guard let objects = state.room?.objects, objects.indices.contains(objectIndex)
        else { return nil }
        return objects[objectIndex]
    }

    var body: some View {
        Group {
            if let appState, let object = previewObject(in: appState) {
                ObjectDetailSheet(objectID: object.id)
                    .environment(\.tremor, env)
                    .environment(router)
                    .environment(appState)
                    .environment(\.fixItPlan, store)
            } else {
                ProgressView().tremorScreen()
            }
        }
        .task {
            let state = AppState(env: env)
            let room = RoomFixtures.dangerousBedroom
            let assessment = assess
                ? env.risk.assess(room: room, intensity: .viii)
                : nil
            state.adopt(room: room, assessment: assessment)
            appState = state
        }
    }
}

