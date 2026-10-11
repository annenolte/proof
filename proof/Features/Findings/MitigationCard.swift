//
//  MitigationCard.swift
//  Tremor — S-16 "How to fix it"
//
//  One card per recommended fix: what to do, what to buy, how long it takes,
//  what standard says so, and — the part that makes anyone actually buy the
//  straps — what this object scores once it is done.
//

import SwiftUI

// MARK: - Mitigation card

struct MitigationCard: View {

    let mitigation: Mitigation
    /// 1-based, so the cards read as an order of work rather than a menu.
    let index: Int
    let currentScore: Double?
    let projectedScore: Double?
    /// True while the engine is still computing the projection.
    let isProjecting: Bool
    /// The sized anchorage demand, shown only under a fix that puts a fastener
    /// into structure.
    let anchorage: AnchorageRequirement?

    @State private var showsSteps = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var projectedBand: RiskBand? { projectedScore.map(RiskBand.init(score:)) }

    private var improvement: Double? {
        guard let currentScore, let projectedScore else { return nil }
        return max(currentScore - projectedScore, 0)
    }

    var body: some View {
        TremorCard(padding: TremorSpacing.md) {
            VStack(alignment: .leading, spacing: TremorSpacing.md) {
                heading
                meta
                Text(mitigation.summary)
                    .tremorType(.callout)
                    .foregroundStyle(TremorColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                stepsDisclosure

                if !mitigation.hardware.isEmpty {
                    hardware
                }

                if let anchorage, mitigation.effect.setsAnchored {
                    anchorageBlock(anchorage)
                }

                if let warning = mitigation.warning {
                    TremorBanner(warning, kind: .warning)
                }

                outcome
            }
        }
    }

    // MARK: Pieces

    private var heading: some View {
        HStack(alignment: .top, spacing: TremorSpacing.sm) {
            Text("\(index)")
                .tremorType(.subheadline, numeric: true)
                .foregroundStyle(TremorColor.onPrimary)
                .frame(width: TremorSpacing.xl, height: TremorSpacing.xl)
                .background(TremorColor.primary, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: TremorSpacing.xxs) {
                Text(mitigation.title)
                    .tremorType(.title3)
                    .foregroundStyle(TremorColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(mitigation.femaReference)
                    .tremorType(.caption)
                    .foregroundStyle(TremorColor.inkTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: mitigation.symbolName)
                .font(TremorFont.title3)
                .foregroundStyle(TremorColor.primary)
                .accessibilityHidden(true)
        }
    }

    private var meta: some View {
        // Wrapping row: at accessibility sizes three chips will not sit side by
        // side, and truncating "10 min · $12 · basic tools" loses the cost.
        FindingsWrap(spacing: TremorSpacing.xs) {
            FindingsTag(FindingsFormat.duration(mitigation.minutes), systemImage: "clock")
            FindingsTag(FindingsFormat.money(mitigation.estimatedCostUSD), systemImage: "tag")
            FindingsTag(mitigation.difficulty.displayName, systemImage: mitigation.difficulty.symbolName)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(FindingsFormat.duration(mitigation.minutes)), "
            + "\(FindingsFormat.money(mitigation.estimatedCostUSD)), "
            + mitigation.difficulty.displayName.lowercased())
    }

    @ViewBuilder
    private var stepsDisclosure: some View {
        if !mitigation.steps.isEmpty {
            VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                Button {
                    withAnimation(TremorMotion.resolved(TremorMotion.change, reduceMotion: reduceMotion)) {
                        showsSteps.toggle()
                    }
                } label: {
                    HStack(spacing: TremorSpacing.xs) {
                        Text(showsSteps ? "Hide the steps" : "How to do it")
                            .tremorType(.subheadline)
                        Image(systemName: "chevron.down")
                            .font(TremorFont.caption)
                            .rotationEffect(.degrees(showsSteps ? 180 : 0))
                    }
                    .foregroundStyle(TremorColor.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(showsSteps ? "Hides the instructions" : "Shows the instructions")

                if showsSteps {
                    VStack(alignment: .leading, spacing: TremorSpacing.sm) {
                        ForEach(Array(mitigation.steps.enumerated()), id: \.offset) { pair in
                            HStack(alignment: .top, spacing: TremorSpacing.sm) {
                                Text("\(pair.offset + 1).")
                                    .tremorType(.footnote, numeric: true)
                                    .foregroundStyle(TremorColor.inkTertiary)
                                    .frame(minWidth: TremorSpacing.lg, alignment: .trailing)
                                Text(pair.element)
                                    .tremorType(.callout)
                                    .foregroundStyle(TremorColor.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private var hardware: some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            FindingsSectionLabel("What to buy")
            ForEach(mitigation.hardware) { item in
                HStack(alignment: .top, spacing: TremorSpacing.sm) {
                    Image(systemName: "circle.fill")
                        .font(TremorFont.caption)
                        .foregroundStyle(TremorColor.stroke)
                        .padding(.top, TremorSpacing.xxs)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                        Text("\(item.quantity)× \(item.name)")
                            .tremorType(.subheadline)
                            .foregroundStyle(TremorColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(item.specification)
                            .tremorType(.footnote)
                            .foregroundStyle(TremorColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(ReportFormat.money(item.totalCostUSD))
                        .tremorType(.footnote, numeric: true)
                        .foregroundStyle(TremorColor.inkTertiary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(TremorSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TremorColor.surfaceSunken,
                    in: RoundedRectangle(cornerRadius: TremorRadius.sm, style: .continuous))
    }

    private func anchorageBlock(_ requirement: AnchorageRequirement) -> some View {
        VStack(alignment: .leading, spacing: TremorSpacing.xs) {
            FindingsSectionLabel("How hard it has to pull")
            Text(requirement.summary)
                .tremorType(.footnote)
                .foregroundStyle(TremorColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let fixing = requirement.recommendedFixing {
                Text("Use \(fixing.displayName.lowercased()).")
                    .tremorType(.subheadline)
                    .foregroundStyle(TremorColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let warning = requirement.plasterboardWarning {
                Text(warning)
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(requirement.derivation)
                .tremorType(.caption)
                .foregroundStyle(TremorColor.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(TremorSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TremorColor.primarySoft,
                    in: RoundedRectangle(cornerRadius: TremorRadius.sm, style: .continuous))
    }

    @ViewBuilder
    private var outcome: some View {
        if let projectedScore, let projectedBand, let improvement, improvement >= 1 {
            HStack(spacing: TremorSpacing.sm) {
                Image(systemName: "arrow.down.right.circle.fill")
                    .font(TremorFont.title3)
                    .foregroundStyle(TremorColor.success)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: TremorSpacing.hair) {
                    Text("After this fix: \(projectedBand.displayName) (\(FindingsFormat.score(projectedScore))/100)")
                        .tremorType(.bodyEmphasis, numeric: true)
                        .foregroundStyle(TremorColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(Int(improvement.rounded())) points better, worked out by shaking the room again with this fix in place.")
                        .tremorType(.caption)
                        .foregroundStyle(TremorColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(TremorSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TremorColor.surfaceSunken,
                        in: RoundedRectangle(cornerRadius: TremorRadius.sm, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "After this fix: \(projectedBand.spokenScore(projectedScore)). "
                + "\(Int(improvement.rounded())) points better.")
        } else if isProjecting, mitigation.effect.isModelled {
            HStack(spacing: TremorSpacing.sm) {
                ProgressView().controlSize(.small).tint(TremorColor.primary)
                Text("Working out what this fix is worth…")
                    .tremorType(.footnote)
                    .foregroundStyle(TremorColor.inkTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // Honest: a cabinet latch is worth doing and changes no number a
            // rigid-block solution can produce. Saying "8% safer" here would be
            // an invention.
            Text(unmodelledNote)
                .tremorType(.caption)
                .foregroundStyle(TremorColor.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var unmodelledNote: String {
        if mitigation.effect.isModelled {
            return "This one does not change the score much on its own — it is worth doing alongside the fix above."
        }
        return "This protects what is inside rather than stopping the piece moving, so it does not change the score. Worth doing anyway."
    }
}

// MARK: - Wrapping row

/// A row that wraps to the next line instead of squeezing or truncating.
///
/// Used for chip rows, which is the one place in these screens where three short
/// labels must all stay readable at `.accessibility3`.
struct FindingsWrap: Layout {

    var spacing: CGFloat = TremorSpacing.xs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let rows = layout(subviews: subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let rows = layout(subviews: subviews, width: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var height: CGFloat = 0
    }

    private func layout(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        var x: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.indices.isEmpty, x + size.width > width {
                rows.append(current)
                current = Row()
                x = 0
            }
            current.indices.append(index)
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: - Previews

#Preview("Mitigation card") {
    ScrollView {
        VStack(spacing: TremorSpacing.md) {
            MitigationCard(
                mitigation: MitigationLibrary.anchorTallFurniture,
                index: 1,
                currentScore: 88,
                projectedScore: 12,
                isProjecting: false,
                anchorage: AnchorageCalculator.worked140kgBookcaseOnSecondFloor)

            MitigationCard(
                mitigation: MitigationLibrary.doorLatches,
                index: 2,
                currentScore: 88,
                projectedScore: nil,
                isProjecting: false,
                anchorage: nil)

            MitigationCard(
                mitigation: MitigationLibrary.loadBottomFirst,
                index: 3,
                currentScore: 88,
                projectedScore: nil,
                isProjecting: true,
                anchorage: nil)
        }
        .padding(.vertical, TremorSpacing.xl)
    }
    .tremorScreen()
}
