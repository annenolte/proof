//
//  FixItPlanView.swift
//  Tremor — S-17 fix-it plan
//
//  The room's findings as an afternoon's work: ordered by how much risk each
//  fix removes, grouped by the trip you would make to buy the parts, priced,
//  timed, and headed by the one number that makes anyone actually do it —
//  what this room scores when the plan is finished.
//
//  Pushed full screen from S-15's docked CTA and from S-16.
//

import SwiftUI
import UIKit

struct FixItPlanView: View {

    @Environment(\.tremor) private var tremor
    @Environment(Router.self) private var router
    @Environment(AppState.self) private var appState
    @Environment(\.fixItPlan) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model = FixItPlanModel()
    @State private var showsShoppingList = false

    var body: some View {
        VStack(spacing: 0) {
            TremorNavBar(
                title: "Fix-it plan",
                subtitle: model.plan.map { "\($0.roomName) · intensity \($0.intensity.roman)" },
                leading: TremorNavBarItem(systemImage: "chevron.left", label: "Back") {
                    router.pop()
                },
                trailing: shoppingListItem)

            content
        }
        .tremorScreen(inset: 0)
        .overlay {
            if model.celebrating, !reduceMotion {
                FindingsConfetti { model.celebrating = false }
                    .allowsHitTesting(false)
            }
        }
        .task(id: taskKey) {
            await model.load(env: tremor, appState: appState, store: store)
        }
        .onDisappear { model.cancel() }
        .sheet(isPresented: $showsShoppingList) {
            if let plan = model.plan {
                ShoppingListSheet(plan: plan) { text in
                    UIPasteboard.general.string = text
                    appState.post("Shopping list copied",
                                  message: "Paste it wherever your list lives.")
                }
            }
        }
        .onChange(of: model.celebrating) { _, celebrating in
            guard celebrating else { return }
            if tremor.settings.hapticsEnabled { TremorHaptic.success.play() }
            if reduceMotion {
                // No confetti under Reduce Motion, so the completion still has to
                // announce itself.
                appState.post("Every fix is done",
                              message: "This room is as safe as this plan can make it.")
                model.celebrating = false
            }
        }
    }

    private var taskKey: String {
        "\(appState.room?.id.uuidString ?? "none")/\(appState.assessment?.id.uuidString ?? "none")"
            + "/\(appState.room?.updatedAt.timeIntervalSince1970 ?? 0)"
    }

    private var shoppingListItem: TremorNavBarItem? {
        guard let plan = model.plan, plan.trips.contains(where: { !$0.hardware.isEmpty })
        else { return nil }
        return TremorNavBarItem(systemImage: "cart", label: "Shopping list",
                               hint: "Shows every part this plan needs") {
            showsShoppingList = true
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            loadingState

        case .noRoom:
            TremorEmptyState(
                title: "Nothing in your plan yet",
                message: "Open a room, shake it, and every hazard we find turns into a fix you can tick off.",
                systemImage: "checklist",
                actionTitle: "Go to your rooms",
                action: { router.popToRoot() })
                .frame(maxHeight: .infinity)

        case .notAssessed:
            TremorEmptyState(
                title: "Shake the room first",
                message: "We build the plan from what actually falls, so there's nothing to list until this room has been through an earthquake.",
                systemImage: "waveform.path",
                actionTitle: "Choose an earthquake",
                action: {
                    appState.stagePhase = .configurator
                    router.pop()
                })
                .frame(maxHeight: .infinity)

        case .nothingToFix:
            TremorEmptyState(
                title: "Nothing to fix in here",
                message: "At this strength of shaking everything in this room stays where it is. That's unusual — nice work.",
                systemImage: "checkmark.seal",
                actionTitle: "Try a bigger earthquake",
                action: {
                    appState.stagePhase = .configurator
                    router.pop()
                })
                .frame(maxHeight: .infinity)

        case .failed(let message):
            TremorEmptyState(
                title: "We couldn't build your plan",
                message: message,
                systemImage: "exclamationmark.triangle",
                actionTitle: "Try again",
                action: { Task { await model.load(env: tremor, appState: appState, store: store) } })
                .frame(maxHeight: .infinity)

        case .ready:
            plan
        }
    }

    private var loadingState: some View {
        ScrollView {
            VStack(spacing: TremorSpacing.md) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: TremorRadius.card, style: .continuous)
                        .fill(TremorColor.surfaceSunken)
                        .frame(height: TremorSize.rowTwoLine)
                }
            }
            .padding(.horizontal, TremorSpacing.pageInset)
            .padding(.vertical, TremorSpacing.lg)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Building your fix-it plan")
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private var plan: some View {
        if let plan = model.plan {
            ScrollView {
                VStack(alignment: .leading, spacing: TremorSpacing.xxl) {
                    header(plan)

                    ForEach(model.trips(store: store)) { trip in
                        tripSection(trip, plan: plan)
                    }

                    if !plan.trips.allSatisfy({ $0.hardware.isEmpty }) {
                        shoppingListCard(plan)
                    }

                    footnote(plan)
                }
                .padding(.horizontal, TremorSpacing.pageInset)
                .padding(.top, TremorSpacing.lg)
                .padding(.bottom, TremorSpacing.section)
            }
        }
    }

    // MARK: Header

    private func header(_ plan: FixItPlan) -> some View {
        let done = model.completedCount(store: store)
        let total = plan.items.count
        let finished = model.isFinished(store: store)

        return TremorCard(padding: TremorSpacing.lg,
                         fill: finished ? TremorRiskBand.low.surface : TremorColor.surface) {
            VStack(alignment: .leading, spacing: TremorSpacing.lg) {
                HStack(alignment: .top, spacing: TremorSpacing.lg) {
                    VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                        // The before-and-after leads, because it is the reason
                        // to do any of this. "24 fixes" as a headline reads as a
                        // chore; as a supporting line it reads as a plan.
                        Text(finished
                             ? "Every fix is done"
                             : "From \(plan.currentBand.displayName) to \(plan.projectedBand.displayName)")
                            .tremorType(.title2)
                            .foregroundStyle(TremorColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(finished
                             ? "This room is as safe as this plan can make it."
                             : plan.headline)
                            .tremorType(.footnote)
                            .foregroundStyle(TremorColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(done) of \(total) done")
                            .tremorType(.caption)
                            .foregroundStyle(TremorColor.inkTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    TremorProgressRing(
                        value: model.progress(store: store),
                        size: TremorSize.rowRich,
                        tint: finished ? TremorColor.success : TremorColor.primary)
                        .accessibilityLabel("Plan progress")
                }

                TremorRowDivider(leadingInset: 0)

                FindingsScoreDelta(
                    currentScore: plan.currentScore,
                    currentBand: plan.currentBand,
                    projectedScore: plan.projectedScore,
                    projectedBand: plan.projectedBand,
                    currentLabel: "This room now",
                    projectedLabel: "With the plan done")

                progressLine(plan)
            }
        }
    }

    @ViewBuilder
    private func progressLine(_ plan: FixItPlan) -> some View {
        if model.isScoringProgress {
            HStack(spacing: TremorSpacing.sm) {
                ProgressView().controlSize(.small).tint(TremorColor.primary)
                Text("Working out where you've got to…")
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkTertiary)
            }
        } else if let soFar = model.scoreSoFar, soFar < plan.currentScore - 0.5 {
            let band = RiskBand(score: soFar)
            HStack(spacing: TremorSpacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .font(TremorFont.subheadline)
                    .foregroundStyle(TremorColor.success)
                    .accessibilityHidden(true)
                Text("What you've ticked already takes it to \(band.displayName) (\(FindingsFormat.score(soFar))).")
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("What you have ticked already takes it to \(band.spokenScore(soFar))")
        }
    }

    // MARK: Trips

    private func tripSection(_ trip: ShoppingTrip, plan: FixItPlan) -> some View {
        let items = model.items(in: trip)
        return VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            TremorSectionHeader(Self.title(for: trip.venue), subtitle: Self.subtitle(for: trip))

            TremorCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { pair in
                        FixItRow(
                            item: pair.element,
                            isComplete: store.isComplete(pair.element.id, in: plan.roomID),
                            onToggle: { toggle(pair.element) },
                            onOpenObject: { openObject(pair.element.objectID) })
                        if pair.offset < items.count - 1 {
                            TremorRowDivider()
                        }
                    }
                }
            }
        }
    }

    private func shoppingListCard(_ plan: FixItPlan) -> some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            TremorSectionHeader("Shopping list",
                               subtitle: "Everything above, merged into one list.")
            TremorCard(padding: TremorSpacing.md) {
                VStack(alignment: .leading, spacing: TremorSpacing.md) {
                    ForEach(plan.trips) { trip in
                        if !trip.hardware.isEmpty {
                            VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                                FindingsSectionLabel(Self.title(for: trip.venue))
                                ForEach(trip.hardware) { line in
                                    Text(line.displayLine)
                                        .tremorType(.callout)
                                        .foregroundStyle(TremorColor.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    TremorButton("Copy the list", variant: .secondary,
                                size: .medium, leadingIcon: "doc.on.doc") {
                        UIPasteboard.general.string = plan.shoppingList
                        if tremor.settings.hapticsEnabled { TremorHaptic.success.play() }
                        appState.post("Shopping list copied",
                                      message: "Paste it wherever your list lives.")
                    }
                }
            }
        }
    }

    private func footnote(_ plan: FixItPlan) -> some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            Text("Prices are typical hardware-store prices in US dollars and are a guide, not a quote. Times assume you have a drill and a stud finder.")
                .tremorType(.caption)
                .foregroundStyle(TremorColor.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Text("The “with the plan done” score is worked out by shaking this room again with every fix in place — it is not an estimate.")
                .tremorType(.caption)
                .foregroundStyle(TremorColor.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Trip copy

    /// A section heading that reads as an instruction rather than a category.
    static func title(for venue: SupplyVenue) -> String {
        switch venue {
        case .nothingToBuy:   return "Do these today"
        case .hardwareStore:  return "One trip to the hardware store"
        case .online:         return "Order these"
        case .professional:   return "Book someone in"
        }
    }

    /// "You already have everything you need · 3 hours". The cost is left out
    /// when there is nothing to spend, so the line cannot say "nothing to buy"
    /// and quote a price in the same breath.
    static func subtitle(for trip: ShoppingTrip) -> String {
        var parts = [trip.venue.detail]
        if trip.venue != .nothingToBuy, trip.estimatedCostUSD.upperBound >= 0.01 {
            parts.append(FindingsFormat.money(trip.estimatedCostUSD))
        }
        parts.append(FindingsFormat.duration(trip.totalMinutes))
        return parts.joined(separator: " · ")
    }

    // MARK: Actions

    private func toggle(_ item: ChecklistItem) {
        let finished = model.toggle(item, store: store)
        if !finished, tremor.settings.hapticsEnabled { TremorHaptic.light.play() }
    }

    private func openObject(_ objectID: UUID) {
        appState.selectedObjectID = objectID
        router.openObject(objectID)
    }
}

// MARK: - Row

/// One fix: a 24pt checkbox, what to do and to what, and what it costs.
///
/// The checkbox and the row body are two separate controls on purpose — ticking
/// something off and reading why it matters are different intentions, and
/// merging them means every accidental tap marks work as done.
struct FixItRow: View {

    let item: ChecklistItem
    let isComplete: Bool
    let onToggle: () -> Void
    let onOpenObject: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: TremorSpacing.md) {
            Button(action: onToggle) {
                FindingsCheckbox(isOn: isComplete)
                    .frame(width: TremorSize.minimumTapTarget,
                           height: TremorSize.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.mitigation.title)
            .accessibilityValue(isComplete ? "Done" : "Not done")
            .accessibilityAddTraits(isComplete ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint(isComplete ? "Marks this as still to do" : "Marks this as done")

            Button(action: onOpenObject) {
                VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                    Text(item.mitigation.title)
                        .tremorType(.bodyEmphasis)
                        .foregroundStyle(isComplete ? TremorColor.inkTertiary : TremorColor.ink)
                        .strikethrough(isComplete, color: TremorColor.inkTertiary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: TremorSpacing.xs) {
                        Image(systemName: item.objectSymbolName)
                            .font(TremorFont.caption)
                            .foregroundStyle(TremorColor.inkTertiary)
                            .accessibilityHidden(true)
                        Text(item.objectName)
                            .tremorType(.footnote)
                            .foregroundStyle(TremorColor.inkSecondary)
                    }

                    FindingsWrap(spacing: TremorSpacing.xs) {
                        FindingsTag(FindingsFormat.money(item.mitigation.estimatedCostUSD))
                        FindingsTag(FindingsFormat.duration(item.mitigation.minutes))
                        if item.isScored, item.changesBand {
                            FindingsTag(item.bandTransition, systemImage: "arrow.down.right")
                        }
                    }
                    .padding(.top, TremorSpacing.xxs)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(item.mitigation.title), \(item.objectName)")
            .accessibilityValue(
                "\(FindingsFormat.money(item.mitigation.estimatedCostUSD)), "
                + "\(FindingsFormat.duration(item.mitigation.minutes))"
                + (item.isScored && item.changesBand ? ", takes it from \(item.bandTransition)" : ""))
            .accessibilityHint("Opens this object's details")
            .accessibilityAddTraits(.isButton)

            Image(systemName: "chevron.right")
                .font(TremorFont.caption)
                .foregroundStyle(TremorColor.inkTertiary)
                .padding(.top, TremorSpacing.md)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, TremorSpacing.listInset)
        .padding(.vertical, TremorSpacing.sm)
        .frame(minHeight: TremorSize.rowTwoLine)
    }
}

// MARK: - Shopping list sheet

struct ShoppingListSheet: View {

    let plan: FixItPlan
    let onCopy: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TremorSheet(title: "Shopping list",
                   subtitle: "Everything this plan needs, merged so you buy one box of screws instead of four.",
                   presentation: .modal,
                   action: TremorSheetAction(title: "Done") { dismiss() }) {
            VStack(alignment: .leading, spacing: TremorSpacing.lg) {
                ForEach(plan.trips) { trip in
                    if !trip.hardware.isEmpty {
                        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                            TremorSectionHeader(FixItPlanView.title(for: trip.venue), subtitle: trip.venue.detail)
                            ForEach(trip.hardware) { line in
                                Text(line.displayLine)
                                    .tremorType(.callout)
                                    .foregroundStyle(TremorColor.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                if plan.trips.allSatisfy({ $0.hardware.isEmpty }) {
                    TremorEmptyState(
                        title: "Nothing to buy",
                        message: "Every fix in your plan is free — it's all moving things and taking things down.",
                        systemImage: "hand.raised")
                }
            }
        } footer: {
            TremorButton("Copy the list", leadingIcon: "doc.on.doc") {
                onCopy(plan.shoppingList)
                dismiss()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(TremorRadius.sheet)
        .presentationBackground(TremorColor.surface)
    }
}

// MARK: - Confetti

/// The 900 ms celebration. Yuzu, brand purple and white, once, and never under
/// Reduce Motion — the caller decides that, so this view stays a pure animation.
struct FindingsConfetti: View {

    let onFinish: () -> Void

    @State private var progress: Double = 0

    private struct Piece {
        let x: Double
        let delay: Double
        let drift: Double
        let spin: Double
        let colorIndex: Int
        let size: Double
    }

    private static let pieces: [Piece] = (0..<44).map { index in
        var generator = SystemRandomNumberGenerator()
        return Piece(
            x: Double.random(in: 0...1, using: &generator),
            delay: Double.random(in: 0...0.25, using: &generator),
            drift: Double.random(in: -0.12...0.12, using: &generator),
            spin: Double.random(in: -3...3, using: &generator),
            colorIndex: index % 3,
            size: Double.random(in: 6...12, using: &generator))
    }

    private static let palette: [Color] = [
        TremorColor.accent, TremorColor.primary, TremorColor.surface,
    ]

    var body: some View {
        Canvas { context, size in
            for piece in Self.pieces {
                let local = min(max((progress - piece.delay) / (1 - piece.delay), 0), 1)
                guard local > 0 else { continue }
                let y = -0.1 + local * 1.25
                let x = piece.x + piece.drift * local
                let rect = CGRect(
                    x: x * size.width - piece.size / 2,
                    y: y * size.height - piece.size / 2,
                    width: piece.size,
                    height: piece.size * 0.6)
                var transformed = context
                transformed.opacity = 1 - pow(local, 3)
                transformed.translateBy(x: rect.midX, y: rect.midY)
                transformed.rotate(by: .radians(piece.spin * local * .pi))
                transformed.translateBy(x: -rect.midX, y: -rect.midY)
                transformed.fill(
                    Path(roundedRect: rect, cornerRadius: TremorRadius.xs),
                    with: .color(Self.palette[piece.colorIndex]))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.linear(duration: 0.9)) { progress = 1 }
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                onFinish()
            }
        }
    }
}

// MARK: - Previews

#Preview("S-17 — in progress") {
    FixItPlanPreviewHost()
}

#Preview("S-17 — nothing to fix") {
    FixItPlanPreviewHost(room: RoomFixtures.safeLivingRoom, intensity: .vi)
}

#Preview("S-17 — not assessed") {
    FixItPlanPreviewHost(assess: false)
}

struct FixItPlanPreviewHost: View {

    var room: ScannedRoom = RoomFixtures.dangerousBedroom
    var intensity: MercalliIntensity = .viii
    var assess: Bool = true

    @State private var env = TremorEnvironment.makePreview()
    @State private var router = Router()
    @State private var appState: AppState?
    @State private var store = FixItPlanStore.ephemeral()

    var body: some View {
        Group {
            if let appState {
                FixItPlanView()
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
            state.adopt(room: room,
                        assessment: assess ? env.risk.assess(room: room, intensity: intensity) : nil)
            appState = state
        }
    }
}
