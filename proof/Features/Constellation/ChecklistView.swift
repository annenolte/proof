//
//  ChecklistView.swift
//  proof — Features / Constellation
//
//  The list beside the sky (CLAUDE.md §7a.6). Every flag the sky shows is readable here as
//  plain text, and selecting one here selects it there.
//
//  Progress is "X of Y flags marked done" — never a score (§7a.5). The note that these are
//  flags to check, not a safety guarantee, is the first thing on the page and the first
//  line of the export.
//

import SwiftUI

struct ChecklistView: View {

    let roomName: String
    let sky: ConstellationModel
    var onBackToRoom: () -> Void
    /// Selects a star (or lights a chain) in the sky and goes back to it.
    var onShowInRoom: () -> Void

    @State private var renaming: Constellation?
    @State private var renameText = ""
    @State private var confirmsReset = false
    @State private var expandedPlans: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: TremorSpacing.xl) {
                    header
                    progress
                    plans
                    if !sky.analysis.chains.isEmpty { chains }
                    flagSections
                    if !sky.removedObjects.isEmpty { removed }
                    limits
                    parameters
                    footerActions
                }
                .padding(.horizontal, TremorSpacing.pageInset)
                .padding(.top, TremorSpacing.lg)
                .padding(.bottom, TremorSpacing.xxl)
            }

            TremorButton("Back to the room", variant: .primary, leadingIcon: "cube.transparent") {
                onBackToRoom()
            }
            .padding(.horizontal, TremorSpacing.pageInset)
            .padding(.top, TremorSpacing.sm)
            .padding(.bottom, TremorSpacing.ctaBottomInset)
        }
        .background(TremorColor.canvas.ignoresSafeArea())
        .alert("Rename fix plan", isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } })
        ) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let renaming { sky.rename(renaming.id, to: renameText) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Reset your edits?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Reset to what the scan found", role: .destructive) { sky.resetCraft() }
            Button("Keep my edits", role: .cancel) {}
        } message: {
            Text("Removed and added flags, links, fix plans and done marks are cleared.")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            Text("\(roomName) · \(sky.stage.title)")
                .tremorType(.overline)
                .foregroundStyle(TremorColor.inkTertiary)
            Text("Flags to check")
                .tremorType(.displayM)
                .foregroundStyle(TremorColor.ink)
                .accessibilityAddTraits(.isHeader)
            TremorBanner(
                "Flags to check, not a safety guarantee.",
                message: "proof flags what its geometry and its object list can see. It cannot tell whether furniture is anchored or a cabinet is latched, and small things like outlets and cords may be missing.",
                kind: .highlight)
        }
    }

    private var progress: some View {
        let total = sky.analysis.flags.count
        return TremorProgressBar(
            value: total == 0 ? 0 : Double(sky.doneCount) / Double(total),
            label: sky.progressText)
    }

    // MARK: Fix plans

    private var plans: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            TremorSectionHeader("Fix plans", subtitle: "Constellations you have named")

            if sky.constellations.isEmpty {
                Text("None yet. Keep a suggestion below, or show a climbing path in the room and tap “Fix plan”.")
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(sky.constellations) { constellation in
                planCard(constellation)
            }

            let suggestions = sky.suggestions
            if !suggestions.isEmpty {
                Text("Suggested from the climbing paths")
                    .tremorType(.captionEmphasis)
                    .foregroundStyle(TremorColor.inkSecondary)
                    .padding(.top, TremorSpacing.xs)
                ForEach(suggestions) { suggestion in
                    TremorCard(padding: TremorSpacing.md, fill: TremorColor.primarySoft, shadow: nil) {
                        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                            Text(suggestion.name).tremorType(.headline).foregroundStyle(TremorColor.ink)
                            starNames(suggestion.starIDs)
                            TremorButton("Keep as a fix plan", variant: .primary, size: .small,
                                         leadingIcon: "plus", fillsWidth: false) {
                                sky.keep(suggestion)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func planCard(_ c: Constellation) -> some View {
        let expanded = expandedPlans.contains(c.id)
        return TremorCard(padding: TremorSpacing.md) {
            VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                HStack(alignment: .top) {
                    Button {
                        sky.toggleStatus(c.id)
                    } label: {
                        Image(systemName: c.status == .done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 24))
                            .foregroundStyle(c.status == .done ? TremorColor.success : TremorColor.strokeStrong)
                    }
                    .accessibilityLabel(c.status == .done ? "Mark open" : "Mark done")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name)
                            .tremorType(.headline)
                            .foregroundStyle(TremorColor.ink)
                            .strikethrough(c.status == .done)
                        Text(c.origin == .engine ? "From a climbing path proof found" : "Grouped by you")
                            .tremorType(.caption).foregroundStyle(TremorColor.inkTertiary)
                    }
                    Spacer()
                    Menu {
                        Button("Rename") { renameText = c.name; renaming = c }
                        Button("Show in the room") {
                            if let chain = sky.analysis.chains.first(where: { c.starIDs.contains($0.hazardID) && c.starIDs.contains($0.nodeIDs[0]) }) {
                                sky.setMode(.paths); sky.light(chain.id)
                            } else {
                                sky.selectedID = c.starIDs.first
                            }
                            onShowInRoom()
                        }
                        Button("Delete", role: .destructive) { sky.deleteConstellation(c.id) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(TremorColor.inkSecondary)
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("More for \(c.name)")
                }
                starNames(c.starIDs)
                Text(c.fixPlan)
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkSecondary)
                    .lineLimit(expanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                Button(expanded ? "Show less" : "Read the plan") {
                    if expanded { expandedPlans.remove(c.id) } else { expandedPlans.insert(c.id) }
                }
                .tremorType(.captionEmphasis)
                .foregroundStyle(TremorColor.primary)
                Text("Drafted from the measured data. Check it against the room.")
                    .tremorType(.caption)
                    .foregroundStyle(TremorColor.inkTertiary)
            }
        }
    }

    private func starNames(_ ids: [String]) -> some View {
        FlowLayout(spacing: TremorSpacing.xxs) {
            ForEach(ids, id: \.self) { id in
                let object = sky.analysis.object(id)
                HStack(spacing: 3) {
                    Circle()
                        .fill(object?.role.isHazard == true ? TremorColor.accent : TremorColor.primarySoft)
                        .overlay(Circle().stroke(TremorColor.ink.opacity(0.4), lineWidth: 0.5))
                        .frame(width: 7, height: 7)
                    Text(object?.label ?? "Removed flag").tremorType(.caption)
                }
                .foregroundStyle(TremorColor.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(TremorColor.surfaceSunken))
            }
        }
    }

    // MARK: Chains

    private var chains: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.sm) {
            TremorSectionHeader("Climbing paths",
                                subtitle: "Routes from the floor that a single photo can't show")
            ForEach(sky.analysis.chains) { chain in
                TremorCard.tappable(
                    padding: TremorSpacing.md,
                    accessibilityHint: "Shows this path in the room"
                ) {
                    sky.setMode(.paths); sky.light(chain.id)
                    sky.selectedID = nil
                    onShowInRoom()
                } content: {
                    VStack(alignment: .leading, spacing: TremorSpacing.xs) {
                        HStack {
                            Text(sky.sentence(for: chain))
                                .tremorType(.headline).foregroundStyle(TremorColor.ink)
                            Spacer()
                            Image(systemName: "figure.climbing").foregroundStyle(TremorColor.primary)
                        }
                        ChainSteps(chain: chain, analysis: sky.analysis)
                    }
                }
            }
        }
    }

    // MARK: Flags

    private var flagSections: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.lg) {
            TremorSectionHeader("All flags", subtitle: "Tap one to see it in the room")
            ForEach(HazardKind.allCases) { kind in
                let flags = sky.analysis.flags.filter { $0.kind == kind }
                if !flags.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: TremorSpacing.xs) {
                            Image(systemName: kind.symbol).foregroundStyle(TremorColor.primary)
                            Text(kind.title).tremorType(.headline).foregroundStyle(TremorColor.ink)
                            Spacer()
                            Text("\(flags.filter(sky.isDone).count)/\(flags.count)")
                                .tremorType(.caption, numeric: true)
                                .foregroundStyle(TremorColor.inkTertiary)
                        }
                        .padding(.bottom, TremorSpacing.xs)
                        Text("Consider: " + kind.fixTypes.joined(separator: " · "))
                            .tremorType(.caption)
                            .foregroundStyle(TremorColor.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, TremorSpacing.xs)
                        ForEach(flags) { flag in
                            flagRow(flag)
                            TremorRowDivider()
                        }
                    }
                }
            }
        }
    }

    private func flagRow(_ flag: Flag) -> some View {
        let done = sky.isDone(flag)
        return HStack(alignment: .top, spacing: TremorSpacing.sm) {
            Button {
                sky.toggleDone(flag)
            } label: {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundStyle(done ? TremorColor.success : TremorColor.strokeStrong)
            }
            .accessibilityLabel(done ? "Done" : "Open")
            .accessibilityHint("Toggles whether this flag is done")

            Button {
                sky.selectedID = flag.objectID
                onShowInRoom()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: TremorSpacing.xxs) {
                        Text(flag.label)
                            .tremorType(.subheadline)
                            .foregroundStyle(TremorColor.ink)
                            .strikethrough(done)
                        if flag.isHeuristic { Badge("Heuristic") }
                        if case .viaChain = flag.reachability { Badge("By climbing", systemImage: "figure.climbing") }
                        if flag.reachability == .notReached { Badge("Out of reach") }
                    }
                    Text(flag.detail)
                        .tremorType(.caption)
                        .foregroundStyle(TremorColor.inkTertiary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows it in the room")
        }
        .padding(.vertical, TremorSpacing.xs)
    }

    // MARK: Removed

    private var removed: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            TremorSectionHeader("Removed by you")
            ForEach(sky.removedObjects) { object in
                HStack {
                    Text(object.label).tremorType(.subheadline).foregroundStyle(TremorColor.ink)
                    Spacer()
                    TremorButton("Put back", variant: .tertiary, size: .small, fillsWidth: false) {
                        sky.restore(object.id)
                    }
                }
            }
        }
    }

    // MARK: Honesty

    private var limits: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            TremorSectionHeader("What proof can't see")
            ForEach(Self.limitations, id: \.self) { line in
                Label(line, systemImage: "eye.slash")
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    static let limitations = [
        "Whether furniture is anchored to the wall, or a cabinet is latched.",
        "Small things — outlets, cords, coins, magnets. A scan finds them poorly, so most are missing.",
        "Drawers or doors pulled open into steps. Surfaces are taken as the scan saw them.",
        "Anything that moved after the walkthrough was filmed.",
        "Climbing paths are geometry with placeholder thresholds, not a prediction of what a child will do."
    ]

    private var parameters: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            TremorSectionHeader("Parameters", subtitle: "\(sky.stage.title) stage")
            ForEach(sky.analysis.parameters.all) { p in
                HStack {
                    Text(p.title).tremorType(.footnote).foregroundStyle(TremorColor.ink)
                    Spacer()
                    Text(p.formatted).tremorType(.footnote, numeric: true).foregroundStyle(TremorColor.inkSecondary)
                    if p.provenance.isAssumption { Badge("Assumption") }
                }
                .padding(.vertical, 2)
            }
            Text("Every number here is a placeholder until it has a source in docs/HAZARDS.md.")
                .tremorType(.caption)
                .foregroundStyle(TremorColor.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footerActions: some View {
        VStack(spacing: TremorSpacing.sm) {
            ShareLink(
                item: FixPlanWriter.markdown(roomName: roomName, analysis: sky.analysis, state: CraftStateSnapshot.of(sky)),
                subject: Text("\(roomName) — flags to check"),
                preview: SharePreview("\(roomName) — flags to check")
            ) {
                Label("Export checklist", systemImage: "square.and.arrow.up")
                    .tremorType(.bodyEmphasis)
                    .foregroundStyle(TremorColor.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: TremorSize.buttonMedium)
                    .background(Capsule().fill(TremorColor.primarySoft))
            }
            TremorButton("Reset my edits", variant: .tertiary, size: .medium) { confirmsReset = true }
        }
    }
}

/// The craft state as the export needs it, read through the model's public surface.
enum CraftStateSnapshot {
    @MainActor
    static func of(_ sky: ConstellationModel) -> CraftState {
        var state = CraftState()
        state.stage = sky.stage
        state.constellations = sky.constellations
        state.doneFlagIDs = Set(sky.analysis.flags.filter(sky.isDone).map(\.id))
        return state
    }
}
