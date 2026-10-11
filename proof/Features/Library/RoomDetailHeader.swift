//
//  RoomDetailHeader.swift
//  Tremor — Features / Library (S-18)
//
//  S-18 is the header that identifies a saved room: its plate, its name, where
//  in the building it is, what is in it, and how it did the last time it was
//  shaken. SPEC lists it as "part of S-06 push" — it is the block you see when
//  you open a room, and it is the block the library shows when you ask a room
//  about itself.
//
//  It is written as two pieces on purpose:
//
//    • `RoomDetailHeader` is pure — data in, nothing out but the callbacks you
//      hand it. The 3D stage (S-12) can drop it above its sheet content without
//      inheriting a loader, and it renders correctly with the building context
//      still missing, which is the state it is in for the first frame.
//
//    • `RoomDetailSheet` wraps it with the actions the library needs (open,
//      rename, duplicate, share, delete) and owns the load of the full room, so
//      the building line can say "Ground floor of 2 · Hardwood" rather than
//      nothing.
//

import SwiftUI

// MARK: - Header

/// The identity block for one saved room.
struct RoomDetailHeader: View {

    /// Index-level facts: name, kind, object count, dates, latest band.
    var summary: RoomSummary
    /// Full-room facts. `nil` until the package is read; the header degrades to
    /// the room kind alone rather than showing a placeholder.
    var building: BuildingContext?
    /// True while the package is still loading, which softens the building line
    /// instead of leaving a hole.
    var isLoading: Bool = false
    /// Opens S-20. Shown as a "?" beside the verdict when provided.
    var onExplain: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.md) {
            HStack(alignment: .top, spacing: TremorSpacing.md) {
                RoomThumbnail(room: summary, size: Metric.plate)

                VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                    Text(summary.name)
                        .tremorType(.title2)
                        .foregroundStyle(TremorColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)

                    Text(contextLine)
                        .tremorType(.footnote)
                        .foregroundStyle(TremorColor.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .redacted(reason: isLoading && building == nil ? .placeholder : [])

                    if summary.isSample {
                        Text("Demo room")
                            .tremorType(.captionEmphasis)
                            .foregroundStyle(TremorColor.primary)
                            .padding(.horizontal, TremorSpacing.xs)
                            .padding(.vertical, TremorSpacing.xxs)
                            .background(TremorColor.primarySoft, in: Capsule())
                            .padding(.top, TremorSpacing.xxs)
                    }
                }
            }

            verdict
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Pieces

    @ViewBuilder
    private var verdict: some View {
        if summary.isDamaged {
            TremorBanner(
                "This room's file is damaged",
                message: "We can't read its geometry any more, so it can't be opened or simulated. Deleting it is the only way forward — the rest of your library is unaffected.",
                kind: .danger)
        } else if let assessment = summary.latestAssessment {
            TremorCard(padding: TremorSpacing.md,
                      fill: LibraryBandPalette.surface(assessment.band),
                      shadow: nil) {
                VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.xs) {
                        // The badge carries the band only. Its "showsAction"
                        // variant sets band and instruction on one capsule at
                        // `lineLimit(1)`, which truncates to "Anchor this…" at
                        // accessibility text sizes — and a truncated instruction
                        // is the one thing on this card that must never truncate.
                        RiskBadge(assessment.band, size: .large)
                        Spacer(minLength: 0)
                        if let onExplain {
                            TremorInfoButton(about: "how a room is scored", action: onExplain)
                                .padding(.trailing, -TremorSpacing.sm)
                        }
                    }

                    Text(assessment.band.action)
                        .tremorType(.title3)
                        .foregroundStyle(TremorColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(scoreLine(assessment))
                        .tremorType(.callout)
                        .foregroundStyle(TremorColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            TremorCard(padding: TremorSpacing.md, fill: TremorColor.surfaceSunken, shadow: nil) {
                VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                    Text("Not shaken yet")
                        .tremorType(.bodyEmphasis)
                        .foregroundStyle(TremorColor.ink)
                    Text("Open this room and run an earthquake to find out what falls.")
                        .tremorType(.callout)
                        .foregroundStyle(TremorColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Copy

    /// "Bedroom · Ground floor of 2 · Hardwood", degrading gracefully to just
    /// the room kind while the package is still being read.
    private var contextLine: String {
        var parts = [summary.kind.displayName]
        if let building {
            parts.append(Self.storeyPhrase(building))
            parts.append(building.floorSurface.displayName)
        }
        parts.append(LibraryFormatting.objectCount(summary.objectCount))
        return parts.joined(separator: " · ")
    }

    /// "Ground floor", "1st floor of 3" — never "z/h", never a bare integer.
    static func storeyPhrase(_ building: BuildingContext) -> String {
        let storey: String
        switch building.floor {
        case 0: storey = "Ground floor"
        case 1: storey = "1st floor"
        case 2: storey = "2nd floor"
        case 3: storey = "3rd floor"
        default: storey = "\(building.floor)th floor"
        }
        guard building.totalStoreys > 1 else { return storey }
        return "\(storey) of \(building.totalStoreys)"
    }

    private func scoreLine(_ assessment: AssessmentSummary) -> String {
        let score = Int(assessment.score.rounded())
        let date = LibraryFormatting.shortDate(assessment.createdAt)
        return "Scored \(score) out of 100 at intensity \(assessment.intensity.roman) — \(assessment.intensity.shakingLabel.lowercased()) shaking — on \(date)."
    }

    private enum Metric {
        /// 88pt — the Lyft rich-row height, reused as a hero plate so the header
        /// lines up with the list it came from.
        static let plate: CGFloat = TremorSize.rowRich
    }
}

// MARK: - Sheet

/// The room's own screen inside the library: the S-18 header, the physics
/// context that changes its verdict, and everything you can do to it.
struct RoomDetailSheet: View {

    var room: RoomSummary
    var onOpen: () -> Void
    var onRename: () -> Void
    var onDuplicate: () -> Void
    var onShare: () -> Void
    var onDelete: () -> Void

    @Environment(\.tremor) private var tremor
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var loaded: ScannedRoom?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            TremorNavBar(
                title: "Room details",
                trailing: TremorNavBarItem(systemImage: "xmark", label: "Close") { dismiss() })

            ScrollView {
                VStack(alignment: .leading, spacing: TremorSpacing.xl) {
                    RoomDetailHeader(
                        summary: room,
                        building: loaded?.building,
                        isLoading: isLoading,
                        onExplain: { dismiss(); router.openMethod() })

                    if let loadError {
                        TremorBanner("Couldn't read the rest of this room",
                                    message: loadError,
                                    kind: .warning,
                                    actionTitle: "Try again",
                                    action: { Task { await load() } })
                    }

                    if let loaded {
                        physicsBlock(loaded)
                    }

                    actions
                }
                .padding(.horizontal, TremorSpacing.pageInset)
                .padding(.vertical, TremorSpacing.lg)
            }
        }
        .background(TremorColor.canvas.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { await load() }
    }

    // MARK: Blocks

    private func physicsBlock(_ room: ScannedRoom) -> some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            TremorSectionHeader("What changes the verdict")

            TremorCard(padding: TremorSpacing.md, shadow: .card) {
                VStack(spacing: 0) {
                    factRow(
                        "Floor",
                        value: RoomDetailHeader.storeyPhrase(room.building),
                        detail: amplificationLine(room.building),
                        symbol: "building.2")
                    TremorRowDivider()
                    factRow(
                        "Floor surface",
                        value: room.building.floorSurface.displayName,
                        detail: "Sets how easily things slide instead of tipping.",
                        symbol: "square.grid.3x3")
                    TremorRowDivider()
                    factRow(
                        "Ground",
                        value: room.building.soil.displayName,
                        detail: room.building.soil.detail,
                        symbol: "mountain.2")
                }
            }
        }
    }

    private func factRow(_ title: String,
                         value: String,
                         detail: String,
                         symbol: String) -> some View {
        HStack(alignment: .top, spacing: TremorSpacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: TremorControlMetrics.glyphMedium, weight: .regular))
                .foregroundStyle(TremorColor.primary)
                .frame(width: TremorControlMetrics.glyphLarge)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                HStack(alignment: .firstTextBaseline, spacing: TremorSpacing.xs) {
                    Text(title)
                        .tremorType(.bodyEmphasis)
                        .foregroundStyle(TremorColor.ink)
                    Spacer(minLength: TremorSpacing.xs)
                    Text(value)
                        .tremorType(.subheadline)
                        .foregroundStyle(TremorColor.inkSecondary)
                        .multilineTextAlignment(.trailing)
                }
                Text(detail)
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, TremorSpacing.sm)
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            TremorSectionHeader("Manage")

            TremorCard(padding: 0, shadow: .card) {
                VStack(spacing: 0) {
                    if !room.isDamaged {
                        TremorListRow(title: "Open in 3D",
                                     subtitle: "See the room and run an earthquake",
                                     leading: .iconWell("cube.transparent"),
                                     accessory: .chevron) { dismiss(); onOpen() }
                        TremorRowDivider()
                    }
                    TremorListRow(title: "Rename",
                                 leading: .iconWell("pencil"),
                                 accessory: .chevron) { dismiss(); onRename() }
                    if !room.isDamaged {
                        TremorRowDivider()
                        TremorListRow(title: "Duplicate",
                                     subtitle: "A fresh copy, with no simulation results",
                                     leading: .iconWell("plus.square.on.square"),
                                     accessory: .chevron) { dismiss(); onDuplicate() }
                        TremorRowDivider()
                        TremorListRow(title: "Share or export",
                                     subtitle: "PDF report, 3D model or the raw data",
                                     leading: .iconWell("square.and.arrow.up"),
                                     accessory: .chevron) { dismiss(); onShare() }
                    }
                }
                // The card paints its corners but does not clip its content, and
                // a row's press wash is a full-bleed rectangle — so the rows are
                // clipped to the same radius here.
                .clipShape(RoundedRectangle(cornerRadius: TremorRadius.card, style: .continuous))
            }

            TremorButton("Delete this room",
                        variant: .tertiary,
                        size: .medium,
                        leadingIcon: "trash",
                        hint: "Asks you to confirm first") {
                dismiss()
                onDelete()
            }
            .foregroundStyle(TremorColor.danger)
            .tint(TremorColor.danger)
            .padding(.top, TremorSpacing.xs)
        }
    }

    // MARK: Copy and loading

    private func amplificationLine(_ building: BuildingContext) -> String {
        let factor = building.floorAmplification
        guard factor > 1.02 else {
            return "At ground level the furniture feels the ground motion as it is."
        }
        return String(format: "This floor shakes about %.1f× as hard as the ground.", factor)
    }

    private func load() async {
        guard !room.isDamaged else {
            isLoading = false
            return
        }
        isLoading = true
        loadError = nil
        do {
            loaded = try await tremor.rooms.load(id: room.id)
        } catch {
            loadError = AppState.message(for: error)
        }
        isLoading = false
    }
}

// MARK: - Previews

private func headerPreviewSummary(
    band: RiskBand?,
    damaged: Bool = false,
    sample: Bool = false
) -> RoomSummary {
    RoomSummary(
        id: RoomFixtures.stableID("Bedroom"),
        name: "Our bedroom",
        kind: .bedroom,
        objectCount: 12,
        createdAt: Date().addingTimeInterval(-86_400 * 30),
        updatedAt: Date().addingTimeInterval(-86_400 * 3),
        isSample: sample,
        hasThumbnail: false,
        isDamaged: damaged,
        latestAssessment: band.map {
            AssessmentSummary(id: UUID(), intensity: .viii, band: $0, score: 84,
                              createdAt: Date().addingTimeInterval(-86_400 * 3))
        })
}

#Preview("S-18 header — states") {
    ScrollView {
        VStack(alignment: .leading, spacing: TremorSpacing.xxl) {
            RoomDetailHeader(
                summary: headerPreviewSummary(band: .severe),
                building: BuildingContext(floor: 2, totalStoreys: 3, soil: .soft, floorSurface: .hardwood),
                onExplain: {})

            RoomDetailHeader(
                summary: headerPreviewSummary(band: nil, sample: true),
                building: BuildingContext())

            RoomDetailHeader(
                summary: headerPreviewSummary(band: .low),
                building: nil,
                isLoading: true)

            RoomDetailHeader(
                summary: headerPreviewSummary(band: nil, damaged: true),
                building: nil)
        }
        .padding(TremorSpacing.pageInset)
    }
    .tremorScreen(inset: 0)
}

#Preview("S-18 sheet") {
    RoomDetailSheet(
        room: headerPreviewSummary(band: .high),
        onOpen: {}, onRename: {}, onDuplicate: {}, onShare: {}, onDelete: {})
    .environment(Router())
}
