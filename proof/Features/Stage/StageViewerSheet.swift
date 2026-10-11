//
//  StageViewerSheet.swift
//  Tremor — S-12 Room viewer (3D stage, idle)
//
//  The sheet at `peek`: the room's name, what is in it, and one big action.
//  Nothing else. This is the calmest screen in the app and it earns that by
//  deferring every decision to S-13.
//
//  Expanded to `medium` it becomes either the room's own detail (what the scan
//  found, what the building does to the shaking) or, when something on the
//  stage is selected, that object's summary with a way into S-16.
//

import SwiftUI

struct StageViewerSheet: View {

    // Content
    let room: ScannedRoom?
    let assessment: RoomAssessment?
    let loadPhase: AppState.LoadPhase
    let sceneState: StageModel.SceneState
    let subtitle: String
    let selectedObject: ScannedObject?
    let selectedRisk: ObjectRisk?
    let isExpanded: Bool
    let isReducedFidelity: Bool

    // Actions
    let onSimulate: () -> Void
    let onSeeReport: () -> Void
    let onRunAgain: () -> Void
    let onOpenDetails: (UUID) -> Void
    let onClearSelection: () -> Void
    let onRetry: () -> Void
    let onRescan: () -> Void
    let onExplainMethod: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var hasAssessment: Bool { assessment != nil }
    private var isEmptyRoom: Bool { (room?.objects.isEmpty ?? false) }

    /// The peek height this sheet needs. A room that has already been simulated
    /// carries a second pill, so it is taller — the CTA is never half off the
    /// bottom of a fixed detent.
    static func peekHeight(hasAssessment: Bool, dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let base = StageDetent.peekHeight(for: dynamicTypeSize)
        guard hasAssessment else { return base }
        return base + TremorSize.buttonMedium + TremorSpacing.xs
    }

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                ScrollView { expandedContent.padding(.bottom, TremorSpacing.md) }
                    .scrollBounceBehavior(.basedOnSize)
            } else {
                header
                Spacer(minLength: 0)
            }
            footer
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        switch loadPhase {
        case .loading, .idle:
            VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                StageSkeletonBlock(height: TremorSpacing.xl, width: 180, radius: TremorRadius.sm)
                StageSkeletonBlock(height: TremorSpacing.md, width: 240, radius: TremorRadius.xs)
            }
            .padding(.horizontal, TremorSpacing.lg)
            .padding(.top, TremorSpacing.sm)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Opening this room")

        case .failed(let message):
            VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                Text("We couldn't open this room")
                    .tremorType(.title3)
                    .foregroundStyle(TremorColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TremorSpacing.lg)
            .padding(.top, TremorSpacing.sm)

        case .loaded:
            VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                Text(room?.name ?? "Your room")
                    .tremorType(.title3)
                    .foregroundStyle(TremorColor.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TremorSpacing.lg)
            .padding(.top, TremorSpacing.sm)
        }
    }

    // MARK: - Expanded

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.md) {
            header

            if let sceneMessage = sceneState.failureMessage {
                TremorBanner("Showing the floor plan instead",
                            message: sceneMessage,
                            kind: .warning)
                    .padding(.horizontal, TremorSpacing.lg)
            }

            if isReducedFidelity {
                TremorBanner("Running in low-power mode",
                            message: "The 3D view is simpler to save your battery. Every number in your report is exactly the same.",
                            kind: .neutral)
                    .padding(.horizontal, TremorSpacing.lg)
            }

            if let selectedObject {
                selectionCard(selectedObject)
            } else if let room {
                roomDetail(room)
            }
        }
    }

    private func selectionCard(_ object: ScannedObject) -> some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            TremorSectionHeader("Selected",
                               actionTitle: "Clear",
                               actionHint: "Deselects this object on the stage",
                               action: onClearSelection)

            TremorCard {
                VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                    HStack(spacing: TremorSpacing.sm) {
                        ObjectThumbnail(object: object, band: selectedRisk?.band)
                        VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                            Text(object.type.displayName)
                                .tremorType(.bodyEmphasis)
                                .foregroundStyle(TremorColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(objectMetrics(object))
                                .tremorType(.footnote)
                                .foregroundStyle(TremorColor.inkTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: TremorSpacing.xs)
                        if let band = selectedRisk?.band {
                            RiskBadge(band)
                        }
                    }

                    if let reason = selectedRisk?.reasons.first {
                        Text(reason)
                            .tremorType(.callout)
                            .foregroundStyle(TremorColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Run the earthquake to find out what happens to this one.")
                            .tremorType(.callout)
                            .foregroundStyle(TremorColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    TremorButton("Open details",
                                variant: .secondary,
                                size: .medium,
                                trailingIcon: "chevron.right",
                                hint: "Opens the full breakdown and how to fix it") {
                        onOpenDetails(object.id)
                    }
                }
            }
            .padding(.horizontal, TremorSpacing.lg)
        }
    }

    private func roomDetail(_ room: ScannedRoom) -> some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            TremorSectionHeader("This room")

            TremorCard {
                VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                    detailRow("What we found",
                              room.objects.isEmpty
                                ? "Nothing yet"
                                : "\(room.objects.count) objects, \(room.movableObjects.count) of them free to move")
                    TremorRowDivider(leadingInset: 0)
                    detailRow("Floor", room.building.floorSurface.displayName)
                    TremorRowDivider(leadingInset: 0)
                    detailRow("Ground", room.building.soil.displayName)
                    TremorRowDivider(leadingInset: 0)
                    detailRow("Your floor shakes",
                              StageModel.amplificationLabel(room.building.floorAmplification)
                                + " the ground motion")
                }
            }
            .padding(.horizontal, TremorSpacing.lg)

            Button(action: onExplainMethod) {
                Text("Where these numbers come from")
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.primary)
                    .padding(.vertical, TremorSpacing.xs)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, TremorSpacing.lg)
            .accessibilityHint("Opens how proof works")
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.sm) {
            Text(label)
                .tremorType(.callout)
                .foregroundStyle(TremorColor.inkTertiary)
            Spacer(minLength: TremorSpacing.xs)
            Text(value)
                .tremorType(.subheadline)
                .foregroundStyle(TremorColor.ink)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func objectMetrics(_ object: ScannedObject) -> String {
        let height = String(format: "%.2f m tall", object.extents.height)
        let anchored = object.isAnchored ? "anchored" : "not anchored"
        return "\(height) · \(anchored)"
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: TremorSpacing.xs) {
            switch loadPhase {
            case .loading, .idle:
                StageSkeletonBlock(height: TremorSize.buttonLarge, radius: TremorRadius.button)

            case .failed:
                TremorButton("Try again", leadingIcon: "arrow.clockwise", action: onRetry)

            case .loaded where isEmptyRoom:
                TremorButton("Scan this room again",
                            leadingIcon: "viewfinder",
                            hint: "Starts a new scan so we can pick up the furniture",
                            action: onRescan)

            case .loaded where hasAssessment:
                TremorButton("Run it again",
                            variant: .secondary,
                            size: .medium,
                            hint: "Goes back to the earthquake settings",
                            action: onRunAgain)
                TremorButton("See the report",
                            hint: "Shows what fell and how to fix it",
                            action: onSeeReport)

            case .loaded:
                TremorButton("Simulate an earthquake",
                            hint: "Choose how big, then watch your room shake",
                            action: onSimulate)
            }
        }
        .padding(.horizontal, TremorSpacing.lg)
        .padding(.top, TremorSpacing.sm)
        .padding(.bottom, TremorSpacing.ctaBottomInset)
    }
}

// MARK: - Previews

private func stagePreviewSheet<Content: View>(
    height: CGFloat = 320,
    @ViewBuilder content: () -> Content
) -> some View {
    ZStack(alignment: .bottom) {
        TremorColor.ink.ignoresSafeArea()
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: TremorSize.grabberHeight / 2, style: .continuous)
                .fill(TremorColor.ink.opacity(0.20))
                .frame(width: TremorSize.grabberWidth, height: TremorSize.grabberHeight)
                .padding(.top, TremorSpacing.xs)
            content()
        }
        .frame(height: height, alignment: .top)
        .background(TremorColor.surface)
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: TremorRadius.sheet,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: TremorRadius.sheet,
            style: .continuous))
    }
}

private func previewViewer(
    room: ScannedRoom? = RoomFixtures.dangerousBedroom,
    assessment: RoomAssessment? = nil,
    loadPhase: AppState.LoadPhase = .loaded,
    sceneState: StageModel.SceneState = .ready,
    selected: ScannedObject? = nil,
    isExpanded: Bool = false
) -> StageViewerSheet {
    StageViewerSheet(
        room: room,
        assessment: assessment,
        loadPhase: loadPhase,
        sceneState: sceneState,
        subtitle: room.map {
            StageModel.roomSubtitle(objectCount: $0.objects.count, building: $0.building)
        } ?? "",
        selectedObject: selected,
        selectedRisk: nil,
        isExpanded: isExpanded,
        isReducedFidelity: false,
        onSimulate: {},
        onSeeReport: {},
        onRunAgain: {},
        onOpenDetails: { _ in },
        onClearSelection: {},
        onRetry: {},
        onRescan: {},
        onExplainMethod: {})
}

#Preview("S-12 peek — never simulated") {
    stagePreviewSheet(height: 180) { previewViewer() }
}

#Preview("S-12 peek — already simulated") {
    stagePreviewSheet(height: 244) {
        previewViewer(assessment: RiskEngine(ensembleSize: 3).assess(
            room: RoomFixtures.dangerousBedroom, intensity: .viii))
    }
}

#Preview("S-12 loading") {
    stagePreviewSheet(height: 180) { previewViewer(room: nil, loadPhase: .loading) }
}

#Preview("S-12 failed") {
    stagePreviewSheet(height: 200) {
        previewViewer(room: nil, loadPhase: .failed("This room's files are damaged. Scanning it again takes about three minutes."))
    }
}

#Preview("S-12 empty room") {
    var empty = RoomFixtures.dangerousBedroom
    empty.objects = []
    return stagePreviewSheet(height: 190) { previewViewer(room: empty) }
}

#Preview("S-12 expanded — selection") {
    stagePreviewSheet(height: 520) {
        previewViewer(selected: RoomFixtures.dangerousBedroom.objects.first, isExpanded: true)
    }
}

#Preview("S-12 expanded — room detail") {
    stagePreviewSheet(height: 520) { previewViewer(isExpanded: true) }
}

#Preview("S-12 accessibility text") {
    stagePreviewSheet(height: 300) { previewViewer() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
